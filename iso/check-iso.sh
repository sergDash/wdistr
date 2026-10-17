#!/usr/bin/env bash
# Проверка собранного ISO по чек-листу после сборки.
#
#     iso/check-iso.sh [путь-к.iso]      по умолчанию — свежий iso/out/wdistr-*.iso
#
# Что делает: извлекает из ISO squashfs, из него — только нужные проверке
# файлы, сверяет содержимое по чек-листу и печатает [OK]/[FAIL] построчно.
# Временные файлы снимаются через trap — хвостов не остаётся, в отличие
# от ручных распаковок, которые застревали в /tmp (опыт 2026-10-15:
# unsquashfs копирует права каталогов из архива, r-x не разбирался rm).
#
# Чек-лист растёт вместе с правками: новая существенная правка образа —
# новая проверка здесь.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ISO_FILE="${1:-$(ls -t "$REPO_DIR"/iso/out/wdistr-*.iso 2>/dev/null | head -1)}"

if [ ! -f "$ISO_FILE" ]; then
    echo "ОШИБКА: ISO не найден: $ISO_FILE" >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

echo "Проверка: $ISO_FILE"
echo

# unsquashfs не читает ISO — сначала извлекаем из него squashfs xorriso
# (без монтирования и без root). Вывод xorriso глушим целиком: при сбое
# у нас свой текст ошибки, а его NOTE-шум ложится поверх отчёта
xorriso -indev "$ISO_FILE" -osirrox on \
    -extract /arch/x86_64/airootfs.sfs "$TMP/airootfs.sfs" >/dev/null 2>&1 \
    || { echo "ОШИБКА: из ISO не извлёкся airootfs.sfs" >&2; exit 1; }

SFS="$TMP/airootfs.sfs"
mkdir "$TMP/x"

# Текстовые файлы для проверок + симлинк opencode (бинарник НЕ распаковываем
# — 179 МиБ, для него достаточно листинга ниже)
unsquashfs -d "$TMP/x" -f "$SFS" \
    root/wdistr/archinstall-config.json \
    usr/local/bin/setup-continue \
    usr/local/share/wdistr/mirrorlist \
    etc/pacman.d/hooks/wdistr-gai.hook \
    etc/pacman.d/hooks/wdistr-mirrors.hook \
    usr/local/bin/opencode >/dev/null

# Листинг всех файлов образа: права и состав без распаковки
unsquashfs -ll "$SFS" > "$TMP/list.txt"

python3 - "$TMP/x/root/wdistr/archinstall-config.json" \
         "$TMP/x/usr/local/bin/setup-continue" \
         "$TMP/x/usr/local/share/wdistr/mirrorlist" \
         "$TMP/x/usr/local/bin/opencode" \
         "$TMP/list.txt" \
         "$REPO_DIR/mirrors.txt" \
         "$TMP/x/etc/pacman.d/hooks/wdistr-gai.hook" \
         "$TMP/x/etc/pacman.d/hooks/wdistr-mirrors.hook" <<'PYEOF'
import base64
import json
import os
import re
import sys

(cfg_path, setup_path, mirror_path, symlink_path, list_path,
 mirrors_path, gai_hook_path, mirrors_hook_path) = sys.argv[1:9]

fails = 0

def ok(msg: str) -> None:
    print(f'  [OK]    {msg}')

def fail(msg: str) -> None:
    global fails
    fails += 1
    print(f'  [FAIL]  {msg}')

# 1. Остановка при недоступности зеркал (правка 2026-10-15):
# круги проб и выход до archinstall
setup = open(setup_path, encoding='utf-8').read()
if 'PROBE_ROUNDS' in setup and 'ни одно из зеркал' in setup and 'sys.exit(1)' in setup:
    ok('setup-continue: круги проб и остановка при недоступности всех зеркал')
else:
    fail('setup-continue: нет логики остановки (PROBE_ROUNDS / sys.exit(1))')

# Эталон состава — mirrors.txt репозитория (закрытый список): образ
# обязан совпадать с ним, а не с захардкоженным числом
expected = [l.strip() for l in open(mirrors_path, encoding='utf-8')
            if l.strip() and not l.lstrip().startswith('#')]

