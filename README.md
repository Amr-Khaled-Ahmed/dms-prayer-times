# Prayer Times

A DankMaterialShell plugin for daily Islamic prayer times. It provides a DankBar widget and popout, a Prayer Times tab and overview card in the DMS Dashboard, optional prayer notifications and Athan playback, and a Quran recitation browser/player.

## Features

- Next prayer name and countdown in the DankBar
- Popout view showing all prayer times (Imsak, Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha)
- Hijri and Gregorian date display
- Optional desktop reminders before prayer and notifications at prayer time
- Optional Athan playback from a local audio file or direct URL
- Quran recitation browser/player in the widget popout and Dashboard tab
- Searchable reciter and riwayah picker in the Dashboard tab and widget popout
- Prayer Times Dashboard tab with a countdown, daily prayer schedule, and optional Quran section
- Dashboard overview card showing the current period and countdown; clicking it opens the Prayer Times tab
- Prayer times calculated locally with the `salat` Python library; the Hijri date is calculated offline too

## How It Works

Prayer times are calculated locally using the `salat` Python library with the **Egyptian General Authority** method and standard Asr calculation. The plugin reads `cache.json` as soon as the Dashboard tab or bar widget opens, so previously calculated timings appear immediately. It recalculates on startup, after location settings change, and every hour, then updates the cache. If the location is not configured, saved timings remain visible with a reminder to configure a location instead of leaving the tab stuck on a loading screen. The Hijri date is calculated locally with the Kuwaiti algorithm.

**Location** comes from Settings → Plugins → Prayer Times → Location & Timezone:
- **Manual (default)**: enter your latitude, longitude, and UTC offset. The fields are blank on a fresh install, so set all three before new calculations can run. Existing cached times can still be displayed; manual calculations work offline.
- **Auto Detect Location**: resolves approximate coordinates and timezone via IP-based geolocation (`ip-api.com`) whenever timings are recalculated. Requires internet.

