# CHANGELOG v0.5.81 — Fiscal DRY_RUN v1

Дата: 22.09.2026.

- Добавлен отдельный FiscalizationDraftBuilder.
- DRY_RUN создаётся только после подтверждённой карточной оплаты.
- Сетевые вызовы Fiscal API отсутствуют.
- Точность card_amount строится из amountMinor.
- iBonus discount блокирует финальную строковую цену до утверждения распределения.
- FFD payment/type/vat не угадываются.
- Обновлено обращение коллегам i-Retail с разделением Retail и Fiscal контуров.
