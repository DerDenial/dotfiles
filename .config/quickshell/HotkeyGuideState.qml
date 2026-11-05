import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

QtObject {
    id: state

    property bool blocked: false
    property bool shown: false
    property var groups: []
    property string status: ""
    property string error: ""
    readonly property bool loading: catalogReader.running
    property string expectedEpoch: ""
    property string wantedToken: ""
    property string readerToken: ""
    property int readerGeneration: 0
    property bool received: false
    property var retiredTokens: []

    function epochOf(token) {
        return /^[0-9]+-[0-9a-f]{8}-[1-9][0-9]{0,12}$/.test(token)
            ? token.slice(0, token.lastIndexOf("-")) : "";
    }

    function epochOrder(epoch) {
        return Number(epoch.slice(0, epoch.indexOf("-")));
    }

    function retireToken(token) {
        if (!token || retiredTokens.indexOf(token) !== -1) return;
        // IPC clients may finish in a different order from the physical keys.
        retiredTokens = retiredTokens.concat([token]).slice(-64);
    }

    function dismiss() {
        retireToken(wantedToken);
        wantedToken = "";
        shown = false;
        retire.restart();
    }

    function holdShow(token) {
        const epoch = epochOf(token);
        if (!epoch || retiredTokens.indexOf(token) !== -1) return;
        if (expectedEpoch && epoch !== expectedEpoch && epochOrder(epoch) <= epochOrder(expectedEpoch)) return;
        if (blocked) {
            retireToken(token);
            return;
        }
        expectedEpoch = epoch;
        if (wantedToken === token) return;
        dismiss();
        retire.stop();
        wantedToken = token;
        if (!catalogReader.running) readCatalog();
    }

    function holdHide(token) {
        if (!epochOf(token)) return;
        retireToken(token);
        if (wantedToken === token) dismiss();
    }

    function reset(epoch) {
        if (!/^[0-9]+-[0-9a-f]{8}$/.test(epoch)) return;
        if (expectedEpoch && epoch !== expectedEpoch && epochOrder(epoch) <= epochOrder(expectedEpoch)) return;
        dismiss();
        expectedEpoch = epoch;
    }

    function readCatalog() {
        if (!wantedToken || blocked || catalogReader.running) return;
        readerToken = wantedToken;
        ++readerGeneration;
        received = false;
        catalogReader.running = true;
    }

    function acceptCatalog(info) {
        if (!wantedToken || readerToken !== wantedToken || blocked) return;
        groups = Array.isArray(info.groups) ? info.groups : [];
        status = String(info.notice || info.sourceLabel || "");
        error = info.ok === true ? "" : String(info.error || "Shortcuts are temporarily unavailable.");
        // Resolve the catalogue before opening, so the card has its final size.
        shown = true;
    }

    onBlockedChanged: if (blocked) dismiss()

    property IpcHandler ipc: IpcHandler {
        target: "hotkeyGuide"
        function holdShow(token: string): void { state.holdShow(token); }
        function holdHide(token: string): void { state.holdHide(token); }
        function reset(epoch: string): void { state.reset(epoch); }
    }

    property Connections configEvents: Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") state.dismiss();
        }
    }

    property Timer retire: Timer {
        interval: 10000
        onTriggered: {
            if (state.wantedToken || state.shown || state.catalogReader.running) return;
            state.groups = [];
            state.status = "";
            state.error = "";
        }
    }

    property Process catalogReader: Process {
        command: ["python3", Quickshell.shellPath("Hotkeys/catalog.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                state.received = true;
                try {
                    state.acceptCatalog(JSON.parse(text));
                } catch (e) {
                    state.acceptCatalog({ ok: false, groups: [], error: "Shortcuts are temporarily unavailable." });
                }
            }
        }
        stderr: StdioCollector {}
        onExited: function(exitCode, exitStatus) {
            const completedGeneration = state.readerGeneration;
            Qt.callLater(function() {
                if (state.readerGeneration !== completedGeneration || state.catalogReader.running) return;
                if (state.wantedToken && state.readerToken !== state.wantedToken) {
                    state.readCatalog();
                } else if (state.wantedToken && !state.received) {
                    state.acceptCatalog({ ok: false, groups: [], error: "Shortcuts are temporarily unavailable." });
                }
                if (!state.wantedToken) state.retire.restart();
            });
        }
    }
}
