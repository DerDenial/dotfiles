import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../Theme" as ThemeApi
Button {
    id: root
    property string iconName: ""
    property bool accent: false
    property bool destructive: false
    implicitHeight: 36
    implicitWidth: Math.max(36, label.implicitWidth + 24)
    padding: 12
    topPadding: 6
    bottomPadding: 6
    hoverEnabled: true
    opacity: enabled ? 1 : 0.4
    font.family: "Inter"
    font.pixelSize: 12
    Accessible.name: text
    contentItem: Row {
        id: label
        spacing: root.text && root.iconName ? 7 : 0
        Text {
            visible: root.iconName.length > 0
            text: root.iconName
            color: root.accent ? ThemeApi.Theme.onAccent : root.destructive ? ThemeApi.Theme.red : ThemeApi.Theme.text
            font.family: "Material Symbols Rounded"
            font.pixelSize: 18
            anchors.verticalCenter: parent.verticalCenter
        }
        SLabel {
            text: root.text
            color: root.accent ? ThemeApi.Theme.onAccent : root.destructive ? ThemeApi.Theme.red : ThemeApi.Theme.text
            font.pixelSize: 12
            font.weight: Font.Medium
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    background: Rectangle {
        radius: 11
        color: root.accent ? ThemeApi.Theme.accent : root.destructive ? ThemeApi.Theme.redDark : root.hovered ? ThemeApi.Theme.surfaceRaised : ThemeApi.Theme.surfaceAlt
        border.width: root.activeFocus ? 2 : 0
        border.color: ThemeApi.Theme.accent
        scale: root.down ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }
        Behavior on color { ColorAnimation { duration: 140 } }
    }
}
