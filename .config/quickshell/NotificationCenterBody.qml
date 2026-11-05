pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "Theme" as ThemePalette
import "Notifications" as Notifications

Item {
    id: body
    objectName: "notificationCenterBody"
    property var service: Notifications.Service
    readonly property real desiredHeight: header.height + 13 + dndRow.height + 13 + history.contentHeight
    readonly property real historyAvailableHeight: Math.max(0, height - history.y)
    signal closeRequested()
    function resetScroll() { history.contentY = 0; }

    Item {
        id: header
        width: parent.width; height: 38
        Text { text: "Notifications"; anchors.verticalCenter: parent.verticalCenter; font.family: "Inter"; font.pixelSize: 20; font.weight: Font.DemiBold; color: ThemePalette.Theme.textBright }
        Button {
            id: clearButton
            objectName: "clearAllNotifications"
            anchors.right: closeButton.left; anchors.rightMargin: 9; anchors.verticalCenter: parent.verticalCenter
            width: 58; height: 30
            enabled: body.service && body.service.count > 0
            Accessible.name: "Clear all notifications"
            contentItem: Text { text: "Clear"; color: clearButton.enabled ? ThemePalette.Theme.muted : ThemePalette.Theme.mutedStrong; font.family: "Inter"; font.pixelSize: 10; font.weight: Font.Medium; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { radius: 10; color: clearButton.hovered && clearButton.enabled ? ThemePalette.Theme.surfaceRaised : ThemePalette.Theme.surface }
            onClicked: body.service.clearAll()
        }
        ToolButton {
            id: closeButton
            objectName: "closeNotificationCenter"
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: 32; height: 32
            Accessible.name: "Close notification center"
            contentItem: Text { text: "close"; font.family: "Material Symbols Rounded"; font.pixelSize: 20; color: ThemePalette.Theme.muted; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { radius: 11; color: closeButton.hovered ? ThemePalette.Theme.surfaceRaised : "transparent" }
            onClicked: body.closeRequested()
            ToolTip.visible: hovered
            ToolTip.text: "Super + T · Esc to close"
        }
    }
    Rectangle {
        id: dndRow
        y: header.height + 13
        width: parent.width; height: 46; radius: 14
        color: ThemePalette.Theme.surface
        Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: body.service && body.service.dnd ? "do_not_disturb_on" : "notifications_active"; color: body.service && body.service.dnd ? ThemePalette.Theme.accent : ThemePalette.Theme.muted; font.family: "Material Symbols Rounded"; font.pixelSize: 20 }
        Text { x: 43; anchors.verticalCenter: parent.verticalCenter; text: "Do not disturb"; font.family: "Inter"; font.pixelSize: 11; font.weight: Font.Medium; color: ThemePalette.Theme.text }
        Switch {
            id: dndSwitch
            objectName: "notificationDndSwitch"
            anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
            width: 42; height: 28
            checked: !!body.service && body.service.dnd
            Accessible.name: "Do not disturb"
            indicator: Rectangle {
                x: 0; y: (parent.height - height) / 2
                width: 40; height: 23; radius: 12
                color: dndSwitch.checked ? ThemePalette.Theme.accent : ThemePalette.Theme.surfaceRaised
                Rectangle { x: dndSwitch.checked ? 20 : 3; y: 3; width: 17; height: 17; radius: 9; color: dndSwitch.checked ? ThemePalette.Theme.onAccent : ThemePalette.Theme.muted; Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } } }
            }
            onToggled: {
                const requested = checked;
                checked = Qt.binding(function() { return !!body.service && body.service.dnd; });
                if (body.service) body.service.setDnd(requested);
            }
        }
    }
    Flickable {
        id: history
        objectName: "notificationHistory"
        y: dndRow.y + dndRow.height + 13
        width: parent.width; height: body.historyAvailableHeight
        contentWidth: width
        contentHeight: stack.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height + 0.5
        flickableDirection: Flickable.VerticalFlick
        clip: true
        onContentHeightChanged: contentY = Math.max(0, Math.min(contentY, Math.max(0, contentHeight - height)))
        onHeightChanged: contentY = Math.max(0, Math.min(contentY, Math.max(0, contentHeight - height)))
        ScrollBar.vertical: ScrollBar { width: 3; policy: history.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
        Column {
            id: stack
            width: history.width; spacing: 9
            Item {
                objectName: "emptyNotifications"
                width: parent.width; height: 64
                visible: !body.service || body.service.count === 0
                Text { anchors.horizontalCenter: parent.horizontalCenter; y: 3; text: "notifications_none"; color: ThemePalette.Theme.mutedStrong; font.family: "Material Symbols Rounded"; font.pixelSize: 23 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; y: 37; text: "No new notifications"; color: ThemePalette.Theme.muted; font.family: "Inter"; font.pixelSize: 11 }
            }
            Repeater {
                model: body.service ? body.service.entries : []
                delegate: NotificationCard {
                    required property var modelData
                    width: stack.width
                    notification: modelData
                    service: body.service
                }
            }
        }
    }
}
