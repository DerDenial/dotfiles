pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Theme" as ThemeApi

PanelWindow {
    id: windowBar

    property bool opened: false
    property bool closing: false
    property bool pendingOpen: false
    property bool canOpen: true
    readonly property bool active: opened || closing || pendingOpen
    property real reveal: 0
    property string selectedKey: ""
    property string pendingActivation: ""
    property string actionKey: ""
    property point actionAnchor: Qt.point(0, 0)
    readonly property var entries: windowState.entries
    readonly property int selectedIndex: entries.findIndex(entry => entry.key === selectedKey)
    readonly property var selectedEntry: selectedIndex >= 0 ? entries[selectedIndex] : null
    readonly property var actionEntry: actionKey ? entries.find(entry => entry.key === actionKey) || null : null
    readonly property WindowActions actionsMenu: actionsLoader.item as WindowActions
    readonly property var iconView: bodyLoader.item ? bodyLoader.item.iconView : null
    readonly property real tileSize: 52
    readonly property real iconSize: 32
    readonly property real frameInset: 4
    readonly property real frameSize: tileSize - frameInset * 2
    readonly property real frameRadius: 12
    readonly property real indicatorHeight: 2
    readonly property real tileSpacing: 6
    readonly property real tileStride: tileSize + tileSpacing
    readonly property real dockPadding: 10
    readonly property real bottomInset: 24
    readonly property real iconRowWidth: entries.length * tileSize + Math.max(0, entries.length - 1) * tileSpacing
    readonly property real cardWidth: Math.max(0, Math.min(860, width - 32,
        entries.length ? iconRowWidth + dockPadding * 2 : 216))
    readonly property real cardHeight: tileSize + dockPadding * 2
    readonly property real previewHeight: Math.max(0, Math.min(334, height * 0.46,
        height - bottomInset - cardHeight - 48))

    signal aboutToOpen()

    WindowBarState {
        id: windowState
        engaged: windowBar.active || windowBar.pendingActivation !== "" || windowState.pinBusy
        onEntriesChanged: windowBar.reconcileSelection()
        onTargetScreenChanged: {
            if (targetScreen && (windowBar.opened || windowBar.closing))
                windowBar.screen = targetScreen;
        }
    }

    function open() {
        if (opened || pendingOpen || pendingActivation) return;
        // Capture the previous app/monitor before mapping this keyboard surface.
        pendingOpen = true;
        windowState.prepare();
        aboutToOpen();
        if (canOpen) revealBar();
    }

    function revealBar() {
        if (!pendingOpen || !canOpen) return;
        if (!bodyLoader.ensureLoaded()) {
            pendingOpen = false;
            return;
        }
        if (windowState.targetScreen) screen = windowState.targetScreen;
        selectedKey = entries.some(entry => entry.key === windowState.activeKey)
            ? windowState.activeKey : entries.length ? entries[0].key : "";
        opened = true;
        pendingOpen = false;
        closing = false;
        animateReveal(1);
        Qt.callLater(focusBody);
        Qt.callLater(positionSelection);
    }

    function close(keepActivation) {
        closeActions();
        pendingOpen = false;
        if (!keepActivation) pendingActivation = "";
        if (!opened) return;
        closing = true;
        opened = false;
        if (bodyLoader.item) bodyLoader.item.focus = false;
        animateReveal(0);
    }

    function toggle() {
        if (opened || pendingOpen) close();
        else open();
    }

    function animateReveal(destination) {
        revealAnimation.stop();
        revealAnimation.to = destination;
        revealAnimation.duration = destination ? 235 : 155;
        revealAnimation.easing.type = destination ? Easing.OutBack : Easing.InCubic;
        revealAnimation.start();
    }

    function focusBody() {
        if (opened && bodyLoader.item) bodyLoader.item.forceActiveFocus();
    }

    function reconcileSelection() {
        if (!opened && !pendingOpen) return;
        if (actionKey && !entries.some(entry => entry.key === actionKey)) closeActions();
        if (!entries.some(entry => entry.key === selectedKey))
            selectedKey = entries.length ? entries[0].key : "";
        // Metadata changes can replace the JS model without changing the key.
        // Keep the selected icon in view after ListView has applied that model.
        Qt.callLater(positionSelection);
    }

    function positionSelection() {
        if (opened && iconView && selectedIndex >= 0)
            iconView.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    function select(index) {
        if (!opened || actionKey || index < 0 || index >= entries.length) return;
        selectedKey = entries[index].key;
        positionSelection();
    }

    function moveSelection(direction) {
        if (!entries.length) return;
        const current = Math.max(0, selectedIndex);
        select((current + direction + entries.length) % entries.length);
    }

    function accept(index) {
        if (!opened || index < 0 || index >= entries.length) return;
        selectedKey = entries[index].key;
        pendingActivation = selectedKey;
        close(true);
    }

    function openActions(index, anchor) {
        if (!opened || index < 0 || index >= entries.length) return;
        actionKey = "";
        selectedKey = entries[index].key;
        actionAnchor = anchor || (iconView
            ? iconView.contentItem.mapToItem(windowBar.contentItem, index * tileStride + tileSize / 2, 0)
            : Qt.point(card.x + card.width / 2, card.y));
        actionKey = selectedKey;
        windowState.refreshActions();
        positionSelection();
        Qt.callLater(focusBody);
    }

    function closeActions() {
        actionKey = "";
    }

    function performAction(action, target) {
        const key = actionKey;
        if (!key) return;
        let requested = false;
        if (action === "close") requested = windowState.closeWindow(key);
        else if (action === "float") requested = windowState.toggleFloating(key);
        else if (action === "pin") requested = windowState.togglePinned(key);
        else if (action === "move") requested = windowState.moveToWorkspace(key, target);
        if (!requested) {
            if (actionsMenu) actionsMenu.errorText = windowState.actionError || "This window is no longer available.";
            return;
        }
        closeActions();
        // Let any application save dialog receive focus after a normal close request.
        if (action === "close") close();
    }

    function togglePin(key) {
        if (!opened) return;
        windowState.togglePinned(key);
    }

    function activatePending() {
        // Wait until the layer is unmapped and its exclusive grab has ended.
        if (!pendingActivation || opened || closing || pendingOpen || visible
            || (card.Window.window && card.Window.window.active)) return;
        const key = pendingActivation;
        windowState.activate(key);
        pendingActivation = "";
    }

    function handleKey(event) {
        if (event.isAutoRepeat && (event.key === Qt.Key_Escape || event.key === Qt.Key_Return
            || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
            event.accepted = true;
            return;
        }
        if (actionKey && actionsMenu) {
            actionsMenu.handleKey(event);
            return;
        }
        if (event.key === Qt.Key_Escape) close();
        else if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && event.modifiers & Qt.ShiftModifier))
            openActions(selectedIndex, null);
        else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Backtab)
            moveSelection(-1);
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down)
            moveSelection(1);
        else if (event.key === Qt.Key_Tab)
            moveSelection(event.modifiers & Qt.ShiftModifier ? -1 : 1);
        else if (event.key === Qt.Key_Home) select(0);
        else if (event.key === Qt.Key_End) select(entries.length - 1);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
            accept(selectedIndex);
        else return;
        event.accepted = true;
    }

    onCanOpenChanged: if (canOpen && pendingOpen) revealBar()
    onCardWidthChanged: if (opened) Qt.callLater(positionSelection)
    onVisibleChanged: if (!visible) Qt.callLater(activatePending)

    visible: opened || closing
    color: "transparent"
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "qs-window-hotbar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // Closing visuals never keep an invisible pointer-input surface behind.
    mask: Region {
        width: windowBar.opened ? windowBar.width : 0
        height: windowBar.opened ? windowBar.height : 0
    }

    IpcHandler {
        target: "windowBar"
        function toggle(): void { windowBar.toggle(); }
        function open(): void { windowBar.open(); }
        function close(): void { windowBar.close(); }
    }

    Connections {
        target: card.Window.window
        function onActiveChanged() {
            if (windowBar.opened) Qt.callLater(windowBar.focusBody);
            else Qt.callLater(windowBar.activatePending);
        }
    }

    NumberAnimation {
        id: revealAnimation
        target: windowBar
        property: "reveal"
        easing.overshoot: 0.55
        onFinished: {
            if (!windowBar.opened) {
                windowBar.reveal = 0;
                windowBar.closing = false;
                Qt.callLater(windowBar.activatePending);
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: windowBar.opened
        onClicked: windowBar.close()
    }

    Loader {
        id: previewLoader
        active: (windowBar.opened || windowBar.closing) && windowBar.selectedEntry !== null
            && windowBar.previewHeight >= 100 && width >= 160
        width: Math.max(0, Math.min(520, windowBar.width - 64))
        height: windowBar.previewHeight
        x: (windowBar.width - width) / 2
        y: Math.max(16, Math.min((windowBar.height - height) / 2,
            windowBar.height - windowBar.bottomInset - windowBar.cardHeight - height - 24))
            + (1 - windowBar.reveal) * 18
        sourceComponent: WindowPreview {
            id: windowPreview
            entry: windowBar.selectedEntry
            onPinRequested: key => windowBar.togglePin(key)
            capturing: windowBar.opened
            reveal: windowBar.reveal
            onActivated: windowBar.accept(windowBar.selectedIndex)
            onContextRequested: position => windowBar.openActions(windowBar.selectedIndex,
                windowPreview.mapToItem(windowBar.contentItem, position.x, position.y))
            onCloseRequested: key => {
                if (windowBar.opened && windowState.closeWindow(key)) windowBar.close();
            }
        }
    }

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: windowBar.height - windowBar.bottomInset - height + (1 - windowBar.reveal) * 24
        width: windowBar.cardWidth
        height: windowBar.cardHeight
        radius: 20
        color: Qt.alpha(ThemeApi.Theme.bg0, 0.25)
        border.width: 1
        border.color: Qt.alpha(ThemeApi.Theme.border, 0.45)
        opacity: Math.max(0, Math.min(1, windowBar.reveal * 1.6))

        MouseArea {
            anchors.fill: parent
            enabled: windowBar.opened
            onClicked: mouse => { mouse.accepted = true; }
        }

        MenuBodyLoader {
            id: bodyLoader
            anchors.fill: parent
            anchors.margins: windowBar.dockPadding
            engaged: windowBar.active
            enabled: windowBar.opened
            sourceComponent: FocusScope {
                id: body
                property alias iconView: icons
                anchors.fill: parent
                focus: windowBar.opened
                Keys.onPressed: event => windowBar.handleKey(event)

                ListView {
                    id: icons
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(body.width, windowBar.iconRowWidth)
                    height: windowBar.tileSize
                    orientation: ListView.Horizontal
                    spacing: windowBar.tileSpacing
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    model: windowBar.entries
                    currentIndex: windowBar.selectedIndex
                    highlight: null

                    SelectionTrail {
                        id: selection
                        parent: icons.contentItem
                        z: 0
                        width: icons.width
                        height: icons.height
                        targetRect: Qt.rect(Math.max(0, windowBar.selectedIndex) * windowBar.tileStride + windowBar.frameInset,
                            windowBar.frameInset, windowBar.frameSize, windowBar.frameSize)
                        engaged: windowBar.entries.length > 0 && windowBar.selectedIndex >= 0 && (windowBar.opened || windowBar.closing)
                        animate: windowBar.opened && !windowBar.closing
                        accentColor: ThemeApi.Theme.accent
                        surfaceColor: Qt.alpha(ThemeApi.Theme.surface, 0.48)
                        radius: windowBar.frameRadius
                        headDuration: 175
                        tailDuration: 235
                        echoCount: 2
                        echoOpacity: 0.45
                        maxTrailLength: windowBar.tileSize
                    }

                    delegate: Item {
                        id: tile
                        required property int index
                        required property var modelData
                        readonly property bool selected: index === windowBar.selectedIndex
                        width: windowBar.tileSize
                        height: windowBar.tileSize
                        z: 1
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.appName + ": " + modelData.title
                        Accessible.onPressAction: windowBar.accept(tile.index)

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: windowBar.frameInset
                            radius: windowBar.frameRadius
                            color: tileMouse.containsMouse && !tile.selected ? Qt.alpha(ThemeApi.Theme.surface, 0.52) : "transparent"
                        }
                        Image {
                            id: iconImage
                            anchors.centerIn: parent
                            width: windowBar.iconSize
                            height: windowBar.iconSize
                            source: tile.modelData.icon
                            sourceSize.width: windowBar.iconSize * 2
                            sourceSize.height: windowBar.iconSize * 2
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            visible: status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: iconImage
                            text: "web_asset"
                            color: ThemeApi.Theme.accent
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 28
                            visible: iconImage.status !== Image.Ready
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: windowBar.tileSize - windowBar.indicatorHeight
                            width: tile.modelData.key === windowState.activeKey ? 12 : 3
                            height: windowBar.indicatorHeight
                            radius: 2
                            color: tile.modelData.key === windowState.activeKey ? ThemeApi.Theme.accent : ThemeApi.Theme.muted
                            opacity: tile.modelData.key === windowState.activeKey ? 1 : 0.55
                        }
                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onEntered: windowBar.select(tile.index)
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton)
                                    windowBar.openActions(tile.index,
                                        tile.mapToItem(windowBar.contentItem, tile.width / 2, 0));
                                else windowBar.accept(tile.index);
                            }
                        }
                        ToolTip.visible: tileMouse.containsMouse && !windowBar.actionKey
                        ToolTip.delay: 500
                        ToolTip.text: tile.modelData.title + (tile.modelData.workspace ? "\nWorkspace " + tile.modelData.workspace : "")
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: windowBar.entries.length === 0
                    text: "No open windows"
                    color: ThemeApi.Theme.muted
                    font.family: "Inter"
                    font.pixelSize: 11
                }
            }
        }
    }

    Rectangle {
        visible: windowBar.opened && windowState.actionError !== ""
        anchors.horizontalCenter: card.horizontalCenter
        y: card.y - height - 10
        width: Math.min(windowBar.width - 48, errorLabel.implicitWidth + 28)
        height: errorLabel.implicitHeight + 18
        radius: 12
        color: Qt.alpha(ThemeApi.Theme.bg0, 0.92)
        border.width: 1
        border.color: Qt.alpha(ThemeApi.Theme.red, 0.35)
        Text {
            id: errorLabel
            anchors.centerIn: parent
            width: Math.min(implicitWidth, windowBar.width - 76)
            text: windowState.actionError
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: ThemeApi.Theme.red
            font.family: "Inter"
            font.pixelSize: 11
        }
    }

    MouseArea {
        z: 20
        anchors.fill: parent
        enabled: windowBar.opened && windowBar.actionKey !== ""
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: windowBar.closeActions()
        onWheel: wheel => { wheel.accepted = true; }
    }

    Loader {
        id: actionsLoader
        z: 21
        active: windowBar.opened && windowBar.actionEntry !== null
        width: Math.max(0, Math.min(272, windowBar.width - 32))
        x: Math.max(16, Math.min(windowBar.actionAnchor.x - width / 2, windowBar.width - width - 16))
        y: Math.max(16, Math.min(windowBar.actionAnchor.y - height - 10, windowBar.height - height - 16))
        sourceComponent: WindowActions {
            entry: windowBar.actionEntry
            workspaces: windowState.workspaceChoices
            maximumHeight: Math.max(0, windowBar.height - 32)
            onDismissed: windowBar.closeActions()
            onInvoked: (action, target) => windowBar.performAction(action, target)
        }
    }
}
