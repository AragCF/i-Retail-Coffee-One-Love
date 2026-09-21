# Приёмка S2 — живой каталог I-Retail на JL22

Дата: 21.09.2026  
Статус: **S2 принят, 6/6, 100%**.

## Доказательство

Источник:

`test_reports/s2_catalog_diagnostics/S2_DIAGNOSTICS_20260921_031840.zip`

Устройство:
- product: `octopus_jetinno`;
- model: `UniWin_M190`;
- device: `octopus-jetinno`;
- Android: `6.0.1`.

Установленная версия:
- versionCode: `46`;
- versionName: `0.5.46-s2-isrg-root-x1-compat`.

## TLS

Штатный Android 6 TrustManager не доверяет текущей цепочке I-Retail:

`admin.beta.i-retail.com → YR1 → Root YR → ISRG Root X1`.

Это подтверждено отдельным TLS-probe:

`SYSTEM_TRUST=FAIL`.

Совместимый контур v0.5.46:
- применяется только на API <= 23;
- применяется только к `my.i-retail.com`;
- сначала вызывает системный TrustManager;
- при системном отказе использует официальный `ISRG Root X1`;
- не отключает hostname verification;
- не включает trust-all.

Живой журнал подтвердил:

`LEGACY_ROOT_APPLIED host=my.i-retail.com api=23 root=ISRG_ROOT_X1`

`SYSTEM_TRUST_FAIL_EXTRA_ROOT_OK host=my.i-retail.com root=ISRG_ROOT_X1`

## Живой каталог

Критерий S2 выполнен:

`REFRESH success=true source=I-Retail ZIP products=8 offers=8 categories=2 channel=5676 failureStage=- failureReason=- failureDetail=-`

Итого:
- авторизация: успешно;
- TLS: успешно через ограниченную совместимость Android 6;
- ZIP-каталог: успешно;
- товаров: 8;
- предложений: 8;
- категорий: 2;
- ошибок каталога: нет.

## Статус этапов

- S0: закрыт;
- S1: закрыт;
- S2: **закрыт**;
- S3 DRY_RUN: закрыт;
- S3 серверная синхронизация/лояльность: продолжается.

По крупным контрактным этапам S0–S6 закрыто **3 из 7 = 43%**.

## Следующий безопасный шаг

Не включать реальную `iretail/order/synchronize`, пока не подтверждены по актуальной документации:
- reserve-order-id / id;
- employee_id;
- pin;
- точный формат тела;
- схема ответа;
- идемпотентность;
- повтор/восстановление статуса.

Следующий этап — аудит актуального серверного контракта S3.