The Quran player fetches its reciter/riwayah list from the public [mp3quran.net API](https://www.mp3quran.net/ar/api) when first opened and caches it in `reciters.json`. Use its refresh button to fetch the list again. Audio playback is handed off to the first installed player in this order: `mpv`, `ffplay`, then `cvlc`.

## Requirements

- DankMaterialShell >= 1.2.0; the Dashboard tab and card need a DMS version with plugin Dashboard support
- Python 3
- `salat` Python library
- `notify-send` and a working desktop notification service for notifications
- One of `mpv`, `ffplay` (part of `ffmpeg`), or `cvlc` (part of VLC) for Athan and Quran audio playback; not needed to calculate prayer times
- Internet access for auto-location, fetching the Quran reciter list, streaming Quran audio, or streaming an Athan URL. Manual prayer-time calculation and Hijri date calculation work offline.

Install the dependencies:

```bash
pip install salat
sudo pacman -S mpv        # or: sudo apt install mpv   (any one of mpv/ffmpeg/vlc works)
```

## Installation

```bash
mkdir -p ~/.config/dms/plugins
cp -r prayerTimes ~/.config/dms/plugins/
```

Then in DMS:
1. Settings → Plugins → Scan for Plugins
2. Enable **Prayer Times**
3. Settings → DankBar → Add Widget → Prayer Times
4. Open the DMS Dashboard and add the **Prayer Times** card from its editor if you want the overview card.

The **Prayer Times** Dashboard tab is registered by the plugin. If it is not shown, confirm that the plugin is enabled and that your DMS build supports plugin Dashboard tabs.

## Dashboard and Island mode

The Prayer Times Dashboard tab is registered as `plugin_prayerTimes`. On DMS builds without plugin-tab Island support, it appears only in the regular Dashboard. If you have applied the local DMS Island plugin-tab integration, it also appears in the Island's native Dashboard tab navigation. Use `dms ipc call dash open plugin_prayerTimes` to select and open it; use `dash open`, not `dash toggle`, when you want to switch tabs while the Dashboard is already visible.

To open the Prayer Times tab from a DankMaterialShell Lua keybind, add this to your `binds-user.lua` and change the key combination if needed:

```lua
hl.bind(
    "SUPER + P",
    hl.dsp.exec_cmd("dms ipc call dash open plugin_prayerTimes"),
    { description = "Prayer Times dashboard" }
)
```

## Configuration

Open Settings → Plugins → Prayer Times to configure:

| Setting | Description | Default |
|---|---|---|
| Icon Only Mode | Show only the prayer icon in the bar | Off |
| Show Seconds | Show seconds in the countdown timer | Off |
| Auto Detect Location | Resolve coordinates via IP-based geolocation instead of manual entry | Off |
| Latitude / Longitude / UTC Offset | Manual coordinates, used only when Auto Detect Location is off | Empty — must be set manually |
| Reminder (minutes) | How many minutes before prayer to send a notification | 15 |
| Play Athan Sound | Play an audio file when each prayer time starts | Off |
| Athan Sound (file path or URL) | Local `.mp3`/`.ogg`/`.wav` path, or a direct `http(s)` link | Empty |
| Show Quran Tab in Popout | Adds the Quran browser/player tab to the popout | On |

The Dashboard also has plugin options:

| Dashboard option | Description | Default |
|---|---|---|
| 12-hour format | Display Dashboard prayer times in 12-hour format | Off |
| Show Quran tab in dashboard | Show or hide the Quran section in the Dashboard tab | On |

### Using the Quran tab

1. Open the widget popout and switch to **Quran**, or open the Prayer Times Dashboard tab and expand its Quran section.
2. The first time, the plugin fetches the reciter list (internet required) and caches it in `reciters.json`. Use the refresh icon beside the selected reciter to fetch the list again.
3. Type a reciter name or riwayah into the search field in the Dashboard tab or widget popout and choose a matching result. The selected reciter appears above the search.
4. Select a surah to stream it. Select the playing surah again or use the stop button to stop playback.

### Setting an Athan sound

The repository includes `assets/athan.mp3`; you can use it or select another recording. Check the recording's license before redistribution. Other sources that offer free-to-use recordings include:

- **[Pixabay – Azan sound effects](https://pixabay.com/sound-effects/search/azan/)** — royalty-free, no attribution required, straightforward MP3 download. Easiest option to stay copyright-safe.
- **[aladhan.com/download-adhans](https://aladhan.com/download-adhans)** — several full Adhan recordings for personal use, including the Fajr version.
- **[IslamCan.com Azan MP3](https://www.islamcan.com/audio/adhan/index.shtml)** — free downloads, several reciters.

Always check the license on the specific file before redistribution; "free download" does not always mean the file can be republished.

Once you have a file:

1. Put it in this plugin's `assets/` folder, or use the included `assets/athan.mp3`.
2. In Settings → Plugins → Prayer Times → Athan Sound, enter `assets/athan.mp3` to use the included file. Relative paths resolve from the plugin directory.
3. Alternatively, use any local absolute path (`/home/you/Sounds/athan.mp3`) or a direct streaming URL.

## Location & Privacy

No coordinates are hardcoded. With manual location, the coordinates are used locally and are not sent to a service. With auto-location enabled, the IP-geolocation service receives the lookup request and your public IP address. Quran reciter-list requests and audio streams go to mp3quran.net or its audio hosts; Athan URLs are contacted only when you configure and play one. Prayer-time and reciter caches are stored in the plugin directory.

## Files

```
prayerTimes/
├── plugin.json          — plugin manifest, settings, and Dashboard registration
├── PrayerWidget.qml     — DankBar widget, popout, notifications, and Quran player
├── PrayerDashTab.qml    — Prayer Times Dashboard tab and Quran section
├── PrayerDashCard.qml   — Dashboard overview card
├── PrayerSettings.qml   — settings panel
├── get_times.py         — Python script for offline prayer-time calculation
├── fetch_reciters.py    — Python script that caches the reciter list from mp3quran.net
├── cache.json           — daily prayer-times cache
├── reciters.json        — cached Quran reciter/riwayah list
├── assets/athan.mp3     — bundled Athan audio (select it in settings to enable playback)
└── icon.svg             — plugin icon
```

## Compatibility

- **Compositors**: Wayland compositors supported by DMS
- **Distributions**: Linux distributions with Python 3, pip, and the required dependencies

## Author

Customized by zeroaccess
Original plugin by muadz