"""
Calculates today's prayer times and writes them to cache.json.

Usage:
    python3 get_times.py <cache_path> auto
    python3 get_times.py <cache_path> manual <lat> <lon> <utc_offset_hours>

"auto" mode resolves the machine's approximate location via IP-based
geolocation (no local config needed, nothing hardcoded). "manual" mode
uses the lat/lon/UTC-offset passed in from the plugin's settings.
"""

import sys
import json
import datetime
import urllib.request
from datetime import timezone, timedelta

import salat

try:
    from zoneinfo import ZoneInfo
except ImportError:
    ZoneInfo = None

IP_GEOLOCATION_URL = "http://ip-api.com/json/?fields=status,message,lat,lon,timezone"


def geolocate_by_ip():
    """Best-effort IP-based geolocation. Returns (lat, lon, utc_offset_hours)."""
    req = urllib.request.Request(IP_GEOLOCATION_URL, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=8) as resp:
        data = json.loads(resp.read().decode("utf-8"))

    if data.get("status") != "success":
        raise RuntimeError(data.get("message", "IP geolocation lookup failed"))

    lat = float(data["lat"])
    lon = float(data["lon"])
    tz_name = data.get("timezone")

    offset_hours = 0.0
    if tz_name and ZoneInfo is not None:
        now = datetime.datetime.now(ZoneInfo(tz_name))
        offset_hours = now.utcoffset().total_seconds() / 3600

    return lat, lon, offset_hours


# ── Offline Gregorian → Hijri conversion ─────────────────────────────────────
def gregorian_to_hijri(year, month, day):
    """Pure-math Gregorian to Hijri conversion (Kuwaiti algorithm)."""
    if month < 3:
        year -= 1
        month += 12
    a = int(year / 100)
    b = 2 - a + int(a / 4)

    JD = int(365.25 * (year + 4716)) + int(30.6001 * (month + 1)) + day + b - 1524.5
    JDN = int(JD)

    l = JDN - 1948440 + 10632
    n2 = int(l / 10631)
    l = l - 10631 * n2 + 354
    j2 = int((10985 - l) / 5316) * int((50 * l) / 17719) + int(l / 5670) * int(
        (43 * l) / 15238
    )
    l = (
        l
        - int((30 - j2) / 15) * int((17719 * j2) / 50)
        - int(j2 / 16) * int((15238 * j2) / 43)
        + 29
    )
    H_month = int((24 * l) / 709)
    H_day = l - int((709 * H_month) / 24)
    H_year = 30 * n2 + j2 - 30

    return H_year, H_month, H_day


HIJRI_MONTHS_AR = [
    "",
    "محرم",
    "صفر",
    "ربيع الأول",
    "ربيع الآخر",
    "جمادى الأولى",
    "جمادى الآخرة",
    "رجب",
    "شعبان",
    "رمضان",
    "شوال",
    "ذو القعدة",
    "ذو الحجة",
]


def main():
    if len(sys.argv) < 3:
        print("error: usage: get_times.py <cache_path> auto|manual [lat lon utc_offset]")
        sys.exit(1)

    cache_path = sys.argv[1]
    mode = sys.argv[2]

    if mode == "auto":
        try:
            lat, lon, tz_offset = geolocate_by_ip()
        except Exception as e:
            print(f"error: auto-location failed ({e}); check your internet connection "
                  f"or switch to manual coordinates in settings")
            sys.exit(1)
    elif mode == "manual":
        if len(sys.argv) < 6:
            print("error: manual mode requires <lat> <lon> <utc_offset>")
            sys.exit(1)
        try:
            lat = float(sys.argv[3])
            lon = float(sys.argv[4])
            tz_offset = float(sys.argv[5])
        except ValueError:
            print("error: latitude, longitude, and UTC offset must be numeric")
            sys.exit(1)
    else:
        print(f"error: unknown mode '{mode}' (expected 'auto' or 'manual')")
        sys.exit(1)

    tz = timezone(timedelta(hours=tz_offset))
    date = datetime.date.today()

    pt = salat.PrayerTimes(salat.CalculationMethod.EGYPT, salat.AsrMethod.STANDARD)
    times = pt.calc_times(date, tz, lon, lat)

    h_year, h_month, h_day = gregorian_to_hijri(date.year, date.month, date.day)
    hijri_str = f"{h_day} {HIJRI_MONTHS_AR[h_month]} {h_year}"

    imsak = (times["fajr"] - timedelta(minutes=10)).strftime("%H:%M")

    data = {
        "times": [
            times["fajr"].strftime("%H:%M"),
            times["sunrise"].strftime("%H:%M"),
            times["dhuhr"].strftime("%H:%M"),
            times["asr"].strftime("%H:%M"),
            times["maghrib"].strftime("%H:%M"),
            times["isha"].strftime("%H:%M"),
            imsak,
        ],
        "imsak": imsak,
        "hijri": hijri_str,
        "date": str(date),
    }

    with open(cache_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)

    print("done:", data)


if __name__ == "__main__":
    main()