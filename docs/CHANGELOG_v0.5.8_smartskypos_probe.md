# i-Retail Android UI v0.5.8 — SmartSkyPOS / Kozen P12

## Цель

Подключить к текущему i-Retail восстановленный Binder/AIDL-контракт SmartSkyPOS
`1.9.19-RC.1.11057` и подготовить безопасную аппаратную проверку до перевода
штатной кнопки банковской карты на реальный эквайринг.

## Что добавлено

- Полный восстановленный AIDL-контракт `com.skytech.smartskyposlib`.
- Bundle-backed Parcelable-классы из Integration Kit.
- `SmartSkyPosConnector`.
- `SmartSkyPosGateway` с fail-closed логикой.
- `SmartSkyPosDiagnosticActivity`, не входящая в launcher.
- `buildFeatures.aidl = true`.
- Package visibility для `com.skytech.smartskypos`.
- Windows-сценарии:
  - `SMARTSKYPOS_01_BUILD_INSTALL.bat`;
  - `SMARTSKYPOS_02_SAFE_PROBE.bat`;
  - `SMARTSKYPOS_03_CONTROLLED_PAYMENT.bat`;
  - `SMARTSKYPOS_04_COLLECT_LOGS.bat`.

## Безопасная последовательность

1. `bindService()` к `com.crestwavetech.smartskyposservice.SmartSkyPosService`.
2. `ISmartSkyPos.Stub.asInterface()`.
3. `registerStateCallback()`.
4. `getState()`.
5. Только при `READY(0)` — `getTerminalData()`.
6. Только при `TerminalData.code == 0` и наличии терминалов — открытие внутреннего payment gate.
7. `payment()` доступен только в отдельном диагностическом режиме, после ручного подтверждения.

`UNFINISHED_OPERATION(2)` закрывает payment gate. Автоматического повторного
вызова `payment()` при неопределённом результате нет.

## Что намеренно не изменено

Штатная кнопка «Банковская карта» в `MainActivity` пока не вызывает SmartSkyPOS.
Это будет сделано после фактического журнала безопасной проверки на Kozen P12.

Так мы не смешиваем два этапа:

- проверку Binder-контракта;
- реальный пользовательский платёжный сценарий.

## Защита журналов

Диагностический слой не выводит:

- PAN;
- CVV;
- срок действия карты;
- cardholder;
- EMV/CVM-блоки;
- содержимое чеков;
- QR payload.

Для результата оплаты сохраняются только технически необходимые безопасные поля:
`code`, `approved`, `message`, `RRN`, `authCode`, сумма, валюта, TID,
номер чека и идентификатор транзакции.

## Ограничение сборочной проверки

В среде подготовки архива доступны JDK/Javac, но отсутствуют Android SDK,
Gradle и Kotlin compiler. Поэтому полноценный `assembleDebug` здесь не запускался.
Архив содержит Windows-сценарий штатной сборки на рабочей машине.
