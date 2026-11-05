import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: emojiState

    property string helperPath: Quickshell.shellPath("Emoji/backend.py")
    property bool engaged: false
    property bool opening: false
    property bool busy: false
    property bool waitingForInput: false
    property bool catalogLoaded: false
    property bool captured: false
    property var catalog: []
    property var recentGlyphs: []
    property var target: null
    property var pendingRequest: null
    property string error: ""
    property int generation: 0
    property int captureGeneration: -1
    property bool captureReceived: false
    property bool catalogReceived: false
    property bool actionReceived: false
    readonly property bool catalogReading: catalogReaderLoader.active
    readonly property bool loading: opening || catalogReading
    readonly property bool inputSuspended: busy
    readonly property var recentEmojis: {
        const lookup = new Map();
        for (const entry of catalog) {
            lookup.set(entry.emoji, entry);
            for (const variant of entry.variants || [])
                lookup.set(variant.emoji, Object.assign({}, entry, variant));
        }
        return recentGlyphs.map(emoji => lookup.get(emoji)).filter(Boolean);
    }

    signal readyToOpen()

    function prepareOpen() {
        if (busy) return;
        ++generation;
        opening = true;
        captured = false;
        target = null;
        error = "";
        retire.stop();
        if (!catalogLoaded && !catalogReading) {
            catalogReceived = false;
            catalogReaderLoader.active = true;
        }
        if (!recentsReader.running) recentsReader.running = true;
        if (!capture.running) startCapture();
    }

    function startCapture() {
        if (!opening || capture.running) return;
        captureGeneration = generation;
        captureReceived = false;
        capture.running = true;
    }

    function revealWhenReady() {
        if (!opening || !captured || !catalogLoaded) return;
        opening = false;
        readyToOpen();
    }

    function cancelOpen() {
        ++generation;
        opening = false;
        captured = false;
        handoffWatchdog.stop();
        if (waitingForInput) {
            waitingForInput = false;
            pendingRequest = null;
            busy = false;
        }
        if (!action.running) target = null;
        if (!engaged && !busy) retire.restart();
    }

    function queueInsert(emoji) {
        if (busy || action.running || opening || !emoji) return false;
        error = "";
        pendingRequest = { emoji: String(emoji), target: target, keepOpen: true, inputReleased: true };
        waitingForInput = true;
        handoffWatchdog.restart();
        busy = true;
        return true;
    }

    function inputReleased() {
        if (!busy || !waitingForInput || !pendingRequest) return;
        handoffWatchdog.stop();
        waitingForInput = false;
        actionReceived = false;
        action.command = ["python3", helperPath, "insert", "--request", JSON.stringify(pendingRequest)];
        pendingRequest = null;
        action.running = true;
    }

    function finishAction(info) {
        if (Array.isArray(info.recents)) recentGlyphs = info.recents;
        error = info.ok === true && info.inserted === true ? String(info.warning || "")
              : String(info.message || "Das Emoji konnte nicht eingefügt werden.");
    }

    onEngagedChanged: {
        if (engaged) retire.stop();
        else if (!busy) retire.restart();
    }

    property Timer handoffWatchdog: Timer {
        interval: 650
        onTriggered: {
            if (!emojiState.waitingForInput) return;
            emojiState.waitingForInput = false;
            emojiState.pendingRequest = null;
            emojiState.error = "Der Tastaturfokus konnte nicht freigegeben werden. Bitte erneut versuchen.";
            emojiState.busy = false;
        }
    }

    property Timer retire: Timer {
        interval: 10000
        onTriggered: {
            if (emojiState.engaged || emojiState.busy || emojiState.opening || capture.running || catalogReading || recentsReader.running) return;
            emojiState.catalog = [];
            emojiState.catalogLoaded = false;
            emojiState.recentGlyphs = [];
            emojiState.target = null;
        }
    }

    property Process capture: Process {
        command: ["python3", emojiState.helperPath, "capture"]
        stdout: StdioCollector {
            onStreamFinished: {
                emojiState.captureReceived = true;
                if (!emojiState.opening || emojiState.captureGeneration !== emojiState.generation) return;
                try {
                    const info = JSON.parse(text);
                    emojiState.target = info.ok === true ? info.target : null;
                    if (info.ok !== true) emojiState.error = String(info.message || "Das Eingabefenster konnte nicht ermittelt werden.");
                } catch (e) {
                    emojiState.target = null;
                    emojiState.error = "Das Eingabefenster konnte nicht ermittelt werden.";
                }
                emojiState.captured = true;
                emojiState.revealWhenReady();
            }
        }
        stderr: StdioCollector { }
        onExited: function(exitCode, exitStatus) {
            Qt.callLater(function() {
                if (!emojiState.opening) return;
                if (emojiState.captureGeneration !== emojiState.generation) emojiState.startCapture();
                else if (!emojiState.captureReceived) {
                    emojiState.target = null;
                    emojiState.captured = true;
                    emojiState.error = "Das Eingabefenster konnte nicht ermittelt werden.";
                    emojiState.revealWhenReady();
                }
            });
        }
    }

    // Release the raw JSON collector as soon as this read ends. Only the parsed
    // catalog is kept during the picker's brief warm-cache period.
    function finishCatalogRead(reader) {
        Qt.callLater(function() {
            if (catalogReaderLoader.item !== reader || reader.running) return;
            if (!emojiState.catalogReceived) {
                emojiState.catalogLoaded = true;
                emojiState.error = "Der Emoji-Katalog konnte nicht geladen werden.";
                emojiState.revealWhenReady();
            }
            catalogReaderLoader.active = false;
            // A canceled slow read must still get a later chance to retire.
            if (!emojiState.engaged && !emojiState.busy && !emojiState.opening) retire.restart();
        });
    }

    property Loader catalogReaderLoader: Loader {
        active: false
        asynchronous: false
        sourceComponent: Component {
            Process {
                id: reader
                command: ["python3", emojiState.helperPath, "catalog"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        emojiState.catalogReceived = true;
                        try {
                            const info = JSON.parse(text);
                            emojiState.catalog = info.ok === true && Array.isArray(info.emojis) ? info.emojis : [];
                            if (info.ok !== true) emojiState.error = String(info.message || "Der Emoji-Katalog fehlt.");
                        } catch (e) {
                            emojiState.catalog = [];
                            emojiState.error = "Der Emoji-Katalog konnte nicht geladen werden.";
                        }
                        emojiState.catalogLoaded = true;
                        emojiState.revealWhenReady();
                    }
                }
                stderr: StdioCollector { }
                onExited: emojiState.finishCatalogRead(reader)
                onRunningChanged: if (!running) emojiState.finishCatalogRead(reader)
            }
        }
    }

    property Process recentsReader: Process {
        command: ["python3", emojiState.helperPath, "recents"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const info = JSON.parse(text);
                    emojiState.recentGlyphs = info.ok === true && Array.isArray(info.recents) ? info.recents : [];
                } catch (e) { emojiState.recentGlyphs = []; }
            }
        }
        stderr: StdioCollector { }
    }

    property Process action: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                emojiState.actionReceived = true;
                try { emojiState.finishAction(JSON.parse(text)); }
                catch (e) { emojiState.finishAction({ message: "Das Emoji konnte nicht eingefügt werden." }); }
            }
        }
        stderr: StdioCollector { }
        onExited: function(exitCode, exitStatus) {
            Qt.callLater(function() {
                if (!emojiState.actionReceived) emojiState.finishAction({ message: "Das Emoji konnte nicht eingefügt werden." });
                emojiState.busy = false;
                if (!emojiState.engaged) {
                    emojiState.target = null;
                    retire.restart();
                }
            });
        }
    }
}
