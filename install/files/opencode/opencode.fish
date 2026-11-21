#!/usr/bin/fish
# Сборка opencode собственной сборки с патчами (wdistr).
#
# Версия ОБЯЗАТЕЛЬНА первым аргументом — дефолта нет (решение
# 2026-10-13): патчи рукописные, а теги ветки 2.0 пока не разбирали;
# какая версия будет свежей на момент сборки — заранее неизвестно.
# Пример: opencode.fish 1.19.1

set VER $argv[1]
if test -z "$VER"
    echo "Укажите версию первым аргументом: opencode.fish <версия>" >&2
    echo "Например: opencode.fish 1.19.1" >&2
    exit 1
end

function fail
    echo "Ошибка: команда завершилась с кодом $status" >&2
    exit 1
end

# В чистой системе репозитория ещё нет — клонируем при первом запуске
if not test -d ~/src/opencode
    git clone https://github.com/sst/opencode.git ~/src/opencode; or fail
end

cd ~/src/opencode/; or fail

# git fetch --tags упал бы на конфликте тега vscode-v1.0.0 (локальный ≠ апстрим);
# нам нужен только тег версии — забираем точечно (опыт 2026-10-17)
git fetch origin; or fail
git fetch origin tag v$VER; or fail
git switch -f dev; or fail
git reset --hard origin/dev; or fail

git switch --detach v$VER; or fail
# untracked-файлы прошлой сборки (патчи создавали тесты) мешают git apply —
# чистим перед патчами (опыт 2026-10-17: scroll-window-eviction.test.tsx
# остался с v1.19.0, git apply упал «уже содержится в рабочем каталоге»)
git clean -fd; or fail
# pkg.pr.new мёртв (NXDOMAIN) — заменяем URL @solidjs/start на npm-версию,
# иначе bun install падает; зависимость нужна packages/enterprise (веб),
# CLI от неё не зависит, нам важно лишь пройти установку (опыт 2026-10-10)
sed -i 's|https://pkg.pr.new/@solidjs/start@dfb2020|2.0.5|' package.json; or fail
rm -f bun.lock; or fail  # сломанный lock мешает — bun решит зависимости заново
bun install; or fail

git apply ~/bin/opencode-1.patch; or fail
git apply ~/bin/opencode-2.patch; or fail
git apply ~/bin/opencode-3.patch; or fail
git apply ~/bin/opencode-4.patch; or fail
git apply ~/bin/opencode-5.patch; or fail

# Если не указать версию, будет 0.0.0--дата.
# --single собирает только хост-платформу, заодно прогоняет smoke-тест бинарника.
OPENCODE_VERSION=$VER ./packages/opencode/script/build.ts --single; or fail
# cp обрезает файл, который сейчас исполняется (ETXTBSY: «Текстовый файл занят»),
# а install заменяет его новым inode, поэтому пересборка не требует закрывать TUI.
install -m 0755 ./packages/opencode/dist/opencode-linux-x64/bin/opencode ~/bin/opencode-$VER; or fail

# Windows-сборка. Без --single build.ts берёт все 12 целей (linux, darwin, win32),
# поэтому нужную цель задаём фильтром. Фильтр вписываем в копию build.ts рядом с
# оригиналом: скрипт считает все пути от своего каталога (import.meta.dirname),
# поэтому копия в другом месте не найдёт ни generate.ts, ни package.json.
# Отслеживаемый build.ts остаётся нетронутым (опыт 2026-11-17: правка оригинала
# требует ручного git checkout, а при падении сборки забывается).
set -l win_targets 'allTargets.filter((item) => item.os === "win32" && item.arch === "x64" && item.avx2 !== false)'
cat packages/opencode/script/build.ts | string replace ': allTargets' ": $win_targets" > packages/opencode/script/build-windows.ts
set -l win_status 0
OPENCODE_VERSION=$VER bun run ./packages/opencode/script/build-windows.ts; or set win_status $status
rm -f packages/opencode/script/build-windows.ts
test $win_status -eq 0; or fail
# exe под Linux не запускается, поэтому кладём без исполняемого бита (решение 2026-11-17).
# На Windows этот файл нужно положить в C:\Users\User\.opencode\bin
install -m 0644 ./packages/opencode/dist/opencode-windows-x64/bin/opencode.exe ~/bin/opencode-$VER.exe; or fail

cd ~/bin/; or fail
ln -sf opencode-$VER opencode; or fail


# Как создавать патч
# git commit -m "fix"
# git format-patch -1 HEAD
# cp 0001-fix.patch ~/bin/opencode-0001.patch
