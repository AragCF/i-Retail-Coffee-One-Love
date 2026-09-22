from __future__ import annotations

import html
import re
import ssl
import urllib.request
from urllib.parse import urljoin

BASE = "https://my.i-retail.com/api/apidoc/actual/"
INDEX = urljoin(BASE, "index.html")
ctx = ssl.create_default_context()

def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent":"CoffeeOneLove-S3-Permission-Docs/1.0"})
    with urllib.request.urlopen(req, timeout=30, context=ctx) as r:
        data = r.read()
        print(f"[FETCH] {url} status={getattr(r,'status','')} bytes={len(data)}")
        return data.decode("utf-8", errors="replace")

def textify(raw: str) -> str:
    value = re.sub(r"(?is)<script.*?</script>", " ", raw)
    value = re.sub(r"(?is)<style.*?</style>", " ", value)
    value = re.sub(r"(?is)<[^>]+>", " ", value)
    value = html.unescape(value)
    return re.sub(r"\s+", " ", value).strip()

index = fetch(INDEX)
hrefs = sorted(set(m.group(1) for m in re.finditer(r'href="([^"]+)"', index, flags=re.I)))

keywords = ("usercontroller","role","permission","access","authentication","profilecontroller","merchant")
candidates = []
for href in hrefs:
    low = href.lower()
    if any(k in low for k in keywords):
        candidates.append(href)

print("[CANDIDATE_PAGES]")
for href in candidates:
    print(href)

for href in candidates:
    url = urljoin(BASE, href.lstrip("./"))
    try:
        raw = fetch(url)
    except Exception as exc:
        print(f"[FETCH_ERROR] {href}: {type(exc).__name__}: {exc}")
        continue

    text = textify(raw)
    print("=" * 100)
    print("[PAGE] " + href)

    endpoints = []
    for m in re.finditer(r"/api/[A-Za-z0-9_./-]+", text):
        ep = m.group(0).rstrip(".,;:)]}")
        if ep not in endpoints:
            endpoints.append(ep)

    print("[ENDPOINTS]")
    for ep in endpoints:
        print(ep)

    hit_any = False
    for term in (
        "permission", "permissions", "role", "roles", "access", "rights",
        "authentication", "authorize", "current user", "profile",
        "merchant", "admin", "device/create", "device management"
    ):
        matches = list(re.finditer(re.escape(term), text, flags=re.I))
        if not matches:
            continue
        hit_any = True
        print()
        print("[TERM] " + term)
        for m in matches[:4]:
            start=max(0,m.start()-900)
            end=min(len(text),m.start()+2200)
            print(text[start:end])
            print()

    if not hit_any:
        print("[NO_PERMISSION_TERMS]")

print("[SAFETY]")
print("Only public documentation GET requests were made; no authentication or working API call.")