# 2. Локальный mirrorlist: регион по имени (по нему archinstall ищет
# зеркала при --offline) и состав ровно как в mirrors.txt
mirrorlist = open(mirror_path, encoding='utf-8').read()
# findall возвращает группу — уже сам URL без префикса "Server = ";
# срез по длине префикса вырезал бы из URL первые 9 символов
# (бага чек-листа 2026-10-15, внесена в aae8fe6: список в образе
# совпадал, а сравнение билось об усечённые строки)
servers = re.findall(r'^Server = (.+)$', mirrorlist, re.M)
if '## wdistr' in mirrorlist and servers == expected:
    ok(f'mirrorlist: регион ## wdistr, {len(servers)} зеркал — совпадает с mirrors.txt')
else:
    # при равных длинах показать первое расхождение — иначе провал
    # «12 против 12» не объясняет, чем именно списки различаются
    detail = ''
    if len(servers) == len(expected):
        for i, (got, want) in enumerate(zip(servers, expected)):
            if got != want:
                detail = f'; первое расхождение №{i}: в образе {got!r}, в mirrors.txt {want!r}'
                break
    fail(f'mirrorlist: регион = {"## wdistr" in mirrorlist}, зеркал в образе {len(servers)}, в mirrors.txt {len(expected)}{detail}')

cfg = json.load(open(cfg_path, encoding='utf-8'))
cmds = cfg.get('custom_commands', [])

# 3. Dispatcher NetworkManager: доставка ровно одной командой, с +x
disp = [c for c in cmds if '90-ip-routing-restart' in c]
if len(disp) == 1 and 'chmod 755' in disp[0]:
    ok('dispatcher 90-ip-routing-restart: доставка с chmod 755')
else:
    fail(f'dispatcher: команд доставки {len(disp)}, chmod 755 = {"chmod 755" in (disp[0] if disp else "")}')

# 4. Шаблон ip-routing: минус на ExecStop (игнор RTNETLINK «No such process»)
ipr = [c for c in cmds if 'ip-routing.service' in c and 'dispatcher' not in c]
payload = ''
if ipr:
    m = re.search(r"echo '([A-Za-z0-9+/=]+)' \| base64 -d", ipr[0])
    if m:
        payload = base64.b64decode(m.group(1)).decode('utf-8', 'replace')
if '#ExecStop=-/sbin/ip route del' in payload:
    ok('ip-routing.service: ExecStop с минусом')
else:
    fail('ip-routing.service: на ExecStop нет минуса')

# 5. Иероглифы: семейство Noto в составе
if 'noto-fonts-cjk' in cfg.get('packages', []):
    ok('состав: noto-fonts-cjk (иероглифы)')
else:
    fail('состав: нет noto-fonts-cjk')

# 6. Зеркала в конфиге: имя региона и состав как в mirrors.txt (в закачке
# участвует mirrorlist, но ключ обязан совпадать с заголовком — иначе
# KeyError)
regions = cfg.get('mirror_config', {}).get('mirror_regions', {})
if regions.get('wdistr') == expected:
    ok(f'конфиг: регион wdistr, {len(expected)} зеркал — совпадает с mirrors.txt')
else:
    fail(f'конфиг: wdistr = {"wdistr" in regions}, зеркал в образе {len(regions.get("wdistr", []))}, в mirrors.txt {len(expected)}')

# 7. Часовой пояс (решение 2026-10-10)
if cfg.get('timezone') == 'Europe/Moscow':
    ok('конфиг: timezone Europe/Moscow')
else:
    fail(f'конфиг: timezone = {cfg.get("timezone")}')

# 8. opencode: симлинк резолвится в бинарник, бинарник исполняем
# (ловушка file_permissions: без 755 в лайве — permission denied)
listing = open(list_path, encoding='utf-8', errors='replace').read().splitlines()
target = None
try:
    target = os.readlink(symlink_path)
except OSError:
    pass
