# CHANGELOG v0.5.99 — controlled payment without Kozen Windows ADB

Дата: 23.09.2026.

Исправлен сценарий единственной разрешённой оплаты на 1 ₽.

Причина:
- Kozen физически работает с JL22 по USB/AOA;
- Windows ADB к Kozen может отсутствовать;
- v0.5.98 ошибочно считал Windows ADB обязательным и останавливался до теста.

Изменено:
- Windows ADB к Kozen теперь необязателен;
- если ADB доступен, текущий bridge 0.5.2 собирается и обновляется на Kozen;
- если ADB недоступен, используется уже установленный bridge;
- перед показом разрешения на оплату основной KozenAoaPaymentClient выполняет read-only preflight по тому же AOA-сеансу;
- preflight отправляет только PING, INFO, GET_STATE и GET_TERMINAL_DATA;
- требуется bridge=0.5.2, protocol=4 и paymentPolicy=EXPLICIT_SINGLE_NO_AUTO_RETRY;
- успешный AOA-сеанс остаётся открытым и переиспользуется для последующей единственной оплаты;
- при провале preflight платёжный маркер не создаётся и разрешённая попытка остаётся неиспользованной.

Финансовый контракт S3_FISCAL_POSITIVE_PAYMENT_CONTRACT_v1.0.1 не расширен и не изменён.
