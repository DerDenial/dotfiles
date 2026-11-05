import QtQuick
import QtQuick.Layouts
import "../Theme" as ThemeApi
Rectangle {
    id: root
    property string text: ""
    property bool warning: false
    property string iconName: warning ? "error_outline" : "info"
    Layout.fillWidth: true
    implicitHeight: noticeLabel.implicitHeight + 28
    visible: text.length > 0
    radius: 14
    color: warning ? ThemeApi.Theme.redDark : ThemeApi.Theme.accentSoft
    Text {
        id: icon
        x: 14; y: 14
        text: root.iconName
        font.family: "Material Symbols Rounded"
        font.pixelSize: 18
        color: root.warning ? ThemeApi.Theme.red : ThemeApi.Theme.accent
    }
    SLabel {
        id: noticeLabel
        x: 42; y: 14
        width: Math.max(0, root.width - 58)
        text: root.text
        font.pixelSize: 12
        wrapMode: Text.WordWrap
        color: root.warning ? ThemeApi.Theme.onErrorContainer : ThemeApi.Theme.onAccentContainer
    }
}
