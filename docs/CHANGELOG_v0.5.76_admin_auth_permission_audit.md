# CHANGELOG v0.5.76 — admin authentication / permission audit

Дата: 22.09.2026.

Документация выявила отдельный admin-authentication. Новый аудит безопасно сравнивает ordinary/admin authentication и permissions, не публикуя токены или учётные данные.

Если admin-auth выдаст токен, выполняется только read-only admin/device/find.

Изменяющих вызовов нет.
