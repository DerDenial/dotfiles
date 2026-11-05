import QtQuick
import QtQuick.Controls
import "../Theme" as ThemeApi
Slider {
    id: root
    from: 0
    to: 100
    stepSize: 1
    implicitWidth: 200
    implicitHeight: 32
    leftPadding: 9; rightPadding: 9
    opacity: enabled ? 1 : 0.4
    background: Rectangle {
        x: root.leftPadding; y: (root.height - height) / 2
        width: root.availableWidth; height: 6; radius: 3
        color: ThemeApi.Theme.surfaceRaised
        Rectangle { width: parent.width * root.visualPosition; height: parent.height; radius: 3; color: ThemeApi.Theme.accent }
    }
    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * root.availableWidth - width / 2
        y: (root.height - height) / 2
        width: root.pressed ? 22 : 18
        height: width
        radius: width / 2
        color: ThemeApi.Theme.accent
        border.width: 3
        border.color: ThemeApi.Theme.onAccent
        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 0.6 } }
    }
}
