import QtQuick
import QtQuick.Layouts
import "Theme" as ThemePalette

RowLayout {
    id: root

    property int level: 0
    property bool showPercentage: false
    property bool charging: false
    readonly property color accent: level <= 15 ? ThemePalette.Theme.red : level <= 30 ? ThemePalette.Theme.yellow : ThemePalette.Theme.accent

    spacing: showPercentage ? 7 : 0
    implicitWidth: showPercentage ? 72 : 28
    implicitHeight: 18

    Item {
        Layout.preferredWidth: 25
        Layout.preferredHeight: 15

        Rectangle {
            x: 0
            y: 2
            width: 22
            height: 11
            radius: 3
            color: "transparent"
            border.width: 1.4
            border.color: ThemePalette.Theme.muted

            Rectangle {
                x: 2
                y: 2
                width: Math.max(0, (parent.width - 4) * root.level / 100)
                height: parent.height - 4
                radius: 1.5
                color: root.accent
            }

            Text {
                anchors.centerIn: parent
                visible: root.charging
                text: "bolt"
                color: ThemePalette.Theme.textBright
                font.family: "Material Symbols Rounded"
                font.pixelSize: 10
            }
        }

        Rectangle {
            x: 22.5
            y: 5
            width: 2.5
            height: 5
            radius: 1
            color: ThemePalette.Theme.muted
        }

    }

    Text {
        visible: root.showPercentage
        text: root.level + "%"
        color: ThemePalette.Theme.textBright
        font.family: "Inter"
        font.pixelSize: 13
        font.weight: Font.DemiBold
    }

}
