import QtQuick
import Quickshell.Io

QtObject {
    id: state
    property bool polling: false
    property string backend: ""
    property string address: ""
    property string error: ""
    property bool reachable: false
    readonly property bool active: backend === "Running"
    readonly property bool busy: action.running
    readonly property string status: busy ? "Updating…" : error || (active ? "Connected · " + address : backend === "Stopped" ? "Disconnected" : backend === "NeedsLogin" ? "Sign in with tailscale up" : reachable ? backend : "Service unavailable")
    function refresh() { if (!query.running) query.running = true; }
    function toggle() {
        if (!reachable || busy) return;
        error = "";
        action.command = active ? ["tailscale", "down"] : ["tailscale", "up", "--timeout=10s"];
        action.running = true;
    }
    onPollingChanged: if (polling) refresh()
    property Timer timer: Timer { interval: 5000; repeat: true; running: state.polling; onTriggered: state.refresh() }
    property Process query: Process {
        command: ["timeout", "4", "tailscale", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var info = JSON.parse(text);
                    state.backend = info.BackendState || "";
                    state.address = info.TailscaleIPs && info.TailscaleIPs.length ? info.TailscaleIPs[0] : "";
                    state.reachable = true;
                } catch (e) { state.reachable = false; }
            }
        }
    }
    property Process action: Process {
        stderr: StdioCollector {
            onStreamFinished: {
                if (!text.trim()) return;
                state.error = /permission|denied|operator|sudo/i.test(text) ? "Operator permission required" : "Could not change connection";
                console.warn("Tailscale:", text.trim());
            }
        }
        onExited: function(exitCode, exitStatus) {
            if (exitCode !== 0 && !state.error) state.error = "Could not change connection";
            state.refresh();
        }
    }
}
