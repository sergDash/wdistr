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
    etc/pacman.d/hooks/wdistr-ghostty.hook \
    etc/pacman.d/hooks/wdistr-cinnamon.hook \
    usr/local/share/wdistr/cinnamon-appmenu.css \
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
         "$TMP/x/etc/pacman.d/hooks/wdistr-mirrors.hook" \
         "$TMP/x/etc/pacman.d/hooks/wdistr-ghostty.hook" \
         "$TMP/x/etc/pacman.d/hooks/wdistr-cinnamon.hook" \
         "$TMP/x/usr/local/share/wdistr/cinnamon-appmenu.css" <<'PYEOF'
import base64
import json
import os
import re
import sys

(cfg_path, setup_path, mirror_path, symlink_path, list_path,
 mirrors_path, gai_hook_path, mirrors_hook_path,
 ghostty_hook_path, cinnamon_hook_path,
 cinnamon_css_path) = sys.argv[1:12]

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
# PDF → Okular (решение 2026-10-16), исходный текст и простой текст →
# VSCodium (пожелание 2026-10-18); без inode/directory codium
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
    'text/x-python=codium.desktop': 'VSCodium-исходный',
    'text/plain=codium.desktop': 'VSCodium-текст',
}
missing = [name for key, name in checks.items() if key not in payload]
if len(mm) == 1 and not missing:
    ok(f'mimeapps.list: Nemo/Thunderbird/Viewnior/WordCraft/GridCraft/Okular/VSCodium')
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

# 23. Терминал по умолчанию — Ghostty с ЯВНЫМ --gtk-single-instance=false
# (решение 2026-10-17). При single-instance «Открыть в терминале» из Nemo
# уходил через D-Bus работающему процессу, окно рисовал первичный процесс
# и брало каталог последнего окна вместо папки Nemo. Просто убрать =true
# недостаточно: дефолт gtk-single-instance=detect при работающем основном
# процессе всё равно делегирует ему. Обе точки (системный дефолт + форс
# первого входа) обязаны держать --gtk-single-instance=false.
# Проверяем сами строки exec: значения должны быть ровно
# '/usr/bin/ghostty --gtk-single-instance=false'; упоминание флага в
# комментариях допустимо.
term_sys = re.search(
    r"^\s*exec='/usr/bin/ghostty --gtk-single-instance=false'\s*$",
    dc_payload, re.M)
term_force = re.search(
    r"^\s*gsettings set org\.cinnamon\.desktop\.default-applications\.terminal exec '/usr/bin/ghostty --gtk-single-instance=false'\s*$",
    cd_payload, re.M)
if term_sys and term_force:
    ok('терминал: Ghostty --gtk-single-instance=false в системном дефолте и форсе')
else:
    fail(f'терминал: системный дефолт = {bool(term_sys)}, форс = {bool(term_force)}')

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
# добавлен следом за bc/httrack/time/bind; sticky — заметки (2026-10-16);
# man-db + man-pages + man-pages-ru — man-страницы (2026-10-17: без
# man-db в составе pacman спрашивал поставщика молча ставить всё)
utils = cfg.get('packages', [])
missing = [p for p in ('bc', 'bind', 'httrack', 'time', 'pv', 'sticky',
                       'man-db', 'man-pages', 'man-pages-ru')
           if p not in utils]
if not missing:
    ok(f'состав: утилиты bc/bind/httrack/time/pv/sticky и man (всего {len(utils)} пакетов)')
else:
    fail(f'состав: в packages[] {len(utils)}, не хватает: {missing}')

# 14. Сервисы в services[]: bluetooth (иначе GUI blueman есть, а демон
# disabled — опыт 2026-10-15 на рабочей машине), smartd (мониторинг
# SMART дисков — пакет ставится, сервис без включения молчит),
# systemd-resolved (локальный кэширующий резолвер — опыт 2026-10-16) и
# vboxservice (Guest Additions: без сервиса гость не получает режимы
# от хоста — lightdm сидит в 1280x800, setvideomodehint не применяется;
# опыт 2026-10-18 на тестовой; пакет guest-utils в составе намеренно)
services = cfg.get('services', [])
svc_missing = [s for s in ('bluetooth', 'smartd', 'systemd-resolved', 'vboxservice') if s not in services]
if not svc_missing:
    ok(f'сервисы: bluetooth, smartd, systemd-resolved, vboxservice включены ({", ".join(services)})')
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

