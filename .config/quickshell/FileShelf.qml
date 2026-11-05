pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "Theme" as ThemeApi

// A non-modal shelf on the already mapped panel. Only its card and the notch
// are in the input mask, leaving applications usable while files are parked.
FocusScope {
    id: host
    required property FileShelfState shelfState
    property Item notch: null
    property bool available: true
    property bool canOpen: true
    property bool opened: false
    property bool closing: false
    property bool pendingOpen: false
    property bool closePending: false
    property real reveal: 0
    readonly property bool active: opened || closing || pendingOpen || shelfState.dragging
    readonly property Item inputSurface: surface.visible ? surface : null
    readonly property bool incoming: notchDrop.containsDrag || cardDrop.containsDrag
    readonly property var panel: bodyLoader.item
    readonly property real targetHeight: Math.max(150, Math.min(height - 58, (panel ? panel.implicitHeight : 180) + 36))
    signal aboutToOpen()
    signal fullyClosed()

    function open() {
        if (!available || opened || pendingOpen) return;
        closePending = false;
        pendingOpen = true;
        aboutToOpen();
        if (canOpen) revealShelf();
    }
    function revealShelf() {
        if (!pendingOpen || !canOpen || !available) return;
        // Resolve the panel height before the opening animation is visible.
        if (!bodyLoader.ensureLoaded()) { pendingOpen = false; return; }
        opened = true;
        pendingOpen = closing = false;
        shelfState.refresh();
        animateTo(1);
        Qt.callLater(function() { if (host.opened) host.forceActiveFocus(); });
    }
    function requestClose() {
        pendingOpen = false;
        if (shelfState.dragging) { closePending = true; return; }
        closePending = false;
        if (!opened) return;
        closing = true;
        opened = false;
        animateTo(0);
    }
    function toggle() { opened || pendingOpen ? requestClose() : open(); }
    function animateTo(value) {
        revealMotion.stop();
        revealMotion.to = value;
        revealMotion.duration = value ? 200 : 145;
        revealMotion.easing.type = value ? Easing.OutBack : Easing.OutCubic;
        revealMotion.start();
    }
    function localFiles(event) {
        return !shelfState.dragging && event.hasUrls && event.urls.length > 0
            && (event.supportedActions & Qt.CopyAction) !== 0
            && event.urls.length <= 256
            && Array.from(event.urls).every(url => /^file:\/\/(?:localhost)?\//i.test(String(url)));
    }
    function enterFiles(event) {
        if (!available || !localFiles(event)) { event.accepted = false; return; }
        event.action = Qt.CopyAction;
        event.accepted = true;
        open();
    }
    function dropFiles(event) {
        if (!available || !localFiles(event)) { event.accepted = false; return; }
        // DragEvent is borrowed from Qt; never retain it across asynchronous work.
        const urls = Array.from(event.urls, url => String(url));
        if (shelfState.addUrls(urls)) { event.accept(Qt.CopyAction); open(); }
        else event.accepted = false;
    }
    onCanOpenChanged: if (canOpen && pendingOpen) revealShelf()
    onAvailableChanged: if (!available) requestClose()
    Keys.onEscapePressed: if (opened && !shelfState.dragging) requestClose()
    Connections {
        target: host.shelfState
        function onDragEnded() { if (host.closePending) host.requestClose(); }
    }
    IpcHandler {
        target: "fileShelf"
        function toggle(): void { host.toggle(); }
        function open(): void { host.open(); }
        function close(): void { host.requestClose(); }
    }
    NumberAnimation {
        id: revealMotion
        target: host
        property: "reveal"
        easing.overshoot: 0.45
        onFinished: if (!host.opened) { host.closing = false; host.fullyClosed(); }
    }
    DropArea {
        id: notchDrop
        objectName: "shelfNotchDrop"
        x: (host.width - width) / 2
        y: 0
        width: host.notch ? host.notch.width : 236
        height: host.notch ? host.notch.height : 34
        enabled: host.available && !host.shelfState.dragging
        onEntered: event => host.enterFiles(event)
        onPositionChanged: event => {
            event.accepted = host.localFiles(event);
            if (event.accepted) event.action = Qt.CopyAction;
        }
        onDropped: event => host.dropFiles(event)
        Rectangle {
            anchors.fill: parent
            visible: notchDrop.containsDrag
            topLeftRadius: 0
            topRightRadius: 0
            bottomLeftRadius: host.notch ? host.notch.bottomLeftRadius : 17
            bottomRightRadius: bottomLeftRadius
            color: ThemeApi.Theme.notchBg
            border.width: 1
            border.color: ThemeApi.Theme.accent
            Row {
                anchors.centerIn: parent
                spacing: 6
                Text { text: "add"; font.family: "Material Symbols Rounded"; font.pixelSize: 17; color: ThemeApi.Theme.accent }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Drop files"; font.family: "Inter"; font.pixelSize: 11; font.weight: Font.DemiBold; color: ThemeApi.Theme.accent }
            }
        }
    }
    Rectangle {
        id: surface
        objectName: "fileShelfSurface"
        visible: host.opened || host.closing || host.shelfState.dragging
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(240, Math.min(568, host.width - 32))
        height: host.targetHeight
        y: 42 - 10 * (1 - host.reveal)
        radius: 24
        color: ThemeApi.Theme.notchBg
        border.width: 1
        border.color: host.incoming ? ThemeApi.Theme.accent : ThemeApi.Theme.border
        opacity: Math.max(0, Math.min(1, host.reveal))
        scale: 0.985 + 0.015 * host.reveal
        transformOrigin: Item.Top
        Behavior on height { enabled: host.opened && !host.shelfState.dragging; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        // The drop targets and surface stay mapped; only idle visual controls
        // retire. A native drag must keep its exact source delegate alive.
        MenuBodyLoader {
            id: bodyLoader
            objectName: "shelfBodyLoader"
            anchors.fill: parent
            anchors.margins: 18
            engaged: host.active || host.closePending || host.incoming
            sourceComponent: FileShelfPanel {
                shelf: host.shelfState
                opened: host.opened
                presented: surface.visible
                onCloseRequested: host.requestClose()
            }
        }
        DropArea {
            id: cardDrop
            objectName: "shelfCardDrop"
            anchors.fill: parent
            enabled: host.available && !host.shelfState.dragging
            onEntered: event => host.enterFiles(event)
            onPositionChanged: event => {
                event.accepted = host.localFiles(event);
                if (event.accepted) event.action = Qt.CopyAction;
            }
            onDropped: event => host.dropFiles(event)
        }
    }
}
