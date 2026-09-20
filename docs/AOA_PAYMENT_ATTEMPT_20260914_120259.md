# Результат контролируемой оплаты через JL22 → USB/AOA → Kozen → SmartSkyPOS

Источник: `AOA_PAYMENT_JL22_KOZEN_20260914_120259_pay-20260914115500.zip` из ветки `v0.5.16-payment-over-aoa`.

## Подтверждённый ход

- AOA канал открылся штатно: JL22 увидел Kozen как `18d1:2d01`.
- `PING/PONG`, `INFO`, `getState()` и `getTerminalData()` прошли успешно.
- Непосредственно перед финансовым вызовом подтверждено:
  - `state=0`;
  - `terminalId=12000679`;
  - `payment=true`;
  - `paymentType=00`;
  - `transactionType=payment`;
  - `currencies=643`.
- JL22 передал ровно одну команду `PAYMENT` с `requestId=pay-20260914115500`, суммой `1.00`, TID `12000679`, валютой `643`.
- Автоматического повтора не было.

## Результат SmartSkyPOS

SmartSkyPOS завершил вызов так:

```text
status=COMPLETED
code=302
approved=null
message=Превышен_таймаут_чтения_карты
rrn=-
authCode=-
amount=-
currency=-
terminalId=-
receipt=-
transactionId=-
```

На стороне Kozen зафиксировано:

```text
PAYMENT_CALL_RESULT requestId=pay-20260914115500 code=302 approved=null rrn=- receipt=- noAutoRetry=true
```

## Вывод

Платёжный вызов действительно дошёл до SmartSkyPOS и терминал около минуты ожидал чтения карты. Операция не была одобрена: `approved=true` отсутствует, RRN/чек не получены. Причина — тайм-аут чтения карты.

Это также объясняет отсутствие ожидаемого визуального подтверждения: финансовый вызов стартовал, но интерфейс Kozen не дал пользователю достаточно заметного приглашения приложить карту. Перед повторным тестом нужно использовать staged-сценарий v0.5.17 и сделать явную индикацию состояния на Kozen/Windows. Старый `AOA_14_PAYMENT_1_RUB_TEST.bat` больше не использовать.
