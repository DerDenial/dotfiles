import QtQuick
import Quickshell
import Quickshell.Io

// A single read-only sampler is owned by the open network panel.
QtObject {
    id: telemetry
    property bool enabled: false
    property bool ready: false
    property string error: ""
    property var snapshot: ({ interface: { id: "", name: "", kind: "none", connected: false }, warnings: [] })
    property var history: []
    readonly property string helper: Quickshell.env("HOME") + "/.config/quickshell/Network/telemetry.py"
    readonly property bool running: sampler.running
    readonly property real windowSeconds: 120

    function value(number) { return typeof number === "number" && Number.isFinite(number); }
    function nullable(number) { return number === null || value(number) && number >= 0; }
    function accept(line) {
        if (!enabled || !line.trim()) return;
        try {
            const sample = JSON.parse(line);
            const connection = sample ? sample.interface : null;
            if (!sample || sample.ok !== true || !value(sample.timestamp) || !value(sample.monotonic)
                    || !connection || typeof connection.id !== "string" || typeof connection.name !== "string"
                    || typeof connection.kind !== "string" || typeof connection.connected !== "boolean"
                    || !nullable(sample.rxBytesPerSecond) || !nullable(sample.txBytesPerSecond)
                    || !nullable(sample.receivedBytes) || !nullable(sample.sentBytes)
                    || !Array.isArray(sample.warnings) || !sample.warnings.every(warning => typeof warning === "string"))
                throw new Error("Invalid network sample");
            const oldInterface = snapshot.interface;
            snapshot = sample;
            ready = true;
            error = "";
            if (!connection.connected || !connection.id) { history = []; return; }
            const point = { t: sample.monotonic, rx: sample.rxBytesPerSecond, tx: sample.txBytesPerSecond, id: connection.id };
            const previous = history.length ? history[history.length - 1] : null;
            let next = !oldInterface || oldInterface.id !== connection.id || !oldInterface.connected
                || previous && point.t <= previous.t ? [] : history.filter(item => point.t - item.t <= windowSeconds);
            next.push(point);
            history = next.slice(-121);
        } catch (exception) {
            error = "Could not read network data.";
        }
    }
    onEnabledChanged: {
        if (enabled) {
            ready = false;
            error = "";
            snapshot = { interface: { id: "", name: "", kind: "none", connected: false }, warnings: [] };
            history = [];
        }
    }
    property Process sampler: Process {
        command: ["python3", "-u", telemetry.helper, "--stream", "--interval", "1"]
        running: telemetry.enabled
        stdout: SplitParser { onRead: data => telemetry.accept(data) }
        stderr: StdioCollector { }
        onExited: (code, status) => {
            if (telemetry.enabled) telemetry.error = "Network monitoring stopped. Close and reopen the panel to retry.";
        }
    }
}
