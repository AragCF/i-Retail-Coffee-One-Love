# Отчёт реализации v0.5.43 — JL22 SSL diagnostics

Дата: 20.09.2026

## Основание

Живой отчёт v0.5.42 подтвердил:
- JL22 = Android 6.0.1;
- DNS работает;
- host my.i-retail.com доступен;
- proxy отсутствует;
- отказ происходит на этапе authentication;
- причина — SSL.

Windows/curl с тем же API-контрактом получает HTTP 200, access token и ZIP-каталог.

## Реализовано

1. Подтипы SSL:
   - SSL_HANDSHAKE;
   - SSL_PEER_UNVERIFIED;
   - SSL_PROTOCOL;
   - SSL_KEY;
   - SSL.
2. Безопасный failureDetail — только цепочка имён классов исключений.
3. Сбор:
   - UTC-времени JL22;
   - часового пояса;
   - auto_time;
   - Android security patch;
   - количества системных CA;
   - наличия curl/wget/openssl.
4. Диагностика не меняет TrustManager, HostnameVerifier или SSL socket factory.
5. HTTPS остаётся обязательным.

## Автоматическая проверка

GitHub Actions run: `35509603658`.

Успешно:
- root layout;
- S1;
- S2 catalog/money;
- S3 DRY_RUN;
- S2 diagnostics;
- v0.5.43 SSL safety guard;
- Windows Retail API audit guards;
- PowerShell syntax/runtime guards;
- assembleDebug;
- APK artifact upload.

APK artifact: `iRetail-v0.5.43-debug-apk`.
Artifact digest:
`sha256:f1f119b292be8c1c841bb83c1c01d2de59332f6b1f492f94e475eb591c73ef01`.

## Следующий шаг

Запустить `S2_02_CATALOG_DIAGNOSTICS.bat` на JL22. Сценарий сам выберет JL22, соберёт/установит APK, сформирует ZIP и отправит его в Git.

После живого отчёта выбирается точечное исправление TLS. До этого SSL-проверки не ослабляются.

## Прогресс

- v0.5.43 программно: **6/6, 100%**.
- S2: по-прежнему **5/6, 83%** до успешного живого каталога.
- S3 DRY_RUN: **4/4, 100%**.
