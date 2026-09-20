# Источник доверенного корня ISRG Root X1 — v0.5.46

Дата: 20.09.2026

## Причина добавления

Живой TLS-chain probe на JL22 Android 6.0.1 показал цепочку:

`admin.beta.i-retail.com → Let's Encrypt YR1 → Root YR → ISRG Root X1`.

Системный TrustManager Android 6 завершает проверку:

`SSLHandshakeException > CertificateException > CertPathValidatorException`.

Официальная документация Let's Encrypt указывает:
- цепочка YR1 по умолчанию заканчивается на ISRG Root X1;
- штатное доверие к ISRG Root X1 на Android начинается с Android 7.1.1.

## Источник сертификата

Официальный репозиторий Let's Encrypt:

- repository: `letsencrypt/website`;
- path: `static/certs/isrgrootx1.pem`;
- source blob SHA: `b85c8037f6b60976b2546fdbae88312c5246d9a3`;
- публичный адрес: `https://letsencrypt.org/certs/isrgrootx1.pem`.

В проект скопирован self-signed ISRG Root X1 без изменений.

## Контроль целостности

Официальный SHA-256 сертификата ISRG Root X1:

`96bcec06264976f37460779acf28c5a7cfe8a3c0aae11a8ffcee05c0bddf08c6`.

Приложение вычисляет SHA-256 встроенного сертификата перед добавлением его в дополнительное хранилище доверия. При несовпадении соединение не получает дополнительного доверия.

## Область применения

Дополнительный корень применяется только:
- на Android API <= 23;
- для `my.i-retail.com`.

Остальные соединения продолжают использовать обычное системное доверие.

## Не отключается

- hostname verification;
- системный TrustManager;
- проверка цепочки;
- HTTPS.
