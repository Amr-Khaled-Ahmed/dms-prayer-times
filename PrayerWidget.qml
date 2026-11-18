import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root
    pluginId: "prayerTimes"

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
    property int nextTimeSec: 0
    property int nextTotalSeconds: 0

    // Settings
    property bool iconOnly: pluginData.iconOnly ?? false
    property bool showSeconds: pluginData.showSeconds ?? false
    property bool use12H: false
    property int notifyThresholdSec: (Number(pluginData.notifyMinutes) || 15) * 60
    property bool playAthanSound: pluginData.playAthanSound ?? false
    property string athanSoundPath: pluginData.athanSoundPath ?? ""
    property bool quranEnabled: pluginData.quranEnabled ?? true
    property bool autoLocation: pluginData.autoLocation === true
    property string latitude: pluginData.latitude ?? ""
    property string longitude: pluginData.longitude ?? ""
    property string timeZoneOffset: pluginData.timeZoneOffset ?? ""

    // Resolved at runtime from wherever this plugin is actually installed —
    // never hardcode a path, so the plugin works on any machine/user.
    readonly property string pluginDir: {
        let fullUrl = Qt.resolvedUrl(".").toString()
        return fullUrl.replace("file://", "")
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
    readonly property color subtleBg: Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.05)

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
            if (code === 0) cacheReader.running = true
            root.fetching = false
        }
    }

    // Cache reader
    Process {
        id: cacheReader
        command: ["cat", root.pluginDir + "cache.json"]
        stdout: SplitParser {
            onRead: function(line) {
                if (line.trim() === "") return
                try {
                    var obj = JSON.parse(line)
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
                            Imsak:   t[0],
                            Sunset:  t[4]
                        },
                        date: {
                            readable: obj.date || "",
                            hijri: obj.hijri || ""
                        }
                    }
                    processPrayerData(fakeData)
                } catch(e) {
                    console.warn("Prayer Times: couldn't parse cached schedule:", e)
                }
            }
        }
    }

    // Reciter list fetcher (hits mp3quran.net once, caches to reciters.json)
    Process {
        id: reciterFetcher
        command: ["python3", root.pluginDir + "fetch_reciters.py", root.pluginDir + "reciters.json"]
        onExited: function(code) {
            root.fetchingReciters = false
            root.reciterStatus = code === 0 ? "" : "Couldn't refresh the reciter list."
            reciterCacheReader.running = true
        }
    }

    // Reciter cache reader
    Process {
        id: reciterCacheReader
        command: ["cat", root.pluginDir + "reciters.json"]
        stdout: SplitParser {
            onRead: function(line) {
                if (line.trim() === "") return
                try {
                    var obj = JSON.parse(line)
                    if (obj.reciters && obj.reciters.length > 0) {
                        root.reciters = obj.reciters
                        if (root.selectedReciterIndex >= root.reciters.length) root.selectedReciterIndex = 0
                    }
                } catch(e) {
                    console.warn("Prayer Times: couldn't parse cached reciters:", e)
                }
            }
        }
    }

    // Initialize when plugin service is ready
    onPluginServiceChanged: {
        if (pluginService) {
            loadPluginData()
            cacheReader.running = true
            Qt.callLater(root.fetchPrayerTimes)
            reciterCacheReader.running = true // pick up any previously cached reciter list
        }
    }

    Connections {
        target: SettingsData
        function onPluginSettingsChanged() {
            if (!root.pluginService) return
            root.loadPluginData()
            Qt.callLater(root.fetchPrayerTimes)
        }
    }

    onAutoLocationChanged: fetchPrayerTimes()
    onLatitudeChanged: if (!autoLocation) fetchPrayerTimes()
    onLongitudeChanged: if (!autoLocation) fetchPrayerTimes()
    onTimeZoneOffsetChanged: if (!autoLocation) fetchPrayerTimes()

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

        var args = ["python3", root.pluginDir + "get_times.py", root.pluginDir + "cache.json"]

        if (root.autoLocation) {
            args.push("auto")
        } else {
            if (root.latitude === "" || root.longitude === "" || root.timeZoneOffset === "") {
                cacheReader.running = true
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

        root.fetching = true
        pyRunner.command = args
        pyRunner.running = false
        pyRunner.running = true
    }

    // Runs an audio file/URL through whichever player is installed (mpv, then ffplay, then cvlc)
    function playerCommandFor(target) {
        return ["bash", "-c",
            "if command -v mpv >/dev/null 2>&1; then exec mpv --no-video --really-quiet \"$0\"; " +
            "elif command -v ffplay >/dev/null 2>&1; then exec ffplay -nodisp -autoexit -loglevel quiet \"$0\"; " +
            "elif command -v cvlc >/dev/null 2>&1; then exec cvlc --play-and-exit -q \"$0\"; " +
            "else notify-send -a 'Prayer Widget' 'No audio player found — install mpv, ffplay, or cvlc'; fi",
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
        if (!root.playAthanSound || root.athanSoundPath === "") return
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
        var mins = Math.ceil(root.nextTotalSeconds / 60)
        prayerNotifyProc.command = [
            "notify-send", "-a", "Prayer Widget", "-u", "critical", "-i", iconPath,
            root.nextName + " in " + mins + " min (at " + root.formatTime(root.nextTime) + ")"
        ]
        prayerNotifyProc.running = true
    }

    function sendPrayerTimeNotification() {
        prayerNotifyProc.command = [
            "notify-send", "-a", "Prayer Widget", "-u", "critical", "-i", iconPath,
            "Time for " + root.nextName
        ]
        prayerNotifyProc.running = true
        root.playAthan()
    }

    // Countdown update + notifications
    function updateCountdown() {
        var now    = clock.date
        var nowSec = now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds()
        var rawDiff = root.nextTimeSec - nowSec
        var diff = rawDiff
        if (diff < 0) diff += 86400
        root.nextTotalSeconds = diff

        var urgent = diff > 0 && diff <= root.notifyThresholdSec
        if (urgent && !root._wasUrgent) sendPrayerNotification()

        var atTime = (rawDiff <= 0 && rawDiff > -60)
        if (atTime && !root._wasAtTime) sendPrayerTimeNotification()

        root._wasUrgent = urgent
        root._wasAtTime = atTime
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
        if (nowStr < fajrT)    return { currName: "Isha",    nextName: "Fajr",    nextTime: fajrT    }
        if (nowStr < dhuhrT)   return { currName: "Fajr",    nextName: "Dhuhr",   nextTime: dhuhrT   }
        if (nowStr < asrT)     return { currName: "Dhuhr",   nextName: "Asr",     nextTime: asrT     }
        if (nowStr < maghribT) return { currName: "Asr",     nextName: "Maghrib", nextTime: maghribT }
        if (nowStr < ishaT)    return { currName: "Maghrib", nextName: "Isha",    nextTime: ishaT    }
        return                        { currName: "Isha",    nextName: "Fajr",    nextTime: fajrT    }
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
        var period = determinePrayerPeriod(
            nowStr, root.fajr, root.dhuhr, root.asr, root.maghrib, root.isha
        )

        root.nextTimeSec = timeToMinutes(period.nextTime) * 60
        if (root.nextName !== period.nextName) {
            root._wasUrgent = false
            root._wasAtTime = false
        }
        root.currName = period.currName
        root.nextName = period.nextName
        root.nextTime = period.nextTime
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

    // Horizontal bar pill
    horizontalBarPill: Component {
        Row {
            spacing: root.iconOnly ? 0 : Theme.spacingXS
            rightPadding: root.iconOnly ? 0 : Theme.spacingS

            DankIcon {
                name: root.getPrayerIcon(root.currName)
                size: Theme.iconSize - 6
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: !root.iconOnly
               // text: root.nextTime !== "" ? (root.nextName + " " + root.formatTime(root.nextTime)) : "Loading..."
              text: root.nextTime !== "" ? root.nextName : "Loading..."
               font.pixelSize: Theme.fontSizeSmall
              color: Theme.secondary
              anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: !root.iconOnly && root.nextTime !== ""
                text: "·"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                leftPadding: 2; rightPadding: 2
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: !root.iconOnly && root.nextTime !== ""
                text: root.formatCountdown(root.nextTotalSeconds)
                font.pixelSize: Theme.fontSizeSmall
                font.weight: root.isUrgent ? Font.Bold : Font.Normal
                color: root.isUrgent ? root.accentColor : Theme.secondary
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // Vertical bar pill
    verticalBarPill: Component {
        Column {
            spacing: 2

            DankIcon {
                name: root.getPrayerIcon(root.currName)
                size: Theme.iconSize - 6
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                visible: root.nextTime !== ""
                text: root.formatCountdown(root.nextTotalSeconds)
                font.pixelSize: Theme.fontSizeSmall - 2
                color: root.isUrgent ? root.accentColor : Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // Popout panel
    popoutContent: Component {
        Item {
            id: popoutRoot
            width: 260
            implicitWidth: 260
            implicitHeight: content.implicitHeight + Theme.spacingM * 2

            Column {
                id: content
                spacing: Theme.spacingS
                anchors.fill: parent
                anchors.margins: Theme.spacingM

                Item {
                    width: parent.width
                    height: Math.max(dateCol.implicitHeight, refreshPill.height)

                    Column {
                        id: dateCol
                        spacing: 2
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            text: root.dateHijr
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                        }

                        StyledText {
                            text: root.dateGreg
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    Rectangle {
                        id: refreshPill
                        width: 28; height: 28; radius: width / 2
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        color: refreshArea.containsMouse
                               ? Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.12)
                               : root.subtleBg

                        DankIcon {
                            name: "refresh"
                            size: Theme.iconSize - 4
                            color: Theme.surfaceVariantText
                            anchors.centerIn: parent
                        }

                        MouseArea {
                            id: refreshArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.fetchPrayerTimes()
                        }
                    }
                }

                // Tab switcher (only shown when the Quran panel is enabled)
                Row {
                    width: parent.width
                    spacing: Theme.spacingXS
                    visible: root.quranEnabled

                    Rectangle {
                        width: (parent.width - Theme.spacingXS) / 2
                        height: 28
                        radius: 6
                        color: !root.showQuranPanel ? root.accentBg : root.subtleBg
                        border.color: !root.showQuranPanel ? root.accentColor : "transparent"
                        border.width: !root.showQuranPanel ? 1 : 0

                        StyledText {
                            anchors.centerIn: parent
                            text: "Prayers"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: !root.showQuranPanel ? Font.Bold : Font.Normal
                            color: !root.showQuranPanel ? root.accentColor : Theme.surfaceVariantText
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showQuranPanel = false
                        }
                    }

                    Rectangle {
                        width: (parent.width - Theme.spacingXS) / 2
                        height: 28
                        radius: 6
                        color: root.showQuranPanel ? root.accentBg : root.subtleBg
                        border.color: root.showQuranPanel ? root.accentColor : "transparent"
                        border.width: root.showQuranPanel ? 1 : 0

                        StyledText {
                            anchors.centerIn: parent
                            text: "Quran"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: root.showQuranPanel ? Font.Bold : Font.Normal
                            color: root.showQuranPanel ? root.accentColor : Theme.surfaceVariantText
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showQuranPanel = true
                        }
                    }
                }

                // ── Prayers panel ──────────────────────────────────────────
                Column {
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: !root.showQuranPanel || !root.quranEnabled

                    // Countdown card
                    Rectangle {
                        width: parent.width
                        height: cdCol.implicitHeight + Theme.spacingM * 2
                        radius: 8
                        color: root.accentBg
                        border.color: root.accentColor
                        border.width: 1

                        Column {
                            id: cdCol
                            anchors.centerIn: parent
                            spacing: 4

                            StyledText {
                                text: root.nextName !== "" ? (root.nextName + "  in") : "..."
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            StyledText {
                                text: root.nextTime !== "" ? root.formatCountdown(root.nextTotalSeconds) : "..."
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                                color: root.isUrgent ? root.accentColor : Theme.surfaceText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            StyledText {
                                text: root.nextTime !== "" ? ("at  " + root.formatTime(root.nextTime)) : ""
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }

                    // Prayer times list
                    Repeater {
                        model: [
                            { label: "Imsak",   time: root.imsak,   icon: "moon_stars" },
                            { label: "Fajr",    time: root.fajr,    icon: "bedtime" },
                            { label: "Sunrise", time: root.sunrise, icon: "wb_twilight" },
                            { label: "Dhuhr",   time: root.dhuhr,   icon: "wb_sunny" },
                            { label: "Asr",     time: root.asr,     icon: "light_mode" },
                            { label: "Maghrib", time: root.maghrib, icon: "wb_twilight" },
                            { label: "Isha",    time: root.isha,    icon: "bedtime" }
                        ]

                        delegate: Item {
                            width: parent.width
                            height: 36

                            readonly property bool isNext: modelData.label === root.nextName
                            readonly property bool isCurr: modelData.label === root.currName

                            Rectangle {
                                anchors.fill: parent
                                anchors.leftMargin: 6; anchors.rightMargin: 6
                                anchors.topMargin: 2; anchors.bottomMargin: 2
                                radius: height / 2
                                color: isNext ? root.accentBg : (isCurr ? root.subtleBg : "transparent")
                                border.color: isNext ? root.accentColor : "transparent"
                                border.width: isNext ? 1 : 0
                            }

                            Item {
                                anchors.fill: parent
                                anchors.leftMargin: 12; anchors.rightMargin: 12

                                Row {
                                    spacing: Theme.spacingS
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter

                                    DankIcon {
                                        name: modelData.icon
                                        size: Theme.iconSize
                                        color: isNext ? root.accentColor : (isCurr ? Theme.surfaceText : Theme.surfaceVariantText)
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    StyledText {
                                        text: modelData.label
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: (isNext || isCurr) ? Font.Bold : Font.Normal
                                        color: isNext ? root.accentColor : (isCurr ? Theme.surfaceText : Theme.surfaceVariantText)
                                        width: 64
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                StyledText {
                                    text: root.formatTime(modelData.time)
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: (isNext || isCurr) ? Font.Bold : Font.Normal
                                    color: isNext ? root.accentColor : (isCurr ? Theme.surfaceText : Theme.surfaceVariantText)
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    horizontalAlignment: Text.AlignRight
                                    width: 70
                                }
                            }
                        }
                    }
                }

                // ── Quran panel ────────────────────────────────────────────
                Column {
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: root.showQuranPanel && root.quranEnabled

                    StyledText {
                        width: parent.width
                        text: root.reciters.length > 0
                              ? "Selected · " + root.reciters[root.selectedReciterIndex].name
                                + " — " + root.reciters[root.selectedReciterIndex].moshaf_name
                              : (root.fetchingReciters ? "Fetching reciters..."
                                 : root.reciterStatus || "No reciter list loaded")
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                    }

                    DTextField {
                        width: parent.width
                        height: 36
                        placeholderText: root.reciters.length > 0
                                ? "Search reciters or riwayah..."
                                : "Reciter list is not available"
                        enabled: root.reciters.length > 0
                        text: root.reciterSearch
                        onTextChanged: root.reciterSearch = text
                    }

                    StyledText {
                        width: parent.width
                        visible: root.reciterSearch.trim() !== "" && root.filteredReciters().length === 0
                        text: "No matching reciters"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    ListView {
                        width: parent.width
                        height: 112
                        visible: root.reciterSearch.trim() !== "" && root.filteredReciters().length > 0
                        clip: true
                        model: root.filteredReciters()

                        delegate: Item {
                            width: ListView.view.width
                            height: 44

                            Rectangle {
                                anchors.fill: parent
                                radius: 6
                                color: reciterResultMouse.containsMouse ? root.subtleBg : "transparent"
                            }

                            Column {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Theme.spacingS
                                anchors.rightMargin: Theme.spacingS
                                spacing: 2

                                StyledText {
                                    width: parent.width
                                    text: modelData.reciter.name
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
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

                    // Refresh row
                    Item {
                        width: parent.width
                        height: 24

                        StyledText {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.reciters.length + " moshaf entries cached"
                            font.pixelSize: Theme.fontSizeSmall - 1
                            color: Theme.surfaceVariantText
                        }

                        Rectangle {
                            anchors.right: parent.right
                            width: 24; height: 24; radius: 12
                            color: root.subtleBg

                            DankIcon {
                                name: "refresh"
                                size: Theme.iconSize - 8
                                color: Theme.surfaceVariantText
                                anchors.centerIn: parent
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.fetchReciters()
                            }
                        }
                    }

                    // Surah list
                    ListView {
                        width: parent.width
                        height: 220
                        clip: true
                        model: 114

                        delegate: Item {
                            width: ListView.view.width
                            height: 32

                            readonly property int surahNum: index + 1
                            readonly property bool isPlaying: root.playingSurah === surahNum

                            Rectangle {
                                anchors.fill: parent
                                radius: 6
                                color: isPlaying ? root.accentBg : "transparent"
                            }

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 8; anchors.rightMargin: 8
                                spacing: Theme.spacingS

                                StyledText {
                                    width: 22
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: surahNum
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }

                                StyledText {
                                    width: parent.width - 80
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.surahNames[index]
                                    font.pixelSize: Theme.fontSizeMedium
                                    elide: Text.ElideRight
                                    color: isPlaying ? root.accentColor : Theme.surfaceText
                                }

                                DankIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: isPlaying ? "stop" : "play_arrow"
                                    size: Theme.iconSize - 4
                                    color: isPlaying ? root.accentColor : Theme.surfaceVariantText
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (isPlaying) root.stopQuran()
                                    else root.playSurah(root.selectedReciterIndex, surahNum)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
