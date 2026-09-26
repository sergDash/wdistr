# Сборка ISO (archiso)

Полный проверенный конвейер: от профиля до тестируемого ISO (2026-09-26).

## Где что живёт

- Профиль — `iso/` в репозитории (снят с пакета archiso-90 из extra;
  версию профиля держать синхронизированной с archiso в сборочной VM).
- Сборка — в сборочной VM `wdistr-build` (Arch, пакет `archiso`).
- Выходные файлы mkarchiso создаются в `out` **относительно текущей папки
  запуска** (запуск из `~` → `~/out`), не профиля.
- Тестовый стенд — `vm/create-test-vm.sh` (VM `wdistr-test` со свежим
  `iso/out/wdistr-*.iso`).

## Передача профиля в сборочную VM

Хост раздаёт репозиторий: `python3 -m http.server 8000` (из корня
репозитория). В госте:

```sh
curl -fsSL http://10.0.2.2:8000/iso-profile.tgz -o /tmp/p.tgz
tar -xzf /tmp/p.tgz -C ~          # даёт ~/iso; sudo не нужен
```

Тарбол собирается на хосте: `tar czf iso-profile.tgz iso` (файл в
`.gitignore`).

## Сборка

```sh
sudo mkarchiso -v ~/iso            # путь явный, см. проблему с профилем
```

## Вынос готового ISO на хост

Обратный канал: проброс порта гостя 8000 на хост 9999. Правило
`controlvm ... natpf1` живёт только пока VM работает; для постоянного —
когда VM выключена:

```bash
VBoxManage modifyvm wdistr-build --natpf1 "isoout,tcp,,9999,,8000"
```

В госте: `cd ~/out && python3 -m http.server 8000`.
На хосте: `curl -o iso/out/<имя>.iso http://127.0.0.1:9999/<имя>.iso`.

## Проверка содержимого ISO без загрузки

```bash
7z x -o/tmp/x <iso> arch/x86_64/airootfs.sfs
unsquashfs -d /tmp/x/ex /tmp/x/arch/x86_64/airootfs.sfs etc/hostname root/wdistr
```

## Тест

```bash
bash vm/create-test-vm.sh          # пересоздание: VBoxManage unregistervm wdistr-test --delete
```

В госте: `sh /root/wdistr/go.sh --dry-run`, затем `sh /root/wdistr/go.sh`.

## Известные особенности

- В живой среде нет команды `hostname` — проверять `cat /etc/hostname`.
- В текстовой консоли живой среды мышь захватывается (интеграция неактивна
  до X) — в окно не кликать.
- Для пересборки после правок профиля: заново тарбол → передача → сборка.
  Изменения вида «добавить пакет в живую среду» — `iso/packages.x86_64`;
  изменения содержимого установленной системы — конфиг в `install/`.

## Перед передачей профиля

Если правились файлы в `install/files/` — пересобрать команды доставки:

```bash
python3 install/regen-custom-commands.py   # сам синхронизирует конфиг с профилем
```

Иначе изменения не доедут до устанавливаемой системы (airootfs настраивает
только живую среду, целевая система получает настройки через custom_commands).

- Выключение тестовой VM командой `controlvm ... acpipowerbutton` может
  не сработать (2 случая 2026-09-26, XFCE-гость) — тогда `controlvm ... poweroff`
  (данные тестовые, допустимо).

## Перед КАЖДОЙ пересборкой — удалять work и out

Внутри `work/` mkarchiso хранит маркеры «шаг уже выполнен». Если каталог
остался от прошлой (или прерванной) сборки, повторный запуск **молча
пропускает все шаги и завершается с кодом 0, не создав ISO** — выглядит
как мгновенное «падение» после `Validating options... Done!`
(случай 2026-09-26). Безопасный шаблон перед запуском:

```sh
sudo rm -rf /home/user/work /home/user/out
cd /home/user && nohup sudo mkarchiso -v /home/user/iso > /home/user/build.log 2>&1 < /dev/null &
```

Проверка, что сборка реально идёт: в логе через ~10 секунд должны появиться
строки `checking keyring...` / загрузки пакетов, а не только `Done!` валидации.
