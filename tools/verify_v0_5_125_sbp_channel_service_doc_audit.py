from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")
audit=(ROOT/"tools/iRetailSbpChannelServiceDocsAudit.ps1").read_text(encoding="utf-8")
runner=(ROOT/"MAIN_40_SBP_CHANNEL_SERVICE_DOC_AUDIT.bat").read_text(encoding="utf-8")
publisher=(ROOT/"tools/Publish-TestArtifact.ps1").read_text(encoding="utf-8")
analyzer=(ROOT/"tools/analyze_sbp_channel_service_docs_report.py").read_text(encoding="utf-8")

checks={
    "app version 0.5.125":"versionCode 125" in gradle and "versionName '0.5.125-sbp-channel-service-doc-audit'" in gradle,
    "docs audit targets index":"index.html" in audit and "my.i-retail.com/api/apidoc/actual" in audit,
    "docs audit searches channel/service/admin pages":all(x in audit for x in ["channel","service","shop","admin"]),
    "docs audit searches SBP configuration terms":all(x in audit for x in ["shop_verified","service_in_slug","sbp_low_risk","offline_shop_id"]),
    "docs audit has no authentication":"user/authentication" not in audit and "access_token" not in audit,
    "docs audit has no working API mutation":not bool(re.search(r'Invoke-CurlToFile\s+\(\$baseUrl',audit,re.I)),
    "runner auto-publishes":"Publish-TestArtifact.ps1" in runner and "AUTO_PUBLISH_OK" in runner,
    "runner says no manual upload":"No manual archive upload is required." in runner,
    "runner states zero working API calls":"Working API calls: 0" in runner,
    "analyzer consumes committed ZIP":"SBP_CHANNEL_SERVICE_DOCS_*.zip" in analyzer and "04_route_candidates.json" in analyzer,
    "publisher stages only artifact and sha":"git -C $repo add -- $relative $shaRelative" in publisher and "git add ." not in publisher.lower(),
}

failed=[name for name,ok in checks.items() if not ok]
for name,ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ")+name)
if failed:
    raise SystemExit("v0.5.125 SBP channel/service docs audit guard failed: "+", ".join(failed))
print(f"[OK] v0.5.125 SBP channel/service docs audit guard: {len(checks)} checks passed")
