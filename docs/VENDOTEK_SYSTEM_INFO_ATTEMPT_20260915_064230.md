# Vendotek — первая попытка чтения System Information

Дата: 15.09.2026  
Архив: `VENDOTEK_SYSTEM_INFO_20260915_064230.zip`  
Ветка: `v0.5.24-vendotek-system-info`

## Итог

Обмен VTK и запрос `STATUS` с реальным Vendotek прошли успешно. Финансовых команд не отправлялось.

Подтверждённая последовательность:

```text
VTK_IDL_OK operation=0
SYSINFO_TX query=STATUS
SYSINFO_RX query=STATUS info=STATE=BUSY,NOT_READY;READY,DESCRIPTION=IN_SERVICE
SYSINFO_TX query=POS_PARAMS
```

После `POS_PARAMS` терминал немедленно вернул корректный обычный `IDL` без тега `SystemInformation`. Затем штатное приложение Jetinno снова заняло передний план. Поскольку диагностическая Activity была объявлена с `android:noHistory="true"`, Android уничтожил её при уходе в фон, `onDestroy()` вызвал `shutdownNow()`, и диагностический поток завершился `InterruptedException`.

Это означает, что `SYSTEM_INFO_ERROR` данного прогона не является ошибкой транспортного уровня VTK и не доказывает отсутствие поддержки `POS_PARAMS`.

## STATUS

Фактический ответ терминала:

```text
STATE=BUSY,NOT_READY;READY,DESCRIPTION=IN_SERVICE
```

Руководство VTK-MAN-RU 1.0 допускает комбинации состояний в `STATUS`. `DESCRIPTION=IN_SERVICE` означает, что терминал находится в сервисном меню. Перед первым финансовым VRP состояние должно быть повторно проверено; пока терминал сообщает `BUSY/NOT_READY` и `IN_SERVICE`, платёжный маршрут считается неготовым независимо от присутствия `READY` в комбинированном ответе.

## Исправление

Для `VendotekSystemInfoDiagnosticActivity` отключён `noHistory`, чтобы штатная заставка Jetinno могла временно занять экран, не уничтожая диагностический поток. Обычный интерфейс i-Retail по-прежнему восстанавливается Windows-сценарием после завершения теста.

Версия исправленной сборки: `0.5.24-vendotek-system-info-lifecycle-fix`, `versionCode=26`.

## Безопасность

Повторный тест остаётся только информационным. Разрешённые VTK-сообщения:

- обычный `IDL`;
- `IDL + SystemInformation=STATUS`;
- `IDL + SystemInformation=POS_PARAMS`;
- `IDL + SystemInformation=BANK_PARAMS`;
- `IDL + SystemInformation=NET_PARAMS`.

`VRP`, `FIN`, `ABR`, `DIS` и финансовые команды отсутствуют.
