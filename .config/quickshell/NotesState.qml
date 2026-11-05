import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

QtObject {
    id: notes
    readonly property string helperPath: (Quickshell.env("HOME") || StandardPaths.writableLocation(StandardPaths.HomeLocation)) + "/.config/quickshell/Notes/store.py"
    property var items: []
    property int total: 0
    property string selectedId: ""
    property string title: ""
    property string content: ""
    property string query: ""
    property bool loaded: false
    property bool available: false
    property string error: ""
    property bool conflict: false
    property int revision: 0
    property int editSerial: 0
    property int savedSerial: 0
    readonly property bool dirty: selectedId !== "" && editSerial !== savedSerial
    readonly property bool busy: inFlight || worker.running
    readonly property bool saving: busy && requestKind === "save"
    readonly property bool editorBusy: busy && requestKind !== "save" && requestKind !== "list"
    readonly property string saveStatus: error ? "Changes need attention" : saving ? "Saving…" : dirty ? "Unsaved changes" : selectedId ? "Saved locally" : "Local notes"
    property bool inFlight: false
    property string requestKind: ""
    property var requestPayload: null
    property var response: null
    property int sentSerial: 0
    property int querySerial: 0
    property int sentQuerySerial: 0
    property var pendingIntent: null
    property bool refreshPending: false
    property bool ensureSelection: false
    property bool createIfEmpty: false
    property bool saveReady: false
    signal editorChanged()
    signal created()
    signal closedReady()

    function refresh() {
        error = "";
        refreshPending = true;
        ensureSelection = selectedId === "";
        createIfEmpty = selectedId === "";
        if (selectedId && !dirty && !pendingIntent) pendingIntent = { kind: "select", id: selectedId };
        pump();
    }
    function select(id) {
        if (!id || String(id) === selectedId) return;
        error = "";
        pendingIntent = { kind: "select", id: String(id) };
        pump();
    }
    function create() {
        error = "";
        pendingIntent = { kind: "create" };
        pump();
    }
    function updateTitle(text) {
        if (!selectedId || editorBusy || title === text) return;
        title = text;
        markEdited();
    }
    function updateBody(text) {
        if (!selectedId || editorBusy || content === text) return;
        content = text;
        markEdited();
    }
    function markEdited() {
        ++editSerial;
        saveReady = false;
        saveDelay.restart();
    }
    function saveNow() {
        if (conflict) {
            error = "This note changed elsewhere. Save a copy to keep your edits.";
            return;
        }
        error = "";
        saveDelay.stop();
        saveReady = true;
        pump();
    }
    function saveCopy() {
        if (!selectedId) return;
        error = "";
        pendingIntent = { kind: "copy" };
        pump();
    }
    function removeSelected() {
        if (!selectedId) return;
        error = "";
        pendingIntent = { kind: "delete", id: selectedId };
        pump();
    }
    function requestClose() {
        pendingIntent = { kind: "close" };
        if (conflict && dirty) {
            error = "Save a copy before closing to keep your edits.";
            return;
        }
        error = "";
        pump();
    }
    function loadEditor(note) {
        selectedId = String(note.id);
        title = String(note.title || "");
        content = String(note.content || "");
        revision = Number(note.revision || 1);
        editSerial = savedSerial = 0;
        conflict = false;
        saveReady = false;
        saveDelay.stop();
        editorChanged();
    }
    function clearEditor() {
        selectedId = "";
        title = content = "";
        editSerial = savedSerial = revision = 0;
        conflict = false;
        saveReady = false;
        saveDelay.stop();
        editorChanged();
    }
    function begin(kind, id, payload) {
        inFlight = true;
        requestKind = kind;
        requestPayload = payload;
        response = null;
        sentSerial = editSerial;
        sentQuerySerial = querySerial;
        var command = ["python3", helperPath, kind];
        if (kind === "list") command.push("--query=" + query.slice(0, 512));
        else if (id) command.push(String(id));
        worker.command = command;
        worker.stdinEnabled = payload !== null;
        worker.running = true;
    }
    function pump() {
        if (busy || error) return;
        var copying = pendingIntent && pendingIntent.kind === "copy";
        if (dirty && !copying && (saveReady || pendingIntent)) {
            if (conflict) {
                error = "This note changed elsewhere. Save a copy to keep your edits.";
                return;
            }
            saveReady = false;
            begin("save", selectedId, { title: title, content: content, expectedRevision: revision });
            return;
        }
        if (pendingIntent) {
            var intent = pendingIntent;
            pendingIntent = null;
            if (intent.kind === "close") { closedReady(); return; }
            if (intent.kind === "select") { begin("get", intent.id, null); return; }
            if (intent.kind === "delete") { begin("delete", intent.id, { expectedRevision: revision }); return; }
            if (intent.kind === "copy") { begin("create", "", { title: title, content: content }); return; }
            if (intent.kind === "create") { begin("create", "", { title: "", content: "" }); return; }
        }
        if (refreshPending) {
            refreshPending = false;
            begin("list", "", null);
        }
    }
    function finish(code) {
        var result = response;
        if (code !== 0 || !result || result.ok !== true) {
            conflict = result && result.code === "CONFLICT";
            error = result && result.error ? String(result.error) : "Notes could not be saved or loaded. Your current edits are still here.";
            if (conflict) error = "This note changed elsewhere. Save a copy to keep your edits.";
            if (!loaded) available = false;
            return;
        }
        if ((requestKind === "list" && !Array.isArray(result.notes))
            || (["get", "create", "save"].includes(requestKind) && (!result.note || typeof result.note.content !== "string"))) {
            error = "The notes response could not be read. Your current edits are still here.";
            return;
        }
        available = true;
        if (requestKind === "save") {
            revision = Number(result.note.revision);
            savedSerial = sentSerial;
            conflict = false;
            refreshPending = true;
        } else if (requestKind === "get" || requestKind === "create") {
            loadEditor(result.note);
            ensureSelection = false;
            createIfEmpty = false;
            if (requestKind === "create") { refreshPending = true; created(); }
        } else if (requestKind === "delete") {
            clearEditor();
            refreshPending = true;
            ensureSelection = true;
            createIfEmpty = false;
        } else if (requestKind === "list") {
            if (sentQuerySerial !== querySerial) { refreshPending = true; return; }
            if (JSON.stringify(items) !== JSON.stringify(result.notes)) items = result.notes;
            total = Number(result.total || 0);
            loaded = true;
            if (ensureSelection && !selectedId && !pendingIntent) {
                ensureSelection = false;
                if (items.length) pendingIntent = { kind: "select", id: String(items[0].id) };
                else if (createIfEmpty && !query.trim()) pendingIntent = { kind: "create" };
                createIfEmpty = false;
            }
        }
    }

    onQueryChanged: { ++querySerial; queryDelay.restart(); }
    property Timer queryDelay: Timer {
        interval: 150
        onTriggered: { notes.refreshPending = true; notes.pump(); }
    }
    property Timer saveDelay: Timer {
        interval: 650
        onTriggered: { notes.saveReady = true; notes.pump(); }
    }
    property Process worker: Process {
        onRunningChanged: if (!running && notes.inFlight) Qt.callLater(function() {
            // FailedToStart has no exited signal. Normal exit has cleared inFlight already.
            if (!worker.running && notes.inFlight) {
                notes.finish(-1);
                notes.inFlight = false;
            }
        })
        onStarted: {
            if (notes.requestPayload !== null) {
                write(JSON.stringify(notes.requestPayload));
                stdinEnabled = false;
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try { notes.response = JSON.parse(text); }
                catch (error) { notes.response = null; }
            }
        }
        stderr: StdioCollector { }
        onExited: function(code, status) {
            notes.finish(code);
            notes.inFlight = false;
            Qt.callLater(function() { notes.pump(); });
        }
    }
}