# 18. Автозапуск: AmneziaVPN, CopyQ и Flameshot доставлены в
# /etc/xdg/autostart/ (решение 2026-10-16, 2026-10-17). Sticky Notes
# включён иначе — ключом org.x.sticky autostart (проверка 30): пакет
# ставит свой autostart-файл с флагом --autostart, файл оживляет
# ключ. emote отключён хуком (проверка 19)
autostart = [c for c in cmds if '/etc/xdg/autostart/' in c]
names = set()
for c in autostart:
    m = re.search(r"/etc/xdg/autostart/([A-Za-z0-9._-]+\.desktop)", c)
    if m:
        names.add(m.group(1))
need_autostart = {'AmneziaVPN.desktop', 'copyq.desktop'}
missing = need_autostart - names
if not missing:
    ok(f'автозапуск: AmneziaVPN/copyq в /etc/xdg/autostart (всего {len(names)} файлов)')
else:
    fail(f'автозапуск: не хватает {sorted(missing)}, найдено {sorted(names)}')
# Flameshot в системном автозапуске НЕТ по решению 2026-10-19: его
# галка «Запускать в фоне при старте» видит только собственный
# ~/.config/autostart/Flameshot.desktop (с большой буквы), чужой
# системный файл давал запуск при снятой галке
if 'flameshot.desktop' not in names:
    ok('автозапуск: flameshot НЕ в /etc/xdg/autostart (собственный механизм)')
else:
    fail('автозапуск: flameshot остался в системном автозапуске — убрать')

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
# шаг создаёт /swapfile 8G→4G→пропуск, NOCOW для btrfs, fstab.
# На машинах с памятью больше 64 ГиБ своп пропускается (2026-10-17):
# потолок не пробивается, файл 8 ГиБ не нужен
swap_ok = ('chattr +C /swapfile' in fb_payload
           and '/swapfile none swap' in fb_payload
           and '67108864' in fb_payload)
if swap_ok:
    ok('first-boot: своп с фолбэком, NOCOW и пропуском при памяти >64 ГиБ')
else:
    fail('first-boot: нет шага свопа или условия по памяти (>64 ГиБ)')

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

# 24. Ghostty: .desktop пакета приведён к --gtk-single-instance=false
# (решение 2026-10-17). В настройках Cinnamon терминал сверяет dconf-ключ
# exec со строкой Exec .desktop (cs_default.py) — штатный =true не давал
# ghostty отмечаться в списке, хотя работал. Хук на пакет + немедленный
# sed в custom_commands (пакет уже установлен archinstall'ом до
# custom_commands). Проверяем обе стороны и содержимое хука
ghostty_hook = open(ghostty_hook_path).read()
if 'Target = ghostty' in ghostty_hook and '--gtk-single-instance=false' in ghostty_hook:
    ok('ghostty: хук на пакет приводит .desktop к --gtk-single-instance=false')
else:
    fail('ghostty: хук без Target = ghostty или без замены флага')
if any("com.mitchellh.ghostty.desktop" in c and '--gtk-single-instance=false' in c
       for c in cmds):
    ok('ghostty: немедленный sed .desktop в custom_commands')
else:
    fail('ghostty: нет немедленного sed .desktop в custom_commands')

# 25. Конфиг Ghostty в домашней папке первого пользователя (решение
# 2026-10-17): ghostty читает ТОЛЬКО ~/.config/ghostty/config —
# XDG_CONFIG_DIRS (/etc/xdg) он игнорирует (опыт 2026-10-17:
# системный файл доехал в цель, но +show-config его не видел,
# конфиг оставался пустым). Рамка server, темы, хоткеи
gh_cfg = [c for c in cmds if '/home/$U/.config/ghostty/config' in c]
gh_payload = ''
if gh_cfg:
    # В команде посева несколько echo-payload — ищем тот, что
    # декодируется в конфиг ghostty (по ключевой строке)
    for m in re.finditer(r"echo '([A-Za-z0-9+/=]+)'", gh_cfg[0]):
        decoded = base64.b64decode(m.group(1)).decode()
        if 'window-decoration' in decoded:
            gh_payload = decoded
            break
if 'window-decoration = server' in gh_payload and 'theme = Andromeda' in gh_payload:
    ok('ghostty: конфиг в ~/.config/ghostty/config первого пользователя')
else:
    fail('ghostty: конфиг не доставлен в домашнюю папку или неполон')

