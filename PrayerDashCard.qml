// PrayerDashCard.qml — Prayer Times Enhanced overview card for the Dashboard.
// Shows the current prayer period and countdown by reading the shared cache.
// Auto-location resolves coordinates through ip-api.com; Quran audio streams
// from mp3quran.net and is handled by the widget and Dashboard tab.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Modules.DDash.Overview

DashCardComponent {
    id: root

    // ── Settings from pluginData/options (same keys as the bar widget) ───────
    readonly property bool use12H: options.use12H ?? false

    // ── Prayer state ─────────────────────────────────────────────────────────
    property string fajr:      ""
    property string dhuhr:     ""
    property string asr:       ""
    property string maghrib:   ""
    property string isha:      ""
    property string currName:   ""
    property string nextName:   ""
    property string nextTime:   ""
    property int    nextTimeSec:   0
    property int    nextTotalSecs: 0
    property string dateHijr:   ""
    property bool   fetching:   false
    property int    notifyThresholdSec: (Number(pluginData.notifyMinutes) || 15) * 60

    readonly property bool isUrgent: nextTotalSecs > 0 && nextTotalSecs <= notifyThresholdSec

    readonly property string pluginDir: {
        let u = Qt.resolvedUrl(".").toString()
        return u.replace("file://", "")
    }

    clickable: true

    // ── Back-end: read cache on load ─────────────────────────────────────────
    Process {
        id: pyRunner
        onExited: function(code) {
            if (code === 0) cacheReader.running = true
            root.fetching = false
        }
    }

    Process {
        id: cacheReader
        command: ["cat", root.pluginDir + "cache.json"]
        stdout: SplitParser {
            onRead: function(line) {
                if (line.trim() === "") return
                try {
                    const obj = JSON.parse(line)
                    if (!obj.times) return
                    const t = obj.times
                    root.processPrayerData(
                        { Fajr:t[0], Sunrise:t[1], Dhuhr:t[2], Asr:t[3], Maghrib:t[4], Isha:t[5], Imsak:t[0] },
                        obj.hijri || ""
                    )
                } catch(e) {}
            }
        }
    }

    SystemClock {
        id: clock
        enabled: root.live
        precision: SystemClock.Minutes
        onDateChanged: { if (root.nextTimeSec > 0) root.updateCountdown() }
    }

    Timer {
        interval: 3600000; repeat: true; running: root.live
        onTriggered: root.fetch()
    }

    Component.onCompleted: root.fetch()

    // ── Helpers ───────────────────────────────────────────────────────────────
    function fetch() {
        if (root.fetching) return
        const loc = pluginData.autoLocation === true
        if (!loc && (!pluginData.latitude || !pluginData.longitude || !pluginData.timeZoneOffset))
            return cacheReader.running = true  // at minimum try the existing cache
        root.fetching = true
        const args = ["python3", root.pluginDir + "get_times.py", root.pluginDir + "cache.json"]
        if (loc) args.push("auto")
        else     args.push("manual", pluginData.latitude, pluginData.longitude, pluginData.timeZoneOffset)
        pyRunner.command = args
        pyRunner.running = false
        pyRunner.running = true
    }

    function stripTZ(s) { return s ? s.split(" ")[0] : "" }
    function timeToMin(hhmm) {
        const p = hhmm.split(":"); return parseInt(p[0]) * 60 + parseInt(p[1])
    }
    function formatTime(t) {
        if (!t || t === "") return ""
        if (!root.use12H) return t
        const p = t.split(":"); let h = parseInt(p[0])
        const ampm = h >= 12 ? "PM" : "AM"; h = h % 12; if (h === 0) h = 12
        return h + ":" + p[1] + " " + ampm
    }
    function formatCountdown(secs) {
        if (secs <= 0) return "0 min"
        const h = Math.floor(secs / 3600), m = Math.floor((secs % 3600) / 60)
        const mm = (m < 10 ? "0" : "") + m
        return h > 0 ? h + ":" + mm : m + " min"
    }
    function getPrayerIcon(name) {
        const m = { Fajr:"bedtime", Dhuhr:"wb_sunny", Asr:"light_mode", Maghrib:"wb_twilight", Isha:"bedtime" }
        return m[name] || "mosque"
    }
    function processPrayerData(timings, hijri) {
        root.fajr    = stripTZ(timings.Fajr)
        root.dhuhr   = stripTZ(timings.Dhuhr)
        root.asr     = stripTZ(timings.Asr)
        root.maghrib = stripTZ(timings.Maghrib)
        root.isha    = stripTZ(timings.Isha)
        root.dateHijr = hijri

        refreshPeriod(Qt.formatTime(clock.date, "HH:mm"))
        updateCountdown()
    }
    function refreshPeriod(now) {
        if (!root.fajr || !root.dhuhr || !root.asr || !root.maghrib || !root.isha)
            return false
        let period
        if      (now < root.fajr)    period = { currName:"Isha",    nextName:"Fajr",    nextTime:root.fajr    }
        else if (now < root.dhuhr)   period = { currName:"Fajr",    nextName:"Dhuhr",   nextTime:root.dhuhr   }
        else if (now < root.asr)     period = { currName:"Dhuhr",   nextName:"Asr",     nextTime:root.asr     }
        else if (now < root.maghrib) period = { currName:"Asr",     nextName:"Maghrib", nextTime:root.maghrib }
        else if (now < root.isha)    period = { currName:"Maghrib", nextName:"Isha",    nextTime:root.isha    }
        else                         period = { currName:"Isha",    nextName:"Fajr",    nextTime:root.fajr    }

        root.nextTimeSec = timeToMin(period.nextTime) * 60
        root.currName    = period.currName
        root.nextName    = period.nextName
        root.nextTime    = period.nextTime
        return true
    }
    function updateCountdown() {
        const d   = clock.date
        const now = d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds()
        let diff  = root.nextTimeSec - now

        // Advance immediately when a prayer has passed so the card never shows
        // a stale ~24h countdown between hourly refreshes.
        if (root.nextTimeSec > 0 && diff <= 0) {
            if (refreshPeriod(Qt.formatTime(d, "HH:mm")))
                diff = root.nextTimeSec - now
        }
        if (diff < 0) diff += 86400
        root.nextTotalSecs = Math.max(0, diff)
    }

    // ── Card content ──────────────────────────────────────────────────────────
    Column {
        anchors.centerIn: parent
        spacing:          Theme.spacingS

        // Prayer icon
        DIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name:  root.getPrayerIcon(root.currName)
            size:  Theme.iconSizeLarge
            color: root.isUrgent ? Theme.error : root.accentColor
        }

        // Next prayer name
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text:            root.nextName !== "" ? root.nextName : "…"
            font.pixelSize:  Theme.fontSizeMedium
            font.weight:     Font.Medium
            color:           root.contentColor
        }

        // Countdown
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text:            root.nextTime !== "" ? root.formatCountdown(root.nextTotalSecs) : "…"
            font.pixelSize:  Theme.fontSizeXXLarge
            font.weight:     Font.Bold
            color:           root.isUrgent ? Theme.error : root.accentColor
        }

        // "at HH:MM" label
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text:            root.nextTime !== "" ? ("at " + root.formatTime(root.nextTime)) : ""
            font.pixelSize:  Theme.fontSizeSmall
            color:           root.mutedColor
        }

        // Hijri date
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            visible:         root.dateHijr !== ""
            text:            root.dateHijr
            font.pixelSize:  Theme.fontSizeSmall
            color:           root.mutedColor
        }
    }
}
