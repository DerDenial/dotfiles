import QtQuick
import QtQuick.Controls
import "Theme" as ThemePalette

Rectangle {
    id: tile
    property string title: ""
    property string status: ""
    property string iconName: ""
    property bool active: false
    property bool available: true
    property bool showDetails: true
    property bool compact: false
    property bool filled: true
    property bool error: false
    readonly property color foreground: active && filled ? ThemePalette.Theme.onAccent : ThemePalette.Theme.textBright
    readonly property color secondary: active && filled ? Qt.rgba(foreground.r, foreground.g, foreground.b, 0.74) : error ? ThemePalette.Theme.red : ThemePalette.Theme.muted
    signal toggled()
    signal detailsRequested()
    implicitWidth: 214
    implicitHeight: compact ? 56 : 108
    activeFocusOnTab: available
    Accessible.role: Accessible.CheckBox
    Accessible.name: title + ": " + status
    Accessible.checkable: true
    Accessible.checked: active
    Keys.onSpacePressed: if (available) toggled()
    Keys.onReturnPressed: if (available) toggled()
    radius: compact ? 18 : 23
    color: active ? filled ? ThemePalette.Theme.accent : ThemePalette.Theme.accentSoft : ThemePalette.Theme.surface
    border.width: activeFocus ? 2 : 0
    border.color: ThemePalette.Theme.accent
    Behavior on color { ColorAnimation { duration: 180 } }

    MouseArea {
        id: toggleMouse
        anchors.fill: parent
        anchors.rightMargin: tile.showDetails ? 38 : 0
        enabled: tile.available
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.toggled()
    }
    Rectangle {
        anchors.fill: parent
        radius: tile.radius
        color: tile.foreground
        opacity: toggleMouse.pressed ? 0.09 : toggleMouse.containsMouse ? 0.035 : 0
        Behavior on opacity { NumberAnimation { duration: 100 } }
    }

    Text {
        x: tile.compact ? 15 : 16
        y: tile.compact ? (tile.height - height) / 2 : 14
        text: tile.iconName
        color: tile.active && tile.filled ? tile.foreground : tile.active ? ThemePalette.Theme.accent : ThemePalette.Theme.muted
        font.family: "Material Symbols Rounded"
        font.pixelSize: tile.compact ? 23 : 27
        opacity: tile.available ? 1 : 0.48
        scale: tile.active ? 1 : 0.94
        Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 0.55 } }
    }
    Column {
        x: tile.compact ? 48 : 16
        y: tile.compact ? (tile.height - height) / 2 : 60
        width: tile.width - x - (tile.showDetails ? 42 : tile.compact ? 48 : 14)
        spacing: tile.compact ? 3 : 4
        Text {
            width: parent.width
            text: tile.title
            color: tile.foreground
            font.family: "Inter"
            font.pixelSize: tile.compact ? 12 : 14
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: tile.status
            color: tile.secondary
            font.family: "Inter"
            font.pixelSize: 10
            elide: Text.ElideRight
        }
    }
    Rectangle {
        x: tile.width - (tile.showDetails ? 57 : 30)
        y: tile.compact ? (tile.height - height) / 2 : 22
        width: 7; height: 7; radius: 3.5
        color: tile.active ? tile.foreground : ThemePalette.Theme.mutedStrong
        opacity: tile.active ? 0.8 : 0.45
    }
    Rectangle {
        visible: tile.showDetails
        x: tile.width - 38
        y: 17
        width: 1
        height: tile.height - 34
        color: tile.foreground
        opacity: tile.active && tile.filled ? 0.15 : 0.08
    }
    ToolButton {
        visible: tile.showDetails
        anchors.right: parent.right
        width: 38; height: parent.height
        Accessible.name: "Open " + tile.title + " settings"
        contentItem: Text {
            text: "chevron_right"
            color: tile.foreground
            font.family: "Material Symbols Rounded"
            font.pixelSize: 21
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle { radius: tile.radius; color: tile.foreground; opacity: parent.pressed ? 0.12 : parent.hovered ? 0.06 : 0 }
        onClicked: tile.detailsRequested()
    }
    ToolTip.visible: toggleMouse.containsMouse
    ToolTip.delay: 700
    ToolTip.text: title + " · " + status
}
