# CHANGELOG v0.5.96 — fiscal self-test intent fix

Дата: 23.09.2026.

Живой v0.5.95:
- сборка успешна;
- APK установлен;
- standalone сохранён;
- real POS выключен;
- DRAFT_READY marker не появился.

Исправлено:
- диагностический intent обрабатывается в onCreate и onNewIntent;
- перед self-test выполняется force-stop пакета;
- добавлен SELF_TEST_TRIGGER;
- ожидание результата увеличено до 10 секунд;
- исторический versionName guard сделан пригодным для следующих версий.

Финансовых вызовов нет.
