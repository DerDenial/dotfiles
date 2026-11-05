import QtQuick
import Quickshell
import Quickshell.Io

// One finite helper exists only after an explicit Check/Retry action.
QtObject {
    id: state
    property bool enabled: false
    readonly property bool running: ownsProcess
    property bool ownsProcess: false
    property bool cancelling: false
    property bool protocolFailed: false
    property bool receivedFinal: false
    property var snapshot: initialSnapshot("idle")
    readonly property string helper: Quickshell.shellPath("Network/check.py")

    function initialSnapshot(phase) {
        const ids = ["link", "router", "dns", "internet"];
        const titles = ["Network link", "Router", "DNS", "Internet"];
        return { phase: phase, steps: ids.map((id, index) => ({ id: id, title: titles[index],
                status: "pending", detail: "Waiting to be checked", durationMs: null })),
            summary: { status: "idle", title: phase === "running" ? "Checking your connection…" : "Ready to check",
                detail: "Check your network link, router, DNS and internet access." }, checkedAt: null };
    }
    function isNumber(value) { return typeof value === "number" && Number.isFinite(value) && value >= 0; }
    function smallString(value) { return typeof value === "string" && value.length <= 2048; }
    function terminal(phase, title, detail) {
        snapshot = Object.assign({}, snapshot, { phase: phase,
            steps: snapshot.steps.map(step => step.status === "pending" || step.status === "running"
                ? Object.assign({}, step, { status: "skipped", detail: "Check not completed" }) : step),
            summary: { status: phase, title: title, detail: detail } });
    }
    function start() {
        if (!enabled || ownsProcess || runner.running) return false;
        cancelling = false;
        protocolFailed = false;
        receivedFinal = false;
        snapshot = initialSnapshot("running");
        ownsProcess = true;
        startupTimeout.start();
        totalTimeout.start();
        runner.running = true;
        return true;
    }
    function cancel() {
        if (!ownsProcess || cancelling) return;
        cancelling = true;
        terminal("cancelled", "Check stopped", "Run the check again whenever you’re ready.");
        startupTimeout.stop();
        totalTimeout.stop();
        runner.signal(15);
        stopTimeout.start();
    }
    function fail(message) {
        if (!ownsProcess) return;
        protocolFailed = true;
        terminal("error", "Could not complete the check", message);
        runner.signal(15);
        stopTimeout.start();
    }
    function accept(line) {
        if (!ownsProcess || cancelling || protocolFailed || !line.trim()) return;
        try {
            if (line.length > 32768) throw Error("Oversize result");
            const next = JSON.parse(line);
            const ids = ["link", "router", "dns", "internet"];
            const statuses = ["pending", "running", "ok", "warning", "failed", "skipped"];
            if (!next || ["running", "complete", "error", "cancelled"].indexOf(next.phase) < 0
                    || !Array.isArray(next.steps) || next.steps.length !== 4
                    || !next.steps.every((step, index) => step && step.id === ids[index]
                        && statuses.indexOf(step.status) >= 0 && smallString(step.title) && smallString(step.detail)
                        && (step.durationMs === null || isNumber(step.durationMs)))
                    || !next.summary || ["idle", "ok", "warning", "failed", "cancelled", "error"].indexOf(next.summary.status) < 0
                    || !smallString(next.summary.title) || !smallString(next.summary.detail)
                    || !(next.checkedAt === null || smallString(next.checkedAt)))
                throw Error("Invalid result");
            if (next.phase === "complete" && (next.steps.some(step => step.status === "pending" || step.status === "running")
                    || ["ok", "warning", "failed"].indexOf(next.summary.status) < 0))
                throw Error("Incomplete result");
            if (next.phase === "error" && next.summary.status !== "error"
                    || next.phase === "cancelled" && next.summary.status !== "cancelled"
                    || next.checkedAt !== null && !Number.isFinite(Date.parse(next.checkedAt)))
                throw Error("Invalid terminal state");
            if (receivedFinal) return;
            snapshot = next;
            receivedFinal = next.phase !== "running";
        } catch (error) { fail("Could not read the check results. Please try again."); }
    }
    function exited(code) {
        startupTimeout.stop();
        totalTimeout.stop();
        stopTimeout.stop();
        if (!ownsProcess) return;
        if (cancelling) terminal("cancelled", "Check stopped", "Run the check again whenever you’re ready.");
        else if (!protocolFailed && (!receivedFinal || code !== 0 && snapshot.phase !== "error"))
            terminal("error", "Could not complete the check", "Please try again. No network settings were changed.");
        ownsProcess = false;
        cancelling = false;
    }
    onEnabledChanged: if (!enabled) cancel()
    Component.onDestruction: if (runner && runner.running) runner.signal(15)

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
            if (runner.running) state.fail("The connection check could not start. Please try again.");
            else {
                state.protocolFailed = true;
                state.terminal("error", "Could not start the check", "Please try again.");
                state.exited(-1);
            }
        }
    }
    property Timer totalTimeout: Timer {
        interval: 25000
        onTriggered: state.fail("The connection check timed out. Please try again.")
    }
    property Timer stopTimeout: Timer {
        interval: 1500
        onTriggered: {
            if (runner.running) runner.signal(9);
            else state.exited(-1);
        }
    }
}
