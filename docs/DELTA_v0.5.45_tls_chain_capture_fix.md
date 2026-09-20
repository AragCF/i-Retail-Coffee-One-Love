# DELTA v0.5.45 — исправление захвата TLS-цепочки

Дата: 20.09.2026  
Основа: живой отчёт `S2_DIAGNOSTICS_20260920_171950.zip`.

## Что доказано

TLS-проба v0.5.44 действительно запустилась и штатный системный TrustManager отказал:

- `SYSTEM_TRUST=FAIL`;
- `SSLHandshakeException > CertificateException > CertPathValidatorException`.

Но сам журнал `CHAIN/CERT` не попал в ZIP.

## Причина

В `logcat` один и тот же тег `IretailTls` был указан дважды:

- `IretailTls:I`;
- `IretailTls:E`.

Последний уровень фактически оставил только сообщения уровня Error, поэтому строки `Log.i(... "CHAIN")` и `Log.i(... "CERT")` были отфильтрованы.

## 🟢 Исправлено

- фильтр заменён на единый `IretailTls:V`;
- теперь в отчёт должны попадать все уровни этого тега, включая:
  - `CHAIN`;
  - `CERT`;
  - `SYSTEM_TRUST`;
  - `PROBE_FAILED`;
- версия поднята до `0.5.45-s2-tls-chain-capture-fix`;
- добавлен версионно-независимый guard `verify_tls_chain_probe.py`.

## 🔴 Не менялось

- TLS trust model;
- HostnameVerifier;
- X509TrustManager;
- API-маршруты;
- учётные данные;
- платежи;
- заказы.

## Цель живой проверки

Получить фактическую цепочку сертификатов сервера на JL22 и после этого выбрать точечное исправление доверия Android 6.
