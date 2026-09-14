import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme

ColumnLayout {
    id: view

    readonly property var sources: [
        { id: "radio", label: "Radio", icon: "radio" },
        { id: "podcasts", label: "Podcasts", icon: "podcasts" },
        { id: "upnp", label: "Media", icon: "dns" }
    ]

    property string source: "radio"
    // Breadcrumbs as { title, path }; the source root is the empty trail.
    property var trail: []
    property string query: ""

    property var items: []
    property int totalCount: 0
    property bool loading: false
    property string message: ""
    property string notice: ""
    property bool loaded: false

    // Bumped per request so a slow response for a list the user already left cannot overwrite the current one.
    property int generation: 0

    readonly property string currentPath: trail.length > 0 ? trail[trail.length - 1].path : ""
    readonly property bool inFavorites: /\/favorites$/.test(currentPath)
    readonly property string sourceLabel: sources.find(s => s.id === source).label

    spacing: 8

    onVisibleChanged: {
        if (visible && !loaded)
            reload();
    }

    function reload() {
        loaded = true;
        const gen = ++generation;
        loading = true;
        message = "";
        KefService.browse(source, currentPath, query, (ok, json) => {
            if (gen !== generation)
                return;
            loading = false;
            if (!ok || !json) {
                items = [];
                totalCount = 0;
                message = (json && json.error) || "Could not load this list";
                return;
            }
            items = json.items || [];
            totalCount = json.totalCount || items.length;
            message = json.message || (items.length === 0 ? "Nothing here" : "");
        });
    }

    function selectSource(id) {
        source = id;
        trail = [];
        setQuery("");
        reload();
    }

    function open(item) {
        trail = trail.concat([{ title: item.title, path: item.path }]);
        setQuery("");
        reload();
    }

    function back() {
        if (query !== "")
            setQuery("");
        else
            trail = trail.slice(0, -1);
        reload();
    }

    function setQuery(text) {
        searchDelay.stop();
        query = text;
        searchField.text = text;
    }

    function search(text) {
        setQuery(text);
        reload();
    }

    function openSearch(sourceId, text) {
        source = sourceId;
        trail = [];
        search(text);
    }

    function showNotice(text) {
        notice = text;
        noticeTimer.restart();
    }

    function isStation(item) { return item.audioType === "audioBroadcast"; }
    function isPlayable(item) { return item.type === "audio" || item.playable === true || isStation(item); }
    function canQueue(item) { return isPlayable(item) && !isStation(item); }

    function pickPlaylist(item) {
        playlistPicker.track = KefService.trackFromBrowseItem(item);
        playlistPicker.open();
    }

    // The server only keeps favorites for live stations and podcast shows, which are the feed containers.
    function canFavorite(item) {
        if (source === "radio")
            return isStation(item);
        return source === "podcasts" && item.type === "container" && /\/feed\/\d+$/.test(item.path);
    }

    function activate(item) {
        if (item.searchQuery)
            search(item.searchQuery);
        else if (item.type === "container" && !isStation(item))
            open(item);
        else
            KefService.playBrowseItem(source, item);
    }

    function queue(item) {
        KefService.queueBrowseItem(source, item, (ok, json) => {
            if (!ok)
                showNotice((json && json.error) || "Could not add to the queue");
            else
                showNotice(json.tracksAdded === 1 ? `Added “${item.title}” to the queue` : `Added ${json.tracksAdded} tracks to the queue`);
        });
    }

    function favorite(item) {
        const add = !inFavorites;
        KefService.favoriteBrowseItem(source, item, add, (ok, json) => {
            if (!ok) {
                showNotice((json && json.error) || "Could not update favorites");
                return;
            }
            showNotice(add ? `Added “${item.title}” to favorites` : `Removed “${item.title}” from favorites`);
            if (!add)
                reload();
        });
    }

    Timer {
        id: searchDelay
        interval: 500
        onTriggered: view.search(searchField.text.trim())
    }

    Timer {
        id: noticeTimer
        interval: 3000
        onTriggered: view.notice = ""
    }

    PlaylistPicker {
        id: playlistPicker
        x: (view.width - width) / 2
        y: 80
        onFinished: message => view.showNotice(message)
    }

    Row {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: view.sources

            PillButton {
                required property var modelData
                icon: modelData.icon
                text: modelData.label
                selected: view.source === modelData.id
                onClicked: view.selectSource(modelData.id)
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        IconButton {
            icon: "arrow_back"
            size: 34
            enabled: view.trail.length > 0 || view.query !== ""
            onClicked: view.back()
        }
        KefTextField {
            id: searchField
            Layout.fillWidth: true
            placeholderText: `Search ${view.sourceLabel.toLowerCase()}…`
            onTextEdited: searchDelay.restart()
            onAccepted: view.search(text.trim())
        }
    }

    KefLabel {
        Layout.fillWidth: true
        visible: view.trail.length > 0 || view.query !== ""
        elide: Text.ElideLeft
        font.pixelSize: 11
        color: Theme.on_surface_variant
        text: [view.sourceLabel].concat(view.trail.map(t => t.title)).concat(view.query !== "" ? [`“${view.query}”`] : []).join("  ›  ")
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        KefLabel {
            anchors.centerIn: parent
            visible: view.loading || (view.message !== "" && list.count === 0)
            text: view.loading ? "Loading…" : view.message
            color: Theme.on_surface_variant
        }

        ListView {
            id: list
            anchors.fill: parent
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            visible: !view.loading
            model: view.items
            ScrollBar.vertical: ScrollBar {}

            delegate: Rectangle {
                id: row

                required property var modelData
                readonly property var item: modelData

                width: ListView.view.width
                height: 50
                radius: 8
                color: hover.hovered ? Theme.surface_container_high : "transparent"

                HoverHandler {
                    id: hover
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.activate(row.item)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 10

                    Artwork {
                        implicitWidth: 38
                        implicitHeight: 38
                        source: KefService.resolveUrl(row.item.icon)
                        fallbackIcon: row.item.searchQuery ? "search" : view.isStation(row.item) ? "radio" : row.item.type === "container" ? "folder" : "music_note"
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        KefLabel {
                            Layout.fillWidth: true
                            text: row.item.title
                        }
                        KefLabel {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: [row.item.artist, row.item.album].filter(Boolean).join(" · ") || row.item.description || ""
                            font.pixelSize: 11
                            color: Theme.on_surface_variant
                        }
                    }

                    Row {
                        IconButton {
                            visible: hover.hovered && view.canFavorite(row.item)
                            icon: view.inFavorites ? "heart_broken" : "favorite_border"
                            size: 30
                            onClicked: view.favorite(row.item)
                        }
                        IconButton {
                            // The server rejects containers as playlist tracks, which includes radio stations.
                            visible: hover.hovered && row.item.type === "audio"
                            icon: "library_add"
                            size: 30
                            onClicked: view.pickPlaylist(row.item)
                        }
                        IconButton {
                            visible: hover.hovered && view.canQueue(row.item)
                            icon: "playlist_add"
                            size: 30
                            onClicked: view.queue(row.item)
                        }
                        IconButton {
                            visible: view.isPlayable(row.item)
                            icon: "play_arrow"
                            size: 30
                            onClicked: KefService.playBrowseItem(view.source, row.item)
                        }
                        MaterialIcon {
                            visible: row.item.type === "container" && !view.isStation(row.item)
                            width: 30
                            height: 30
                            name: "chevron_right"
                            color: Theme.on_surface_variant
                        }
                    }
                }
            }
        }
    }

    KefLabel {
        Layout.fillWidth: true
        visible: text !== ""
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: 11
        color: view.notice !== "" ? Theme.primary : Theme.on_surface_variant
        text: view.notice !== "" ? view.notice : (!view.loading && view.totalCount > view.items.length ? `Showing ${view.items.length} of ${view.totalCount}` : "")
    }
}
