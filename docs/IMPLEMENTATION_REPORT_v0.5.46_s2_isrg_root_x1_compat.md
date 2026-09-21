# Отчёт реализации v0.5.46 — Android 6 / ISRG Root X1 compatibility

Дата: 20.09.2026

## Доказанная причина

Живой TLS-chain capture на JL22 Android 6.0.1 показал:

- leaf: `CN=admin.beta.i-retail.com`;
- intermediate: `Let's Encrypt YR1`;
- cross-signed root: `Root YR`;
- issuer Root YR: `ISRG Root X1`;
- системная проверка Android 6: `SYSTEM_TRUST=FAIL`;
- исключение: `SSLHandshakeException > CertificateException > CertPathValidatorException`.

Официальная документация Let's Encrypt подтверждает, что стандартная цепочка YR1 завершается на ISRG Root X1, а штатное доверие Android к ISRG Root X1 начинается с Android 7.1.1.

## Реализовано

1. В приложение добавлен официальный self-signed `ISRG Root X1`.
2. Перед использованием проверяется его SHA-256:
   `96bcec06264976f37460779acf28c5a7cfe8a3c0aae11a8ffcee05c0bddf08c6`.
3. Для HTTPS I-Retail:
   - на Android 7+ ничего не меняется;
   - на Android API <= 23 и только для `my.i-retail.com`:
     - сначала проверяется системный TrustManager;
     - только при его отказе проверка повторяется с дополнительным ISRG Root X1.
4. HostnameVerifier не заменяется.
5. Глобальная SSL factory не устанавливается.
6. Trust-all отсутствует.
7. Диагностика пишет:
   - `LEGACY_ROOT_APPLIED`;
   - `SYSTEM_TRUST_FAIL_EXTRA_ROOT_OK`;
   - обычный результат `IretailCatalog`.

## Источник корня

- официальный репозиторий: `letsencrypt/website`;
- файл: `static/certs/isrgrootx1.pem`;
- source blob SHA: `b85c8037f6b60976b2546fdbae88312c5246d9a3`.

## Автоматические проверки

GitHub Actions run: `35523632495`.

Успешно:
- root layout;
- S1 truthful states;
- S2 catalog/money;
- S3 DRY_RUN;
- S2 catalog diagnostics;
- JL22 SSL diagnostics;
- TLS chain probe;
- v0.5.46 ISRG Root X1 compatibility guard;
- Retail API curl audit;
- PowerShell syntax/runtime guards;
- `assembleDebug`;
- APK artifact upload.

Artifact:
- `iRetail-v0.5.46-debug-apk`;
- artifact id: `10608208755`;
- digest: `sha256:dd5f0b50b6063ec31f21de42e5f066d1440dec06db7c0f777b44717374af5633`.

## Следующий шаг

Запустить `S2_02_CATALOG_DIAGNOSTICS.bat` на JL22.

Критерий закрытия S2:

`REFRESH success=true source=I-Retail ZIP`

с ненулевым числом товаров.

Если после восстановления цепочки появится ошибка hostname verification, она будет рассматриваться отдельно; проверка имени узла намеренно не отключена.

## Прогресс

- v0.5.46 программно: **6/6, 100%**;
- S2 до живой приёмки: **5/6, 83%**;
- S3 DRY_RUN: **4/4, 100%**.
