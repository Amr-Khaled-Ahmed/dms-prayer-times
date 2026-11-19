import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "prayerTimesEnhanced"

    RowLayout {
        width: parent.width
        spacing: Theme.spacingM

        Rectangle {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
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
                text: "Daily prayer schedule, Athan reminders, and Quran recitations."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }
        }
    }

    DCard {
        id: displayCard
        width: parent.width
        height: displayContent.implicitHeight + displayCard.pad * 2
        pad: Theme.spacingL

        Column {
            id: displayContent
            width: parent.width
            spacing: Theme.spacingM

            RowLayout {
                width: parent.width
                spacing: Theme.spacingM

                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: Theme.cornerRadiusS
                    color: Theme.withAlpha(Theme.primary, 0.12)

                    DIcon {
                        anchors.centerIn: parent
                        name: "tune"
                        size: Theme.iconSizeSmall
                        color: Theme.primary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: "Display"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightBold
                        color: Theme.surfaceText
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "Control how the bar widget presents prayer information."
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                    }
                }
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

    DCard {
        id: locationCard
        width: parent.width
        height: locationContent.implicitHeight + locationCard.pad * 2
        pad: Theme.spacingL

        Column {
            id: locationContent
            width: parent.width
            spacing: Theme.spacingM

            RowLayout {
                width: parent.width
                spacing: Theme.spacingM

                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: Theme.cornerRadiusS
                    color: Theme.withAlpha(Theme.primary, 0.12)

                    DIcon {
                        anchors.centerIn: parent
                        name: "location_on"
                        size: Theme.iconSizeSmall
                        color: Theme.primary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: "Location & Timezone"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightBold
                        color: Theme.surfaceText
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "Use automatic geolocation or provide exact coordinates manually."
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                    }
                }
            }

            ToggleSetting {
                id: autoLocToggle
                settingKey: "autoLocation"
                label: "Auto Detect Location"
                description: "Resolve your coordinates automatically via IP-based geolocation (needs internet). Leave this off to enter your own coordinates manually below."
                defaultValue: false
            }

            StyledText {
                width: parent.width
                visible: autoLocToggle.value
                text: "Manual latitude, longitude, and UTC-offset fields are hidden while Auto Detect Location is on."
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
                    text: "Enter your own coordinates — nothing is pre-filled."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
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

    DCard {
        id: notifyCard
        width: parent.width
        height: notifyContent.implicitHeight + notifyCard.pad * 2
        pad: Theme.spacingL

        Column {
            id: notifyContent
            width: parent.width
            spacing: Theme.spacingM

            RowLayout {
                width: parent.width
                spacing: Theme.spacingM

                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: Theme.cornerRadiusS
                    color: Theme.withAlpha(Theme.primary, 0.12)

                    DIcon {
                        anchors.centerIn: parent
                        name: "notifications"
                        size: Theme.iconSizeSmall
                        color: Theme.primary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: "Notifications"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightBold
                        color: Theme.surfaceText
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "Choose how early to be reminded before each prayer."
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                    }
                }
            }

            StringSetting {
                settingKey: "notifyMinutes"
                label: "Reminder (minutes before prayer)"
                description: "How many minutes before prayer to send a notification (0–1440)."
                defaultValue: "15"
            }
        }
    }

    DCard {
        id: athanCard
        width: parent.width
        height: athanContent.implicitHeight + athanCard.pad * 2
        pad: Theme.spacingL

        Column {
            id: athanContent
            width: parent.width
            spacing: Theme.spacingM

            RowLayout {
                width: parent.width
                spacing: Theme.spacingM

                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: Theme.cornerRadiusS
                    color: Theme.withAlpha(Theme.primary, 0.12)

                    DIcon {
                        anchors.centerIn: parent
                        name: "volume_up"
                        size: Theme.iconSizeSmall
                        color: Theme.primary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: "Athan (Call to Prayer)"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightBold
                        color: Theme.surfaceText
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "Play an audio file the moment each prayer time starts."
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                    }
                }
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
                description: "A local .mp3/.ogg/.wav path, a direct http(s) link to stream, or a filename inside this plugin's assets/ folder (e.g. assets/athan.mp3)."
                defaultValue: ""
            }
        }
    }

    DCard {
        id: quranCard
        width: parent.width
        height: quranContent.implicitHeight + quranCard.pad * 2
        pad: Theme.spacingL

        Column {
            id: quranContent
            width: parent.width
            spacing: Theme.spacingM

            RowLayout {
                width: parent.width
                spacing: Theme.spacingM

                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: Theme.cornerRadiusS
                    color: Theme.withAlpha(Theme.primary, 0.12)

                    DIcon {
                        anchors.centerIn: parent
                        name: "menu_book"
                        size: Theme.iconSizeSmall
                        color: Theme.primary
                    }
                }

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
                        text: "Browse reciters and stream any surah from the widget popout."
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                    }
                }
            }

            ToggleSetting {
                settingKey: "quranEnabled"
                label: "Show Quran Tab in Popout"
                description: "Adds a Quran tab to the widget popout to browse reciters and play any surah."
                defaultValue: true
            }

            StyledText {
                width: parent.width
                text: "Reciter metadata and audio are provided by mp3quran.net. Playback requires mpv, ffplay, or cvlc."
                font.pixelSize: Theme.fontSizeXSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }
        }
    }
}
