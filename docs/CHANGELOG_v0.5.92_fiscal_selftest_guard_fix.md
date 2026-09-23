# CHANGELOG v0.5.92 — fiscal self-test guard fix

Дата: 23.09.2026.

v0.5.91 был остановлен ложным срабатыванием исторического guard v0.5.81.

Причина: debug self-test добавил отдельный вызов FiscalGateway раньше боевого startRealCardPayment() в MainActivity.kt.

Исправление:
- исторический guard теперь анализирует только тело startRealCardPayment();
- проверяется реальный порядок markPaymentConfirmed() -> fiscalGateway.afterPaymentConfirmed(order);
- сам self-test и финансовая логика не изменены.
