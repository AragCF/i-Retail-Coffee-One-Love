# CHANGELOG v0.5.68 — анализ external_code

Дата: 21.09.2026.

## Основание

Живой v0.5.67 доказал:
- server code у device 3476 присутствует;
- его длина 4;
- он совпадает с текущим config device_code;
- external_code присутствует;
- external_code не совпадает с config device_code.

Значит, первоначальная гипотеза о неверном обычном device_code отвергнута.

## Добавлено

- анализ безопасных признаков external_code из опубликованного ZIP;
- поиск всех документированных I-Retail endpoints рядом с external_code;
- точный контекст register-external-system.

Никаких новых API-вызовов нет.
