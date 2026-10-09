type: инструкция
category: wdistr/Перенос
title: Перенос настроек Firefox
summary:
  Руками: rsync-профиля firefox с бэкапа и файл profiles.ini. Три шага
  и один файл — без скриптов.
date: 2026-10-09

Рабочий профиль хоста: `r1jfcjbe.default-release-1777001883874`
(закладки, история, `about:config`, расширения, пароли, куки — всё
внутри, переносится целиком). Бэкап хоста — на внешнем диске:
`/media/serg/4TB/rsync/home/serg`.

## 1. Скопировать профиль (firefox ещё не запускался)

Иначе удали `~/.mozilla/firefox` целиком:

```sh
rsync -a /media/serg/4TB/rsync/home/serg/.mozilla/firefox/r1jfcjbe.default-release-1777001883874 ~/.mozilla/firefox/
rm -f ~/.mozilla/firefox/r1jfcjbe.default-release-1777001883874/{lock,parent.lock,.parentlock}
```

Lock-файлы удаляются обязательно — с чужой машины firefox может
считать профиль занятым.

## 2. Файл profiles.ini

Просто вставить в `~/.mozilla/firefox/profiles.ini`:

```ini
[Profile0]
Name=default
IsRelative=1
Path=r1jfcjbe.default-release-1777001883874
Default=1

[General]
StartWithLastProfile=1
Version=2
```

Зачем: без этого файла firefox выберёт пустой профиль — выбор
«рабочего» привязан к хэшу старой установки (`installs.ini`), на новой
машине его нет. Чистый `profiles.ini` с `Default=1` снимает вопрос.

## 3. Запустить firefox

Закладки, история, `about:config`, расширения и пароли на месте.
