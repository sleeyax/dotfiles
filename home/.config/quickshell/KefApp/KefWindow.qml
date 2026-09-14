import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.CustomTheme

PanelWindow {
    id: root

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "kef"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    // Normal rather than Ignore, so the compositor places the panel below waybar's exclusive zone instead of it guessing the bar's height.
    exclusionMode: ExclusionMode.Normal

    anchors {
        top: true
        right: true
    }
    margins {
        top: 4
        right: 4
    }

    implicitWidth: 480
    implicitHeight: content.implicitHeight + 2 * (frame.anchors.margins + content.anchors.margins)
    color: "transparent"

    readonly property bool isOpen: KefService.panelOpen

    // Keeps the surface mapped until the hide animation has finished.
    property bool shown: false
    visible: shown

    property string currentTab: "queue"

    readonly property var tabs: [
        { id: "queue", label: "Queue", icon: "queue_music" }
    ]

    readonly property var sources: [
        { id: "wifi", label: "Wi-Fi", icon: "wifi" },
        { id: "bluetooth", label: "Bluetooth", icon: "bluetooth" },
        { id: "tv", label: "TV", icon: "tv" },
        { id: "optical", label: "Optical", icon: "settings_input_component" },
        { id: "coaxial", label: "Coaxial", icon: "settings_input_composite" },
        { id: "analog", label: "Analog", icon: "settings_input_svideo" },
        { id: "usb", label: "USB", icon: "usb" }
    ]

    onIsOpenChanged: {
        if (isOpen) {
            shown = true;
            frame.forceActiveFocus();
        }
    }

    HyprlandFocusGrab {
        windows: [root]
        active: root.shown && root.isOpen
        onCleared: KefService.panelOpen = false
    }

    Shortcut {
        sequence: "Escape"
        onActivated: KefService.panelOpen = false
    }

    Item {
        id: frame
        anchors.fill: parent
        anchors.margins: 12
        focus: true

        opacity: root.isOpen ? 1 : 0
        transform: Translate {
            y: root.isOpen ? 0 : -16
            Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
                onRunningChanged: {
                    if (!running && !root.isOpen)
                        root.shown = false;
                }
            }
        }

        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Space:
                KefService.playOrStop();
                break;
            case Qt.Key_Up:
                KefService.changeVolume(2);
                break;
            case Qt.Key_Down:
                KefService.changeVolume(-2);
                break;
            case Qt.Key_Right:
                KefService.next();
                break;
            case Qt.Key_Left:
                KefService.previous();
                break;
            case Qt.Key_M:
                KefService.setMuted(!KefService.muted);
                break;
            default:
                return;
            }
            event.accepted = true;
        }

        // Clicking empty space hands keyboard focus back from a text field to the panel shortcuts.
        MouseArea {
            anchors.fill: parent
            onPressed: mouse => {
                frame.forceActiveFocus();
                mouse.accepted = false;
            }
        }

        RectangularShadow {
            anchors.fill: background
            radius: background.radius
            blur: 15
            color: Qt.rgba(Theme.shadow.r, Theme.shadow.g, Theme.shadow.b, 0.4)
        }

        Rectangle {
            id: background
            anchors.fill: parent
            radius: 14
            opacity: 0.95
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Theme.primary }
                GradientStop { position: 1.0; color: Theme.on_primary }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: parent.radius - anchors.margins
                color: Theme.background
            }
        }

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 18
            spacing: 16

            // --- Header ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                MaterialIcon {
                    name: "speaker"
                    size: 26
                    color: Theme.primary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    KefLabel {
                        Layout.fillWidth: true
                        text: KefService.speakerName || "KEF"
                        font.pixelSize: 16
                        font.bold: true
                    }
                    KefLabel {
                        Layout.fillWidth: true
                        visible: KefService.speakerIp !== ""
                        text: `${KefService.speakerModel} · ${KefService.speakerIp}`
                        color: Theme.on_surface_variant
                        font.pixelSize: 11
                    }
                }

                Rectangle {
                    implicitWidth: 8
                    implicitHeight: 8
                    radius: 4
                    color: !KefService.backendUp ? Theme.error : KefService.standby ? Theme.outline : Theme.tertiary
                }

                IconButton {
                    icon: "power_settings_new"
                    enabled: KefService.backendUp
                    checked: !KefService.standby
                    onClicked: KefService.setPower(KefService.standby)
                }
            }

            // --- Backend not reachable ---
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 24
                Layout.bottomMargin: 24
                visible: !KefService.backendUp
                spacing: 12

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    name: KefService.backendFailed ? "error_outline" : "hourglass_empty"
                    size: 40
                    color: KefService.backendFailed ? Theme.error : Theme.on_surface_variant
                }
                KefLabel {
                    Layout.alignment: Qt.AlignHCenter
                    text: KefService.backendFailed ? `kefw2ui did not answer on port ${KefService.port}` : "Starting kefw2ui…"
                    color: Theme.on_surface_variant
                }
                PillButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: KefService.backendFailed
                    icon: "refresh"
                    text: "Retry"
                    onClicked: KefService.ensureBackend()
                }
            }

            // --- Standby ---
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 24
                Layout.bottomMargin: 24
                visible: KefService.backendUp && KefService.standby
                spacing: 14

                IconButton {
                    Layout.alignment: Qt.AlignHCenter
                    icon: "power_settings_new"
                    size: 72
                    filled: true
                    onClicked: KefService.setPower(true)
                }
                KefLabel {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Speaker is in standby"
                    color: Theme.on_surface_variant
                }
            }

            // --- Now playing ---
            ColumnLayout {
                Layout.fillWidth: true
                visible: KefService.backendUp && !KefService.standby
                spacing: 16

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    Artwork {
                        implicitWidth: 132
                        implicitHeight: 132
                        radius: 10
                        fallbackIcon: "album"
                        source: KefService.iconUrl
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 4

                        KefLabel {
                            Layout.fillWidth: true
                            text: KefService.title || "Nothing playing"
                            font.pixelSize: 17
                            font.bold: true
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                        }
                        KefLabel {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: KefService.artist
                            color: Theme.primary
                        }
                        KefLabel {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: KefService.album
                            color: Theme.on_surface_variant
                        }
                        Rectangle {
                            visible: KefService.isLive
                            Layout.topMargin: 4
                            implicitWidth: liveText.implicitWidth + 12
                            implicitHeight: 18
                            radius: 4
                            color: Theme.error_container

                            KefLabel {
                                id: liveText
                                anchors.centerIn: parent
                                text: "LIVE"
                                font.pixelSize: 10
                                font.bold: true
                                color: Theme.on_error_container
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: !KefService.isLive && KefService.duration > 0
                    spacing: 0

                    KefSlider {
                        id: progress
                        Layout.fillWidth: true
                        from: 0
                        to: KefService.duration
                        externalValue: KefService.position
                        onCommitted: value => KefService.seek(value)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        KefLabel {
                            text: KefService.formatTime(progress.value)
                            color: Theme.on_surface_variant
                            font.pixelSize: 11
                        }
                        Item { Layout.fillWidth: true }
                        KefLabel {
                            text: KefService.formatTime(KefService.duration)
                            color: Theme.on_surface_variant
                            font.pixelSize: 11
                        }
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 14

                    IconButton {
                        icon: "shuffle"
                        checked: KefService.shuffle
                        enabled: !KefService.isLive
                        onClicked: KefService.setShuffle(!KefService.shuffle)
                    }
                    IconButton {
                        icon: "skip_previous"
                        size: 44
                        onClicked: KefService.previous()
                    }
                    IconButton {
                        icon: KefService.playing ? (KefService.isLive ? "stop" : "pause") : "play_arrow"
                        size: 60
                        filled: true
                        onClicked: KefService.playOrStop()
                    }
                    IconButton {
                        icon: "skip_next"
                        size: 44
                        onClicked: KefService.next()
                    }
                    IconButton {
                        icon: KefService.repeatMode === "one" ? "repeat_one" : "repeat"
                        checked: KefService.repeatMode !== "off"
                        enabled: !KefService.isLive
                        onClicked: KefService.cycleRepeat()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    IconButton {
                        icon: KefService.muted ? "volume_off" : volume.value < 35 ? "volume_down" : "volume_up"
                        checked: KefService.muted
                        onClicked: KefService.setMuted(!KefService.muted)
                    }
                    KefSlider {
                        id: volume
                        Layout.fillWidth: true
                        from: 0
                        to: 100
                        stepSize: 1
                        wheelEnabled: true
                        externalValue: KefService.volume
                        onCommitted: value => KefService.setVolume(value)
                    }
                    KefLabel {
                        Layout.preferredWidth: 32
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(volume.value)
                        color: Theme.on_surface_variant
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: root.sources

                        PillButton {
                            required property var modelData
                            icon: modelData.icon
                            text: modelData.label
                            selected: KefService.source === modelData.id
                            onClicked: KefService.setSource(modelData.id)
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Theme.outline_variant
                }

                Row {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: root.tabs

                        PillButton {
                            required property var modelData
                            icon: modelData.icon
                            text: modelData.label
                            selected: root.currentTab === modelData.id
                            onClicked: root.currentTab = modelData.id
                        }
                    }
                }

                StackLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 320
                    currentIndex: root.tabs.findIndex(tab => tab.id === root.currentTab)

                    QueueView {}
                }
            }
        }
    }
}
