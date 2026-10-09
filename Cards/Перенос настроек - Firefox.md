type: инструкция
category: wdistr/Перенос
title: Перенос настроек Firefox
summary:
  Руками: скопировать профиль firefox с бэкапа и вписать profiles.ini.
  Три команды и один файл — без скриптов.
date: 2026-10-09

Рабочий профиль хоста: `r1jfcjbe.default-release-1777001883874`
(закладки, история, `about:config`, расширения, пароли, куки — всё
внутри, переносится целиком).

## 1. На хосте — свежий бэкап

Закрыть firefox, запустить `backup_rsync`. Свежесть — по маркеру-дате в
корне `rsync/` на диске.

## 2. На новой машине — скопировать профиль

Диск с бэкапом подключён, firefox ещё НЕ запускался (иначе удали
`~/.mozilla/firefox` целиком):

```sh
cp -a /media/serg/4TB/rsync/home/serg/.mozilla/firefox/r1jfcjbe.default-release-1777001883874 ~/.mozilla/firefox/
rm -f ~/.mozilla/firefox/r1jfcjbe.default-release-1777001883874/{lock,parent.lock,.parentlock}
```

Lock-файлы удаляются обязательно — с чужой машины firefox может
считать профиль занятым.

## 3. Файл profiles.ini

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

## 4. Запустить firefox

Закладки, история, `about:config`, расширения и пароли на месте.
