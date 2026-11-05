import QtQuick
import "Theme" as ThemePalette
import QtQuick.Layouts
import Quickshell

Item {
    id: popup
    property var settingsController: null

    property string confirmAction: ""
    property string confirmTitle: ""
    property string confirmDescription: ""

    function open() {
        visible = true;
        openAnimation.restart();
    }

    function close() {
        if (settingsController) settingsController.close();
        else closeAnimation.restart();
    }

    function toggle() {
        if (visible)
            close();
        else
            open();
    }

    function chooseAction(action, title) {
        if (action === "lock") {
            close();
            Quickshell.execDetached(["python3", Quickshell.env("HOME") + "/.config/quickshell/LockScreen/lock.py"]);
            return;
        }

        confirmAction = action;
        confirmTitle = title;
        if (action === "logout")
            confirmDescription = "Close your Hyprland session?";
        else if (action === "suspend")
            confirmDescription = "Put the computer to sleep?";
        else if (action === "hibernate")
            confirmDescription = "Save your session and power off?";
        else if (action === "restart")
            confirmDescription = "Restart the computer now?";
        else
            confirmDescription = "Shut down the computer now?";
    }

    function confirm() {
        const action = confirmAction;
        close();

        if (action === "logout")
            Quickshell.execDetached(["hyprctl", "dispatch", "exit"]);
        else if (action === "suspend")
            Quickshell.execDetached(["systemctl", "suspend"]);
        else if (action === "hibernate")
            Quickshell.execDetached(["systemctl", "hibernate"]);
        else if (action === "restart")
            Quickshell.execDetached(["python3", Quickshell.env("HOME") + "/.config/quickshell/session-power.py", "reboot"]);
        else if (action === "shutdown")
            Quickshell.execDetached(["python3", Quickshell.env("HOME") + "/.config/quickshell/session-power.py", "poweroff"]);
    }

    property var powerActions: [
        { title: "Lock", subtitle: "Lock the screen", icon: "lock", action: "lock", color: ThemePalette.Theme.accent },
        { title: "Suspend", subtitle: "Sleep temporarily", icon: "bedtime", action: "suspend", color: ThemePalette.Theme.accent },
        { title: "Hibernate", subtitle: "Save session and power off", icon: "mode_night", action: "hibernate", color: ThemePalette.Theme.accent },
        { title: "Log out", subtitle: "End your Hyprland session", icon: "logout", action: "logout", color: ThemePalette.Theme.red },
        { title: "Restart", subtitle: "Restart the computer", icon: "restart_alt", action: "restart", color: ThemePalette.Theme.red },
        { title: "Shut down", subtitle: "Power off the computer", icon: "power_settings_new", action: "shutdown", color: ThemePalette.Theme.red }
    ]


    Rectangle {
        id: surface
        anchors.fill: parent
        radius: 0
        color: "transparent"
        scale: 0.92
        opacity: 0
        border.width: 0
        border.color: "transparent"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 0
            spacing: 18

                SettingsPageHeader {
        title: popup.confirmAction === "" ? "Power & session" : popup.confirmTitle + "?"
        subtitle: popup.confirmAction === "" ? "Lock, sleep, restart or end your session" : popup.confirmDescription
        iconName: popup.confirmAction === "" ? "power_settings_new" : "warning"
        accentColor: ThemePalette.Theme.accent
    }

            ColumnLayout {
                visible: popup.confirmAction === ""
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 7

                Repeater {
                    model: popup.powerActions

                    delegate: Rectangle {
                        id: actionRow
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 58
                        radius: 16
                        color: actionArea.containsMouse ? ThemePalette.Theme.surfaceRaised : ThemePalette.Theme.surfaceAlt
                        border.width: 1
                        border.color: actionArea.containsMouse ? ThemePalette.Theme.accentDark : ThemePalette.Theme.border

                        Item {
                            id: actionIconSlot
                            width: 26
                            height: 26
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                anchors.fill: parent
                                text: actionRow.modelData.icon
                                color: actionRow.modelData.color
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 20
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        ColumnLayout {
                            anchors.left: actionIconSlot.right
                            anchors.leftMargin: 12
                            anchors.right: actionChevron.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: actionRow.modelData.title
                                color: ThemePalette.Theme.textBright
                                font.family: "Inter"
                                font.pixelSize: 14
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: actionRow.modelData.subtitle
                                color: ThemePalette.Theme.muted
                                font.family: "Inter"
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            id: actionChevron
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20
                            text: "chevron_right"
                            color: ThemePalette.Theme.mutedStrong
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 18
                            horizontalAlignment: Text.AlignHCenter
                        }

                        MouseArea {
                            id: actionArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: popup.chooseAction(actionRow.modelData.action, actionRow.modelData.title)
                        }
                    }
                }
            }

            ColumnLayout {
                visible: popup.confirmAction !== ""
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                Item { Layout.fillHeight: true }

                Text {
                    Layout.fillWidth: true
                    text: popup.confirmDescription
                    color: ThemePalette.Theme.text
                    font.family: "Inter"
                    font.pixelSize: 15
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 42
                        radius: 12
                        color: cancelArea.containsMouse ? ThemePalette.Theme.surfaceRaised : ThemePalette.Theme.surfaceAlt
                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: ThemePalette.Theme.text
                            font.family: "Inter"
                            font.pixelSize: 14
                        }
                        MouseArea {
                            id: cancelArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: popup.confirmAction = ""
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 42
                        radius: 12
                        color: confirmArea.containsMouse ? ThemePalette.Theme.redBright : ThemePalette.Theme.red
                        Text {
                            anchors.centerIn: parent
                            text: "Confirm"
                            color: ThemePalette.Theme.onError
                            font.family: "Inter"
                            font.pixelSize: 14
                            font.weight: Font.Medium
                        }
                        MouseArea {
                            id: confirmArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: popup.confirm()
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }

    ParallelAnimation {
        id: openAnimation
        NumberAnimation { target: surface; property: "scale"; from: 0.92; to: 1; duration: 240; easing.type: Easing.OutCubic }
        NumberAnimation { target: surface; property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
    }

    ParallelAnimation {
        id: closeAnimation
        onFinished: {
            popup.visible = false;
            popup.confirmAction = "";
        }
        NumberAnimation { target: surface; property: "scale"; from: 1; to: 0.94; duration: 170; easing.type: Easing.InCubic }
        NumberAnimation { target: surface; property: "opacity"; from: 1; to: 0; duration: 130 }
    }
}
