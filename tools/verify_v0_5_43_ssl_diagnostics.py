from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

models = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/Models.kt").read_text(encoding="utf-8")
gateways = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/IntegrationGateways.kt").read_text(encoding="utf-8")
main = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
diag = (ROOT / "S2_02_CATALOG_DIAGNOSTICS.bat").read_text(encoding="utf-8")
build = (ROOT / "app/build.gradle").read_text(encoding="utf-8")

checks = {
    "versionCode 43": "versionCode 43" in build,
    "versionName 0.5.43": "versionName '0.5.43-s2-jl22-ssl-diagnostics'" in build,
    "failure detail field exists": "val failureDetail: String? = null" in models,
    "SSL handshake classified": '"SSL_HANDSHAKE"' in gateways,
    "SSL peer verification classified": '"SSL_PEER_UNVERIFIED"' in gateways,
    "SSL protocol classified": '"SSL_PROTOCOL"' in gateways,
    "SSL key classified": '"SSL_KEY"' in gateways,
    "generic SSL fallback remains": 'is javax.net.ssl.SSLException -> "SSL"' in gateways,
    "safe class-chain detail exists": 'safeCatalogFailureDetail' in gateways and 'javaClass.simpleName' in gateways,
    "failure detail is logged": 'failureDetail=${result.failureDetail ?: "-"}' in main,
    "device UTC time captured": '04c_date_utc.txt' in diag,
    "timezone captured": '04d_timezone.txt' in diag,
    "auto time captured": '04e_auto_time.txt' in diag,
    "system CA count captured": '04f_system_ca_count.txt' in diag,
    "security patch captured": '04b_security_patch.txt' in diag,
    "no permissive HostnameVerifier": "HostnameVerifier" not in gateways,
    "no custom X509TrustManager": "X509TrustManager" not in gateways,
    "no SSL verification disable": "setDefaultSSLSocketFactory" not in gateways and "ALLOW_ALL" not in gateways,
    "HTTPS base remains": "https://my.i-retail.com/api/" in gateways,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)

if failed:
    raise SystemExit("v0.5.43 SSL diagnostics guard failed: " + ", ".join(failed))

print(f"[OK] v0.5.43 SSL diagnostics guard: {len(checks)} checks passed")
