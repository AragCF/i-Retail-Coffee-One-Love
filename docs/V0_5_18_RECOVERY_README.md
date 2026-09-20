# v0.5.18 — read-only recovery через AOA

Этот этап предназначен только для сверки последней транзакции SmartSkyPOS после завершённой/отклонённой операции.

Запуск под Windows:

```bat
call AOA_16_LAST_TRANSACTION_RECOVERY.bat 192.168.1.192:5555 192.168.31.134:5555 12000679
```

Пакет использует отдельные приложения `jl22AoaRecovery` и `kozenRecoveryBridge`. В recovery-мосте отсутствуют Binder-коды `payment`, `cancel`, `refund`, `reconciliation` и `report`: доступны только `getState`, `getLastTransaction` и `getTransaction`.

В журнал возвращаются только безопасные поля результата (`code`, `approved`, `message`, `rc`, `RRN`, `authCode`, сумма, валюта, TID, номер чека, id, тип). PAN, имя держателя, EMV-поля и тексты чеков намеренно не читаются и не передаются.

После завершения результат публикуется командой:

```bat
call GIT_105_PUBLISH_AOA_RECOVERY_RESULT.bat
```
