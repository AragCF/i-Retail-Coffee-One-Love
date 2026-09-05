# i-Retail v0.5.9 — SmartSkyPOS controlled payment test

## Purpose

This version is a temporary Kozen P12 diagnostic build. It is not the production deployment architecture for Coffee One Love.

Production i-Retail remains intended for the Android 6 coffee machine. Kozen P12 integration will later move behind a dedicated bridge/adapter layer.

## Changes from v0.5.8

- removed all `EditText` controls from `SmartSkyPosDiagnosticActivity`;
- no Android keyboard/IME is required for the controlled payment test;
- added fixed test amount buttons: 1 RUB, 10 RUB, 100 RUB;
- selected amount is shown explicitly on screen;
- Terminal ID and currency are no longer editable;
- the payment route is selected only from current `TerminalData` and only from an operation whose `transactionType` is `payment`;
- the payment button is enabled only when the existing fail-closed gateway reports an open payment gate and a valid card-payment route exists;
- before every `payment()` call the gateway still re-checks current `READY(0)` and fetches fresh `TerminalData`;
- no automatic payment or automatic retry was added;
- while a payment is in flight the explicit payment button is disabled;
- transaction result is displayed using non-sensitive fields only;
- `SMARTSKYPOS_03_CONTROLLED_PAYMENT.bat` no longer asks for an amount on the PC.

## Expected Kozen P12 flow

1. Build/install the debug APK.
2. Run `SMARTSKYPOS_02_SAFE_PROBE.bat` if the terminal state has not already been verified.
3. Run `SMARTSKYPOS_03_CONTROLLED_PAYMENT.bat`.
4. Verify on P12:
   - `State: READY(0)`;
   - `TerminalData: 0`;
   - `Gate: OPEN`;
   - a Terminal ID and currency are displayed.
5. Press `1 ₽` for the first real test.
6. Press `ВЫПОЛНИТЬ ТЕСТОВУЮ ОПЛАТУ` once.
7. Confirm the Android dialog once.
8. Complete/cancel the operation on SmartSkyPOS/P12 as required.
9. Run `SMARTSKYPOS_04_COLLECT_LOGS.bat` and inspect `PAYMENT_RESULT`.

## Safety rules

- There is no financial operation on activity launch.
- There is no auto-retry after timeout/exception.
- `UNFINISHED_OPERATION(2)` keeps the payment gate closed.
- A payment route is never accepted from free-form user input.
- PAN/CVV/EMV data and receipt body are not written to the diagnostic log.

## Version

- `versionCode`: 19
- `versionName`: `0.5.9-smartskypos-payment-test`
