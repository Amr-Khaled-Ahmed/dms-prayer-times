# Prayer Times

A DankMaterialShell bar widget for displaying Islamic prayer times, fully offline using local astronomical calculations — now with an Athan sound at prayer time and a built-in Quran recitation browser/player.

## Preview

![Screenshot](screenshot.png)

## Features

- Next prayer name and countdown in the DankBar
- Popout view showing all prayer times (Imsak, Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha)
- Hijri and Gregorian date display
- Desktop notifications before prayer time and at prayer time
- **Athan sound**: plays an audio file (local file or streamed URL) the moment each prayer time starts
- **Quran tab**: browse hundreds of reciters and stream any surah straight from the popout
- Fully offline for prayer time calculation — uses the `salat` Python library
- Hijri date fetched from network when available, falls back to Gregorian date offline
- Configurable notification threshold

## How It Works

Prayer times are calculated locally using the `salat` Python library with the **Egyptian General Authority** calculation method. The plugin runs a Python script on startup and every hour to recalculate and cache the times for the day.

**Location** comes from Settings → Plugins → Prayer Times → Location & Timezone:
- **Auto Detect Location (default)**: resolves your approximate coordinates via IP-based geolocation (`ip-api.com`) each time the times are recalculated. Needs internet; nothing is stored beyond the local cache file on your own machine.
- **Manual**: disable auto-detect and enter your own latitude, longitude, and UTC offset. Nothing is pre-filled — you must set all three yourself. Prayer-time calculation then runs fully offline.

The Quran tab fetches its reciter/riwayah list once from the public [mp3quran.net API](https://www.mp3quran.net/ar/api) and caches it to `reciters.json`; you can re-fetch anytime with the refresh button in the panel. Streaming and Athan playback are handed off to whichever of `mpv`, `ffplay`, or `cvlc` is installed on your system (checked in that order).

## Requirements

- DankMaterialShell >= 1.2.0
- Python 3
- `salat` Python library
- One of `mpv`, `ffplay` (part of `ffmpeg`), or `cvlc` (part of VLC) — only needed for the Athan sound and Quran playback, not for prayer times themselves
- Internet access the first time you open the Quran tab (to fetch the reciter list) and whenever you stream a surah or an Athan URL

Install the dependencies:

```bash
pip install salat
sudo pacman -S mpv        # or: sudo apt install mpv   (any one of mpv/ffmpeg/vlc works)
```

## Installation

```bash
cp -r prayerTimes ~/.config/DankMaterialShell/plugins/
```

Then in DMS:
1. Settings → Plugins → Scan for Plugins
2. Enable **Prayer Times**
3. Settings → DankBar → Add Widget → Prayer Times

## Configuration

Open Settings → Plugins → Prayer Times to configure:

| Setting | Description | Default |
|---|---|---|
| Icon Only Mode | Show only the prayer icon in the bar | Off |
| Show Seconds | Show seconds in the countdown timer | Off |
| Auto Detect Location | Resolve coordinates via IP-based geolocation instead of manual entry | On |
| Latitude / Longitude / UTC Offset | Manual coordinates, used only when Auto Detect Location is off | (empty — must be set manually) |
| Reminder (minutes) | How many minutes before prayer to send a notification | 15 |
| Play Athan Sound | Play an audio file when each prayer time starts | Off |
| Athan Sound (file path or URL) | Local `.mp3`/`.ogg`/`.wav` path, or a direct `http(s)` link | (empty) |
| Show Quran Tab in Popout | Adds the Quran browser/player tab to the popout | On |

### Using the Quran tab

1. Open the widget's popout and switch to the **Quran** tab.
2. The first time, tap the refresh icon to fetch the reciter list (needs internet).
3. Use the arrows to pick a reciter/riwayah, then tap any surah to stream it. Tap it again (or the stop icon) to stop.

### Setting an Athan sound

This plugin doesn't bundle an Athan recording (copyright), so you'll need to supply your own. A few sources that offer free-to-use recordings:

- **[Pixabay – Azan sound effects](https://pixabay.com/sound-effects/search/azan/)** — royalty-free, no attribution required, straightforward MP3 download. Easiest option to stay copyright-safe.
- **[aladhan.com/download-adhans](https://aladhan.com/download-adhans)** — several full Adhan recordings for personal use, including the Fajr version.
- **[IslamCan.com Azan MP3](https://www.islamcan.com/audio/adhan/index.shtml)** — free downloads, several reciters.

Always check the license on the specific file before shipping it inside a public repo — "free download" pages don't all use the same terms, and some are for personal use only rather than redistribution. If you plan to publish this plugin with a bundled Athan file, Pixabay's royalty-free tracks are the safest to redistribute.

Once you have a file:

1. Drop it into this plugin's `assets/` folder, e.g. `assets/athan.mp3`.
2. In Settings → Plugins → Prayer Times → Athan Sound, just enter `assets/athan.mp3` — no need for a full absolute path, it resolves relative to wherever the plugin is installed.
3. Alternatively, use any local absolute path (`/home/you/Sounds/athan.mp3`) or a direct streaming URL.

## Location & Privacy

Nothing in this plugin is hardcoded to any particular place or machine. Location is resolved either automatically via IP geolocation or manually from coordinates you type into Settings — see [How It Works](#how-it-works). No location data leaves your machine except the IP-geolocation lookup itself (when Auto Detect is on) and the Quran/Athan streaming requests you trigger.

## Files

```
prayerTimes/
├── plugin.json          — plugin manifest
├── PrayerWidget.qml     — main bar widget + Quran player
├── PrayerSettings.qml   — settings panel
├── get_times.py         — Python script for offline prayer-time calculation
├── fetch_reciters.py    — Python script that caches the reciter list from mp3quran.net
├── cache.json           — daily prayer-times cache (auto-generated)
├── reciters.json         — reciter list cache (auto-generated on first Quran-tab use)
├── assets/              — put your own athan.mp3 (or similar) here, referenced by relative path in settings
└── icon.svg             — plugin icon
```

## Compatibility

- **Compositors**: Hyprland, Niri, Sway, and any Wayland compositor supported by DMS
- **Distros**: Any Linux distribution with Python 3 and pip

## Author

Customized by zeroaccess
Original plugin by muadz