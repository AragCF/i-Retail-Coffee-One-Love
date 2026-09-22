# Fiscal adapter boundary — контракт v1.0.0

Дата: 22.09.2026  
Статус: SAFE_STRUCTURE_ONLY

## Цель

Зафиксировать архитектурную границу из ТЗ:
- POS adapter;
- Retail adapter;
- Fiscal adapter;
- Device adapter.

## Реализовано

`FiscalGateway` принимает только уже оплаченный `RuntimeOrder`.

Текущая реализация:
`DryRunFiscalGateway`.

Она:
- не выполняет сеть;
- не хранит credentials;
- не выставляет `FISCALIZED`;
- не возвращает receiptUrl;
- делегирует локальный DRY_RUN в `FiscalizationDraftBuilder`.

## Будущие реализации

После подтверждения контракта можно добавить, например:
- I-Retail Cloud Fiscal provider;
- First OFD provider;
- иной Fiscal provider.

Каждый из них обязан реализовать тот же `FiscalGateway`, не затрагивая POS-оплату и устройство приготовления.