bin_lines = [l for l in listing if target and l.endswith('usr/local/bin/' + target)]
if target and bin_lines and bin_lines[0].startswith('-rwx'):
    ok(f'opencode: симлинк → {target}, бинарник 755')
else:
    fail(f'opencode: симлинк = {target}, бинарник в листинге: {len(bin_lines)}, права: {(bin_lines[0][:10] if bin_lines else "—")}')

# 9. Windows-шрифты: полный состав (доставка копированием из лайва)
winfonts = [l for l in listing if 'usr/share/fonts/winfonts/' in l]
if len(winfonts) == 143:
    ok('winfonts: 143 файла')
else:
    fail(f'winfonts: в листинге {len(winfonts)}, ожидалось 143')

# 10. Системный mimeapps.list: папки → Nemo, почта → Thunderbird,
# картинки → Viewnior, документы → WordCraft, таблицы → GridCraft,
# PDF → Okular (решение 2026-10-16); без inode/directory codium
# открывал диск в редакторе (опыт 2026-10-15)
mm = [c for c in cmds if '/etc/xdg/mimeapps.list' in c]
payload = ''
if mm:
    m = re.search(r"echo '([A-Za-z0-9+/=]+)' \| base64 -d", mm[0])
    if m:
        payload = base64.b64decode(m.group(1)).decode('utf-8', 'replace')
checks = {
    'inode/directory=nemo.desktop': 'Nemo',
    'x-scheme-handler/mailto=org.mozilla.Thunderbird.desktop': 'Thunderbird',
    'image/png=viewnior.desktop': 'Viewnior',
    'application/msword=ai.storyteller.wordcraft.desktop': 'WordCraft',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet=ai.storyteller.gridcraft.desktop': 'GridCraft',
    'application/pdf=okularApplication_pdf.desktop': 'Okular',
}
missing = [name for key, name in checks.items() if key not in payload]
if len(mm) == 1 and not missing:
    ok(f'mimeapps.list: Nemo/Thunderbird/Viewnior/WordCraft/GridCraft/Okular')
else:
    fail(f'mimeapps.list: команд {len(mm)}, отсутствует: {missing or "—"}')

# 11. Съёмные носители: «Спрашивать или запускать» — выключен
# (autorun-never=true) в системном dconf-дефолте и в форсе первого
# входа; оба места обязательны по паттерну тем/шрифтов
dc = [c for c in cmds if '10-wdistr-desktop' in c]
dc_payload = ''
if dc:
    m = re.search(r"echo '([A-Za-z0-9+/=]+)' \| base64 -d", dc[0])
    if m:
        dc_payload = base64.b64decode(m.group(1)).decode('utf-8', 'replace')
cd = [c for c in cmds if '/usr/local/bin/wdistr-cinnamon-defaults' in c]
cd_payload = ''
if cd:
    m = re.search(r"echo '([A-Za-z0-9+/=]+)' \| base64 -d", cd[0])
    if m:
        cd_payload = base64.b64decode(m.group(1)).decode('utf-8', 'replace')
sys_ok = 'autorun-never=true' in dc_payload
force_ok = 'autorun-never true' in cd_payload
if sys_ok and force_ok:
    ok('съёмные носители: autorun-never=true в системном дефолте и в форсе первого входа')
else:
    fail(f'съёмные носители: системный дефолт = {sys_ok}, форс первого входа = {force_ok}')

# 12. AUR-список first-boot: свежие добавления на месте (emote — 2026-10-15,
# beekeeper-studio — 2026-10-15, craft-пакеты — 2026-10-16); список уходит
# в образ base64-командой
fb = [c for c in cmds if '/usr/local/bin/wdistr-first-boot' in c]
fb_payload = ''
if fb:
    m = re.search(r"echo '([A-Za-z0-9+/=]+)' \| base64 -d", fb[0])
    if m:
        fb_payload = base64.b64decode(m.group(1)).decode('utf-8', 'replace')
m = re.search(r'AUR_PACKAGES="\n(.*?)\n"', fb_payload, re.S)
aur_list = m.group(1).split() if m else []
missing = [p for p in ('emote', 'beekeeper-studio', 'photocraft',
                       'vectorcraft', 'wordcraft', 'gridcraft')
           if p not in aur_list]
