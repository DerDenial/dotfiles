import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Theme" as ThemeApi

// A normal desktop window: other apps and the notch remain interactive.
FloatingWindow {
    id: app
    title: "Quickshell Task Manager"
    implicitWidth: 1040
    implicitHeight: 720
    minimumSize: Qt.size(760, 520)
    color: ThemeApi.Theme.bg0
    visible: surfaceMapped
    property bool opened: false
    property bool pendingOpen: false
    property bool canOpen: true
    property bool surfaceMapped: false
    property real reveal: 0
    signal aboutToOpen()

    function open() {
        pendingOpen = true;
        aboutToOpen();
        if (canOpen) showWindow();
    }
    function focusWindow() {
        if (!opened) return;
        const existing = Array.from(ToplevelManager.toplevels.values).find(window => window.title === app.title);
        if (existing) {
            try { existing.activate(); } catch (error) { /* The surface may have just closed. */ }
        }
        if (panelLoader.item) panelLoader.item.focusProcesses();
    }
    function showWindow() {
        if (!pendingOpen || !canOpen) return;
        pendingOpen = false;
        minimized = false;
        opened = true;
        Qt.callLater(focusWindow);
    }
    function close() {
        pendingOpen = false;
        opened = false;
        taskState.cancelEnd();
    }
    function toggle() { if (opened || pendingOpen) close(); else open(); }
    onCanOpenChanged: if (canOpen && pendingOpen) showWindow()
    onClosed: { pendingOpen = false; opened = false; surfaceMapped = false; reveal = 0; }
    onOpenedChanged: {
        entrance.stop();
        if (opened) surfaceMapped = true;
        entrance.from = reveal;
        entrance.to = opened ? 1 : 0;
        entrance.duration = opened ? 200 : 120;
        entrance.easing.type = opened ? Easing.OutBack : Easing.OutCubic;
        entrance.start();
    }
    NumberAnimation {
        id: entrance
        target: app
        property: "reveal"
        easing.overshoot: 0.45
        onFinished: if (!app.opened) app.surfaceMapped = false
    }
    TaskManagerState { id: taskState; active: app.opened && !app.minimized }
    Loader {
        id: panelLoader
        anchors.fill: parent
        active: app.surfaceMapped
        onLoaded: if (app.opened) item.focusProcesses()
        sourceComponent: TaskManagerPanel {
            id: panel
            manager: taskState
            enabled: app.opened
            opacity: Math.max(0, Math.min(1, app.reveal))
            scale: 0.985 + 0.015 * app.reveal
            onCloseRequested: app.close()
            onMoveRequested: app.startSystemMove()
        }
    }
    IpcHandler {
        target: "taskManager"
        function open(): void { app.open(); }
        function close(): void { app.close(); }
        function toggle(): void { app.toggle(); }
    }
}
