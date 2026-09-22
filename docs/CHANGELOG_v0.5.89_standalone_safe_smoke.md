# CHANGELOG v0.5.89 — standalone safe smoke

Дата: 23.09.2026.

По фактической конфигурации JL22:
- i-Retail UI соответствует режиму standalone;
- i-Retail остаётся на переднем плане;
- Jetinno работает в фоне;
- его UI/хранитель экрана не надо возвращать после теста.

Smoke-test теперь:
- сохраняет standalone + real_pos_enabled=false;
- запускает i-Retail из сохранённого режима;
- проверяет SharedPreferences;
- не запускает Jetinno UI;
- оставляет i-Retail активным после отчёта.
