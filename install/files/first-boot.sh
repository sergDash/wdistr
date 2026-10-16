#!/bin/sh
# Автоинициализация при первом запуске системы (wdistr).
# Состав: обновление пакетов и баз (включая multilib), подключение flathub,
# установка flatpak-программ и AUR (helper yay + разрешённый список).
# Лог пишется в ~/install-log/first-boot.log — читаемо пользователем
# и агентом opencode (сценарий самопроверки).
set -u

# Первый обычный пользователь системы (uid >= 1000) — владелец логов
USER_HOME="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 { print $6; exit }')"
USER_NAME="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 { print $1; exit }')"
LOGDIR="$USER_HOME/install-log"
LOG="$LOGDIR/first-boot.log"

mkdir -p "$LOGDIR"

echo "== wdistr: инициализация первого запуска: $(date -Is) ==" >>"$LOG"

# Строгий режим (решение 2026-10-09): любая упавшая команда →
# ненулевой код всего скрипта → systemd пометит юнит failed, маркер
# first-boot-done НЕ создастся и инициализация повторится при
# следующей загрузке (идемпотентные шаги повтор безопасен)
FAILED=0

# run: команда + её код возврата — в лог; ошибка помечает общий флаг
run() {
    echo "+ $*" >>"$LOG"
    "$@" >>"$LOG" 2>&1
    rc=$?
    echo "  rc=$rc" >>"$LOG"
    if [ "$rc" -ne 0 ]; then FAILED=1; fi
}

# 1. Базы всех репозиториев (multilib включён, но база не скачана) + актуальность
run pacman -Syu --noconfirm

# 2. opencode собственной сборки — СРАЗУ И В ФОНЕ (решение 2026-10-09):
#    зависимостей от yay нет (git/bun/node-gyp стоят pacstrap'ом), поэтому
#    сборка идёт параллельно с flatpak и AUR — librepcb не задерживает
#    opencode. Дожидаемся в конце скрипта: systemd убивает дочерние
#    процессы юнита после его завершения. Версия зафиксирована в скрипте;
#    обновление вручную: opencode.fish <версия>
# РЕШЕНИЕ 2026-10-13: сборка на первом запуске ОТКЛЮЧЕНА — оставлено для
#    истории. Причина: opencode уже входит в дистрибутив (бинарник в
#    iso/airootfs, доставка копированием), обновление — вручную
#    opencode.fish <версия>; сборка одной и той же версии при каждой
#    установке — лишняя трата времени и места (~6 ГиБ ~/src/opencode
#    плюс кэш bun), а какая версия будет свежей на момент установки —
#    заранее неизвестно.
# OC_LOG="$LOGDIR/opencode-build.log"
# nohup sudo -u "$USER_NAME" env HOME="$USER_HOME" \
#     fish "$USER_HOME/bin/opencode.fish" > "$OC_LOG" 2>&1 &
# OC_PID=$!
# echo "+ opencode.fish в фоне (pid $OC_PID), лог: $OC_LOG" >>"$LOG"

# 3. Flathub
run flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# 3. Flatpak-программы состава (решение 2026-10-09: приоритет — AUR,
#    в flatpak остаётся steam — его multilib-версия задаёт интерактивный
#    вопрос vulkan-драйверов, а flatpak-версия ставится без вопросов;
#    состав и обоснования — Cards/Базовый набор программ, раздел «Приложения»)
FLATPAK_APPS="
com.valvesoftware.Steam
com.ktechpit.whatsie
net.xmind.XMind
org.dash.dash-core
"
for app in $FLATPAK_APPS; do
    run flatpak install --noninteractive -y flathub "$app"
done

# Сессия Cinnamon могла стартовать раньше установки flatpak (первый запуск
# идёт параллельно с входом пользователя) — дёрнуть перечитывание списка
# приложений, иначе новые программы не появятся в меню до перезапуска
# сессии (опыт 2026-10-10: whatsie ставился после старта сессии, в меню
# не был виден). Если Cinnamon не запущен — ошибка глушится.
# Опыт 2026-10-12: этот же сигнал ронял Cinnamon в аварийный режим
# (диалог «работаете в аварийном режиме, перезапустить?») — строка
# закомментирована, проверяем, повторяется ли аварийный режим без неё;
# цена — новые flatpak в меню появятся только после перезапуска сессии.
# sudo -u "$USER_NAME" killall -HUP cinnamon 2>/dev/null || true

# 4. AUR: sudo без пароля только для pacman — иначе yay и сборка пакетов
#    не пройдут без интерактивного ввода (первый запуск — фоновый сервис)
echo '%wheel ALL=(ALL) NOPASSWD: /usr/bin/pacman' > /etc/sudoers.d/wheel-pacman
chmod 440 /etc/sudoers.d/wheel-pacman

