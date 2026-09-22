import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme

Popup {
    id: picker

    // A playlist track built by KefService.trackFromBrowseItem.
    property var track: null

    signal finished(string message)

    width: 260
    padding: 8
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    onOpened: {
        nameField.text = "";
        KefService.refreshPlaylists();
    }

    function add(playlist) {
        KefService.addTrackToPlaylist(playlist.id, track, ok => {
            finished(ok ? `Added to “${playlist.name}”` : "Could not update the playlist");
            close();
        });
    }

    function create() {
        const name = nameField.text.trim();
        if (name === "")
            return;
        KefService.createPlaylist(name, [track], (ok, json) => {
            finished(ok ? `Created “${name}”` : (json && json.error) || "Could not create the playlist");
            close();
        });
    }

    background: Rectangle {
        radius: 10
        color: Theme.surface_container
        border.width: 1
        border.color: Theme.outline_variant
    }

    contentItem: ColumnLayout {
        spacing: 4

        KefLabel {
            Layout.margins: 4
            text: "Add to playlist"
            font.bold: true
        }

        ListView {
            Layout.fillWidth: true
            implicitHeight: Math.min(contentHeight, 200)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: KefService.playlists

            delegate: Rectangle {
                id: option

                required property var modelData

                width: ListView.view.width
                height: 32
                radius: 6
                color: optionMouse.containsMouse ? Theme.surface_container_highest : "transparent"

                KefLabel {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: option.modelData.name
                }

                MouseArea {
                    id: optionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: picker.add(option.modelData)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            KefTextField {
                id: nameField
                Layout.fillWidth: true
                placeholderText: "New playlist"
                onAccepted: picker.create()
            }
            IconButton {
                icon: "add"
                size: 34
                enabled: nameField.text.trim() !== ""
                onClicked: picker.create()
            }
        }
    }
}
