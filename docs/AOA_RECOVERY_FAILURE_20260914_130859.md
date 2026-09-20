# AOA recovery — разбор сбоя 2026-09-14 13:08:59

Источник: `AOA_RECOVERY_JL22_KOZEN_20260914_130859.zip`.

## Что произошло

JL22 успешно увидел Kozen как AOA-устройство `18d1:2d01`, открыл BULK-канал и начал безопасный read-only recovery. Однако отдельное приложение `kozenRecoveryBridge` аварийно завершилось до выдачи USB accessory permission, поэтому JL22 не получил даже `PONG` и завершил прогон с `RECOVERY_PONG_TIMEOUT`.

Корневая причина — `RecoveryBridgeActivity.safeAccessory()` вызывал `UsbAccessory.getSerial()` до того, как Android 11 выдал новому приложению разрешение на accessory. На Kozen это приводит к `SecurityException: User has not given ... permission to accessory`.

## Исправление

В `RecoveryBridgeActivity` диагностическое описание accessory больше не читает защищённый serial до выдачи разрешения. Для журнала до разрешения используются только manufacturer/model/version. Версия recovery-приложения повышена до `0.1.1-read-only-recovery-permission-fix`.

Финансовых операций в этом прогоне не было. Recovery-мост по-прежнему содержит только read-only Binder-вызовы `getState`, `getLastTransaction` и `getTransaction`.

## Повторная проверка

```bat
call AOA_16_LAST_TRANSACTION_RECOVERY.bat 192.168.1.192:5555 192.168.31.134:5555 12000679
```

Если Kozen покажет системный запрос USB accessory permission, его нужно разрешить. Карта не требуется.
