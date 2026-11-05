import QtQuick
import Quickshell.Hyprland
import "Theme" as ThemePalette

Item {
    id: root

    property int maxIndicators: 5
    property bool animated: true
    readonly property bool containsMouse: hoverHandler.hovered

    implicitWidth: maxIndicators * 6 + Math.max(0, maxIndicators - 1) * 2
    implicitHeight: 24

    Row {
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: root.maxIndicators

            delegate: Item {
                required property int index
                readonly property int workspaceId: index + 1
                readonly property var workspace: Hyprland.workspaces.values.find(item => Number(item.id) === workspaceId) || null
                readonly property bool occupied: workspace ? workspace.toplevels.values.length > 0 : false

                width: 6
                height: root.height

                Rectangle {
                    anchors.centerIn: parent
                    width: 14
                    height: 22
                    radius: 11
                    color: ThemePalette.Theme.accent
                    opacity: parent.workspace && parent.workspace.active ? 0.07 : 0
                    Behavior on opacity { enabled: root.animated; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 9
                    height: 18
                    radius: 9
                    color: ThemePalette.Theme.accent
                    opacity: parent.workspace && parent.workspace.active ? 0.14 : 0
                    Behavior on opacity { enabled: root.animated; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 4
                    height: parent.workspace && parent.workspace.active ? 14 : parent.occupied ? 10 : 6
                    radius: 2
                    color: ThemePalette.Theme.accent
                    opacity: parent.workspace && parent.workspace.active ? 1 : parent.occupied ? 0.64 : 0.34

                    Behavior on opacity {
                        enabled: root.animated
                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }

                    Behavior on height {
                        enabled: root.animated
                        NumberAnimation {
                            duration: 320
                            easing.type: Easing.OutBack
                            easing.overshoot: 0.65
                        }

                    }

                    Behavior on color {
                        enabled: root.animated
                        ColorAnimation {
                            duration: 160
                        }

                    }

                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (parent.workspace) parent.workspace.activate();
                        else Hyprland.dispatch(Hyprland.usingLua
                            ? "hl.dsp.focus({workspace=" + parent.workspaceId + "})"
                            : "workspace " + parent.workspaceId);
                    }
                }

            }

        }

    }

    HoverHandler {
        id: hoverHandler
    }

}
