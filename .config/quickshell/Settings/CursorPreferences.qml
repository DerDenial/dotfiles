import QtQuick
import Quickshell
import Quickshell.Io

// The controller belongs to SettingsApp, outside its disposable visual pages.
QtObject {
    id: preferences
    property var info: ({ themes: [], current: { theme: "", size: 24 }, saved: false, warnings: [] })
    property string readError: ""
    property string writeError: ""
    readonly property string error: writeError || readError
    property bool reading: false
    property bool writing: false
    property string readReply: ""
    property string writeReply: ""
    readonly property bool busy: writing || writer.running
    readonly property bool loading: reading || reader.running
    readonly property string helper: Quickshell.env("HOME") + "/.config/quickshell/Settings/cursor_preferences.py"
    signal applied()

    function validReply(value) {
        return value && Array.isArray(value.themes) && value.current
            && typeof value.current.theme === "string"
            && Number.isInteger(value.current.size) && typeof value.saved === "boolean"
            && Array.isArray(value.warnings);
    }
    function refresh() {
        if (busy || loading) return;
        reading = true;
        readReply = "";
        reader.running = true;
    }
    function apply(theme, size) {
        if (busy || loading) return;
        if (!info.themes.some(entry => entry.id === theme)
                || ![16, 24, 32, 40, 48, 64].includes(Number(size))) {
            writeError = "Choose an installed cursor theme and a supported size.";
            return;
        }
        writeError = "";
        writing = true;
        writeReply = "";
        writer.command = ["python3", helper, "set", theme, String(size)];
        writer.running = true;
    }
    function finishRead(code, status) {
        if (!reading) return;
        reading = false;
        try {
            const result = JSON.parse(readReply);
            if (code !== 0 || status !== 0 || result.error || !validReply(result))
                throw new Error(result.error || "Could not load cursor themes.");
            info = result;
            readError = "";
        } catch (exception) { readError = String(exception.message || "Could not load cursor themes."); }
    }
    function finishWrite(code, status) {
        if (!writing) return;
        writing = false;
        try {
            const result = JSON.parse(writeReply);
            if (code !== 0 || status !== 0 || result.ok !== true || result.error || !validReply(result))
                throw new Error(result.error || "Could not apply the cursor. Please try again.");
            info = result;
            readError = "";
            applied();
        } catch (exception) { writeError = String(exception.message || "Could not apply the cursor. Please try again."); }
    }
    property Process reader: Process {
        command: ["python3", preferences.helper, "get"]
        stdout: StdioCollector { onStreamFinished: preferences.readReply = text }
        stderr: StdioCollector {}
        onExited: (code, status) => preferences.finishRead(code, status)
        onRunningChanged: if (!running && preferences.reading) Qt.callLater(function() {
            if (!reader.running && preferences.reading) preferences.finishRead(-1, -1);
        })
    }
    property Process writer: Process {
        stdout: StdioCollector { onStreamFinished: preferences.writeReply = text }
        stderr: StdioCollector {}
        onExited: (code, status) => preferences.finishWrite(code, status)
        onRunningChanged: if (!running && preferences.writing) Qt.callLater(function() {
            if (!writer.running && preferences.writing) preferences.finishWrite(-1, -1);
        })
    }
}
