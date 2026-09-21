from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
build = (ROOT / "BUILD_WINDOWS_CLI.bat").read_text(encoding="utf-8")
audit = (ROOT / "S3_10_BUILD_INSTALL_DRY_RUN_V2_AUDIT.bat").read_text(encoding="utf-8")
publish = (ROOT / "S3_11_PUBLISH_DRY_RUN_V2.bat").read_text(encoding="utf-8")
draft = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/OrderSyncDraft.kt").read_text(encoding="utf-8")
evidence = json.loads((ROOT / "app/src/main/assets/content/s3-order-evidence.json").read_text(encoding="utf-8"))

checks = {
    "versionCode 55": "versionCode 55" in gradle,
    "versionName 0.5.55": "0.5.55-s3-dry-run-v2" in gradle,
    "Windows builder version 0.5.55": "0.5.55-s3-dry-run-v2" in build,
    "audit uses exact branch": 'EXPECTED_BRANCH=v0.5.55-s3-dry-run-v2' in audit,
    "publisher uses exact branch": 'EXPECTED_BRANCH=v0.5.55-s3-dry-run-v2' in publish,
    "audit does not call register": "device/register" not in audit,
    "audit does not call synchronize": "order/synchronize" not in audit,
    "draft has no HTTP primitives": "HttpURLConnection" not in draft and "java.net.URL" not in draft,
    "evidence channel": evidence.get("channel_id") == "5676",
    "evidence currency": evidence.get("currency_id") == "643",
    "stale device not current": evidence.get("server_device_snapshot", {}).get("current_for_new_order") is False,
    "stale shift not current": evidence.get("shift_snapshot", {}).get("current_for_new_order") is False,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)
if failed:
    raise SystemExit("v0.5.55 release guard failed: " + ", ".join(failed))
print(f"[OK] v0.5.55 release guard: {len(checks)} checks passed")
