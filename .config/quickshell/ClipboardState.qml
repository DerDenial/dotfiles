import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

QtObject {
    id: state

    property string helperPath: (Quickshell.env("HOME") || StandardPaths.writableLocation(StandardPaths.HomeLocation)) + "/.config/quickshell/Clipboard/store.py"
    property bool polling: false
    property string query: ""
    property string filter: "all"
    property var items: []
    property bool paused: false
    property bool available: false
    property bool watching: false
    property bool loaded: false
    property int total: 0
    property int pinnedCount: 0
    property string actionError: ""
    property string backendError: ""
    property string watcherError: ""
    readonly property string error: actionError || backendError || watcherError
    readonly property bool busy: action.running
    readonly property bool loading: listing.running
    readonly property bool queryPending: displayedRevision !== queryRevision

    property int queryRevision: 0
    property int displayedRevision: -1
    property int listingRevision: -1
    property bool refreshPending: false
    property bool listReceived: false
    property bool actionReceived: false
    property string actionName: ""
    property string actionId: ""
    property string itemsSignature: ""
    signal copied(string id)

    function refresh() {
        if (listing.running) {
            refreshPending = true;
            return;
        }
        refreshPending = false;
        listReceived = false;
        listingRevision = queryRevision;
        listing.command = ["python3", helperPath, "list", "--query=" + query.slice(0, 512), "--filter", filter];
        listing.running = true;
    }

    function perform(name, id) {
        if (busy || !available || queryPending) return;
        actionError = "";
        actionName = name;
        actionId = id || "";
        actionReceived = false;
        action.command = ["python3", helperPath, name].concat(id ? [String(id)] : []);
        action.running = true;
    }

    function copy(id) { perform("copy", id); }
    function togglePin(id) { perform("pin", id); }
    function remove(id) { perform("delete", id); }
    function clearUnpinned() { perform("clear", ""); }
    function togglePaused() { perform("pause", paused ? "off" : "on"); }
    function restartRecorder() {
        watcherError = "";
        if (!watcher.running) {
            watcherRestart.stop();
            watcher.running = true;
        }
        refresh();
    }

    function scheduleQuery() {
        ++queryRevision;
        queryDelay.restart();
    }

    onQueryChanged: scheduleQuery()
    onFilterChanged: scheduleQuery()
    onPollingChanged: if (polling) refresh()
    Component.onCompleted: refresh()

    property Timer queryDelay: Timer {
        interval: 90
        onTriggered: state.refresh()
    }
    property Timer pollingTimer: Timer {
        interval: 1200
        repeat: true
        running: state.polling
        onTriggered: state.refresh()
    }
    property Timer watcherRestart: Timer {
        interval: 3500
        onTriggered: state.watcher.running = true
    }

    // This process owns the recorder for this shell instance. The helper locks it
    // across reloads and only emits metadata; clipboard contents never enter logs.
    property Process watcher: Process {
        command: ["python3", state.helperPath, "watch"]
        running: true
        stdout: SplitParser {
            onRead: function(line) {
                try {
                    const info = JSON.parse(line);
                    if (info.ok === false || info.error) {
                        state.watcherError = String(info.error || "Clipboard recording is unavailable");
                    } else {
                        state.watcherError = "";
                    }
                    if (state.polling) state.refresh();
                } catch (e) { /* Ignore incomplete metadata without logging it. */ }
            }
        }
        stderr: StdioCollector { }
        onExited: function(exitCode, exitStatus) {
            if (exitCode !== 0 && !state.watcherError)
                state.watcherError = "Clipboard recorder could not start";
            state.watcherRestart.restart();
        }
    }

    property Process listing: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                if (state.listingRevision !== state.queryRevision) return;
                state.listReceived = true;
                try {
                    const info = JSON.parse(text);
                    if (info.ok !== true || !Array.isArray(info.items)) {
                        state.backendError = String(info.error || "Could not load clipboard history");
                        state.available = false;
                        return;
                    }
                    const signature = JSON.stringify(info.items);
                    if (signature !== state.itemsSignature) {
                        state.itemsSignature = signature;
                        state.items = info.items;
                    }
                    state.paused = Boolean(info.paused);
                    state.available = info.available !== false;
                    state.watching = info.watching !== false;
                    state.total = Number(info.total || 0);
                    state.pinnedCount = Number(info.pinnedCount || 0);
                    state.displayedRevision = state.listingRevision;
                    state.backendError = info.available === false ? "Install wl-clipboard to enable clipboard history" : "";
                    state.loaded = true;
                } catch (e) {
                    state.available = false;
                    state.backendError = "Could not load clipboard history";
                }
            }
        }
        stderr: StdioCollector { }
        onExited: function(exitCode, exitStatus) {
            if (state.listingRevision === state.queryRevision && (!state.listReceived || exitCode !== 0)) {
                state.available = false;
                if (!state.backendError) state.backendError = "Clipboard history is unavailable";
            }
            if (state.refreshPending || state.listingRevision !== state.queryRevision)
                Qt.callLater(function() { state.refresh(); });
        }
    }

    property Process action: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                state.actionReceived = true;
                try {
                    const info = JSON.parse(text);
                    if (info.ok !== true) {
                        state.actionError = String(info.error || "The clipboard action failed");
                    } else if (state.actionName === "copy") {
                        state.copied(state.actionId);
                    }
                } catch (e) { state.actionError = "The clipboard action failed"; }
            }
        }
        stderr: StdioCollector { }
        onExited: function(exitCode, exitStatus) {
            if ((!state.actionReceived || exitCode !== 0) && !state.actionError)
                state.actionError = "The clipboard action failed";
            state.refresh();
        }
    }
}
