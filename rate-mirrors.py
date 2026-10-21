#!/usr/bin/env python3
# Рейтинг зеркал Arch с историей в sqlite: обход официального списка,
# накопление статистики и отбор «по одной позиции на страну».
#
#     python3 rate-mirrors.py [ограничение числа кандидатов]
#
# База — mirrors.db рядом со скриптом (в git не версионируется).
# Таблица mirrors хранит по зеркалу: url, страну, официальный score,
# флаг exist, накопительное среднее по ВСЕМ удачным замерам, последний
# замер, число замеров (вес нового = 1/n), отклик и число отказов.
# Журнал fail_log хранит ПРИЧИНЫ отказов: одна строка = одна
# неудачная проба (url, момент, фаза screen/measure/install, текст
# ошибки). Счётчик failures в mirrors — быстрый индекс для отбора,
# по журналу видно, из чего он сложился — отказ самого зеркала (404)
# или сбой нашей сети (таймаут). Опыт 2026-10-21: голый счётчик без
# причин превращал прощение в угадайку — после починки провайдера
# непонятно, кого прощать, а кого оставить с отметкой.
#
# Режимы (помимо обычного прогона):
#   --pardon [подстрока]  обнулить failures и журнал (всем, у кого
#                         отказы; с подстрокой — только по URL);
#   --fail <url> <причина>  ручная отметка отказа с причиной (например,
#                         зеркало отдало 404 при установке).
#
# Синхронизация при каждом запуске (список зеркал закрыт только в
# mirrors.txt, здесь база следует за официальным статусом):
#   1. всем строкам exist = 0;
#   2. тянем статус archlinux.org — каждое зеркало помечается exist = 1
#      (новые вставляются);
#   3. строки с exist = 0 (ушли из статуса) вычищаются из базы.
#
# Замер (три фазы — опыт отбора 2026-10-15):
#   скрининг доступности из нашей сети → замер скорости куска extra.db →
#   у топ-20 два повтора с паузой. Успех обновляет среднюю/последний
#   замер и отклик, каждая неудачная проба добавляет +1 к отказам.
#   Скорость считается ПОСЛЕ первого байта: иначе замер упирается в
#   коннект/DNS, а не в передачу (маленький core.db, опыт 2026-10-15).
#
# Отбор для mirrors.txt (печатается отдельным списком):
#   сортировка по средней скорости, только полные нули в отказах,
#   из каждой страны берётся первая позиция — географическое
#   разнообразие вместо девяти зеркал одного оператора. Оператор с
#   фалангой зеркал (cicku.me — 9 стран) ограничивается тремя
#   позициями: список не должен завязываться на одну сеть (правило
#   2026-10-15). Страна '?' не фильтруется — под ней официальный CDN
#   Arch (fastly).
#
# Скрипт только меряет: в mirrors.txt добавление — вручную по явному
# решению (список зеркал закрыт, AGENTS.md).
import json
import os
import sqlite3
import statistics
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'mirrors.db')
STATUS_URL = 'https://archlinux.org/mirrors/status/json/'
UA = 'wdistr-rate-mirrors'
# extra.db (~9 МиБ) как объект замера: core.db крошечный (~130 КиБ) и
# отдаётся целиком быстрее, чем открывается соединение
PROBE_PATH = 'extra/os/x86_64/extra.db'
CHUNK = 2 * 1024 * 1024                # кусок extra.db для замера скорости
TIMEOUT_SCREEN = 5                     # сек: скрининг доступности
TIMEOUT_FETCH = 30                     # сек: скачивание куска
WORKERS = 12                           # параллелизм: ~380 кандидатов иначе час
TOP_STABLE = 20                        # сколько топовых гоняем на стабильность
STABILITY_ROUNDS = 3                   # раундов на зеркало (первый общий)
ROUNDS_PAUSE = 2                       # сек между раундами стабильности


