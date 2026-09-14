import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme

ColumnLayout {
    id: view

    // The open playlist with its tracks, or null while the list of playlists is shown.
    property var detail: null
    property bool naming: false
    // Empty while naming a new playlist, otherwise the id of the playlist being renamed.
    property string renameTarget: ""
    property string confirmDelete: ""
    property string notice: ""
    property bool loaded: false

    spacing: 8

    onVisibleChanged: {
        if (visible && !loaded) {
            loaded = true;
            KefService.refreshPlaylists();
        }
    }

    Connections {
        target: KefService
        function onPlaylistsChanged() {
            if (view.detail)
                view.open(view.detail.id);
        }
    }

    function showNotice(text) {
        notice = text;
        noticeTimer.restart();
    }

    function open(id) {
        KefService.getPlaylist(id, (ok, json) => {
            if (ok && json)
                detail = json.playlist;
            else
                detail = null;
        });
    }

    function startNaming(id) {
        renameTarget = id;
        nameField.text = id === "" ? "" : detail.name;
        naming = true;
        nameField.forceActiveFocus();
    }

    function submitName() {
        const name = nameField.text.trim();
        if (name === "")
            return;
        naming = false;
        if (renameTarget === "") {
            KefService.createPlaylist(name, [], (ok, json) => {
                if (ok)
                    open(json.playlist.id);
                else
                    showNotice((json && json.error) || "Could not create the playlist");
            });
        } else {
            save({ name: name });
        }
    }

    // PUT overwrites the description whenever it is left out, so every save sends the whole playlist.
    function save(changes) {
        const next = Object.assign({ name: detail.name, description: detail.description || "", tracks: detail.tracks || [] }, changes);
        detail = Object.assign({}, detail, next);
        KefService.updatePlaylist(detail.id, next, (ok, json) => {
            if (!ok)
                showNotice((json && json.error) || "Could not save the playlist");
        });
    }

    function moveTrack(from, to) {
        const tracks = detail.tracks.slice();
        if (to < 0 || to >= tracks.length)
            return;
        tracks.splice(to, 0, tracks.splice(from, 1)[0]);
        save({ tracks: tracks });
    }

    function removeTrack(index) {
        const tracks = detail.tracks.slice();
        tracks.splice(index, 1);
        save({ tracks: tracks });
    }

    function load(id, append) {
        KefService.loadPlaylist(id, append, (ok, json) => {
            if (!ok) {
                showNotice((json && json.error) || "Could not load the playlist");
                return;
            }
            const skipped = json.skipped ? `, ${json.skipped} skipped` : "";
            showNotice((append ? `Added ${json.trackCount} tracks to the queue` : `Playing ${json.trackCount} tracks`) + skipped);
        });
    }

    function remove(id) {
        if (confirmDelete !== id) {
            confirmDelete = id;
            confirmTimer.restart();
            return;
        }
        confirmDelete = "";
        KefService.deletePlaylist(id, ok => {
            if (!ok)
                showNotice("Could not delete the playlist");
            else if (detail && detail.id === id)
                detail = null;
        });
    }

    Timer {
        id: noticeTimer
        interval: 3000
        onTriggered: view.notice = ""
    }

    Timer {
        id: confirmTimer
        interval: 3000
        onTriggered: view.confirmDelete = ""
    }

    RowLayout {
        Layout.fillWidth: true
        visible: view.naming
        spacing: 6

        KefTextField {
            id: nameField
            Layout.fillWidth: true
            placeholderText: "Playlist name"
            onAccepted: view.submitName()
        }
        IconButton {
            icon: "check"
            enabled: nameField.text.trim() !== ""
            onClicked: view.submitName()
        }
        IconButton {
            icon: "close"
            onClicked: view.naming = false
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: !view.naming && view.detail === null
        spacing: 6

        KefLabel {
            Layout.fillWidth: true
            text: KefService.playlists.length === 1 ? "1 playlist" : `${KefService.playlists.length} playlists`
            color: Theme.on_surface_variant
        }
        PillButton {
            icon: "add"
            text: "New playlist"
            onClicked: view.startNaming("")
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: !view.naming && view.detail !== null
        spacing: 2

        IconButton {
            icon: "arrow_back"
            size: 34
            onClicked: view.detail = null
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            KefLabel {
                Layout.fillWidth: true
                text: view.detail ? view.detail.name : ""
                font.bold: true
            }
            KefLabel {
                Layout.fillWidth: true
                font.pixelSize: 11
                color: Theme.on_surface_variant
                text: {
                    if (!view.detail)
                        return "";
                    const count = (view.detail.tracks || []).length;
                    return [count === 1 ? "1 track" : `${count} tracks`, view.detail.description].filter(Boolean).join(" · ");
                }
            }
        }
        IconButton {
            icon: "play_arrow"
            size: 32
            enabled: view.detail !== null && (view.detail.tracks || []).length > 0
            onClicked: view.load(view.detail.id, false)
        }
        IconButton {
            icon: "playlist_add"
            size: 32
            enabled: view.detail !== null && (view.detail.tracks || []).length > 0
            onClicked: view.load(view.detail.id, true)
        }
        IconButton {
            icon: "edit"
            size: 32
            onClicked: view.startNaming(view.detail.id)
        }
        IconButton {
            icon: view.detail && view.confirmDelete === view.detail.id ? "delete_forever" : "delete_outline"
            size: 32
            checked: view.detail !== null && view.confirmDelete === view.detail.id
            onClicked: view.remove(view.detail.id)
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        KefLabel {
            anchors.centerIn: parent
            visible: view.detail === null ? playlistList.count === 0 : trackList.count === 0
            text: view.detail === null ? "No playlists yet" : "This playlist is empty"
            color: Theme.on_surface_variant
        }

        ListView {
            id: playlistList
            anchors.fill: parent
            visible: view.detail === null
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: KefService.playlists
            ScrollBar.vertical: ScrollBar {}

            delegate: Rectangle {
                id: playlistRow

                required property var modelData

                width: ListView.view.width
                height: 50
                radius: 8
                color: playlistHover.hovered ? Theme.surface_container_high : "transparent"

                HoverHandler {
                    id: playlistHover
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.open(playlistRow.modelData.id)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 10

                    Rectangle {
                        implicitWidth: 38
                        implicitHeight: 38
                        radius: 6
                        color: Theme.surface_container_high

                        MaterialIcon {
                            anchors.centerIn: parent
                            name: "queue_music"
                            size: 18
                            color: Theme.on_surface_variant
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        KefLabel {
                            Layout.fillWidth: true
                            text: playlistRow.modelData.name
                        }
                        KefLabel {
                            Layout.fillWidth: true
                            font.pixelSize: 11
                            color: Theme.on_surface_variant
                            text: [playlistRow.modelData.trackCount === 1 ? "1 track" : `${playlistRow.modelData.trackCount} tracks`, playlistRow.modelData.description].filter(Boolean).join(" · ")
                        }
                    }

                    Row {
                        visible: playlistHover.hovered || view.confirmDelete === playlistRow.modelData.id

                        IconButton {
                            icon: "play_arrow"
                            size: 30
                            enabled: playlistRow.modelData.trackCount > 0
                            onClicked: view.load(playlistRow.modelData.id, false)
                        }
                        IconButton {
                            icon: "playlist_add"
                            size: 30
                            enabled: playlistRow.modelData.trackCount > 0
                            onClicked: view.load(playlistRow.modelData.id, true)
                        }
                        IconButton {
                            icon: view.confirmDelete === playlistRow.modelData.id ? "delete_forever" : "delete_outline"
                            size: 30
                            checked: view.confirmDelete === playlistRow.modelData.id
                            onClicked: view.remove(playlistRow.modelData.id)
                        }
                    }
                }
            }
        }

        ListView {
            id: trackList
            anchors.fill: parent
            visible: view.detail !== null
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: view.detail ? view.detail.tracks || [] : []
            ScrollBar.vertical: ScrollBar {}

            delegate: Rectangle {
                id: trackRow

                required property var modelData
                required property int index

                width: ListView.view.width
                height: 50
                radius: 8
                color: trackHover.hovered ? Theme.surface_container_high : "transparent"

                HoverHandler {
                    id: trackHover
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 10

                    Artwork {
                        implicitWidth: 38
                        implicitHeight: 38
                        source: KefService.resolveUrl(trackRow.modelData.icon)
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        KefLabel {
                            Layout.fillWidth: true
                            text: trackRow.modelData.title
                        }
                        KefLabel {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: [trackRow.modelData.artist, trackRow.modelData.album].filter(Boolean).join(" · ")
                            font.pixelSize: 11
                            color: Theme.on_surface_variant
                        }
                    }

                    KefLabel {
                        visible: !trackHover.hovered && trackRow.modelData.duration > 0
                        text: KefService.formatTime(trackRow.modelData.duration || 0)
                        font.pixelSize: 11
                        color: Theme.on_surface_variant
                    }

                    Row {
                        visible: trackHover.hovered

                        IconButton {
                            icon: "arrow_upward"
                            size: 30
                            enabled: trackRow.index > 0
                            onClicked: view.moveTrack(trackRow.index, trackRow.index - 1)
                        }
                        IconButton {
                            icon: "arrow_downward"
                            size: 30
                            enabled: trackRow.index < trackList.count - 1
                            onClicked: view.moveTrack(trackRow.index, trackRow.index + 1)
                        }
                        IconButton {
                            icon: "close"
                            size: 30
                            onClicked: view.removeTrack(trackRow.index)
                        }
                    }
                }
            }
        }
    }

    KefLabel {
        Layout.fillWidth: true
        visible: view.notice !== ""
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: 11
        color: Theme.primary
        text: view.notice
    }
}
