import QtQuick
import QtQuick.Layouts
import "Theme" as ThemePalette

RowLayout {
    id: header

    property string title: ""
    property string subtitle: ""
    property string iconName: "settings"
    property color accentColor: ThemePalette.Theme.accent
    default property alias actions: actionSlot.data

    Layout.fillWidth: true
    spacing: 14

    Rectangle {
        Layout.preferredWidth: 48
        Layout.preferredHeight: 48
        radius: 17
        color: ThemePalette.Theme.surfaceRaised

        Text {
            anchors.centerIn: parent
            text: header.iconName
            color: header.accentColor
            font.family: "Material Symbols Rounded"
            font.pixelSize: 24
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Text {
            Layout.fillWidth: true
            text: header.title
            color: ThemePalette.Theme.textBright
            font.family: "Inter"
            font.pixelSize: 22
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Text {
            Layout.fillWidth: true
            text: header.subtitle
            color: ThemePalette.Theme.muted
            font.family: "Inter"
            font.pixelSize: 11
            elide: Text.ElideRight
        }
    }

    RowLayout {
        id: actionSlot
        spacing: 8
    }
}
