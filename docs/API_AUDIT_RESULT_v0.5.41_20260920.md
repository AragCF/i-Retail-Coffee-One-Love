# Результат Windows/curl-аудита Retail API — v0.5.41

Дата: 20.09.2026  
Источник: `test_reports/retail_api_curl/RAPI_CURL_20260920_084938.zip`.

## Итог

Retail API с Windows работает.

Подтверждено:
- документация `https://my.i-retail.com/api/apidoc/actual/index.html` доступна по HTTP 200;
- `POST /api/user/authentication` вернул HTTP 200;
- API-статус авторизации: `true`;
- access token получен;
- `POST /api/iretail/catalog/download-actual-zip` вернул HTTP 200;
- Content-Type каталога: `application/zip`;
- размер ZIP: 4029 байт;
- SHA-256: `24839ab7c4710b8bb84ec70bdbf0dba0b211ac185eecbbac5a3b9127b415e9d9`;
- проверка отчёта на утечку учётных данных пройдена.

## Структура каталога

ZIP содержит:
- `/categories.json`;
- `/offers_0000.json`.

В `offers_0000.json` — 8 предложений. Все восемь имеют:
- `available=true`;
- `status_id=1`;
- корректную цену;
- идентификатор;
- название.

Набор включает кофейные позиции: Американо, Эспрессо, Капучино, Флэт Уайт, Латте, Американо XL, Капучино кокос, Какао.

## Совместимость с Android-разборщиком

Текущий Android-разборщик:
- удаляет ведущий `/` у имени ZIP-entry;
- читает `categories.json`;
- читает `offers_*.json`;
- допускает `external_offer_id=null` и в этом случае использует внутренний id;
- принимает `available=true` и `status_id=1`.

Поэтому структура фактически полученного Windows-каталога совместима с текущим Android-кодом.

## Вывод

Проблема S2 не находится на стороне самого API или формата каталога.

Живой прогон v0.5.38 на JL22 дал:
- `success=false`;
- `source=content XML`.

При этом тот же контракт с Windows даёт успешную авторизацию и ZIP.

Следующий диагностический контур должен локализовать отказ на JL22:
- authentication;
- download;
- DNS;
- connect;
- TLS/SSL;
- timeout;
- parse;
- cache.

До получения живого JL22-отчёта S2 остаётся незакрытым.
