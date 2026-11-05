import QtQuick
import Quickshell
import Quickshell.Io

// One read-only sampler exists only while the hardware panel is open.
QtObject {
    id: telemetry
    property bool enabled: false
    property bool ready: false
    property string error: ""
    property var snapshot: ({ cpu: {}, gpus: [], battery: { present: false }, warnings: [] })
    property var history: []
    readonly property string helper: Quickshell.env("HOME") + "/.config/quickshell/Hardware/telemetry.py"
    readonly property bool running: sampler.running
    readonly property real windowSeconds: 120

    function value(number) { return typeof number === "number" && Number.isFinite(number); }
    function accept(line) {
        if (!enabled || !line.trim()) return;
        try {
            const sample = JSON.parse(line);
            if (!sample || sample.ok !== true || !value(sample.timestamp)
                    || !value(sample.monotonic) || !sample.cpu || typeof sample.cpu.name !== "string"
                    || !Array.isArray(sample.gpus) || !sample.gpus.every(gpu => gpu && typeof gpu.name === "string")
                    || !sample.battery || typeof sample.battery.present !== "boolean"
                    || !Array.isArray(sample.warnings) || !sample.warnings.every(warning => typeof warning === "string"))
                throw new Error("Invalid hardware sample");
            snapshot = sample;
            ready = true;
            error = "";
            const battery = sample.battery;
            if (!battery.present) { history = []; return; }
            const point = { t: sample.monotonic, watts: value(battery.powerW) && battery.powerW >= 0 ? battery.powerW : null,
                charging: battery.charging === true, draining: battery.draining === true };
            const previous = history.length ? history[history.length - 1] : null;
            let next = previous && point.t <= previous.t ? [] : history.filter(item => point.t - item.t <= windowSeconds);
            next.push(point);
            history = next.slice(-121);
        } catch (exception) {
            error = "Could not read hardware data.";
        }
    }
    onEnabledChanged: {
        if (enabled) {
            ready = false;
            error = "";
            snapshot = { cpu: {}, gpus: [], battery: { present: false }, warnings: [] };
            history = [];
        }
    }
    property Process sampler: Process {
        command: ["python3", "-u", telemetry.helper, "--stream", "--interval", "1"]
        running: telemetry.enabled
        stdout: SplitParser { onRead: data => telemetry.accept(data) }
        stderr: StdioCollector { }
        onExited: (code, status) => {
            if (telemetry.enabled) telemetry.error = "Hardware monitoring stopped. Close and reopen the panel to retry.";
        }
    }
}
