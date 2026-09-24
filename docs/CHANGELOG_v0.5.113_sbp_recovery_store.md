# CHANGELOG v0.5.113 — SBP recovery store

Дата: 24.09.2026.

Добавлен fail-closed recovery для СБП-сессии после process/app restart.

Долговечно сохраняются только:
- sessionId;
- state;
- amountMinor;
- generation;
- adapterId;
- realPaymentSent;
- updatedAt.

Намеренно НЕ сохраняются:
- qrId;
- qrPayload;
- платёжный токен.

Поведение:
- QR_READY / WAITING_CONFIRMATION после restart восстанавливаются как UNCERTAIN;
- realPaymentSent=true также всегда считается unresolved;
- при UNCERTAIN новый QR не создаётся;
- recovery probe не вызывает финансовых команд;
- очистка через diagnostic intent разрешена только dry-run adapter при liveFinancialEnabled=false.

MAIN_32_SBP_RESTART_RECOVERY_SMOKE.bat автоматически проверяет:
1. создание synthetic QR;
2. force-stop процесса;
3. восстановление UNCERTAIN;
4. отсутствие qrId/payload после restart;
5. отсутствие нового QR;
6. безопасную очистку dry-run store.