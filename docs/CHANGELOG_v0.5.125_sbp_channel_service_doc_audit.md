# CHANGELOG v0.5.125 — аудит серверной настройки СБП

Дата: 25.09.2026.

## Исходная точка

Автоматически опубликованный `SBP_CHANNEL_INVENTORY_20260925_185214.zip` доказал:

- каналов профиля 2512: 2;
- каналов с SBP: 0;
- shop_verified каналов: 0;
- enabled каналов: 0;
- channel 5676: external, external_plastic_cards, payme_alfa, goswiff;
- channel 5994: external, external_plastic_nonitgerated.

Следовательно, прямой СБП блокируется серверной конфигурацией профиля/канала/PayIn-PayOut shop.

## Новый безопасный аудит

`tools/iRetailSbpChannelServiceDocsAudit.ps1`

- скачивает публичный apiDoc index;
- автоматически обнаруживает страницы channel/service/shop/payment/admin;
- добавляет известные страницы как fallback;
- ищет контекст:
  - `get-available-services-in`;
  - `service_in_id`;
  - `service_in_slug`;
  - `shop_verified`;
  - `user_verified`;
  - `offline_shop_id`;
  - `pipo_id`;
  - `verify` / `verification`;
  - `enable` / `enabled`;
  - `update` / `edit` / `save` / `create`;
  - `sbp` / `sbp_low_risk`;
- извлекает ближайшие `/api/...` route candidates.

Сетевые действия — только публичные GET документации.

## Runner

`MAIN_40_SBP_CHANNEL_SERVICE_DOC_AUDIT.bat`

- не использует авторизацию;
- не вызывает рабочие API;
- сам публикует ZIP и SHA256 в текущую ветку;
- после публикации достаточно сообщить ChatGPT, что MAIN_40 завершён.

## Цель

До обращения в поддержку получить один из двух результатов:

1. документирован обычный/административный API настройки SBP — тогда фиксируем точную границу прав;
2. такого публичного пути нет — тогда формируем конкретный запрос в i-Retail на:
   - shop verification;
   - включение SBP service;
   - выдачу service_in_id/slug для channel 5676;
   - подтверждение create/status контракта.
