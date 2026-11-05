import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

QtObject {
    id: state
    readonly property string helperPath: (Quickshell.env("HOME") || StandardPaths.writableLocation(StandardPaths.HomeLocation)) + "/.config/quickshell/Shelf/store.py"
    property var items: []
    property bool loaded: false
    property bool available: false
    property string error: ""
    property string notice: ""
    readonly property bool busy: inFlight || worker.running
    readonly property int count: items.length
    property bool dragging: false
    property bool nativeDragStarted: false
    property bool finishingDrag: false
    property string dragId: ""
    property var requests: []
    property bool inFlight: false
    property string requestKind: ""
    property var requestPayload: null
    property var response: null
    property var heldResponse: null
    signal dragEnded()

    function enqueue(kind, payload) {
        if (kind === "list" && (requestKind === "list" && busy || requests.some(r => r.kind === "list"))) return true;
        if (requests.length >= 16) { error = "Please wait for the shelf to finish updating."; return false; }
        error = "";
        requests = requests.concat([{ kind: kind, payload: payload }]);
        pump();
        return true;
    }
    function refresh() { return enqueue("list", null); }
    function addUrls(urls) {
        if (!Array.isArray(urls) || !urls.length || dragging) return false;
        return enqueue("add", { urls: urls.slice(0, 256).map(url => String(url)) });
    }
    function remove(id) { return enqueue("remove", { ids: [String(id)] }); }
    function clear() { return enqueue("clear", null); }
    function pump() {
        if (busy || dragging || !requests.length) return;
        const next = requests[0];
        requests = requests.slice(1);
        requestKind = next.kind;
        requestPayload = next.payload;
        response = null;
        inFlight = true;
        worker.command = ["python3", helperPath, requestKind];
        worker.stdinEnabled = requestPayload !== null;
        worker.running = true;
    }
    function applyResult(result) {
        if (!result || result.ok !== true || !Array.isArray(result.items)) {
            error = result && result.error ? String(result.error) : "The shelf could not be updated.";
            if (!loaded) available = false;
            return;
        }
        const valid = result.items.every(item => item && /^[0-9a-f]{64}$/.test(String(item.id))
            && typeof item.fileUrl === "string" && item.fileUrl.startsWith("file://")
            && typeof item.name === "string");
        if (!valid) { error = "The shelf response could not be read."; return; }
        // Replacing a model would destroy the native drag source. Hold it until
        // DragFinished has unwound, including responses started before a drag.
        if (dragging) { heldResponse = result; return; }
        if (JSON.stringify(items) !== JSON.stringify(result.items)) items = result.items;
        loaded = available = true;
        error = "";
        notice = result.skipped > 0 ? "Some items were already on the shelf or could not be added." : "";
    }
    function finish(code) {
        operationDeadline.stop();
        if (code !== 0 && (!response || response.ok !== false)) {
            error = "The shelf could not be updated. Please try again.";
        } else applyResult(response);
        requestKind = "";
        inFlight = false;
        Qt.callLater(pump);
    }
    function beginDrag(id) {
        const entry = items.find(item => item.id === id);
        if (dragging || busy || !entry || entry.missing) return false;
        dragId = id;
        nativeDragStarted = finishingDrag = false;
        dragging = true;
        dragStartGuard.restart();
        return true;
    }
    function markDragStarted() {
        if (!dragging) return;
        nativeDragStarted = true;
        dragStartGuard.stop();
    }
    function endDrag(action) {
        if (!dragging || finishingDrag) return;
        dragStartGuard.stop();
        finishingDrag = true;
        // Preserve the delegate until its DragFinished signal returns to Qt.
        Qt.callLater(function() {
            dragging = nativeDragStarted = finishingDrag = false;
            dragId = "";
            if (heldResponse) {
                const result = heldResponse;
                heldResponse = null;
                applyResult(result);
            }
            dragEnded();
            pump();
        });
    }
    Component.onCompleted: refresh()

    property Timer dragStartGuard: Timer {
        interval: 1000
        onTriggered: if (state.dragging && !state.nativeDragStarted) state.endDrag(Qt.IgnoreAction)
    }
    property Timer operationDeadline: Timer {
        interval: 5000
        onTriggered: {
            if (!state.inFlight) return;
            state.error = "The shelf is taking too long to respond.";
            if (state.worker.running) state.worker.signal(15);
        }
    }
    property Process worker: Process {
        onStarted: {
            state.operationDeadline.restart();
            if (state.requestPayload !== null) {
                write(JSON.stringify(state.requestPayload) + "\n");
                stdinEnabled = false;
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try { state.response = JSON.parse(text); }
                catch (e) { state.response = null; }
            }
        }
        stderr: StdioCollector { }
        onExited: (code, status) => state.finish(status === 0 ? code : -1)
        onRunningChanged: if (!running && state.inFlight) Qt.callLater(function() {
            if (!worker.running && state.inFlight) state.finish(-1);
        })
    }
}
