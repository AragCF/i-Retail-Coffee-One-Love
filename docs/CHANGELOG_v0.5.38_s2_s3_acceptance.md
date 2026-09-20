# CHANGELOG v0.5.38 — объединённая приёмка S2 + S3

Дата: 20.09.2026  
Основа: `v0.5.37-s3-order-draft`.  
Проверенный программный SHA: `7cdfcea6786e8d51849b35c9800647f19543331e`.

## 🟢 Добавлено

- единый сценарий `S23_01_BUILD_INSTALL_ACCEPTANCE_AUDIT.bat`;
- версионно-независимая проверка безопасного черновика S3;
- проверка выпуска `tools/verify_v0_5_38_acceptance.py`;
- единый отчёт S2+S3:
  - результат живого обновления каталога;
  - снимок каталога;
  - локальный `order_sync_draft.json`;
  - снимок экрана заказа;
  - пакетная информация Android;
  - ветка Git и SHA исходника.

## 🟡 Изменено

- версия APK: `0.5.38-s2-s3-acceptance`, `versionCode 38`;
- рабочие build/cache/log каталоги исключены из `.gitignore`;
- Android workflow проверяет root-layout, S1, S2, S3 и 0.5.38 acceptance guard;
- README синхронизирован с текущим этапом.

## Защита живого прогона

- запуск приложения выполняется с `real_pos_enabled=false`;
- старый `order_sync_draft.json` удаляется до нового теста;
- сценарий проверяет точную ветку `v0.5.38-s2-s3-acceptance`;
- сценарий отказывается работать при незакоммиченных изменениях отслеживаемых файлов;
- SHA исходника сохраняется в отчёте;
- JSON проверяется через PowerShell / `ConvertFrom-Json`;
- обязательны:
  - `mode=DRY_RUN_ONLY`;
  - `send_allowed=false`;
  - `validation.lines_equal_gross=true`;
- живой каталог классифицируется отдельно от кэша.

## 🔴 Не добавлено

- нет `iretail/order/synchronize`;
- нет реального платежа;
- нет фискализации;
- нет изменения SmartSkyPOS/AOA или VTK;
- нет Multicard.

## Автоматическая проверка

GitHub Actions run: `35489157072`.

Успешно:
1. root-layout guard;
2. S1 truthful states;
3. S2 catalog and money;
4. S3 dry-run order draft;
5. v0.5.38 combined acceptance guard;
6. `assembleDebug`;
7. загрузка APK-артефакта.

Артефакт: `iRetail-v0.5.38-debug-apk`.  
Digest артефакта GitHub Actions: `sha256:a92ee40706cba2835166297e62393cf525e410f3b9967753e490470b79b762b7`.
