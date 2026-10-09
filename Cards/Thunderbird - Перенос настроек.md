type: инструкция
category: wdistr/Перенос
title: Перенос настроек Thunderbird
summary:
  Руками: rsync-профиля thunderbird с бэкапа и файл profiles.ini.
  Внимание: на хосте thunderbird — flatpak, брать его профиль из
  ~/.var/app, а НЕ старый ~/.thunderbird.
date: 2026-10-09

Рабочий профиль хоста: `1rwi47i4.default-release` (письма, адресная
книга, календарь, PGP-ключи — всё внутри). Бэкап хоста — на внешнем
диске: `/media/serg/4TB/rsync/home/serg`.

**Не перепутай источник.** Thunderbird на хосте — flatpak, его свежий
профиль лежит в контейнере `~/.var/app/org.mozilla.thunderbird/`.
Каталог `~/.thunderbird` в бэкапе — остаток старой установки 2025
года, с ним работать нельзя.

## 1. Скопировать профиль (thunderbird ещё не запускался)

Иначе удали `~/.thunderbird` целиком:

```sh
rsync -a /media/serg/4TB/rsync/home/serg/.var/app/org.mozilla.thunderbird/.thunderbird/1rwi47i4.default-release ~/.thunderbird/
rm -f ~/.thunderbird/1rwi47i4.default-release/{lock,parent.lock,.parentlock}
```

## 2. Файл profiles.ini

Вставить в `~/.thunderbird/profiles.ini`:

```ini
[Profile0]
Name=default
IsRelative=1
Path=1rwi47i4.default-release
Default=1

[General]
StartWithLastProfile=1
Version=2
```

Зачем: выбор «рабочего» профиля у mozilla-программ привязан к хэшу
старой установки (`installs.ini`), на новой машине его нет — без
чистого `profiles.ini` откроется пустой профиль.

## 3. Запустить thunderbird

Письма, адреска и PGP на месте.
