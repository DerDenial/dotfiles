pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "Theme" as ThemeApi

// Content only: the shell owns the width/radius morph and reserved work area.
Item {
    id: bar

    required property var panelWindow
    property string clockValue: "00:00"
    property int batteryLevel: 0
    property bool batteryCharging: false
    property bool statusActive: false
    property bool active: false
    property int shelfCount: 0
    property int notificationCount: 0
    property bool notificationsPaused: false
    property real amount: active ? 1 : 0
    readonly property bool shown: active || amount > 0.001

    signal quickSettingsRequested()
    signal powerRequested()
    signal windowBarRequested()
    signal shelfRequested()
    signal notificationsRequested()

    implicitHeight: 34
    visible: shown
    opacity: Math.max(0, Math.min(1, amount))
    enabled: active

    WindowBarState {
        id: windows
        engaged: bar.shown
    }
    onActiveChanged: if (active) windows.prepare()
    Component.onCompleted: if (active) windows.prepare()

    component IconAction: ToolButton {
        id: button
        required property string symbol
        required property string label
        implicitWidth: 28
        implicitHeight: 28
        focusPolicy: Qt.NoFocus
        Accessible.name: label
        ToolTip.visible: hovered
        ToolTip.delay: 450
        ToolTip.text: label
        contentItem: Text {
            text: button.symbol
            color: button.hovered ? ThemeApi.Theme.accent : ThemeApi.Theme.muted
            font.family: "Material Symbols Rounded"
            font.pixelSize: 18
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 8
            color: button.down ? ThemeApi.Theme.surfaceRaised : button.hovered ? ThemeApi.Theme.surface : "transparent"
        }
    }

    Item {
        id: leftRegion
        x: 14
        width: Math.max(0, bar.width / 2 - (bar.statusActive ? 230 : 100))
        height: bar.height
        clip: true

        WorkspaceIndicators {
            id: workspaces
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 50
            height: 24
            maxIndicators: 5
            animated: bar.active
        }
        Rectangle {
            x: workspaces.width + 12
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 14
            color: Qt.alpha(ThemeApi.Theme.border, 0.65)
        }
        IconAction {
            id: windowButton
            x: workspaces.width + 21
            anchors.verticalCenter: parent.verticalCenter
            symbol: "view_carousel"
            label: "Open windows · Super+Tab"
            onClicked: bar.windowBarRequested()
        }

        ListView {
            id: apps
            anchors.left: windowButton.right
            anchors.leftMargin: 7
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 30
            orientation: ListView.Horizontal
            spacing: 4
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick
            model: windows.entries
            highlight: null

            delegate: Item {
                id: windowTile
                required property var modelData
                readonly property bool selected: !!modelData.ref && modelData.ref.activated
                width: 29
                height: 30
                Accessible.role: Accessible.Button
                Accessible.name: modelData.appName + ": " + modelData.title
                Accessible.onPressAction: windows.activate(modelData.key)

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: 8
                    color: windowTile.selected ? ThemeApi.Theme.accentSoft
                        : appMouse.containsMouse ? ThemeApi.Theme.surface : "transparent"
                }
                Image {
                    id: appIcon
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 4
                    width: 20
                    height: 20
                    source: windowTile.modelData.icon
                    sourceSize.width: 40
                    sourceSize.height: 40
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: appIcon
                    visible: appIcon.status !== Image.Ready
                    text: "web_asset"
                    color: ThemeApi.Theme.accent
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 19
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 26
                    width: windowTile.selected ? 12 : 3
                    height: 2
                    radius: 1
                    color: windowTile.selected ? ThemeApi.Theme.accent : ThemeApi.Theme.muted
                    opacity: windowTile.selected ? 1 : 0.45
                }
                MouseArea {
                    id: appMouse
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) bar.windowBarRequested();
                        else windows.activate(windowTile.modelData.key);
                    }
                }
                ToolTip {
                    visible: appMouse.containsMouse
                    delay: 500
                    width: Math.min(440, Math.max(120, bar.width - 32))
                    contentItem: Text {
                        text: windowTile.modelData.appName + " · " + windowTile.modelData.title
                            + (windowTile.modelData.workspace ? "\nWorkspace " + windowTile.modelData.workspace : "")
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        color: ThemeApi.Theme.text
                        font.family: "Inter"
                        font.pixelSize: 11
                    }
                    background: Rectangle {
                        radius: 10
                        color: ThemeApi.Theme.surface
                        border.width: 1
                        border.color: ThemeApi.Theme.border
                    }
                }
            }
            ScrollBar.horizontal: ScrollBar {
                height: 2
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle { radius: 1; color: Qt.alpha(ThemeApi.Theme.accent, 0.5) }
                background: Rectangle { color: "transparent" }
            }
        }
    }

    Item {
        anchors.centerIn: parent
        visible: !bar.statusActive
        width: 54
        height: 26
        FlipClock {
            anchors.centerIn: parent
            time: bar.clockValue
            fontSize: 18
            scale: 15 / 18
            animated: bar.active
        }
    }

    Item {
        id: rightRegion
        x: bar.width / 2 + (bar.statusActive ? 230 : 82)
        width: Math.max(0, bar.width / 2 - (bar.statusActive ? 244 : 96))
        height: bar.height
        clip: true

        Row {
            id: statusRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 30
            spacing: 11

            Item {
                id: traySlot
                readonly property Item trayItem: trayLoader.item as Item
                width: Math.max(0, Math.min(trayItem ? trayItem.implicitWidth : 0,
                    rightRegion.width - 279))
                height: 30
                visible: width > 16
                clip: true
                Loader {
                    id: trayLoader
                    active: bar.shown
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: TrayIcons {
                        panelWindow: bar.panelWindow
                        anchorBottom: bar.height
                    }
                }
            }
            Rectangle {
                visible: traySlot.visible
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 14
                color: Qt.alpha(ThemeApi.Theme.border, 0.65)
            }
            WifiSignalIndicator {
                anchors.verticalCenter: parent.verticalCenter
                width: 17
                height: 14
            }
            BatteryIndicator {
                anchors.verticalCenter: parent.verticalCenter
                level: bar.batteryLevel
                charging: bar.batteryCharging
                showPercentage: true
                width: 72
                height: 18
            }
            IconAction {
                anchors.verticalCenter: parent.verticalCenter
                symbol: bar.notificationsPaused ? "notifications_paused" : "notifications"
                label: "Notifications · Super+T" + (bar.notificationCount ? " · " + bar.notificationCount + " unread" : "")
                onClicked: bar.notificationsRequested()
                Rectangle {
                    visible: bar.notificationCount > 0
                    x: parent.width - 5; y: 2
                    width: 4; height: 4; radius: 2
                    color: ThemeApi.Theme.accent
                }
            }
            IconAction {
                anchors.verticalCenter: parent.verticalCenter
                symbol: "inventory_2"
                label: "File shelf" + (bar.shelfCount ? " · " + bar.shelfCount + " items" : "")
                onClicked: bar.shelfRequested()
                Rectangle {
                    visible: bar.shelfCount > 0
                    x: parent.width - 5; y: 2
                    width: 4; height: 4; radius: 2
                    color: ThemeApi.Theme.accent
                }
            }
            IconAction {
                anchors.verticalCenter: parent.verticalCenter
                symbol: "tune"
                label: "Quick settings"
                onClicked: bar.quickSettingsRequested()
            }
            IconAction {
                anchors.verticalCenter: parent.verticalCenter
                symbol: "power_settings_new"
                label: "Power · Super+Esc"
                onClicked: bar.powerRequested()
            }
        }
    }
}
