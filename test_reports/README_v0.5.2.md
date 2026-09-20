# Проверки v0.5.2

В этой среде нет Android SDK, поэтому полный APK не собирался. Выполнена статическая компиляционная проверка Kotlin-файлов через локальные Android-заглушки:

- `Models.kt`
- `IntegrationGateways.kt`
- `MainActivity.kt`

Результат: `exitcode=0`. Полную Gradle/Android-сборку нужно выполнить на Windows через `BUILD_WINDOWS_CLI.bat`.
