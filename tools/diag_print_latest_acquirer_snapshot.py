from pathlib import Path
from zipfile import ZipFile

root=Path(__file__).resolve().parents[1]
d=root/"test_reports"/"acquirer_snapshot"
zips=sorted(d.glob("ACQUIRER_SNAPSHOT_*.zip"))
if not zips:
    raise SystemExit("no acquirer snapshot zip")
latest=zips[-1]
print("[REPORT]",latest.name)
with ZipFile(latest) as z:
    for name in z.namelist():
        print("\n=====",name,"=====")
        print(z.read(name).decode("utf-8","replace"))
