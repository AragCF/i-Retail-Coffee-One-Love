from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
build = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
audit = (ROOT / "S23_01_BUILD_INSTALL_ACCEPTANCE_AUDIT.bat").read_text(encoding="utf-8")
gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")

checks = {
    "versionCode 38": "versionCode 38" in build,
    "versionName 0.5.38": "versionName '0.5.38-s2-s3-acceptance'" in build,
    "combined audit exists": "SAFE S2 + S3 ACCEPTANCE" in audit,
    "audit forbids payment selection": "DO NOT choose card, cash or online payment" in audit,
    "audit forces real POS off": "--ez real_pos_enabled false" in audit,
    "audit extracts local draft": "order_sync_draft.json" in audit,
    "audit parses JSON with PowerShell": "ConvertFrom-Json" in audit,
    "audit requires DRY_RUN_ONLY": "$p.mode -ne 'DRY_RUN_ONLY'" in audit,
    "audit requires send_allowed false": "$p.send_allowed -ne $false" in audit,
    "audit checks exact line sum": "$p.validation.lines_equal_gross -ne $true" in audit,
    "nested builds ignored": "**/build/" in gitignore,
    "runtime logs ignored": "*_logs/" in gitignore,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)
if failed:
    raise SystemExit("v0.5.38 acceptance guard failed: " + ", ".join(failed))
print(f"[OK] v0.5.38 acceptance guard: {len(checks)} checks passed")