if not missing and len(aur_list) >= 15:
    ok(f'first-boot: AUR-список — {len(aur_list)} пакетов, emote/beekeeper/craft входят')
else:
    fail(f'first-boot: AUR-список пакетов {len(aur_list)}, не хватает: {missing or "—"}')

# 13. Консольные утилиты второй волны (решение 2026-10-15): pv
# добавлен следом за bc/httrack/time/bind; sticky — заметки (2026-10-16)
utils = cfg.get('packages', [])
missing = [p for p in ('bc', 'bind', 'httrack', 'time', 'pv', 'sticky')
           if p not in utils]
if not missing:
    ok(f'состав: утилиты bc/bind/httrack/time/pv и sticky (всего {len(utils)} пакетов)')
else:
    fail(f'состав: в packages[] {len(utils)}, не хватает: {missing}')

# 14. Сервисы в services[]: bluetooth (иначе GUI blueman есть, а демон
# disabled — опыт 2026-10-15 на рабочей машине), smartd (мониторинг
# SMART дисков — пакет ставится, сервис без включения молчит) и
# systemd-resolved (локальный кэширующий резолвер — опыт 2026-10-16)
services = cfg.get('services', [])
svc_missing = [s for s in ('bluetooth', 'smartd', 'systemd-resolved') if s not in services]
if not svc_missing:
    ok(f'сервисы: bluetooth, smartd, systemd-resolved включены ({", ".join(services)})')
else:
    fail(f'сервисы: нет {svc_missing}, services[] = {services}')

# 15. Симлинк resolv.conf на stub-конфиг resolved — штатный путь для
# программ, читающих файл напрямую (без него они минуют кэш).
# Симлинк ставит setup-continue копированием в /mnt напрямую, а НЕ
# custom_commands: те идут через arch-chroot, который bind-монтирует
# /etc/resolv.conf хоста поверх /mnt — «ln» падает с «Device or resource
# busy» (опыт установки 2026-10-16). Проверяем обе стороны.
if 'stub-resolv.conf' in setup and '/mnt/etc/resolv.conf' in setup:
    ok('resolved: симлинк ставит setup-continue (в /mnt напрямую)')
else:
    fail('resolved: setup-continue не ставит симлинк resolv.conf -> stub')
if any('stub-resolv.conf' in c or 'resolv.conf' in c for c in cmds):
    fail('resolved: симлинк resolv.conf в custom_commands — там arch-chroot его уронит')
else:
    ok('resolved: симлинка resolv.conf в custom_commands нет (правильно)')

# 16. gai.conf: хук ищет НЕЗАКОММЕНТИРОВАННУЮ строку (^[^#]) — наивный
# grep -q матчит закомментированный пример стокового файла и пропускает
# echo (опыт чистой установки 2026-10-16: precedence не добавился)
gai_hook = open(gai_hook_path).read()
if re.search(r"\[\^#\]\*precedence", gai_hook):
    ok('gai: хук ищет precedence с ^[^#] (не матчит комментарий)')
else:
    fail('gai: хук без ^[^#] — на чистой системе precedence не добавится')
if any("^[^#]*precedence" in c for c in cmds):
    ok('gai: custom_commands с ^[^#]-проверкой')
else:
    fail('gai: в custom_commands grep без ^[^#] — строка не добавится')

# 17. Хук зеркал: безопасен при установке в цель — pacman с --root читает
# хуки живой, но источника /usr/local/share/wdistr/mirrorlist в цели нет
# (cp падал с cannot stat, опыт 2026-10-16); test -f || exit 0
mirrors_hook = open(mirrors_hook_path).read()
if 'test -f' in mirrors_hook and 'exit 0' in mirrors_hook:
    ok('зеркала: хук с test -f || exit 0 (безопасен в цели)')
else:
    fail('зеркала: хук без test -f — при установке cp упадёт с cannot stat')

