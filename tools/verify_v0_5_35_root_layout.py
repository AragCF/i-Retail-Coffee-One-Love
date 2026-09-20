from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OLD = "iRetail_Android_UI_v0.5.8_" + "smartskypos_probe_source"

checks = []

def require(name: str, condition: bool) -> None:
    checks.append((name, condition))
    if not condition:
        raise SystemExit(f"[FAIL] {name}")

require("settings.gradle is in repository root", (ROOT / "settings.gradle").is_file())
require("app module is in repository root", (ROOT / "app").is_dir())
require("docs are in repository root", (ROOT / "docs").is_dir())
require("tools are in repository root", (ROOT / "tools").is_dir())
require("old nested project directory is absent", not (ROOT / OLD).exists())

build = (ROOT / "app/build.gradle").read_text(encoding="utf-8")
builder = (ROOT / "BUILD_WINDOWS_CLI.bat").read_text(encoding="utf-8", errors="replace")
readme = (ROOT / "README.md").read_text(encoding="utf-8")

require("versionCode 35", "versionCode 35" in build)
require("versionName 0.5.35-root-layout", "versionName '0.5.35-root-layout'" in build)
require("Windows build script version 0.5.35", "SCRIPT_VERSION=0.5.35-root-layout" in builder)
require("README declares root layout", "0.5.35-root-layout" in readme)

active = []
active.extend(ROOT.glob("*.bat"))
active.extend((ROOT / ".github/workflows").glob("*.yml"))
active.extend((ROOT / ".github/workflows").glob("*.yaml"))
active.extend((ROOT / "tools").rglob("*.py"))
active.extend((ROOT / "tools").rglob("*.ps1"))
active.extend((ROOT / "tools").rglob("*.bat"))
active.extend([ROOT / "settings.gradle", ROOT / "build.gradle", ROOT / "gradle.properties"])

bad = []
for path in active:
    if not path.is_file() or path.resolve() == Path(__file__).resolve():
        continue
    text = path.read_text(encoding="utf-8", errors="replace")
    if OLD in text:
        bad.append(str(path.relative_to(ROOT)))

if bad:
    print("[DETAIL] Old nested path is still referenced by:")
    for item in bad:
        print(" - " + item)
require("active scripts/workflows do not reference old nested path", not bad)

print(f"[OK] v0.5.35 root-layout guard: {len(checks)} checks passed")
