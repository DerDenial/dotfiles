import Quickshell
import Quickshell.Hyprland
import QtQuick
import "Theme" as ThemePalette
import QtQuick.Layouts

Rectangle {
    id: root

    implicitWidth: row.implicitWidth + 22
    implicitHeight: 33
    radius: height / 2
    color: "transparent"

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 4

        Repeater {
            model: Hyprland.workspaces

            delegate: Rectangle {
                id: workspaceChip

                required property var modelData
                property bool occupied: modelData.toplevels.values.length > 0
                property string workspaceLabel: {
                    const name = String(modelData.name || "");
                    if (name.length > 0 && !/^-?[0-9]+$/.test(name))
                        return name.replace(/^special:/, "");
                    return String(modelData.id);
                }

                implicitWidth: Math.max(27, label.implicitWidth + 14)
                implicitHeight: 25
                radius: 9
                color: modelData.active ? ThemePalette.Theme.accent : ThemePalette.Theme.surfaceAlt
                border.width: modelData.active ? 0 : 1
                border.color: ThemePalette.Theme.border

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: workspaceChip.workspaceLabel
                    color: workspaceChip.modelData.active ? ThemePalette.Theme.surface : ThemePalette.Theme.text
                    font.family: "Inter"
                    font.pixelSize: 12
                    font.weight: workspaceChip.modelData.active ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }

                Rectangle {
                    visible: workspaceChip.occupied
                    width: 4
                    height: 4
                    radius: 2
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: 3
                    anchors.bottomMargin: 3
                    color: workspaceChip.modelData.active ? ThemePalette.Theme.surface : ThemePalette.Theme.accent
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: workspaceChip.modelData.activate()
                }

                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
                Behavior on implicitWidth {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
            }
        }
    }
}
