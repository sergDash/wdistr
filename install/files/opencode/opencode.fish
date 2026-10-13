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

git fetch origin; or fail
git fetch --tags; or fail
git switch -f dev; or fail
git reset --hard origin/dev; or fail

git switch --detach v$VER; or fail
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

# Если не указать версию, будет 0.0.0--дата
OPENCODE_VERSION=$VER ./packages/opencode/script/build.ts --single; or fail
cp ./packages/opencode/dist/opencode-linux-x64/bin/opencode ~/bin/opencode-$VER; or fail
cd ~/bin/; or fail
ln -sf opencode-$VER opencode; or fail


# Как создавать патч
# git commit -m "fix"
# git format-patch -1 HEAD
# cp 0001-fix.patch ~/bin/opencode-0001.patch
