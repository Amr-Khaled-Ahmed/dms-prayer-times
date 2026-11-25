// PrayerDashCard.qml — Prayer Times Enhanced overview card for the Dashboard.
// Shows the current prayer period and countdown by reading the shared cache.
// Auto-location resolves coordinates through ip-api.com; Quran audio streams
// from mp3quran.net and is handled by the widget and Dashboard tab.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Modules.DDash
import qs.Modules.DDash.Overview

DashCardComponent {
    id: root

    readonly property var storedDashOptions: DashRegistry.storedOptions(entryId)
    readonly property bool use12H: storedDashOptions.use12H !== undefined
                                   ? (options.use12H ?? false)
                                   : (pluginData.use12H ?? false)
    readonly property string calcMethod: pluginData.calcMethod ?? "egypt"
    readonly property string asrMethod: pluginData.asrMethod ?? "standard"
    readonly property int hijriOffset: {
        const value = Number(pluginData.hijriOffset)
        return Number.isFinite(value) ? Math.round(value) : 0
    }

    property string fajr: ""
    property string dhuhr: ""
    property string asr: ""
    property string maghrib: ""
    property string isha: ""
    property string currName: ""
    property string nextName: ""
    property string nextTime: ""
    property string prevTime: ""
    property int nextTimeSec: 0
    property int nextTotalSecs: 0
    property real periodProgress: 0
    property string dateHijr: ""
    property bool fetching: false
    readonly property bool hasData: fajr !== "" && dhuhr !== "" && asr !== "" && maghrib !== "" && isha !== ""

    readonly property real notifyMinutes: {
        const raw = pluginData.notifyMinutes
        if (raw === undefined || raw === null || String(raw).trim() === "") return 15
        const value = Number(raw)
        return Number.isFinite(value) ? value : 15
    }
    property int notifyThresholdSec: notifyMinutes * 60
    readonly property bool isUrgent: nextTotalSecs > 0 && nextTotalSecs <= notifyThresholdSec

    readonly property string pluginDir: {
        let u = Qt.resolvedUrl(".").toString()
        return u.replace("file://", "")
    }
    readonly property string cacheDir: Paths.strip(Paths.cache) + "/prayerTimesEnhanced"
    readonly property string cachePath: cacheDir + "/cache.json"

    tone: options.tone ?? "primary"
    clickable: true

    Process {
        id: pyRunner
        onExited: function(code) {
            if (code === 0) cacheView.reload()
            root.fetching = false
        }
    }

    FileView {
        id: cacheView
        path: root.cachePath
        watchChanges: true
        blockLoading: false
        printErrors: false

        onLoaded: {
            try {
                const obj = JSON.parse(cacheView.text())
                if (!Array.isArray(obj.times) || obj.times.length < 6) return
                const t = obj.times
                root.processPrayerData({
                    Fajr: t[0],
                    Sunrise: t[1],
                    Dhuhr: t[2],
                    Asr: t[3],
                    Maghrib: t[4],
                    Isha: t[5]
                }, obj.hijri || "")
            } catch(e) {}
        }
    }

    SystemClock {
        id: clock
        enabled: root.live
        precision: SystemClock.Minutes
        onDateChanged: {
            if (root.nextTimeSec > 0) root.updateCountdown()
        }
    }

    Timer {
        interval: 3600000
        repeat: true
        running: root.live
        onTriggered: root.fetch()
    }

    Component.onCompleted: {
        Paths.mkdir(root.cacheDir)
        root.fetch()
    }

    onPluginDataChanged: Qt.callLater(root.fetch)

    function fetch() {
        if (root.fetching) return
        const loc = pluginData.autoLocation === true
        if (!loc && (!pluginData.latitude || !pluginData.longitude || !pluginData.timeZoneOffset))
            return cacheView.reload()
        root.fetching = true
        const args = ["python3", root.pluginDir + "get_times.py", root.cachePath]
        if (loc) args.push("auto")
        else args.push("manual", pluginData.latitude, pluginData.longitude, pluginData.timeZoneOffset)
        args.push("--method", root.calcMethod)
        args.push("--asr", root.asrMethod)
        args.push("--hijri-offset", String(root.hijriOffset))
        pyRunner.command = args
        pyRunner.running = false
        pyRunner.running = true
    }

    function stripTZ(s) {
        return s ? String(s).split(" ")[0] : ""
    }

    function timeToMin(hhmm) {
        const p = String(hhmm).split(":")
        return parseInt(p[0], 10) * 60 + parseInt(p[1], 10)
    }

    function formatTime(t) {
        if (!t || t === "") return ""
        if (!root.use12H) return t
        const p = t.split(":")
        if (p.length < 2) return t
        let h = parseInt(p[0], 10)
        const ampm = h >= 12 ? "PM" : "AM"
        h = h % 12
        if (h === 0) h = 12
        return h + ":" + p[1] + " " + ampm
    }

    function formatCountdown(secs) {
        if (secs <= 0) return "0 min"
        const h = Math.floor(secs / 3600)
        const m = Math.floor((secs % 3600) / 60)
        const mm = (m < 10 ? "0" : "") + m
        return h > 0 ? h + ":" + mm : m + " min"
    }

    function getPrayerIcon(name) {
        const m = {
            Fajr: "bedtime",
            Dhuhr: "wb_sunny",
            Asr: "light_mode",
            Maghrib: "wb_twilight",
            Isha: "bedtime"
        }
        return m[name] || "mosque"
    }

    function processPrayerData(timings, hijri) {
        root.fajr = stripTZ(timings.Fajr)
        root.dhuhr = stripTZ(timings.Dhuhr)
        root.asr = stripTZ(timings.Asr)
        root.maghrib = stripTZ(timings.Maghrib)
        root.isha = stripTZ(timings.Isha)
        root.dateHijr = hijri
        root.refreshPeriod(Qt.formatTime(clock.date, "HH:mm"))
        root.updateCountdown()
    }

    function refreshPeriod(now) {
        if (!root.hasData) return false
        let period
        if (now < root.fajr) {
            period = { currName: "Isha", prevTime: root.isha, nextName: "Fajr", nextTime: root.fajr }
        } else if (now < root.dhuhr) {
            period = { currName: "Fajr", prevTime: root.fajr, nextName: "Dhuhr", nextTime: root.dhuhr }
        } else if (now < root.asr) {
            period = { currName: "Dhuhr", prevTime: root.dhuhr, nextName: "Asr", nextTime: root.asr }
        } else if (now < root.maghrib) {
            period = { currName: "Asr", prevTime: root.asr, nextName: "Maghrib", nextTime: root.maghrib }
        } else if (now < root.isha) {
            period = { currName: "Maghrib", prevTime: root.maghrib, nextName: "Isha", nextTime: root.isha }
        } else {
            period = { currName: "Isha", prevTime: root.isha, nextName: "Fajr", nextTime: root.fajr }
        }
        root.nextTimeSec = timeToMin(period.nextTime) * 60
        root.currName = period.currName
        root.prevTime = period.prevTime
        root.nextName = period.nextName
        root.nextTime = period.nextTime
        return true
    }

    function updateProgress() {
        if (!root.hasData || root.prevTime === "" || root.nextTimeSec <= 0) {
            root.periodProgress = 0
            return
        }
        const d = clock.date
        const nowSec = d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds()
        const prevSec = timeToMin(root.prevTime) * 60
        let total = root.nextTimeSec - prevSec
        if (total <= 0) total += 86400
        let elapsed = nowSec - prevSec
        if (elapsed < 0) elapsed += 86400
        if (elapsed > total) elapsed = total
        root.periodProgress = Math.max(0, Math.min(1, elapsed / total))
    }

    function updateCountdown() {
        const d = clock.date
        const nowSec = d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds()
        let diff = root.nextTimeSec - nowSec
        if (root.nextTimeSec > 0 && diff <= 0) {
            if (refreshPeriod(Qt.formatTime(d, "HH:mm")))
                diff = root.nextTimeSec - nowSec
        }
        if (diff < 0) diff += 86400
        root.nextTotalSecs = Math.max(0, diff)
        root.updateProgress()
    }

    Item {
        anchors.fill: parent

        RowLayout {
            id: topRow
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Theme.spacingS

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Theme.iconSizeLarge
                Layout.preferredHeight: Theme.iconSizeLarge
                radius: width / 2
                color: Theme.withAlpha(root.contentColor, 0.12)

                DIcon {
                    anchors.centerIn: parent
                    name: root.getPrayerIcon(root.nextName)
                    size: Theme.iconSize
                    color: root.isUrgent ? Theme.error : root.accentColor
                }
            }

            Column {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0

                StyledText {
                    text: root.nextName !== "" ? "Next prayer" : "Prayer times"
                    font.pixelSize: Theme.fontSizeSmall
                    color: root.mutedColor
                }

                StyledText {
                    text: root.nextName !== "" ? root.nextName : (root.hasData ? "—" : "Not set")
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Theme.fontWeightBold
                    color: root.contentColor
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumWidth: 100
                text: root.dateHijr
                font.pixelSize: Theme.fontSizeXSmall
                color: root.mutedColor
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
            }
        }

        DRingGauge {
            id: progressRing
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(parent.width, parent.height - topRow.height - bottomRow.height - Theme.spacingL)
            height: width
            value: root.hasData ? root.periodProgress : 0
            strokeWidth: Theme.spacingXS
            startAngle: -90
            ringColor: root.isUrgent ? Theme.error : root.accentColor
            trackColor: Theme.withAlpha(root.contentColor, 0.16)
            animated: true

            Column {
                anchors.centerIn: parent
                spacing: 0

                NumericText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.hasData ? root.formatCountdown(root.nextTotalSecs) : "—"
                    font.pixelSize: progressRing.width >= 92 ? Theme.fontSizeXLarge : Theme.fontSizeLarge
                    font.weight: Theme.fontWeightBold
                    color: root.isUrgent ? Theme.error : root.contentColor
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.hasData ? root.nextName : "Open settings"
                    font.pixelSize: Theme.fontSizeXSmall
                    color: root.mutedColor
                }
            }
        }

        RowLayout {
            id: bottomRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: Theme.spacingS

            StyledText {
                text: root.hasData ? ("at " + root.formatTime(root.nextTime)) : ""
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                color: root.contentColor
            }

            Item { Layout.fillWidth: true }

            StyledText {
                Layout.maximumWidth: parent.width / 2
                text: root.hasData && root.currName !== "" ? (root.currName + " now") : ""
                font.pixelSize: Theme.fontSizeXSmall
                color: root.mutedColor
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