# 18. Автозапуск: AmneziaVPN и CopyQ доставлены в /etc/xdg/autostart/
# (решение 2026-10-16); sticky ставит свой файл пакет, emote отключён
# хуком (проверка 19)
autostart = [c for c in cmds if '/etc/xdg/autostart/' in c]
names = set()
for c in autostart:
    m = re.search(r"/etc/xdg/autostart/([A-Za-z0-9._-]+\.desktop)", c)
    if m:
        names.add(m.group(1))
if 'AmneziaVPN.desktop' in names and 'copyq.desktop' in names:
    ok(f'автозапуск: AmneziaVPN и copyq в /etc/xdg/autostart (всего {len(names)} файлов)')
else:
    fail(f'автозапуск: найдено {sorted(names)}, нужны AmneziaVPN.desktop и copyq.desktop')

# 19. emote: автозапуск отключён хуком (решение 2026-10-17: пакет AUR
# при установке/обновлении кладёт свой autostart-файл, окно при входе
# лишнее). Хук доставляется custom_commands в
# /etc/pacman.d/hooks/wdistr-emote.hook; проверяем и саму доставку, и
# содержимое (Hidden=true, Trigger на пакет emote) — payload base64
hook_cmds = [c for c in cmds if 'wdistr-emote.hook' in c]
if not hook_cmds:
    fail('emote: хук wdistr-emote.hook не доставляется в цель')
else:
    m = re.search(r"echo '([A-Za-z0-9+/=]+)'", hook_cmds[0])
    if not m:
        fail('emote: команда доставки хука без base64-payload')
    else:
        hook_text = base64.b64decode(m.group(1)).decode()
        if 'Hidden=true' in hook_text and 'Target = emote' in hook_text:
            ok('emote: хук отключения автозапуска доставляется (Hidden=true)')
        else:
            fail('emote: хук без Hidden=true или без Target = emote')

# 20. Своп в first-boot (решение 2026-10-17): Rust-сборки AUR упираются
# в потолок памяти (OOM на librepcb с 8 ГБ, на vectorcraft с 16 ГБ) —
# шаг создаёт /swapfile 8G→4G→пропуск, NOCOW для btrfs, fstab
if 'chattr +C /swapfile' in fb_payload and '/swapfile none swap' in fb_payload:
    ok('first-boot: своп-файл с фолбэком размера и NOCOW для btrfs')
else:
    fail('first-boot: нет шага свопа (chattr +C /swapfile или запись fstab)')

# 21. VirtualBox: обход апстрим-бага #397 (сегфолт при пробуждении
# экрана хоста) — переменная в /etc/environment через custom_commands
# (решение 2026-10-17)
if any('VBOX_DESKTOPWATCHDOGPOLICY_SYNTHTEST=' in c and '/etc/environment' in c
       for c in cmds):
    ok('virtualbox: обход бага #397 — переменная доставляется в /etc/environment')
else:
    fail('virtualbox: нет строки VBOX_DESKTOPWATCHDOGPOLICY_SYNTHTEST в /etc/environment')

# 22. Иконки игр Steam (Steam - Иконка игры на панели Cinnamon.md): у
# каждого steam_app_<appid>.desktop в /usr/share/applications должна быть
# парная иконка в hicolor — иначе панель откатывается к иконке Steam
icon_cmds = [c for c in cmds if '/usr/share/icons/hicolor/' in c and 'steam_app' in c]
icon_ids = set(re.findall(r'steam_app_(\d+)\.png', ' '.join(icon_cmds)))
desk_ids = set(re.findall(r'steam_app_(\d+)\.desktop', ' '.join(cmds)))
missing = desk_ids - icon_ids
if desk_ids and not missing:
    ok(f'игры Steam: {len(desk_ids)} .desktop, у всех есть иконка в hicolor')
else:
    fail(f'игры Steam: иконки не хватает для appid: {sorted(missing) or "нет desktop-файлов"}')

print()
print(f'  инфо:   custom_commands — {len(cmds)} команд')
print(f'Итог: провалов — {fails}')
sys.exit(1 if fails else 0)
PYEOF
