import QtQuick
import QtQuick.Layouts
import "../Theme" as ThemeApi
Item {
    id: root
    property string title: ""
    property string subtitle: ""
    property string iconName: ""
    property string value: ""
    property bool interactive: false
    property bool destructive: false
    default property alias actions: trailing.data
    signal clicked()
    Layout.fillWidth: true
    implicitHeight: Math.max(64, labels.implicitHeight + 20, trailing.implicitHeight + 14)
    opacity: enabled ? 1 : 0.4
    activeFocusOnTab: interactive
    Accessible.role: interactive ? Accessible.Button : Accessible.StaticText
    Accessible.name: title
    Keys.onReturnPressed: if (interactive) clicked()
    property Rectangle hoverBackground: Rectangle {
        parent: root
        anchors.fill: parent
        radius: 13
        color: ThemeApi.Theme.surfaceRaised
        opacity: rowMouse.containsMouse && root.interactive ? 0.6 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }
    property MouseArea clickArea: MouseArea {
        id: rowMouse
        parent: root
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
    property RowLayout rowLayout: RowLayout {
        parent: root
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        spacing: 14
        Rectangle {
            visible: root.iconName.length > 0
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            radius: 12
            color: root.destructive ? ThemeApi.Theme.redDark : ThemeApi.Theme.accentSoft
            Text {
                anchors.centerIn: parent
                text: root.iconName
                color: root.destructive ? ThemeApi.Theme.red : ThemeApi.Theme.accent
                font.family: "Material Symbols Rounded"
                font.pixelSize: 20
            }
        }
        ColumnLayout {
            id: labels
            Layout.fillWidth: true
            spacing: 4
            SLabel { text: root.title; Layout.fillWidth: true; color: root.destructive ? ThemeApi.Theme.red : ThemeApi.Theme.textBright; font.weight: Font.Medium; elide: Text.ElideRight }
            SLabel { text: root.subtitle; visible: text.length > 0; Layout.fillWidth: true; font.pixelSize: 11; color: ThemeApi.Theme.muted; wrapMode: Text.WordWrap }
        }
        SLabel { text: root.value; visible: text.length > 0; Layout.maximumWidth: 220; elide: Text.ElideRight; color: ThemeApi.Theme.muted; font.pixelSize: 12 }
        RowLayout { id: trailing; spacing: 8 }
        Text {
            visible: root.interactive
            text: "chevron_right"
            color: ThemeApi.Theme.muted
            font.family: "Material Symbols Rounded"
            font.pixelSize: 20
        }
    }
}
