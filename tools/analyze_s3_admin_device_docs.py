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
    req = urllib.request.Request(url, headers={"User-Agent": "CoffeeOneLove-S3-Docs-Audit/1.0"})
    with urllib.request.urlopen(req, timeout=30, context=ctx) as r:
        data = r.read()
        print(f"[FETCH] {url} status={getattr(r, 'status', '')} bytes={len(data)}")
        return data.decode("utf-8", errors="replace")

def textify(raw: str) -> str:
    value = re.sub(r"(?is)<script.*?</script>", " ", raw)
    value = re.sub(r"(?is)<style.*?</style>", " ", value)
    value = re.sub(r"(?is)<[^>]+>", " ", value)
    value = html.unescape(value)
    return re.sub(r"\s+", " ", value).strip()

index = fetch(INDEX)
hrefs = sorted(set(m.group(1) for m in re.finditer(r'href="([^"]+)"', index, flags=re.I)))

device_links = []
for href in hrefs:
    low = href.lower()
    if "devicecontroller" in low or ("device" in low and "controller" in low):
        device_links.append(href)

print("[DEVICE_CONTROLLER_LINKS]")
for href in device_links:
    print(href)

admin_links = [x for x in device_links if "admin" in x.lower()]
if not admin_links:
    print("[ADMIN_DEVICE_CONTROLLER] NOT_FOUND")
else:
    print("[ADMIN_DEVICE_CONTROLLER_LINKS]")
    for href in admin_links:
        print(href)

targets = admin_links or device_links

for href in targets:
    url = urljoin(BASE, href.lstrip("./"))
    raw = fetch(url)
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
        if "/device" in ep.lower() or "/devices" in ep.lower():
            print(ep)

    for term in (
        "create", "add", "save", "new device", "device type",
        "workplace_cashier", "self_service_terminal", "coffee_machine",
        "external_code", "device_code", "channel_id", "profile_id",
        "trade_point_id", "cashier", "terminal"
    ):
        matches = list(re.finditer(re.escape(term), text, flags=re.I))
        if not matches:
            continue
        print()
        print("[TERM] " + term)
        for m in matches[:4]:
            start = max(0, m.start() - 900)
            end = min(len(text), m.start() + 2200)
            print(text[start:end])
            print()

print("[SAFETY]")
print("Only public documentation GET requests were made. No authentication and no working API calls.")
