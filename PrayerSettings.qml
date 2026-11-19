import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "prayerTimesEnhanced"

    StyledText {
        width: parent.width
        text: "Prayer Times Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    // ── Display Settings ──
    StyledRect {
        width: parent.width
        height: displayColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: displayColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Display"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            ToggleSetting {
                settingKey: "iconOnly"
                label: "Icon Only Mode"
                description: "Show only the prayer icon in the bar."
                defaultValue: false
            }

            ToggleSetting {
                settingKey: "showSeconds"
                label: "Show Seconds in Countdown"
                description: "Show seconds in the countdown timer."
                defaultValue: false
            }
        }
    }

    // ── Location Settings ──
    StyledRect {
        width: parent.width
        height: locationColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: locationColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Location & Timezone"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            ToggleSetting {
                id: autoLocToggle
                settingKey: "autoLocation"
                label: "Auto Detect Location"
                description: "Resolve your coordinates automatically via IP-based geolocation (needs internet). Leave this off to enter your own coordinates manually below."
                defaultValue: false
            }

            StyledText {
                visible: autoLocToggle.value
                text: "Manual latitude/longitude/UTC-offset fields are hidden while Auto Detect Location is on."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
            }

            // Manual Location Inputs (visible whenever Auto Location is NOT explicitly enabled)
            Column {
                width: parent.width
                spacing: Theme.spacingM
                visible: !autoLocToggle.value

                StyledText {
                    text: "Enter your own coordinates — nothing is pre-filled."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    width: parent.width
                }

                StringSetting {
                    settingKey: "latitude"
                    label: "Latitude"
                    description: "Decimal degrees from -90 to 90, e.g. 51.5074 or -33.8688. Positive = North, negative = South."
                    defaultValue: ""
                }

                StringSetting {
                    settingKey: "longitude"
                    label: "Longitude"
                    description: "Decimal degrees from -180 to 180, e.g. -0.1278 or 151.2093. Positive = East, negative = West."
                    defaultValue: ""
                }

                StringSetting {
                    settingKey: "timeZoneOffset"
                    label: "UTC Offset (Hours)"
                    description: "UTC offset in hours (including optional fractions), from -14 to +14; e.g. 3 or -5.5."
                    defaultValue: ""
                }
            }
        }
    }

    // ── Notifications Settings ──
    StyledRect {
        width: parent.width
        height: notifyColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: notifyColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Notifications"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            StringSetting {
                settingKey: "notifyMinutes"
                label: "Reminder (minutes before prayer)"
                description: "How many minutes before prayer to send a notification (0–1440)."
                defaultValue: "15"
            }
        }
    }

    // ── Athan Settings ──
    StyledRect {
        width: parent.width
        height: athanColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: athanColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Athan (Call to Prayer)"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            ToggleSetting {
                settingKey: "playAthanSound"
                label: "Play Athan Sound"
                description: "Play an audio file the moment each prayer time starts."
                defaultValue: false
            }

            StringSetting {
                settingKey: "athanSoundPath"
                label: "Athan Sound (file path or URL)"
                description: "A local .mp3/.ogg/.wav path, a direct http(s) link to stream, or a filename inside this plugin's assets/ folder (e.g. assets/athan.mp3)."
                defaultValue: ""
            }
        }
    }

    // ── Quran Settings ──
    StyledRect {
        width: parent.width
        height: quranColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: quranColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Quran Recitations"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            ToggleSetting {
                settingKey: "quranEnabled"
                label: "Show Quran Tab in Popout"
                description: "Adds a Quran tab to the widget popout to browse reciters and play any surah."
                defaultValue: true
            }
        }
    }
}
