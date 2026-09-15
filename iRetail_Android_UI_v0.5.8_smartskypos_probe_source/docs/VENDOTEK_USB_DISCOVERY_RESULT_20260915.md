# Vendotek — результат аппаратного USB-обнаружения на JL22

Дата: 15.09.2026  
Ветка: `v0.5.23-vendotek-discovery`  
Архив испытания: `VENDOTEK_USB_DISCOVERY_20260915_054045.zip`

## 1. Что подтверждено на реальном оборудовании

Vendotek физически подключён к USB Host кофе-машины JL22 и определяется Linux-ядром Android 6 как стандартный преобразователь FTDI FT232R USB UART.

Фактические параметры:

```text
VID:PID       0403:6001
Manufacturer  FTDI
Product       FT232R USB UART
Serial        A10LV1PB
USB speed     12 Mbit/s (full-speed)
Device class  00/00/00
Interface     ff/ff/ff
Kernel driver ftdi_sio
TTY           /dev/ttyUSB0
Bulk IN       0x81
Bulk OUT      0x02
MaxPacket     0x0040 (64 bytes)
```

Ядро JL22 регистрирует устройство однозначно:

```text
usb 1-1.4: New USB device found, idVendor=0403, idProduct=6001
usb 1-1.4: Product: FT232R USB UART
usb 1-1.4: Manufacturer: FTDI
usb 1-1.4: SerialNumber: A10LV1PB
ftdi_sio 1-1.4:1.0: FTDI USB Serial Device converter detected
usb 1-1.4: Detected FT232RL
usb 1-1.4: FTDI USB Serial Device converter now attached to ttyUSB0
```

Следовательно, первоначальная гипотеза о USB virtual COM подтверждена аппаратно. Для данного экземпляра Vendotek не требуется угадывать CDC ACM, CH340 или PL2303: транспорт — FTDI FT232R.

## 2. Что это означает для архитектуры i-Retail

На уровне VTK кофе-машина выступает VMC, Vendotek — POS. Для последовательного транспорта применяются требования VTK:

- 115200 бит/с;
- 8N1;
- без управления потоком;
- стартовый байт `0x1F`;
- длина big-endian;
- discriminator `0x96FB` от VMC к POS и `0x97FB` от POS к VMC;
- BER-TLV полезная нагрузка;
- CRC16-CCITT, начальное значение `0xFFFF`, передача big-endian;
- оставшиеся байты кадра после первого байта должны быть получены в пределах 8 секунд.

Первый рабочий протокольный шаг — не платёж, а `IDL`: после питания VMC начинает отправлять IDL, POS отвечает IDL, после чего обе стороны переходят из INACTIVE в IDLE.

## 3. Почему мы пока не отправляем IDL

Наличие `/dev/ttyUSB0` ещё не доказывает, что обычный APK `com.coffeeonelove.iretail` имеет Linux/SELinux-права на открытие этого character device и настройку termios.

Перед первой записью в Vendotek необходимо проверить:

- владельца, группу, mode и SELinux context `/dev/ttyUSB0`;
- effective uid/gid `adb shell`;
- uid приложения i-Retail;
- доступность `run-as` для debug-сборки;
- эффективные read/write права приложения на `/dev/ttyUSB0`;
- наличие `stty`/serial tooling в Android 6;
- наличие иных процессов, удерживающих tty;
- режим SELinux.

Эта проверка не открывает финансовой операции и не отправляет байты VTK.

## 4. Следующий этап

Следующий сценарий: `VENDOTEK_02_TTY_ACCESS_PROBE.bat`.

Если приложение может безопасно работать с `/dev/ttyUSB0`, дальнейший IDL-probe будет построен поверх kernel `ftdi_sio`. Если обычному APK доступ запрещён, транспорт будет реализован через Android USB Host с прямой работой с FTDI-интерфейсом и `claimInterface(..., true)`, без зависимости от права приложения на `/dev/ttyUSB0`.

После выбора транспорта первым сообщением станет только IDL. `VRP`, `FIN`, `ABR`, `DIS` и любые финансовые команды до успешного IDL/SystemInfo этапа не отправляются.
