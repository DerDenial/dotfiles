pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "Theme" as ThemePalette
import "Notifications" as Notifications

Rectangle {
    id: card
    objectName: "notificationCard"
    property var notification: null
    property var service: Notifications.Service
    readonly property string appName: notification ? String(notification.appName || "Notification") : "Notification"
    readonly property string summary: notification ? String(notification.summary || "") : ""
    readonly property string bodyText: notification ? String(notification.body || "") : ""
    readonly property var actions: notification && notification.actions ? Array.from(notification.actions) : []
    readonly property bool hasReply: !!notification && notification.hasInlineReply === true
    readonly property string imageSource: safeImage(notification ? notification.image : "")
    readonly property real progressValue: {
        const hints = notification && notification.hints ? notification.hints : ({});
        const value = Number(hints.value);
        return hints.value !== undefined && Number.isFinite(value) ? Math.max(0, Math.min(100, value)) : -1;
    }
    readonly property string iconSource: resolveIcon(notification)
    readonly property string timestampText: {
        const value = service && notification ? Number(service.timestamp(notification)) : 0;
        return Number.isFinite(value) && value > 0 ? Qt.formatTime(new Date(value), "HH:mm") : "";
    }
    implicitHeight: Math.max(80, content.implicitHeight + 26)
    height: implicitHeight
    radius: 18
    color: ThemePalette.Theme.surface
    border.width: 1
    border.color: Qt.alpha(ThemePalette.Theme.border, 0.38)

    function safeImage(source) {
        const value = String(source || "");
        if (value.startsWith("/") && !value.startsWith("//")) return "file://" + value;
        if (/^file:\/\/(?:localhost)?\//.test(value) || /^image:\/\/(?:qsimage|icon)\//.test(value)) return value;
        return "";
    }
    function resolveIcon(item) {
        if (!item) return "";
        const direct = safeImage(item.appIcon);
        if (direct) return direct;
        const name = String(item.appIcon || "");
        if (name && !name.includes(":") && !name.includes("/")) {
            const icon = Quickshell.iconPath(name, true);
            if (icon) return icon;
        }
        const desktopId = String(item.desktopEntry || "").replace(/\.desktop$/, "");
        const desktop = desktopId ? DesktopEntries.byId(desktopId) : null;
        if (desktop && desktop.icon) {
            const local = safeImage(desktop.icon);
            if (local) return local;
            if (!desktop.icon.includes(":") && !desktop.icon.includes("/")) return Quickshell.iconPath(desktop.icon, true);
        }
        return "";
    }

    Column {
        id: content
        x: 14; y: 13
        width: parent.width - 28
        spacing: 9

        Item {
            width: parent.width; height: 28
            Rectangle {
                width: 27; height: 27; radius: 9
                color: ThemePalette.Theme.surfaceRaised
                Image {
                    id: appIcon
                    anchors.centerIn: parent; width: 19; height: 19
                    source: card.iconSource
                    sourceSize.width: 38; sourceSize.height: 38
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true; cache: false
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: appIcon.status !== Image.Ready
                    text: "notifications"
                    font.family: "Material Symbols Rounded"; font.pixelSize: 18
                    color: ThemePalette.Theme.accent
                }
            }
            Text {
                objectName: "notificationApp"
                x: 36; anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - 142)
                text: card.appName; textFormat: Text.PlainText
                font.family: "Inter"; font.pixelSize: 10; font.weight: Font.DemiBold
                color: ThemePalette.Theme.muted
                elide: Text.ElideRight
            }
            Text {
                anchors.right: dismissButton.left; anchors.rightMargin: 5
                anchors.verticalCenter: parent.verticalCenter
                text: card.timestampText
                textFormat: Text.PlainText
                font.family: "Inter"; font.pixelSize: 9
                color: ThemePalette.Theme.mutedStrong
            }
            ToolButton {
                id: dismissButton
                objectName: "dismissNotification"
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                width: 26; height: 26
                Accessible.name: "Dismiss notification"
                contentItem: Text { text: "close"; font.family: "Material Symbols Rounded"; font.pixelSize: 17; color: ThemePalette.Theme.muted; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 8; color: dismissButton.hovered ? ThemePalette.Theme.surfaceRaised : "transparent" }
                onClicked: if (card.notification && card.service) card.service.dismiss(card.notification)
                ToolTip.visible: hovered
                ToolTip.text: "Dismiss"
            }
        }
        Column {
            width: parent.width; spacing: 4
            visible: summaryLabel.text.length > 0 || bodyLabel.text.length > 0
            Text {
                id: summaryLabel
                objectName: "notificationSummary"
                width: parent.width
                visible: text.length > 0
                text: card.summary; textFormat: Text.PlainText
                font.family: "Inter"; font.pixelSize: 13; font.weight: Font.DemiBold
                color: ThemePalette.Theme.textBright
                wrapMode: Text.Wrap
                maximumLineCount: 3; elide: Text.ElideRight
            }
            Text {
                id: bodyLabel
                objectName: "notificationBody"
                width: parent.width
                visible: text.length > 0
                text: card.bodyText; textFormat: Text.PlainText
                font.family: "Inter"; font.pixelSize: 11
                color: ThemePalette.Theme.muted
                wrapMode: Text.Wrap
                maximumLineCount: 6; elide: Text.ElideRight
            }
        }
        Image {
            objectName: "notificationImage"
            width: parent.width; height: visible ? 120 : 0
            visible: card.imageSource.length > 0 && status !== Image.Error
            source: card.imageSource
            sourceSize.width: Math.round(width * 2); sourceSize.height: 240
            fillMode: Image.PreserveAspectFit
            asynchronous: true; cache: false
        }
        Rectangle {
            width: parent.width; height: 4; radius: 2
            visible: card.progressValue >= 0
            color: ThemePalette.Theme.surfaceRaised
            Rectangle { width: parent.width * card.progressValue / 100; height: parent.height; radius: 2; color: ThemePalette.Theme.accent }
        }
        Flow {
            width: parent.width; spacing: 6
            visible: card.actions.length > 0
            Repeater {
                model: card.actions
                delegate: Button {
                    id: actionButton
                    required property var modelData
                    objectName: "notificationAction"
                    width: Math.min(parent.width, Math.max(68, actionLabel.implicitWidth + 24))
                    height: 31
                    Accessible.name: String(modelData.text || "Open")
                    contentItem: Text {
                        id: actionLabel
                        text: String(actionButton.modelData.text || "Open"); textFormat: Text.PlainText
                        font.family: "Inter"; font.pixelSize: 10; font.weight: Font.Medium
                        color: ThemePalette.Theme.onAccentContainer
                        elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle { radius: 10; color: actionButton.down ? ThemePalette.Theme.surfaceRaised : actionButton.hovered ? ThemePalette.Theme.accentSoft : Qt.alpha(ThemePalette.Theme.accentSoft, 0.65); border.width: 1; border.color: Qt.alpha(ThemePalette.Theme.accent, actionButton.activeFocus ? 0.65 : 0.12) }
                    onClicked: if (card.notification && card.service) card.service.invoke(card.notification, modelData)
                }
            }
        }
        RowLayout {
            width: parent.width; spacing: 6
            visible: card.hasReply
            TextField {
                id: replyField
                objectName: "notificationReply"
                Layout.fillWidth: true; Layout.preferredHeight: 34
                placeholderText: card.notification ? String(card.notification.inlineReplyPlaceholder || "Write a reply…") : "Write a reply…"
                placeholderTextColor: ThemePalette.Theme.mutedStrong
                color: ThemePalette.Theme.textBright
                font.family: "Inter"; font.pixelSize: 11
                selectByMouse: true
                selectionColor: ThemePalette.Theme.accentSoft
                selectedTextColor: ThemePalette.Theme.textBright
                leftPadding: 10; rightPadding: 10
                background: Rectangle { radius: 10; color: ThemePalette.Theme.notchBg; border.width: 1; border.color: replyField.activeFocus ? ThemePalette.Theme.accent : ThemePalette.Theme.border }
                onAccepted: if (text.trim().length && card.notification && card.service) { card.service.reply(card.notification, text); clear(); }
            }
            ToolButton {
                id: sendButton
                objectName: "sendNotificationReply"
                Layout.preferredWidth: 34; Layout.preferredHeight: 34
                enabled: replyField.text.trim().length > 0
                Accessible.name: "Send reply"
                contentItem: Text { text: "arrow_upward"; font.family: "Material Symbols Rounded"; font.pixelSize: 20; color: sendButton.enabled ? ThemePalette.Theme.onAccent : ThemePalette.Theme.mutedStrong; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 11; color: sendButton.enabled ? ThemePalette.Theme.accent : ThemePalette.Theme.surfaceRaised }
                onClicked: if (card.notification && card.service) { card.service.reply(card.notification, replyField.text); replyField.clear(); }
            }
        }
    }
}
