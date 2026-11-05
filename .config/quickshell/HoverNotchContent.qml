import QtQuick
import QtQuick.Layouts
import "Theme" as ThemePalette

Item {
    id: root
    required property var panelWindow
    property real availableWidth: 760
    property string clockValue: "00:00"
    property string dateValue: ""
    property int batteryLevel: 0
    property bool batteryCharging: false
    property bool animated: true
    property int shelfCount: 0
    property int notificationCount: 0
    property bool notificationsPaused: false
    // Follow the actual outline, including its small rebound, rather than a fade timeline.
    readonly property real stretch: Math.max(0, Math.min(1.06, (height - 34) / 30))
    readonly property real reveal: Math.min(1, stretch)
    readonly property bool hasTray: tray.implicitWidth > 16
    readonly property real expandedWidth: Math.max(236, Math.min(availableWidth, Math.max(540, Math.min(760, targetLayout.implicitWidth + 48))))
    signal quickSettingsRequested()
    signal shelfRequested()
    signal notificationsRequested()

    function blend(compact, expanded) { return compact + (expanded - compact) * stretch; }
    function targetX(item) { return targetLayout.x + item.x; }

    // Geometry targets only: the visible clock/workspaces/status each exist just once.
    RowLayout {
        id: targetLayout
        width: root.expandedWidth - 48
        height: 64
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 14
        enabled: false
        Item { id: workspaceTarget; Layout.preferredWidth: 88; Layout.preferredHeight: 40 }
        Item { id: clockTarget; implicitWidth: 54 + 9 + dateText.implicitWidth; Layout.minimumWidth: 54; Layout.fillWidth: true; Layout.preferredHeight: 34 }
        Item { id: trayTarget; visible: root.hasTray; Layout.preferredWidth: tray.implicitWidth; Layout.preferredHeight: 33 }
        Item { id: notificationTarget; Layout.preferredWidth: 34; Layout.preferredHeight: 34 }
        Item { id: shelfTarget; Layout.preferredWidth: 34; Layout.preferredHeight: 34 }
        Item { id: settingsTarget; Layout.preferredWidth: 34; Layout.preferredHeight: 34 }
        Item { id: statusTarget; Layout.preferredWidth: 94; Layout.preferredHeight: 18 }
    }

    Item {
        id: workspaceGroup
        x: root.blend(root.width / 2 - 102, root.targetX(workspaceTarget))
        width: root.blend(50, 88)
        height: root.height
        Item {
            x: 0; y: 12
            width: 88 * root.reveal
            height: 15
            clip: true
            Text {
                text: "Desktop"
                color: ThemePalette.Theme.textBright
                font.family: "Inter"
                font.pixelSize: 11
                transform: Scale { xScale: root.reveal; yScale: 0.7 + 0.3 * root.reveal; origin.y: 15 }
            }
        }
        WorkspaceIndicators {
            x: 0
            y: root.blend((root.height - 16) / 2, 29)
            width: workspaceGroup.width
            height: root.blend(16, 22)
            maxIndicators: 5
            animated: root.animated
            transform: Scale {
                origin.x: workspaceGroup.width / 2
                origin.y: 11
                xScale: 1 + 0.10 * root.stretch
                yScale: 1 + 0.12 * root.stretch
            }
        }
    }

    Item {
        id: clockSlot
        readonly property real expandedCenter: root.targetX(clockTarget) + clockTarget.width / 2 - (54 + 9 + dateText.implicitWidth) / 2 + 27
        x: root.blend(root.width / 2, expandedCenter) - width / 2
        y: (root.height - height) / 2
        width: 54; height: 28
        FlipClock {
            anchors.centerIn: parent
            time: root.clockValue
            fontSize: 18
            animated: root.animated
            scale: root.blend(15 / 18, 1)
        }
    }

    Item {
        x: clockSlot.x + clockSlot.width + 9 * root.stretch
        y: (root.height - 20) / 2
        width: dateText.implicitWidth * root.reveal
        height: 20
        clip: true
        Text {
            id: dateText
            anchors.verticalCenter: parent.verticalCenter
            text: root.dateValue
            color: ThemePalette.Theme.muted
            font.family: "Inter"
            font.pixelSize: 10
            transform: Scale { xScale: root.reveal; yScale: 0.75 + 0.25 * root.reveal; origin.y: 6 }
        }
    }

    Item {
        x: root.blend(root.width / 2 + 20, root.targetX(trayTarget))
        y: (root.height - 33) / 2
        width: tray.implicitWidth * root.reveal
        height: 33
        clip: true
        enabled: root.reveal > 0.75
        TrayIcons {
            id: tray
            panelWindow: root.panelWindow
            anchorBottom: root.height
            transform: Scale { xScale: root.reveal; yScale: 0.7 + 0.3 * root.reveal; origin.y: 16.5 }
        }
    }

    Item {
        x: root.blend(root.width / 2 + 20, root.targetX(notificationTarget))
        y: (root.height - 34) / 2
        width: 34 * root.reveal
        height: 34
        clip: true
        enabled: root.reveal > 0.7
        Rectangle {
            width: 34; height: 34; radius: 11
            color: notificationMouse.containsMouse ? ThemePalette.Theme.surface : "transparent"
            transform: Scale { xScale: root.reveal; yScale: 0.7 + 0.3 * root.reveal; origin.y: 17 }
            Text {
                anchors.centerIn: parent
                text: root.notificationsPaused ? "notifications_paused" : "notifications"
                color: root.notificationCount > 0 || notificationMouse.containsMouse ? ThemePalette.Theme.accent : ThemePalette.Theme.muted
                font.family: "Material Symbols Rounded"
                font.pixelSize: 21
            }
            Rectangle {
                visible: root.notificationCount > 0
                x: 25; y: 5; width: 5; height: 5; radius: 3
                color: ThemePalette.Theme.accent
            }
            MouseArea {
                id: notificationMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.notificationsRequested()
            }
            Accessible.role: Accessible.Button
            Accessible.name: "Notifications · Super+T" + (root.notificationCount ? " · " + root.notificationCount + " unread" : "")
            Accessible.onPressAction: root.notificationsRequested()
        }
    }

    Item {
        x: root.blend(root.width / 2 + 26, root.targetX(shelfTarget))
        y: (root.height - 34) / 2
        width: 34 * root.reveal
        height: 34
        clip: true
        enabled: root.reveal > 0.7
        Rectangle {
            width: 34; height: 34; radius: 11
            color: shelfMouse.containsMouse ? ThemePalette.Theme.surface : "transparent"
            transform: Scale { xScale: root.reveal; yScale: 0.7 + 0.3 * root.reveal; origin.y: 17 }
            Text {
                anchors.centerIn: parent
                text: "inventory_2"
                color: root.shelfCount > 0 || shelfMouse.containsMouse ? ThemePalette.Theme.accent : ThemePalette.Theme.muted
                font.family: "Material Symbols Rounded"
                font.pixelSize: 21
            }
            Rectangle {
                visible: root.shelfCount > 0
                x: 25; y: 5
                width: 5; height: 5; radius: 3
                color: ThemePalette.Theme.accent
            }
            MouseArea {
                id: shelfMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.shelfRequested()
            }
            Accessible.role: Accessible.Button
            Accessible.name: "File shelf" + (root.shelfCount ? " · " + root.shelfCount + " items" : "")
            Accessible.onPressAction: root.shelfRequested()
        }
    }

    Item {
        x: root.blend(root.width / 2 + 40, root.targetX(settingsTarget))
        y: (root.height - 34) / 2
        width: 34 * root.reveal
        height: 34
        clip: true
        enabled: root.reveal > 0.7
        Rectangle {
            width: 34; height: 34; radius: 11
            color: settingsMouse.containsMouse ? ThemePalette.Theme.surface : "transparent"
            transform: Scale { xScale: root.reveal; yScale: 0.7 + 0.3 * root.reveal; origin.y: 17 }
            Text {
                anchors.centerIn: parent
                text: "tune"
                color: settingsMouse.containsMouse ? ThemePalette.Theme.accent : ThemePalette.Theme.muted
                font.family: "Material Symbols Rounded"
                font.pixelSize: 22
            }
            MouseArea {
                id: settingsMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.quickSettingsRequested()
            }
        }
    }

    Item {
        id: statusGroup
        x: root.blend(root.width / 2 + 52, root.targetX(statusTarget))
        y: (root.height - 18) / 2
        width: root.blend(50, 94)
        height: 18
        RowLayout {
            width: 50; height: 18
            spacing: 5
            WifiSignalIndicator { Layout.preferredWidth: 17; Layout.preferredHeight: 14 }
            BatteryIndicator { level: root.batteryLevel; charging: root.batteryCharging; Layout.preferredWidth: 28; Layout.preferredHeight: 18 }
        }
        Item {
            x: 57
            width: 37 * root.reveal
            height: 18
            clip: true
            Text {
                text: root.batteryLevel + "%"
                color: ThemePalette.Theme.textBright
                font.family: "Inter"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
                transform: Scale { xScale: root.reveal; yScale: 0.8 + 0.2 * root.reveal; origin.y: 9 }
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.quickSettingsRequested()
        }
    }
}
