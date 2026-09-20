# DELTA v0.5.44 — безопасный TLS chain probe на JL22

Дата: 20.09.2026  
Основа: живой отчёт v0.5.43.

## Доказано до v0.5.44

На JL22 Android 6.0.1:
- DNS работает;
- время корректно и синхронизируется автоматически;
- my.i-retail.com доступен;
- proxy отсутствует;
- отказ происходит на authentication;
- причина: SSL_HANDSHAKE;
- цепочка причин: SSLHandshakeException > CertificateException > CertPathValidatorException.

Это означает отказ проверки цепочки сертификатов.

## Цель v0.5.44

Получить именно ту X.509-цепочку, которую сервер предъявляет JL22, при этом **не отключать системную проверку доверия**.

## 🟢 Добавлено

- диагностический TLS probe, который:
  - подключается к хосту из действующего iretail-api.json;
  - получает server certificate chain;
  - пишет только публичные поля сертификатов:
    - subject;
    - issuer;
    - notBefore/notAfter;
    - signature algorithm;
    - SHA-256;
  - передаёт цепочку штатному Android X509TrustManager;
  - фиксирует SYSTEM_TRUST=OK либо SYSTEM_TRUST=FAIL;
- probe запускается только с intent-extra tls_chain_probe=true;
- S2_02_CATALOG_DIAGNOSTICS.bat включает этот extra только для диагностического прогона;
- журнал отчёта дополнительно собирает IretailTls.

## 🟡 Изменено

- versionCode 44;
- versionName 0.5.44-s2-tls-chain-probe.

## 🔴 Не изменено

- HostnameVerifier;
- системная проверка сертификатов;
- TrustManager как источник доверия;
- серверные API-маршруты;
- учётные данные;
- платежи и заказы.

## ⚠️ Безопасность

Probe оборачивает системный X509TrustManager только для журналирования публичной цепочки и затем вызывает его штатную checkServerTrusted(). Ошибка доверия повторно выбрасывается. Небезопасного режима trust-all нет.

## Критерий следующего решения

После живого отчёта:
- chain size = 1 при issuer != subject — вероятен отсутствующий intermediate на сервере;
- chain содержит intermediate, но системный trust падает на корне — вероятен отсутствующий корневой CA в Android 6;
- конкретные subject/issuer определят точный безопасный вариант исправления.
