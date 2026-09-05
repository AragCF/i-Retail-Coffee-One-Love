# Отчёт реализации v0.5.3

## Основание

Проверочный отчёт по профилю «Выставка» показал:

- авторизация успешна;
- профиль «Выставка» найден как `profile_id=2512`;
- список каналов профиля содержит канал `id=5676`, `name=Выставка`, `use_ibonus_loyalty=true`;
- запросы к `channel_id=3476` возвращают `humanFriendlyException.doesNotExistChannel`;
- `download-actual-zip` с `channel_id=3476` возвращает JSON-ошибку, а не ZIP.

## Изменённые файлы

- `app/src/main/assets/content/iretail-api.json`
- `app/src/main/java/com/coffeeonelove/iretail/ui/IntegrationGateways.kt`
- `app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt`
- `app/build.gradle`
- `BUILD_WINDOWS_CLI.bat`
- `README.md`

## Проверка

Добавлена локальная статическая компиляционная проверка Kotlin через Android-заглушки. Полная сборка APK по-прежнему выполняется на рабочей Windows-машине через `BUILD_WINDOWS_CLI.bat`.
