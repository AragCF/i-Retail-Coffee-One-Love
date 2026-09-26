from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

models = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/Models.kt").read_text(encoding="utf-8")
gateways = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/IntegrationGateways.kt").read_text(encoding="utf-8")
main = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
diag = (ROOT / "S2_02_CATALOG_DIAGNOSTICS.bat").read_text(encoding="utf-8")
selector = (ROOT / "tools/Select-JL22Device.ps1").read_text(encoding="utf-8")
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")

# From v0.5.126, an explicitly empty offer array is a valid server snapshot.
# Preserve validation and diagnostics; reject invalid structure instead of emptiness.
version_match = re.search(r"\bversionCode\s+(\d+)", gradle)
version_code = int(version_match.group(1)) if version_match else 0
server_managed = version_code >= 126
if server_managed:
    validation_present = all(fragment in gateways for fragment in (
        'if (!parsed.structureValid)',
        'CatalogStageException("validate", "INVALID_CATALOG_STRUCTURE"',
        'if (!reparsed.structureValid)',
    ))
else:
    validation_present = 'CatalogStageException("validate", "EMPTY_CATALOG"' in gateways

checks = {
    "app version is readable": version_match is not None,
    "CatalogRefreshResult has failureStage": "val failureStage: String? = null" in models,
    "CatalogRefreshResult has failureReason": "val failureReason: String? = null" in models,
    "authentication stage exists": 'CatalogStageException("authentication"' in gateways,
    "download stage exists": 'CatalogStageException("download"' in gateways,
    "parse stage exists": 'CatalogStageException("parse"' in gateways,
    "validate stage follows the active contract": validation_present,
    "cache stage exists": 'CatalogStageException("cache"' in gateways,
    "HTTP errors are reduced to status code": '"HTTP_$httpCode"' in gateways,
    "DNS failure is classified": '"UNKNOWN_HOST"' in gateways,
    "timeout is classified": '"TIMEOUT"' in gateways,
    "connect failure is classified": '"CONNECT"' in gateways,
    "SSL failure is classified": '"SSL"' in gateways,
    "auth rejection is classified": '"REJECTED"' in gateways,
    "catalog log exposes safe failure stage": 'failureStage=${result.failureStage ?: "-"}' in main,
    "catalog log exposes safe failure reason": 'failureReason=${result.failureReason ?: "-"}' in main,
    "JL22 selector checks product": "octopus_jetinno" in selector,
    "JL22 selector checks model": "UniWin_M190" in selector,
    "JL22 selector checks device": "octopus-jetinno" in selector,
    "JL22 selector falls back to numbered menu": "Select device number" in selector,
    "diagnostic script uses JL22 selector": "Select-JL22Device.ps1" in diag,
    "diagnostic script disables real POS": "--ez real_pos_enabled false" in diag,
    "diagnostic script captures filtered catalog log": "IretailCatalog:I" in diag and "AndroidRuntime:E *:S" in diag,
    "diagnostic script does not capture full logcat": "logcat -d -v threadtime >" not in diag,
}

if server_managed:
    checks.update({
        "valid empty catalog is not an API error": '"EMPTY_CATALOG"' not in gateways,
        "offer array must exist": 'if (!root.has("offers"))' in gateways,
        "offer array must have the right type": 'throw IllegalStateException("offers is not an array")' in gateways,
    })

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)

if failed:
    raise SystemExit("S2 catalog diagnostics guard failed: " + ", ".join(failed))

print(f"[OK] S2 catalog diagnostics guard: {len(checks)} checks passed")
