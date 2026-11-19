"""
Fetches the list of Quran reciters (and their "moshaf" / riwayah variants)
from the public mp3quran.net API and caches it locally as reciters.json,
so the plugin's Quran panel can browse and stream recitations.

API reference: https://www.mp3quran.net/ar/api
Endpoint used: https://www.mp3quran.net/api/v3/reciters?language=ar

Each moshaf entry has a "server" base URL. The audio file for a given surah
is built as: server + zero-padded-3-digit-surah-number + ".mp3"
e.g. https://server6.mp3quran.net/thubti/098.mp3

Usage:
    python3 fetch_reciters.py <cache_path>
"""

import os
import sys
import json
import urllib.request

API_URL = "https://www.mp3quran.net/api/v3/reciters?language=ar"


def fetch(cache_path):
    req = urllib.request.Request(API_URL, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        raw = json.loads(resp.read().decode("utf-8"))

    reciters = []
    for r in raw.get("reciters", []):
        for m in r.get("moshaf", []):
            server = m.get("server", "")
            if not isinstance(server, str) or not server.startswith("https://"):
                continue
            reciters.append(
                {
                    "id": r.get("id"),
                    "name": r.get("name", ""),
                    "moshaf_name": m.get("name", ""),
                    "server": server,
                    "surah_list": m.get("surah_list", ""),
                }
            )

    # Sort alphabetically (Arabic) by reciter name for a predictable browsing order
    reciters.sort(key=lambda x: x["name"])

    os.makedirs(os.path.dirname(os.path.abspath(cache_path)), exist_ok=True)
    with open(cache_path, "w", encoding="utf-8") as f:
        json.dump({"reciters": reciters}, f, ensure_ascii=False)

    print(f"done: cached {len(reciters)} moshaf entries")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("error: usage: fetch_reciters.py <cache_path>")
        sys.exit(1)
    try:
        fetch(sys.argv[1])
    except Exception as e:
        print(f"error: {e}")
        sys.exit(1)