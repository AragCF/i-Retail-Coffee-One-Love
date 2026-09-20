# Сборка i-Retail Android UI v0.4.2 в APK из Windows CLI

Документ описывает сборку проекта в `debug APK` из обычной командной строки Windows без открытия Android Studio.

Обновление v0.4.2 исправляет проблему из Windows-лога, где сборка падала на `:app:clean`, потому что Windows не давала удалить папку `app\build\outputs\apk\debug`: какой-то процесс держал папку или файл открытым.

Проект: `iRetail Android UI`  
Пакет приложения: `com.coffeeonelove.iretail`  
Минимальная версия Android: Android 6 / API 23  
Целевой модуль Gradle: `:app`

---

## 1. Что изменилось в v0.4.2

Раньше скрипт всегда выполнял:

```bat
gradle :app:clean
```

На Windows это часто ломается, если папка с APK открыта в Проводнике, Total Commander, Android Studio, антивирусе, `adb install` или другом процессе.

Теперь основной режим сборки **не запускает clean**. Это нормально: для обычной отладочной сборки `clean` не нужен.

Новый основной сценарий:

1. Проверить Java.
2. Найти Android SDK.
3. Обновить `local.properties`.
4. Найти Gradle.
5. Остановить старые Gradle daemon-процессы.
6. Собрать `:app:assembleDebug`.
7. Скопировать APK в `dist`.

---

## 2. Что уже есть в архиве

В корне проекта есть файл:

- `BUILD_WINDOWS_CLI.bat` — основной скрипт сборки APK из Windows CLI.

Скрипт безопасно работает из путей с символом `!`, например:

```text
C:\54\Projects\!0719 - Coffee\Stage 02\Frontend - Android Kotlin\iretail_android_ui_mvp_v0_2
```

После успешной сборки APK будет скопирован в папку:

```text
dist\iRetail_Android_UI_v0.4.2-debug-YYYYMMDD_HHMMSS.apk
```

Также создаётся или обновляется файл:

```text
dist\iRetail_Android_UI_v0.4.2-debug-latest.apk
```

Исходный файл Gradle остаётся здесь:

```text
app\build\outputs\apk\debug\app-debug.apk
```

---

## 3. Что нужно установить на Windows

### 3.1. JDK

Подходит JDK 17 или JDK 21. В твоём логе уже используется OpenJDK 21, это нормально.

Проверка:

```bat
java -version
```

Если Java не находится:

1. Установить JDK x64.
2. Создать переменную окружения `JAVA_HOME`.
3. Добавить `%JAVA_HOME%\bin` в `PATH`.
4. Открыть новую командную строку.

---

### 3.2. Android SDK

Нужен Android SDK с установленной платформой `android-35`.

Скрипт ищет SDK по переменным:

- `ANDROID_HOME`
- `ANDROID_SDK_ROOT`

Если переменные не заданы, он проверяет стандартную папку:

```text
%LOCALAPPDATA%\Android\Sdk
```

В твоём логе SDK найден здесь:

```text
C:\54\Dist\Progr\Android_Tools
```

Это подходит, если внутри есть Android SDK, Build Tools и Platform Tools.

---

### 3.3. Gradle

Скрипт использует `gradlew.bat`, если он есть. Если Gradle Wrapper отсутствует, он ищет системный `gradle.bat` или `gradle`.

В твоём логе использовался:

```text
C:\54\Dist\Progr\Android_Tools\gradle\bin\gradle.bat
```

Gradle 9.4.1 доходит до сборки, но при ошибках совместимости Android Gradle Plugin безопаснее использовать Gradle 8.7–8.10.x.

---

## 4. Обычная сборка APK

Открой Windows Command Prompt или PowerShell, перейди в корень проекта и запусти:

```bat
BUILD_WINDOWS_CLI.bat
```

Это основной рекомендуемый способ.

Он **не выполняет clean**, поэтому не должен падать из-за заблокированной папки `app\build`.

---

## 5. Сборка с обычной очисткой

Если всё закрыто и нужна очистка:

```bat
BUILD_WINDOWS_CLI.bat --clean
```

Если `clean` не сможет удалить `app\build`, скрипт покажет предупреждение и всё равно продолжит сборку.

Это сделано специально: ошибка очистки не должна блокировать получение APK.

---

## 6. Сборка с жёсткой очисткой

Если проект ведёт себя странно после нескольких сборок:

```bat
BUILD_WINDOWS_CLI.bat --hardclean
```

Скрипт попробует удалить:

```text
app\build
build
```

Если Windows не даст удалить папки, скрипт покажет предупреждение и продолжит сборку.

---

## 7. Где взять готовый APK

После успешной сборки основной файл будет здесь:

```text
dist\iRetail_Android_UI_v0.4.2-debug-latest.apk
```

Также рядом будет файл с точным временем сборки:

```text
dist\iRetail_Android_UI_v0.4.2-debug-YYYYMMDD_HHMMSS.apk
```

Это сделано, чтобы не зависеть от заблокированного файла `latest`.

---

## 8. Быстрая установка на устройство через ADB

Проверить устройство:

```bat
adb devices
```

Установить последнюю сборку:

```bat
adb install -r dist\iRetail_Android_UI_v0.4.2-debug-latest.apk
```

Для Jetinno JL22 это имеет смысл делать только после проверки, что устройство видно через ADB и разрешает установку APK.

---

## 9. Что делать, если снова будет ошибка удаления `app\build`

Это не ошибка приложения и не ошибка Kotlin. Это блокировка файла/папки в Windows.

Закрой:

- Проводник, открытый в `app\build` или `dist`;
- Total Commander, открытый в папке сборки;
- Android Studio;
- окно просмотра APK/архива;
- процесс установки APK, если он завис;
- антивирусную проверку, если она держит файл.

Потом запусти:

```bat
BUILD_WINDOWS_CLI.bat
```

Обычная сборка без clean должна пройти дальше.

---

## 10. Что делать, если ошибка уже не про clean

Если сборка дошла до `:app:compileDebugKotlin`, `:app:mergeDebugResources`, `:app:processDebugManifest` или `:app:packageDebug` — это уже новая ошибка сборки, а не блокировка очистки.

В этом случае пришли новый лог целиком. Исправлять надо будет уже конкретную проблему компиляции, ресурсов или манифеста.


## Ошибка `MockGateways.kt` при сборке поверх старой папки

Если проект распаковывался поверх старой версии, в дереве исходников мог остаться файл `app/src/main/java/com/coffeeonelove/iretail/ui/MockGateways.kt`. Начиная с v0.4.2 сборочный скрипт и Gradle автоматически удаляют этот устаревший файл перед компиляцией. Если ошибка повторится, распакуйте архив в новую пустую папку или вручную удалите этот файл.
