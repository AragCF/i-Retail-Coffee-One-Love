from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")
audit=(ROOT/"tools/iRetailSbpChannelInventory.ps1").read_text(encoding="utf-8")
runner=(ROOT/"MAIN_39_SBP_CHANNEL_INVENTORY.bat").read_text(encoding="utf-8")
publisher=(ROOT/"tools/Publish-TestArtifact.ps1").read_text(encoding="utf-8")
analyzer=(ROOT/"tools/analyze_sbp_channel_inventory_report.py").read_text(encoding="utf-8")

checks={
    "app version 0.5.124":"versionCode 124" in gradle and "versionName '0.5.124-sbp-channel-inventory'" in gradle,
    "audit enumerates profile channels":'iretail/channel/get-channels' in audit and 'profile_id=[string]$config.profile_id' in audit,
    "audit reads each channel":'iretail/channel/get"' in audit,
    "audit reads available services":'iretail/channel/get-available-services-in' in audit,
    "audit records verification flags":"shop_verified" in audit and "user_verified" in audit,
    "audit records enabled flags":"channel_enable" in audit and "related_enabled" in audit,
    "audit detects SBP slugs":"sbp_count" in audit and "^sbp($|_)" in audit,
    "audit performs no payment mutation":not bool(re.search(r'Invoke-ReadOnlyApi\s+"[^"]+"\s+"(?:iretail/payment-in/create|iretail/payment-in/revert|order/create|order/pay)"',audit,re.I)),
    "audit performs no channel mutation":not bool(re.search(r'Invoke-ReadOnlyApi\s+"[^"]+"\s+"iretail/channel/(?:create|update|save|edit|delete|enable|disable)',audit,re.I)),
    "audit has no Kozen transport dependency":"KozenAoaPaymentClient" not in audit and "com.skytech" not in audit and not bool(re.search(r'\badb(?:\.exe)?\s+(?:connect|devices|-s|shell|install|logcat|push|pull)',audit,re.I)),
    "runner auto-publishes":"Publish-TestArtifact.ps1" in runner and "AUTO_PUBLISH_OK" in runner,
    "runner says no manual upload":"No manual archive upload is required." in runner,
    "publisher stages only artifact and sha":"git -C $repo add -- $relative $shaRelative" in publisher and "git add ." not in publisher.lower(),
    "analyzer consumes committed ZIP":"SBP_CHANNEL_INVENTORY_*.zip" in analyzer and "20_channel_inventory.json" in analyzer,
}

failed=[name for name,ok in checks.items() if not ok]
for name,ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ")+name)
if failed:
    raise SystemExit("v0.5.124 SBP channel inventory guard failed: "+", ".join(failed))
print(f"[OK] v0.5.124 SBP channel inventory guard: {len(checks)} checks passed")
