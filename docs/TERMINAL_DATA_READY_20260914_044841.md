# SmartSkyPOS TerminalData через JL22 → USB/AOA → Kozen Bridge

Исходный прогон: `AOA_TERMINAL_DATA_JL22_KOZEN_20260914_044841.zip`.

Подтверждено на реальном Kozen P12:

```text
state=0
terminalId=12000679
merchantId=J500523
serial=P12240612000679
terminals=1
payment=true
paymentTid=12000679
paymentType=00
transactionType=payment
currencies=643
```

В журнале Kozen Bridge операция объявлена SmartSkyPOS как:

```text
name=Оплата
type=00
transactionType=payment
currencies=643
```

Следовательно, безопасные предварительные условия для контролируемого тестового вызова `payment()` на 1.00 RUB подтверждены. Финансовых операций в этом прогоне не выполнялось.

Следующий этап должен соблюдать fail-closed правила:

- новый платёж вызывается только после свежих `getState()==0` и `getTerminalData()`;
- TID и валюта берутся только из свежего TerminalData;
- один request ID соответствует не более чем одному вызову `payment()`;
- при неопределённом результате автоматического повторного платежа нет;
- `code=0` не означает одобрение: успех только при `approved=true`;
- журналы не содержат PAN/CVV/EMV или полные чеки.
