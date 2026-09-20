# iRetail Android UI v0.5.8 — SmartSkyPOS probe

Версия: `0.5.8-smartskypos-probe`.

Эта версия подключает к текущему i-Retail восстановленный клиентский контракт
SmartSkyPOS `1.9.19-RC.1.11057` для Kozen P12.

## Первый запуск

Запускайте сценарии строго по порядку:

1. `SMARTSKYPOS_01_BUILD_INSTALL.bat`
2. `SMARTSKYPOS_02_SAFE_PROBE.bat`
3. только после успешного probe — `SMARTSKYPOS_03_CONTROLLED_PAYMENT.bat`
4. `SMARTSKYPOS_04_COLLECT_LOGS.bat`

Подробности: `docs/SMARTSKYPOS_KOZEN_P12_TEST_PLAN_v0.5.8.md`.

## Главное ограничение этой версии

Обычная кнопка «Банковская карта» в i-Retail пока остаётся на прежнем локальном
контуре. Реальный SmartSkyPOS подключён отдельным диагностическим слоем.

Это сделано намеренно: сначала на реальном Kozen P12 подтверждаем
`bind → StateCallback → READY → TerminalData`, затем контролируемую `payment()`,
и лишь после этого переводим пользовательский платёжный путь.

## Сборка

`BUILD_WINDOWS_CLI.bat`

Сценарий собирает debug APK и кладёт последнюю копию в:

`dist/iRetail_Android_UI_v0.5.8-smartskypos-probe-debug-latest.apk`

## Исходный контракт

В `app/src/main/aidl/com/skytech/smartskyposlib` и
`app/src/main/java/com/skytech/smartskyposlib` включён контракт,
восстановленный непосредственно из SmartSkyPOS `1.9.19-RC.1.11057`.

Резервные AIDL-слоты 31, 32 и 40 нельзя удалять: они сохраняют точную
нумерацию Binder-транзакций последующих методов.

## Проверка

Структурный отчёт: `test_reports/validation_v0.5.8_smartskypos_probe.json`.

Полную Android APK-сборку в среде подготовки архива выполнить нельзя:
Android SDK/Gradle отсутствуют. На Windows используется штатный сценарий сборки.

## Известный старый вопрос

Исходная `v0.5.7` уже содержала настройки I-Retail в
`app/src/main/assets/content/iretail-api.json`. В этой точечной SmartSkyPOS-ветке
они не менялись, чтобы не ломать существующий каталог/лояльность. Перед
production-сборкой их следует вынести из APK в защищённую конфигурацию.