# 26. Системная рамка окна у craft-приложений (решение 2026-10-17) и
# масштаб колесом мыши в photocraft (решение 2026-10-18): photocraft/
# vectorcraft по умолчанию рисуют свою (CSD) — минимальные пользовательские
# конфиги пишутся до установки пакетов (она в first-boot), guard от
# затирания при повторе
craft_ok = ('"interface":{"systemTitleBar":true}' in ' '.join(cmds)
            and '"engine_prefs":{"systemTitleBar":true}' in ' '.join(cmds))
if craft_ok:
    ok('craft: photocraft/vectorcraft — systemTitleBar=true в конфигах')
else:
    fail('craft: нет минимальных конфигов systemTitleBar=true')
if '"general":{"zoomWithScrollWheel":true}' in ' '.join(cmds):
    ok('photocraft: масштаб колесом мыши включён (zoomWithScrollWheel)')
else:
    fail('photocraft: нет zoomWithScrollWheel=true в конфиге')

# 27. Группировка окон на панели отменена (решение 2026-10-17): ключ
# group-apps=false в JSON-патче applet'а (cinnamon-defaults) И посев
# готового 2.json при установке — applet не перечитывает JSON на лету,
# и без посева первая сессия после установки оставалась сгруппированной
# (опыт 2026-10-17)
if "d['group-apps']['value'] = False" in cd_payload:
    ok('панель: группировка окон отменена (group-apps=false) в форсе')
else:
    fail('панель: нет group-apps=False в cinnamon-defaults')
# Instance меню :5 + посев 5.json (опыт 2026-10-18, установки
# user2/user3/user4): «Reloading applet» настройки не перечитывает,
# перенос между зонами не пересоздаёт — надёжное пересоздание даёт
# только новый instance id с готовым файлом JSON
if ('menu@cinnamon.org:5' in cd_payload
        and 'menu@cinnamon.org/5.json' in cd_payload):
    ok('панель: меню instance :5 с посевом 5.json в cinnamon-defaults')
else:
    fail('панель: нет instance :5/посева 5.json в cinnamon-defaults')
gwl_seed = [c for c in cmds
            if 'grouped-window-list@cinnamon.org/2.json' in c]
# В команде несколько echo-payload (ghostty + этот JSON) — ищем тот,
# что декодируется в JSON с group-apps
gwl_payload = ''
if gwl_seed:
    for m in re.finditer(r"echo '([A-Za-z0-9+/=]+)'", gwl_seed[0]):
        try:
            text = base64.b64decode(m.group(1)).decode()
        except Exception:
            continue
        if '"group-apps"' in text:
            gwl_payload = text
            break
if '"group-apps"' in gwl_payload and '"value": false' in gwl_payload:
    ok('панель: посев 2.json с group-apps=false в домашней папке')
else:
    fail('панель: посева 2.json с group-apps=false нет в custom_commands')
# Посев 13.json calendar — тот же паттерн (опыт 2026-10-18: формат
# даты не применялся в первую сессию, applet создавал файл с дефолтами
# после патча cinnamon-defaults)
cal_seed = [c for c in cmds if 'calendar@cinnamon.org/13.json' in c]
cal_payload = ''
if cal_seed:
    for m in re.finditer(r"echo '([A-Za-z0-9+/=]+)'", cal_seed[0]):
        try:
            text = base64.b64decode(m.group(1)).decode()
        except Exception:
            continue
        if 'use-custom-format' in text:
            cal_payload = text
            break
if '"value": true' in cal_payload and '%a, %e %b' in cal_payload:
    ok('панель: посев 13.json календаря с кастомным форматом даты')
else:
    fail('панель: посева 13.json календаря нет в custom_commands')

# 28. Перетаскивание окон — Win, не Alt (решение 2026-10-17): ключ в
# системном dconf-дефолте и в форсе первого входа (паттерн тем/шрифтов)
wm_sys = re.search(
    r"^\s*mouse-button-modifier='<Super>'\s*$", dc_payload, re.M)
wm_force = re.search(
    r"^\s*gsettings set org\.cinnamon\.desktop\.wm\.preferences mouse-button-modifier '<Super>'\s*$",
    cd_payload, re.M)
if wm_sys and wm_force:
    ok('окна: перетаскивание Win (<Super>) в системном дефолте и форсе')
else:
    fail(f'окна: системный дефолт = {bool(wm_sys)}, форс = {bool(wm_force)}')

# 29. Значки на кнопках окон — выключены (решение 2026-10-17): ключ
# xsettings-схемы в обоих местах (паттерн тем/шрифтов)
icons_sys = re.search(
    r"^\s*buttons-have-icons=false\s*$", dc_payload, re.M)
