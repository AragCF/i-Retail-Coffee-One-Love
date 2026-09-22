# Отчёт реализации v0.5.76 — S3 admin-auth permission audit

## Цель

Проверить, был ли permission denied следствием использования обычного пользовательского токена вместо admin token.

## Read-only последовательность

1. user/authentication.
2. user/admin-authentication.
3. user/get-permissions с ordinary token.
4. user/get-permissions с admin token.
5. user/get-profile-list с admin token.
6. admin/device/find только при наличии admin token.

## Безопасность

- access_token/refresh_token не сохраняются;
- отчёт хранит только token_present/tokens_equal и безопасные permissions;
- все изменяющие admin/device и iretail методы отсутствуют;
- ZIP проходит отдельную проверку перед публикацией.
