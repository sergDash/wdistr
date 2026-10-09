type: инструкция
category: wdistr/Перенос
title: Перенос настроек Thunderbird
summary:
  Руками: скопировать профиль thunderbird с бэкапа и вписать profiles.ini.
  Внимание: на хосте thunderbird — flatpak, брать его профиль из
  ~/.var/app, а НЕ старый ~/.thunderbird.
date: 2026-10-09

Рабочий профиль хоста: `1rwi47i4.default-release` (письма, адресная
книга, календарь, PGP-ключи — всё внутри).

**Не перепутай источник.** Thunderbird на хосте — flatpak, его свежий
профиль лежит в контейнере `~/.var/app/org.mozilla.thunderbird/`.
Каталог `~/.thunderbird` в бэкапе — остаток старой установки 2025
года, с ним работать нельзя.

## 1. На хосте — свежий бэкап

Закрыть thunderbird, запустить `backup_rsync`.

## 2. На новой машине — скопировать профиль

Диск подключён, thunderbird ещё НЕ запускался (иначе удали
`~/.thunderbird` целиком):

```sh
mkdir -p ~/.thunderbird
cp -a /media/serg/4TB/rsync/home/serg/.var/app/org.mozilla.thunderbird/.thunderbird/1rwi47i4.default-release ~/.thunderbird/
rm -f ~/.thunderbird/1rwi47i4.default-release/{lock,parent.lock,.parentlock}
```

## 3. Файл profiles.ini

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

## 4. Запустить thunderbird

Письма, адреска и PGP на месте.
