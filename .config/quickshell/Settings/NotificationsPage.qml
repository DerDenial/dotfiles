import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../Theme" as ThemeApi
import "../Notifications" as Notifications

SPage {
    id: page

    property var notificationService: Notifications.Service
    readonly property bool dnd: notificationService.dnd
    readonly property int notificationCount: notificationService.count
    readonly property bool busy: openDelay.running
    property string notice: ""

    function setDnd(enabled) { notificationService.setDnd(enabled); }

    function openCenter() {
        if (busy) return;
        if (controller) controller.close();
        openDelay.restart();
    }

    function clearHistory() {
        if (busy || notificationCount <= 0 || !controller) return;
        controller.confirm("Clear all notifications?", "This removes the current notification history. Dismissed notifications cannot be restored.", function() {
            page.notificationService.clearAll();
            page.notice = "Notification history cleared.";
        });
    }

    function hidePopups() {
        notificationService.hideToast();
        notice = "Pop-up hidden. Your notification history is still available.";
    }

    property Timer openDelay: Timer {
        interval: 120
        onTriggered: page.notificationService.requestCenter()
    }

    SNotice {
        Layout.fillWidth: true
        text: page.notice
    }

    SCard {
        Layout.fillWidth: true
        title: "Do not disturb"
        subtitle: "Choose when notifications can interrupt you"
        iconName: "do_not_disturb_on"

        SRow {
            Layout.fillWidth: true
            title: "Pause notification pop-ups"
            subtitle: page.dnd ? "On · new notifications stay in your history"
                : "Off · new notifications appear in the notch"
            iconName: page.dnd ? "notifications_paused" : "notifications_active"

            SToggle {
                objectName: "notificationDndToggle"
                checked: page.dnd
                enabled: !page.busy
                Accessible.name: "Do not disturb"
                onToggled: {
                    var requested = checked;
                    checked = Qt.binding(function() { return page.dnd; });
                    page.setDnd(requested);
                }
            }
        }

        SLabel {
            Layout.fillWidth: true
            text: "Do not disturb silences pop-ups without deleting notifications. You can still read them in the notification center."
            color: ThemeApi.Theme.muted
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }
    }

    SCard {
        Layout.fillWidth: true
        title: "Notification history"
        subtitle: "Messages, downloads and updates from this session"
        iconName: "inbox"

        RowLayout {
            Layout.fillWidth: true
            spacing: 18

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                Text {
                    objectName: "notificationHistoryCount"
                    text: String(page.notificationCount)
                    color: ThemeApi.Theme.textBright
                    font.family: "Inter"
                    font.pixelSize: 42
                    font.weight: Font.DemiBold
                }

                SLabel {
                    text: page.notificationCount === 0 ? "You're all caught up"
                        : page.notificationCount === 1 ? "Notification in history" : "Notifications in history"
                    color: ThemeApi.Theme.muted
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
            }

            SButton {
                objectName: "openNotificationCenter"
                text: "Open center"
                iconName: "notifications"
                accent: true
                enabled: !page.busy
                onClicked: page.openCenter()
            }
        }

        SRow {
            Layout.fillWidth: true
            title: "Clear notification history"
            subtitle: "Remove all notifications from the center"
            iconName: "delete_sweep"

            SButton {
                objectName: "clearNotificationHistory"
                text: "Clear all"
                destructive: true
                enabled: page.notificationCount > 0 && !page.busy
                onClicked: page.clearHistory()
            }
        }
    }

    SCard {
        Layout.fillWidth: true
        title: "Notch notifications"
        subtitle: "Managed by Quickshell · Super + T opens the center"
        iconName: "notifications"

        SRow {
            Layout.fillWidth: true
            title: "Hide visible pop-up"
            subtitle: "Clear your screen while keeping the notification in history"
            iconName: "visibility_off"

            SButton {
                objectName: "hideNotificationPopup"
                text: "Hide pop-up"
                enabled: !page.busy
                onClicked: page.hidePopups()
            }
        }
    }
}
