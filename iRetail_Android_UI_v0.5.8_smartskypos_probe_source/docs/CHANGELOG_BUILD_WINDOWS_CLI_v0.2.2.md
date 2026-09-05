# CHANGELOG_BUILD_WINDOWS_CLI_v0.2.2

## Что исправлено

Исправлена ошибка сборки `:app:compileDebugKotlin`:

```text
Inconsistent JVM-target compatibility detected for tasks 'compileDebugJavaWithJavac' (1.8) and 'compileDebugKotlin' (21).
```

Причина: сборка запускалась под JDK 21, Java-компиляция Android-проекта шла с целевой совместимостью 1.8, а Kotlin-компилятор автоматически выбирал JVM target 21. Gradle/Kotlin остановили сборку из-за несовпадения целей.

## Что изменено

В `app/build.gradle` явно зафиксирована совместимость Java/Kotlin:

- Java source compatibility: 1.8;
- Java target compatibility: 1.8;
- Kotlin JVM target: 1.8.

Также обновлены служебные поля версии:

- `versionCode`: 3;
- `versionName`: `0.2.2-ui-mvp`.

## Что не менялось

- логика Android-приложения;
- экраны;
- карта переходов;
- ресурсы;
- пакет приложения;
- минимальная версия Android: API 23 / Android 6.

## Что делать дальше

1. Распаковать архив в рабочую папку.
2. Запустить `BUILD_WINDOWS_CLI.bat`.
3. После успешной сборки взять APK из:

```text
app\build\outputs\apk\debug\app-debug.apk
```

Если появится новая ошибка, нужно прислать свежий лог сборки полностью.
