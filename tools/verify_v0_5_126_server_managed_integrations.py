from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
errors = []

def require(condition, message):
    if not condition:
        errors.append(message)

gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
gateways = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/IntegrationGateways.kt").read_text(encoding="utf-8")
main = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
models = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/Models.kt").read_text(encoding="utf-8")
contract_path = ROOT / "docs/SERVER_MANAGED_INTEGRATIONS_CONTRACT_v1.0.0.md"
contract = contract_path.read_text(encoding="utf-8") if contract_path.exists() else ""

require("versionCode 126" in gradle, "versionCode must be 126")
require("0.5.126-server-managed-integrations" in gradle, "versionName mismatch")
require("Статус: APPROVED" in contract, "approved server-managed contract missing")

# Catalog: valid empty server catalog must be accepted and local demo products must not reappear.
require("structureValid" in gateways, "catalog structural validation missing")
require('INVALID_CATALOG_STRUCTURE' in gateways, "catalog invalid-structure state missing")
require('parsed.products.isEmpty()' not in gateways.split('private fun parseCatalogZip', 1)[0],
        "fresh catalog path still rejects an empty product list")
require('return if (apiConfig.enabled) emptyList() else loadProductsFromXmlAsset()' in gateways,
        "remote-enabled cold start must not fall back to XML products")
require('if (contentRepository.isRemoteCatalogEnabled())' in main and
        'remoteCoffee.ifEmpty { localCoffeeFallbackProducts() }' in main,
        "visual coffee fallback must be conditional on remote I-Retail being disabled")
require('"Меню временно пусто"' in main, "empty catalog UI state missing")

# Channel configuration must be read-only and fail closed for payments.
require("refreshChannelConfigAsync" in gateways, "channel config refresh missing")
require('"iretail/channel/get-available-services-in"' in gateways, "available-services endpoint missing")
require('"iretail/channel/get"' in gateways, "channel metadata endpoint missing")
require("ChannelConfigRefreshResult" in models, "channel config result model missing")
require("paymentMethodAllowedByServer" in main, "server payment gating missing")
require("PAYMENT_BLOCKED" in main, "payment gating audit log missing")
require("paymentConfigReady" in main, "payment config fail-closed state missing")
require("periodicServerRefresh" in main and "serverRefreshIntervalMs" in main,
        "periodic server refresh missing")

# Loyalty balance is read-only until a server-side redemption contract is proven.
require("loyaltyGateway.applyBonus(0)" in main, "local bonus redemption is not disabled")
require("maxBonusRub" not in main, "old local max-bonus calculation still present")
require("Списание бонусов пока не выполняется" in main or "списание бонусов пока не выполняется" in main,
        "truthful loyalty message missing")

# v0.5.126 must not introduce mutating Retail payment/order/admin endpoints in the content repository.
for forbidden in (
    "iretail/payment-in/create",
    "iretail/order/synchronize",
    "admin/device/create",
    "device/register-external-system",
):
    require(forbidden not in gateways, f"forbidden mutating endpoint introduced in IntegrationGateways: {forbidden}")

if errors:
    print("v0.5.126 verification FAILED")
    for e in errors:
        print(" -", e)
    sys.exit(1)

print("v0.5.126 verification OK")
print(" - empty server catalog is a valid state")
print(" - local demo fallback is disabled while remote I-Retail is enabled")
print(" - channel/payment services are read-only and fail-closed")
print(" - local bonus redemption is disabled")
print(" - no new mutating Retail API endpoint was introduced")
