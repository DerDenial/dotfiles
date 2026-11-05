import QtQuick
import QtQuick.Layouts
import "../Theme" as ThemeApi
Rectangle {
    id: root
    property string title: ""
    property string subtitle: ""
    property string iconName: ""
    property real padding: 20
    default property alias content: body.data
    Layout.fillWidth: true
    implicitHeight: outer.implicitHeight + padding * 2
    radius: 20
    color: ThemeApi.Theme.surface
    border.width: 1
    border.color: Qt.rgba(ThemeApi.Theme.border.r, ThemeApi.Theme.border.g, ThemeApi.Theme.border.b, 0.55)
    property ColumnLayout layoutRoot: ColumnLayout {
        id: outer
        parent: root
        x: root.padding
        y: root.padding
        width: Math.max(0, root.width - root.padding * 2)
        spacing: root.title ? 14 : 0
        RowLayout {
            visible: root.title.length > 0
            Layout.fillWidth: true
            spacing: 10
            Text {
                visible: root.iconName.length > 0
                text: root.iconName
                font.family: "Material Symbols Rounded"
                font.pixelSize: 20
                color: ThemeApi.Theme.accent
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                SLabel { text: root.title; font.pixelSize: 14; font.weight: Font.DemiBold; color: ThemeApi.Theme.textBright; Layout.fillWidth: true }
                SLabel { visible: root.subtitle.length > 0; text: root.subtitle; font.pixelSize: 11; color: ThemeApi.Theme.muted; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            }
        }
        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: 10
        }
    }
}
