import QtQuick
import QtQuick.Controls
import "Theme" as ThemeApi

Button {
    id: actionButton
    property string symbol: ""
    property bool emphasized: false
    property color tint: ThemeApi.Theme.accent
    property color onTint: ThemeApi.Theme.onAccent
    implicitHeight: 34
    implicitWidth: contentItem.implicitWidth + 24
    leftPadding: 12
    rightPadding: 12
    topPadding: 0
    bottomPadding: 0
    focusPolicy: Qt.NoFocus
    Accessible.name: text || ToolTip.text
    ToolTip.visible: hovered
    ToolTip.delay: 450
    opacity: enabled ? 1 : 0.45
    contentItem: Item {
        implicitWidth: buttonContent.implicitWidth
        implicitHeight: buttonContent.implicitHeight
        Row {
            id: buttonContent
            anchors.centerIn: parent
            spacing: 6
            Text {
                visible: actionButton.symbol !== ""
                text: actionButton.symbol
                color: actionButton.emphasized ? actionButton.onTint : ThemeApi.Theme.muted
                font.family: "Material Symbols Rounded"
                font.pixelSize: 18
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: actionButton.text !== ""
                text: actionButton.text
                color: actionButton.emphasized ? actionButton.onTint : ThemeApi.Theme.textBright
                font.family: "Inter"
                font.pixelSize: 11
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
    background: Rectangle {
        radius: 11
        color: actionButton.emphasized
            ? (actionButton.down ? Qt.darker(actionButton.tint, 1.12) : actionButton.hovered ? Qt.lighter(actionButton.tint, 1.06) : actionButton.tint)
            : (actionButton.down ? ThemeApi.Theme.surfaceRaised : actionButton.hovered ? ThemeApi.Theme.surfaceAlt : "transparent")
        Behavior on color { ColorAnimation { duration: 120 } }
    }
}
