# CHANGELOG v0.5.97 — fiscal self-test dynamic version

Дата: 23.09.2026.

Убрана хрупкая привязка MAIN_25 и GIT_125 к конкретной Git-ветке и вручную прописанному EXPECTED_VERSION.

Теперь:
- MAIN_25 читает versionName прямо из app/build.gradle;
- имя ветки не влияет на запуск self-test;
- publisher публикует отчёт в текущую ветку и запрещает только detached HEAD;
- исторические guards проверяют инварианты, а не конкретный номер выпуска;
- при безопасном validation failure диагностический ZIP всё равно публикуется.

Финансовая операция отсутствует.
