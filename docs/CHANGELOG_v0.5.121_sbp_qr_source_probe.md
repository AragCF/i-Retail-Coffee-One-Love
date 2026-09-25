# CHANGELOG v0.5.121 — подготовка живого источника СБП-QR

Дата: 25.09.2026.

## Исходная точка

Живой прогон v0.5.120 завершён успешно:

- `DRY_RUN_QR_READY`;
- `DRY_RUN_QR_SCANNED`;
- `DRY_RUN_CONFIRMED`;
- `DRY_RUN_CONFIRM_INVARIANTS runtimeOrderPaid=false fiscalCalled=false machineCalled=false realQrPaymentSent=false`;
- `Outcome: DRY_RUN_OK`.

Следующий рубеж — получить QR не из синтетического payload, а из реального `SmartSkyPOS qrPayment`.

## Что подготовлено

### Kozen Bridge 0.5.7

Добавлен отдельный контролируемый путь будущей генерации QR:

- команда `START_SBP_QR_PROBE`;
- команда только чтения `GET_SBP_PROBE_STATUS`;
- строгая сумма 1,00 ₽;
- валюта 643;
- свежий маршрут `42/qrPayment`;
- обязательный одноразовый requestId;
- состояние STARTED сохраняется до Binder-вызова;
- Binder transaction #19 запускается в отдельном рабочем потоке;
- AOA-поток остаётся свободен для `GET_SBP_QR_EVENT`;
- callback `onQrReading` по-прежнему проходит через очередь `QR_EVENT_PEEK_ACK_V1`;
- raw qrId/payload не журналируются.

### JL22

Клиент умеет:

- различать отдельный незавершённый СБП-пробник;
- не отправлять второй вызов при неопределённом предыдущем;
- читать настоящий callback QR;
- принимать только источник `smartsky-callback`;
- проверять hash/length;
- показывать живой QR на JL22 с предупреждением «НЕ СКАНИРОВАТЬ»;
- не считать этот факт оплатой.

### Экран Kozen

Bridge UI 0.5.7 умеет показывать состояние пробы и факт получения callback QR без вывода сырого payload.

## Предохранитель

В этом выпуске реальный вызов намеренно не вооружён:

- `LIVE_QR_PAYMENT_ENABLED=false`;
- `LIVE_QR_GENERATION_PROBE_ENABLED=false` на Kozen;
- `LIVE_QR_GENERATION_PROBE_ENABLED=false` на JL22.

Обычный `QR_PAYMENT` остаётся заблокирован.

## Разрешённый живой шаг

`MAIN_36_SBP_QR_SOURCE_PREFLIGHT.bat` выполняет только read-only:

- обновляет приложения до 0.5.121 / Bridge 0.5.7;
- держит `real_pos=false`;
- проверяет PING/INFO/state/TerminalData/GET_SBP_ROUTE;
- требует `42/qrPayment/643`;
- требует `liveEnabled=false`;
- требует `probeEnabled=false`.

Финансовой операции preflight не создаёт.
