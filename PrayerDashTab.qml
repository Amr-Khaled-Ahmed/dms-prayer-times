// PrayerDashTab.qml — Prayer Times Enhanced dashboard tab.
// Reads pluginData and the shared cache directly; no logic is shared with the
// bar widget. Auto-location resolves coordinates with an HTTP request to
// ip-api.com, and Quran recitations stream from mp3quran.net.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Modules.DDash
import qs.Modules.DDash.Overview

DashTabComponent {
    id: root

    // ── Shared plugin settings (same keys used by PrayerWidget) ──────────────
    readonly property bool use12H:          options.use12H        ?? false
    readonly property bool showQuranInDash: options.showQuranInDash ?? true

    // Prayer time data — populated by the Python back-end via shared cache
    property string fajr:    ""
    property string dhuhr:   ""
    property string asr:     ""
    property string maghrib: ""
    property string isha:    ""
    property string imsak:   ""
    property string sunrise: ""
    property string dateHijr: ""
    property string dateGreg: ""
    property string statusMessage: ""
    property bool   hasPrayerData: false
    property string reciterStatus: ""

    property string currName: ""
    property string nextName: ""
    property string nextTime: ""
    property int    nextTimeSec:    0
    property int    nextTotalSecs:  0
    property bool   fetching:       false

    // Quran state (independent copy for the dash tab)
    property bool   showQuranPanel:    false
    property var    reciters:          []
    property int    selectedReciter:   0
    property string reciterSearch:     ""
    property int    playingSurah:      -1
    property bool   quranPlaying:      false
    property bool   fetchingReciters:  false
    readonly property real notifyMinutes: {
        const raw = pluginData.notifyMinutes
        if (raw === undefined || raw === null || String(raw).trim() === "") return 15
        const value = Number(raw)
        return Number.isFinite(value) ? value : 15
    }
    property int notifyThresholdSec: notifyMinutes * 60

    readonly property bool isUrgent: nextTotalSecs > 0 && nextTotalSecs <= notifyThresholdSec
    readonly property int headerHeight: Theme.spacingXL + Theme.spacingM
    readonly property int standardRowHeight: Theme.spacingXL + Theme.spacingM
    readonly property int quranRowHeight: Theme.spacingXL + Theme.spacingL + Theme.spacingXS
    readonly property int heroCardHeight: Theme.spacingXL * 4 + Theme.spacingS
    readonly property int refreshButtonSize: Theme.spacingXL + Theme.spacingS
    readonly property int compactControlSize: Theme.spacingXL + Theme.spacingXS
    readonly property int reciterRefreshSize: Theme.spacingXL + Theme.spacingXXS
    readonly property int reciterCardHeight: Theme.spacingXL * 4 + Theme.spacingM + Theme.spacingXXS
    readonly property int reciterResultsHeight: Theme.spacingXL * 6 + Theme.spacingM
    readonly property int surahCardHeight: Theme.spacingXL * 11 + Theme.spacingL
    readonly property int prayerLabelWidth: Theme.spacingXL * 3 - Theme.spacingXXS
    readonly property int prayerTimeWidth: Theme.spacingXL * 3 + Theme.spacingS
    readonly property int surahNumberWidth: Theme.spacingXL
    readonly property int surahTextInset: Theme.spacingXL * 3

    // Plugin directory (resolved at runtime — works on any install path)
    readonly property string pluginDir: {
        let u = Qt.resolvedUrl(".").toString()
        return u.replace("file://", "")
    }
    readonly property string cacheDir: Paths.strip(Paths.cache) + "/prayerTimesEnhanced"
    readonly property string cachePath: cacheDir + "/cache.json"
    readonly property string reciterCachePath: cacheDir + "/reciters.json"

    // ── Surah name list (Arabic) ────────────────────────────────────────────
    readonly property var surahNames: [
        "الفاتحة","البقرة","آل عمران","النساء","المائدة","الأنعام","الأعراف","الأنفال",
        "التوبة","يونس","هود","يوسف","الرعد","إبراهيم","الحجر","النحل",
        "الإسراء","الكهف","مريم","طه","الأنبياء","الحج","المؤمنون","النور",
        "الفرقان","الشعراء","النمل","القصص","العنكبوت","الروم","لقمان","السجدة",
        "الأحزاب","سبأ","فاطر","يس","الصافات","ص","الزمر","غافر",
        "فصلت","الشورى","الزخرف","الدخان","الجاثية","الأحقاف","محمد","الفتح",
        "الحجرات","ق","الذاريات","الطور","النجم","القمر","الرحمن","الواقعة",
        "الحديد","المجادلة","الحشر","الممتحنة","الصف","الجمعة","المنافقون","التغابن",
        "الطلاق","التحريم","الملك","القلم","الحاقة","المعارج","نوح","الجن",
        "المزمل","المدثر","القيامة","الإنسان","المرسلات","النبأ","النازعات","عبس",
        "التكوير","الانفطار","المطففين","الانشقاق","البروج","الطارق","الأعلى","الغاشية",
        "الفجر","البلد","الشمس","الليل","الضحى","الشرح","التين","العلق",
        "القدر","البينة","الزلزلة","العاديات","القارعة","التكاثر","العصر","الهمزة",
        "الفيل","قريش","الماعون","الكوثر","الكافرون","النصر","المسد","الإخلاص",
        "الفلق","الناس"
    ]

    // ── Back-end processes ───────────────────────────────────────────────────
    Process {
        id: pyRunner
        onExited: function(code) {
            if (code === 0) {
                cacheView.reload()
                if (root.hasPrayerData) root.statusMessage = ""
            } else {
                root.statusMessage = root.hasPrayerData
                        ? "Update failed; showing saved prayer times."
                        : "Could not load prayer times. Check your location settings."
            }
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
                if (!Array.isArray(obj.times) || obj.times.length < 6) {
                    console.warn("Prayer Times: cached schedule has an invalid format")
                    return
                }
                const t = obj.times
                root.processPrayerData({
                    timings: {
                        Fajr:    t[0], Sunrise: t[1], Dhuhr:   t[2],
                        Asr:     t[3], Maghrib: t[4], Isha:    t[5],
                        Imsak:   obj.imsak || t[6] || "", Sunset:  t[4]
                    },
                    date: { readable: obj.date || "", hijri: obj.hijri || "" }
                })
            } catch(e) {
                console.warn("Prayer Times: couldn't parse cached schedule:", e)
            }
        }

        onLoadFailed: {
            if (!root.hasPrayerData)
                root.statusMessage = "No saved prayer times. Set your location in plugin settings."
        }
    }

    Process {
        id: reciterFetcher
        command: ["python3", root.pluginDir + "fetch_reciters.py", root.reciterCachePath]
        onExited: function(code) {
            root.fetchingReciters = false
            root.reciterStatus = code === 0 ? "" : "Couldn't refresh the reciter list."
            reciterCacheView.reload()
        }
    }

    FileView {
        id: reciterCacheView
        path: root.reciterCachePath
        watchChanges: true
        blockLoading: false
        printErrors: false

        onLoaded: {
            try {
                const obj = JSON.parse(reciterCacheView.text())
                const safeReciters = Array.isArray(obj.reciters)
                    ? obj.reciters.filter(function(r) {
                        return r && typeof r.server === "string" && r.server.startsWith("https://")
                    })
                    : []
                if (safeReciters.length > 0) {
                    root.reciters = safeReciters
                    if (root.selectedReciter >= root.reciters.length)
                        root.selectedReciter = 0
                }
            } catch(e) {
                console.warn("Prayer Times: couldn't parse cached reciters:", e)
            }
        }
    }

    Process {
        id: quranPlayer
        running: false
        onExited: function() { root.quranPlaying = false; root.playingSurah = -1 }
    }

    // ── Clock & timers ───────────────────────────────────────────────────────
    SystemClock {
        id: clock
        enabled: root.live
        precision: SystemClock.Minutes
        onDateChanged: { if (root.nextTimeSec > 0) root.updateCountdown() }
    }

    Timer {
        interval: 3600000; repeat: true; running: root.live
        onTriggered: root.fetchPrayerTimes()
    }

    Component.onCompleted: {
        Paths.mkdir(root.cacheDir)
        cacheView.reload()
        root.fetchPrayerTimes()
        reciterCacheView.reload()
    }

    onPluginDataChanged: Qt.callLater(root.fetchPrayerTimes)

    onShowQuranPanelChanged: {
        if (showQuranPanel && root.reciters.length === 0 && !root.fetchingReciters)
            root.doFetchReciters()
    }

    // ── Helper functions ─────────────────────────────────────────────────────
    function fetchPrayerTimes() {
        if (root.fetching) return
        const loc = pluginData.autoLocation === true
        const latitude = Number(pluginData.latitude)
        const longitude = Number(pluginData.longitude)
        const offset = Number(pluginData.timeZoneOffset)
        const validManualLocation = root.hasManualLocation()
        if (!loc && !validManualLocation) {
            root.statusMessage = root.hasPrayerData
                    ? "Showing saved times. Add a valid location to refresh them."
                    : "Set your latitude, longitude and UTC offset in plugin settings."
            return
        }
        root.statusMessage = "Updating prayer times…"
        root.fetching = true
        const args = ["python3", root.pluginDir + "get_times.py", root.cachePath]
        if (loc) {
            args.push("auto")
        } else {
            args.push("manual", String(latitude), String(longitude), String(offset))
        }
        pyRunner.command = args
        pyRunner.running = false
        pyRunner.running = true
    }

    function stripTZ(s) { return s ? s.split(" ")[0] : "" }
    function hasManualLocation() {
        const latitude = Number(pluginData.latitude)
        const longitude = Number(pluginData.longitude)
        const offset = Number(pluginData.timeZoneOffset)
        return String(pluginData.latitude ?? "").trim() !== ""
                && String(pluginData.longitude ?? "").trim() !== ""
                && String(pluginData.timeZoneOffset ?? "").trim() !== ""
                && Number.isFinite(latitude) && latitude >= -90 && latitude <= 90
                && Number.isFinite(longitude) && longitude >= -180 && longitude <= 180
                && Number.isFinite(offset) && offset >= -14 && offset <= 14
    }
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
        return h > 0 ? (h < 10 ? "0" : "") + h + ":" + mm : m + " min"
    }
    function determinePeriod(now, fajr, dhuhr, asr, maghrib, isha) {
        if (now < fajr)    return { currName:"Isha",    nextName:"Fajr",    nextTime:fajr    }
        if (now < dhuhr)   return { currName:"Fajr",    nextName:"Dhuhr",   nextTime:dhuhr   }
        if (now < asr)     return { currName:"Dhuhr",   nextName:"Asr",     nextTime:asr     }
        if (now < maghrib) return { currName:"Asr",     nextName:"Maghrib", nextTime:maghrib }
        if (now < isha)    return { currName:"Maghrib", nextName:"Isha",    nextTime:isha    }
        return             { currName:"Isha",    nextName:"Fajr",    nextTime:fajr    }
    }
    function processPrayerData(data) {
        if (!data || !data.timings || !data.timings.Fajr || !data.timings.Dhuhr
                || !data.timings.Asr || !data.timings.Maghrib || !data.timings.Isha) {
            console.warn("Prayer Times: received an incomplete schedule")
            return
        }
        root.fajr    = stripTZ(data.timings.Fajr)
        root.dhuhr   = stripTZ(data.timings.Dhuhr)
        root.asr     = stripTZ(data.timings.Asr)
        root.maghrib = stripTZ(data.timings.Maghrib)
        root.isha    = stripTZ(data.timings.Isha)
        root.imsak   = stripTZ(data.timings.Imsak || "")
        root.sunrise = stripTZ(data.timings.Sunrise || "")
        root.dateGreg = data.date.readable || ""
        root.dateHijr = data.date.hijri || ""
        root.hasPrayerData = true
        if (!root.fetching) {
            const locationConfigured = pluginData.autoLocation === true || root.hasManualLocation()
            const today = Qt.formatDate(clock.date, "yyyy-MM-dd")
            if (!locationConfigured) {
                root.statusMessage = root.dateGreg !== today
                        ? "Showing saved times from " + root.dateGreg + ". Set a valid location to calculate today's schedule."
                        : "Showing saved times. Add a valid location to refresh them."
            } else {
                root.statusMessage = root.dateGreg !== today
                        ? "Saved schedule is from " + root.dateGreg + ". Refresh to calculate today's times."
                        : ""
            }
        }
        const now = Qt.formatTime(clock.date, "HH:mm")
        root.refreshPeriod(now)
        root.updateCountdown()
    }
    function refreshPeriod(now) {
        if (!root.fajr || !root.dhuhr || !root.asr || !root.maghrib || !root.isha)
            return false
        const period = determinePeriod(now, root.fajr, root.dhuhr, root.asr, root.maghrib, root.isha)
        root.nextTimeSec = timeToMin(period.nextTime) * 60
        root.currName = period.currName
        root.nextName = period.nextName
        root.nextTime = period.nextTime
        return true
    }
    function updateCountdown() {
        const now    = clock.date
        const nowSec = now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds()
        let diff = root.nextTimeSec - nowSec

        // Advance immediately when a prayer has passed so the card never shows
        // a stale ~24h countdown between cache refreshes.
        if (root.nextTimeSec > 0 && diff <= 0) {
            if (root.refreshPeriod(Qt.formatTime(now, "HH:mm")))
                diff = root.nextTimeSec - nowSec
        }
        if (diff < 0) diff += 86400
        root.nextTotalSecs = Math.max(0, diff)
    }
    function getPrayerIcon(name) {
        const m = { Fajr:"bedtime", Dhuhr:"wb_sunny", Asr:"light_mode", Maghrib:"wb_twilight", Isha:"bedtime" }
        return m[name] || "mosque"
    }
    function pad3(n) { let s = "" + n; while (s.length < 3) s = "0" + s; return s }
    function doFetchReciters() {
        if (root.fetchingReciters) return
        root.fetchingReciters = true
        root.reciterStatus = ""
        reciterFetcher.running = true
    }
    function filteredReciters() {
        const query = root.reciterSearch.trim().toLowerCase()
        if (query === "") return []
        const matches = []
        for (let i = 0; i < root.reciters.length; i++) {
            const reciter = root.reciters[i]
            const searchable = (String(reciter.name || "") + " "
                               + String(reciter.moshaf_name || "")).toLowerCase()
            if (searchable.includes(query))
                matches.push({ index: i, reciter: reciter })
        }
        return matches
    }
    function playSurah(ridx, num) {
        if (!root.reciters.length) return
        const reciter = root.reciters[ridx]
        if (!reciter || typeof reciter.server !== "string"
                || !reciter.server.startsWith("https://"))
            return
        const url = reciter.server + pad3(num) + ".mp3"
        quranPlayer.command = ["sh", "-c",
            "if command -v mpv >/dev/null 2>&1; then exec mpv --no-video --really-quiet -- \"$0\"; " +
            "elif command -v ffplay >/dev/null 2>&1; then exec ffplay -nodisp -autoexit -loglevel quiet -- \"$0\"; " +
            "elif command -v cvlc >/dev/null 2>&1; then exec cvlc --play-and-exit -q -- \"$0\"; " +
            "else dms notify -a 'Prayer Times Enhanced' 'No audio player found — install mpv, ffplay, or cvlc'; fi", url]
        quranPlayer.running = false; quranPlayer.running = true
        root.playingSurah = num; root.quranPlaying = true
    }
    function stopQuran() { quranPlayer.running = false; root.quranPlaying = false; root.playingSurah = -1 }

    // ── Focus & height ───────────────────────────────────────────────────────
    focusTarget: mainContent
    implicitHeight: Math.max(DashMetrics.tabMinHeight, mainContent.implicitHeight + Theme.spacingL * 2)

    // ── UI ───────────────────────────────────────────────────────────────────
    Column {
        id: mainContent
        anchors.top:              parent.top
        anchors.left:             parent.left
        anchors.right:            parent.right
        anchors.topMargin:        Theme.spacingL
        anchors.leftMargin:       Theme.spacingL
        anchors.rightMargin:      Theme.spacingL
        spacing:                  Theme.spacingM

        // ── Header: Hijri/Gregorian date + refresh ───────────────────────────
        Item {
            width:  parent.width
            height: Math.max(dateCol.implicitHeight, root.headerHeight)

            Column {
                id: dateCol
                anchors.left:            parent.left
                anchors.verticalCenter:  parent.verticalCenter
                spacing: Theme.spacingXXS

                StyledText {
                    text:            root.dateHijr !== "" ? root.dateHijr : "Prayer times"
                    font.pixelSize:  Theme.fontSizeMedium
                    font.weight:     Font.Bold
                    color:           Theme.surfaceText
                }
                StyledText {
                    text:            root.dateGreg
                    font.pixelSize:  Theme.fontSizeSmall
                    color:           Theme.surfaceVariantText
                }
            }

            // Refresh button
            Rectangle {
                id: refreshBtn
                anchors.right:          parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: root.refreshButtonSize; height: root.refreshButtonSize; radius: width / 2
                color: refreshMA.containsMouse
                       ? Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.12)
                       : Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.06)
                DIcon {
                    name:            "refresh"
                    size:            Theme.iconSize
                    color:           Theme.surfaceVariantText
                    anchors.centerIn: parent
                }
                MouseArea {
                    id: refreshMA
                    anchors.fill:  parent
                    hoverEnabled:  true
                    cursorShape:   Qt.PointingHandCursor
                    onClicked:     root.fetchPrayerTimes()
                }
            }
        }

        StyledText {
            width: parent.width
            visible: root.statusMessage !== ""
            text: root.statusMessage
            font.pixelSize: Theme.fontSizeSmall
            color: root.hasPrayerData ? Theme.surfaceVariantText : Theme.error
            wrapMode: Text.WordWrap
        }

        // ── Countdown hero card ──────────────────────────────────────────────
        Card {
            id: heroCard
            width:   parent.width
            height:  root.heroCardHeight
            tone:    "primary"

            Row {
                id: heroCol
                anchors.fill: parent
                anchors.margins: Theme.spacingL
                spacing: Theme.spacingM

                DIcon {
                    name: root.nextName !== "" ? root.getPrayerIcon(root.nextName) : "mosque"
                    size: Theme.iconSizeLarge
                    color: root.isUrgent ? Theme.error : heroCard.contentColor
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    id: heroDetails
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS

                    StyledText {
                        text: root.nextName !== "" ? "Next prayer" : "Prayer schedule"
                        font.pixelSize: Theme.fontSizeSmall
                        color: heroCard.mutedColor
                    }
                    StyledText {
                        text: root.nextName !== "" ? root.nextName : (root.fetching ? "Loading…" : "Unavailable")
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: heroCard.contentColor
                    }
                    StyledText {
                        text: root.nextTime !== "" ? ("at " + root.formatTime(root.nextTime)) : ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: heroCard.mutedColor
                    }
                }

                Item {
                    width: Math.max(0, heroCol.width - Theme.iconSizeLarge
                                    - Theme.spacingM * 3 - heroDetails.implicitWidth
                                    - countdownText.implicitWidth)
                    height: 1
                }

                StyledText {
                    id: countdownText
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.nextTime !== "" ? root.formatCountdown(root.nextTotalSecs) : "—"
                    font.pixelSize: Theme.fontSizeDisplayLarge
                    font.weight: Font.Bold
                    color: root.isUrgent ? Theme.error : heroCard.contentColor
                }
            }
        }

        // ── Prayer times list ────────────────────────────────────────────────
        Card {
            width:   parent.width
            height:  prayerList.implicitHeight + Theme.spacingM * 2

            GridLayout {
                id: prayerList
                x: Theme.spacingM
                y: Theme.spacingM
                width: parent.width - Theme.spacingM * 2
                columns: width >= Theme.smallBreakpoint ? 2 : 1
                columnSpacing: Theme.spacingS
                rowSpacing: Theme.spacingXS

                StyledText {
                    text: "Today's schedule"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                    color: Theme.surfaceVariantText
                    Layout.fillWidth: true
                    Layout.columnSpan: prayerList.columns
                }

                Repeater {
                    model: [
                        { label:"Imsak",   time:root.imsak,   icon:"moon_stars"  },
                        { label:"Fajr",    time:root.fajr,    icon:"bedtime"     },
                        { label:"Sunrise", time:root.sunrise, icon:"wb_twilight" },
                        { label:"Dhuhr",   time:root.dhuhr,   icon:"wb_sunny"    },
                        { label:"Asr",     time:root.asr,     icon:"light_mode"  },
                        { label:"Maghrib", time:root.maghrib, icon:"wb_twilight" },
                        { label:"Isha",    time:root.isha,    icon:"bedtime"     }
                    ]
                    delegate: Item {
                        Layout.fillWidth: true
                        Layout.preferredWidth: (prayerList.width - prayerList.columnSpacing * (prayerList.columns - 1)) / prayerList.columns
                        Layout.preferredHeight: root.standardRowHeight

                        readonly property bool isNext: modelData.label === root.nextName
                        readonly property bool isCurr: modelData.label === root.currName

                        Rectangle {
                            anchors.fill:          parent
                            anchors.leftMargin:    Theme.spacingXS
                            anchors.rightMargin:   Theme.spacingXS
                            anchors.topMargin:     Theme.spacingXXS
                            anchors.bottomMargin:  Theme.spacingXXS
                            radius:                height / 2
                            color:  isNext ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
                                           : isCurr ? Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.07)
                                           : "transparent"
                            border.color: isNext ? Theme.primary : "transparent"
                            border.width: isNext ? 1 : 0
                        }

                        Item {
                            anchors.fill:          parent
                            anchors.leftMargin:    Theme.spacingM
                            anchors.rightMargin:   Theme.spacingM

                            Row {
                                spacing:                Theme.spacingS
                                anchors.left:           parent.left
                                anchors.verticalCenter: parent.verticalCenter

                                DIcon {
                                    name:  modelData.icon
                                    size:  Theme.iconSize
                                    color: isNext ? Theme.primary : (isCurr ? Theme.surfaceText : Theme.surfaceVariantText)
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text:            modelData.label
                                    font.pixelSize:  Theme.fontSizeMedium
                                    font.weight:     (isNext || isCurr) ? Font.Bold : Font.Normal
                                    color:           isNext ? Theme.primary : (isCurr ? Theme.surfaceText : Theme.surfaceVariantText)
                                    width:           root.prayerLabelWidth
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            StyledText {
                                text:               root.formatTime(modelData.time)
                                font.pixelSize:     Theme.fontSizeMedium
                                font.weight:        (isNext || isCurr) ? Font.Bold : Font.Normal
                                color:              isNext ? Theme.primary : (isCurr ? Theme.surfaceText : Theme.surfaceVariantText)
                                anchors.right:      parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                width:              root.prayerTimeWidth
                            }
                        }
                    }
                }
            }
        }

        // ── Quran section (optional) ─────────────────────────────────────────
        Column {
            width:   parent.width
            spacing: Theme.spacingS
            visible: root.showQuranInDash

            // Section header + toggle
            Item {
                width:  parent.width
                height: root.headerHeight

                StyledText {
                    anchors.left:           parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text:            "Quran Recitations"
                    font.pixelSize:  Theme.fontSizeMedium
                    font.weight:     Font.Bold
                    color:           Theme.surfaceText
                }

                Rectangle {
                    anchors.right:          parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.compactControlSize; height: root.compactControlSize; radius: width / 2
                    color: quranToggleMA.containsMouse
                           ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
                           : Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.06)
                    DIcon {
                        name:            root.showQuranPanel ? "expand_less" : "expand_more"
                        size:            Theme.iconSize
                        color:           Theme.surfaceVariantText
                        anchors.centerIn: parent
                    }
                    MouseArea {
                        id: quranToggleMA
                        anchors.fill:  parent
                        hoverEnabled:  true
                        cursorShape:   Qt.PointingHandCursor
                        onClicked:     root.showQuranPanel = !root.showQuranPanel
                    }
                }
            }

            // Collapsible Quran panel
            Column {
                width:   parent.width
                spacing: Theme.spacingS
                visible: root.showQuranPanel

                // Reciter picker row
                Card {
                    width:  parent.width
                    height: root.reciterCardHeight

                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        spacing: Theme.spacingXS

                        Item {
                            width: parent.width
                            height: root.reciterRefreshSize

                            StyledText {
                                text: root.reciters.length > 0
                                        ? "Selected · " + root.reciters[root.selectedReciter].name
                                          + " — " + root.reciters[root.selectedReciter].moshaf_name
                                        : (root.fetchingReciters ? "Loading reciters…"
                                           : root.reciterStatus || "No reciter list loaded")
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                                elide: Text.ElideRight
                                anchors.left: parent.left
                                anchors.right: reciterRefresh.left
                                anchors.rightMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Rectangle {
                                id: reciterRefresh
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: root.reciterRefreshSize
                                height: root.reciterRefreshSize
                                radius: width / 2
                                color: reciterRefreshMouse.containsMouse
                                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
                                        : Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.06)
                                DIcon {
                                    name: "refresh"
                                    size: Theme.iconSizeSmall + Theme.spacingXS
                                    color: Theme.surfaceVariantText
                                    anchors.centerIn: parent
                                }
                                MouseArea {
                                    id: reciterRefreshMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.doFetchReciters()
                                }
                            }
                        }

                        DTextField {
                            id: reciterSearchField
                            width: parent.width
                            height: root.standardRowHeight
                            placeholderText: root.reciters.length > 0
                                    ? "Search reciters or riwayah…"
                                    : "Reciter list is not available"
                            enabled: root.reciters.length > 0
                            text: root.reciterSearch
                            onTextChanged: root.reciterSearch = text
                        }

                        StyledText {
                            visible: root.reciterSearch.trim() !== "" && root.filteredReciters().length === 0
                            text: "No matching reciters"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            width: parent.width
                        }
                    }
                }

                Card {
                    width: parent.width
                    height: root.reciterResultsHeight
                    visible: root.reciterSearch.trim() !== "" && root.filteredReciters().length > 0

                    DListView {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingXS
                        clip: true
                        model: root.filteredReciters()

                        delegate: Item {
                            width: ListView.view.width
                            height: root.quranRowHeight
                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.cornerRadius
                                color: reciterResultMouse.containsMouse
                                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                                        : "transparent"
                            }
                            Column {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Theme.spacingS
                                anchors.rightMargin: Theme.spacingS
                                spacing: Theme.spacingXXS
                                StyledText {
                                    text: modelData.reciter.name
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                                StyledText {
                                    text: modelData.reciter.moshaf_name
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                            }
                            MouseArea {
                                id: reciterResultMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.selectedReciter = modelData.index
                                    root.reciterSearch = ""
                                }
                            }
                        }
                    }
                }

                // Surah list (scrollable)
                Card {
                    width:  parent.width
                    height: root.surahCardHeight

                    DListView {
                        anchors.fill:    parent
                        anchors.margins: Theme.spacingXS
                        clip:            true
                        model:           114

                        delegate: Item {
                            width:  ListView.view.width
                            height: root.standardRowHeight

                            readonly property int  surahNum: index + 1
                            readonly property bool playing:  root.playingSurah === surahNum

                            Rectangle {
                                anchors.fill:  parent
                                radius:        Theme.cornerRadiusS
                                color:         playing
                                               ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
                                               : rowMA.containsMouse
                                               ? Qt.rgba(Theme.surfaceText.r, Theme.surfaceText.g, Theme.surfaceText.b, 0.07)
                                               : "transparent"
                            }

                            Row {
                                anchors.fill:          parent
                                anchors.leftMargin:    Theme.spacingS
                                anchors.rightMargin:   Theme.spacingS
                                spacing:               Theme.spacingS

                                StyledText {
                                    width:           root.surahNumberWidth
                                    anchors.verticalCenter: parent.verticalCenter
                                    text:            surahNum
                                    font.pixelSize:  Theme.fontSizeSmall
                                    color:           Theme.surfaceVariantText
                                }
                                StyledText {
                                    width:           parent.width - root.surahTextInset
                                    anchors.verticalCenter: parent.verticalCenter
                                    text:            root.surahNames[index]
                                    font.pixelSize:  Theme.fontSizeMedium
                                    elide:           Text.ElideRight
                                    color:           playing ? Theme.primary : Theme.surfaceText
                                }
                                DIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name:  playing ? "stop" : "play_arrow"
                                    size:  Theme.iconSizeSmall + Theme.spacingXS
                                    color: playing ? Theme.primary : Theme.surfaceVariantText
                                }
                            }

                            MouseArea {
                                id: rowMA
                                anchors.fill:  parent
                                hoverEnabled:  true
                                cursorShape:   Qt.PointingHandCursor
                                onClicked:     playing ? root.stopQuran() : root.playSurah(root.selectedReciter, surahNum)
                            }
                        }
                    }
                }
            }
        }

        // Bottom padding
        Item { width: 1; height: Theme.spacingM }
    }
}
