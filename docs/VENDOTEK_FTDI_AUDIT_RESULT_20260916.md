# Vendotek VT — результат пассивного FTDI-аудита Windows

Дата: 16.09.2026  
Архив: `VENDOTEK_FTDI_AUDIT_20260916_191302.zip`

## Главный результат

Предыдущий прямой COM-тест был ошибочно запущен через `COM7`. Аудит установил, что `COM7` — это Bluetooth COM-порт Windows, а настоящий FTDI VCP терминала Vendotek — **`COM24`**.

### Vendotek FTDI

```text
USB Serial Port (COM24)
PNPDeviceID=FTDIBUS\VID_0403+PID_6001+A507YBKBA\0000
Status=OK
ConfigManagerErrorCode=0
REG.PortName=COM24
FTDI driver 2.12.36.20
oem91.inf
signed=true
```

Низкоуровневый USB-конвертер также виден штатно:

```text
USB Serial Converter
USB\VID_0403&PID_6001\A507YBKB
Status=OK
ConfigManagerErrorCode=0
```

### Что было COM7

```text
Standard Serial over Bluetooth link (COM7)
PNPDeviceID=BTHENUM\...
```

Именно поэтому предыдущая запись VTK IDL в `COM7` завершалась тайм-аутом: это был не интерфейс Vendotek.

## Вывод

Windows-драйвер FTDI для Vendotek установлен и устройство исправно перечисляется как `COM24`. Ошибка предыдущего прямого COM-теста не относится к Vendotek, VTK или FTDI — был выбран неверный COM-порт.

Следующий шаг: повторить прямой не финансовый VTK-тест `IDL + STATUS` строго через `COM24`.

## Безопасность

Пассивный аудит не записал в Vendotek ни одного байта. Финансовых команд не было.
