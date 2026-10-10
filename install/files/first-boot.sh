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
OC_LOG="$LOGDIR/opencode-build.log"
nohup sudo -u "$USER_NAME" env HOME="$USER_HOME" \
    fish "$USER_HOME/bin/opencode.fish" > "$OC_LOG" 2>&1 &
OC_PID=$!
echo "+ opencode.fish в фоне (pid $OC_PID), лог: $OC_LOG" >>"$LOG"

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
run sudo -u "$USER_NAME" env HOME="$USER_HOME" \
    yay -S --noconfirm --needed \
    pragtical-bin amneziavpn-bin \
    protonup-qt portproton librepcb jan localsend \
    vscodium-bin session-desktop-bin \
    lmstudio-bin arduino-ide-bin jstest-gtk-git

# 8. Дожидаемся фоновой сборки opencode и фиксируем её итог
wait "$OC_PID"
OC_RC=$?
echo "+ opencode: rc=$OC_RC (подробности — $OC_LOG)" >>"$LOG"

# Логи принадлежат пользователю, чтобы читать без root
chown -R "$(stat -c %U:%G "$USER_HOME")" "$LOGDIR"

# Итог: ненулевой exit → юнит failed → маркер не встанет → повтор
if [ "$FAILED" -ne 0 ] || [ "$OC_RC" -ne 0 ]; then
    echo "== инициализация с ОШИБКАМИ: $(date -Is) (повтор при следующей загрузке) ==" >>"$LOG"
    exit 1
fi
echo "== инициализация завершена: $(date -Is) ==" >>"$LOG"
