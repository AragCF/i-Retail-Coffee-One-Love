# CHANGELOG v0.5.125 — аудит серверной настройки СБП

Дата: 25.09.2026.

## Живой результат v0.5.124

`MAIN_39` проверил все каналы profile_id=2512.

### Канал 5676 — «Выставка»

- configured_channel=true;
- channel_enable=false;
- related_enabled=false;
- status_id=1;
- related_status_id=1;
- offline_shop_present=true;
- user_verified=true;
- shop_verified=false;
- доступные службы:
  - external;
  - external_plastic_cards;
  - payme_alfa;
  - goswiff;
- SBP services: 0.

### Канал 5994 — тестовый

- configured_channel=false;
- channel_enable=false;
- related_enabled=false;
- status_id=1;
- related_status_id=1;
- offline_shop_present=true;
- user_verified=true;
- shop_verified=false;
- доступные службы:
  - external;
  - external_plastic_nonitgerated;
- SBP services: 0.

### Вывод

Глобальный справочник знает `sbp` и `sbp_low_risk`, но ни один существующий канал профиля их не получает.

Прямой СБП на JL22 сейчас блокируется серверной конфигурацией/верификацией PayIn-PayOut shop, а не отсутствием Android QR UI.

## Новый read-only этап

`MAIN_40_SBP_SERVER_CONFIG_DOC_AUDIT.bat` скачивает только публичную документацию:

- admin/channel;
- admin/service-in;
- admin/service;
- admin/online-shop;
- admin/trade-point;
- admin/profile;
- admin/profile-settings;
- admin/setting;
- channel;
- online-shop;
- trade-point;
- service-in;
- iretail/channel;
- iretail/payment-in;
- iretail/pipo/input.

Ищутся documented routes и контекст вокруг verification/enable/service binding/SBP.

## Безопасность

- authentication: нет;
- business API calls: нет;
- config mutation: нет;
- payment mutation: нет;
- Kozen/ADB: нет;
- ZIP автоматически публикуется в Git.

## Следующий выбор по фактам

1. Если документация показывает доступный API настройки — сначала анализируем его контракт и права, не вызывая его.
2. Если настройки/верификация недоступны через документированный API — готовим точный запрос оператору i-Retail/PayIn-PayOut на включение `sbp`/ `sbp_low_risk` для канала 5676/связанного магазина.
