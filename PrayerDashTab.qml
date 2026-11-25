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
    // Dashboard options explicitly saved from the dashboard editor win;
    // otherwise fall back to the global plugin settings.
    readonly property var storedDashOptions: DashRegistry.storedOptions(entryId)
    readonly property bool use12H: storedDashOptions.use12H !== undefined
                                   ? (options.use12H ?? false)
                                   : (pluginData.use12H ?? false)
    readonly property bool showQuranInDash: storedDashOptions.showQuranInDash !== undefined
                                            ? (options.showQuranInDash ?? true)
                                            : (pluginData.showQuranInDash ?? true)
    readonly property bool showImsak: pluginData.showImsak ?? true
    readonly property bool showSunrise: pluginData.showSunrise ?? true
    readonly property string calcMethod: pluginData.calcMethod ?? "egypt"
    readonly property string asrMethod: pluginData.asrMethod ?? "standard"
    readonly property int hijriOffset: {
        const value = Number(pluginData.hijriOffset)
        return Number.isFinite(value) ? Math.round(value) : 0
    }

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
    readonly property bool statusIsError: {
        const msg = root.statusMessage
        return msg.indexOf("Could not") === 0
                || msg.indexOf("Update failed") === 0
                || msg.indexOf("Set your") === 0
                || msg.indexOf("Add a valid") !== -1
    }
    readonly property color statusColor: root.statusIsError ? Theme.error : Theme.tertiary

    property string currName: ""
    property string nextName: ""
    property string nextTime: ""
    property string prevTime: ""
    property int    nextTimeSec:    0
    property int    nextTotalSecs:  0
    property real   periodProgress: 0
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
    readonly property int quranRowHeight: 48
    readonly property int reciterResultsHeight: 192
    readonly property int surahCardHeight: 360

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
        args.push("--method", root.calcMethod)
        args.push("--asr", root.asrMethod)
        args.push("--hijri-offset", String(root.hijriOffset))
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
    function formatGregorian(value) {
        if (!value) return ""
        let text = String(value)
        if (text.indexOf("T") === -1 && text.length === 10)
            text += "T12:00:00"
        const d = new Date(text)
        if (isNaN(d.getTime())) return String(value)
        return d.toLocaleDateString(Qt.locale(), Locale.LongFormat)
    }

    function formatCountdown(secs) {
        if (secs <= 0) return "0 min"
        const h = Math.floor(secs / 3600), m = Math.floor((secs % 3600) / 60)
        const mm = (m < 10 ? "0" : "") + m
        return h > 0 ? (h < 10 ? "0" : "") + h + ":" + mm : m + " min"
    }
    function determinePeriod(now, fajr, dhuhr, asr, maghrib, isha) {
        if (now < fajr)    return { currName:"Isha",    prevTime:isha,    nextName:"Fajr",    nextTime:fajr    }
        if (now < dhuhr)   return { currName:"Fajr",    prevTime:fajr,    nextName:"Dhuhr",   nextTime:dhuhr   }
        if (now < asr)     return { currName:"Dhuhr",   prevTime:dhuhr,   nextName:"Asr",     nextTime:asr     }
        if (now < maghrib) return { currName:"Asr",     prevTime:asr,     nextName:"Maghrib", nextTime:maghrib }
        if (now < isha)    return { currName:"Maghrib", prevTime:maghrib, nextName:"Isha",    nextTime:isha    }
        return             { currName:"Isha",    prevTime:isha,    nextName:"Fajr",    nextTime:fajr    }
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
        const rawGreg = data.date.readable || ""
        root.dateGreg = root.formatGregorian(rawGreg)
        root.dateHijr = data.date.hijri || ""
        root.hasPrayerData = true
        if (!root.fetching) {
            const locationConfigured = pluginData.autoLocation === true || root.hasManualLocation()
            const today = Qt.formatDate(clock.date, "yyyy-MM-dd")
            if (!locationConfigured) {
                root.statusMessage = rawGreg !== today
                        ? "Showing saved times from " + root.dateGreg + ". Set a valid location to calculate today's schedule."
                        : "Showing saved times. Add a valid location to refresh them."
            } else {
                root.statusMessage = rawGreg !== today
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
        root.prevTime = period.prevTime
        root.nextName = period.nextName
        root.nextTime = period.nextTime
        return true
    }

    function updateProgress() {
        if (!root.hasPrayerData || root.prevTime === "" || root.nextTimeSec <= 0) {
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
        root.updateProgress()
    }
    function getPrayerIcon(name) {
        const m = { Fajr:"bedtime", Dhuhr:"wb_sunny", Asr:"light_mode", Maghrib:"wb_twilight", Isha:"bedtime" }
        return m[name] || "mosque"
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
    function timelineItems() {
        return [
            { label: "Fajr", time: root.fajr, icon: "bedtime" },
            { label: "Dhuhr", time: root.dhuhr, icon: "wb_sunny" },
            { label: "Asr", time: root.asr, icon: "light_mode" },
            { label: "Maghrib", time: root.maghrib, icon: "wb_twilight" },
            { label: "Isha", time: root.isha, icon: "bedtime" }
        ]
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
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Theme.spacingL
        anchors.leftMargin: Theme.spacingL
        anchors.rightMargin: Theme.spacingL
        spacing: Theme.spacingL

        // ── Header ───────────────────────────────────────────────────────────
        RowLayout {
            width: parent.width
            spacing: Theme.spacingM

            Rectangle {
                Layout.preferredWidth: 46
                Layout.preferredHeight: 46
                radius: 23
                color: Theme.withAlpha(Theme.primary, 0.14)

                DIcon {
                    anchors.centerIn: parent
                    name: root.nextName !== "" ? root.getPrayerIcon(root.nextName) : "mosque"
                    size: Theme.iconSizeLarge
                    color: root.isUrgent ? Theme.error : Theme.primary
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: "Prayer Times"
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Theme.fontWeightBold
                    color: Theme.surfaceText
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.dateGreg !== ""
                          ? root.dateGreg + (root.dateHijr !== "" ? " · " + root.dateHijr : "")
                          : (root.fetching ? "Calculating today's schedule…" : "Your daily prayer schedule")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                }
            }

            DRefreshButton {
                busy: root.fetching
                tooltipText: "Refresh prayer times"
                onClicked: root.fetchPrayerTimes()
            }
        }

        // ── Status banner ────────────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: statusRow.implicitHeight + Theme.spacingS * 2
            radius: Theme.cornerRadiusM
            visible: root.statusMessage !== ""
            color: Theme.withAlpha(root.statusColor, 0.09)
            border.width: Theme.outlineWidth
            border.color: Theme.withAlpha(root.statusColor, 0.24)

            RowLayout {
                id: statusRow
                anchors.fill: parent
                anchors.margins: Theme.spacingS
                spacing: Theme.spacingS

                DIcon {
                    Layout.preferredWidth: Theme.iconSizeSmall
                    Layout.preferredHeight: Theme.iconSizeSmall
                    name: root.statusIsError ? "error" : "info"
                    size: Theme.iconSizeSmall
                    color: root.statusColor
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.statusMessage
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    wrapMode: Text.WordWrap
                }
            }
        }

        // ── Countdown hero ───────────────────────────────────────────────────
        Card {
            id: heroCard
            width: parent.width
            height: heroRow.implicitHeight + heroCard.pad * 2
            pad: Theme.spacingL
            tone: "primary"

            RowLayout {
                id: heroRow
                width: parent.width
                spacing: Theme.spacingL

                DRingGauge {
                    Layout.preferredWidth: 116
                    Layout.preferredHeight: 116
                    value: root.hasPrayerData ? root.periodProgress : 0
                    strokeWidth: Theme.spacingXS
                    startAngle: -90
                    ringColor: root.isUrgent ? Theme.error : heroCard.accentColor
                    trackColor: Theme.withAlpha(heroCard.contentColor, 0.16)

                    Column {
                        anchors.centerIn: parent
                        spacing: 0

                        NumericText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.hasPrayerData
                                  ? root.formatCountdown(root.nextTotalSecs) : "—"
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Theme.fontWeightBold
                            color: root.isUrgent ? Theme.error : heroCard.contentColor
                        }

                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.hasPrayerData ? "remaining" : ""
                            font.pixelSize: Theme.fontSizeXSmall
                            color: heroCard.mutedColor
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingXS

                    RowLayout {
                        spacing: Theme.spacingS

                        DIcon {
                            Layout.preferredWidth: Theme.iconSizeSmall
                            Layout.preferredHeight: Theme.iconSizeSmall
                            name: root.nextName !== "" ? root.getPrayerIcon(root.nextName) : "mosque"
                            size: Theme.iconSizeSmall
                            color: root.isUrgent ? Theme.error : heroCard.accentColor
                        }

                        StyledText {
                            text: root.nextName !== "" ? "NEXT PRAYER" : "PRAYER SCHEDULE"
                            font.pixelSize: Theme.fontSizeXSmall
                            font.weight: Theme.fontWeightBold
                            font.letterSpacing: 1
                            color: heroCard.mutedColor
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.nextName !== ""
                              ? root.nextName
                              : (root.fetching ? "Loading…" : "Set your location")
                        font.pixelSize: Theme.fontSizeXXLarge
                        font.weight: Theme.fontWeightBold
                        color: root.isUrgent ? Theme.error : heroCard.contentColor
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.nextName !== ""
                              ? "at " + root.formatTime(root.nextTime)
                                + (root.currName !== "" ? "  ·  current: " + root.currName : "")
                              : "Enable auto-location or add coordinates in settings"
                        font.pixelSize: Theme.fontSizeSmall
                        color: heroCard.mutedColor
                        wrapMode: Text.WordWrap
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 4
                        Layout.topMargin: Theme.spacingXXS
                        visible: root.hasPrayerData
                        radius: 2
                        color: Theme.withAlpha(heroCard.contentColor, 0.16)

                        Rectangle {
                            width: parent.width * root.periodProgress
                            height: parent.height
                            radius: parent.radius
                            color: root.isUrgent ? Theme.error : heroCard.accentColor
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.hasPrayerData
                        text: Math.round(root.periodProgress * 100) + "% of this prayer period"
                        font.pixelSize: Theme.fontSizeXSmall
                        color: heroCard.mutedColor
                    }
                }
            }
        }

        // ── Prayer timeline ──────────────────────────────────────────────────
        Card {
            id: timelineCard
            width: parent.width
            height: timelineContent.implicitHeight + timelineCard.pad * 2
            pad: Theme.spacingM
            visible: root.hasPrayerData

            ColumnLayout {
                id: timelineContent
                width: parent.width
                spacing: Theme.spacingS

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        Layout.fillWidth: true
                        text: "Prayer flow"
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.fontWeightBold
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        text: root.nextName !== "" ? "Up next · " + root.nextName : ""
                        font.pixelSize: Theme.fontSizeXSmall
                        color: Theme.surfaceVariantText
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 84

                    Rectangle {
                        x: parent.width * 0.1
                        y: 17
                        width: parent.width * 0.8
                        height: 2
                        radius: 1
                        color: Theme.withAlpha(Theme.primary, 0.2)
                    }

                    RowLayout {
                        anchors.fill: parent
                        spacing: 0

                        Repeater {
                            model: root.timelineItems()

                            delegate: ColumnLayout {
                                id: timelineNode
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                spacing: Theme.spacingXXS

                                readonly property bool isNext: modelData.label === root.nextName
                                readonly property bool isCurr: modelData.label === root.currName

                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter
                                    width: 36
                                    height: 36
                                    radius: 18
                                    color: timelineNode.isNext
                                           ? Theme.primary
                                           : timelineNode.isCurr
                                             ? Theme.withAlpha(Theme.surfaceText, 0.12)
                                             : Theme.withAlpha(Theme.surfaceText, 0.06)
                                    border.width: timelineNode.isNext ? 2 : 0
                                    border.color: Theme.primary

                                    DIcon {
                                        anchors.centerIn: parent
                                        name: modelData.icon
                                        size: Theme.iconSizeSmall
                                        color: timelineNode.isNext
                                               ? Theme.onPrimary
                                               : timelineNode.isCurr
                                                 ? Theme.surfaceText
                                                 : Theme.surfaceVariantText
                                    }
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: modelData.label
                                    font.pixelSize: Theme.fontSizeXSmall
                                    font.weight: timelineNode.isNext ? Theme.fontWeightBold : Font.Normal
                                    color: timelineNode.isNext
                                           ? Theme.primary
                                           : timelineNode.isCurr
                                             ? Theme.surfaceText
                                             : Theme.surfaceVariantText
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.formatTime(modelData.time)
                                    font.pixelSize: Theme.fontSizeXSmall
                                    color: timelineNode.isNext ? Theme.primary : Theme.surfaceVariantText
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Empty state ──────────────────────────────────────────────────────
        Card {
            id: emptyCard
            width: parent.width
            height: emptyContent.implicitHeight + emptyCard.pad * 2
            pad: Theme.spacingL
            visible: !root.hasPrayerData

            RowLayout {
                id: emptyContent
                width: parent.width
                spacing: Theme.spacingM

                DIcon {
                    Layout.preferredWidth: Theme.iconSizeLarge
                    Layout.preferredHeight: Theme.iconSizeLarge
                    name: "location_off"
                    size: Theme.iconSizeLarge
                    color: Theme.surfaceVariantText
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingXXS

                    StyledText {
                        Layout.fillWidth: true
                        text: root.fetching ? "Calculating prayer times…" : "Prayer times aren't set up yet"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightBold
                        color: Theme.surfaceText
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "Open Settings → Plugins → Prayer Times Enhanced and add your coordinates, or enable Auto Detect Location."
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        // ── Prayer schedule ──────────────────────────────────────────────────
        Card {
            id: scheduleCard
            width: parent.width
            height: scheduleContent.implicitHeight + scheduleCard.pad * 2
            pad: Theme.spacingM
            visible: root.hasPrayerData

            ColumnLayout {
                id: scheduleContent
                width: parent.width
                spacing: Theme.spacingS

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        Layout.fillWidth: true
                        text: "Today's schedule"
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.fontWeightBold
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        text: root.nextName !== "" ? "Next · " + root.nextName : ""
                        font.pixelSize: Theme.fontSizeXSmall
                        color: Theme.surfaceVariantText
                    }
                }

                GridLayout {
                    id: prayerGrid
                    Layout.fillWidth: true
                    columns: width >= Theme.smallBreakpoint ? 2 : 1
                    columnSpacing: Theme.spacingS
                    rowSpacing: Theme.spacingXS

                    Repeater {
                        model: root.scheduleItems()

                        delegate: Rectangle {
                            id: prayerRow
                            Layout.fillWidth: true
                            Layout.preferredWidth: (prayerGrid.width - prayerGrid.columnSpacing * (prayerGrid.columns - 1)) / prayerGrid.columns
                            Layout.preferredHeight: 48
                            radius: Theme.cornerRadiusM

                            readonly property bool isNext: modelData.label === root.nextName
                            readonly property bool isCurr: modelData.label === root.currName

                            color: isNext ? Theme.withAlpha(Theme.primary, 0.12)
                                          : isCurr ? Theme.withAlpha(Theme.surfaceText, 0.05)
                                          : "transparent"
                            border.width: isNext ? 1 : 0
                            border.color: isNext ? Theme.withAlpha(Theme.primary, 0.5) : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingS
                                anchors.rightMargin: Theme.spacingM
                                spacing: Theme.spacingS

                                Rectangle {
                                    Layout.preferredWidth: 30
                                    Layout.preferredHeight: 30
                                    radius: Theme.cornerRadiusS
                                    color: prayerRow.isNext
                                           ? Theme.withAlpha(Theme.primary, 0.2)
                                           : Theme.withAlpha(Theme.surfaceText, 0.06)

                                    DIcon {
                                        anchors.centerIn: parent
                                        name: modelData.icon
                                        size: Theme.iconSizeSmall
                                        color: prayerRow.isNext ? Theme.primary
                                               : (prayerRow.isCurr ? Theme.surfaceText : Theme.surfaceVariantText)
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.label
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: (prayerRow.isNext || prayerRow.isCurr)
                                                     ? Theme.fontWeightBold : Theme.fontWeight
                                        color: prayerRow.isNext ? Theme.primary
                                               : (prayerRow.isCurr ? Theme.surfaceText : Theme.surfaceVariantText)
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        visible: prayerRow.isNext || prayerRow.isCurr
                                        text: prayerRow.isNext ? "Next" : "Now"
                                        font.pixelSize: Theme.fontSizeXSmall
                                        color: prayerRow.isNext ? Theme.primary : Theme.surfaceVariantText
                                    }
                                }

                                StyledText {
                                    text: root.formatTime(modelData.time)
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: (prayerRow.isNext || prayerRow.isCurr)
                                                 ? Theme.fontWeightBold : Theme.fontWeightMedium
                                    color: prayerRow.isNext ? Theme.primary
                                           : (prayerRow.isCurr ? Theme.surfaceText : Theme.surfaceVariantText)
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Quran section ────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: Theme.spacingM
            visible: root.showQuranInDash

            RowLayout {
                width: parent.width

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: "Quran Recitations"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightBold
                        color: Theme.surfaceText
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.reciters.length > 0
                              ? "114 surahs · " + root.reciters.length + " reciters"
                              : "Stream beautiful recitations"
                        font.pixelSize: Theme.fontSizeXSmall
                        color: Theme.surfaceVariantText
                    }
                }

                DButton {
                    text: root.showQuranPanel ? "Hide" : "Browse"
                    iconName: root.showQuranPanel ? "expand_less" : "expand_more"
                    variant: "tonal"
                    buttonHeight: Theme.buttonHeightXS
                    onClicked: root.showQuranPanel = !root.showQuranPanel
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM
                visible: root.showQuranPanel

                // Reciter picker
                Card {
                    id: reciterCard
                    width: parent.width
                    height: reciterContent.implicitHeight + reciterCard.pad * 2
                    pad: Theme.spacingM

                    ColumnLayout {
                        id: reciterContent
                        width: parent.width
                        spacing: Theme.spacingS

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingM

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.reciters.length > 0
                                          ? root.reciters[root.selectedReciter].name
                                          : (root.fetchingReciters ? "Loading reciters…" : "Reciter")
                                    font.pixelSize: Theme.fontSizeMedium
                                    font.weight: Theme.fontWeightMedium
                                    color: Theme.surfaceText
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.reciters.length > 0
                                          ? root.reciters[root.selectedReciter].moshaf_name
                                          : (root.reciterStatus || "Refresh to load the reciter list")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    elide: Text.ElideRight
                                }
                            }

                            DRefreshButton {
                                busy: root.fetchingReciters
                                tooltipText: "Refresh reciters"
                                onClicked: root.doFetchReciters()
                            }
                        }

                        DSearchField {
                            id: reciterSearchField
                            Layout.fillWidth: true
                            placeholderText: root.reciters.length > 0
                                             ? "Search reciters or riwayah…"
                                             : "Reciter list is not available"
                            enabled: root.reciters.length > 0
                            text: root.reciterSearch
                            onTextEdited: root.reciterSearch = text
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: root.reciterSearch.trim() !== ""
                                     && root.filteredReciters().length === 0
                            text: "No matching reciters"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }
                }

                // Reciter search results
                Card {
                    width: parent.width
                    height: root.reciterResultsHeight
                    visible: root.reciterSearch.trim() !== ""
                             && root.filteredReciters().length > 0

                    DListView {
                        anchors.fill: parent
                        clip: true
                        model: root.filteredReciters()
                        spacing: Theme.spacingXXS

                        delegate: Item {
                            width: ListView.view.width
                            height: root.quranRowHeight

                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.cornerRadiusS
                                color: reciterResultMouse.containsMouse
                                       ? Theme.withAlpha(Theme.primary, 0.1)
                                       : "transparent"
                            }

                            ColumnLayout {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Theme.spacingS
                                anchors.rightMargin: Theme.spacingS
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.reciter.name
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Theme.fontWeightMedium
                                    color: Theme.surfaceText
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.reciter.moshaf_name
                                    font.pixelSize: Theme.fontSizeXSmall
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
                                    root.selectedReciter = modelData.index
                                    root.reciterSearch = ""
                                }
                            }
                        }
                    }
                }

                // Surah browser
                Card {
                    id: surahCard
                    width: parent.width
                    height: root.surahCardHeight
                    pad: Theme.spacingM

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: Theme.spacingS

                        RowLayout {
                            Layout.fillWidth: true

                            StyledText {
                                Layout.fillWidth: true
                                text: root.playingSurah > 0
                                      ? "Playing · " + root.surahNames[root.playingSurah - 1]
                                      : "114 Surahs"
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Theme.fontWeightBold
                                color: root.playingSurah > 0 ? Theme.primary : Theme.surfaceVariantText
                                elide: Text.ElideRight
                            }

                            DButton {
                                visible: root.playingSurah > 0
                                text: "Stop"
                                iconName: "stop"
                                variant: "tonal"
                                buttonHeight: Theme.buttonHeightXS
                                onClicked: root.stopQuran()
                            }
                        }

                        DListView {
                            id: surahList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: 114
                            spacing: Theme.spacingXXS

                            delegate: Item {
                                width: ListView.view.width
                                height: 44

                                readonly property int surahNum: index + 1
                                readonly property bool playing: root.playingSurah === surahNum

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.cornerRadiusS
                                    color: playing
                                           ? Theme.withAlpha(Theme.primary, 0.14)
                                           : surahRowMouse.containsMouse
                                             ? Theme.withAlpha(Theme.surfaceText, 0.06)
                                             : "transparent"
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.spacingS
                                    anchors.rightMargin: Theme.spacingS
                                    spacing: Theme.spacingS

                                    Rectangle {
                                        Layout.preferredWidth: 28
                                        Layout.preferredHeight: 28
                                        radius: 14
                                        color: playing
                                               ? Theme.withAlpha(Theme.primary, 0.2)
                                               : Theme.withAlpha(Theme.surfaceText, 0.06)

                                        StyledText {
                                            anchors.centerIn: parent
                                            text: surahNum
                                            font.pixelSize: Theme.fontSizeXSmall
                                            font.weight: Theme.fontWeightMedium
                                            color: playing ? Theme.primary : Theme.surfaceVariantText
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.surahNames[index]
                                        font.pixelSize: Theme.fontSizeMedium
                                        elide: Text.ElideRight
                                        color: playing ? Theme.primary : Theme.surfaceText
                                    }

                                    DIcon {
                                        Layout.preferredWidth: Theme.iconSizeSmall
                                        Layout.preferredHeight: Theme.iconSizeSmall
                                        name: playing ? "stop_circle" : "play_circle"
                                        size: Theme.iconSizeSmall
                                        color: playing ? Theme.primary : Theme.surfaceVariantText
                                    }
                                }

                                MouseArea {
                                    id: surahRowMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: playing ? root.stopQuran()
                                                       : root.playSurah(root.selectedReciter, surahNum)
                                }
                            }
                        }
                    }
                }
            }
        }

        Item { width: 1; height: Theme.spacingM }
    }
}
