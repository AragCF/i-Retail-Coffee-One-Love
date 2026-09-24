from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

gradle = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
helper = (ROOT / "tools/WAIT_FOR_JL22.bat").read_text(encoding="utf-8")
dryrun = (ROOT / "MAIN_30_SBP_DRYRUN_UI_TEST.bat").read_text(encoding="utf-8")
queue = (ROOT / "MAIN_34_SBP_EVENT_QUEUE_SYNTHETIC_TEST.bat").read_text(encoding="utf-8")
combined = (ROOT / "MAIN_35_KOZEN_BRIDGE_UPGRADE_AND_SBP_QUEUE_TEST.bat").read_text(encoding="utf-8")
build = (ROOT / "BUILD_WINDOWS_CLI.bat").read_text(encoding="utf-8")

signature = 'product:octopus_jetinno model:UniWin_M190 device:octopus-jetinno'
helper_call = 'tools\\WAIT_FOR_JL22.bat" JL22'

checks = {
    "app version 0.5.117": "versionCode 117" in gradle and "versionName '0.5.117-jl22-wait-loop'" in gradle,
    "build script version 0.5.117": 'SCRIPT_VERSION=0.5.117-jl22-wait-loop' in build,
    "helper matches exact JL22 signature": signature in helper,
    "helper accepts live device": 'if /I "%%B"=="device"' in helper and 'set "FOUND=%%A"' in helper,
    "helper recognizes offline device": 'if /I "%%B"=="offline"' in helper and 'set "OFFLINE=%%A"' in helper,
    "helper attempts network reconnect": 'adb connect "!OFFLINE!"' in helper,
    "helper loops without attempt limit": ":WAIT_LOOP" in helper and "goto WAIT_LOOP" in helper and "for /l" not in helper.lower(),
    "helper waits for arbitrary key": "pause >nul" in helper,
    "helper explicitly documents Ctrl+C abort": "Ctrl+C" in helper,
    "helper returns selected serial": 'set "%OUTVAR%=%%V"' in helper,
    "dry-run uses persistent helper": dryrun.count(helper_call) >= 2,
    "event queue uses persistent helper": queue.count(helper_call) >= 2,
    "combined runner uses persistent helper": combined.count(helper_call) >= 1,
    "dry-run no longer exits merely because JL22 is missing": "Live JL22 not found" not in dryrun,
    "event queue no longer exits merely because JL22 is missing": "Live JL22 not found" not in queue,
    "current version in dry-run": "0.5.117-jl22-wait-loop" in dryrun,
    "current version in event queue": "0.5.117-jl22-wait-loop" in queue,
    "current version in combined runner": "0.5.117-jl22-wait-loop" in combined,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("[OK] " if ok else "[FAIL] ") + name)

if failed:
    raise SystemExit("v0.5.117 JL22 wait-loop guard failed: " + ", ".join(failed))

print(f"[OK] v0.5.117 JL22 wait-loop guard: {len(checks)} checks passed")