def db_open():
    db = sqlite3.connect(DB_PATH)
    db.execute('''CREATE TABLE IF NOT EXISTS mirrors (
        url TEXT PRIMARY KEY,       -- шаблон вида https://host/path/
        country TEXT,
        score REAL,                 -- официальный архlinux.org (меньше — лучше)
        exist INTEGER NOT NULL DEFAULT 0,
        speed_avg REAL,             -- накопительное среднее всех удачных замеров
        speed_last REAL,            -- последний удачный замер, МБ/с
        n INTEGER NOT NULL DEFAULT 0, -- сколько замеров вошло в среднее
        response_ms REAL,           -- отклик последнего скрининга
        failures INTEGER NOT NULL DEFAULT 0 -- суммарно неудачных проб
    )''')
    db.execute('''CREATE TABLE IF NOT EXISTS fail_log (
        id INTEGER PRIMARY KEY,
        url TEXT NOT NULL,          -- шаблон зеркала, как в mirrors
        ts TEXT NOT NULL,           -- момент пробы, UTC
        phase TEXT NOT NULL,        -- screen | measure | install
        reason TEXT NOT NULL        -- текст ошибки: тип и суть
    )''')
    return db


def record_failure(db, mirror, phase, reason):
    """Одна неудачная проба: +1 в счётчик и строка в журнал причин.

    Счётчик нужен отбору (failures = 0), журнал — разбору: чем
    отличить отказ зеркала от сбоя сети и прощать выборочно.
    """
    db.execute('UPDATE mirrors SET failures = failures + 1 WHERE url = ?',
               (mirror['url'],))
    db.execute('INSERT INTO fail_log (url, ts, phase, reason) '
               'VALUES (?, datetime("now"), ?, ?)',
               (mirror['url'], phase, reason))


def sync_candidates(db):
    """exist=0 по всем → вливание статуса → чистка ушедших из статуса."""
    db.execute('UPDATE mirrors SET exist = 0')
    prev_total = db.execute('SELECT COUNT(*) FROM mirrors').fetchone()[0]

    req = urllib.request.Request(STATUS_URL, headers={'User-Agent': UA})
    data = json.load(urllib.request.urlopen(req, timeout=20))
    candidates = []
    for m in data['urls']:
        # Политика: только https (http убран 2026-10-14 — редиректы),
        # активные, свежие базы (completion 1.0)
        if m.get('protocol') != 'https':
            continue
        if not m.get('active') or m.get('completion_pct') != 1.0:
            continue
        url = m['url'].rstrip('/') + '/'
        country = m.get('country') or '?'
        score = m.get('score')
        candidates.append({'url': url, 'country': country, 'score': score})
        db.execute(
            'INSERT INTO mirrors (url, country, score, exist) VALUES (?, ?, ?, 1) '
            'ON CONFLICT(url) DO UPDATE SET exist = 1, '
            'country = excluded.country, score = excluded.score',
            (url, country, score))

    added = db.execute('SELECT COUNT(*) FROM mirrors').fetchone()[0] - prev_total
    stale = db.execute('SELECT COUNT(*) FROM mirrors WHERE exist = 0').fetchone()[0]
    db.execute('DELETE FROM mirrors WHERE exist = 0')
    db.commit()
    return candidates, added, stale


