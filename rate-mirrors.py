#!/usr/bin/env python3
# Рейтинг зеркал Arch для выбора в mirrors.txt.
#
#     python3 rate-mirrors.py [ограничение числа кандидатов]
#
# Откуда кандидаты: официальный статус archlinux.org/mirrors/status/json —
# все зеркала с полями score/country/completion. Фильтр по нашей политике:
# только https (http убран 2026-10-14: редиректы отнимают время),
# активные, базы свежие (completion 1.0).
#
# Три прогона, потому что опыт отбора показал две ошибки:
#   1. разовый замер скорости не ловит «прыгающих» (cdnmirror/truenetwork
#      выбирались по красивому замеру и начали отбивать соединения);
#   2. официальный рейтинг не учитывает наш путь (far.fi — лучший в
#      статусе, из нашей сети не отвечает вообще).
# Поэтому: скрининг доступности с нашей сети → замер скорости на куске
# core.db → у топ-20 ещё два повтора: зеркало, пропустившее хоть один
# раунд, в «лучшие» не идёт.
#
# Скрипт только меряет и печатает: в mirrors.txt добавление — вручную
# и по явному решению (список зеркал закрыт, AGENTS.md).
import json
import statistics
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

STATUS_URL = 'https://archlinux.org/mirrors/status/json/'
UA = 'wdistr-rate-mirrors'
# extra.db (~9 МиБ) как объект замера: core.db крошечный (~130 КиБ) и
# отдаётся целиком быстрее, чем открывается соединение — замер упирается
# в коннект/DNS, все зеркала показывают ~0,0 (опыт 2026-10-15)
PROBE_PATH = 'extra/os/x86_64/extra.db'
CHUNK = 2 * 1024 * 1024                # кусок extra.db для замера скорости
TIMEOUT_SCREEN = 5                     # сек: скрининг доступности
TIMEOUT_FETCH = 30                     # сек: скачивание куска
WORKERS = 12                           # параллелизм: 378 кандидатов иначе час
TOP_STABLE = 20                        # сколько топовых гоняем на стабильность
STABILITY_ROUNDS = 3                   # раундов на зеркало (первый общий)
ROUNDS_PAUSE = 2                       # сек между раундами стабильности


def fetch_candidates(limit):
    """Официальный статус → кандидаты https/completion 1.0 с метаданными."""
    req = urllib.request.Request(STATUS_URL, headers={'User-Agent': UA})
    data = json.load(urllib.request.urlopen(req, timeout=20))
    out = []
    for m in data['urls']:
        if m.get('protocol') != 'https':
            continue
        if not m.get('active') or m.get('completion_pct') != 1.0:
            continue
        out.append({
            'url': m['url'].rstrip('/') + '/',   # шаблон: <url>$repo/os/$arch
            'country': m.get('country') or '?',
            'score': m.get('score'),             # официальный, меньше — лучше
        })
    # Порядок статуса близок к official score — limit полезен для прогона
    # на части списка при отладке
    if limit:
        out = out[:limit]
    return out


def screen(mirror):
    """Скрининг: отвечает ли зеркало с нашей сети (1 байт core.db)."""
    t0 = time.time()
    url = mirror['url'] + PROBE_PATH
    try:
        req = urllib.request.Request(
            url, headers={'Range': 'bytes=0-0', 'User-Agent': UA})
        with urllib.request.urlopen(req, timeout=TIMEOUT_SCREEN) as resp:
            resp.read(1)
        return time.time() - t0, None
    except Exception as exc:
        return None, f'{type(exc).__name__}: {exc}'


def measure(mirror):
    """Замер: кусок extra.db → (МБ/с передачи, ошибка).

    Скорость считается ПОСЛЕ первого байта, иначе в неё упирается
    коннект/DNS: на маленьком файле соединение дороже самой передачи
    (опыт 2026-10-15, см. PROBE_PATH). Коннект/DNS виден в колонке
    «отклик» из скрининга.
    """
    url = mirror['url'] + PROBE_PATH
    try:
        req = urllib.request.Request(
            url,
            headers={'Range': f'bytes=0-{CHUNK - 1}', 'User-Agent': UA})
        t0 = time.time()
        with urllib.request.urlopen(req, timeout=TIMEOUT_FETCH) as resp:
            first = resp.read(1)
            t_first = time.time()
            rest = resp.read(CHUNK - 1)
            t_done = time.time()
        got = len(first) + len(rest)
        transfer = t_done - t_first
        if got <= 1 or transfer <= 0:
            return None, 'нет данных передачи'
        return (got - 1) / transfer / (1024 * 1024), None
    except Exception as exc:
        return None, f'{type(exc).__name__}: {exc}'


