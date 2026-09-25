from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
publisher = (ROOT / "tools/Publish-TestArtifact.ps1").read_text(encoding="utf-8")
audit = (ROOT / "tools/iRetailDirectSbpServicesAudit.ps1").read_text(encoding="utf-8")
runner = (ROOT / "MAIN_38_SBP_DIRECT_SERVICES_READONLY_AUDIT.bat").read_text(encoding="utf-8")
contract = (ROOT / "docs/SBP_DUAL_MODE_CONTRACT_v2.0.0.md").read_text(encoding="utf-8")

checks = {
    "app version 0.5.123": "versionCode 123" in gradle and "versionName '0.5.123-sbp-direct-services-audit'" in gradle,
    "direct contour remains independent": "SBP_DIRECT_JL22" in contract and "Kozen может быть" in contract,
    "audit calls channel available services": 'iretail/channel/get-available-services-in' in audit,
    "audit calls recent incoming payments read-only": 'iretail/channel/get-payments-in' in audit,
    "audit reads used service list": 'service-in/get-used' in audit,
    "audit reads global service list": 'service-in/get-service-in-list' in audit,
    "audit never invokes payment create": not bool(re.search(r'Invoke-ReadOnlyApi\s+"[^"]+"\s+"iretail/payment-in/create"', audit, re.I)),
    "audit never invokes payment revert": not bool(re.search(r'Invoke-ReadOnlyApi\s+"[^"]+"\s+"iretail/payment-in/revert"', audit, re.I)),
    "audit has no Kozen transport dependency": "KozenAoaPaymentClient" not in audit and "com.skytech" not in audit and not bool(re.search(r'\badb(?:\.exe)?\s+(?:connect|devices|-s|shell|install|logcat|push|pull)', audit, re.I)),
    "runner has no ADB command": not bool(re.search(r'\badb(?:\.exe)?\s+(?:connect|devices|-s|shell|install|logcat|push|pull)', runner, re.I)),
    "runner auto-publishes": "Publish-TestArtifact.ps1" in runner and "AUTO_PUBLISH_OK" in runner,
    "runner says no manual upload": "No manual archive upload is required." in runner,
    "publisher refuses pre-staged changes": "Git index already contains staged changes" in publisher,
    "publisher stages only artifact and sha": "git -C $repo add -- $relative $shaRelative" in publisher,
    "publisher pushes current branch": 'git -C $repo push origin ("HEAD:" + $branch)' in publisher,
    "publisher creates SHA256 sidecar": "Get-FileHash -Algorithm SHA256" in publisher,
    "publisher does not git add dot": "git add ." not in publisher.lower(),
    "runner uses current branch": "v0.5.123-sbp-direct-services-audit" in runner,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)

if failed:
    raise SystemExit("v0.5.123 direct SBP services audit guard failed: " + ", ".join(failed))

print(f"[OK] v0.5.123 direct SBP services audit guard: {len(checks)} checks passed")
