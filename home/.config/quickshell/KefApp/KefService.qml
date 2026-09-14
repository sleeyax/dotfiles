pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property int port: 18080
    readonly property string baseUrl: "http://127.0.0.1:" + port

    property bool panelOpen: false

    property bool backendUp: false
    property bool backendFailed: false
    property bool speakerConnected: false

    property string speakerName: ""
    property string speakerIp: ""
    property string speakerModel: ""

    property int volume: 0
    property bool muted: false
    property string source: ""
    property string powerStatus: ""
    readonly property bool standby: source === "standby" || powerStatus === "standby"

    property string playState: "stopped"
    readonly property bool playing: playState === "playing"
    property string title: ""
    property string artist: ""
    property string album: ""
    property string icon: ""
    property int duration: 0
    property int position: 0
    property string audioType: ""
    property bool live: false
    readonly property bool isLive: live || audioType === "audioBroadcast"
    readonly property string iconUrl: resolveUrl(icon)

    property bool shuffle: false
    property string repeatMode: "off"

    property var queueTracks: []
    property int queueIndex: -1

    // Set whenever the panel opens, so the queue and play mode are fetched once a fresh /api/player has confirmed the speaker is awake.
    property bool awakeStateStale: true

    property var playlists: []

    signal reindexUpdated(var data)

    function resolveUrl(url) {
        if (!url)
            return "";
        return url.startsWith("/") ? baseUrl + url : url;
    }

    function formatTime(ms) {
        const total = Math.max(0, Math.floor(ms / 1000));
        const h = Math.floor(total / 3600);
        const m = Math.floor(total / 60) % 60;
        const s = String(total % 60).padStart(2, "0");
        return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${s}` : `${m}:${s}`;
    }

    function request(method, path, body, callback) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            let json = null;
            try {
                json = xhr.responseText ? JSON.parse(xhr.responseText) : null;
            } catch (e) {}
            const ok = xhr.status >= 200 && xhr.status < 300;
            if (!ok && xhr.status !== 0)
                console.warn(`kef: ${method} ${path} -> ${xhr.status} ${xhr.responseText}`);
            if (callback)
                callback(ok, json, xhr.status);
        };
        xhr.open(method, baseUrl + path);
        if (body !== undefined && body !== null) {
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.send(JSON.stringify(body));
        } else {
            xhr.send();
        }
    }

    function get(path, callback) { request("GET", path, null, callback); }
    function post(path, body, callback) { request("POST", path, body === undefined ? {} : body, callback); }

    // --- Backend lifecycle ---

    function ensureBackend() {
        if (backendUp)
            return;
        backendFailed = false;
        get("/api/health", ok => {
            if (ok) {
                markBackendUp();
                return;
            }
            if (!backendProcess.running)
                backendProcess.running = true;
            healthPoll.attempts = 0;
            healthPoll.start();
        });
    }

    function markBackendUp() {
        healthPoll.stop();
        backendUp = true;
        events.running = true;
        refreshState();
    }

    Process {
        id: backendProcess
        command: ["kefw2ui", "-bind", "127.0.0.1", "-port", String(root.port), "-no-discovery"]
        onRunningChanged: {
            if (!running && root.backendUp) {
                root.backendUp = false;
                events.running = false;
            }
        }
    }

    Timer {
        id: healthPoll
        property int attempts: 0
        interval: 250
        repeat: true
        onTriggered: {
            if (++attempts > 40) {
                stop();
                root.backendFailed = true;
                console.warn("kef: backend did not answer on " + root.baseUrl);
                return;
            }
            root.get("/api/health", ok => {
                if (ok && !root.backendUp)
                    root.markBackendUp();
            });
        }
    }

    // --- Event stream ---

    Process {
        id: events
        command: ["curl", "-sN", root.baseUrl + "/events"]
        stdout: SplitParser {
            onRead: line => root.handleLine(line)
        }
        onRunningChanged: {
            if (running)
                watchdog.restart();
            else if (root.backendUp)
                reconnect.start();
        }
    }

    // The server pings every 30s, so a silent stream is a dead one.
    Timer {
        id: watchdog
        interval: 45000
        onTriggered: events.running = false
    }

    Timer {
        id: reconnect
        interval: 2000
        onTriggered: {
            root.backendUp = false;
            root.ensureBackend();
        }
    }

    function handleLine(line) {
        watchdog.restart();
        if (!line.startsWith("data:"))
            return;
        let msg;
        try {
            msg = JSON.parse(line.slice(5));
        } catch (e) {
            return;
        }
        if (msg.type)
            applyEvent(msg.type, msg.data || {});
    }

    function applyEvent(type, d) {
        switch (type) {
        case "volume":
            volume = d.volume;
            break;
        case "mute":
            muted = d.muted;
            break;
        case "source":
            source = d.source;
            break;
        case "power":
            powerStatus = d.status;
            break;
        case "player":
            applyPlayer(d);
            // Live track events omit audioType and live, which would otherwise stay stale across a switch between radio and a track.
            if (d.position === undefined)
                playerRefresh.restart();
            break;
        case "playTime":
            position = Math.max(0, d.position);
            break;
        case "speaker":
            speakerName = d.name || "";
            speakerIp = d.ip || "";
            speakerModel = d.model || "";
            break;
        case "speakerHealth":
            speakerConnected = d.connected;
            // A speaker that connects after the stream opened never gets a snapshot.
            if (d.connected)
                refreshState();
            break;
        case "queue":
            refreshQueue();
            break;
        case "playMode":
            refreshPlayMode();
            break;
        case "playlists":
            refreshPlaylists();
            break;
        case "reindex":
            reindexUpdated(d);
            break;
        }
    }

    function applyPlayer(d) {
        if (d.state !== undefined) playState = d.state;
        if (d.title !== undefined) title = d.title;
        if (d.artist !== undefined) artist = d.artist;
        if (d.album !== undefined) album = d.album;
        if (d.icon !== undefined) icon = d.icon;
        if (d.duration !== undefined) duration = d.duration;
        if (d.position !== undefined) position = Math.max(0, d.position);
        if (d.audioType !== undefined) audioType = d.audioType;
        if (d.live !== undefined) live = d.live;
        if (d.volume !== undefined) volume = d.volume;
        if (d.muted !== undefined) muted = d.muted;
        if (d.source !== undefined) source = d.source;
    }

    Timer {
        id: playerRefresh
        interval: 300
        onTriggered: root.refreshPlayer()
    }

    // speakerConnected is false when the backend could not subscribe to the speaker's events, which firmware V26120 refuses to kefw2ui 0.0.3, so /events only ever carries the snapshot.
    Timer {
        interval: 2000
        repeat: true
        running: root.backendUp && !root.speakerConnected && root.panelOpen
        onTriggered: root.refreshPlayer()
    }

    // The speaker reports playTime irregularly, so the position advances locally between reports.
    Timer {
        interval: 1000
        repeat: true
        running: root.playing && !root.isLive && root.duration > 0
        onTriggered: root.position = Math.min(root.duration, root.position + 1000)
    }

    // Both endpoints answer from cache while the speaker is in standby instead of waking it.
    function refreshState() {
        get("/api/speaker", (ok, json) => {
            if (!ok || !json || !json.active)
                return;
            const a = json.active;
            speakerName = a.name || "";
            speakerIp = a.ip || "";
            speakerModel = a.model || "";
            powerStatus = a.status || powerStatus;
        });
        refreshPlayer();
    }

    function refreshPlayer() {
        get("/api/player", (ok, json) => {
            if (!ok || !json)
                return;
            applyPlayer(json);
            if (panelOpen && !standby && awakeStateStale)
                refreshAwakeState();
        });
    }

    function refreshAwakeState() {
        awakeStateStale = false;
        refreshPlayMode();
        refreshQueue();
    }

    // Unlike /api/player, the queue endpoints query the speaker directly and would wake it from standby.
    function refreshPlayMode() {
        if (standby)
            return;
        get("/api/queue/mode", applyPlayMode);
    }

    function applyPlayMode(ok, json) {
        if (!ok || !json)
            return;
        shuffle = json.shuffle;
        repeatMode = json.repeat;
    }

    function setShuffle(on) {
        shuffle = on;
        post("/api/queue/mode", { shuffle: on }, applyPlayMode);
    }

    function cycleRepeat() {
        const next = { off: "all", all: "one", one: "off" }[repeatMode] || "off";
        repeatMode = next;
        post("/api/queue/mode", { repeat: next }, applyPlayMode);
    }

    function refreshQueue() {
        if (standby)
            return;
        get("/api/queue", (ok, json) => {
            if (!ok || !json)
                return;
            queueTracks = json.tracks || [];
            queueIndex = json.currentIndex;
        });
    }

    // The server resolves indices against a queue it re-reads, so every change is followed by a refresh rather than patched locally.
    function playQueueItem(index) { post("/api/queue/play", { index: index }, refreshQueue); }
    function removeQueueItem(index) { post("/api/queue/remove", { indices: [index] }, refreshQueue); }
    function clearQueue() { post("/api/queue/clear", {}, refreshQueue); }

    function moveQueueItem(from, to) {
        if (to < 0 || to >= queueTracks.length)
            return;
        post("/api/queue/move", { from: from, to: to }, refreshQueue);
    }

    function saveQueueAsPlaylist(name, callback) {
        post("/api/playlists/save-queue", { name: name }, (ok, json) => callback(ok, json && json.error));
    }

    // --- Browsing ---

    function browse(source, path, query, callback) {
        let url = `/api/browse/${source}`;
        if (query)
            url += "?q=" + encodeURIComponent(query);
        else if (path)
            url += "?path=" + encodeURIComponent(path);
        get(url, callback);
    }

    // The server needs mediaData to queue a radio or podcast item without a lookup of its own.
    function browseBody(source, item) {
        return {
            source: source,
            path: item.path,
            type: item.type,
            title: item.title,
            icon: item.icon,
            id: item.id,
            artist: item.artist,
            album: item.album,
            audioType: item.audioType,
            mediaData: item.mediaData,
            containerPath: item.containerPath
        };
    }

    function playBrowseItem(source, item) {
        post("/api/browse/play", browseBody(source, item), ok => {
            if (ok)
                playerRefresh.restart();
        });
    }

    function queueBrowseItem(source, item, callback) {
        post("/api/browse/queue", browseBody(source, item), (ok, json) => {
            if (ok)
                refreshQueue();
            callback(ok, json);
        });
    }

    function favoriteBrowseItem(source, item, add, callback) {
        post("/api/browse/favorite", { source: source, path: item.path, id: item.id, title: item.title, add: add }, callback);
    }

    // --- Playlists ---

    // Playlists are files kept by the backend, so unlike the queue they can be read while the speaker is in standby.
    function refreshPlaylists() {
        get("/api/playlists", (ok, json) => {
            if (ok && json)
                playlists = json.playlists || [];
        });
    }

    function getPlaylist(id, callback) {
        get(`/api/playlists/${encodeURIComponent(id)}`, callback);
    }

    function createPlaylist(name, tracks, callback) {
        post("/api/playlists", { name: name, tracks: tracks }, (ok, json) => {
            if (ok)
                refreshPlaylists();
            callback(ok, json);
        });
    }

    function updatePlaylist(id, playlist, callback) {
        request("PUT", `/api/playlists/${encodeURIComponent(id)}`, playlist, (ok, json) => {
            if (ok)
                refreshPlaylists();
            callback(ok, json);
        });
    }

    function deletePlaylist(id, callback) {
        request("DELETE", `/api/playlists/${encodeURIComponent(id)}`, null, ok => {
            if (ok)
                refreshPlaylists();
            callback(ok);
        });
    }

    function loadPlaylist(id, append, callback) {
        post(`/api/playlists/load/${encodeURIComponent(id)}`, { append: append }, (ok, json) => {
            if (ok) {
                refreshQueue();
                playerRefresh.restart();
            }
            callback(ok, json);
        });
    }

    // A track with a uri plays without the speaker looking its path up first, and a browse item only carries that uri inside mediaData.
    function trackFromBrowseItem(item) {
        const media = item.mediaData || {};
        const resource = (media.resources || [])[0] || {};
        const meta = media.metaData || {};
        return {
            title: item.title,
            artist: item.artist,
            album: item.album,
            duration: item.duration || resource.duration,
            icon: item.icon,
            path: item.path,
            id: item.id,
            type: item.type,
            uri: resource.uri,
            mimeType: resource.mimeType,
            serviceId: meta.serviceID
        };
    }

    function addTrackToPlaylist(id, track, callback) {
        getPlaylist(id, (ok, json) => {
            if (!ok || !json) {
                callback(false);
                return;
            }
            const playlist = json.playlist;
            updatePlaylist(id, {
                name: playlist.name,
                description: playlist.description || "",
                tracks: (playlist.tracks || []).concat([track])
            }, updated => callback(updated));
        });
    }

    // --- Commands ---

    function playPause() { post("/api/player/play"); }
    function stop() { post("/api/player/stop"); }
    function next() { post("/api/player/next"); }
    function previous() { post("/api/player/prev"); }

    function playOrStop() {
        if (isLive && playing)
            stop();
        else
            playPause();
    }

    function seek(ms) {
        position = ms;
        post("/api/player/seek", { positionMs: Math.max(0, Math.round(ms)) });
    }

    function setVolume(v) {
        const clamped = Math.max(0, Math.min(100, Math.round(v)));
        volume = clamped;
        post("/api/player/volume", { volume: clamped });
    }

    function changeVolume(delta) { setVolume(volume + delta); }

    function setMuted(m) {
        muted = m;
        post("/api/player/mute", { muted: m });
    }

    function setSource(s) {
        source = s;
        post("/api/player/source", { source: s });
    }

    function setPower(on) {
        post("/api/player/power", { powerOn: on }, (ok, json) => {
            if (ok && json)
                powerStatus = json.status;
            if (ok && on)
                refreshState();
        });
    }

    IpcHandler {
        target: "kef"
        function toggle(): void { root.panelOpen = !root.panelOpen }
        function open(): void { root.panelOpen = true }
        function close(): void { root.panelOpen = false }
        function isOpen(): bool { return root.panelOpen }
        function playPause(): void { root.ensureBackend(); root.playOrStop() }
        function next(): void { root.ensureBackend(); root.next() }
        function previous(): void { root.ensureBackend(); root.previous() }
        function volumeUp(): void { root.ensureBackend(); root.changeVolume(2) }
        function volumeDown(): void { root.ensureBackend(); root.changeVolume(-2) }
        function toggleMute(): void { root.ensureBackend(); root.setMuted(!root.muted) }
        function connect(): void { root.ensureBackend() }
        function status(): string {
            return JSON.stringify({
                backendUp: root.backendUp,
                backendFailed: root.backendFailed,
                speakerConnected: root.speakerConnected,
                speaker: root.speakerName,
                source: root.source,
                power: root.powerStatus,
                volume: root.volume,
                muted: root.muted,
                state: root.playState,
                title: root.title,
                artist: root.artist,
                position: root.position,
                duration: root.duration,
                live: root.isLive
            })
        }
    }

    onPanelOpenChanged: {
        if (!panelOpen)
            return;
        awakeStateStale = true;
        if (backendUp)
            refreshPlayer();
        else
            ensureBackend();
    }

    onStandbyChanged: {
        if (panelOpen && !standby && source !== "")
            refreshAwakeState();
    }

    // The current queue index only moves with the track.
    onTitleChanged: {
        if (panelOpen)
            refreshQueue();
    }
}
