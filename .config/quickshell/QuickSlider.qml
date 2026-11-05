import QtQuick
import QtQuick.Controls
import "Theme" as ThemePalette

Item {
    id: control
    property string title: ""
    property string subtitle: ""
    property string iconName: ""
    property real percent: 0
    property real minimum: 0
    property bool available: true
    property bool muted: false
    property bool iconClickable: false
    readonly property bool dragging: slider.pressed
    signal valueRequested(real percentage)
    signal interactionFinished()
    signal iconClicked()
    implicitWidth: 440
    implicitHeight: 78

    Text {
        id: titleText
        x: 4; y: 1
        text: control.title
        color: ThemePalette.Theme.text
        font.family: "Inter"
        font.pixelSize: 11
        font.weight: Font.DemiBold
    }
    Text {
        x: titleText.width + 14
        y: 2
        width: Math.max(0, parent.width - x - 4)
        text: control.subtitle
        color: ThemePalette.Theme.mutedStrong
        font.family: "Inter"
        font.pixelSize: 10
        elide: Text.ElideRight
    }
    Slider {
        id: slider
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: 50
        padding: 0
        from: control.minimum; to: 100; stepSize: 1
        enabled: control.available
        opacity: control.available ? 1 : 0.48
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus
        Accessible.name: control.title
        Binding { target: slider; property: "value"; value: Math.min(100, Math.max(control.minimum, control.percent)); when: !slider.pressed }
        onMoved: control.valueRequested(value)
        onPressedChanged: if (!pressed) control.interactionFinished()
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        background: Rectangle {
            width: slider.availableWidth
            height: slider.availableHeight
            radius: 18
            color: ThemePalette.Theme.surface
            border.width: slider.activeFocus ? 2 : 0
            border.color: ThemePalette.Theme.accent
            Rectangle {
                width: slider.visualPosition * parent.width
                height: parent.height
                radius: 18
                color: control.muted ? ThemePalette.Theme.mutedStrong : ThemePalette.Theme.accent
            }
        }
        handle: Rectangle {
            x: Math.max(6, Math.min(slider.width - width - 6, slider.visualPosition * slider.width - width / 2))
            y: (slider.height - height) / 2
            width: 4; height: slider.pressed ? 26 : 20; radius: 2
            color: control.muted ? ThemePalette.Theme.textBright : ThemePalette.Theme.onAccent
            opacity: slider.pressed || slider.hovered || slider.activeFocus ? 0.8 : 0
            Behavior on height { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }
            Behavior on opacity { NumberAnimation { duration: 100 } }
        }
        ToolButton {
            x: 7
            anchors.verticalCenter: parent.verticalCenter
            width: 38; height: 38
            enabled: control.available && control.iconClickable
            Accessible.name: control.muted ? "Unmute sound" : "Mute sound"
            contentItem: Text {
                text: control.iconName
                color: slider.visualPosition * slider.width > 46 ? control.muted ? ThemePalette.Theme.textBright : ThemePalette.Theme.onAccent : ThemePalette.Theme.muted
                font.family: "Material Symbols Rounded"
                font.pixelSize: 23
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle { radius: 12; color: ThemePalette.Theme.textBright; opacity: parent.hovered ? 0.09 : 0 }
            onClicked: control.iconClicked()
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: control.available ? Math.round(slider.value) + "%" : "—"
            color: slider.visualPosition > 0.92 ? control.muted ? ThemePalette.Theme.textBright : ThemePalette.Theme.onAccent : ThemePalette.Theme.textBright
            font.family: "Inter"
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }
    }
}
