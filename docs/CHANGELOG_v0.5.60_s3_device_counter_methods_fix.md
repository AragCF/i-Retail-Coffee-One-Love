# CHANGELOG v0.5.60 — исправление пути внутри ZIP

Дата: 21.09.2026.

## Ошибка v0.5.59

`analyze_s3_device_counter_methods.py` использовал `Path(name).name`. ZIP был создан Windows PowerShell и содержал Windows-разделители в именах элементов, поэтому Linux-runner GitHub Actions не отделил basename и сообщил `Device controller page not found`.

## Исправлено

Имя ZIP-элемента сначала нормализуется: обратные слэши заменяются на прямые, затем выделяется последний компонент пути.

Никаких сетевых API-вызовов не добавлено. Анализируется тот же опубликованный `S3_COUNTER_SOURCES_20260921_175333.zip`.
