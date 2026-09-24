# CHANGELOG v0.5.110 — SBP DRY_RUN UI

Дата: 24.09.2026.

Начат безопасный этап S4 / СБП.

Добавлено:
- отдельная `SbpDryRunSession` и состояния IDLE / QR_READY / WAITING_CONFIRMATION / CONFIRMED / EXPIRED / CANCELLED / ERROR;
- синтетические qrId/payload с явной маркировкой `SBP-DRY-RUN`;
- диагностический intent `sbp_dry_run_self_test=true` только для debug + Standalone + realPos=false;
- экран PAYMENT_ONLINE_QR показывает безопасный dry-run;
- отдельный переход имитации сканирования QR;
- отдельный переход синтетического подтверждения;
- при подтверждении RuntimeOrder не переводится в PAID, FiscalGateway не вызывается, приготовление не запускается;
- обычный пользовательский ONLINE-платёж остаётся заблокирован;
- `MAIN_30_SBP_DRYRUN_UI_TEST.bat` для ручного smoke-test без денег.

Живой SmartSkyPOS `qrPayment` не подключён и не разрешён.