# CHANGELOG v0.5.83 — fiscal adapter guard fix

Дата: 22.09.2026.

v0.5.82 не прошёл CI из-за исторического v0.5.81 guard, который требовал прямую ссылку MainActivity -> FiscalizationDraftBuilder.

Исправлен только guard:
- принимает прежний прямой путь;
- либо новый provider-neutral путь MainActivity -> FiscalGateway -> DryRunFiscalGateway -> FiscalizationDraftBuilder.

Сетевое поведение не менялось.
