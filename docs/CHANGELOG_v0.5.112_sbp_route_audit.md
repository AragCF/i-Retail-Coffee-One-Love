# CHANGELOG v0.5.112 — SBP route read-only audit

Дата: 24.09.2026.

Production bridge подготовлен к безопасной проверке маршрута СБП.

Bridge 0.5.3:
- добавлен Binder slot constant TX_QR_PAYMENT=19 исключительно как контрактная метаинформация;
- LIVE_QR_PAYMENT_ENABLED=false;
- AOA команда QR_PAYMENT всегда отвечает BLOCKED / LIVE_QR_PAYMENT_NOT_APPROVED и не вызывает SmartSkyPOS;
- добавлен GET_SBP_ROUTE;
- GET_SBP_ROUTE читает только TerminalData;
- точный маршрут: operation type 42 / transactionType qrPayment / currency 643;
- наружу выводится только tidPresent, а не TID.

JL22:
- KozenAoaPaymentClient совместим с bridge 0.5.2 и 0.5.3;
- на 0.5.2 readSbpRoute возвращает BRIDGE_UPGRADE_REQUIRED до отправки неизвестной команды;
- на 0.5.3 отправляется только GET_SBP_ROUTE;
- отдельный intent sbp_route_readonly_audit=true при realPos=false.

Windows:
- MAIN_32 автоматически обновляет bridge до 0.5.3, если Kozen доступен по ADB;
- если ADB недоступен, аудит безопасно работает со старым bridge и фиксирует BRIDGE_UPGRADE_REQUIRED;
- результат санитизируется и публикуется.

Живой qrPayment не разрешён и не вызывается.