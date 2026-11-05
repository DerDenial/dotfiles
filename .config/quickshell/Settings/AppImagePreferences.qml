import QtQuick
import Quickshell
import Quickshell.Io

// Keep this controller on SettingsApp so an installation survives page disposal.
QtObject {
    id: preferences
    property var info: ({ apps: [], warnings: [] })
    property var candidate: null
    property string error: ""
    property string operation: ""
    property string readReply: ""
    property string inspectReply: ""
    property string writeReply: ""
    readonly property bool loading: operation === "list"
    readonly property bool inspecting: operation === "inspect"
    readonly property bool writing: operation === "apply" || operation === "restore"
    readonly property bool busy: operation.length > 0 || reader.running || inspector.running || writer.running
    readonly property string helper: Quickshell.env("HOME") + "/.config/quickshell/Settings/appimage_manager.py"
    signal applied(string message)

    function validApp(app) {
        return app && typeof app.id === "string" && typeof app.name === "string"
            && typeof app.path === "string" && typeof app.icon === "string"
            && typeof app.architecture === "string" && typeof app.version === "string"
            && typeof app.executable === "boolean" && typeof app.managed === "boolean"
            && typeof app.canRollback === "boolean";
    }
    function validReply(reply) {
        return reply && reply.ok === true && Array.isArray(reply.apps)
            && reply.apps.every(validApp) && Array.isArray(reply.warnings)
            && reply.warnings.every(value => typeof value === "string");
    }
    function validCandidate(value) {
        return value && typeof value.token === "string" && typeof value.path === "string"
            && typeof value.name === "string" && typeof value.version === "string"
            && typeof value.architecture === "string" && typeof value.compatible === "boolean"
            && typeof value.icon === "string" && typeof value.targetPath === "string"
            && (value.operation === "install" || value.operation === "update");
    }
    function refresh() {
        if (busy) return;
        error = "";
        readReply = "";
        operation = "list";
        reader.running = true;
    }
    function inspect(path, targetId) {
        if (busy || typeof path !== "string" || !path.length) return;
        error = "";
        candidate = null;
        inspectReply = "";
        operation = "inspect";
        inspector.command = ["python3", helper, "inspect", path];
        if (targetId) inspector.command = inspector.command.concat([targetId]);
        inspector.running = true;
    }
    function discard() {
        if (!busy) { candidate = null; error = ""; }
    }
    function apply() {
        if (busy || !candidate || !candidate.compatible || !candidate.token) return;
        error = "";
        writeReply = "";
        operation = "apply";
        writer.command = ["python3", helper, "apply", candidate.token];
        writer.running = true;
    }
    function restore(id) {
        if (busy || !info.apps.some(app => app.id === id && app.canRollback)) return;
        error = "";
        candidate = null;
        writeReply = "";
        operation = "restore";
        writer.command = ["python3", helper, "restore", id];
        writer.running = true;
    }
    function finish(kind, code, status, text) {
        if (operation !== kind) return;
        try {
            const reply = JSON.parse(text);
            if (code !== 0 || status !== 0 || reply.ok !== true || !validReply(reply))
                throw new Error(reply.error || "The AppImage operation could not be completed.");
            if (kind === "inspect" && !validCandidate(reply.candidate))
                throw new Error("Could not read the selected AppImage.");
            info = reply;
            if (kind === "inspect") candidate = reply.candidate;
            if (kind === "apply" || kind === "restore") {
                candidate = null;
                applied(typeof reply.message === "string" ? reply.message : kind === "restore" ? "Previous version restored" : "AppImage installed");
            }
            error = "";
        } catch (exception) {
            error = String(exception.message || "The AppImage operation could not be completed.");
            // A failed apply may have invalidated its review token. Reinspect it.
            if (kind === "apply") candidate = null;
        }
        operation = "";
    }
    property Process reader: Process {
        command: ["python3", preferences.helper, "list"]
        stdout: StdioCollector { onStreamFinished: preferences.readReply = text }
        stderr: StdioCollector { }
        onExited: (code, status) => preferences.finish("list", code, status, preferences.readReply)
        onRunningChanged: if (!running && preferences.operation === "list") Qt.callLater(function() {
            if (!reader.running && preferences.operation === "list") preferences.finish("list", -1, -1, preferences.readReply);
        })
    }
    property Process inspector: Process {
        stdout: StdioCollector { onStreamFinished: preferences.inspectReply = text }
        stderr: StdioCollector { }
        onExited: (code, status) => preferences.finish("inspect", code, status, preferences.inspectReply)
        onRunningChanged: if (!running && preferences.operation === "inspect") Qt.callLater(function() {
            if (!inspector.running && preferences.operation === "inspect") preferences.finish("inspect", -1, -1, preferences.inspectReply);
        })
    }
    property Process writer: Process {
        stdout: StdioCollector { onStreamFinished: preferences.writeReply = text }
        stderr: StdioCollector { }
        onExited: (code, status) => preferences.finish(preferences.operation, code, status, preferences.writeReply)
        onRunningChanged: if (!running && preferences.writing) Qt.callLater(function() {
            if (!writer.running && preferences.writing) preferences.finish(preferences.operation, -1, -1, preferences.writeReply);
        })
    }
}
