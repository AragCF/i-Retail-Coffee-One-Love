from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
probe = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/IretailTlsChainProbe.kt").read_text(encoding="utf-8")
main = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
diag = (ROOT / "S2_02_CATALOG_DIAGNOSTICS.bat").read_text(encoding="utf-8")
build = (ROOT / "app/build.gradle").read_text(encoding="utf-8")

checks = {
    "probe delegates to system trust": "systemTrust.checkServerTrusted(chain, authType)" in probe,
    "probe logs chain size": '"CHAIN host=' in probe and 'size=${chain.size}' in probe,
    "probe logs certificate issuer": "issuer=" in probe,
    "probe logs certificate subject": "subject=" in probe,
    "probe logs SHA256": "sha256=" in probe,
    "probe rethrows certificate failure": "throw e" in probe,
    "probe does not override HostnameVerifier": "HostnameVerifier" not in probe,
    "probe has no trust-all return": "return true" not in probe,
    "probe only runs via explicit intent": 'getBooleanExtra("tls_chain_probe", false)' in main,
    "diagnostic intent enables probe": "--ez tls_chain_probe true" in diag,
    "diagnostic log captures TLS tag": "IretailTls:V" in diag,
    "fast capture script exists": (ROOT / "S2_04_CAPTURE_TLS_CHAIN_ONLY.bat").exists(),
    "fast capture uses verbose TLS filter": "IretailTls:V" in (ROOT / "S2_04_CAPTURE_TLS_CHAIN_ONLY.bat").read_text(encoding="utf-8"),
    "fast capture checks CHAIN": "CHAIN " in (ROOT / "S2_04_CAPTURE_TLS_CHAIN_ONLY.bat").read_text(encoding="utf-8"),
    "fast capture checks CERT": "CERT " in (ROOT / "S2_04_CAPTURE_TLS_CHAIN_ONLY.bat").read_text(encoding="utf-8"),
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)
if failed:
    raise SystemExit("TLS chain probe guard failed: " + ", ".join(failed))
print(f"[OK] TLS chain probe guard: {len(checks)} checks passed")
