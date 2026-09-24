# CHANGELOG v0.5.114 — SBP expiry and idempotency

Дата: 24.09.2026.

Добавлен срок жизни и идемпотентность СБП-сессии.

Правила:
- default TTL dry-run QR: 120 секунд;
- повторный start до TTL возвращает ту же sessionId/generation;
- current() переводит активную no-payment сессию в EXPIRED после TTL;
- confirmSynthetic после EXPIRED не может вернуть CONFIRMED;
- после EXPIRED может быть создана новая dry-run generation;
- persisted realPaymentSent=true никогда не превращается в EXPIRED — recovery остаётся UNCERTAIN;
- createdAtMs / expiresAtMs сохраняются долговечно;
- qrId / qrPayload по-прежнему не сохраняются.

MAIN_33_SBP_TTL_IDEMPOTENCY_SMOKE.bat автоматически проверяет все инварианты на JL22 без Kozen и без денег.