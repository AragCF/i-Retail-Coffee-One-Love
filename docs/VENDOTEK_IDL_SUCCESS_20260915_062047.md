# Vendotek — подтверждённый VTK IDL по FTDI на JL22

Дата: 15.09.2026  
Ветка-источник испытания: `v0.5.23-vendotek-discovery`  
Архив: `VENDOTEK_IDL_20260915_062047.zip`

## Итог

Первый реальный двусторонний обмен VTK между JL22 и Vendotek подтверждён на стенде.

Цепочка:

```text
JL22 Android 6
→ kernel ftdi_sio
→ /dev/ttyUSB0
→ FTDI FT232R 0403:6001
→ Vendotek
→ VTK response
```

Фактический запрос от JL22:

```text
IDL_TX localTime=20260915T062045+0300
1f001d96fb010349444c11143230323630393135543036323034352b30333030e1a2
```

Фактический ответ Vendotek:

```text
1f000a97fb010349444c030130d90c
```

Разбор ответа:

```text
discriminator=0x97FB
crcOk=true
message=IDL
operation=0
```

Итоговый маркер приложения:

```text
VTK_IDL_OK operation=0 keepalive=-
```

Следовательно, подтверждены одновременно:

- физическая USB-линия;
- FTDI FT232R;
- kernel driver `ftdi_sio`;
- `/dev/ttyUSB0`;
- настройка порта `115200 8N1`;
- VTK framing;
- BER-TLV;
- направления `0x96FB`/`0x97FB`;
- CRC16-CCITT;
- передача `LocalTime`;
- реальный ответ POS на IDL.

## Особенность JL22

`/sbin/busybox` нельзя непосредственно выполнить из UID приложения, однако factory `/system/bin/su` позволяет диагностическому клиенту настроить termios. В успешном прогоне:

```text
SERIAL_CONFIG_DIRECT_FULL rc=-126
SERIAL_CONFIG_DIRECT_FALLBACK rc=-126
SERIAL_CONFIG_ROOT_FULL rc=0
SERIAL_CONFIG rc=0 detail=root-full
TTY_OPEN_OK uid=10051
```

Это допустимо как средство аппаратно-протокольной верификации. Для окончательного промышленного транспортного слоя зависимость от внешнего запуска BusyBox/root должна быть устранена или изолирована.

## Финансовая безопасность

Успешный тест отправил только один `IDL`. `VRP`, `FIN`, `ABR`, `DIS` и другие финансовые/операционные команды отсутствовали.

## Следующий безопасный этап

Ветка `v0.5.24-vendotek-system-info` выполняет только read-only System Information запросы согласно VTK-MAN-RU 1.0 section 3.2.3:

- `STATUS`;
- `POS_PARAMS`;
- `BANK_PARAMS`;
- `NET_PARAMS`.

Каждый запрос передаётся как `IDL + LocalTime + SystemInformation(12h)`, с интервалом не менее 10 секунд между IDL-сообщениями. Продажа `VRP` на этом этапе запрещена.
