# S4 — СБП через Kozen / SmartSkyPOS: безопасный контракт реализации

Версия: 0.1.0  
Дата: 24.09.2026  
Статус: **IMPLEMENTATION_SAFE_SCOPE_APPROVED_BY_EXISTING_ROADMAP / LIVE_PAYMENT_NOT_APPROVED**

## 1. Цель

Подготовить независимый от карточного acquiring-контур СБП:

`i-Retail UI → JL22 → USB/AOA → Kozen production bridge → SmartSkyPOS qrPayment → QR payload → i-Retail QR screen → final result`

## 2. Уже подтверждённые источники

Текущий восстановленный SmartSkyPOS Binder ABI:
- `qrPayment` — Binder transaction #19;
- `qrRefund` — #23;
- `qrCancel` — #41;
- callback `TransactionCallback.onQrReading(qrId, qrPayload)`;
- `TransactionParams` содержит `payload`, `payloadType`, `QR_id`, `QR_type`.

TerminalData исторически объявлял:
- `Оплата СБП`;
- operation type `42`;
- transactionType `qrPayment`;
- currency `643`.

В UI уже существуют:
- `PAYMENT_ONLINE_QR`;
- `PAYMENT_ONLINE_CONFIRM`.

## 3. Разрешённый безопасный объём

Можно без нового финансового разрешения:
- добавить отдельный SBP adapter boundary;
- реализовать модели состояния QR;
- реализовать обработку `onQrReading`;
- хранить correlation/request id;
- реализовать идемпотентность и восстановление;
- показать QR payload в диагностическом режиме или через безопасный QR renderer;
- добавить dry-run / synthetic callbacks;
- добавить guards и тесты;
- добавить read-only проверку наличия operation type=42;
- не вызывать реальный `qrPayment`.

## 4. Запрещено без отдельного явного разрешения

- живой `qrPayment`;
- живой `qrRefund`;
- `qrCancel` реальной операции;
- автоматический повтор QR-платежа;
- использование новой суммы/транзакции для проверки;
- публикация чувствительного QR payload, если он содержит платёжный токен.

## 5. Архитектурные требования

- карточная оплата и СБП — разные adapters/state machines;
- общий `RuntimeOrder` получает PAID только после достоверного final success;
- QR callback не равен факту оплаты;
- генерированный QR должен иметь ограниченный срок жизни;
- повторное открытие экрана не создаёт новую финансовую операцию;
- после restart сначала recovery/status, а не новая операция;
- реальный SBP выключен по умолчанию;
- persisted safety state должен оставаться fail-closed.

## 6. Первый технический этап

1. Зафиксировать точный TerminalData route type=42.
2. Добавить `SbpPaymentClient`/boundary без финансового вызова.
3. Добавить synthetic QR event.
4. Связать `PAYMENT_ONLINE_QR` с моделью QR-состояния.
5. Добавить sanitization для qrId/payload.
6. Добавить CI guard: production `qrPayment` не вызывается из dry-run.
7. Выпустить отдельный безопасный smoke-test без денег.

## 7. Условие живого теста

Живой СБП-тест оформляется отдельным финансовым контрактом и требует явного разрешения пользователя.