icons_force = re.search(
    r"^\s*gsettings set org\.cinnamon\.settings-daemon\.plugins\.xsettings buttons-have-icons false\s*$",
    cd_payload, re.M)
if icons_sys and icons_force:
    ok('окна: значки на кнопках выключены в системном дефолте и форсе')
else:
    fail(f'окна: системный дефолт = {bool(icons_sys)}, форс = {bool(icons_force)}')

# 30. Sticky Notes: автозапуск через ключ org.x.sticky autostart
# (решение 2026-10-17). Пакет ставит свой autostart-файл с флагом
# --autostart: программа при старте сверяет ключ и выходит, если
# false (дефолт схемы) — ключ в системном dconf-дефолте оживляет
# штатный файл. Дубль в форсе не нужен: схема приложенная, Cinnamon
# её не перебивает
sticky_key = re.search(
    r"^\s*\[org/x/sticky\]\s*$", dc_payload, re.M)
sticky_val = re.search(
    r"^\s*autostart=true\s*$", dc_payload, re.M)
if sticky_key and sticky_val:
    ok('sticky: ключ org.x.sticky autostart=true в системном дефолте')
else:
    fail(f'sticky: ключ = {bool(sticky_key)}, autostart=true = {bool(sticky_val)}')

# 31. setup-continue при провале archinstall печатает ГОТОВУЮ команду
# продолжения с параметрами пользователя (запрос 2026-10-17: «повторите
# с теми же аргументами» путало — не было видно, что повторять)
if ('Попробуйте продолжить командой' in setup
        and 'setup-continue $1 $2 $3' in setup):
    ok('setup-continue: при провале archinstall печатается готовая команда')
else:
    fail('setup-continue: нет готовой команды продолжения в сообщении об ошибке')

# 32. Flameshot: системный дефолт /etc/xdg/flameshot/flameshot.ini —
# устаревший X11-снимок, захват активного монитора (запрос 2026-10-17)
# и автозапуск (решение 2026-10-19: startupLaunch=true + посев
# ~/.config/autostart/Flameshot.desktop первого пользователя — галка
# «Запускать в фоне при старте» включена и отражает реальность).
# QSettings в UserScope падает к системному скоупу, личный файл
# пользователя дефолт перекрывает
fh = [c for c in cmds if '/etc/xdg/flameshot/flameshot.ini' in c]
fh_payload = ''
if fh:
    m = re.search(r"echo '([A-Za-z0-9+/=]+)'", fh[0])
    if m:
        fh_payload = base64.b64decode(m.group(1)).decode()
if ('useX11LegacyScreenshot=true' in fh_payload
        and 'captureActiveMonitor=true' in fh_payload
        and 'startupLaunch=true' in fh_payload):
    ok('flameshot: системный дефолт с X11-снимком, активным монитором и startupLaunch')
else:
    fail('flameshot: нет /etc/xdg/flameshot/flameshot.ini или ключей')
fh_ast = [c for c in cmds if '/home/$U/.config/autostart/Flameshot.desktop' in c]
fh_ast_payload = ''
if fh_ast:
    for m in re.finditer(r"echo '([A-Za-z0-9+/=]+)'", fh_ast[0]):
        decoded = base64.b64decode(m.group(1)).decode()
        if 'Flameshot' in decoded or 'flameshot' in decoded:
            fh_ast_payload = decoded
            break
if ('Exec=flameshot' in fh_ast_payload
        and 'X-GNOME-Autostart-enabled=true' in fh_ast_payload):
    ok('flameshot: посев ~/.config/autostart/Flameshot.desktop первого пользователя')
else:
    fail('flameshot: нет посева пользовательского автозапуска Flameshot.desktop')

# 33. Audacity: тема тёмная (решение 2026-10-18). Панели Audacity
# рисуются собственной системой тем classic/light/dark — GTK/dconf
# приложение не читает, без ключа Theme действует светлый classic
# (опыт установки 2026-10-18). Посев минимального audacity.cfg в
# ~/.config первого пользователя (паттерн ghostty), guard test -f
aud_cfg = [c for c in cmds if '/home/$U/.config/audacity/audacity.cfg' in c]
aud_payload = ''
if aud_cfg:
    # В команде посева несколько echo-payload (ghostty + audacity +
    # JSON applet'ов) — ищем тот, что декодируется в audacity.cfg
    for m in re.finditer(r"echo '([A-Za-z0-9+/=]+)'", aud_cfg[0]):
        decoded = base64.b64decode(m.group(1)).decode()
        if 'Theme=' in decoded:
            aud_payload = decoded
            break
