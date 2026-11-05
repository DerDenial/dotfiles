pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Theme" as ThemeApi

PanelWindow {
    id: powerMenu

    property alias opened: menuTransition.opened
    property alias closing: menuTransition.closing
    readonly property bool active: menuTransition.active
    readonly property bool ownsSurface: menuTransition.ownsSurface
    readonly property bool returning: menuTransition.returning
    readonly property real morphProgress: menuTransition.motion.amount
    property Item sourceNotch: null
    property bool canOpen: true
    property string clockValue: "00:00"
    property int batteryLevel: 0
    property bool batteryCharging: false

    property int selectedIndex: 0
    property string confirmationAction: ""
    property bool confirmationAccept: false
    property string pendingAction: ""
    property string executingAction: ""
    property string error: ""
    property bool processStarted: false
    readonly property bool busy: pendingAction !== "" || executingAction !== "" || actionProcess.running
    readonly property var actions: [
        { id: "lock", label: "Lock", detail: "Keep your session open", icon: "lock" },
        { id: "logout", label: "Log out", detail: "End your session", icon: "logout" },
        { id: "restart", label: "Restart", detail: "Restart the computer", icon: "restart_alt" },
        { id: "shutdown", label: "Shut down", detail: "Turn off the computer", icon: "power_settings_new" }
    ]
    readonly property var confirmationEntry: actions.find(function(entry) { return entry.id === powerMenu.confirmationAction; }) || null
    readonly property string confirmationMessage: confirmationAction === "logout"
        ? "Your session will end. Save any open documents first."
        : confirmationAction === "restart"
        ? "Your computer will restart. Save any open documents first."
        : "Your computer will shut down. Save any open documents first."
    signal aboutToOpen()

    NotchTransition {
        id: menuTransition
        dropdownAlignment: 1
        surface: card
        sourceNotch: powerMenu.sourceNotch
        canOpen: powerMenu.canOpen
        expandedWidth: Math.min(260, powerMenu.width - 32)
        expandedHeight: Math.min(84, powerMenu.height - (menuTransition.dropdown ? 58 : 24))
        onAboutToOpen: powerMenu.aboutToOpen()
        onActivated: Qt.callLater(powerMenu.focusBody)
        onActiveChanged: if (!menuTransition.active) Qt.callLater(powerMenu.runPendingAction)
    }

    function open() {
        if (busy || opened || menuTransition.preparing || menuTransition.capturePending) return;
        if (!bodyLoader.ensureLoaded()) return;
        selectedIndex = 0;
        confirmationAction = "";
        confirmationAccept = false;
        menuTransition.open();
    }
    function close() {
        // Keep the current page visible through the closing morph.
        // The next open resets confirmation to the safe Cancel selection.
        menuTransition.close();
        if (bodyLoader.item) bodyLoader.item.focus = false;
    }
    function toggle() {
        if (opened || menuTransition.pendingOpen || menuTransition.preparing || menuTransition.capturePending) close();
        else open();
    }
    function focusBody() {
        if (opened && bodyLoader.item) bodyLoader.item.forceActiveFocus();
    }
    function choose(index) {
        if (busy || !opened || index < 0 || index >= actions.length) return;
        selectedIndex = index;
        error = "";
        if (actions[index].id === "lock") commit("lock");
        else {
            confirmationAction = actions[index].id;
            confirmationAccept = false;
            focusBody();
        }
    }
    function cancelConfirmation() {
        confirmationAction = "";
        confirmationAccept = false;
        focusBody();
    }
    function commit(action) {
        if (busy || !opened || !actions.some(function(entry) { return entry.id === action; })) return;
        pendingAction = action;
        error = "";
        close();
        Qt.callLater(runPendingAction);
    }
    function commandFor(action) {
        switch (action) {
        case "shutdown": return ["python3", Quickshell.env("HOME") + "/.config/quickshell/session-power.py", "poweroff"];
        case "restart": return ["python3", Quickshell.env("HOME") + "/.config/quickshell/session-power.py", "reboot"];
        case "logout": return ["python3", Quickshell.env("HOME") + "/.config/quickshell/Logout/launch.py"];
        default: return [];
        }
    }
    function runPendingAction() {
        // Wait for both the morph handoff and the exclusive keyboard grab to end.
        if (!pendingAction || active || actionProcess.running || (card.Window.window && card.Window.window.active)) return;
        const action = pendingAction;
        pendingAction = "";
        if (action === "lock") {
            // A real screen lock must outlive a Quickshell reload or restart.
            Quickshell.execDetached(["python3", Quickshell.env("HOME") + "/.config/quickshell/LockScreen/lock.py"]);
            return;
        }
        const command = commandFor(action);
        if (!command.length) return;
        executingAction = action;
        processStarted = false;
        actionProcess.command = command;
        actionProcess.running = true;
        startGuard.restart();
    }
    function actionFailed() {
        if (!executingAction) return;
        const action = executingAction;
        executingAction = "";
        processStarted = false;
        startGuard.stop();
        error = action === "lock" ? "Could not lock. Please try again."
            : action === "logout" ? "Could not log out. Please try again."
            : action === "restart" ? "Could not restart. Please try again."
            : "Could not shut down. Please try again.";
        Qt.callLater(open);
    }
    function handleKey(event) {
        if (event.isAutoRepeat) {
            if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Escape, Qt.Key_Space].indexOf(event.key) >= 0) event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Escape) {
            close();
        } else if (confirmationAction) {
            if ([Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down, Qt.Key_Tab, Qt.Key_Backtab].indexOf(event.key) >= 0)
                confirmationAccept = !confirmationAccept;
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                if (confirmationAccept) commit(confirmationAction);
                else cancelConfirmation();
            } else return;
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) selectedIndex = (selectedIndex + 3) % 4;
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) selectedIndex = (selectedIndex + 1) % 4;
        else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
            selectedIndex = (selectedIndex + (event.key === Qt.Key_Backtab || event.modifiers & Qt.ShiftModifier ? 3 : 1)) % 4;
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) choose(selectedIndex);
        else return;
        event.accepted = true;
    }

    // Keep the process alive even after the visual content has been released.
    Process {
        id: actionProcess
        stderr: StdioCollector {
            onStreamFinished: if (text.trim()) console.warn("Power menu action:", text.trim())
        }
        onStarted: {
            powerMenu.processStarted = true;
            startGuard.stop();
        }
        onExited: function(exitCode, exitStatus) {
            startGuard.stop();
            if (exitCode !== 0 || exitStatus !== 0) powerMenu.actionFailed();
            else {
                powerMenu.executingAction = "";
                powerMenu.processStarted = false;
            }
        }
        onRunningChanged: if (!running) Qt.callLater(function() {
            if (!actionProcess.running && powerMenu.executingAction && !powerMenu.processStarted) powerMenu.actionFailed();
        })
    }
    Timer {
        id: startGuard
        interval: 1800
        onTriggered: if (!actionProcess.running && powerMenu.executingAction && !powerMenu.processStarted) powerMenu.actionFailed()
    }
    property Connections inputFocus: Connections {
        target: card.Window.window
        function onActiveChanged() {
            if (powerMenu.opened) Qt.callLater(powerMenu.focusBody);
            else Qt.callLater(powerMenu.runPendingAction);
        }
    }

    visible: menuTransition.visible
    color: "transparent"
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.keyboardFocus: opened || menuTransition.preparing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    IpcHandler {
        target: "powerMenu"
        function toggle(): void { powerMenu.toggle(); }
        function open(): void { powerMenu.open(); }
        function close(): void { powerMenu.close(); }
    }

    MouseArea { anchors.fill: parent; enabled: powerMenu.opened; onClicked: powerMenu.close() }

    NotchMenuSurface {
        id: card
        transition: menuTransition
        color: ThemeApi.Theme.notchBg
        border.width: 1
        border.color: Qt.alpha(ThemeApi.Theme.border, 0.65)

        Rectangle { visible: !menuTransition.dropdown; x: 0; y: 0; width: parent.width; height: parent.border.width; color: parent.color; z: 100 }
        MouseArea { anchors.fill: parent; enabled: powerMenu.opened }

        MenuBodyLoader {
            id: bodyLoader
            engaged: menuTransition.active || menuTransition.pendingOpen
            width: menuTransition.expandedWidth - 24
            height: menuTransition.expandedHeight - 20
            anchors.horizontalCenter: parent.horizontalCenter
            y: 10 * Math.min(1, bodyStretch.unfold)
            enabled: powerMenu.opened && !powerMenu.busy
            visible: powerMenu.opened || powerMenu.closing
            transform: NotchContentStretch {
                id: bodyStretch
                transition: menuTransition
                canvasWidth: menuTransition.expandedWidth - 24
                horizontalInset: 24
            }
            sourceComponent: Component {
                FocusScope {
                    id: menuBody
                    anchors.fill: parent
                    Keys.onPressed: function(event) { powerMenu.handleKey(event); }
                    Item {
                        anchors.fill: parent
                        visible: powerMenu.confirmationAction === ""
                        SelectionTrail {
                            id: actionSelection
                            objectName: "powerMainSelection"
                            anchors.fill: actionRow
                            targetRect: Qt.rect(powerMenu.selectedIndex * (actionRow.cellSize + actionRow.spacing),
                                0, actionRow.cellSize, actionRow.cellSize)
                            engaged: (powerMenu.opened || powerMenu.closing) && powerMenu.confirmationAction === ""
                            animate: powerMenu.opened && !powerMenu.closing
                            accentColor: ThemeApi.Theme.accent
                            surfaceColor: ThemeApi.Theme.accent
                            radius: 12
                            headDuration: 180
                            tailDuration: 300
                            echoCount: 4
                            echoOpacity: 1.1
                            maxTrailLength: actionRow.cellSize
                        }
                        Row {
                            id: actionRow
                            z: 1
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: Math.max(0, (parent.height - cellSize - 10) / 2)
                            spacing: 8
                            readonly property real cellSize: Math.max(24, Math.min(40,
                                (parent.width - spacing * 3) / 4, parent.height - 10))
                            Repeater {
                                model: powerMenu.actions
                                delegate: Item {
                                    id: actionButton
                                    property string symbol
                                    property string label
                                    property string description
                                    property bool chosen
                                    property bool filled
                                    signal previewRequested()
                                    signal activated()
                                    implicitWidth: 36
                                    implicitHeight: 36
                                    Accessible.role: Accessible.Button
                                    Accessible.name: label
                                    Accessible.description: description
                                    Accessible.onPressAction: activated()
                                    Rectangle {
                                        // Keep tile backplates below the moving head and echoes.
                                        parent: actionSelection
                                        objectName: actionButton.objectName + "Backdrop"
                                        z: -1
                                        x: actionButton.x
                                        y: actionButton.y
                                        width: actionButton.width
                                        height: actionButton.height
                                        radius: 12
                                        color: "transparent"
                                        gradient: Gradient {
                                            GradientStop {
                                                position: 0
                                                color: actionButton.chosen ? "transparent" : Qt.alpha(ThemeApi.Theme.surfaceRaised, actionPointer.containsMouse ? 0.88 : 0.66)
                                            }
                                            GradientStop {
                                                position: 1
                                                color: actionButton.chosen ? "transparent" : Qt.alpha(ThemeApi.Theme.surface, 0.62)
                                            }
                                        }
                                        border.width: actionButton.chosen ? 0 : 1
                                        border.color: Qt.alpha(ThemeApi.Theme.border, actionPointer.containsMouse ? 0.55 : 0.25)
                                        scale: actionPointer.pressed ? 0.94 : 1
                                        Behavior on scale { NumberAnimation { duration: 135; easing.type: Easing.OutCubic } }
                                        Rectangle {
                                            x: 8; y: 1
                                            width: Math.max(0, parent.width - 16); height: 1
                                            radius: 1
                                            color: Qt.alpha(ThemeApi.Theme.textBright, 0.065)
                                            visible: !actionButton.chosen
                                        }
                                        Text {
                                            // Symbols and input stay above the shared selection layer.
                                            parent: actionButton
                                            anchors.centerIn: parent
                                            anchors.verticalCenterOffset: actionButton.chosen ? -1 : 0
                                            text: actionButton.symbol
                                            font.family: "Material Symbols Rounded"
                                            font.pixelSize: Math.min(18, actionButton.width * 0.45)
                                            color: actionButton.chosen ? ThemeApi.Theme.onAccent : ThemeApi.Theme.muted
                                            scale: (actionButton.chosen ? 1.07 : 1) * (actionPointer.pressed ? 0.94 : 1)
                                            Behavior on scale { NumberAnimation { duration: 190; easing.type: Easing.OutBack; easing.overshoot: 0.55 } }
                                            Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 190; easing.type: Easing.OutBack; easing.overshoot: 0.55 } }
                                        }
                                    }
                                    MouseArea {
                                        id: actionPointer
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: actionButton.previewRequested()
                                        onPositionChanged: actionButton.previewRequested()
                                        onClicked: actionButton.activated()
                                    }
                                    ToolTip.visible: powerMenu.opened && actionPointer.containsMouse
                                    ToolTip.delay: 550
                                    ToolTip.text: label
                                    required property int index
                                    required property var modelData
                                    objectName: "powerAction" + index
                                    width: actionRow.cellSize
                                    height: width
                                    symbol: modelData.icon
                                    label: modelData.label
                                    description: modelData.detail
                                    chosen: powerMenu.selectedIndex === index
                                    onPreviewRequested: powerMenu.selectedIndex = index
                                    onActivated: powerMenu.choose(index)
                                }
                            }
                        }
                        Rectangle {
                            x: actionRow.x + actionSelection.headX + (actionSelection.headWidth - width) / 2
                            y: actionRow.y + actionRow.height + 6
                            width: 10; height: 2; radius: 1
                            color: ThemeApi.Theme.accent
                            opacity: 0.65
                        }
                    }

                    Item {
                        id: confirmationArea
                        anchors.fill: parent
                        visible: powerMenu.confirmationAction !== ""
                        Row {
                            anchors.centerIn: parent
                            spacing: 8
                            Rectangle {
                                width: confirmationArea.cellSize
                                height: width
                                radius: 12
                                color: Qt.alpha(ThemeApi.Theme.accent, 0.09)
                                border.width: 1
                                border.color: Qt.alpha(ThemeApi.Theme.accent, 0.18)
                                Text {
                                    anchors.centerIn: parent
                                    text: powerMenu.confirmationEntry ? powerMenu.confirmationEntry.icon : "power_settings_new"
                                    color: ThemeApi.Theme.accent
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: 20
                                }
                            }
                            Item {
                                width: 1
                                height: confirmationArea.cellSize
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 1
                                    height: 16
                                    color: ThemeApi.Theme.border
                                    opacity: 0.7
                                }
                            }
                            Item {
                                width: confirmationRow.width
                                height: confirmationArea.cellSize
                                SelectionTrail {
                                    id: confirmationSelection
                                    objectName: "powerConfirmationSelection"
                                    anchors.fill: parent
                                    targetRect: Qt.rect(powerMenu.confirmationAccept ? confirmationArea.cellSize + 8 : 0,
                                        0, confirmationArea.cellSize, confirmationArea.cellSize)
                                    engaged: (powerMenu.opened || powerMenu.closing) && powerMenu.confirmationAction !== ""
                                    animate: powerMenu.opened && !powerMenu.closing
                                    accentColor: ThemeApi.Theme.accent
                                    surfaceColor: ThemeApi.Theme.accent
                                    radius: 12
                                    headDuration: 180
                                    tailDuration: 300
                                    echoCount: 4
                                    echoOpacity: 1.1
                                    maxTrailLength: confirmationArea.cellSize
                                }
                                Row {
                                    id: confirmationRow
                                    z: 1
                                    spacing: 8
                                    Repeater {
                                        model: 2
                                        delegate: Item {
                                            id: confirmButton
                                            property string symbol
                                            property string label
                                            property string description
                                            property bool chosen
                                            property bool filled
                                            signal previewRequested()
                                            signal activated()
                                            implicitWidth: 36
                                            implicitHeight: 36
                                            Accessible.role: Accessible.Button
                                            Accessible.name: label
                                            Accessible.description: description
                                            Accessible.onPressAction: activated()
                                            Rectangle {
                                                // Keep tile backplates below the moving head and echoes.
                                                parent: confirmationSelection
                                                objectName: confirmButton.objectName + "Backdrop"
                                                z: -1
                                                x: confirmButton.x
                                                y: confirmButton.y
                                                width: confirmButton.width
                                                height: confirmButton.height
                                                radius: 12
                                                color: "transparent"
                                                gradient: Gradient {
                                                    GradientStop {
                                                        position: 0
                                                        color: confirmButton.chosen ? "transparent" : Qt.alpha(ThemeApi.Theme.surfaceRaised, confirmPointer.containsMouse ? 0.88 : 0.66)
                                                    }
                                                    GradientStop {
                                                        position: 1
                                                        color: confirmButton.chosen ? "transparent" : Qt.alpha(ThemeApi.Theme.surface, 0.62)
                                                    }
                                                }
                                                border.width: confirmButton.chosen ? 0 : 1
                                                border.color: Qt.alpha(ThemeApi.Theme.border, confirmPointer.containsMouse ? 0.55 : 0.25)
                                                scale: confirmPointer.pressed ? 0.94 : 1
                                                Behavior on scale { NumberAnimation { duration: 135; easing.type: Easing.OutCubic } }
                                                Rectangle {
                                                    x: 8; y: 1
                                                    width: Math.max(0, parent.width - 16); height: 1
                                                    radius: 1
                                                    color: Qt.alpha(ThemeApi.Theme.textBright, 0.065)
                                                    visible: !confirmButton.chosen
                                                }
                                                Text {
                                                    // Symbols and input stay above the shared selection layer.
                                                    parent: confirmButton
                                                    anchors.centerIn: parent
                                                    anchors.verticalCenterOffset: confirmButton.chosen ? -1 : 0
                                                    text: confirmButton.symbol
                                                    font.family: "Material Symbols Rounded"
                                                    font.pixelSize: Math.min(18, confirmButton.width * 0.45)
                                                    color: confirmButton.chosen ? ThemeApi.Theme.onAccent : ThemeApi.Theme.muted
                                                    scale: (confirmButton.chosen ? 1.07 : 1) * (confirmPointer.pressed ? 0.94 : 1)
                                                    Behavior on scale { NumberAnimation { duration: 190; easing.type: Easing.OutBack; easing.overshoot: 0.55 } }
                                                    Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 190; easing.type: Easing.OutBack; easing.overshoot: 0.55 } }
                                                }
                                            }
                                            MouseArea {
                                                id: confirmPointer
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onEntered: confirmButton.previewRequested()
                                                onPositionChanged: confirmButton.previewRequested()
                                                onClicked: confirmButton.activated()
                                            }
                                            ToolTip.visible: powerMenu.opened && confirmPointer.containsMouse
                                            ToolTip.delay: 550
                                            ToolTip.text: label
                                            required property int index
                                            objectName: index === 0 ? "powerCancel" : "powerConfirm"
                                            width: confirmationArea.cellSize
                                            height: width
                                            symbol: index === 0 ? "close" : "check"
                                            label: index === 0 ? "Cancel"
                                                : powerMenu.confirmationEntry ? powerMenu.confirmationEntry.label : "Confirm"
                                            description: index === 0 ? "Return to power actions" : powerMenu.confirmationMessage
                                            chosen: powerMenu.confirmationAccept === (index === 1)
                                            filled: true
                                            onPreviewRequested: powerMenu.confirmationAccept = index === 1
                                            onActivated: {
                                                if (index === 1) powerMenu.commit(powerMenu.confirmationAction);
                                                else powerMenu.cancelConfirmation();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        readonly property real cellSize: Math.max(20, Math.min(36, actionRow.cellSize - 4,
                            (width - 25) / 3, height))
                    }

                    ToolButton {
                        id: errorHint
                        objectName: "powerError"
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: -10
                        anchors.topMargin: -12
                        width: 20
                        height: 20
                        visible: powerMenu.error !== ""
                        focusPolicy: Qt.NoFocus
                        Accessible.name: powerMenu.error
                        Accessible.role: Accessible.AlertMessage
                        ToolTip.visible: hovered
                        ToolTip.text: powerMenu.error
                        contentItem: Text {
                            text: "error"
                            color: ThemeApi.Theme.red
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 16
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Item {}
                    }
                }
            }
        }

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            width: menuTransition.snapshotWidth
            height: menuTransition.snapshotHeight
            source: menuTransition.snapshot ? menuTransition.snapshot.url : ""
            visible: !menuTransition.dropdown && menuTransition.snapshot !== null && (!powerMenu.closing || menuTransition.wideReturn)
            transform: NotchContentStretch { transition: menuTransition; canvasWidth: menuTransition.snapshotWidth; compact: true }
            fillMode: Image.Stretch
            onStatusChanged: {
                menuTransition.snapshotReady = status === Image.Ready || status === Image.Error;
                if (menuTransition.preparing && card.Window.window) card.Window.window.update();
            }
        }
        CompactNotch {
            anchors.horizontalCenter: parent.horizontalCenter
            clockValue: powerMenu.clockValue
            batteryLevel: powerMenu.batteryLevel
            batteryCharging: powerMenu.batteryCharging
            visible: !menuTransition.dropdown && ((powerMenu.closing && !menuTransition.wideReturn) || menuTransition.snapshot === null)
            transform: NotchContentStretch { transition: menuTransition; canvasWidth: 236; compact: true }
        }
    }
}
