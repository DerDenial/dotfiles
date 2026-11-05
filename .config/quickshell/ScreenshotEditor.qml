pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "Theme" as ThemeApi

PanelWindow {
    id: editor
    property bool opened: false
    property bool closing: false
    property bool preparing: false
    property bool capturing: false
    property bool exporting: false
    property bool retake: false
    property bool canCapture: true
    readonly property bool active: opened || closing || preparing || capturing || exporting || retake
    property real reveal: 0
    property string homePath: Quickshell.env("HOME") || StandardPaths.writableLocation(StandardPaths.HomeLocation)
    readonly property string helperPath: homePath + "/.config/quickshell/Screenshots/backend.py"
    property string appName: "Desktop"
    property string session: ""
    property url imageSource: ""
    property int imageWidth: 0
    property int imageHeight: 0
    property string errorText: ""
    property bool captureCancelled: false
    property var captureReply: null
    property var exportReply: null
    property string exportPayload: ""
    property string exportAction: ""
    property bool exportCancelled: false
    property bool exportTimedOut: false
    property var cleanupQueue: []
    property bool cleanupPending: false
    property string cleanupToken: ""
    readonly property ScreenshotEditorBody body: bodyLoader.item as ScreenshotEditorBody

    signal aboutToCapture()

    function fileUrl(path) {
        return "file://" + String(path).split("/").map(part => encodeURIComponent(part)).join("/");
    }

    function sourceAppName() {
        let window = ToplevelManager.activeToplevel
            || (Hyprland.activeToplevel ? Hyprland.activeToplevel.wayland : null);
        for (let depth = 0; window && window.parent && depth < 16; ++depth) window = window.parent;
        if (!window) return "Desktop";
        const desktop = DesktopEntries.heuristicLookup(String(window.appId || ""));
        return String(desktop && desktop.name ? desktop.name : window.appId || "Screenshot");
    }

    function chooseScreen(region) {
        const screens = Array.from(Quickshell.screens);
        let target = null;
        if (region && Number.isFinite(region.x) && Number.isFinite(region.y)) {
            const x = region.x + region.width / 2;
            const y = region.y + region.height / 2;
            target = screens.find(candidate => x >= candidate.x && y >= candidate.y
                && x < candidate.x + candidate.width && y < candidate.y + candidate.height);
        }
        const monitor = Hyprland.focusedMonitor;
        target = target || (monitor ? screens.find(candidate => candidate.name === monitor.name) : null) || screens[0];
        if (target) editor.screen = target;
    }

    function capture() {
        if (preparing || capturing || exporting) return;
        if (opened || closing || session || cleanupPending || cleanupQueue.length) {
            retake = true;
            close(true);
            return;
        }
        beginCapture();
    }

    function beginCapture() {
        if (preparing || capturing || opened || closing || exporting) return;
        appName = sourceAppName();
        chooseScreen(null);
        preparing = true;
        retake = false;
        errorText = "";
        aboutToCapture();
        if (canCapture) captureDelay.restart();
    }

    function launchCapture() {
        if (!preparing || !canCapture) return;
        captureCancelled = false;
        captureReply = null;
        captureJob.command = ["python3", helperPath, "capture-region", "--app-name=" + appName];
        capturing = true;
        preparing = false;
        captureJob.running = true;
    }

    function validSession(value) {
        return typeof value === "string" && /^[a-f0-9]{32}$/.test(value);
    }

    function finishCapture() {
        if (!capturing || captureJob.running) return;
        captureKill.stop();
        const response = captureReply;
        const cancelled = captureCancelled || response && response.cancelled;
        if (cancelled) {
            if (response && validSession(response.session)) enqueueCleanup(response.session);
            capturing = false;
            finishClose();
            return;
        }
        if (!response || !response.ok || !validSession(response.session)
            || typeof response.path !== "string" || !response.path.startsWith("/")
            || !(response.width > 0 && response.height > 0)) {
            if (response && validSession(response.session)) enqueueCleanup(response.session);
            capturing = false;
            notify("Screenshot unavailable", response && response.error ? response.error : "Please try selecting the region again.");
            finishClose();
            return;
        }
        session = response.session;
        imageSource = fileUrl(response.path);
        imageWidth = response.width;
        imageHeight = response.height;
        if (response.appName) appName = response.appName;
        chooseScreen(response.region || response.geometry);
        opened = true;
        capturing = false;
        animate(1);
        Qt.callLater(function() { if (editor.opened && editor.body) editor.body.forceActiveFocus(); });
    }

    function exportImage(action, edit) {
        if (!opened || exporting || !session || (action !== "copy" && action !== "save")) return;
        exportAction = action;
        exportPayload = JSON.stringify(edit);
        exportReply = null;
        exportCancelled = false;
        exportTimedOut = false;
        errorText = "";
        exporting = true;
        exportJob.command = ["python3", helperPath, "render", "--session", session, "--action", action];
        exportDeadline.restart();
        exportJob.running = true;
    }

    function finishExport() {
        if (!exporting || exportJob.running) return;
        exportDeadline.stop();
        exportKill.stop();
        exporting = false;
        exportPayload = "";
        if (exportCancelled || !opened) {
            finishClose();
            return;
        }
        if (exportReply && exportReply.ok) {
            notify(exportAction === "copy" ? "Screenshot copied" : "Screenshot saved",
                exportAction === "copy" ? "Image copied to the clipboard" : "Saved in Pictures/Screenshots");
            close();
        } else {
            errorText = exportReply && exportReply.error ? exportReply.error : "The image could not be exported. Please try again.";
        }
    }

    function close(keepRetake) {
        if (!keepRetake) retake = false;
        captureDelay.stop();
        preparing = false;
        if (capturing) {
            captureCancelled = true;
            captureJob.running = false;
            if (captureJob.running) captureKill.restart();
        }
        if (exporting) {
            exportCancelled = true;
            exportJob.running = false;
            if (exportJob.running) exportKill.restart();
        }
        if (opened) {
            closing = true;
            opened = false;
            if (body) body.focus = false;
            animate(0);
        } else finishClose();
    }

    function finishClose() {
        if (opened || closing || preparing || capturing || exporting) return;
        if (session) {
            const token = session;
            session = "";
            imageSource = "";
            imageWidth = imageHeight = 0;
            enqueueCleanup(token);
        }
        if (retake && !cleanupPending && !cleanupQueue.length) Qt.callLater(function() {
            if (editor.retake && !editor.cleanupPending && !editor.cleanupQueue.length) editor.beginCapture();
        });
    }

    function enqueueCleanup(token) {
        if (!validSession(token) || cleanupQueue.indexOf(token) >= 0) return;
        cleanupQueue = cleanupQueue.concat([token]);
        drainCleanup();
    }

    function drainCleanup() {
        if (cleanupPending || cleanupJob.running || !cleanupQueue.length) return;
        const token = cleanupQueue[0];
        cleanupQueue = cleanupQueue.slice(1);
        cleanupPending = true;
        cleanupToken = token;
        cleanupJob.command = ["python3", helperPath, "cleanup", "--session", token];
        cleanupJob.running = true;
    }

    function finishCleanup() {
        if (!cleanupPending || cleanupJob.running) return;
        cleanupPending = false;
        cleanupToken = "";
        drainCleanup();
        finishClose();
    }

    function notify(title, message) {
        Quickshell.execDetached(["notify-send", "--app-name=Screenshots", title, String(message)]);
    }

    function animate(destination) {
        revealMotion.stop();
        revealMotion.to = destination;
        revealMotion.duration = destination ? 175 : 120;
        revealMotion.start();
    }

    onCanCaptureChanged: {
        if (canCapture && preparing) captureDelay.restart();
        else if (!canCapture) captureDelay.stop();
    }
    Component.onDestruction: {
        const tokens = cleanupQueue.concat([session, cleanupToken, captureReply ? captureReply.session : ""]);
        for (let index = 0; index < tokens.length; ++index) {
            const token = tokens[index];
            if (validSession(token) && tokens.indexOf(token) === index)
                Quickshell.execDetached(["python3", helperPath, "cleanup", "--session", token]);
        }
    }

    visible: opened || closing
    color: "transparent"
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "qs-screenshot-editor"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: Region {
        width: editor.opened ? editor.width : 0
        height: editor.opened ? editor.height : 0
    }

    IpcHandler {
        target: "screenshotEditor"
        function capture(): void { editor.capture(); }
        function close(): void { editor.close(); }
    }

    NumberAnimation {
        id: revealMotion
        target: editor
        property: "reveal"
        easing.type: Easing.OutCubic
        onFinished: if (!editor.opened) {
            editor.closing = false;
            editor.reveal = 0;
            editor.finishClose();
        }
    }
    Timer { id: captureDelay; interval: 70; onTriggered: editor.launchCapture() }
    Timer {
        id: captureKill
        interval: 400
        onTriggered: if (editor.captureCancelled && captureJob.running && Number(captureJob.processId) > 0) captureJob.signal(9)
    }
    Timer {
        id: exportKill
        interval: 400
        onTriggered: if ((editor.exportCancelled || editor.exportTimedOut) && exportJob.running && Number(exportJob.processId) > 0) exportJob.signal(9)
    }
    Timer {
        id: exportDeadline
        interval: 20000
        onTriggered: {
            editor.exportTimedOut = true;
            editor.exportReply = {ok: false, error: "Export took too long. Please try again."};
            exportJob.running = false;
            if (exportJob.running) exportKill.restart();
        }
    }

    Process {
        id: captureJob
        stdout: StdioCollector {
            onStreamFinished: {
                try { editor.captureReply = JSON.parse(text); }
                catch (error) { editor.captureReply = null; }
            }
        }
        stderr: StdioCollector { }
        onStarted: if (editor.captureCancelled) running = false
        onExited: Qt.callLater(editor.finishCapture)
        onRunningChanged: if (!running) Qt.callLater(editor.finishCapture)
    }
    Process {
        id: exportJob
        stdinEnabled: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (editor.exportTimedOut) return;
                try { editor.exportReply = JSON.parse(text); }
                catch (error) { editor.exportReply = null; }
            }
        }
        stderr: StdioCollector { }
        onStarted: {
            if (editor.exportCancelled || editor.exportTimedOut) running = false;
            else write(editor.exportPayload + "\n");
        }
        onExited: Qt.callLater(editor.finishExport)
        onRunningChanged: if (!running) Qt.callLater(editor.finishExport)
    }
    Process {
        id: cleanupJob
        stdout: StdioCollector { }
        stderr: StdioCollector { }
        onExited: Qt.callLater(editor.finishCleanup)
        onRunningChanged: if (!running) Qt.callLater(editor.finishCleanup)
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(ThemeApi.Theme.bgDim, 0.44)
        opacity: editor.reveal
    }
    Loader {
        id: bodyLoader
        anchors.fill: parent
        active: editor.opened || editor.closing
        enabled: editor.opened
        opacity: editor.reveal
        sourceComponent: ScreenshotEditorBody {
            source: editor.imageSource
            imageWidth: editor.imageWidth
            imageHeight: editor.imageHeight
            busy: editor.exporting
            errorText: editor.errorText
            appName: editor.appName
            onCopyRequested: edit => editor.exportImage("copy", edit)
            onSaveRequested: edit => editor.exportImage("save", edit)
            onDismissed: editor.close()
            onNewCaptureRequested: editor.capture()
        }
    }
}
