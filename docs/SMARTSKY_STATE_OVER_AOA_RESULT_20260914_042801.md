# SmartSkyPOS getState через JL22 → USB/AOA → Kozen Bridge

Исходный прогон: `AOA_STATE_JL22_KOZEN_20260914_042801.zip`.

## Подтверждено

Полная сквозная цепочка чтения SmartSkyPOS работает:

```text
JL22 / Android 6
  -> USB host / Android Open Accessory
  -> Kozen P12 / i-Retail Kozen Bridge
  -> local Binder
  -> SmartSkyPOS
```

JL22 получил:

```text
AOA_PING_OK PONG 1001 bridge=0.1.0 manufacturer=Kozen model=P12 android=11 sdk=30
AOA_LINK_OK INFO 1002 protocol=1 transport=AOA role=kozen-payment-bridge bridge=0.2.0 smartsky=bound
GET_STATE_RX_MATCH reads=1 STATE 1003 code=0 state=0 bound=true descriptor=com.skytech.smartskyposlib.ISmartSkyPos
SMARTSKY_STATE_OVER_AOA_OK STATE 1003 code=0 state=0 bound=true descriptor=com.skytech.smartskyposlib.ISmartSkyPos
```

Со стороны Kozen подтверждено:

```text
RX GET_STATE 1003
SMARTSKY_GET_STATE_OK state=0 descriptor=com.skytech.smartskyposlib.ISmartSkyPos
TX STATE 1003 code=0 state=0 bound=true descriptor=com.skytech.smartskyposlib.ISmartSkyPos
```

SmartSkyPOS service реально связан с процессом `com.coffeeonelove.iretail.kozenbridge`.

## Вывод

Архитектурный путь `JL22 -> USB/AOA -> Kozen Bridge -> SmartSkyPOS Binder` подтвержден на реальном оборудовании.

Следующий безопасный шаг — через тот же канал вызвать только `getTerminalData()` (Binder transaction #4) и подтвердить TID, наличие операции `payment` / transaction type `00` и валюты `643` перед добавлением финансовой команды.

Финансовых операций в подтвержденном прогоне не было.
