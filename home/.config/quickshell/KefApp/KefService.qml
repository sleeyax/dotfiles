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

    signal queueUpdated()
    signal playModeUpdated(string mode)
    signal playlistsUpdated()
    signal reindexUpdated(var data)
    signal stateRefreshed()

    function resolveUrl(url) {
        if (!url)
            return "";
        return url.startsWith("/") ? baseUrl + url : url;
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
            queueUpdated();
            break;
        case "playMode":
            playModeUpdated(d.mode || "");
            break;
        case "playlists":
            playlistsUpdated();
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
            stateRefreshed();
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

    onPanelOpenChanged: if (panelOpen) ensureBackend()
}
