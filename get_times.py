"""
Calculates today's prayer times and writes them to cache.json.

Usage:
    python3 get_times.py <cache_path> auto [options]
    python3 get_times.py <cache_path> manual <lat> <lon> <utc_offset_hours> [options]

Options:
    --method <egypt|mwl|makkah|karachi|isna|tehran|jafari>
    --asr <standard|hanafi>
    --hijri-offset <days>

"auto" mode resolves the machine's approximate location via IP-based
geolocation (no local config needed, nothing hardcoded). "manual" mode
uses the lat/lon/UTC-offset passed in from the plugin's settings.
"""

import os
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

# Human-friendly keys used by the plugin settings mapped to salat enums.
CALCULATION_METHODS = {
    "egypt": salat.CalculationMethod.EGYPT,
    "mwl": salat.CalculationMethod.MWL,
    "makkah": salat.CalculationMethod.MAKKAH,
    "karachi": salat.CalculationMethod.KARACHI,
    "isna": salat.CalculationMethod.ISNA,
    "tehran": salat.CalculationMethod.TEHRAN,
    "jafari": salat.CalculationMethod.JAFARI,
}

ASR_METHODS = {
    "standard": salat.AsrMethod.STANDARD,
    "hanafi": salat.AsrMethod.HANAFI,
}

DEFAULT_OPTIONS = {
    "method": "egypt",
    "asr": "standard",
    "hijri_offset": 0,
}


def parse_options(argv):
    """Split trailing --options from positional arguments.

    Returns (positional, options). Options may use "--name value" or
    "--name=value" form and can appear in any order after the mode.
    """
    positional = []
    options = dict(DEFAULT_OPTIONS)
    index = 0

    while index < len(argv):
        token = argv[index]
        if token.startswith("--"):
            name = token[2:]
            value = None
            if "=" in name:
                name, value = name.split("=", 1)
            if value is None:
                if index + 1 >= len(argv):
                    raise ValueError(f"missing value for --{name}")
                index += 1
                value = argv[index]

            if name == "method":
                options["method"] = value
            elif name == "asr":
                options["asr"] = value
            elif name == "hijri-offset":
                options["hijri_offset"] = int(float(value))
            else:
                raise ValueError(f"unknown option --{name}")
        else:
            positional.append(token)
        index += 1

    return positional, options


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
    JDN = int(JD + 0.5)

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
    try:
        positional, options = parse_options(sys.argv[1:])
    except ValueError as e:
        print(f"error: {e}")
        sys.exit(1)

    if len(positional) < 2:
        print("error: usage: get_times.py <cache_path> auto|manual [lat lon utc_offset] [options]")
        sys.exit(1)

    cache_path = positional[0]
    mode = positional[1]

    if mode == "auto":
        try:
            lat, lon, tz_offset = geolocate_by_ip()
        except Exception as e:
            print(f"error: auto-location failed ({e}); check your internet connection "
                  f"or switch to manual coordinates in settings")
            sys.exit(1)
    elif mode == "manual":
        if len(positional) < 5:
            print("error: manual mode requires <lat> <lon> <utc_offset>")
            sys.exit(1)
        try:
            lat = float(positional[2])
            lon = float(positional[3])
            tz_offset = float(positional[4])
        except ValueError:
            print("error: latitude, longitude, and UTC offset must be numeric")
            sys.exit(1)
    else:
        print(f"error: unknown mode '{mode}' (expected 'auto' or 'manual')")
        sys.exit(1)

    method_key = str(options["method"]).lower()
    asr_key = str(options["asr"]).lower()
    calc_method = CALCULATION_METHODS.get(method_key, salat.CalculationMethod.EGYPT)
    asr_method = ASR_METHODS.get(asr_key, salat.AsrMethod.STANDARD)

    tz = timezone(timedelta(hours=tz_offset))
    date = datetime.date.today()

    makkah_fallback = False
    try:
        pt = salat.PrayerTimes(calc_method, asr_method)
    except ImportError:
        # The Umm al-Qura method needs the optional hijri-converter package
        # for its Ramadan Isha adjustment. Keep working with a close
        # approximation instead of failing the whole refresh.
        if method_key != "makkah":
            raise
        from salat.methods import GeneralMethod

        print("warning: install hijri-converter for exact Umm al-Qura times; "
              "using a 90-minute Isha approximation")
        pt = GeneralMethod(18.5, 18.5, asr_method)
        makkah_fallback = True

    times = pt.calc_times(date, tz, lon, lat)
    if makkah_fallback:
        times["isha"] = times["maghrib"] + timedelta(minutes=90)

    hijri_date = date + timedelta(days=options["hijri_offset"])
    h_year, h_month, h_day = gregorian_to_hijri(
        hijri_date.year, hijri_date.month, hijri_date.day
    )
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
        "method": method_key,
        "asr": asr_key,
        "hijri_offset": options["hijri_offset"],
    }

    os.makedirs(os.path.dirname(os.path.abspath(cache_path)), exist_ok=True)
    with open(cache_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)

    print("done:", data)


if __name__ == "__main__":
    main()