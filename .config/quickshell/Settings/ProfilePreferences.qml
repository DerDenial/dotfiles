import QtQuick
import Quickshell
import Quickshell.Io

// SettingsApp owns this finite worker; closing Appearance never cancels a save.
QtObject {
    id: preferences
    property var info: ({ ok: true, current: { sourcePath: "", fileUrl: "", hasImage: false, mode: "auto" }, warnings: [] })
    readonly property var current: info.current
    readonly property var warnings: info.warnings
    property string error: ""
    property string operation: ""
    property string reply: ""
    property string terminalError: ""
    property bool ownsProcess: false
    property int generation: 0
    readonly property bool busy: ownsProcess || runner.running
    readonly property bool loading: ownsProcess && operation === "get"
    readonly property bool writing: ownsProcess && operation !== "get"
    readonly property string python: Quickshell.env("HOME") + "/.config/quickshell/material-runtime/bin/python"
    readonly property string helper: Quickshell.env("HOME") + "/.config/quickshell/profile-avatar.py"
    signal applied(string message)

    function validReply(value) {
        return value && typeof value.ok === "boolean" && value.current
            && typeof value.current.sourcePath === "string" && value.current.sourcePath.length <= 16384
            && typeof value.current.fileUrl === "string" && value.current.fileUrl.length <= 16384
            && typeof value.current.hasImage === "boolean"
            && (!value.current.hasImage || value.current.fileUrl.startsWith("file:"))
            && ["auto", "selected", "cleared"].includes(value.current.mode)
            && Array.isArray(value.warnings)
            && value.warnings.every(message => typeof message === "string" && message.length <= 4096);
    }
    function start(kind, argumentsList) {
        if (busy) return false;
        error = "";
        terminalError = "";
        reply = "";
        operation = kind;
        generation++;
        ownsProcess = true;
        runner.command = [python, helper].concat(argumentsList);
        startupTimeout.restart();
        totalTimeout.restart();
        runner.running = true;
        return true;
    }
    function refresh() { return start("get", ["get"]); }
    function setPicture(path) {
        if (busy) return false;
        if (typeof path !== "string" || !path.startsWith("/") || !/\.(png|jpe?g|webp)$/i.test(path)) {
            error = "Choose a PNG, JPG, JPEG or WebP picture using its full path.";
            return false;
        }
        return start("set", ["set", path]);
    }
    function removePicture() { return start("clear", ["clear"]); }
    function finish(code, status) {
        if (!ownsProcess) return;
        startupTimeout.stop();
        totalTimeout.stop();
        stopTimeout.stop();
        const finishedOperation = operation;
        let saved = false;
        try {
            if (terminalError) throw new Error(terminalError);
            if (reply.length > 65536) throw new Error("Could not read the profile picture result.");
            let result;
            try { result = JSON.parse(reply); }
            catch (parseError) { throw new Error("Could not read the profile picture result. Please try again."); }
            if (!validReply(result)) throw new Error("Could not read the profile picture result.");
            // Even a rejected write returns the authoritative, unchanged current picture.
            info = result;
            if (code !== 0 || status !== 0 || !result.ok || result.error)
                throw new Error(typeof result.error === "string" ? result.error : "Could not update your profile picture. Please try again.");
            error = "";
            saved = finishedOperation !== "get";
        } catch (exception) {
            error = terminalError || String(exception.message || "Could not load your profile picture. Please try again.");
        }
        operation = "";
        ownsProcess = false;
        if (saved) applied(finishedOperation === "clear" ? "Profile picture removed" : "Profile picture updated");
    }
    function abort(message) {
        if (!ownsProcess || terminalError) return;
        terminalError = message;
        error = message;
        startupTimeout.stop();
        totalTimeout.stop();
        if (runner.running && runner.processId > 0) {
            runner.signal(15);
            stopTimeout.restart();
        } else {
            // A spawn that never obtained a PID must not receive a process signal.
            runner.running = false;
            finish(-1, -1);
        }
    }
    Component.onDestruction: {
        if (ownsProcess && runner.running && runner.processId > 0) runner.signal(15);
    }
    property Process runner: Process {
        stdout: StdioCollector { onStreamFinished: preferences.reply = text }
        stderr: StdioCollector { }
        onStarted: preferences.startupTimeout.stop()
        onExited: (code, status) => preferences.finish(code, status)
        onRunningChanged: {
            if (!running && preferences.ownsProcess) {
                const serial = preferences.generation;
                Qt.callLater(function() {
                    if (serial === preferences.generation && !runner.running && preferences.ownsProcess)
                        preferences.finish(-1, -1);
                });
            }
        }
    }
    property Timer startupTimeout: Timer {
        interval: 2500
        onTriggered: preferences.abort("The profile picture service could not start. Please try again.")
    }
    property Timer totalTimeout: Timer {
        interval: 30000
        onTriggered: preferences.abort("Updating your profile picture took too long. Please try again.")
    }
    property Timer stopTimeout: Timer {
        interval: 1500
        onTriggered: {
            if (!preferences.ownsProcess) return;
            if (runner.running && runner.processId > 0) runner.signal(9);
            else preferences.finish(-1, -1);
        }
    }
}