def main():
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else None

    print('Загрузка официального статуса зеркал...')
    candidates = fetch_candidates(limit)
    print(f'Кандидатов (https, свежие базы): {len(candidates)}')

    # Фаза 1: скрининг доступности — здесь отсеиваются зеркала,
    # недоступные именно из нашей сети (случай far.fi)
    print(f'Скрининг доступности ({WORKERS} потоков, таймаут {TIMEOUT_SCREEN} с)...')
    dead = []
    survivors = []
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        for mirror, (ttfb, err) in zip(candidates, pool.map(screen, candidates)):
            if err:
                dead.append((mirror, err))
            else:
                mirror['ttfb'] = ttfb
                survivors.append(mirror)
    print(f'Ответили: {len(survivors)}, не ответили: {len(dead)}')

    # Фаза 2: один замер скорости для всех живых
    print(f'Замер скорости (кусок {CHUNK // (1024 * 1024)} МиБ, таймаут {TIMEOUT_FETCH} с)...')
    measured = []
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        for mirror, (speed, err) in zip(survivors, pool.map(measure, survivors)):
            if err:
                dead.append((mirror, err))
            else:
                mirror['rounds'] = [speed]
                measured.append(mirror)
    measured.sort(key=lambda m: -m['rounds'][0])

    # Фаза 3: стабильность топ-N — ещё раунды с паузой; промах раунда =
    # зеркало «прыгает», в лучшие не попадает
    top = measured[:TOP_STABLE]
    print(f'Стабильность: топ-{len(top)}, раунды {STABILITY_ROUNDS}'
          f' с паузой {ROUNDS_PAUSE} с...')
    for rnd in range(2, STABILITY_ROUNDS + 1):
        time.sleep(ROUNDS_PAUSE)
        with ThreadPoolExecutor(max_workers=WORKERS) as pool:
            results = pool.map(measure, top)
        for mirror, (speed, err) in zip(top, results):
            mirror['rounds'].append(speed if not err else None)

    stable = [m for m in top if all(r is not None for r in m['rounds'])]
    flaky = [m for m in top if any(r is None for r in m['rounds'])]
    stable.sort(key=lambda m: -statistics.median(m['rounds']))

    print()
    print(f'ЛУЧШИЕ (стабильные, медиана {STABILITY_ROUNDS} раундов):')
    print(f'{"#":>3} {"МБ/с":>6}  раунды              {"отклик,мс":>10} {"score":>6}  страна            зеркало')
    for n, m in enumerate(stable, 1):
        rounds = ' | '.join(f'{r:.1f}' for r in m['rounds'])
        score = f'{m["score"]:.2f}' if m['score'] is not None else '?'
        print(f'{n:3} {statistics.median(m["rounds"]):6.1f}  {rounds:<19} '
              f'{m["ttfb"] * 1000:10.0f} {score:>6}  {m["country"]:<17} {m["url"]}')

    if flaky:
        print()
        print('ПРЫГАЮТ (пропустили раунд — не рекомендуются):')
        for m in flaky:
            rounds = ' | '.join(f'{r:.1f}' if r else 'ОТКАЗ' for r in m['rounds'])
            print(f'  {rounds}  {m["url"]}')

    if dead:
        print()
        print(f'НЕ ОТВЕТИЛИ ИЗ НАШЕЙ СЕТИ: {len(dead)}')
        reasons = {}
        for _, err in dead:
            key = err.split(':')[0]
            reasons[key] = reasons.get(key, 0) + 1
        print('  причины:', ', '.join(f'{k} ×{v}' for k, v in sorted(reasons.items())))

    print()
    print('Напоминание: добавление в mirrors.txt — вручную по явному решению;')
    print('официальный score справочный (меньше — лучше), решающим считаем')
    print('наши раунды: они меряют путь именно из этой сети.')


if __name__ == '__main__':
    main()
