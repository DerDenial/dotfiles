import QtQuick
import Quickshell
import Quickshell.Io

// No process is started until the user explicitly requests a test.
QtObject {
    id: state
    property bool enabled: false
    readonly property bool running: ownsProcess
    property bool cancelling: false
    property bool ownsProcess: false
    property bool protocolFailed: false
    property bool receivedFinal: false
    property var snapshot: emptySnapshot("idle")
    readonly property string helper: Quickshell.shellPath("SpeedTest/run.py")

    function emptySnapshot(phase) {
        return { phase: phase, progress: 0, downloadMbps: null, uploadMbps: null,
            latencyMs: null, jitterMs: null, liveMbps: null, bytesTransferred: 0,
            provider: "Cloudflare", error: "" };
    }
    function isNumber(value) { return typeof value === "number" && Number.isFinite(value) && value >= 0; }
    function nullable(value) { return value === null || isNumber(value); }
    function start() {
        if (!enabled || ownsProcess || runner.running) return;
        cancelling = false;
        protocolFailed = false;
        receivedFinal = false;
        snapshot = emptySnapshot("latency");
        ownsProcess = true;
        startupTimeout.start();
        totalTimeout.start();
        runner.running = true;
    }
    function cancel() {
        if (!ownsProcess || cancelling) return;
        cancelling = true;
        snapshot = Object.assign({}, snapshot, { phase: "cancelled", liveMbps: null, error: "" });
        startupTimeout.stop();
        totalTimeout.stop();
        runner.signal(15);
        stopTimeout.start();
    }
    function fail(message) {
        if (!ownsProcess) return;
        protocolFailed = true;
        snapshot = Object.assign({}, snapshot, { phase: "error", liveMbps: null, error: message });
        runner.signal(15);
        stopTimeout.start();
    }
    function accept(line) {
        if (!ownsProcess || cancelling || protocolFailed || !line.trim()) return;
        try {
            if (line.length > 16384) throw Error("Oversize sample");
            const next = JSON.parse(line);
            if (!next || ["latency", "download", "upload", "complete", "error", "cancelled"].indexOf(next.phase) < 0
                    || !isNumber(next.progress) || next.progress > 1
                    || !nullable(next.downloadMbps) || !nullable(next.uploadMbps)
                    || !nullable(next.latencyMs) || !nullable(next.jitterMs) || !nullable(next.liveMbps)
                    || !isNumber(next.bytesTransferred) || !Number.isInteger(next.bytesTransferred)
                    || typeof next.error !== "string" || next.error.length > 1024)
                throw Error("Invalid sample");
            if (next.phase === "complete" && (!isNumber(next.downloadMbps) || !isNumber(next.uploadMbps) || !isNumber(next.latencyMs)))
                throw Error("Incomplete result");
            if (receivedFinal) return;
            snapshot = Object.assign({}, next, { provider: "Cloudflare" });
            receivedFinal = ["complete", "error", "cancelled"].indexOf(next.phase) >= 0;
        } catch (error) { fail("Could not read the speed test result. Please try again."); }
    }
    function exited(code) {
        startupTimeout.stop();
        totalTimeout.stop();
        stopTimeout.stop();
        if (!ownsProcess) return;
        if (cancelling) snapshot = Object.assign({}, snapshot, { phase: "cancelled", liveMbps: null, error: "" });
        else if (!protocolFailed && (!receivedFinal || code !== 0 && snapshot.phase !== "error"))
            snapshot = Object.assign({}, snapshot, { phase: "error", liveMbps: null,
                error: "The test could not finish. Check your connection and try again." });
        ownsProcess = false;
        cancelling = false;
    }
    onEnabledChanged: if (!enabled) cancel()
    Component.onDestruction: if (runner.running) runner.signal(15)

    property Process runner: Process {
        command: ["python3", "-u", state.helper]
        stdout: SplitParser { onRead: line => state.accept(line) }
        stderr: StdioCollector {}
        onStarted: startupTimeout.stop()
        onExited: (code, status) => state.exited(code)
    }
    property Timer startupTimeout: Timer {
        interval: 2500
        onTriggered: {
            if (runner.running) state.fail("The speed test could not start. Please try again.");
            else {
                state.protocolFailed = true;
                state.snapshot = Object.assign({}, state.snapshot, { phase: "error", error: "The speed test could not start." });
                state.exited(-1);
            }
        }
    }
    property Timer totalTimeout: Timer {
        interval: 45000
        onTriggered: state.fail("The speed test timed out. Please try again.")
    }
    property Timer stopTimeout: Timer {
        interval: 1500
        onTriggered: {
            if (runner.running) runner.signal(9);
            else state.exited(-1);
        }
    }
}
