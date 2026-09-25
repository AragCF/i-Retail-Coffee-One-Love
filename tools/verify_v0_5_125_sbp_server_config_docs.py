from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")
audit=(ROOT/"tools/iRetailSbpServerConfigDocsAudit.ps1").read_text(encoding="utf-8")
runner=(ROOT/"MAIN_40_SBP_SERVER_CONFIG_DOC_AUDIT.bat").read_text(encoding="utf-8")
publisher=(ROOT/"tools/Publish-TestArtifact.ps1").read_text(encoding="utf-8")
analyzer=(ROOT/"tools/analyze_sbp_server_config_docs.py").read_text(encoding="utf-8")

version_code_match = re.search(r"versionCode\s+(\d+)", gradle)
version_name_match = re.search(r"versionName\s+'([^']+)'", gradle)
version_code = int(version_code_match.group(1)) if version_code_match else 0
version_name = version_name_match.group(1) if version_name_match else ""

checks={
    "app version 0.5.125+": version_code >= 125 and bool(version_name),
    "audit only downloads documentation":"user/authentication" not in audit and "access_token" not in audit and "Invoke-ReadOnlyApi" not in audit,
    "audit has candidate admin docs":all(x in audit for x in [
        "app-controllers-admin-channelcontroller.html",
        "app-controllers-admin-serviceincontroller.html",
        "app-controllers-admin-onlineshopcontroller.html",
        "app-controllers-admin-tradepointcontroller.html",
    ]),
    "audit includes ordinary and iRetail config docs":all(x in audit for x in [
        "app-controllers-channelcontroller.html",
        "app-controllers-serviceincontroller.html",
        "app-controllers-iretail-channelcontroller.html",
        "app-controllers-iretail-paymentincontroller.html",
    ]),
    "audit searches verification and service settings":all(x in audit for x in ["verify","verified","enable","enabled","lock_service","sbp","sbp_low_risk","process_input"]),
    "audit has no state-changing curl":not bool(re.search(r'curl\.exe[^\n\r]*(--request|-X)\s*(POST|PUT|PATCH|DELETE)',audit,re.I)),
    "audit has no Kozen or ADB":"KozenAoaPaymentClient" not in audit and "com.skytech" not in audit and not bool(re.search(r'\badb(?:\.exe)?\s+',audit,re.I)),
    "runner auto-publishes":"Publish-TestArtifact.ps1" in runner and "AUTO_PUBLISH_OK" in runner,
    "runner states public docs only":"Public documentation GET only." in runner and "No authentication." in runner,
    "runner says no manual upload":"No manual archive upload is required." in runner,
    "publisher stages only explicit artifact":"git -C $repo add -- $relative $shaRelative" in publisher and "git add ." not in publisher.lower(),
    "analyzer consumes committed docs ZIP":"SBP_SERVER_CONFIG_DOCS_*.zip" in analyzer and "04_mutating_candidates.json" in analyzer,
}

failed=[name for name,ok in checks.items() if not ok]
for name,ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ")+name)
if failed:
    raise SystemExit("v0.5.125 SBP server config docs audit guard failed: "+", ".join(failed))
print(f"[OK] v0.5.125 SBP server config docs audit guard: {len(checks)} checks passed")