# 5. AUR: helper yay — сборка от ПОЛЬЗОВАТЕЛЯ (makepkg от root запрещён),
#    установка через sudo pacman (NOPASSWD из шага 4). Проверка перед
#    сборкой: повторный запуск (перезагрузка, restart) не должен заново
#    клонировать и собирать yay — идемпотентность без лишней работы
if ! command -v yay >/dev/null 2>&1; then
    TMP="$(mktemp -d)"
    run git clone https://aur.archlinux.org/yay.git "$TMP/yay"
    chown -R "$USER_NAME" "$TMP"
    run sudo -u "$USER_NAME" env HOME="$USER_HOME" \
        sh -c "cd '$TMP/yay' && makepkg -si --noconfirm"
    rm -rf "$TMP"
fi

# 6. AUR: разрешённый список пакетов (Cards/Базовый набор программ).
#    -bin-варианты предпочтительнее сборок из исходников (готовый бинарь
#    вместо компиляции — решение 2026-10-08)
#    Каждый пакет отдельным вызовом (решение 2026-10-13, паттерн flatpak
#    выше): упавший пакет (опыт 2026-10-13: lmstudio-bin с устаревшим
#    sha256 в PKGBUILD) помечает FAILED, но остальные дособираются;
#    при таймерном повторе --needed пропускает стоящее и добирает
#    только упавшее.
AUR_PACKAGES="
amneziavpn-bin
vscodium-bin
jstest-gtk-git
protonup-qt
portproton
session-desktop-bin
lmstudio-bin
arduino-ide-bin
localsend
pragtical-bin
android-studio
librepcb
jan
emote
photocraft
vectorcraft
wordcraft
gridcraft
beekeeper-studio
"
for pkg in $AUR_PACKAGES; do
    run sudo -u "$USER_NAME" env HOME="$USER_HOME" \
        yay -S --noconfirm --needed "$pkg"
done

# 8. Дожидаемся фоновой сборки opencode и фиксируем её итог
# Отключено вместе со сборкой (решение 2026-10-13, шаг 2) — оставлено
# для истории. OC_PID не задаётся, wait на несуществующую переменную
# в set -u упал бы.
# wait "$OC_PID"
# OC_RC=$?
# echo "+ opencode: rc=$OC_RC (подробности — $OC_LOG)" >>"$LOG"

# Логи принадлежат пользователю, чтобы читать без root
chown -R "$(stat -c %U:%G "$USER_HOME")" "$LOGDIR"

# Итог: ненулевой exit → юнит failed → маркер не встанет → повтор
# силами wdistr-first-boot-retry.timer через час (перезагрузка не нужна;
# раньше в строке было «при следующей загрузке» — вводило в заблуждение,
# проверочный агент советовал перезагрузку, опыт 2026-10-14)
# (проверка OC_RC убрана вместе со сборкой opencode — шаг 2)
if [ "$FAILED" -ne 0 ]; then
    echo "== инициализация с ОШИБКАМИ: $(date -Is) (таймер повторит через час; перезагрузка не нужна) ==" >>"$LOG"
    exit 1
fi

# Кэши установки чистим ТОЛЬКО после успеха (опыт 2026-10-13: на тестовой
# 64-ГиБ диске после установки осталось 12 ГиБ, из них ~12 ГиБ — кэши
# pacman 4.7 ГиБ и сборок yay 7.5 ГиБ; после чистки — 24 ГиБ свободно).
# При падении чистить НЕЛЬЗЯ: таймер-повтор дособирает упавшее из уже
# скачанных файлов (--needed пропускает стоящее, упавшее добирается из
# кэша). Ошибка чистки не должна валить юнит: система уже работает,
# маркер важнее места.
# Опыт 2026-10-13: pacman -Scc --noconfirm пакеты НЕ чистит — на вопрос
# «Удалить ВСЕ файлы из кэша? [y/N]» --noconfirm отвечает умолчанием
# «нет»; явные y даёт yes.
echo "+ очистка кэшей pacman и yay" >>"$LOG"
yes | pacman -Scc >>"$LOG" 2>&1
echo "  rc=$? (pacman -Scc)" >>"$LOG"
sudo -u "$USER_NAME" env HOME="$USER_HOME" \
    yay -Scc --noconfirm >>"$LOG" 2>&1
echo "  rc=$? (yay -Scc)" >>"$LOG"

echo "== инициализация завершена: $(date -Is) ==" >>"$LOG"

# Маркер успеха — на рабочем столе пользователя: итог виден без SSH
# и без чтения лога. Папка Desktop появляется при первом входе в сессию,
# mkdir -p подстраховывает, если юнит успел раньше. Файл от пользователя
# (скрипт идёт от root), содержимое — дата и путь к логу для разбора.
DESKTOP_MARKER="$USER_HOME/Desktop/Установка-завершена.txt"
mkdir -p "$USER_HOME/Desktop"
{
    echo "Установка и инициализация завершены: $(date -Is)"
    echo "Лог первого запуска: $LOG"
} > "$DESKTOP_MARKER"
chown "$USER_NAME" "$DESKTOP_MARKER"
