import QtQuick
import QtQuick.Controls
import "../Theme" as ThemeApi
Switch {
    id: root
    implicitWidth: 48
    implicitHeight: 30
    padding: 0
    hoverEnabled: true
    opacity: enabled ? 1 : 0.4
    indicator: Rectangle {
        width: 48
        height: 28
        y: 1
        radius: 14
        color: root.checked ? ThemeApi.Theme.accent : ThemeApi.Theme.surfaceRaised
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? ThemeApi.Theme.accent : root.checked ? "transparent" : ThemeApi.Theme.border
        Rectangle {
            width: 20
            height: 20
            radius: 10
            y: 4
            x: root.checked ? 24 : 4
            color: root.checked ? ThemeApi.Theme.onAccent : ThemeApi.Theme.muted
            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 0.55 } }
        }
        Behavior on color { ColorAnimation { duration: 150 } }
    }
    contentItem: Item {}
}
