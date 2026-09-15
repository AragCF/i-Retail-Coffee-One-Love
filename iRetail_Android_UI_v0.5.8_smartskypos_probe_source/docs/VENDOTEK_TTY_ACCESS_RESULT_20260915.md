# Vendotek — результат проверки TTY-доступа на JL22

Дата: 15.09.2026  
Ветка: `v0.5.23-vendotek-discovery`  
Архив: `VENDOTEK_TTY_ACCESS_20260915_054938.zip`

## Подтверждённые факты

Vendotek остаётся подключён к JL22 как FTDI FT232R `0403:6001`, kernel driver `ftdi_sio`, character device `/dev/ttyUSB0`.

Фактические права устройства:

```text
crwxrwxrwx system system 188,0 /dev/ttyUSB0
mode=0777
SELinux=Disabled
context=unlabeled
```

JL22 работает с root ADB (`adb shell id` вернул `uid=0`), устройство имеет `ro.debuggable=1`; установлен `/system/bin/su`.

Текущая debug-сборка i-Retail имеет UID `10051` и доступна через `run-as`.

## Важная оговорка по run-as тесту

В архиве `run-as ... sh -c` проверки вернули `APP_EXISTS_RC=1`, `APP_READ_RC=1`, `APP_WRITE_RC=1`. Эти значения противоречат одновременно наблюдаемым условиям `mode=0777` и `SELinux=Disabled` и поэтому не рассматриваются как доказательство запрета доступа приложению.

Причина может быть в разборе аргументов `adb shell/run-as/sh -c` на старом Android 6. Окончательная проверка выполняется из самого процесса i-Retail: `File.exists/canRead/canWrite`, затем фактическое открытие tty приложением.

## Serial tooling

Отдельной команды `stty` в PATH нет, но присутствует `/sbin/busybox`. Следующий app-level probe использует BusyBox `stty` для установки обязательных параметров VTK `115200 8N1`, raw mode, no flow control, после чего сам процесс i-Retail открывает `/dev/ttyUSB0`.

## Следующий шаг

Подготовлен `VENDOTEK_03_IDL_SMOKE.bat`.

Он разрешает ровно одно протокольное сообщение — `IDL`. Перед отправкой встроенный VTK codec сверяет себя с опубликованным примером VTK-MAN-RU 1.0 (`20260127T084053+0300`, ожидаемый CRC `0x977E`).

Запрещены и отсутствуют в сценарии `VRP`, `FIN`, `ABR`, `DIS` и любые финансовые команды.
