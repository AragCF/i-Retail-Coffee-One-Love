from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
gradle=(ROOT/"app/build.gradle").read_text(encoding="utf-8")
store=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/SbpSessionStore.kt").read_text(encoding="utf-8")
sbp=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/SbpDryRun.kt").read_text(encoding="utf-8")
main=(ROOT/"app/src/main/java/com/coffeeonelove/iretail/ui/MainActivity.kt").read_text(encoding="utf-8")
runner=(ROOT/"MAIN_33_SBP_TTL_IDEMPOTENCY_SMOKE.bat").read_text(encoding="utf-8")

checks={
    "versionCode 114+": bool(re.search(r"versionCode\s+(114|11[5-9]|1[2-9]\d|[2-9]\d{2,})",gradle)),
    "versionName v0.5.114": "versionName '0.5.114-sbp-expiry-idempotency'" in gradle,
    "snapshot has created/expires": "val createdAtMs: Long" in sbp and "val expiresAtMs: Long" in sbp,
    "default TTL exists": "DEFAULT_TTL_MS: Long = 120_000L" in sbp,
    "minimum TTL exists": "MIN_TTL_MS: Long = 250L" in sbp,
    "active current auto-expires": "System.currentTimeMillis() >= value.expiresAtMs" in sbp and "SbpPaymentState.EXPIRED" in sbp,
    "active start reuses current": "val existing = current()" in sbp and "return existing" in sbp,
    "real payment remains uncertain": "stored.realPaymentSent -> SbpPaymentState.UNCERTAIN" in sbp,
    "expired persisted no-payment session becomes expired": "stored.expiresAtMs > 0L && now >= stored.expiresAtMs -> SbpPaymentState.EXPIRED" in sbp,
    "confirm after expiry blocked": sbp.count("if (value.state == SbpPaymentState.EXPIRED) return value") >= 2,
    "store persists TTL": "KEY_CREATED_AT" in store and "KEY_EXPIRES_AT" in store,
    "store still has no QR token keys": "KEY_QR" not in store,
    "self-test entrypoint": "sbp_expiry_idempotency_self_test" in main,
    "self-test uses short isolated TTL": "DryRunSbpPaymentAdapter(store = null, ttlMs = 600L)" in main,
    "self-test checks same session": "sameBeforeExpiry" in main,
    "self-test checks expired confirm": "confirmBlocked" in main,
    "self-test checks new generation": "newAfterExpiry" in main,
    "runner starts expiry test": "--ez sbp_expiry_idempotency_self_test true" in runner,
    "runner requires all invariants": all(x in runner for x in ["sameBeforeExpiry=true","expired=true","confirmBlocked=true","newAfterExpiry=true","realPaymentSent=false"]),
    "runner no Kozen dependency": "KOZEN" not in runner,
    "runner never enables real POS": "--ez real_pos_enabled true" not in runner,
    "runner has no financial adb command": not bool(re.search(r"adb[^\n\r]*\b(?:PAYMENT|QRPAYMENT|QR_PAYMENT|REFUND|CANCEL)\b",runner,re.I)),
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items():
    print(("[OK] " if v else "[FAIL] ")+k)
if failed:
    raise SystemExit("v0.5.114 SBP expiry/idempotency guard failed: "+", ".join(failed))
print(f"[OK] v0.5.114 SBP expiry/idempotency guard: {len(checks)} checks passed")
