# CHANGELOG v0.5.111 — SBP route read-only contract

Дата: 24.09.2026.

Продолжение S4 / СБП после безопасного UI dry-run.

Добавлено:
- Kozen production bridge 0.5.3;
- generic route lookup по SmartSkyPOS TerminalData;
- сохранён карточный маршрут 00/payment;
- отдельно определяется СБП 42/qrPayment;
- GET_TERMINAL_DATA read-only ответ содержит qrPayment / qrPaymentTid / qrPaymentType / qrTransactionType / qrCurrencies;
- JL22-клиент совместим с bridge 0.5.2 и 0.5.3;
- bridge 0.5.2 честно классифицируется как LEGACY_BRIDGE_NO_SBP_ROUTE_FIELDS;
- MainActivity проверяет exactRoute = type 42 + qrPayment + currency 643 + TID;
- MAIN_31_SBP_ROUTE_READONLY_AUDIT.bat обновляет Kozen bridge только при доступном ADB; иначе ничего на Kozen не меняет.

Не добавлено и запрещено:
- вызов SmartSkyPOS qrPayment;
- QR refund/cancel;
- перевод RuntimeOrder в PAID;
- любые финансовые повторы.