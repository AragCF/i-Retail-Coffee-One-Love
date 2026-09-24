# CHANGELOG v0.5.118 — восстановление СБП на Android 6

Дата: 25.09.2026.

## Наблюдение на реальном JL22

Первый запуск DRY_RUN версии 0.5.117 создал и сохранил активную синтетическую СБП-сессию, но закончился по времени без пользовательского подтверждения.

Следующий запуск корректно попытался восстановить эту сессию, но Android 6 завершил i-Retail:

`java.lang.NoClassDefFoundError: com.coffeeonelove.iretail.ui.SbpDryRunSession$$ExternalSyntheticLambda0`

Стек указывает на `SbpDryRunSession.restore(SbpDryRun.kt:88)`.

Исходный код на этом месте использовал:

`AtomicInteger.updateAndGet { ... }`

## Исправление

Семантика восстановления сохранена. Вместо удаления сессии или отказа от восстановления:

- `updateAndGet(lambda)` удалён;
- монотонный номер поколения восстанавливается циклом `AtomicInteger.get()/compareAndSet()`;
- Java 8 `java.util.function` для этого пути больше не требуется;
- внешний synthetic-lambda класс для `restore()` больше не нужен.

## Испытательный сценарий

`MAIN_30_SBP_DRYRUN_UI_TEST.bat` дополнительно:

- запускает DRY_RUN из свежего процесса через `am force-stop` без `pm clear`;
- сохраняет SharedPreferences и активную СБП-сессию;
- читает `AndroidRuntime`;
- немедленно распознаёт `FATAL EXCEPTION` и `NoClassDefFoundError`;
- возвращает `DRY_RUN_CRASH` вместо бессмысленного ожидания 180 секунд;
- ждёт восстановления JL22 также перед финальным возвратом обычного Standalone.

## Безопасность

- `real_pos_enabled=false`;
- реальный `qrPayment` не вызывается;
- RuntimeOrder не становится PAID;
- FiscalGateway и приготовление кофе не вызываются;
- финансовых команд новый сценарий не отправляет.
