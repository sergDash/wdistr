#!/bin/sh
# Автообновление СИСТЕМЫ (wdistr): еженедельно, таймер wdistr-sys-update.
# pacman -Syu идёт от root (сервис), пароль не нужен; лог —
# install-log/sys-update.log, читаемо пользователем и агентом.
set -u

USER_HOME="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 { print $6; exit }')"
LOGDIR="$USER_HOME/install-log"
LOG="$LOGDIR/sys-update.log"

mkdir -p "$LOGDIR"
echo "== обновление системы: $(date -Is) ==" >>"$LOG"
# Опыт 2026-11-11: разъезд sync-баз (core старая, extra свежая —
# следствие экспериментов с зеркалами либо отставания зеркала) даёт
# pacman «неразрешимые зависимости» (libcrypto.so=4-64 и подобные).
# Бояться нечего — частичного обновления не будет: вопрос pacman
# «skip these packages?» — noyes(), дефолт N, а --noconfirm отвечает
# дефолтом, то есть «не пропускать» → транзакция падает целиком
# (ALPM_ERR_UNSATISFIED_DEPS). rc!=0 уходит в лог, кэш не чистится,
# OnFailure добьёт повтором через 4 часа, когда зеркала догонят.
pacman -Syu --noconfirm >>"$LOG" 2>&1
RC=$?
echo "  rc=$RC" >>"$LOG"

# Решение 2026-11-08: после успеха — полная очистка кэша pacman
# (/var/cache/pacman/pkg), без хранения старых версий. При падении
# обновления чистить нельзя: повтор (wdistr-update-retry) добирает
# пакеты из кэша — та же логика, что в first-boot. --noconfirm на -Scc
# отвечает умолчанием «нет» (опыт 2026-10-13), поэтому явный yes.
# Код очистки на RC не влияет: наружу уходит код обновления.
if [ "$RC" -eq 0 ]; then
    echo "+ очистка кэша pacman" >>"$LOG"
    yes | pacman -Scc >>"$LOG" 2>&1
    echo "  rc=$? (pacman -Scc)" >>"$LOG"
fi

chown -R "$(stat -c %U:%G "$USER_HOME")" "$LOGDIR"
# Код сбоя наружу — по нему сервис включает повтор через 4 часа
# (OnFailure, шаблон wdistr-update-retry@; без exit код гасил chown)
exit "$RC"
