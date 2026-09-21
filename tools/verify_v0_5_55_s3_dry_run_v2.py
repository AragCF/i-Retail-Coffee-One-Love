from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
build = (ROOT / "BUILD_WINDOWS_CLI.bat").read_text(encoding="utf-8")
audit = (ROOT / "S3_10_BUILD_INSTALL_DRY_RUN_V2_AUDIT.bat").read_text(encoding="utf-8")
publish = (ROOT / "S3_11_PUBLISH_DRY_RUN_V2.bat").read_text(encoding="utf-8")
draft = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/OrderSyncDraft.kt").read_text(encoding="utf-8")
evidence = json.loads((ROOT / "app/src/main/assets/content/s3-order-evidence.json").read_text(encoding="utf-8"))

version_code_match = re.search(r"versionCode\s+(\d+)", gradle)
version_name_match = re.search(r"versionName\s+'([^']+)'", gradle)
build_version_match = re.search(r'SCRIPT_VERSION=([^"\r\n]+)', build)

version_code = int(version_code_match.group(1)) if version_code_match else 0

def patch_number(value: str) -> int:
    m = re.match(r"0\.5\.(\d+)", value or "")
    return int(m.group(1)) if m else -1

version_name = version_name_match.group(1) if version_name_match else ""
build_version = build_version_match.group(1) if build_version_match else ""

checks = {
    "versionCode is not older than v0.5.55": version_code >= 55,
    "versionName is not older than v0.5.55": patch_number(version_name) >= 55,
    "Windows builder is not older than v0.5.55": patch_number(build_version) >= 55,
    "historical v0.5.55 audit branch remains exact": 'EXPECTED_BRANCH=v0.5.55-s3-dry-run-v2' in audit,
    "historical v0.5.55 publisher branch remains exact": 'EXPECTED_BRANCH=v0.5.55-s3-dry-run-v2' in publish,
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
    raise SystemExit("S3 DRY_RUN v2 release guard failed: " + ", ".join(failed))
print(f"[OK] S3 DRY_RUN v2 release guard: {len(checks)} checks passed")
