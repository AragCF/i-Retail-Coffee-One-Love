# CHANGELOG v0.5.114 — SBP wire sanitizer

Дата: 24.09.2026.

Подготовлен безопасный AOA-транспорт будущего СБП QR payload без вызова SmartSkyPOS qrPayment.

Bridge 0.5.5:
- Base64URL codec с лимитом raw payload 4096 байт;
- BridgeProtocolSanitizer редактирует payloadB64 / qrPayload / payload / qrIdB64 / qrId;
- все RX/TX строки моста проходят через санитайзер;
- добавлена synthetic-only команда SBP_ECHO_QR;
- команда принимает Base64URL payload, хранит его только в памяти и возвращает по AOA как SBP_QR;
- логирование ответа редактирует raw payload до записи;
- live QR Binder slot #19 всё ещё не вызывается.

JL22:
- симметричный Base64URL codec и WireProtocolSanitizer;
- RX_STALE тоже санитизируется;
- runSyntheticSbpWireRoundTrip() требует bridge 0.5.5;
- payload проверяется byte-for-byte после возврата;
- raw qrId/payload возвращаются только в память приложения;
- MainActivity сохраняет их в приватный SbpSessionStore;
- журнал содержит только hash/length.

Windows:
- MAIN_33 при доступном Kozen ADB сам ставит bridge 0.5.5;
- при старом bridge возвращает BRIDGE_UPGRADE_REQUIRED без обходов;
- приватный SharedPreferences сворачивается до hash/length и raw-копия удаляется ДО safety scan;
- отдельный Sanitize-SbpWireReport.ps1 блокирует публикацию raw payload.

Финансовых команд нет.