# CHANGELOG v0.5.105 — Kozen bridge retrigger after AOA re-enumeration

Дата: 24.09.2026.

Живой тест v0.5.104 дошёл до controlled test UI, но preflight завершился:
`TEST_PREFLIGHT_FAILED code=TIMEOUT_PING noPaymentSent=true`.

Санитизированный отчёт подтвердил:
- тестовый режим и realPos=true в памяти были включены;
- PING был отправлен с JL22;
- ответа PONG не пришло;
- Kozen logcat после очистки оказался пустым;
- PAYMENT не отправлялся;
- одноразовый маркер не создавался;
- persisted real POS после выхода снова false.

Причина соответствует ранее уже встречавшемуся жизненному циклу AOA: первый запуск BridgeActivity происходит до того, как Kozen re-enumerated как USB accessory. В старом успешном production-аудите BridgeActivity повторно запускалась через несколько секунд после AOA-перехода.

Исправлено:
- на пятой итерации read-only preflight при доступном Kozen ADB повторно запускается только BridgeActivity;
- ProductionBridgeService 0.5.2 сохраняет собственную защиту от двойного активного AOA-сеанса;
- финансовых команд этот повторный запуск не отправляет;
- TEST_PREFLIGHT_FAILED / TEST_PREFLIGHT_TIMEOUT / TEST_SETUP_FAILED теперь валидируются как безопасные исходы без финансовой попытки;
- отсутствие marker-файла не вызывает шумную ошибку Wrong attempt contract marker.

Финансовый контракт не расширен: разрешена всё та же единственная реальная карточная операция на 1,00 ₽.