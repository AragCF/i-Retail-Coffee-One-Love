# CHANGELOG v0.5.112 — SBP adapter boundary

Дата: 24.09.2026.

S4 переведён с прямого управления dry-run-сессией на отдельную адаптерную границу.

Добавлено:
- `PaymentMethod.SBP` как отдельный способ оплаты;
- `SbpPaymentState` с состояниями QR_READY / WAITING_CONFIRMATION / CONFIRMED / DECLINED / UNCERTAIN / EXPIRED / CANCELLED / ERROR;
- `SbpPaymentSnapshot`;
- интерфейс `SbpPaymentAdapter`;
- `DryRunSbpPaymentAdapter` как единственная активная реализация;
- MainActivity зависит от интерфейса, а не от конкретной dry-run-сессии;
- `liveFinancialEnabled=false` является явным свойством активного адаптера;
- существующий v0.5.110 UI сохранён через совместимые typealias.

Безопасность:
- production SmartSkyPOS qrPayment всё ещё не вызывается;
- обычный `startPayment(SBP)` остаётся в общей блокировке non-card методов;
- dry-run не может выставить realPaymentSent=true;
- adapter boundary не зависит от SmartSkyPOS/Kozen classes.

Следующий слой: долговечное восстановление незавершённой СБП-сессии после restart.