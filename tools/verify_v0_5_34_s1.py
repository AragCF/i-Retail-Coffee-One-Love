from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
main = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
gateways = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/IntegrationGateways.kt").read_text(encoding="utf-8")
build = (ROOT / "app/build.gradle").read_text(encoding="utf-8")

checks = []

def require(name: str, condition: bool) -> None:
    checks.append((name, condition))
    if not condition:
        raise SystemExit(f"[FAIL] {name}")

require("versionName 0.5.34", "versionName '0.5.34-s1-truthful-states'" in build)
require("versionCode 34", "versionCode 34" in build)

require("Kozen confirmed payment stays PAID", "fun markPaymentConfirmed(): OperationResult" in gateways)
require("no local fiscalized state", "order.status = OrderStatus.FISCALIZED" not in gateways)
require("no fake local receipt URL", "local://receipt/" not in gateways)

require("cash/online blocked before payment start", "if (method != PaymentMethod.CARD)" in main)
require("no timer-based finishPayment", 'handler.postDelayed({ finishPayment()' not in main)
require("no timer-based online confirmation", 'handler.postDelayed({ openScreen("PAYMENT_ONLINE_CONFIRM")' not in main)
require("no timer-based dispense completion", 'handler.postDelayed({ finishDispense()' not in main)

require("device gateway does not report fake success", 'DeviceCommandResult(true, "Выдано' not in gateways)
require("heat gateway does not report fake success", 'DeviceCommandResult(true, "Разогрев завершён"' not in gateways)
require("cup confirmation does not report fake success", 'DeviceCommandResult(true, "Стакан подтверждён"' not in gateways)

require("email send does not jump to success", 'area("Отправить чек", 120, 1480, 840, 160) { openScreen("RECEIPT_EMAIL_COMPLETE") }' not in main)
require("Kozen approved path uses confirmed-payment marker", "orderGateway.markPaymentConfirmed()" in main)
require("S1 status label visible in diagnostics", "UI v0.5.34" in main)

print(f"[OK] v0.5.34 S1 static contract guard: {len(checks)} checks passed")