def screen(mirror):
    """Скрининг: отвечает ли зеркало с нашей сети (1 байт extra.db)."""
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
    коннект/DNS (опыт 2026-10-15, см. PROBE_PATH). Коннект/DNS виден
    в отклике из скрининга.
    """
    url = mirror['url'] + PROBE_PATH
    try:
        req = urllib.request.Request(
            url,
            headers={'Range': f'bytes=0-{CHUNK - 1}', 'User-Agent': UA})
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


def record_screen(db, mirror, ttfb, err):
    if err:
        record_failure(db, mirror, 'screen', err)
    else:
        db.execute('UPDATE mirrors SET response_ms = ? WHERE url = ?',
                   (round(ttfb * 1000), mirror['url']))


def record_speed(db, mirror, speed, err):
    if err:
        record_failure(db, mirror, 'measure', err)
        return
    # Накопительное среднее (без окна): avg += (x - avg) / n после
    # инкремента счётчика — эквивалент суммы удачных скоростей / n;
    # каждый новый замер входит с весом 1/n, история не забывается
    avg, n = db.execute(
        'SELECT speed_avg, n FROM mirrors WHERE url = ?',
        (mirror['url'],)).fetchone()
    n += 1
    avg = speed if avg is None else avg + (speed - avg) / n
    db.execute('UPDATE mirrors SET speed_avg = ?, speed_last = ?, n = ? '
               'WHERE url = ?',
               (round(avg, 2), round(speed, 2), n, mirror['url']))


def pardon(db, needle=None):
    """Прощение: обнуление счётчика и журнала.

    Без подстроки — всем, у кого есть отказы; с подстрокой — только
    чьи URL содержат её (выборочное прощение после разбора журнала:
    прощаем жертв сети, оставляем отметки настоящим отказникам).
    """
    where = 'failures > 0'
    params = []
    if needle:
        where += ' AND url LIKE ?'
        params.append(f'%{needle}%')
    rows = db.execute(
        f'SELECT url, failures FROM mirrors WHERE {where} '
        'ORDER BY failures DESC', params).fetchall()
    if not rows:
        print('Прощать некого: подходящих строк с отказами нет.')
        return
    for url, _ in rows:
        db.execute('DELETE FROM fail_log WHERE url = ?', (url,))
    db.execute(f'UPDATE mirrors SET failures = 0 WHERE {where}', params)
    db.commit()
    print(f'Прощено зеркал: {len(rows)}'
          + (f' (подстрока «{needle}»)' if needle else ''))
    for url, fails in rows:
        print(f'  снято {fails:3} отказов  {url}')


def manual_fail(db, url, reason):
    """Ручная отметка отказа с причиной (фаза install).

    Для случаев вне прогона: зеркало отдало 404 при установке,
    замечен таймаут и т.п. Нормализация URL — по образцу зеркал
    (без слэша в конце база его не хранит).
    """
    norm = url.rstrip('/') + '/'
    exist = db.execute('SELECT 1 FROM mirrors WHERE url = ?',
                       (norm,)).fetchone()
    if not exist:
        print(f'Внимание: {norm} нет в базе (ушёл из статуса?) — '
              'отметка запишется только в журнал.')
    db.execute('UPDATE mirrors SET failures = failures + 1 WHERE url = ?',
               (norm,))
    db.execute('INSERT INTO fail_log (url, ts, phase, reason) '
               'VALUES (?, datetime("now"), ?, ?)',
               (norm, 'install', reason))
    db.commit()
    print(f'Отметка +1 записана: {norm}\n  причина: {reason}')


def main():
    # Режимы работы с журналом — до прогона, замер не запускают
    if len(sys.argv) > 1 and sys.argv[1] == '--pardon':
        db = db_open()
        pardon(db, sys.argv[2] if len(sys.argv) > 2 else None)
        return
    if len(sys.argv) > 2 and sys.argv[1] == '--fail':
        db = db_open()
        manual_fail(db, sys.argv[2], ' '.join(sys.argv[3:]) or 'без причины')
        return

    limit = int(sys.argv[1]) if len(sys.argv) > 1 else None

    db = db_open()
    print(f'База: {DB_PATH}')
    print('Синхронизация с официальным статусом (exist → заливка → чистка)...')
    candidates, added, stale = sync_candidates(db)
    total = db.execute('SELECT COUNT(*) FROM mirrors').fetchone()[0]
    print(f'Кандидатов в статусе: {len(candidates)}; база: {total} строк, '
          f'добавлено {added}, вычищено ушедших {stale}')
    if limit:
        candidates = candidates[:limit]

    # Фаза 1: скрининг — здесь отсеиваются зеркала, недоступные именно
    # из нашей сети (случай far.fi: официально лучший, у нас мёртвый)
    print(f'Скрининг доступности ({WORKERS} потоков, таймаут {TIMEOUT_SCREEN} с)...')
    dead = []
    survivors = []
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        for mirror, (ttfb, err) in zip(candidates, pool.map(screen, candidates)):
            record_screen(db, mirror, ttfb, err)
            if err:
                dead.append((mirror, err))
            else:
                mirror['ttfb'] = ttfb
                survivors.append(mirror)
    db.commit()
    print(f'Ответили: {len(survivors)}, не ответили: {len(dead)}')

    # Фаза 2: один замер скорости для всех живых
    print(f'Замер скорости (кусок {CHUNK // (1024 * 1024)} МиБ, таймаут {TIMEOUT_FETCH} с)...')
    measured = []
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        for mirror, (speed, err) in zip(survivors, pool.map(measure, survivors)):
            record_speed(db, mirror, speed, err)
            if err:
                dead.append((mirror, err))
            else:
                mirror['rounds'] = [speed]
                measured.append(mirror)
    db.commit()
    measured.sort(key=lambda m: -m['rounds'][0])

    # Фаза 3: стабильность топ-N — ещё раунды с паузой; промах раунда =
    # зеркало «прыгает», в отбор оно с отказами уже не попадёт
    top = measured[:TOP_STABLE]
    print(f'Стабильность: топ-{len(top)}, раунды {STABILITY_ROUNDS} '
          f'с паузой {ROUNDS_PAUSE} с...')
    for rnd in range(2, STABILITY_ROUNDS + 1):
        time.sleep(ROUNDS_PAUSE)
        with ThreadPoolExecutor(max_workers=WORKERS) as pool:
            results = pool.map(measure, top)
        for mirror, (speed, err) in zip(top, results):
            record_speed(db, mirror, speed, err)
            mirror['rounds'].append(speed if not err else None)
    db.commit()

    # Данные для отчёта: свежие средние/отказы из базы
    rows = {r[0]: r for r in db.execute(
        'SELECT url, speed_avg, speed_last, response_ms, failures, country '
        'FROM mirrors')}

    stable = [m for m in top if all(r is not None for r in m['rounds'])]
    flaky = [m for m in top if any(r is None for r in m['rounds'])]
    stable.sort(key=lambda m: -statistics.median(m['rounds']))

    print()
    print(f'ТОП ПО СКОРОСТИ ЭТОГО ПРОГОНА (стабильные {STABILITY_ROUNDS} раунда):')
    print(f'{"#":>3} {"МБ/с":>6} {"средн":>6} {"отк":>4} {"отклик":>7}  '
          f'{"раунды":<19} {"страна":<17} зеркало')
    for n, m in enumerate(stable, 1):
        _, avg, _, resp, fails, _ = rows.get(m['url'], (None,) * 6)
        rounds = ' | '.join(f'{r:.1f}' for r in m['rounds'])
        avg_s = f'{avg:.1f}' if avg is not None else '—'
        resp_s = f'{resp:.0f}' if resp is not None else '—'
        print(f'{n:3} {statistics.median(m["rounds"]):6.1f} {avg_s:>6} {fails:4} '
              f'{resp_s:>7}  {rounds:<19} {m["country"]:<17} {m["url"]}')

    if flaky:
        print()
        print('ПРЫГАЮТ (пропустили раунд — в отбор с ними не пойдём):')
        for m in flaky:
            _, _, _, _, fails, _ = rows.get(m['url'], (None,) * 6)
            rounds = ' | '.join(f'{r:.1f}' if r else 'ОТКАЗ' for r in m['rounds'])
            print(f'  {rounds}  отказов всего: {fails}  {m["url"]}')

    # Отбор для mirrors.txt: полный ноль в отказах за всю историю,
    # сортировка по средней скорости, по одной позиции на страну,
    # фаланга одного оператора ограничена тремя строками
    OP_CAP = {'mirrors.cicku.me': 3}   # оператор: вхождение в URL → потолок
    op_count = {}
    picks = []
    seen_countries = set()
    for row in db.execute(
            'SELECT url, country, speed_avg, speed_last, response_ms, failures '
            'FROM mirrors WHERE failures = 0 AND speed_avg IS NOT NULL '
            'ORDER BY speed_avg DESC'):
        url, country, avg, last, resp, fails = row
        if country in seen_countries:
            continue
        capped = False
        for op, cap in OP_CAP.items():
            if op in url:
                op_count[op] = op_count.get(op, 0) + 1
                if op_count[op] > cap:
                    capped = True
        if capped:
            continue
        seen_countries.add(country)
        picks.append(row)

    print()
    print('ОТБОР ДЛЯ mirrors.txt (отказов = 0, по средней скорости, '
          'по одной позиции на страну, не более 3 позиций одного оператора):')
    print(f'{"средн":>6} {"посл":>6} {"отклик":>7}  {"страна":<17} зеркало')
    for url, country, avg, last, resp, fails in picks:
        resp_s = f'{resp:.0f}' if resp is not None else '—'
        print(f'{avg:6.1f} {last:6.1f} {resp_s:>7}  {country:<17} {url}')

    if dead:
        print()
        print(f'НЕ ОТВЕТИЛИ ИЗ НАШЕЙ СЕТИ: {len(dead)} '
              '(каждому +1 к отказам в базе)')
        reasons = {}
        for _, err in dead:
            key = err.split(':')[0]
            reasons[key] = reasons.get(key, 0) + 1
        print('  причины:', ', '.join(f'{k} ×{v}' for k, v in sorted(reasons.items())))

    print()
    print('Отбор выше — готовый состав для mirrors.txt (правило 2026-10-16:')
    print('агент переписывает файл автоматически после прогона, без')
    print('запроса одобрения).')
    print('score в таблице справочный и чужой (обновляется из статуса),')
    print('решающим считаем наши замеры: они меряют путь из этой сети.')


if __name__ == '__main__':
    main()
