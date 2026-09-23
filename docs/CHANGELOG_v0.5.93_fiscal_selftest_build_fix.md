# CHANGELOG v0.5.93 — fiscal self-test build fix

Дата: 23.09.2026.

v0.5.92 остановился на Kotlin compile:
BuildConfig не генерируется текущей конфигурацией Android Gradle Plugin.

Исправление:
- BuildConfig не включается и не требуется;
- debug-сборка определяется через ApplicationInfo.FLAG_DEBUGGABLE;
- остальная логика self-test неизменна.
