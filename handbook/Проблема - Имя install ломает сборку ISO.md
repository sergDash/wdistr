# Проблема - Имя install ломает сборку ISO

Статус: **решено переименованием** (2026-09-26).

## Симптом

Сборка mkarchiso завершается ошибкой:

```
install: cannot stat '/home/user/work/x86_64/boot/initramfs-*.img': No such file or directory
```

При этом в логе на шаге `(16/22) Updating linux initcpios...` — загадочный
блок:

```
Fetching Arch Linux package database...
Pacman is already running, waiting maximum 10 minutes for it to terminate.
Pre-existing pacman lock never exited. Please clean up any existing pacman sessions before using archinstall.
error: command failed to execute correctly
```

initramfs не создаётся, ISO получается неработоспособным (без него система
не загружается).

## Причина

В профиль был положен `/usr/local/bin/install` — команда установки нашей
системы. Но `install` — это утилита coreutils (копирование файлов с
правами), которой пользуются хуки pacman и mkinitcpio **внутри chroot при
сборке**. `/usr/local/bin` в PATH идёт раньше `/usr/bin`, поэтому:

1. хук вызывает `install -m644 ...`;
2. перехватывается наш скрипт: `$2` («644») непуст → проверка «имя и
   пароль» пройдена → скрипт запускает archinstall **в chroot сборки**;
3. archinstall лезет за базой pacman, упирается в блокировку внешней
   pacstrap-сессии → падает через 10 минут ожидания;
4. шаг хука не выполняется до конца, mkinitcpio не отрабатывает —
   initramfs отсутствует.

Первая попытка объяснить всё запущенным параллельно `pacman -S htop`
(пользователь ставил утилиту) была ошибочной: вторая попытка упала с тем
же текстом уже без чужих pacman. htop — совпадение по времени, а не причина.

## Решение

Команда переименована: **`install` → `setup`**. Правило: в системных путях
(`/usr/local/bin`, и особенно в профиле ISO) нельзя занимать имена
часто вызываемых утилит (`install`, `cp`, `cat`, `mkdir`...).

## Как ловить такое заранее

Любой новый исполняемый файл в `iso/airootfs/usr/local/bin/` — сверить
имя со списком coreutils перед добавлением в профиль.
