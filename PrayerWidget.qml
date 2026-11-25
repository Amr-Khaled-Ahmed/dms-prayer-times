// PrayerWidget.qml — Prayer Times Enhanced Dankbar widget and popout.
// Runs get_times.py, reads the shared cache, sends DMS notifications, plays
// Athan audio, and streams Quran recitations from mp3quran.net.
// Auto-location resolves coordinates with an HTTP request to ip-api.com.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root
    pluginId: "prayerTimesEnhanced"

    // Prayer times data
    property string fajr: ""
    property string dhuhr: ""
    property string asr: ""
    property string maghrib: ""
    property string isha: ""
    property string imsak: ""
    property string sunrise: ""
    property string dateHijr: ""
    property string dateGreg: ""

    // Current prayer period
    property string currName: ""
    property string nextName: ""
    property string nextTime: ""
    property string prevTime: ""
    property int nextTimeSec: 0
    property int nextTotalSeconds: 0
    property real periodProgress: 0
    readonly property bool hasData: fajr !== "" && dhuhr !== "" && asr !== "" && maghrib !== "" && isha !== ""

    // Settings
    property bool iconOnly: pluginData.iconOnly ?? false
    property bool showSeconds: pluginData.showSeconds ?? false
    property bool use12H: pluginData.use12H ?? false
    property bool showImsak: pluginData.showImsak ?? true
    property bool showSunrise: pluginData.showSunrise ?? true
    readonly property real notifyMinutes: {
        const raw = pluginData.notifyMinutes
        if (raw === undefined || raw === null || String(raw).trim() === "") return 15
        const value = Number(raw)
        return Number.isFinite(value) ? value : 15
    }
    property int notifyThresholdSec: notifyMinutes * 60
    property bool remindersEnabled: pluginData.remindersEnabled ?? true
    property bool playAthanSound: pluginData.playAthanSound ?? false
    property string athanSoundPath: pluginData.athanSoundPath ?? ""
    property bool quranEnabled: pluginData.quranEnabled ?? true
    property bool autoLocation: pluginData.autoLocation === true
    property string latitude: pluginData.latitude ?? ""
    property string longitude: pluginData.longitude ?? ""
    property string timeZoneOffset: pluginData.timeZoneOffset ?? ""
    property string calcMethod: pluginData.calcMethod ?? "egypt"
    property string asrMethod: pluginData.asrMethod ?? "standard"
    readonly property int hijriOffset: {
        const value = Number(pluginData.hijriOffset)
        return Number.isFinite(value) ? Math.round(value) : 0
    }

    // Resolved at runtime from wherever this plugin is actually installed —
    // never hardcode a path, so the plugin works on any machine/user.
    readonly property string pluginDir: {
        let fullUrl = Qt.resolvedUrl(".").toString()
        return fullUrl.replace("file://", "")
    }
    readonly property string cacheDir: Paths.strip(Paths.cache) + "/prayerTimesEnhanced"
    readonly property string cachePath: cacheDir + "/cache.json"
    readonly property string reciterCachePath: cacheDir + "/reciters.json"

    // Only one widget instance may send reminders/Athan; otherwise every bar
    // and monitor would fire the same notification and play the same audio.
    property string notifyOwnerToken: ""
    property bool isNotifyOwner: false

    function claimNotifyOwner() {
        if (!pluginService || !root.pluginId || root.notifyOwnerToken === "") return
        let owner = PluginService.getGlobalVar(root.pluginId, "notifyOwner", "")
        if (owner === "") {
            PluginService.setGlobalVar(root.pluginId, "notifyOwner", root.notifyOwnerToken)
            owner = root.notifyOwnerToken
        }
        root.isNotifyOwner = owner === root.notifyOwnerToken
    }

    Connections {
        target: PluginService
        function onGlobalVarChanged(pid, name) {
            if (pid === root.pluginId && name === "notifyOwner")
                Qt.callLater(root.claimNotifyOwner)
        }
    }

    Component.onCompleted: {
        Paths.mkdir(root.cacheDir)
        root.notifyOwnerToken = root.widgetInstanceId || ("widget-" + Math.random().toString(36).slice(2))
        Qt.callLater(root.claimNotifyOwner)
    }
    Component.onDestruction: {
        if (pluginService && root.notifyOwnerToken !== ""
                && PluginService.getGlobalVar(root.pluginId, "notifyOwner", "") === root.notifyOwnerToken)
            PluginService.setGlobalVar(root.pluginId, "notifyOwner", "")
    }

    // Internal state
    property bool fetching: false
    property bool _wasUrgent: false
    property bool _wasAtTime: false

    // Quran panel state
    property bool showQuranPanel: false
    property var reciters: []
    property int selectedReciterIndex: 0
    property string reciterSearch: ""
    property string reciterStatus: ""
    property int playingSurah: -1
    property bool quranPlaying: false
    property bool fetchingReciters: false
    property var surahNames: [
        "الفاتحة", "البقرة", "آل عمران", "النساء", "المائدة", "الأنعام", "الأعراف", "الأنفال",
        "التوبة", "يونس", "هود", "يوسف", "الرعد", "إبراهيم", "الحجر", "النحل",
        "الإسراء", "الكهف", "مريم", "طه", "الأنبياء", "الحج", "المؤمنون", "النور",
        "الفرقان", "الشعراء", "النمل", "القصص", "العنكبوت", "الروم", "لقمان", "السجدة",
        "الأحزاب", "سبأ", "فاطر", "يس", "الصافات", "ص", "الزمر", "غافر",
        "فصلت", "الشورى", "الزخرف", "الدخان", "الجاثية", "الأحقاف", "محمد", "الفتح",
        "الحجرات", "ق", "الذاريات", "الطور", "النجم", "القمر", "الرحمن", "الواقعة",
        "الحديد", "المجادلة", "الحشر", "الممتحنة", "الصف", "الجمعة", "المنافقون", "التغابن",
        "الطلاق", "التحريم", "الملك", "القلم", "الحاقة", "المعارج", "نوح", "الجن",
        "المزمل", "المدثر", "القيامة", "الإنسان", "المرسلات", "النبأ", "النازعات", "عبس",
        "التكوير", "الانفطار", "المطففين", "الانشقاق", "البروج", "الطارق", "الأعلى", "الغاشية",
        "الفجر", "البلد", "الشمس", "الليل", "الضحى", "الشرح", "التين", "العلق",
        "القدر", "البينة", "الزلزلة", "العاديات", "القارعة", "التكاثر", "العصر", "الهمزة",
        "الفيل", "قريش", "الماعون", "الكوثر", "الكافرون", "النصر", "المسد", "الإخلاص",
        "الفلق", "الناس"
    ]

    // UI state
    readonly property bool isUrgent: nextTotalSeconds > 0 && nextTotalSeconds <= notifyThresholdSec
    readonly property color accentColor: Theme.primary
    readonly property color accentBg: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.18)
    popoutWidth: 380
    pillRightClickAction: function() { root.fetchPrayerTimes() }
    readonly property int standardRowHeight: Theme.iconButtonSize
    readonly property int quranRowHeight: 48
    readonly property int reciterListHeight: 168
    readonly property int surahListHeight: 336
    readonly property int surahNumberWidth: 32

    // Notification process
    Process {
        id: prayerNotifyProc
        running: false
    }

    // Athan (call to prayer) sound player
    Process {
        id: athanPlayerProc
        running: false
    }

    // Quran recitation player
    Process {
        id: quranPlayerProc
        running: false
        onExited: function() {
            root.quranPlaying = false
            root.playingSurah = -1
        }
    }

    // Python script runner
    Process {
        id: pyRunner
        onExited: function(code) {
            if (code === 0) cacheView.reload()
            root.fetching = false
        }
    }

    // Cache reader
    FileView {
        id: cacheView
        path: root.cachePath
        watchChanges: true
        blockLoading: false
        printErrors: false

        onLoaded: {
            try {
                var obj = JSON.parse(cacheView.text())
                if (!obj.times) return
                var t = obj.times
                var fakeData = {
                    timings: {
                        Fajr:    t[0],
                        Sunrise: t[1],
                        Dhuhr:   t[2],
                        Asr:     t[3],
                        Maghrib: t[4],
                        Isha:    t[5],
                        Imsak:   obj.imsak || t[6] || "",
                        Sunset:  t[4]
                    },
                    date: {
                        readable: root.formatGregorian(obj.date || ""),
                        hijri: obj.hijri || ""
                    }
                }
                processPrayerData(fakeData)
            } catch(e) {
                console.warn("Prayer Times: couldn't parse cached schedule:", e)
            }
        }
    }

    // Reciter list fetcher (hits mp3quran.net once, caches to reciters.json)
    Process {
        id: reciterFetcher
        command: ["python3", root.pluginDir + "fetch_reciters.py", root.reciterCachePath]
        onExited: function(code) {
            root.fetchingReciters = false
            root.reciterStatus = code === 0 ? "" : "Couldn't refresh the reciter list."
            reciterCacheView.reload()
        }
    }

    // Reciter cache reader
    FileView {
        id: reciterCacheView
        path: root.reciterCachePath
        watchChanges: true
        blockLoading: false
        printErrors: false

        onLoaded: {
            try {
                var obj = JSON.parse(reciterCacheView.text())
                const safeReciters = Array.isArray(obj.reciters)
                    ? obj.reciters.filter(function(r) {
                        return r && typeof r.server === "string" && r.server.startsWith("https://")
                    })
                    : []
                if (safeReciters.length > 0) {
                    root.reciters = safeReciters
                    if (root.selectedReciterIndex >= root.reciters.length) root.selectedReciterIndex = 0
                }
            } catch(e) {
                console.warn("Prayer Times: couldn't parse cached reciters:", e)
            }
        }
    }

    // Initialize when plugin service is ready
    onPluginServiceChanged: {
        if (pluginService) {
            loadPluginData()
            Qt.callLater(root.claimNotifyOwner)
            cacheView.reload()
            Qt.callLater(root.fetchPrayerTimes)
            reciterCacheView.reload() // pick up any previously cached reciter list
        }
    }

    onAutoLocationChanged: fetchPrayerTimes()
    onLatitudeChanged: if (!autoLocation) fetchPrayerTimes()
    onLongitudeChanged: if (!autoLocation) fetchPrayerTimes()
    onTimeZoneOffsetChanged: if (!autoLocation) fetchPrayerTimes()
    onCalcMethodChanged: fetchPrayerTimes()
    onAsrMethodChanged: fetchPrayerTimes()
    onHijriOffsetChanged: fetchPrayerTimes()

    onShowQuranPanelChanged: {
        if (showQuranPanel && root.reciters.length === 0 && !root.fetchingReciters) {
            root.fetchReciters()
        }
    }

    // Timers
    Timer {
        id: refreshTimer
        interval: 3600000  // refresh every hour
        running: pluginService !== null
        repeat: true
        onTriggered: fetchPrayerTimes()
    }

    SystemClock {
        id: clock
        precision: root.showSeconds ? SystemClock.Seconds : SystemClock.Minutes
        onDateChanged: {
            if (root.nextTimeSec > 0) updateCountdown()
        }
    }

    // File path for icon
    readonly property string iconPath: {
        let fullUrl = Qt.resolvedUrl("icon.svg").toString()
        return fullUrl.replace("file://", "")
    }

    // Fetch — runs python script then reads cache
    function fetchPrayerTimes() {
        if (root.fetching) return

        var args = ["python3", root.pluginDir + "get_times.py", root.cachePath]

        if (root.autoLocation) {
            args.push("auto")
        } else {
            if (root.latitude === "" || root.longitude === "" || root.timeZoneOffset === "") {
                cacheView.reload()
                if (SettingsData.pluginSettings[root.pluginId] !== undefined)
                    console.warn("Prayer Times: manual location is enabled but lat/lon/UTC offset " +
                                  "are not fully set — open plugin settings to fill them in.")
                return
            }
            args.push("manual")
            args.push(root.latitude)
            args.push(root.longitude)
            args.push(root.timeZoneOffset)
        }

        args.push("--method", root.calcMethod)
        args.push("--asr", root.asrMethod)
        args.push("--hijri-offset", String(root.hijriOffset))

        root.fetching = true
        pyRunner.command = args
        pyRunner.running = false
        pyRunner.running = true
    }

    // Runs an audio file/URL through whichever player is installed (mpv, then ffplay, then cvlc)
    function playerCommandFor(target) {
        return ["sh", "-c",
            "if command -v mpv >/dev/null 2>&1; then exec mpv --no-video --really-quiet -- \"$0\"; " +
            "elif command -v ffplay >/dev/null 2>&1; then exec ffplay -nodisp -autoexit -loglevel quiet -- \"$0\"; " +
            "elif command -v cvlc >/dev/null 2>&1; then exec cvlc --play-and-exit -q -- \"$0\"; " +
            "else dms notify -a 'Prayer Times Enhanced' 'No audio player found — install mpv, ffplay, or cvlc'; fi",
            target]
    }

    // Resolves a user-entered athan path: leaves http(s) URLs and absolute
    // paths alone, but resolves anything relative (e.g. "assets/athan.mp3")
    // against this plugin's own directory.
    function resolveAthanPath(p) {
        if (p === "") return p
        if (p.startsWith("http://") || p.startsWith("https://") || p.startsWith("/")) return p
        return root.pluginDir + p
    }

    function playAthan() {
        if (!root.isNotifyOwner || !root.playAthanSound || root.athanSoundPath === "") return
        athanPlayerProc.command = playerCommandFor(root.resolveAthanPath(root.athanSoundPath))
        athanPlayerProc.running = false
        athanPlayerProc.running = true
    }

    // Quran functions
    function pad3(n) {
        var s = "" + n
        while (s.length < 3) s = "0" + s
        return s
    }

    function surahAudioUrl(reciter, surahNum) {
        if (!reciter || typeof reciter.server !== "string"
                || !reciter.server.startsWith("https://"))
            return ""
        return reciter.server + pad3(surahNum) + ".mp3"
    }

    function fetchReciters() {
        if (root.fetchingReciters) return
        root.fetchingReciters = true
        root.reciterStatus = ""
        reciterFetcher.running = true
    }

    function filteredReciters() {
        var query = root.reciterSearch.trim().toLowerCase()
        if (query === "") return []
        var matches = []
        for (var i = 0; i < root.reciters.length; i++) {
            var reciter = root.reciters[i]
            var searchable = (String(reciter.name || "") + " "
                              + String(reciter.moshaf_name || "")).toLowerCase()
            if (searchable.includes(query))
                matches.push({ index: i, reciter: reciter })
        }
        return matches
    }

    function playSurah(reciterIdx, surahNum) {
        if (root.reciters.length === 0) return
        var r = root.reciters[reciterIdx]
        var url = surahAudioUrl(r, surahNum)
        if (url === "") return
        quranPlayerProc.command = playerCommandFor(url)
        quranPlayerProc.running = false
        quranPlayerProc.running = true
        root.playingSurah = surahNum
        root.quranPlaying = true
    }

    function stopQuran() {
        quranPlayerProc.running = false
        root.quranPlaying = false
        root.playingSurah = -1
    }

    // Notification functions
    function sendPrayerNotification() {
        if (!root.isNotifyOwner || !root.remindersEnabled) return
        var mins = Math.ceil(root.nextTotalSeconds / 60)
        prayerNotifyProc.command = [
            "dms", "notify", "-a", "Prayer Times Enhanced", "-u", "critical", "-i", iconPath,
            root.nextName + " in " + mins + " min (at " + root.formatTime(root.nextTime) + ")"
        ]
        prayerNotifyProc.running = true
    }

    function sendPrayerTimeNotification() {
        if (!root.isNotifyOwner) return
        if (root.remindersEnabled) {
            prayerNotifyProc.command = [
                "dms", "notify", "-a", "Prayer Times Enhanced", "-u", "critical", "-i", iconPath,
                "Time for " + root.nextName
            ]
            prayerNotifyProc.running = true
        }
        root.playAthan()
    }

    // Countdown update + notifications
    function updateCountdown() {
        var now    = clock.date
        var nowSec = now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds()
        var rawDiff = root.nextTimeSec - nowSec

        // A prayer just passed: notify once, then advance the period immediately
        // instead of showing a stale ~24h countdown until the next cache refresh.
        if (root.nextTimeSec > 0 && rawDiff <= 0) {
            if (rawDiff > -60 && !root._wasAtTime) {
                root._wasAtTime = true
                sendPrayerTimeNotification()
            }
            if (refreshPrayerPeriod(Qt.formatTime(now, "HH:mm")))
                rawDiff = root.nextTimeSec - nowSec
        }

        var diff = rawDiff
        if (diff < 0) diff += 86400
        root.nextTotalSeconds = Math.max(0, diff)
        root.updateProgress()

        if (root.remindersEnabled) {
            var urgent = diff > 0 && diff <= root.notifyThresholdSec
            if (urgent && !root._wasUrgent) sendPrayerNotification()
            root._wasUrgent = urgent
        } else {
            root._wasUrgent = false
        }
    }

    // Utility functions
    function stripTimezone(timeStr) {
        return timeStr ? timeStr.split(" ")[0] : ""
    }

    function timeToMinutes(hhmm) {
        var parts = hhmm.split(":")
        return parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10)
    }

    function formatTime(time24h) {
        if (!time24h || time24h === "") return ""
        if (!root.use12H) return time24h
        var parts = time24h.split(":")
        if (parts.length < 2) return time24h
        var hours = parseInt(parts[0], 10)
        var minutes = parts[1]
        var ampm = hours >= 12 ? "PM" : "AM"
        hours = hours % 12
        if (hours === 0) hours = 12
        return hours + ":" + minutes + " " + ampm
    }

    function formatGregorian(value) {
        if (!value) return ""
        var d = new Date(String(value) + (String(value).length === 10 ? "T12:00:00" : ""))
        if (isNaN(d.getTime())) return String(value)
        return d.toLocaleDateString(Qt.locale(), Locale.LongFormat)
    }

    function formatCountdown(totalSeconds) {
        if (totalSeconds <= 0) return root.showSeconds ? "00:00" : "0 min"
        var h  = Math.floor(totalSeconds / 3600)
        var m  = Math.floor((totalSeconds % 3600) / 60)
        var s  = totalSeconds % 60
        if (root.showSeconds) {
            var mm = (m < 10 ? "0" : "") + m
            var ss = (s < 10 ? "0" : "") + s
            if (h > 0) return (h < 10 ? "0" : "") + h + ":" + mm + ":" + ss
            return mm + ":" + ss
        } else {
            var mm2 = (m < 10 ? "0" : "") + m
            if (h > 0) return (h < 10 ? "0" : "") + h + ":" + mm2
            return m + " min"
        }
    }

    function determinePrayerPeriod(nowStr, fajrT, dhuhrT, asrT, maghribT, ishaT) {
        if (nowStr < fajrT)    return { currName: "Isha",    prevTime: ishaT,    nextName: "Fajr",    nextTime: fajrT    }
        if (nowStr < dhuhrT)   return { currName: "Fajr",    prevTime: fajrT,    nextName: "Dhuhr",   nextTime: dhuhrT   }
        if (nowStr < asrT)     return { currName: "Dhuhr",   prevTime: dhuhrT,   nextName: "Asr",     nextTime: asrT     }
        if (nowStr < maghribT) return { currName: "Asr",     prevTime: asrT,     nextName: "Maghrib", nextTime: maghribT }
        if (nowStr < ishaT)    return { currName: "Maghrib", prevTime: maghribT, nextName: "Isha",    nextTime: ishaT    }
        return                        { currName: "Isha",    prevTime: ishaT,    nextName: "Fajr",    nextTime: fajrT    }
    }

    function refreshPrayerPeriod(nowStr) {
        if (root.fajr === "" || root.dhuhr === "" || root.asr === ""
                || root.maghrib === "" || root.isha === "")
            return false

        var period = determinePrayerPeriod(
            nowStr, root.fajr, root.dhuhr, root.asr, root.maghrib, root.isha
        )
        if (root.nextName !== period.nextName) {
            root._wasUrgent = false
            root._wasAtTime = false
        }
        root.currName = period.currName
        root.prevTime = period.prevTime
        root.nextName = period.nextName
        root.nextTime = period.nextTime
        root.nextTimeSec = timeToMinutes(period.nextTime) * 60
        return true
    }

    function updateProgress() {
        if (!root.hasData || root.prevTime === "" || root.nextTimeSec <= 0) {
            root.periodProgress = 0
            return
        }
        var now = clock.date
        var nowSec = now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds()
        var prevSec = timeToMinutes(root.prevTime) * 60
        var total = root.nextTimeSec - prevSec
        if (total <= 0) total += 86400
        var elapsed = nowSec - prevSec
        if (elapsed < 0) elapsed += 86400
        if (elapsed > total) elapsed = total
        root.periodProgress = Math.max(0, Math.min(1, elapsed / total))
    }

    function processPrayerData(data) {
        var timings  = data.timings
        var dateInfo = data.date

        root.fajr    = stripTimezone(timings.Fajr)
        root.dhuhr   = stripTimezone(timings.Dhuhr)
        root.asr     = stripTimezone(timings.Asr)
        root.maghrib = stripTimezone(timings.Maghrib)
        root.isha    = stripTimezone(timings.Isha)
        root.imsak   = stripTimezone(timings.Imsak   || "")
        root.sunrise = stripTimezone(timings.Sunrise || "")
        root.dateGreg = dateInfo.readable || ""
        root.dateHijr = dateInfo.hijri || ""

        var nowStr = Qt.formatTime(clock.date, "HH:mm")
        refreshPrayerPeriod(nowStr)
        updateCountdown()
    }

    // Prayer icons
    property var prayerIcons: ({
        "Fajr":    "bedtime",
        "Dhuhr":   "wb_sunny",
        "Asr":     "light_mode",
        "Maghrib": "wb_twilight",
        "Isha":    "bedtime"
    })

    function getPrayerIcon(name) {
        return root.prayerIcons[name] || "mosque"
    }

    function scheduleItems() {
        const items = []
        if (root.showImsak)
            items.push({ label: "Imsak", time: root.imsak, icon: "moon_stars" })
        items.push({ label: "Fajr", time: root.fajr, icon: "bedtime" })
        if (root.showSunrise)
            items.push({ label: "Sunrise", time: root.sunrise, icon: "wb_twilight" })
        items.push({ label: "Dhuhr", time: root.dhuhr, icon: "wb_sunny" })
        items.push({ label: "Asr", time: root.asr, icon: "light_mode" })
        items.push({ label: "Maghrib", time: root.maghrib, icon: "wb_twilight" })
        items.push({ label: "Isha", time: root.isha, icon: "bedtime" })
        return items
    }

    component PrayerBadge: Item {
        id: badge
        property string iconName: "mosque"
        property bool urgent: false
        property real progress: -1
        property color badgeColor: Theme.primary
        property color badgeFill: Theme.withAlpha(Theme.primary, 0.18)

        width: Theme.iconSizeSmall + Theme.spacingS
        height: width

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: badge.urgent ? Theme.withAlpha(Theme.error, 0.16) : badge.badgeFill
        }

        DRingGauge {
            anchors.fill: parent
            value: badge.progress
            strokeWidth: 2
            startAngle: -90
            ringColor: badge.urgent ? Theme.error : badge.badgeColor
            trackColor: "transparent"

            DIcon {
                anchors.centerIn: parent
                name: badge.iconName
                size: Theme.iconSizeSmall - 2
                color: badge.urgent ? Theme.error : badge.badgeColor
            }
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: root.iconOnly ? 0 : Theme.spacingS
            rightPadding: root.iconOnly ? 0 : Theme.spacingS
            Accessible.name: root.nextName !== ""
                             ? root.nextName + " in " + root.formatCountdown(root.nextTotalSeconds)
                             : "Prayer times"

            PrayerBadge {
                anchors.verticalCenter: parent.verticalCenter
                iconName: root.getPrayerIcon(root.currName)
                urgent: root.isUrgent
                progress: root.hasData ? root.periodProgress : -1
            }

            StyledText {
                visible: !root.iconOnly
                text: root.nextTime !== "" ? root.nextName
                                           : (root.fetching ? "Loading…" : "Set location")
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                color: root.isUrgent ? Theme.error : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }

            NumericText {
                visible: !root.iconOnly && root.nextTime !== ""
                text: root.formatCountdown(root.nextTotalSeconds)
                font.pixelSize: Theme.fontSizeSmall
                font.weight: root.isUrgent ? Theme.fontWeightBold : Font.Normal
                color: root.isUrgent ? Theme.error : Theme.secondary
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXXS

            PrayerBadge {
                anchors.horizontalCenter: parent.horizontalCenter
                iconName: root.getPrayerIcon(root.currName)
                urgent: root.isUrgent
                progress: root.hasData ? root.periodProgress : -1
            }

            NumericText {
                visible: root.nextTime !== ""
                text: root.formatCountdown(root.nextTotalSeconds)
                font.pixelSize: Theme.fontSizeXSmall
                color: root.isUrgent ? Theme.error : Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popoutRoot
            width: root.popoutWidth
            headerText: "Prayer Times"
            detailsText: root.dateGreg !== "" && root.dateHijr !== ""
                         ? root.dateGreg + " · " + root.dateHijr
                         : (root.dateGreg || root.dateHijr)
            headerActions: Component {
                DRefreshButton {
                    busy: root.fetching
                    tooltipText: "Refresh prayer times"
                    onClicked: root.fetchPrayerTimes()
                }
            }

            Item {
                width: 1
                height: Theme.spacingS
            }

            DButtonGroup {
                width: parent.width
                visible: root.quranEnabled
                model: [
                    { text: "Prayers", icon: "mosque" },
                    { text: "Quran", icon: "menu_book" }
                ]
                currentIndex: root.showQuranPanel ? 1 : 0
                size: "small"
                fillWidth: true
                checkEnabled: false
                maximumWidth: parent.width
                onSelectionChanged: function(index, selected) {
                    if (selected)
                        root.showQuranPanel = index === 1
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM
                visible: !root.showQuranPanel || !root.quranEnabled

                DCard {
                    id: heroCard
                    width: parent.width
                    height: heroContent.implicitHeight + heroCard.pad * 2
                    pad: Theme.spacingL
                    tone: "primary"

                    RowLayout {
                        id: heroContent
                        width: parent.width
                        spacing: Theme.spacingL

                        Column {
                            Layout.fillWidth: true
                            spacing: Theme.spacingXS

                            Row {
                                spacing: Theme.spacingS

                                DIcon {
                                    name: root.getPrayerIcon(root.nextName)
                                    size: Theme.iconSize
                                    color: root.isUrgent ? Theme.error : heroCard.accentColor
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: root.nextName !== "" ? "Next prayer" : "Prayer schedule"
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Theme.fontWeightMedium
                                    color: heroCard.mutedColor
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            StyledText {
                                width: parent.width
                                text: root.nextName !== "" ? root.nextName : (root.hasData ? "—" : "Set location")
                                font.pixelSize: Theme.fontSizeXXLarge
                                font.weight: Theme.fontWeightBold
                                color: heroCard.contentColor
                                elide: Text.ElideRight
                            }

                            StyledText {
                                width: parent.width
                                text: root.hasData
                                      ? "at " + root.formatTime(root.nextTime)
                                        + " · " + Math.round(root.periodProgress * 100) + "% of period"
                                      : "Add coordinates or enable auto-location in settings"
                                font.pixelSize: Theme.fontSizeSmall
                                color: heroCard.mutedColor
                                wrapMode: Text.WordWrap
                            }

                            StyledText {
                                width: parent.width
                                visible: root.currName !== ""
                                text: "Current · " + root.currName
                                font.pixelSize: Theme.fontSizeXSmall
                                color: heroCard.mutedColor
                            }
                        }

                        DRingGauge {
                            Layout.preferredWidth: 104
                            Layout.preferredHeight: 104
                            value: root.hasData ? root.periodProgress : 0
                            strokeWidth: Theme.spacingXS
                            startAngle: -90
                            ringColor: root.isUrgent ? Theme.error : heroCard.accentColor
                            trackColor: Theme.withAlpha(heroCard.contentColor, 0.16)

                            Column {
                                anchors.centerIn: parent
                                spacing: 0

                                NumericText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.hasData ? root.formatCountdown(root.nextTotalSeconds) : "—"
                                    font.pixelSize: Theme.fontSizeLarge
                                    font.weight: Theme.fontWeightBold
                                    color: root.isUrgent ? Theme.error : heroCard.contentColor
                                }

                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.hasData ? "remaining" : ""
                                    font.pixelSize: Theme.fontSizeXSmall
                                    color: heroCard.mutedColor
                                }
                            }
                        }
                    }
                }

                DCard {
                    id: emptyCard
                    width: parent.width
                    height: emptyContent.implicitHeight + emptyCard.pad * 2
                    pad: Theme.spacingL
                    visible: !root.hasData

                    Column {
                        id: emptyContent
                        width: parent.width
                        spacing: Theme.spacingS

                        RowLayout {
                            width: parent.width
                            spacing: Theme.spacingS

                            DIcon {
                                Layout.preferredWidth: Theme.iconSize
                                Layout.preferredHeight: Theme.iconSize
                                name: "location_off"
                                size: Theme.iconSize
                                color: Theme.surfaceVariantText
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: "Prayer times aren't set up yet"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Theme.fontWeightBold
                                color: Theme.surfaceText
                                wrapMode: Text.WordWrap
                            }
                        }

                        StyledText {
                            width: parent.width
                            text: "Open Settings → Plugins → Prayer Times Enhanced and add your coordinates, or enable Auto Detect Location."
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                DCard {
                    id: scheduleCard
                    width: parent.width
                    height: scheduleContent.implicitHeight + scheduleCard.pad * 2
                    pad: Theme.spacingM
                    visible: root.hasData

                    Column {
                        id: scheduleContent
                        width: parent.width
                        spacing: Theme.spacingS

                        RowLayout {
                            width: parent.width

                            StyledText {
                                Layout.fillWidth: true
                                text: "Today's schedule"
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Theme.fontWeightBold
                                color: Theme.surfaceVariantText
                            }

                            StyledText {
                                text: root.currName !== "" ? root.currName + " now" : ""
                                font.pixelSize: Theme.fontSizeXSmall
                                color: Theme.surfaceVariantText
                            }
                        }

                        GridLayout {
                            width: parent.width
                            columns: 2
                            columnSpacing: Theme.spacingS
                            rowSpacing: Theme.spacingXS

                            Repeater {
                                model: root.scheduleItems()

                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Theme.iconButtonSize
                                    radius: Theme.cornerRadiusS
                                    color: isNext ? Theme.withAlpha(Theme.primary, 0.14)
                                                  : isCurr ? Theme.chipSurface
                                                           : "transparent"
                                    border.width: isNext ? Theme.outlineWidth : 0
                                    border.color: isNext ? Theme.primary : "transparent"

                                    readonly property bool isNext: modelData.label === root.nextName
                                    readonly property bool isCurr: modelData.label === root.currName

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.spacingS
                                        anchors.rightMargin: Theme.spacingS
                                        spacing: Theme.spacingXS

                                        DIcon {
                                            Layout.preferredWidth: Theme.iconSizeSmall
                                            Layout.preferredHeight: Theme.iconSizeSmall
                                            name: modelData.icon
                                            size: Theme.iconSizeSmall
                                            color: isNext ? Theme.primary
                                                          : isCurr ? Theme.surfaceText
                                                                   : Theme.surfaceVariantText
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.label
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: (isNext || isCurr) ? Theme.fontWeightBold : Font.Normal
                                            color: isNext ? Theme.primary
                                                          : isCurr ? Theme.surfaceText
                                                                   : Theme.surfaceVariantText
                                            elide: Text.ElideRight
                                        }

                                        StyledText {
                                            text: root.formatTime(modelData.time)
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: (isNext || isCurr) ? Theme.fontWeightBold : Font.Normal
                                            color: isNext ? Theme.primary
                                                          : isCurr ? Theme.surfaceText
                                                                   : Theme.surfaceVariantText
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM
                visible: root.showQuranPanel && root.quranEnabled

                DCard {
                    id: playingCard
                    width: parent.width
                    height: playingContent.implicitHeight + playingCard.pad * 2
                    pad: Theme.spacingM
                    tone: "secondary"
                    visible: root.quranPlaying

                    RowLayout {
                        id: playingContent
                        width: parent.width
                        spacing: Theme.spacingM

                        DIcon {
                            Layout.preferredWidth: Theme.iconSize
                            Layout.preferredHeight: Theme.iconSize
                            name: "graphic_eq"
                            size: Theme.iconSize
                            color: playingCard.accentColor
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                text: "Now playing"
                                font.pixelSize: Theme.fontSizeXSmall
                                color: playingCard.mutedColor
                            }

                            StyledText {
                                width: parent.width
                                text: root.playingSurah > 0
                                      ? "Surah " + root.playingSurah + " · " + root.surahNames[root.playingSurah - 1]
                                      : "Quran"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Theme.fontWeightMedium
                                color: playingCard.contentColor
                                elide: Text.ElideRight
                            }
                        }

                        DButton {
                            text: "Stop"
                            iconName: "stop"
                            buttonHeight: Theme.buttonHeightXS
                            variant: "tonal"
                            onClicked: root.stopQuran()
                        }
                    }
                }

                DCard {
                    id: reciterCard
                    width: parent.width
                    height: reciterContent.implicitHeight + reciterCard.pad * 2
                    pad: Theme.spacingM

                    Column {
                        id: reciterContent
                        width: parent.width
                        spacing: Theme.spacingS

                        RowLayout {
                            width: parent.width
                            spacing: Theme.spacingM

                            Column {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    width: parent.width
                                    text: root.reciters.length > 0
                                          ? root.reciters[root.selectedReciterIndex].name
                                          : (root.fetchingReciters ? "Loading reciters…"
                                                                   : "Reciters")
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Theme.fontWeightMedium
                                    color: Theme.surfaceText
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    width: parent.width
                                    text: root.reciters.length > 0
                                          ? root.reciters[root.selectedReciterIndex].moshaf_name
                                          : (root.reciterStatus || "Refresh to load the reciter list")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    elide: Text.ElideRight
                                }
                            }

                            DRefreshButton {
                                busy: root.fetchingReciters
                                tooltipText: "Refresh reciters"
                                onClicked: root.fetchReciters()
                            }
                        }

                        DSearchField {
                            id: reciterSearchField
                            width: parent.width
                            placeholderText: root.reciters.length > 0
                                             ? "Search reciters or riwayah…"
                                             : "Reciter list is not available"
                            enabled: root.reciters.length > 0
                            text: root.reciterSearch
                            onTextEdited: root.reciterSearch = text
                        }

                        StyledText {
                            width: parent.width
                            visible: root.reciterSearch.trim() !== "" && root.filteredReciters().length === 0
                            text: "No matching reciters"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }
                }

                DCard {
                    width: parent.width
                    height: root.reciterListHeight + Theme.spacingM * 2
                    pad: Theme.spacingM
                    visible: root.reciterSearch.trim() !== "" && root.filteredReciters().length > 0

                    DListView {
                        anchors.fill: parent
                        clip: true
                        model: root.filteredReciters()
                        spacing: Theme.spacingXS

                        delegate: Item {
                            width: ListView.view.width
                            height: root.quranRowHeight

                            Rectangle {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingXS
                                anchors.rightMargin: Theme.spacingXS
                                radius: Theme.cornerRadiusS
                                color: reciterResultMouse.containsMouse
                                       ? Theme.foregroundColor(Theme.chipSurface)
                                       : "transparent"
                            }

                            Column {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Theme.spacingM
                                anchors.rightMargin: Theme.spacingM
                                spacing: Theme.spacingXXS

                                StyledText {
                                    width: parent.width
                                    text: modelData.reciter.name
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Theme.fontWeightMedium
                                    color: Theme.surfaceText
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    width: parent.width
                                    text: modelData.reciter.moshaf_name
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: reciterResultMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.selectedReciterIndex = modelData.index
                                    root.reciterSearch = ""
                                }
                            }
                        }
                    }
                }

                DCard {
                    id: surahCard
                    width: parent.width
                    height: surahContent.implicitHeight + surahCard.pad * 2
                    pad: Theme.spacingM

                    Column {
                        id: surahContent
                        width: parent.width
                        spacing: Theme.spacingS

                        RowLayout {
                            width: parent.width

                            StyledText {
                                Layout.fillWidth: true
                                text: "Surah"
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Theme.fontWeightBold
                                color: Theme.surfaceVariantText
                            }

                            StyledText {
                                text: root.reciters.length > 0 ? root.reciters[root.selectedReciterIndex].name : ""
                                font.pixelSize: Theme.fontSizeXSmall
                                color: Theme.surfaceVariantText
                                elide: Text.ElideRight
                                Layout.maximumWidth: parent.width / 2
                            }
                        }

                        DListView {
                            width: parent.width
                            height: root.surahListHeight
                            clip: true
                            model: 114
                            spacing: Theme.spacingXXS

                            delegate: Item {
                                width: ListView.view.width
                                height: root.standardRowHeight

                                readonly property int surahNum: index + 1
                                readonly property bool isPlaying: root.playingSurah === surahNum

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacingXS
                                    anchors.rightMargin: Theme.spacingXS
                                    radius: Theme.cornerRadiusS
                                    color: isPlaying ? Theme.withAlpha(Theme.primary, 0.14)
                                                     : surahMouse.containsMouse
                                                       ? Theme.foregroundColor(Theme.chipSurface)
                                                       : "transparent"
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacingM
                                    anchors.rightMargin: Theme.spacingM
                                    spacing: Theme.spacingS

                                    StyledText {
                                        Layout.preferredWidth: root.surahNumberWidth
                                        text: surahNum
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: isPlaying ? Theme.primary : Theme.surfaceVariantText
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.surahNames[index]
                                        font.pixelSize: Theme.fontSizeMedium
                                        color: isPlaying ? Theme.primary : Theme.surfaceText
                                        elide: Text.ElideRight
                                    }

                                    DIcon {
                                        Layout.preferredWidth: Theme.iconSizeSmall
                                        Layout.preferredHeight: Theme.iconSizeSmall
                                        name: isPlaying ? "stop" : "play_arrow"
                                        size: Theme.iconSizeSmall
                                        color: isPlaying ? Theme.primary : Theme.surfaceVariantText
                                    }
                                }

                                MouseArea {
                                    id: surahMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (isPlaying)
                                            root.stopQuran()
                                        else
                                            root.playSurah(root.selectedReciterIndex, surahNum)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
