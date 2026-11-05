pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import "Theme" as ThemePalette
import "Notifications" as Notifications

Item {
    id: root
    objectName: "notificationToastContent"
    property var service: Notifications.Service
    property real expandedWidth: 380
    property real expandedHeight: 100
    property bool compactMode: false
    readonly property real foldHeight: 42
    readonly property real stretch: compactMode ? 1 : Math.max(0, Math.min(1.06, (height - foldHeight) / Math.max(1, expandedHeight - foldHeight)))
    readonly property real reveal: Math.min(1, stretch)
    readonly property bool hovered: toastHover.hovered
    // Retain display fields while the source object closes and the outline folds.
    property string cachedApp: "Notification"
    property string cachedSummary: ""
    property string cachedBody: ""
    property string cachedIcon: ""
    property string cachedAvatar: ""
    property string cachedInitials: ""
    readonly property var notification: service ? service.toast : null
    function updateDisplay() {
        if (!notification) return;
        cachedApp = String(notification.appName || "Notification");
        cachedSummary = String(notification.summary || "");
        cachedBody = String(notification.body || "");
        cachedIcon = resolveIcon(notification);
        // Browser-supplied images are separate from the browser/application icon.
        cachedAvatar = safeImage(notification.image);
        cachedInitials = initials(cachedSummary || cachedApp);
    }
    function initials(name) {
        const words = String(name || "").slice(0, 160).trim().split(/\s+/);
        function firstLetter(word) {
            return Array.from(word).find(character => character.toLocaleUpperCase() !== character.toLocaleLowerCase()
                || /[0-9]/.test(character)) || "";
        }
        const letters = words.map(firstLetter).filter(letter => letter.length > 0);
        return (letters.length > 1 ? letters[0] + letters[letters.length - 1] : letters[0] || "").toLocaleUpperCase();
    }
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
    onNotificationChanged: updateDisplay()
    Component.onCompleted: updateDisplay()
    Connections {
        target: root.notification
        ignoreUnknownSignals: true
        function onAppNameChanged() { root.updateDisplay(); }
        function onAppIconChanged() { root.updateDisplay(); }
        function onDesktopEntryChanged() { root.updateDisplay(); }
        function onSummaryChanged() { root.updateDisplay(); }
        function onBodyChanged() { root.updateDisplay(); }
        function onImageChanged() { root.updateDisplay(); }
    }
    HoverHandler { id: toastHover }

    Item {
        width: Math.max(0, root.width - 24)
        height: Math.max(0, root.expandedHeight - 16) * root.reveal
        anchors.horizontalCenter: parent.horizontalCenter
        y: 8 * root.reveal
        clip: true
        Item {
            width: root.expandedWidth - 24
            height: root.expandedHeight - 16
            anchors.horizontalCenter: parent.horizontalCenter
            transform: Scale {
                origin.x: (root.expandedWidth - 24) / 2
                xScale: (root.width - 24) / Math.max(1, root.expandedWidth - 24)
                yScale: root.stretch
            }
            MouseArea {
                objectName: "openToastCenter"
                anchors.fill: parent
                enabled: root.service && root.service.toastActive && root.reveal > 0.7
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.service) root.service.requestCenter()
                Accessible.role: Accessible.Button
                Accessible.name: "Open notification center"
            }
            Rectangle {
                x: 0; y: 0; width: 20; height: 20; radius: 6
                color: ThemePalette.Theme.surface
                Image { id: appIcon; anchors.centerIn: parent; width: 16; height: 16; source: root.cachedIcon; sourceSize.width: 32; sourceSize.height: 32; fillMode: Image.PreserveAspectFit; asynchronous: true; cache: false; visible: status === Image.Ready }
                Text { anchors.centerIn: parent; visible: appIcon.status !== Image.Ready; text: "notifications"; font.family: "Material Symbols Rounded"; font.pixelSize: 15; color: ThemePalette.Theme.accent }
            }
            Text {
                objectName: "toastApp"
                x: 29; y: 2; width: parent.width - 66
                text: root.cachedApp; textFormat: Text.PlainText
                color: ThemePalette.Theme.muted
                font.family: "Inter"; font.pixelSize: 12; font.weight: Font.Medium
                elide: Text.ElideRight
            }
            Item {
                id: messageArea
                x: 0; y: 25
                width: parent.width
                height: Math.max(0, parent.height - 25)
                Rectangle {
                    id: avatar
                    objectName: "toastAvatar"
                    x: 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36; height: 36; radius: 18
                    readonly property bool hasPhoto: avatarImage.status === Image.Ready
                        && avatarImage.implicitWidth > 0 && avatarImage.implicitHeight > 0
                        && avatarImage.implicitWidth / avatarImage.implicitHeight >= 0.8
                        && avatarImage.implicitWidth / avatarImage.implicitHeight <= 1.25
                    // Qt's software scene graph cannot draw shader masks.
                    readonly property bool showPhoto: hasPhoto && GraphicsInfo.api !== GraphicsInfo.Software
                    color: ThemePalette.Theme.accentSoft
                    border.width: 1
                    border.color: Qt.alpha(ThemePalette.Theme.accent, 0.18)
                    Accessible.role: Accessible.Graphic
                    Accessible.name: showPhoto ? "Notification picture" : "Sender initials"
                    Text {
                        anchors.centerIn: parent
                        visible: !avatar.showPhoto
                        text: root.cachedInitials || "person"
                        color: ThemePalette.Theme.accent
                        font.family: root.cachedInitials ? "Inter" : "Material Symbols Rounded"
                        font.pixelSize: root.cachedInitials ? 16 : 22
                        font.weight: Font.DemiBold
                    }
                    Image {
                        id: avatarImage
                        objectName: "toastAvatarImage"
                        anchors.fill: parent
                        source: root.cachedAvatar
                        sourceSize.width: 72; sourceSize.height: 72
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        visible: false
                    }
                    Rectangle {
                        id: avatarMask
                        anchors.fill: parent
                        radius: 18
                        color: "white"
                        layer.enabled: true
                        visible: false
                    }
                    MultiEffect {
                        anchors.fill: parent
                        visible: avatar.showPhoto
                        source: avatarImage
                        maskEnabled: true
                        maskSource: avatarMask
                        autoPaddingEnabled: false
                    }
                }
                Column {
                    x: 46
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - 46)
                    spacing: 3
                    Text {
                        objectName: "toastSummary"
                        width: parent.width
                        visible: text.length > 0
                        text: root.cachedSummary; textFormat: Text.PlainText
                        color: ThemePalette.Theme.textBright
                        font.family: "Inter"; font.pixelSize: 14; font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        objectName: "toastBody"
                        width: parent.width
                        visible: text.length > 0
                        text: root.cachedBody; textFormat: Text.PlainText
                        color: ThemePalette.Theme.text
                        font.family: "Inter"; font.pixelSize: 14
                        wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                    }
                }
            }
            ToolButton {
                id: closeButton
                objectName: "hideNotificationToast"
                anchors.right: parent.right; y: -1
                width: 27; height: 27
                enabled: root.service && root.service.toastActive && root.reveal > 0.7
                focusPolicy: Qt.NoFocus
                Accessible.name: "Hide notification preview"
                contentItem: Text { text: "close"; font.family: "Material Symbols Rounded"; font.pixelSize: 18; color: ThemePalette.Theme.muted; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 9; color: closeButton.hovered ? ThemePalette.Theme.surfaceRaised : "transparent" }
                onClicked: if (root.service) root.service.hideToast()
            }
        }
    }
}
