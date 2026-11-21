#!/usr/bin/fish
# Сборка OpenCode 2 из тега и установка рядом с OpenCode 1.
#
# Версия обязательна: opencode2.fish 2.3.2 [--windows]
# Патчи накладываются из ~/bin/opencode2-*.patch после очистки рабочей копии.
#
# Сборка идёт в отдельной рабочей копии ~/src/opencode-v2, чтобы не трогать
# исходники v1 в ~/src/opencode. Готовый бинарник кладётся в ~/bin/opencode2-<версия>,
# а ~/bin/opencode2-bin указывает на него. Обёртка ~/bin/opencode2 задаёт отдельные
# БД, state, cache и конфиг, поэтому v1 и v2 не делят изменяемое состояние.

set VER $argv[1]
set WINDOWS 0
if contains -- --windows $argv
    set WINDOWS 1
end

if test -z "$VER"; or string match -q -- '-*' $VER
    echo "Укажите версию первым аргументом: opencode2.fish <версия> [--windows]" >&2
    echo "Например: opencode2.fish 2.3.2" >&2
    exit 1
end

function fail
    echo "Ошибка: команда завершилась с кодом $status" >&2
    exit 1
end

set SRC ~/src/opencode-v2

# В связанной рабочей копии .git — файл, поэтому проверяем существование, а не каталог.
if not test -e $SRC/.git
    if test -d ~/src/opencode/.git
        git -C ~/src/opencode fetch origin tag v$VER; or fail
        git -C ~/src/opencode worktree add $SRC v$VER; or fail
    else
        git clone https://github.com/sst/opencode.git $SRC; or fail
    end
end

cd $SRC; or fail

git fetch origin tag v$VER; or fail
git switch -f --detach v$VER; or fail
git clean -fd; or fail

# Патчи лежат вне репозитория: switch -f и clean сбрасывают рабочую копию,
# поэтому единственный источник правок — файлы ~/bin/opencode2-*.patch.
for patch in ~/bin/opencode2-*.patch
    test -e $patch; or continue
    git apply $patch; or fail
end

bun install --frozen-lockfile; or fail

# v2 собирает CLI из packages/cli, а не из packages/opencode.
# --single собирает только хост-платформу и проверяет бинарник.
OPENCODE_VERSION=$VER bun run ./packages/cli/script/build.ts --single; or fail
install -m 0755 ./packages/cli/dist/cli-linux-x64/bin/opencode ~/bin/opencode2-$VER; or fail
ln -sfn opencode2-$VER ~/bin/opencode2-bin; or fail

if test $WINDOWS -eq 1
    # OPENCODE_TARGET фильтрует цели штатно, копировать build.ts не нужно.
    OPENCODE_VERSION=$VER OPENCODE_TARGET=windows-x64 bun run ./packages/cli/script/build.ts; or fail
    install -m 0644 ./packages/cli/dist/cli-windows-x64/bin/opencode.exe ~/bin/opencode2-$VER.exe; or fail
end

echo "Собрано: ~/bin/opencode2-$VER"
echo "Запуск: opencode2"
