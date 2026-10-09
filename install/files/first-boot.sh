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

# run: команда + её код возврата — в лог, для разбора потом
run() {
    echo "+ $*" >>"$LOG"
    "$@" >>"$LOG" 2>&1
    echo "  rc=$?" >>"$LOG"
}

# 1. Базы всех репозиториев (multilib включён, но база не скачана) + актуальность
run pacman -Syu --noconfirm

# 2. Flathub
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
#    установка через sudo pacman (NOPASSWD из шага 4)
TMP="$(mktemp -d)"
run git clone https://aur.archlinux.org/yay.git "$TMP/yay"
chown -R "$USER_NAME" "$TMP"
run sudo -u "$USER_NAME" env HOME="$USER_HOME" \
    sh -c "cd '$TMP/yay' && makepkg -si --noconfirm"
rm -rf "$TMP"

# 6. AUR: разрешённый список пакетов (Cards/Базовый набор программ).
#    -bin-варианты предпочтительнее сборок из исходников (готовый бинарь
#    вместо компиляции — решение 2026-10-08)
run sudo -u "$USER_NAME" env HOME="$USER_HOME" \
    yay -S --noconfirm --needed \
    pragtical-bin amneziavpn-bin \
    protonup-qt portproton librepcb jan localsend \
    vscodium-bin session-desktop-bin \
    lmstudio-bin arduino-ide-bin

# 7. opencode собственной сборки: скрипт и патчи доставлены в ~/bin
#    (custom_commands), здесь — первая сборка (bun + git + патчи).
#    Версия зафиксирована в скрипте; обновление: opencode.fish <версия>
run sudo -u "$USER_NAME" env HOME="$USER_HOME" \
    fish "$USER_HOME/bin/opencode.fish"

# Логи принадлежат пользователю, чтобы читать без root
chown -R "$(stat -c %U:%G "$USER_HOME")" "$LOGDIR"

echo "== инициализация завершена: $(date -Is) ==" >>"$LOG"
