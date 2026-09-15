# Vendotek — первая попытка VTK IDL на JL22

Дата: 15.09.2026  
Архив: `VENDOTEK_IDL_20260915_060552.zip`  
Ветка: `v0.5.23-vendotek-discovery`

## Итог

Первая app-level попытка IDL завершилась `IDL_ERROR`, но **ни одного байта VTK в Vendotek фактически не было отправлено**.

Подтверждено до точки отказа:

```text
PROBE_BEGIN uid=10051 tty=/dev/ttyUSB0
VTK_CODEC_SELFTEST_OK documentedFrame=page8 crc=977e
TTY_FILE exists=true canRead=true canWrite=true
```

То есть:

- кодек VTK успешно воспроизводит эталонный IDL-кадр из VTK-MAN-RU 1.0;
- процесс i-Retail видит `/dev/ttyUSB0`;
- процесс i-Retail получает `canRead=true` и `canWrite=true`;
- ошибка произошла **до** `TTY_OPEN_OK` и **до** `IDL_TX`.

## Причина

Сбой возник при попытке процесса приложения выполнить:

```text
/sbin/busybox stty -F /dev/ttyUSB0 115200 raw ...
```

Android вернул `IOException: Error running exec()`.

Это не ответ Vendotek и не ошибка VTK. Терминал в этом прогоне не получил IDL, VRP, FIN, ABR, DIS или иной команды.

Ранее аппаратная диагностика установила, что:

- `/dev/ttyUSB0` имеет mode `0777`;
- SELinux отключён;
- JL22 имеет factory `/system/bin/su`;
- FTDI обслуживается kernel `ftdi_sio`.

Поэтому следующий диагностический вариант оставляет тот же `/dev/ttyUSB0`, но настраивает termios безопасной последовательностью: сначала прямой BusyBox, затем при невозможности запуска — bounded fallback через factory `su -c`. VTK IDL разрешается к записи только после успешной настройки `115200 8N1`.

## Безопасность

Обновлённый probe по-прежнему содержит только `IDL`. Финансовые сообщения `VRP`, `FIN`, `ABR`, `DIS` не отправляются. Автоматических повторов финансовых операций нет.
