import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "prayerTimesEnhanced"

    // Resolved at runtime so the "test sound" action works on any install path.
    readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "")

    property string testStatus: ""
    property bool resetArmed: false

    function resolveAthanPath(path) {
        if (path === "") return path
        if (path.startsWith("http://") || path.startsWith("https://") || path.startsWith("/"))
            return path
        return root.pluginDir + path
    }

    function testAthanSound() {
        const path = String(root.loadValue("athanSoundPath", "") || "").trim()
        if (path === "") {
            root.testStatus = "Add an Athan sound first."
            return
        }
        root.testStatus = "Playing…"
        testPlayer.command = ["sh", "-c",
            "if command -v mpv >/dev/null 2>&1; then exec mpv --no-video --really-quiet -- \"$0\"; " +
            "elif command -v ffplay >/dev/null 2>&1; then exec ffplay -nodisp -autoexit -loglevel quiet -- \"$0\"; " +
            "elif command -v cvlc >/dev/null 2>&1; then exec cvlc --play-and-exit -q -- \"$0\"; " +
            "else exit 127; fi",
            root.resolveAthanPath(path)]
        testPlayer.running = false
        testPlayer.running = true
    }

    function resetDefaults() {
        const defaults = {
            "use12H": false,
            "iconOnly": false,
            "showSeconds": false,
            "showImsak": true,
            "showSunrise": true,
            "autoLocation": false,
            "latitude": "",
            "longitude": "",
            "timeZoneOffset": "",
            "calcMethod": "egypt",
            "asrMethod": "standard",
            "hijriOffset": 0,
            "remindersEnabled": true,
            "notifyMinutes": 15,
            "playAthanSound": false,
            "athanSoundPath": "",
            "quranEnabled": true,
            "showQuranInDash": true
        }
        for (const key in defaults)
            root.saveValue(key, defaults[key])
        root.testStatus = "Settings restored to defaults."
    }

    Process {
        id: testPlayer
        running: false
        onExited: function(code) {
            if (code === 0)
                root.testStatus = "Test sound finished."
            else if (code === 127)
                root.testStatus = "No audio player found — install mpv, ffplay, or cvlc."
            else
                root.testStatus = "Couldn't play that sound. Check the path or URL."
        }
    }

    Timer {
        id: resetTimer
        interval: 5000
        onTriggered: root.resetArmed = false
    }

    component SectionHeader: RowLayout {
        id: header
        required property string title
        property string subtitle: ""
        property string iconName: "tune"

        width: parent ? parent.width : implicitWidth
        spacing: Theme.spacingM

        Rectangle {
            Layout.preferredWidth: 34
            Layout.preferredHeight: 34
            radius: Theme.cornerRadiusS
            color: Theme.withAlpha(Theme.primary, 0.12)

            DIcon {
                anchors.centerIn: parent
                name: header.iconName
                size: Theme.iconSizeSmall
                color: Theme.primary
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                text: header.title
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightBold
                color: Theme.surfaceText
            }

            StyledText {
                Layout.fillWidth: true
                visible: header.subtitle !== ""
                text: header.subtitle
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }
        }
    }

    component Divider: Rectangle {
        width: parent ? parent.width : 0
        height: 1
        color: Theme.withAlpha(Theme.surfaceText, 0.08)
    }

    // ── Intro ────────────────────────────────────────────────────────────────
    RowLayout {
        width: parent.width
        spacing: Theme.spacingM

        Rectangle {
            Layout.preferredWidth: 52
            Layout.preferredHeight: 52
            radius: Theme.cornerRadiusM
            color: Theme.withAlpha(Theme.primary, 0.14)

            DIcon {
                anchors.centerIn: parent
                name: "mosque"
                size: Theme.iconSizeLarge
                color: Theme.primary
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                text: "Prayer Times Enhanced"
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Theme.fontWeightBold
                color: Theme.surfaceText
            }

            StyledText {
                Layout.fillWidth: true
                text: "Daily prayer schedule, Athan reminders, and Quran recitations — calculated locally on your device."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }
        }
    }

    // ── Display ──────────────────────────────────────────────────────────────
    DCard {
        id: displayCard
        width: parent.width
        height: displayContent.implicitHeight + displayCard.pad * 2
        pad: Theme.spacingL

        Column {
            id: displayContent
            width: parent.width
            spacing: Theme.spacingM

            SectionHeader {
                title: "Display"
                subtitle: "Choose how prayer information appears in the bar, popout, and dashboard."
                iconName: "tune"
            }

            ToggleSetting {
                settingKey: "use12H"
                label: "12-Hour Clock"
                description: "Show times as 1:30 PM instead of 13:30 across the widget and dashboard."
                defaultValue: false
            }

            Divider {}

            ToggleSetting {
                settingKey: "iconOnly"
                label: "Icon Only Mode"
                description: "Show only the prayer icon in the bar to save space."
                defaultValue: false
            }

            ToggleSetting {
                settingKey: "showSeconds"
                label: "Show Seconds in Countdown"
                description: "Include a live seconds value in the bar countdown."
                defaultValue: false
            }

            Divider {}

            ToggleSetting {
                settingKey: "showImsak"
                label: "Show Imsak"
                description: "Display Imsak (10 minutes before Fajr) in the schedule."
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "showSunrise"
                label: "Show Sunrise"
                description: "Display Sunrise in the schedule."
                defaultValue: true
            }
        }
    }

    // ── Location ─────────────────────────────────────────────────────────────
    DCard {
        id: locationCard
        width: parent.width
        height: locationContent.implicitHeight + locationCard.pad * 2
        pad: Theme.spacingL

        Column {
            id: locationContent
            width: parent.width
            spacing: Theme.spacingM

            SectionHeader {
                title: "Location & Timezone"
                subtitle: "Prayer times are calculated offline from your coordinates."
                iconName: "location_on"
            }

            ToggleSetting {
                id: autoLocToggle
                settingKey: "autoLocation"
                label: "Auto Detect Location"
                description: "Resolve approximate coordinates via IP-based geolocation. Requires internet and reveals your public IP to ip-api.com."
                defaultValue: false
            }

            StyledText {
                width: parent.width
                visible: autoLocToggle.value
                text: "Manual coordinates are hidden while Auto Detect Location is on."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM
                visible: !autoLocToggle.value

                StyledText {
                    width: parent.width
                    text: "Enter your own coordinates. Nothing is pre-filled or shared."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }

                StringSetting {
                    settingKey: "latitude"
                    label: "Latitude"
                    placeholder: "e.g. 51.5074"
                    description: "Decimal degrees from -90 to 90. Positive = North, negative = South."
                    defaultValue: ""
                }

                StringSetting {
                    settingKey: "longitude"
                    label: "Longitude"
                    placeholder: "e.g. -0.1278"
                    description: "Decimal degrees from -180 to 180. Positive = East, negative = West."
                    defaultValue: ""
                }

                StringSetting {
                    settingKey: "timeZoneOffset"
                    label: "UTC Offset (Hours)"
                    placeholder: "e.g. 3 or -5.5"
                    description: "Offset from UTC in hours, from -14 to +14. Fractions such as -5.5 are supported."
                    defaultValue: ""
                }
            }
        }
    }

    // ── Calculation ──────────────────────────────────────────────────────────
    DCard {
        id: calculationCard
        width: parent.width
        height: calculationContent.implicitHeight + calculationCard.pad * 2
        pad: Theme.spacingL

        Column {
            id: calculationContent
            width: parent.width
            spacing: Theme.spacingM

            SectionHeader {
                title: "Calculation"
                subtitle: "Pick the convention used for Fajr, Isha, and Asr."
                iconName: "calculate"
            }

            SelectionSetting {
                settingKey: "calcMethod"
                label: "Calculation Method"
                description: "Different authorities use different twilight angles."
                defaultValue: "egypt"
                options: [
                    { label: "Egyptian General Authority", value: "egypt" },
                    { label: "Muslim World League", value: "mwl" },
                    { label: "Umm al-Qura (Makkah)", value: "makkah" },
                    { label: "University of Islamic Sciences, Karachi", value: "karachi" },
                    { label: "Islamic Society of North America (ISNA)", value: "isna" },
                    { label: "Institute of Geophysics, Tehran", value: "tehran" },
                    { label: "Shia Ithna-Ashari (Jafari)", value: "jafari" }
                ]
            }

            SelectionSetting {
                settingKey: "asrMethod"
                label: "Asr Calculation"
                description: "Standard (Shafi'i, Maliki, Hanbali) or Hanafi."
                defaultValue: "standard"
                options: [
                    { label: "Standard (Shafi'i, Maliki, Hanbali)", value: "standard" },
                    { label: "Hanafi", value: "hanafi" }
                ]
            }

            SliderSetting {
                settingKey: "hijriOffset"
                label: "Hijri Date Offset"
                description: "Shift the displayed Hijri date by up to two days to match your local moon sighting."
                defaultValue: 0
                minimum: -2
                maximum: 2
                unit: " days"
                leftIcon: "calendar_month"
            }
        }
    }

    // ── Notifications ────────────────────────────────────────────────────────
    DCard {
        id: notifyCard
        width: parent.width
        height: notifyContent.implicitHeight + notifyCard.pad * 2
        pad: Theme.spacingL

        Column {
            id: notifyContent
            width: parent.width
            spacing: Theme.spacingM

            SectionHeader {
                title: "Notifications"
                subtitle: "Get a desktop reminder before each prayer."
                iconName: "notifications_active"
            }

            ToggleSetting {
                settingKey: "remindersEnabled"
                label: "Prayer Reminders"
                description: "Send a notification when the reminder window opens and when the prayer begins."
                defaultValue: true
            }

            SliderSetting {
                settingKey: "notifyMinutes"
                label: "Reminder Lead Time"
                description: "How many minutes before prayer to send the reminder. Set to 0 to only notify at prayer time."
                defaultValue: 15
                minimum: 0
                maximum: 120
                unit: " min"
                leftIcon: "schedule"
            }
        }
    }

    // ── Athan ────────────────────────────────────────────────────────────────
    DCard {
        id: athanCard
        width: parent.width
        height: athanContent.implicitHeight + athanCard.pad * 2
        pad: Theme.spacingL

        Column {
            id: athanContent
            width: parent.width
            spacing: Theme.spacingM

            SectionHeader {
                title: "Athan (Call to Prayer)"
                subtitle: "Play an audio file the moment each prayer time starts."
                iconName: "volume_up"
            }

            ToggleSetting {
                settingKey: "playAthanSound"
                label: "Play Athan Sound"
                description: "Enable audio playback at the start of each prayer."
                defaultValue: false
            }

            StringSetting {
                settingKey: "athanSoundPath"
                label: "Athan Sound (file path or URL)"
                placeholder: "assets/athan.mp3"
                description: "A local .mp3/.ogg/.wav path, a direct http(s) link, or a filename inside this plugin's assets/ folder."
                defaultValue: ""
            }

            RowLayout {
                width: parent.width
                spacing: Theme.spacingM

                DButton {
                    text: "Test Sound"
                    iconName: "play_arrow"
                    variant: "tonal"
                    buttonHeight: Theme.buttonHeightXS
                    onClicked: root.testAthanSound()
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.testStatus
                    font.pixelSize: Theme.fontSizeSmall
                    color: root.testStatus.indexOf("Couldn't") === 0
                           || root.testStatus.indexOf("No audio") === 0
                           ? Theme.error : Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }

            StyledText {
                width: parent.width
                text: "Playback requires mpv, ffplay, or cvlc. Relative paths resolve from the plugin folder."
                font.pixelSize: Theme.fontSizeXSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }
        }
    }

    // ── Quran ────────────────────────────────────────────────────────────────
    DCard {
        id: quranCard
        width: parent.width
        height: quranContent.implicitHeight + quranCard.pad * 2
        pad: Theme.spacingL

        Column {
            id: quranContent
            width: parent.width
            spacing: Theme.spacingM

            SectionHeader {
                title: "Quran Recitations"
                subtitle: "Browse reciters and stream any surah from the popout or dashboard."
                iconName: "menu_book"
            }

            ToggleSetting {
                settingKey: "quranEnabled"
                label: "Show Quran Tab in Popout"
                description: "Adds a Quran tab to the widget popout to browse reciters and play any surah."
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "showQuranInDash"
                label: "Show Quran Section in Dashboard"
                description: "Show the reciter browser and surah list in the Prayer Times dashboard tab."
                defaultValue: true
            }

            StyledText {
                width: parent.width
                text: "Reciter metadata and audio are provided by mp3quran.net."
                font.pixelSize: Theme.fontSizeXSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }
        }
    }

    // ── Reset ────────────────────────────────────────────────────────────────
    DCard {
        id: resetCard
        width: parent.width
        height: resetContent.implicitHeight + resetCard.pad * 2
        pad: Theme.spacingL

        Column {
            id: resetContent
            width: parent.width
            spacing: Theme.spacingM

            SectionHeader {
                title: "Reset"
                subtitle: "Restore every setting on this page to its default value."
                iconName: "restart_alt"
            }

            DButton {
                text: root.resetArmed ? "Tap again to confirm reset" : "Restore Defaults"
                iconName: "restore"
                variant: root.resetArmed ? "filled" : "outlined"
                danger: root.resetArmed
                buttonHeight: Theme.buttonHeightXS
                onClicked: {
                    if (!root.resetArmed) {
                        root.resetArmed = true
                        resetTimer.restart()
                        return
                    }
                    root.resetArmed = false
                    root.resetDefaults()
                }
            }
        }
    }
}
