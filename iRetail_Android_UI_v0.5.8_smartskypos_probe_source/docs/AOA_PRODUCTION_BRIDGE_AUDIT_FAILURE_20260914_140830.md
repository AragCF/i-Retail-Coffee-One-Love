# Аудит production-моста AOA — разбор сбоя 2026-09-14 14:08:30

Источник: `AOA_PROD_BRIDGE_JL22_KOZEN_20260914_140830.zip`.

## Что подтверждено

- JL22 увидел Kozen в режиме AOA как `18d1:2d01`.
- JL22 успешно открыл BULK IN/OUT и отправил `PING 3001`.
- Клиент аудита физически не содержит и не отправляет финансовых команд; `financialCommandsSent=false`.
- SmartSkyPOS на Kozen был доступен и production-мост успел дойти до `BRIDGE_READY transport=AOA bridge=0.5.0 smartsky=bound`.
- Платёж, отмена, возврат и сверка в этом прогоне не выполнялись.

## Причина `PONG_TIMEOUT`

На Kozen `BridgeActivity` почти одновременно дважды вызвал запуск `ProductionBridgeService`: первый раз из первоначальной обработки Activity, второй — из последующего `onResume()` при уже выданном USB accessory permission.

В журнале это видно как две строки `PRODUCTION_BRIDGE_SERVICE_START requested` с интервалом около 16 мс, после чего появились два конкурентных `OPEN_ACCESSORY` и `InterruptedIOException: read interrupted`. Второй запуск сервиса закрыл/прервал AOA-сеанс, который только начал обслуживать первый запуск. Поэтому `PING 3001`, уже отправленный с JL22, не был прочитан Kozen и аудит завершился `PONG_TIMEOUT`.

Это ошибка жизненного цикла нашего production-моста, а не отказ USB/AOA и не ошибка SmartSkyPOS.

## Исправление 0.5.1

В `BridgeActivity` добавлена защита от повторного запуска сервиса в течение одного стартового цикла: близкие повторные вызовы от `onCreate`/`onResume` отбрасываются и журналируются как `PRODUCTION_BRIDGE_SERVICE_START duplicate_ignored`.

Версия `kozenBridge` повышена до `0.5.1-production-start-debounce` (`versionCode 8`).

## Повторная проверка

Нужно повторить тот же read-only аудит:

```bat
call AOA_17_PRODUCTION_BRIDGE_SAFE_AUDIT.bat 192.168.1.192:5555 192.168.31.134:5555 12000679
```

Карта не требуется. Финансовых команд клиент аудита не отправляет.

После успешного прогона результат публикуется:

```bat
call GIT_106_PUBLISH_PRODUCTION_BRIDGE_AUDIT.bat
```