if '[GUI]' in aud_payload and 'Theme=dark' in aud_payload:
    ok('audacity: посев audacity.cfg с Theme=dark в домашнюю папку')
else:
    fail('audacity: нет посева audacity.cfg или ключа Theme=dark')

# 34. Меню Пуск — квадратное, скроллбары квадратные (решение
# 2026-10-18). cinnamon.css — файл пакета, сток затирает правки при
# обновлениях: хук на пакет cinnamon добивает блок, немедленная
# команда в custom_commands чинит цель сразу (пакет установлен до
# custom_commands, хук при pacstrap не сработал — источник в цели
# ещё не доставлен, паттерн gai). Три стороны: хук, источник, команда
# На старых ISO файлов ещё нет — os.path.exists, не open (иначе
# traceback вместо FAIL)
cin_hook = open(cinnamon_hook_path).read() if os.path.exists(cinnamon_hook_path) else ''
cin_css = open(cinnamon_css_path).read() if os.path.exists(cinnamon_css_path) else ''
if 'Target = cinnamon' in cin_hook and 'wdistr-appmenu' in cin_hook:
    ok('меню: хук на пакет cinnamon дописывает wdistr-appmenu')
else:
    fail('меню: хук без Target = cinnamon или без wdistr-appmenu')
if 'wdistr-appmenu' in cin_css and 'border-color: #999999' in cin_css:
    ok('меню: источник cinnamon-appmenu.css в /usr/local/share/wdistr/')
else:
    fail('меню: нет cinnamon-appmenu.css или нет рамки #999999')
if any('wdistr-appmenu' in c and 'cinnamon-appmenu.css' in c
       and '>> /usr/share/cinnamon/theme/cinnamon.css' in c
       for c in cmds):
    ok('меню: немедленное дописывание блока в custom_commands')
else:
    fail('меню: нет немедленного append блока в custom_commands')

# 35. Session: автообновление отключено (решение 2026-10-18) — дистрибутив
# обновляется своими средствами (та же pacman -Syu по таймеру), приложение
# само себя не тянет. Посев минимального config.json в ~/.config первого
# пользователя (паттерн ghostty), guard test -f
ses_cfg = [c for c in cmds if '/home/$U/.config/Session/config.json' in c]
ses_payload = ''
if ses_cfg:
    for m in re.finditer(r"echo '([A-Za-z0-9+/=]+)'", ses_cfg[0]):
        decoded = base64.b64decode(m.group(1)).decode()
        if 'autoUpdate' in decoded:
            ses_payload = decoded
            break
if '"autoUpdate": false' in ses_payload:
    ok('session: посев config.json с autoUpdate=false в домашнюю папку')
else:
    fail('session: нет посева config.json или ключа autoUpdate=false')

# 36. VSCodium: системная рамка окна (решение 2026-10-18) — titleBarStyle
# native, своя кастомная панель не рисуется. Посев settings.json в
# ~/.config/VSCodium/User первого пользователя, guard test -f
cod_cfg = [c for c in cmds if '/home/$U/.config/VSCodium/User/settings.json' in c]
cod_payload = ''
if cod_cfg:
    for m in re.finditer(r"echo '([A-Za-z0-9+/=]+)'", cod_cfg[0]):
        decoded = base64.b64decode(m.group(1)).decode()
        if 'titleBarStyle' in decoded:
            cod_payload = decoded
            break
if '"window.titleBarStyle": "native"' in cod_payload:
    ok('codium: посев settings.json с системной рамкой (titleBarStyle native)')
else:
    fail('codium: нет посева settings.json или ключа titleBarStyle native')

# 37. Java в составе (запрос 2026-10-19): дефолтная тулчейн-версия
# (jdk-openjdk) и LTS 25 (jdk25-openjdk) — обе из extra, в packages[]
if 'jdk-openjdk' in utils and 'jdk25-openjdk' in utils:
    ok('состав: java — jdk-openjdk (дефолт) и jdk25-openjdk (LTS)')
else:
    fail('состав: в packages[] нет jdk-openjdk и/или jdk25-openjdk')

print()
print(f'  инфо:   custom_commands — {len(cmds)} команд')
print(f'Итог: провалов — {fails}')
sys.exit(1 if fails else 0)
PYEOF
