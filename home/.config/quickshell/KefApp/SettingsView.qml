import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.CustomTheme

Flickable {
    id: view

    property bool loaded: false
    property string notice: ""

    property var speakers: []
    property var discovered: []
    property bool discovering: false

    property var speakerSettings: null
    property var eq: null
    property var subwoofer: null
    property var serverInfo: null

    property var upnp: ({ defaultServer: "", defaultServerPath: "", browseContainer: "", indexContainer: "" })
    property var servers: []
    // "browse" or "index" while a folder is being picked for that setting, empty otherwise.
    property string picking: ""
    property var pickTrail: []
    property var pickContainers: []
    property var reindex: null

    contentHeight: column.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {}

    onVisibleChanged: {
        if (visible && !loaded)
            reload();
    }

    Connections {
        target: KefService
        function onReindexUpdated(data) {
            view.reindex = data;
            if (data.status === "complete")
                view.loadUpnp();
        }
    }

    function showNotice(text) {
        notice = text;
        noticeTimer.restart();
    }

    function reload() {
        loaded = true;
        loadSpeakers();
        loadSpeakerSettings();
        loadUpnp();
        KefService.get("/api/settings/eq", (ok, json) => {
            if (ok && json) {
                eq = json.eq;
                subwoofer = json.subwoofer;
            }
        });
        KefService.get("/api/settings", (ok, json) => {
            if (ok && json)
                serverInfo = json;
        });
    }

    // The backend iterates a map, so the order changes on every call.
    function loadSpeakers() {
        KefService.get("/api/speakers", (ok, json) => {
            if (ok && json)
                speakers = (json.speakers || []).sort((a, b) => a.name.localeCompare(b.name));
        });
    }

    function loadSpeakerSettings() {
        KefService.get("/api/settings/speaker", (ok, json) => {
            if (ok && json)
                speakerSettings = json;
        });
    }

    function switchTo(ip) {
        KefService.switchSpeaker(ip, ok => {
            if (!ok)
                showNotice("Could not switch to that speaker");
            loadSpeakers();
            loadSpeakerSettings();
        });
    }

    function makeDefault(ip) {
        KefService.post("/api/speakers/default", { ip: ip }, ok => {
            if (!ok)
                showNotice("Could not set the default speaker");
            loadSpeakers();
        });
    }

    function discover() {
        discovering = true;
        discovered = [];
        KefService.post("/api/speakers/discover", {}, (ok, json) => {
            discovering = false;
            if (!ok) {
                showNotice("Discovery failed");
                return;
            }
            const known = speakers.map(s => s.ip);
            discovered = (json.discovered || []).filter(d => !known.includes(d.ip));
            if (discovered.length === 0)
                showNotice("No new speakers found");
        });
    }

    function addSpeaker(ip) {
        if (ip === "")
            return;
        KefService.post("/api/speakers/add", { ip: ip }, (ok, json) => {
            if (!ok) {
                showNotice((json && json.error) || `Could not reach a speaker at ${ip}`);
                return;
            }
            discovered = discovered.filter(d => d.ip !== ip);
            ipField.text = "";
            loadSpeakers();
        });
    }

    function setMaxVolume(value) {
        KefService.request("PUT", "/api/settings/speaker", { maxVolume: Math.round(value) }, ok => {
            if (!ok)
                showNotice("Could not set the volume limit");
            loadSpeakerSettings();
        });
    }

    function loadUpnp() {
        KefService.get("/api/settings/upnp", (ok, json) => {
            if (ok && json)
                upnp = json;
        });
        // The speaker lists its own cross-server search next to the real servers.
        KefService.get("/api/upnp/servers", (ok, json) => {
            if (ok && json)
                servers = (json.servers || []).filter(s => !s.path.startsWith("upnp:search"));
        });
    }

    function saveUpnp(changes) {
        const body = Object.assign({
            defaultServer: upnp.defaultServer,
            defaultServerPath: upnp.defaultServerPath,
            browseContainer: upnp.browseContainer,
            indexContainer: upnp.indexContainer
        }, changes);
        KefService.request("PUT", "/api/settings/upnp", body, (ok, json) => {
            if (ok && json)
                upnp = json;
            else
                showNotice((json && json.error) || "Could not save the media settings");
        });
    }

    // A folder is only meaningful on the server it was picked from.
    function selectServer(server) {
        saveUpnp({ defaultServer: server.name, defaultServerPath: server.path, browseContainer: "", indexContainer: "" });
    }

    function startPicking(kind) {
        picking = kind;
        pickTrail = [];
        loadContainers();
    }

    function loadContainers() {
        const query = `?server=${encodeURIComponent(upnp.defaultServerPath)}&path=${encodeURIComponent(pickTrail.join("/"))}`;
        KefService.get("/api/upnp/containers" + query, (ok, json) => {
            pickContainers = ok && json ? json.containers || [] : [];
        });
    }

    function usePickedFolder() {
        const changes = {};
        changes[picking === "browse" ? "browseContainer" : "indexContainer"] = pickTrail.join("/");
        saveUpnp(changes);
        picking = "";
    }

    function startReindex() {
        KefService.post("/api/upnp/reindex", {}, (ok, json, status) => {
            if (ok)
                reindex = { status: "progress", containersScanned: 0, tracksFound: 0, currentContainer: "" };
            else
                showNotice(status === 409 ? "An index is already being built" : (json && json.error) || "Could not start indexing");
        });
    }

    function reindexText() {
        if (!reindex)
            return "";
        switch (reindex.status) {
        case "progress":
            return `Indexing… ${reindex.tracksFound} tracks in ${reindex.containersScanned} folders`;
        case "complete":
            return `Indexed ${reindex.trackCount} tracks on ${reindex.serverName}`;
        default:
            return `Indexing failed: ${reindex.error}`;
        }
    }

    Timer {
        id: noticeTimer
        interval: 4000
        onTriggered: view.notice = ""
    }

    component SectionTitle: KefLabel {
        Layout.fillWidth: true
        Layout.topMargin: 10
        font.pixelSize: 12
        font.bold: true
        font.capitalization: Font.AllUppercase
        color: Theme.primary
    }

    component Field: RowLayout {
        property string label: ""
        property string value: ""

        Layout.fillWidth: true
        visible: value !== ""
        spacing: 8

        KefLabel {
            Layout.preferredWidth: 150
            text: parent.label
            color: Theme.on_surface_variant
        }
        KefLabel {
            Layout.fillWidth: true
            text: parent.value
        }
    }

    ColumnLayout {
        id: column
        width: view.width - 12
        spacing: 6

        KefLabel {
            Layout.fillWidth: true
            visible: view.notice !== ""
            text: view.notice
            color: Theme.primary
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }

        // --- Speakers ---
        SectionTitle {
            Layout.topMargin: 0
            text: "Speakers"
        }

        Repeater {
            model: view.speakers

            Rectangle {
                id: speakerRow

                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 46
                radius: 8
                color: modelData.active ? Theme.secondary_container : speakerHover.hovered ? Theme.surface_container_high : "transparent"

                HoverHandler {
                    id: speakerHover
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !speakerRow.modelData.active
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.switchTo(speakerRow.modelData.ip)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 4
                    spacing: 8

                    MaterialIcon {
                        name: "speaker"
                        size: 20
                        color: speakerRow.modelData.active ? Theme.on_secondary_container : Theme.on_surface_variant
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        KefLabel {
                            Layout.fillWidth: true
                            text: speakerRow.modelData.name
                            font.bold: speakerRow.modelData.active
                        }
                        KefLabel {
                            Layout.fillWidth: true
                            text: [speakerRow.modelData.model, speakerRow.modelData.ip, speakerRow.modelData.active ? "active" : ""].filter(Boolean).join(" · ")
                            font.pixelSize: 11
                            color: Theme.on_surface_variant
                        }
                    }
                    IconButton {
                        icon: speakerRow.modelData.isDefault ? "star" : "star_border"
                        size: 32
                        checked: speakerRow.modelData.isDefault
                        onClicked: view.makeDefault(speakerRow.modelData.ip)
                    }
                }
            }
        }

        Repeater {
            model: view.discovered

            RowLayout {
                id: discoveredRow

                required property var modelData

                Layout.fillWidth: true
                spacing: 8

                KefLabel {
                    Layout.fillWidth: true
                    Layout.leftMargin: 10
                    text: `${discoveredRow.modelData.name} · ${discoveredRow.modelData.model} · ${discoveredRow.modelData.ip}`
                    color: Theme.on_surface_variant
                }
                PillButton {
                    icon: "add"
                    text: "Add"
                    onClicked: view.addSpeaker(discoveredRow.modelData.ip)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            PillButton {
                icon: "wifi_find"
                text: view.discovering ? "Searching…" : "Discover"
                enabled: !view.discovering
                onClicked: view.discover()
            }
            KefTextField {
                id: ipField
                Layout.fillWidth: true
                placeholderText: "Add by IP address"
                onAccepted: view.addSpeaker(text.trim())
            }
            IconButton {
                icon: "add"
                size: 34
                enabled: ipField.text.trim() !== ""
                onClicked: view.addSpeaker(ipField.text.trim())
            }
        }

        // --- Active speaker ---
        SectionTitle {
            text: "Speaker"
            visible: view.speakerSettings !== null
        }

        Field {
            label: "Model"
            value: view.speakerSettings ? view.speakerSettings.speaker.model : ""
        }
        Field {
            label: "IP address"
            value: view.speakerSettings ? view.speakerSettings.speaker.ip : ""
        }
        Field {
            label: "Firmware"
            value: view.speakerSettings ? view.speakerSettings.speaker.firmware : ""
        }
        Field {
            label: "MAC address"
            value: view.speakerSettings ? view.speakerSettings.speaker.macPrimary : ""
        }

        RowLayout {
            Layout.fillWidth: true
            visible: view.speakerSettings !== null
            spacing: 8

            KefLabel {
                Layout.preferredWidth: 150
                text: "Volume limit"
                color: Theme.on_surface_variant
            }
            KefSlider {
                id: maxVolume
                Layout.fillWidth: true
                from: 0
                to: 100
                stepSize: 1
                externalValue: view.speakerSettings ? view.speakerSettings.settings.maxVolume : 100
                onCommitted: value => view.setMaxVolume(value)
            }
            KefLabel {
                Layout.preferredWidth: 32
                horizontalAlignment: Text.AlignRight
                text: Math.round(maxVolume.value)
                color: Theme.on_surface_variant
            }
        }

        // --- EQ ---
        SectionTitle {
            text: "Sound"
            visible: view.eq !== null
        }
        KefLabel {
            Layout.fillWidth: true
            visible: view.eq !== null
            text: "Read-only here; change these in the KEF Connect app."
            font.pixelSize: 11
            color: Theme.on_surface_variant
        }

        Field {
            label: "Profile"
            value: view.eq ? view.eq.profileName || "Default" : ""
        }
        Field {
            label: "Mode"
            value: view.eq ? (view.eq.isExpertMode ? "Expert" : "Basic") : ""
        }
        Field {
            label: "Bass extension"
            value: view.eq ? view.eq.bassExtension : ""
        }
        Field {
            label: "Treble"
            value: view.eq ? `${view.eq.trebleAmount} dB` : ""
        }
        Field {
            label: "Balance"
            value: view.eq ? String(view.eq.balance) : ""
        }
        Field {
            label: "Desk mode"
            value: view.eq ? (view.eq.deskMode ? `On, ${view.eq.deskModeSetting} dB` : "Off") : ""
        }
        Field {
            label: "Wall mode"
            value: view.eq ? (view.eq.wallMode ? `On, ${view.eq.wallModeSetting} dB` : "Off") : ""
        }
        Field {
            label: "Phase correction"
            value: view.eq ? (view.eq.phaseCorrection ? "On" : "Off") : ""
        }
        Field {
            label: "Subwoofer"
            value: {
                if (!view.subwoofer)
                    return "";
                const s = view.subwoofer;
                if (!s.enabled || s.count === 0)
                    return "None";
                return `${s.count} × ${s.stereo ? "stereo" : "mono"}, ${s.preset}, ${s.gain} dB, ${s.polarity} polarity`;
            }
        }
        Field {
            label: "Crossover"
            value: {
                if (!view.subwoofer || !view.subwoofer.enabled || view.subwoofer.count === 0)
                    return "";
                const s = view.subwoofer;
                return `Low-pass ${s.lowPassFreq} Hz` + (s.highPassMode ? `, high-pass ${s.highPassFreq} Hz` : "");
            }
        }

        // --- Media library ---
        SectionTitle {
            text: "Media library"
        }

        KefLabel {
            Layout.fillWidth: true
            visible: view.servers.length === 0
            text: "No media servers found on the network."
            color: Theme.on_surface_variant
        }

        Flow {
            Layout.fillWidth: true
            visible: view.servers.length > 0
            spacing: 6

            Repeater {
                model: view.servers

                PillButton {
                    required property var modelData
                    icon: "dns"
                    text: modelData.name
                    selected: view.upnp.defaultServerPath === modelData.path
                    onClicked: view.selectServer(modelData)
                }
            }
        }

        Repeater {
            model: [
                { kind: "browse", key: "browseContainer", label: "Browse folder" },
                { kind: "index", key: "indexContainer", label: "Index folder" }
            ]

            RowLayout {
                id: folderRow

                required property var modelData

                Layout.fillWidth: true
                visible: view.upnp.defaultServerPath !== "" && view.picking === ""
                spacing: 8

                KefLabel {
                    Layout.preferredWidth: 150
                    text: folderRow.modelData.label
                    color: Theme.on_surface_variant
                }
                KefLabel {
                    Layout.fillWidth: true
                    text: view.upnp[folderRow.modelData.key] || "Whole server"
                }
                IconButton {
                    icon: "folder_open"
                    size: 32
                    onClicked: view.startPicking(folderRow.modelData.kind)
                }
                IconButton {
                    icon: "backspace"
                    size: 32
                    visible: view.upnp[folderRow.modelData.key] !== ""
                    onClicked: {
                        const changes = {};
                        changes[folderRow.modelData.key] = "";
                        view.saveUpnp(changes);
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: view.picking !== ""
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                IconButton {
                    icon: "arrow_back"
                    size: 32
                    enabled: view.pickTrail.length > 0
                    onClicked: {
                        view.pickTrail = view.pickTrail.slice(0, -1);
                        view.loadContainers();
                    }
                }
                KefLabel {
                    Layout.fillWidth: true
                    elide: Text.ElideLeft
                    text: [view.upnp.defaultServer].concat(view.pickTrail).join("  ›  ")
                }
                PillButton {
                    icon: "check"
                    text: "Use"
                    onClicked: view.usePickedFolder()
                }
                IconButton {
                    icon: "close"
                    size: 32
                    onClicked: view.picking = ""
                }
            }

            Repeater {
                model: view.pickContainers

                Rectangle {
                    id: folder

                    required property string modelData

                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: 6
                    color: folderMouse.containsMouse ? Theme.surface_container_high : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        spacing: 8

                        MaterialIcon {
                            name: "folder"
                            size: 18
                            color: Theme.on_surface_variant
                        }
                        KefLabel {
                            Layout.fillWidth: true
                            text: folder.modelData
                        }
                    }

                    MouseArea {
                        id: folderMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            view.pickTrail = view.pickTrail.concat([folder.modelData]);
                            view.loadContainers();
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: view.upnp.defaultServerPath !== ""
            spacing: 8

            PillButton {
                icon: "manage_search"
                text: "Rebuild index"
                enabled: !view.reindex || view.reindex.status !== "progress"
                onClicked: view.startReindex()
            }
            KefLabel {
                Layout.fillWidth: true
                text: view.reindexText()
                font.pixelSize: 11
                color: view.reindex && view.reindex.status === "error" ? Theme.error : Theme.on_surface_variant
            }
        }

        // --- About ---
        SectionTitle {
            text: "About"
        }
        Field {
            label: "Backend"
            value: view.serverInfo ? `kefw2ui on ${view.serverInfo.server.bind}:${view.serverInfo.server.port}` : ""
        }
        Field {
            label: "Live events"
            value: KefService.speakerConnected ? "Connected" : "Unavailable, polling every 2s while open"
        }
    }
}
