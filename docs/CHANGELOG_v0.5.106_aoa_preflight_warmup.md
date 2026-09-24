# CHANGELOG v0.5.106 — AOA preflight warmup

Дата: 24.09.2026.

Санитизированный отчёт v0.5.105 дал точный код:
`PREFLIGHT_FAILED code=WRITE_INCOMPLETE_PING_-1 noPaymentSent=true`.

Это означает: JL22 уже открыл и захватил AOA bulk-интерфейс, но первая запись PING произошла раньше готовности accessory-side bridge на Kozen. Ошибка возникла примерно через 3 секунды, поэтому старый retrigger на пятой секунде не успевал выполниться.

Исправлено:
- read-only preflight повторяет транспортный прогрев максимум 6 раз;
- повторяются только PING/INFO и последующие read-only GET_STATE/GET_TERMINAL_DATA;
- `WRITE_INCOMPLETE_PING_*`, `TIMEOUT_PING`, `BAD_PONG` и родственные транспортные состояния считаются временно повторяемыми;
- между попытками 1200 мс;
- PAYMENT в preflight отсутствует;
- Windows поднимает BridgeActivity на 1-й, 3-й и 5-й секундах ожидания;
- Kozen logcat очищается до первоначального запуска BridgeActivity, а не после него, чтобы lifecycle-маркеры сохранялись.

Финансовый допуск не менялся: разрешена одна реальная операция на 1,00 ₽ только после успешного read-only preflight.