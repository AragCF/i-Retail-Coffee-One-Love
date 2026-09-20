# SmartSkyPOS / Kozen P12 — результат исследования

## Итог

На исследованном Kozen P12 установлен и запущен **SmartSkyPOS**:

- пакет: `com.skytech.smartskypos`
- версия: `1.9.19-RC.1.11057`
- versionCode: `11057`
- устройство: `Kozen P12`
- Android: `11` / API 30
- ABI: `arm64-v8a`
- служба: `com.crestwavetech.smartskyposservice.SmartSkyPosService`
- служба экспортирована: `android:exported="true"`
- Intent action для привязки: `com.skytech.smartskypos.ISmartSkyPos`
- Binder descriptor: `com.skytech.smartskyposlib.ISmartSkyPos`

APK содержит Kozen-специфичные реализации `SdkKozen`, `EmvProcessorKozen`, `PinPadModuleKozen`, `SecurityModuleKozen`, `PrinterKozen` и другие. Следовательно, это нужная сборка SmartSkyPOS для аппаратной платформы P12.

## Что произошло с AAR

Физического `.aar` на терминале нет. Это ожидаемо: библиотека была включена в APK на этапе сборки. Но внутри `classes2.dex` полностью сохранился клиентский Binder-контракт `com.skytech.smartskyposlib` — без существенной обфускации.

Удалось восстановить:

- `ISmartSkyPos`
- `TransactionCallback`
- `StateCallback`
- `TransactionParams` / `TransactionResult`
- `ReconciliationParams` / `ReconciliationResult`
- `ServiceParams` / `ServiceResult`
- `ReportResult`
- `TerminalData`, `Terminal`, `Operation`, `Currency`
- точные номера Binder-транзакций
- ключи Bundle для Parcelable-объектов
- способ сериализации Parcelable: `Parcel.writeBundle()` / `Parcel.readBundle()`.

Это означает, что для технической интеграции официальный AAR **не является блокирующей зависимостью**. Официальный SDK всё равно желательно получить для поддержки и формальной совместимости, но работоспособный клиент можно собрать из восстановленного контракта.

## Binder-транзакции `ISmartSkyPos`

| Код | Метод | Возвращает | Параметры |
|---:|---|---|---|
| 1 | `getState` | `int` | `` |
| 2 | `registerStateCallback` | `void` | `StateCallback` |
| 3 | `unregisterStateCallback` | `void` | `StateCallback` |
| 4 | `getTerminalData` | `TerminalData` | `` |
| 5 | `payment` | `TransactionResult` | `TransactionParams, TransactionCallback` |
| 6 | `cancel` | `TransactionResult` | `TransactionParams, TransactionCallback` |
| 7 | `cancelLast` | `TransactionResult` | `TransactionParams, TransactionCallback` |
| 8 | `refund` | `TransactionResult` | `TransactionParams, TransactionCallback` |
| 9 | `initialization` | `ServiceResult` | `` |
| 10 | `activation` | `ServiceResult` | `` |
| 11 | `testHostConnection` | `ServiceResult` | `ServiceParams` |
| 12 | `cancelCardReading` | `boolean` | `` |
| 13 | `reconciliation` | `ReconciliationResult` | `ReconciliationParams` |
| 14 | `report` | `ReportResult` | `` |
| 15 | `fullReport` | `ReportResult` | `` |
| 16 | `serviceMenu` | `ServiceResult` | `` |
| 17 | `preAuth` | `TransactionResult` | `TransactionParams, TransactionCallback` |
| 18 | `preAuthConfirm` | `TransactionResult` | `TransactionParams, TransactionCallback` |
| 19 | `qrPayment` | `TransactionResult` | `TransactionParams, TransactionCallback` |
| 20 | `getLastTransaction` | `TransactionResult` | `TransactionParams` |
| 21 | `getTransaction` | `TransactionResult` | `TransactionParams` |
| 22 | `ecomPayment` | `TransactionResult` | `TransactionParams, TransactionCallback` |
| 23 | `qrRefund` | `TransactionResult` | `TransactionParams, TransactionCallback` |
| 24 | `b2cCardTransfer` | `TransactionResult` | `TransactionParams, TransactionCallback` |
| 25 | `readCardDetails` | `TransactionResult` | `TransactionParams, TransactionCallback` |
| 26 | `ecPurchase` | `TransactionResult` | `TransactionParams, TransactionCallback` |
| 27 | `ecRefund` | `TransactionResult` | `TransactionParams, TransactionCallback` |
| 28 | `balance` | `TransactionResult` | `TransactionParams, TransactionCallback` |
| 29 | `cashIn` | `TransactionResult` | `TransactionParams, TransactionCallback` |
| 30 | `cashOut` | `TransactionResult` | `TransactionParams, TransactionCallback` |
| 31 | `[reserved]` | `` | `` |
| 32 | `[reserved]` | `` | `` |
| 33 | `setPin` | `TransactionResult` | `TransactionParams, TransactionCallback` |
| 34 | `changePin` | `TransactionResult` | `TransactionParams, TransactionCallback` |
| 35 | `purchaseWithCashback` | `TransactionResult` | `TransactionParams, TransactionCallback` |
| 36 | `unreferencedRefund` | `TransactionResult` | `TransactionParams, TransactionCallback` |
| 37 | `preAuthCancel` | `TransactionResult` | `TransactionParams, TransactionCallback` |
| 38 | `payerDetails` | `TransactionResult` | `TransactionParams, TransactionCallback` |
| 39 | `preAuthIncrement` | `TransactionResult` | `TransactionParams, TransactionCallback` |
| 40 | `[reserved]` | `` | `` |
| 41 | `qrCancel` | `TransactionResult` | `TransactionParams, TransactionCallback` |

