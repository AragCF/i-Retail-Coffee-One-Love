# i-Retail — анализ USB-транспорта JL22 ↔ Kozen P12

Дата: 2026-09-14

## Исходные диагностические архивы

- `USB_JL22_ANDROID6_20260914_001319.zip`
- `USB_KOZEN_P12_20260906_005050.zip`

## JL22

- Производитель/модель: UniWin / UniWin M190.
- Android 6.0.1, API 23.
- Платформа: Allwinner `sun8i`, board `octopus`.
- Android объявляет одновременно `android.hardware.usb.host` и `android.hardware.usb.accessory`.
- Текущий gadget-режим диагностического/ADB-порта: `mtp,adb`.
- Legacy Android USB gadget активен (`/sys/class/android_usb/android0`), VID:PID `1f3a:1007`.
- `dumpsys usb` одновременно показывает активный USB Host и устройство `Realtek USB 10/100 LAN` (`0bda:8152`). Это фактически подтверждает, что JL22 способен работать USB-host одновременно с собственным gadget/ADB-подключением к Windows.
- Ethernet `eth0` активен.

## Kozen P12

- Производитель/модель: Kozen / P12.
- Android 11, API 30.
- SoC/платформа: MediaTek MT6761.
- Android объявляет `android.hardware.usb.host` и `android.hardware.usb.accessory`.
- При диагностике через Windows Kozen находился в USB device/UFP роли: `supported_modes=ufp`, `current_mode=ufp`, `data_role=device`, `power_role=sink`.
- Роль данного порта через Android USB Port Manager не переключается: `can_change_mode=false`, `can_change_power_role=false`, `can_change_data_role=false`.
- Текущая gadget-функция при ADB: `sys.usb.config=adb`.
- `svc usb` сообщает поддержку стандартных функций `mtp`, `ptp`, `rndis`, `midi`, однако их программное переключение из обычного приложения не следует считать доступным без отдельной проверки привилегий.

## Вывод по физической топологии

Предпочтительная и совместимая схема:

`JL22 USB HOST -> Kozen P12 USB DEVICE/UFP`

Kozen не следует назначать USB-host для этого соединения. JL22 уже доказанно работает как USB-host, а порт Kozen, использовавшийся для ADB с Windows, работает как UFP/device.

## Предпочтительный прикладной транспорт

Основной кандидат — Android Open Accessory (AOA):

1. JL22 остаётся USB-host.
2. Приложение i-Retail на JL22 обнаруживает Kozen как USB device.
3. JL22 выполняет стандартное AOA-согласование по control endpoint.
4. Kozen переопределяется как Android Accessory device.
5. Небольшое служебное приложение `i-Retail Payment Bridge` на Kozen получает USB accessory stream.
6. Bridge локально обращается к SmartSkyPOS через уже восстановленный Binder/AIDL-контракт.
7. Ответ по операции возвращается в i-Retail UI на JL22 по тому же USB accessory stream.

Преимущества: не требуется переносить i-Retail UI на Kozen, Binder остаётся локальным для Kozen, не требуется root, не требуется постоянная IP-сеть между устройствами, финансовая операция может иметь строгий request/response протокол и защиту от повторной отправки.

RNDIS рассматривается как запасной транспорт, но не как первый выбор: он требует управляемого переключения gadget-функции Kozen и сетевой конфигурации, что сложнее и потенциально зависит от системных привилегий.

## Следующий испытательный шаг

Перед реализацией AOA-моста необходимо подтвердить реальное USB-перечисление Kozen на физическом USB HOST-порту JL22. Для этого добавлен полностью read-only сценарий:

`USB_08_LIVE_LINK_PROBE.bat`

Сценарий снимает состояние JL22 до подключения Kozen, делает паузу для физического подключения, затем снимает состояние после подключения и формирует ZIP с разницей USB/sysfs/network/device state.
