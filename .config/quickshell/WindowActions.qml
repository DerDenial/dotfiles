pragma ComponentBehavior: Bound

import QtQuick
import "Theme" as ThemeApi

Item {
    id: menu
    required property var entry
    required property var workspaces
    property real maximumHeight: 420
    property bool workspacePage: false
    property int currentIndex: 0
    property real reveal: 0
    property string errorText: ""
    readonly property var mainActions: [
        {id: "float", icon: entry && entry.floating ? "grid_view" : "picture_in_picture_alt",
         label: entry && entry.pinned ? "Unpin to tile window"
             : entry && entry.floatingKnown ? entry.floating ? "Tile window" : "Float window" : "Toggle floating",
         enabled: !!entry && entry.manageable && !entry.pinned && !entry.pinBusy},
        {id: "pin", icon: "push_pin",
         label: entry && entry.pinBusy ? "Updating…" : entry && entry.pinned ? "Unpin window" : "Pin on all workspaces",
         enabled: !!entry && entry.manageable && entry.pinSupported && entry.pinnedKnown && !entry.pinBusy},
        {id: "move", icon: "drive_file_move", label: entry && entry.pinned ? "Unpin to move window" : "Move to workspace",
         enabled: !!entry && entry.manageable && !entry.pinned && !entry.pinBusy},
        {id: "close", icon: "close", label: "Close window", enabled: !!entry}
    ]

    signal dismissed()
    signal invoked(string action, string target)

    width: 272
    implicitHeight: content.implicitHeight + 20
    height: Math.max(0, Math.min(maximumHeight, implicitHeight))
    opacity: reveal
    scale: 0.97 + reveal * 0.03
    transformOrigin: Item.Bottom

    function openWorkspaces() {
        workspacePage = true;
        currentIndex = Math.max(0, workspaces.findIndex(choice => entry && choice.target === entry.workspaceTarget));
        scroll.contentY = 0;
        Qt.callLater(ensureCurrentVisible);
    }

    function goBack() {
        workspacePage = false;
        currentIndex = Math.max(0, mainActions.findIndex(action => action.id === "move"));
        scroll.contentY = 0;
    }

    function choose() {
        errorText = "";
        if (workspacePage) {
            const target = workspaces[currentIndex];
            if (target && entry && target.target !== entry.workspaceTarget)
                invoked("move", target.target);
        } else {
            const action = mainActions[currentIndex];
            if (!action || !action.enabled) return;
            if (action.id === "move") openWorkspaces();
            else invoked(action.id, "");
        }
    }

    function handleKey(event) {
        const key = event.key;
        if (key === Qt.Key_Escape || key === Qt.Key_Backspace) {
            if (workspacePage) goBack();
            else dismissed();
        } else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) choose();
        else if (key === Qt.Key_Home) currentIndex = 0;
        else if (key === Qt.Key_End) currentIndex = (workspacePage ? workspaces.length : mainActions.length) - 1;
        else if (key === Qt.Key_Tab || key === Qt.Key_Backtab || key === Qt.Key_Up || key === Qt.Key_Down
            || key === Qt.Key_Left || key === Qt.Key_Right) {
            if (!workspacePage && key === Qt.Key_Right) {
                if (mainActions[currentIndex].id === "move" && mainActions[currentIndex].enabled) openWorkspaces();
            } else if (!workspacePage && key === Qt.Key_Left) dismissed();
            else {
                let step = key === Qt.Key_Up || key === Qt.Key_Left || key === Qt.Key_Backtab
                    || (key === Qt.Key_Tab && event.modifiers & Qt.ShiftModifier) ? -1 : 1;
                if (workspacePage && currentIndex < 10 && (key === Qt.Key_Up || key === Qt.Key_Down)) step *= 5;
                const count = workspacePage ? workspaces.length : mainActions.length;
                currentIndex = count ? (currentIndex + step + count) % count : 0;
            }
        }
        // The bar keeps its existing keyboard grab; menu keys never switch windows.
        event.accepted = true;
        Qt.callLater(ensureCurrentVisible);
    }

    function ensureCurrentVisible() {
        let target = null;
        if (!workspacePage) target = actionRows.itemAt(currentIndex);
        else if (currentIndex < 10) target = workspaceTiles.itemAt(currentIndex);
        else target = extraRows.itemAt(currentIndex - 10);
        if (!target) return;
        const point = target.mapToItem(content, 0, 0);
        if (point.y < scroll.contentY) scroll.contentY = point.y;
        else if (point.y + target.height > scroll.contentY + scroll.height)
            scroll.contentY = Math.max(0, point.y + target.height - scroll.height);
    }

    Component.onCompleted: entrance.start()
    onWorkspacesChanged: if (workspacePage) {
        currentIndex = Math.max(0, Math.min(currentIndex, workspaces.length - 1));
        Qt.callLater(ensureCurrentVisible);
    }
    NumberAnimation {
        id: entrance
        target: menu
        property: "reveal"
        to: 1
        duration: 150
        easing.type: Easing.OutCubic
    }

    Rectangle {
        x: -3; y: 5
        width: parent.width + 6; height: parent.height + 4
        radius: 20
        color: Qt.alpha(ThemeApi.Theme.bg0, 0.25)
    }
    Rectangle {
        anchors.fill: parent
        radius: 18
        color: ThemeApi.Theme.notchBg
        border.width: 1
        border.color: Qt.alpha(ThemeApi.Theme.border, 0.8)
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => { mouse.accepted = true; }
    }
    Flickable {
        id: scroll
        anchors.fill: parent
        anchors.margins: 10
        contentWidth: width
        contentHeight: content.implicitHeight
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: content
            width: scroll.width
            spacing: 4

            Item {
                width: parent.width
                height: 46
                Text {
                    id: backIcon
                    visible: menu.workspacePage
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28
                    text: "chevron_left"
                    color: ThemeApi.Theme.accent
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 20
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: menu.goBack() }
                }
                Column {
                    anchors.left: menu.workspacePage ? backIcon.right : parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Text {
                        width: parent.width
                        text: menu.workspacePage ? "Move to workspace" : menu.entry ? menu.entry.appName : "Window actions"
                        textFormat: Text.PlainText
                        color: ThemeApi.Theme.textBright
                        font.family: "Inter"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: menu.entry ? menu.entry.title : ""
                        textFormat: Text.PlainText
                        color: ThemeApi.Theme.muted
                        font.family: "Inter"
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }
            }

            Repeater {
                id: actionRows
                model: menu.workspacePage ? [] : menu.mainActions
                delegate: Rectangle {
                    id: actionRow
                    required property int index
                    required property var modelData
                    width: content.width
                    height: 38
                    radius: 10
                    color: menu.currentIndex === index && modelData.enabled ? ThemeApi.Theme.surfaceRaised : "transparent"
                    opacity: modelData.enabled ? 1 : 0.4
                    Text {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: actionRow.modelData.icon
                        color: actionRow.modelData.id === "close" ? ThemeApi.Theme.red : ThemeApi.Theme.accent
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 18
                    }
                    Text {
                        x: 39
                        anchors.verticalCenter: parent.verticalCenter
                        text: actionRow.modelData.label
                        color: actionRow.modelData.id === "close" ? ThemeApi.Theme.red : ThemeApi.Theme.text
                        font.family: "Inter"
                        font.pixelSize: 12
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 9
                        anchors.verticalCenter: parent.verticalCenter
                        visible: actionRow.modelData.id === "move"
                        text: "chevron_right"
                        color: ThemeApi.Theme.muted
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 18
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: actionRow.modelData.enabled
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: menu.currentIndex = actionRow.index
                        onClicked: { menu.currentIndex = actionRow.index; menu.choose(); }
                    }
                }
            }

            Grid {
                visible: menu.workspacePage
                width: content.width
                columns: 5
                spacing: 5
                Repeater {
                    id: workspaceTiles
                    model: menu.workspacePage ? menu.workspaces.slice(0, 10) : []
                    delegate: Rectangle {
                        id: workspaceTile
                        required property int index
                        required property var modelData
                        readonly property bool current: !!menu.entry && modelData.target === menu.entry.workspaceTarget
                        width: (content.width - 20) / 5
                        height: 39
                        radius: 10
                        color: menu.currentIndex === index ? ThemeApi.Theme.surfaceRaised : ThemeApi.Theme.surface
                        border.width: current ? 1 : 0
                        border.color: ThemeApi.Theme.accent
                        Text {
                            anchors.centerIn: parent
                            text: workspaceTile.modelData.label
                            color: workspaceTile.current ? ThemeApi.Theme.accent : ThemeApi.Theme.text
                            font.family: "Inter"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: workspaceTile.current ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onEntered: menu.currentIndex = workspaceTile.index
                            onClicked: { menu.currentIndex = workspaceTile.index; menu.choose(); }
                        }
                    }
                }
            }

            Repeater {
                id: extraRows
                model: menu.workspacePage ? menu.workspaces.slice(10) : []
                delegate: Rectangle {
                    id: extraRow
                    required property int index
                    required property var modelData
                    readonly property bool current: !!menu.entry && modelData.target === menu.entry.workspaceTarget
                    width: content.width
                    height: 36
                    radius: 10
                    color: menu.currentIndex === index + 10 ? ThemeApi.Theme.surfaceRaised : ThemeApi.Theme.surface
                    Text {
                        anchors.fill: parent
                        anchors.margins: 10
                        verticalAlignment: Text.AlignVCenter
                        text: extraRow.modelData.label + (extraRow.current ? "  ✓" : "")
                        textFormat: Text.PlainText
                        color: extraRow.current ? ThemeApi.Theme.accent : ThemeApi.Theme.text
                        font.family: "Inter"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: extraRow.current ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onEntered: menu.currentIndex = extraRow.index + 10
                        onClicked: { menu.currentIndex = extraRow.index + 10; menu.choose(); }
                    }
                }
            }

            Text {
                visible: menu.errorText !== ""
                width: parent.width
                text: menu.errorText
                color: ThemeApi.Theme.red
                font.family: "Inter"
                font.pixelSize: 10
                wrapMode: Text.WordWrap
                padding: 6
            }
        }
    }
}
