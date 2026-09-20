# SmartSkyPOS / Kozen P12 — план первого аппаратного запуска

## Этап A. Сборка и установка

Запустить:

`SMARTSKYPOS_01_BUILD_INSTALL.bat`

Ожидается установленный пакет:

`com.coffeeonelove.iretail`

и установленный SmartSkyPOS:

`com.skytech.smartskypos`, версия `1.9.19-RC.1.11057`.

## Этап B. Безопасная проверка без финансовой операции

Запустить:

`SMARTSKYPOS_02_SAFE_PROBE.bat`

Этот сценарий запускает диагностический экран с `allow_payment=false`.
В этом режиме `payment()` не может быть вызван через интерфейс.

Успешная последовательность в журнале:

- `BIND_OK`;
- `CALLBACK_REGISTERED`;
- `GET_STATE=0 (READY)`;
- `TERMINAL_DATA code=0`;
- `TERMINAL_DATA_OK`;
- `PAYMENT_GATE=OPEN_FOR_EXPLICIT_DIAGNOSTIC_CALL`.

Также должны появиться строки `TERMINAL ...` с реальными TID, операциями
и валютами.

### Стоп-условия

Если получено:

- `BIND_FAILED`;
- `CALLBACK_REGISTER_FAILED`;
- `GET_STATE_REMOTE_EXCEPTION`;
- `state=2 (UNFINISHED_OPERATION)`;
- `TerminalData.code != 0`;
- пустой список терминалов;

контролируемую оплату пока не запускать. Сначала передать журнал для разбора.

## Этап C. Контролируемая payment()

Только после успешного этапа B запустить:

`SMARTSKYPOS_03_CONTROLLED_PAYMENT.bat`

Сценарий спрашивает сумму и открывает диагностический экран с
`allow_payment=true`, однако сам `payment()` не вызывает.

На экране:

1. дождаться `Payment gate: OPEN`;
2. сверить автоматически подставленный `Terminal ID`;
3. сверить валюту с `TerminalData`;
4. нажать `КОНТРОЛИРУЕМАЯ TEST payment()`;
5. ещё раз проверить сумму/TID/валюту в диалоге;
6. вручную подтвердить вызов.

Повтор при ошибке автоматически не выполняется.

## Этап D. Сбор журнала

После проверки запустить:

`SMARTSKYPOS_04_COLLECT_LOGS.bat`

Передать созданную папку `smartskypos_logs/SmartSkyPOS_KozenP12_*`.

После подтверждения фактического результата мы можем переводить штатный
`PaymentMethod.CARD` в `MainActivity` на реальный SmartSkyPOS.
