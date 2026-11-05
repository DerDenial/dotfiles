pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: manager
    property bool active: false
    property bool paused: false
    property bool loading: false
    property string monitorError: ""
    property string actionError: ""
    readonly property string errorText: actionError || monitorError
    property string search: ""
    property string sortKey: "memory"
    property bool sortDescending: true
    property string selectedKey: ""
    property var snapshot: ({})
    property var cpuHistory: []
    property var memoryHistory: []
    property var pendingEnd: null
    property bool endInFlight: false
    readonly property bool actionBusy: endInFlight || endTask.running
    property bool collectorStopping: false
    property bool collectorFailed: false
    property string endReply: ""
    readonly property string helper: Quickshell.env("HOME") + "/.config/quickshell/TaskManager/processes.py"
    readonly property var summary: snapshot.system || ({})
    readonly property var processes: snapshot.processes || []
    readonly property var rows: filteredRows()
    readonly property var selectedProcess: rows.find(row => row.key === selectedKey) || null

    function number(value) { return typeof value === "number" && Number.isFinite(value) ? value : -1; }
    function filteredRows() {
        const query = search.trim().toLocaleLowerCase();
        const values = processes.filter(row => !query || (row.name + " " + row.pid + " " + row.user).toLocaleLowerCase().includes(query));
        const direction = sortDescending ? -1 : 1;
        values.sort(function(left, right) {
            let delta = 0;
            if (sortKey === "name") delta = left.name.localeCompare(right.name);
            else if (sortKey === "pid") delta = left.pid - right.pid;
            else if (sortKey === "cpu") delta = number(left.cpuPercent) - number(right.cpuPercent);
            else if (sortKey === "disk") {
                const leftRate = left.diskReadRate === null || left.diskWriteRate === null ? -1 : number(left.diskReadRate) + number(left.diskWriteRate);
                const rightRate = right.diskReadRate === null || right.diskWriteRate === null ? -1 : number(right.diskReadRate) + number(right.diskWriteRate);
                delta = leftRate - rightRate;
            } else delta = number(left.memoryBytes) - number(right.memoryBytes);
            return delta * direction || left.name.localeCompare(right.name) || left.pid - right.pid;
        });
        return values;
    }
    function sortBy(key) {
        if (!["memory", "cpu", "name", "pid", "disk"].includes(key)) return;
        if (sortKey === key) sortDescending = !sortDescending;
        else { sortKey = key; sortDescending = key !== "name" && key !== "pid"; }
    }
    function select(key) { selectedKey = String(key); }
    function acceptSnapshot(line) {
        if (!active || paused || collectorStopping) return;
        try {
            const next = JSON.parse(line);
            if (next.error) { monitorError = String(next.error); loading = false; return; }
            if (next.schema !== 1 || !next.system || !Array.isArray(next.processes)) throw new Error("Invalid snapshot");
            // A malformed stream never becomes a selectable termination target.
            if (next.processes.some(row => !row || typeof row.key !== "string" || !/^[1-9][0-9]*:[0-9]+$/.test(row.key)
                || !Number.isInteger(row.pid) || row.pid < 1 || typeof row.startTime !== "string"
                || row.key !== String(row.pid) + ":" + row.startTime || typeof row.name !== "string"
                || typeof row.user !== "string" || typeof row.canEnd !== "boolean")) throw new Error("Invalid process metadata");
            snapshot = next;
            monitorError = "";
            loading = false;
            if (typeof next.system.cpuPercent === "number") cpuHistory = cpuHistory.concat([next.system.cpuPercent]).slice(-60);
            if (next.system.memoryTotal > 0) memoryHistory = memoryHistory.concat([100 * next.system.memoryUsed / next.system.memoryTotal]).slice(-60);
            if (selectedKey && !next.processes.some(row => row.key === selectedKey)) selectedKey = "";
        } catch (error) {
            monitorError = "Could not read process information.";
            loading = false;
        }
    }
    function startCollector() {
        if (!active || paused || collectorFailed || collector.running || collectorStopping) return;
        loading = processes.length === 0;
        monitorError = "";
        collector.stdinEnabled = true;
        collector.running = true;
        sampleDeadline.restart();
    }
    function stopCollector() {
        sampleDeadline.stop();
        if (!collector.running) { collectorStopping = false; return; }
        collectorStopping = true;
        // EOF lets the sole collector exit cleanly, including shell reloads.
        collector.stdinEnabled = false;
        stopGuard.restart();
    }
    function requestEnd() {
        if (!active || actionBusy || endTask.running || !selectedProcess || !selectedProcess.canEnd) return;
        pendingEnd = Object.assign({}, selectedProcess);
    }
    function cancelEnd() { pendingEnd = null; }
    function confirmEnd() {
        const target = pendingEnd;
        if (!active || actionBusy || endTask.running || !target || !target.canEnd) return;
        pendingEnd = null;
        actionError = "";
        endInFlight = true;
        endReply = "";
        endTask.command = ["python3", helper, "--end", String(target.pid), target.startTime];
        endTask.running = true;
        endGuard.restart();
    }
    function finishEnd(code, status) {
        if (!endInFlight) return;
        endGuard.stop();
        endInFlight = false;
        try {
            const result = JSON.parse(endReply);
            if (code !== 0 || status !== 0 || result.ok !== true) throw new Error(result.error || "Could not end this process.");
            actionError = "";
        } catch (error) { actionError = String(error.message || "Could not end this process."); }
    }
    onActiveChanged: {
        if (active) { actionError = ""; collectorFailed = false; paused = false; startCollector(); }
        else { pendingEnd = null; stopCollector(); }
    }
    onPausedChanged: { if (paused) stopCollector(); else { collectorFailed = false; startCollector(); } }
    Component.onDestruction: collector.stdinEnabled = false

    property Process collector: Process {
        command: ["python3", "-u", manager.helper, "--watch"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                manager.acceptSnapshot(line);
                if (manager.active && !manager.paused && !manager.collectorStopping) sampleDeadline.restart();
            }
        }
        stderr: StdioCollector { }
        onExited: (code, status) => {
            sampleDeadline.stop();
            if (!manager.collectorStopping && manager.active && !manager.paused) {
                manager.collectorFailed = true;
                manager.loading = false;
                manager.monitorError = "Process monitoring stopped. Close and reopen Task Manager to retry.";
            }
        }
        onRunningChanged: if (!running) Qt.callLater(function() {
            stopGuard.stop();
            if (manager.collectorStopping) {
                manager.collectorStopping = false;
                manager.startCollector();
            } else if (manager.active && !manager.paused && manager.loading) {
                manager.collectorFailed = true;
                manager.loading = false;
                manager.monitorError = "Could not start process monitoring.";
                sampleDeadline.stop();
            }
        })
    }
    property Timer stopGuard: Timer {
        interval: 2000
        onTriggered: if (collector.running && manager.collectorStopping) collector.signal(15)
    }
    property Timer sampleDeadline: Timer {
        interval: 6500
        onTriggered: {
            manager.collectorFailed = true;
            manager.loading = false;
            manager.monitorError = "Process monitoring is not responding. Close and reopen Task Manager to retry.";
            manager.stopCollector();
        }
    }
    property Process endTask: Process {
        stdout: StdioCollector { onStreamFinished: manager.endReply = text }
        stderr: StdioCollector { }
        onExited: (code, status) => manager.finishEnd(code, status)
        onRunningChanged: if (!running && manager.endInFlight) Qt.callLater(function() {
            if (!endTask.running && manager.endInFlight) manager.finishEnd(-1, -1);
        })
    }
    property Timer endGuard: Timer {
        interval: 5000
        onTriggered: {
            if (endTask.running) endTask.signal(15);
            manager.finishEnd(-1, -1);
        }
    }
}
