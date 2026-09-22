# CHANGELOG v0.5.84 — fiscal safe install smoke

Дата: 22.09.2026.

Добавлен безопасный живой smoke-test на JL22:
- автоопределение JL22 по полной ADB-сигнатуре;
- сборка/установка текущего APK;
- explicit kiosk + real_pos_enabled=false;
- Kozen не используется;
- финансовый запрос запрещён;
- Fiscal DRY_RUN без подтверждённой оплаты не должен появляться;
- stock Jetinno UI восстанавливается;
- безопасный ZIP автоматически публикуется в Git.
