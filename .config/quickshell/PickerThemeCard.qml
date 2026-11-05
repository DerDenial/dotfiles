pragma ComponentBehavior: Bound

import QtQuick
import "Theme" as ThemeApi

Item {
    id: card

    required property var profile
    property bool selected: false
    property bool externalSelection: false
    property bool applied: false
    property bool animationsEnabled: false
    signal chosen()
    signal accepted()

    implicitWidth: 220
    implicitHeight: 176

    Accessible.role: Accessible.Button
    Accessible.name: profile.name + (applied ? ", current theme" : "")
    Accessible.description: selected ? "Selected. Press Enter to apply." : "Select theme"
    Accessible.onPressAction: chosen()

    readonly property var profileColors: profile.colors
    readonly property color candidateAccent: profileColors.accent || profileColors.aqua

    Rectangle {
        id: face
        anchors.fill: parent
        anchors.margins: 4
        radius: 18
        color: card.selected ? Qt.alpha(card.profileColors.surface, 0.9)
                             : pointer.containsMouse ? ThemeApi.Theme.surfaceAlt : ThemeApi.Theme.surface
        border.width: card.selected && card.externalSelection ? 0 : card.selected ? 2 : 1
        border.color: card.selected ? card.candidateAccent
                                   : pointer.containsMouse ? Qt.alpha(card.candidateAccent, 0.55) : ThemeApi.Theme.border
        scale: card.externalSelection ? 1 : card.selected ? 1 : pointer.containsMouse ? 0.985 : 0.96

        Behavior on scale {
            enabled: card.animationsEnabled && !card.externalSelection
            NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 0.65 }
        }

        Rectangle {
            id: desktop
            x: 8
            y: 8
            width: parent.width - 16
            height: 84
            radius: 12
            color: card.profileColors.bgDim
            clip: true

            // A small desktop made from the candidate palette, without image textures.
            Rectangle {
                x: desktop.width - 64
                y: 22
                width: 60
                height: 60
                radius: 30
                color: Qt.alpha(card.candidateAccent, 0.13)
            }
            Rectangle {
                x: 7
                y: 27
                width: 42
                height: 42
                radius: 21
                color: Qt.alpha(card.profileColors.purple, 0.12)
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0
                width: 48
                height: 10
                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius: 5
                bottomRightRadius: 5
                color: card.profileColors.notchBg || card.profileColors.bgDim
                Row {
                    x: 7
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            required property int index
                            width: 2
                            height: index === 0 ? 5 : 3
                            radius: 1
                            color: index === 0 ? card.candidateAccent : card.profileColors.mutedStrong
                        }
                    }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 10
                    height: 2
                    radius: 1
                    color: card.profileColors.textBright
                }
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 7
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7
                    height: 3
                    radius: 1
                    color: card.candidateAccent
                }
            }

            Rectangle {
                id: miniWindow
                x: 34
                y: 25
                width: desktop.width - 52
                height: 51
                radius: 7
                color: card.profileColors.bg0
                border.width: 1
                border.color: Qt.alpha(card.candidateAccent, 0.55)

                Row {
                    x: 8
                    y: 7
                    spacing: 3
                    Repeater {
                        model: [card.profileColors.red, card.profileColors.yellow, card.profileColors.green]
                        delegate: Rectangle {
                            required property color modelData
                            width: 3
                            height: 3
                            radius: 2
                            color: modelData
                        }
                    }
                }

                Rectangle {
                    x: 6
                    y: 16
                    width: 28
                    height: 29
                    radius: 4
                    color: card.profileColors.surface
                    Rectangle {
                        x: 4; y: 5
                        width: 20; height: 6
                        radius: 2
                        color: card.profileColors.accentSoft || card.profileColors.surfaceAlt
                        Rectangle { x: 3; y: 2; width: 11; height: 2; radius: 1; color: card.candidateAccent }
                    }
                    Rectangle { x: 7; y: 15; width: 14; height: 2; radius: 1; color: card.profileColors.mutedStrong }
                    Rectangle { x: 7; y: 22; width: 10; height: 2; radius: 1; color: card.profileColors.mutedStrong }
                }

                Column {
                    x: 42
                    y: 19
                    spacing: 4
                    Rectangle { width: 42; height: 3; radius: 1.5; color: card.candidateAccent }
                    Row {
                        spacing: 4
                        Rectangle { width: 14; height: 2; radius: 1; color: card.profileColors.purple }
                        Rectangle { width: 31; height: 2; radius: 1; color: card.profileColors.muted }
                    }
                    Row {
                        spacing: 4
                        Rectangle { width: 24; height: 2; radius: 1; color: card.profileColors.green }
                        Rectangle { width: 19; height: 2; radius: 1; color: card.profileColors.blue }
                    }
                    Rectangle { width: 57; height: 2; radius: 1; color: card.profileColors.mutedStrong }
                }
            }

            Rectangle {
                x: 7
                y: 7
                width: currentLabel.implicitWidth + 12
                height: 18
                radius: 9
                visible: card.applied
                color: card.profileColors.surfaceRaised
                Text {
                    id: currentLabel
                    anchors.centerIn: parent
                    text: "Current"
                    color: card.profileColors.textBright
                    font.family: "Inter"
                    font.pixelSize: 9
                    font.weight: Font.Medium
                }
            }
        }

        Text {
            x: 12
            y: 101
            width: parent.width - 48
            height: 19
            text: card.profile.name
            color: ThemeApi.Theme.textBright
            font.family: "Inter"
            font.pixelSize: 13
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }

        Text {
            x: 12
            y: 121
            width: parent.width - 24
            height: 15
            text: card.profile.flavor
            color: ThemeApi.Theme.muted
            font.family: "Inter"
            font.pixelSize: 10
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }

        Row {
            x: 12
            y: 145
            spacing: 5
            Repeater {
                model: [card.profileColors.red, card.profileColors.orange, card.profileColors.green,
                        card.profileColors.blue, card.profileColors.purple, card.candidateAccent]
                delegate: Rectangle {
                    required property color modelData
                    width: 8
                    height: 8
                    radius: 4
                    color: modelData
                }
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 11
            y: 100
            width: 20
            height: 20
            radius: 10
            visible: card.selected
            color: card.candidateAccent
            Text {
                anchors.centerIn: parent
                text: "check"
                color: card.profileColors.onAccent || card.profileColors.bg0
                font.family: "Material Symbols Rounded"
                font.pixelSize: 14
            }
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: card.chosen()
        onDoubleClicked: card.accepted()
    }
}