Пропуски 31, 32 и 40 существуют в самом APK. В восстановленном `.aidl` добавлены резервные методы, чтобы AIDL-компилятор сохранил точные номера всех последующих транзакций. Эти резервные методы вызывать нельзя.

## Callback

`TransactionCallback`:

- #1 `onStateChanged(int, String)`
- #2 `onQrReading(String, String)`
- #3 — резервный слот
- #4 `onOperationNameChanged(String)`
- #5 `onRequestPassword(String) -> String`

`StateCallback`:

- #1 `onStateChanged(int, String)`

## Наиболее важные поля `TransactionParams`

`TransactionParams` является Bundle-backed Parcelable. Среди восстановленных ключей:

- `amount` — `BigDecimal`, хранится через `Bundle.putSerializable`
- `currencyCode`
- `terminalId`
- `receiptNumber`
- `rrn`
- `referenceNumber`
- `transactionType`
- `id`
- `extraTransactionData`
- `cashbackAmount`
- `ecAmount`
- `phoneNumber`
- `payload`, `payloadType`
- `QR_id`, `QR_type`
- `pan`, `expiryDate`, `cvv`

Конструктор по умолчанию формирует `id` как первые 8 символов случайного UUID — это также воспроизведено в восстановленном классе.

## Рекомендуемый порядок проверки

1. Подключить восстановленный AIDL-контракт к приложению.
2. Привязаться к экспортированной `SmartSkyPosService`.
3. Выполнить только `getState()`.
4. Выполнить `getTerminalData()` и зафиксировать TID/MID/доступные операции.
5. Зарегистрировать `StateCallback` и проверить события состояния.
6. После этого проводить контролируемую тестовую оплату на тестовом/разрешённом контуре.
7. Возврат, отмену и сверку добавлять после фиксации фактического результата оплаты и чековых данных.

## Ограничение восстановления

Это **восстановленный по установленному APK контракт**, а не официальный SDK поставщика. Сигнатуры, Binder-коды, имена классов, Bundle-ключи и способ parceling взяты непосредственно из установленной версии SmartSkyPOS 1.9.19-RC.1.11057. Документационные требования поставщика, бизнес-ограничения отдельных операций и гарантии совместимости с другими версиями APK всё ещё следует сверить с официальным SDK/документацией.
