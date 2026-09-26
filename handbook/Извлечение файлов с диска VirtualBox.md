# Извлечение файлов с диска VirtualBox

Как достать файл из выключенной виртуальной машины, не загружая её:
диск VDI → raw-образ → раздел → чтение файловой системы без монтирования.

Проверено 2026-09-26 на хосте Linux Mint (все инструменты уже установлены:
`qemu-img`, `fdisk`, `dd`, `debugfs`).

## Шаги

VM должна быть выключена. Путь к диску — в `VBoxManage showvminfo <имя> --machinereadable`,
у нас это `vm/wdistr-build.vdi`.

1. Конвертация VDI в raw (root не нужен):

   ```bash
   qemu-img convert -O raw vm/wdistr-build.vdi /tmp/opencode/wd.raw
   ```

   На выходе файл размером во весь виртуальный диск (64 ГБ), но разреженный —
   по факту занимает столько, сколько данных в госте.

2. Найти нужный раздел:

   ```bash
   fdisk -l /tmp/opencode/wd.raw
   ```

   Нас интересует `начало` в секторах (по 512 байт).

3. Вырезать раздел в отдельный файл (корень раздела = секторы / 2048, в MiB):

   ```bash
   dd if=/tmp/opencode/wd.raw of=/tmp/opencode/rootfs.img bs=1M skip=<MiB> conv=sparse
   ```

   `conv=sparse` — не раздувать пустые участки в ноль.

4. Читать содержимое без монтирования и без root — `debugfs`:

   ```bash
   debugfs -R "ls -l /root" /tmp/opencode/rootfs.img
   debugfs -R "dump /var/log/archinstall/install.log /куда/вывести" /tmp/opencode/rootfs.img
   ```

5. После извлечения временные образы удалить (`wd.raw`, `rootfs.img` — это
   десятки гигабайт).

## Где искать конфигурацию archinstall

- В **установленной** системе: `/var/log/archinstall/install.log` — там полный
  JSON-дамп ответов (блок `-- Chosen configuration --`); вырезать его и удалить
  префиксы `[дата] - DEBUG - `, затем проверить `python3 -m json.tool`.
- Кнопка «Save configuration» в archinstall пишет файлы в `/` **живой среды** —
  живая среда не сохраняется между перезагрузками, после `poweroff` файлы
  исчезают. Спастись может только лог установленной системы.
