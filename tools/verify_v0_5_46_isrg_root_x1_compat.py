from pathlib import Path
import base64
import hashlib
import re

ROOT = Path(__file__).resolve().parents[1]

build = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
compat = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/IretailTlsCompat.kt").read_text(encoding="utf-8")
gateways = (ROOT / "app/src/main/java/com/coffeeonelove/iretail/ui/IntegrationGateways.kt").read_text(encoding="utf-8")
diag = (ROOT / "S2_02_CATALOG_DIAGNOSTICS.bat").read_text(encoding="utf-8")
pem_text = (ROOT / "app/src/main/assets/certs/isrgrootx1.pem").read_text(encoding="utf-8")

pem_body = re.sub(r"-----BEGIN CERTIFICATE-----|-----END CERTIFICATE-----|\s+", "", pem_text)
der = base64.b64decode(pem_body)
pem_sha256 = hashlib.sha256(der).hexdigest()
expected_sha256 = "96bcec06264976f37460779acf28c5a7cfe8a3c0aae11a8ffcee05c0bddf08c6"

checks = {
    "versionCode 46": "versionCode 46" in build,
    "versionName 0.5.46": "versionName '0.5.46-s2-isrg-root-x1-compat'" in build,
    "official root fingerprint matches": pem_sha256 == expected_sha256,
    "compat code pins expected fingerprint": expected_sha256 in compat,
    "compat is Android 6 only": "Build.VERSION.SDK_INT > Build.VERSION_CODES.M" in compat,
    "compat is exact I-Retail host only": 'LEGACY_HOST = "my.i-retail.com"' in compat,
    "system trust is attempted first": "systemTrust.checkServerTrusted(chain, authType)" in compat,
    "extra root trust is fallback": "extraTrust.checkServerTrusted(chain, authType)" in compat,
    "no hostname verifier override": "HostnameVerifier" not in compat and "hostnameVerifier" not in compat,
    "no global SSL factory override": "setDefaultSSLSocketFactory" not in compat,
    "no trust-all return": "return true" not in compat,
    "I-Retail connection applies scoped compat": "IretailTlsCompat.applyIfNeeded(context, url, rawConnection)" in gateways,
    "HTTPS request remains HttpsURLConnection-aware": "rawConnection is javax.net.ssl.HttpsURLConnection" in gateways,
    "diagnostics capture compat log": "IretailTlsCompat:I" in diag,
    "live acceptance still checks real ZIP": 'REFRESH success=true source=I-Retail ZIP ' in diag,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)

if failed:
    raise SystemExit("v0.5.46 ISRG Root X1 compatibility guard failed: " + ", ".join(failed))

print(f"[OK] v0.5.46 ISRG Root X1 compatibility guard: {len(checks)} checks passed")
