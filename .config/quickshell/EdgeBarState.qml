pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland

// The compositor's window tag is the source of truth, including after a reload.
QtObject {
    id: state
    readonly property var managedWindows: Array.from(Hyprland.toplevels.values).filter(window => {
        const raw = window.lastIpcObject || {};
        const tags = Array.from(raw.tags || []);
        return tags.some(tag => String(tag).replace(/\*$/, "") === "qs-edge")
            && Number(raw.fullscreen) === 1 && !raw.floating;
    })

    function activeOnScreen(name) {
        const monitor = Array.from(Hyprland.monitors.values).find(candidate => candidate.name === name);
        if (!monitor || !monitor.activeWorkspace) return false;
        return managedWindows.some(window => window.workspace && window.workspace.id === monitor.activeWorkspace.id
            && (!window.monitor || window.monitor.name === name));
    }

    function refresh() { refreshDelay.restart(); }

    property Timer refreshDelay: Timer {
        interval: 45
        onTriggered: {
            Hyprland.refreshToplevels();
            Hyprland.refreshWorkspaces();
            Hyprland.refreshMonitors();
        }
    }
    property Connections events: Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (["tag", "fullscreen", "changefloatingmode", "movewindow", "movewindowv2",
                "openwindow", "closewindow", "workspace", "workspacev2", "focusedmon",
                "monitoradded", "monitoraddedv2", "monitorremoved", "configreloaded"].indexOf(event.name) >= 0)
                state.refresh();
        }
    }
    Component.onCompleted: refresh()
}
