# CHANGELOG v0.5.119 — настоящий СБП QR в альбомном режиме JL22

Дата: 25.09.2026.

## Фактическое наблюдение

На реальном JL22 версия 0.5.118:

- успешно восстановила ранее сохранённую DRY_RUN-сессию;
- не повторила Android 6 `NoClassDefFoundError`;
- вывела экран `PAYMENT_ONLINE_QR`;
- но в центре оставалась статическая заглушка `QR`.

После нажатия на эту область появился текст:

`Этот способ оплаты пока не подключён к подтверждаемому платёжному контуру`

и в журнале не появилось `DRY_RUN_QR_SCANNED`.

## Причина

`renderDynamicLayer()` при альбомной ориентации JL22 уходит в `renderLandscapeScreen()`.

Настоящий `SbpQrRenderer` ранее был добавлен только в портретный `renderPaymentProgressOverlay()`.

Кроме того, альбомные `PAYMENT_CASH / PAYMENT_ONLINE_QR / PAYMENT_ONLINE_CONFIRM` использовали один общий hotspot с `finishPayment()`, поэтому диагностический переход СБП не выполнялся.

## Исправление

Для альбомного интерфейса:

- `PAYMENT_ONLINE_QR + sbpDryRunMode` строит QR локально из `sbpDryRunSession.current()?.qrPayload`;
- QR выводится настоящим `ImageView`, а не надписью;
- область QR переводит DRY_RUN в `WAITING_CONFIRMATION`;
- сохраняется `DRY_RUN_QR_SCANNED`;
- `PAYMENT_ONLINE_CONFIRM` получает отдельный экран и область подтверждения;
- подтверждение сохраняет `DRY_RUN_CONFIRMED`;
- отмена остаётся отдельной идемпотентной ветвью;
- обычный неподключённый онлайн-платёж остаётся fail-closed.

## Безопасность

- `realPos=false`;
- реальный `qrPayment` не вызывается;
- Binder transaction 19 не вызывается;
- заказ не помечается PAID;
- FiscalGateway и кофемашина не вызываются;
- QR содержит только синтетический DRY_RUN payload.
