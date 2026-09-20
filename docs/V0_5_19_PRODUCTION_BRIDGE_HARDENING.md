# v0.5.19 — укрепление production-моста Kozen

## Подтверждённый результат предыдущей транзакции

Read-only recovery `AOA_RECOVERY_JL22_KOZEN_20260914_134723.zip` завершился с `RECOVERY_OK`.

`getLastTransaction()` и независимый `getTransaction(receiptNumber=5)` вернули один и тот же результат:

```text
code=0
codePresent=false
approved=false
approvedPresent=true
message=Отказано
rc=99
rrn=625701636287
authCode=-
amount=1.00
currency=643
terminalId=12000679
receipt=5
transactionId=-
type=00
```

Это подтверждает, что staged-вызов оплаты и сохранённая история SmartSkyPOS согласованы. Результат является определённым отказом, а не неопределённым состоянием.

Поле `code` физически отсутствует в Bundle (`codePresent=false`). В восстановленном контракте SmartSkyPOS `TransactionResult.getCode()` использует `Bundle.getInt("code")`, поэтому при отсутствующем ключе нормализованное значение равно `0`. Старый диагностический sentinel `Integer.MIN_VALUE` больше не используется в production-мосте.

Согласно официальному документу SmartSkyPOS 1.9.8, `rc=99` означает общий ответ банка «Отказано». Это не ошибка USB/AOA и не ошибка Binder-транспорта.

## Изменения production-моста

В `kozenBridge` добавлен `ProductionBridgeService` версии протокола 4 / bridge 0.5.0.

Основные свойства:

- один `requestId` может вызвать `payment()` не более одного раза;
- автоматического повторного `PAYMENT` нет;
- перед оплатой повторно проверяются `getState()==READY(0)` и свежий `TerminalData`;
- допускается только существующий платёжный маршрут `type=00`, `transactionType=payment` и валюта `643`;
- сумма больше не зафиксирована на 1.00, но обязана быть положительной, не более 999999.99 и максимум с двумя знаками после запятой;
- `APPROVED` выдаётся только при `approved=true` и банковском `rc` из набора `00`, `000`, `001`, `007`;
- `approved=false` даёт финальное состояние `DECLINED`;
- отсутствующий/противоречивый признак одобрения даёт `UNCERTAIN`, при котором повтор оплаты запрещён до read-only recovery;
- в ответе явно передаются `codePresent` и `approvedPresent`;
- добавлены read-only команды `GET_LAST_TRANSACTION` и `GET_TRANSACTION`;
- PAN, имя держателя, EMV-поля и банковские слипы в read-only ответах не читаются и не передаются;
- экран Kozen показывает фактическую сумму запроса, а не жёстко заданные 1.00 ₽;
- диагностическое описание USB accessory больше не читает защищённый serial до выдачи Android-разрешения.

## Следующий безопасный тест

Перед подключением production-моста к основному `MainActivity` выполняется отдельный read-only аудит:

```bat
call AOA_17_PRODUCTION_BRIDGE_SAFE_AUDIT.bat 192.168.1.192:5555 192.168.31.134:5555 12000679
```

Этот сценарий устанавливает настоящий `kozenBridge`, но JL22-клиент аудита физически не содержит и не отправляет финансовых команд. Он выполняет только `PING`, `INFO`, `GET_STATE`, `GET_TERMINAL_DATA`, `GET_LAST_TRANSACTION` и `GET_TRANSACTION`.

После успешного аудита результат публикуется:

```bat
call GIT_106_PUBLISH_PRODUCTION_BRIDGE_AUDIT.bat
```

Только после успешного read-only аудита production-моста следует заменять в основном i-Retail UI текущий локальный имитатор оплаты на реальный AOA-клиент.
