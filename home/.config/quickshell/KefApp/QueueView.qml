import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme

ColumnLayout {
    id: view

    property bool saving: false
    property string saveError: ""

    spacing: 8

    function startSave() {
        saveError = "";
        nameField.text = "";
        saving = true;
        nameField.forceActiveFocus();
    }

    function save() {
        const name = nameField.text.trim();
        if (name === "")
            return;
        KefService.saveQueueAsPlaylist(name, (ok, error) => {
            if (ok)
                saving = false;
            else
                saveError = error || "Could not save the playlist";
        });
    }

    RowLayout {
        Layout.fillWidth: true
        visible: !view.saving
        spacing: 6

        KefLabel {
            Layout.fillWidth: true
            text: KefService.queueTracks.length === 1 ? "1 track" : `${KefService.queueTracks.length} tracks`
            color: Theme.on_surface_variant
        }
        PillButton {
            icon: "playlist_add"
            text: "Save as playlist"
            enabled: KefService.queueTracks.length > 0
            onClicked: view.startSave()
        }
        PillButton {
            icon: "clear_all"
            text: "Clear"
            enabled: KefService.queueTracks.length > 0
            onClicked: KefService.clearQueue()
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: view.saving
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            KefTextField {
                id: nameField
                Layout.fillWidth: true
                placeholderText: "Playlist name"
                onAccepted: view.save()
            }
            IconButton {
                icon: "check"
                enabled: nameField.text.trim() !== ""
                onClicked: view.save()
            }
            IconButton {
                icon: "close"
                onClicked: view.saving = false
            }
        }
        KefLabel {
            Layout.fillWidth: true
            visible: view.saveError !== ""
            text: view.saveError
            color: Theme.error
            font.pixelSize: 11
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        KefLabel {
            anchors.centerIn: parent
            visible: list.count === 0
            text: "The queue is empty"
            color: Theme.on_surface_variant
        }

        ListView {
            id: list
            anchors.fill: parent
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: KefService.queueTracks
            ScrollBar.vertical: ScrollBar {}

            delegate: Rectangle {
                id: row

                required property var modelData
                required property int index
                readonly property bool current: index === KefService.queueIndex

                width: ListView.view.width
                height: 50
                radius: 8
                color: current ? Theme.secondary_container : hover.hovered ? Theme.surface_container_high : "transparent"

                HoverHandler {
                    id: hover
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: KefService.playQueueItem(row.index)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 10

                    Artwork {
                        implicitWidth: 38
                        implicitHeight: 38
                        source: KefService.resolveUrl(row.modelData.icon)
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        KefLabel {
                            Layout.fillWidth: true
                            text: row.modelData.title
                            font.bold: row.current
                            color: row.current ? Theme.on_secondary_container : Theme.on_surface
                        }
                        KefLabel {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: [row.modelData.artist, row.modelData.album].filter(Boolean).join(" · ")
                            font.pixelSize: 11
                            color: Theme.on_surface_variant
                        }
                    }

                    KefLabel {
                        visible: !hover.hovered && row.modelData.duration > 0
                        text: KefService.formatTime(row.modelData.duration)
                        font.pixelSize: 11
                        color: Theme.on_surface_variant
                    }

                    Row {
                        visible: hover.hovered

                        IconButton {
                            icon: "arrow_upward"
                            size: 30
                            enabled: row.index > 0
                            onClicked: KefService.moveQueueItem(row.index, row.index - 1)
                        }
                        IconButton {
                            icon: "arrow_downward"
                            size: 30
                            enabled: row.index < list.count - 1
                            onClicked: KefService.moveQueueItem(row.index, row.index + 1)
                        }
                        IconButton {
                            icon: "close"
                            size: 30
                            onClicked: KefService.removeQueueItem(row.index)
                        }
                    }
                }
            }
        }
    }
}
