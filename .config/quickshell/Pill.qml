import QtQuick
import "Theme" as ThemePalette
import QtQuick.Layouts

Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property color iconColor: ThemePalette.Theme.accent
    property int maxLabelWidth: 400

    implicitWidth: row.implicitWidth + 22
    implicitHeight: 33
    radius: height / 2
    color: ThemePalette.Theme.bgDim

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 7

        Text {
            text: root.icon
            color: root.iconColor
            font.family: "Material Symbols Rounded"
            font.pixelSize: 16
        }

        Text {
            text: root.label
            color: ThemePalette.Theme.textWarm
            font.family: "Inter"
            font.pixelSize: 16
            elide: Text.ElideRight
            Layout.maximumWidth: root.maxLabelWidth
            visible: root.label !== ""
        }
    }
}
