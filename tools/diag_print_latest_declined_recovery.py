from pathlib import Path
from zipfile import ZipFile
root=Path(__file__).resolve().parents[1]
d=root/"test_reports"/"declined_payment_recovery"
zips=sorted(d.glob("DECLINED_PAYMENT_RECOVERY_*.zip"))
if not zips:
    raise SystemExit("no recovery zip")
latest=zips[-1]
print("[REPORT]", latest.name)
with ZipFile(latest) as z:
    for name in z.namelist():
        print("\n=====",name,"=====")
        print(z.read(name).decode("utf-8","replace"))
