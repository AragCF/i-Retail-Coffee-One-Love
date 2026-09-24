from pathlib import Path
from zipfile import ZipFile

root = Path(__file__).resolve().parents[1]
report_dir = root / "test_reports" / "fiscal_positive_payment_1rub"
zips = sorted(report_dir.glob("FISCAL_POSITIVE_PAYMENT_1RUB_*.zip"))
if not zips:
    raise SystemExit("No fiscal positive payment reports found")
latest = zips[-1]
print(f"[REPORT] {latest.name}")
with ZipFile(latest) as zf:
    names = set(zf.namelist())
    for name in [
        "01_environment.txt",
        "03_machine_mode.txt",
        "04_attempt_marker.txt",
        "05_jl22_logcat.txt",
        "06_kozen_logcat.txt",
        "07_fiscalization_dry_run.json",
        "08_summary.txt",
        "SAFETY_SCAN_OK.txt",
    ]:
        print(f"\\n===== {name} =====")
        if name not in names:
            print("(missing)")
            continue
        data = zf.read(name).decode("utf-8", "replace")
        print(data)
