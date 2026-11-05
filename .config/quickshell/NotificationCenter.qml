import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "Theme" as ThemePalette
import "Notifications" as Notifications

Item {
    id: panel
    readonly property alias morphSurface: surface
    property alias opened: menuTransition.opened
    property alias closing: menuTransition.closing
    property alias pendingOpen: menuTransition.pendingOpen
    readonly property bool active: menuTransition.active
    readonly property bool handoffActive: menuTransition.ownsSurface
    readonly property bool ownsSurface: menuTransition.ownsSurface
    readonly property bool dropdownMode: menuTransition.dropdown
    readonly property bool capturePending: menuTransition.capturePending
    readonly property bool preparing: menuTransition.preparing
    readonly property bool returning: menuTransition.returning
    readonly property real morphProgress: menuTransition.motion.amount
    property var service: Notifications.Service
    property bool canOpen: true
    property Item sourceNotch: null
    property string clockValue: "00:00"
    property int batteryLevel: 0
    property bool batteryCharging: false
    readonly property real expandedWidth: Math.min(470, Math.max(236, width - 32))
    readonly property real expandedHeight: Math.min(Math.max(130, height - (menuTransition.dropdown ? 58 : 24)), 600,
        (bodyLoader.item ? bodyLoader.item.desiredHeight : 198) + 34)
    signal aboutToOpen()
    onExpandedHeightChanged: if (menuTransition.opened) menuTransition.motion.moveTo(expandedWidth, expandedHeight, menuTransition.dropdown ? 24 : 28, 1, true)
    onExpandedWidthChanged: if (menuTransition.opened) menuTransition.motion.moveTo(expandedWidth, expandedHeight, menuTransition.dropdown ? 24 : 28, 1, true)

    NotchTransition {
        id: menuTransition
        dropdownAlignment: 1
        surface: surface
        sourceNotch: panel.sourceNotch
        expandedWidth: panel.expandedWidth
        expandedHeight: panel.expandedHeight
        canOpen: panel.canOpen
        onAboutToOpen: panel.aboutToOpen()
        onActivated: Qt.callLater(function() {
            if (bodyLoader.item) bodyLoader.item.resetScroll();
            if (panel.service) panel.service.markAllRead();
            if (panel.opened) surface.forceActiveFocus();
        })
    }
    function open() { if (bodyLoader.ensureLoaded()) menuTransition.open(); }
    function close() { menuTransition.close(); }
    function toggle() { if (opened || pendingOpen || capturePending || preparing) close(); else open(); }
    visible: menuTransition.visible
    anchors.fill: parent
    IpcHandler {
        target: "notificationCenter"
        function toggle(): void { panel.toggle(); }
        function open(): void { panel.open(); }
        function close(): void { panel.close(); }
    }
    MouseArea { anchors.fill: parent; enabled: panel.opened; onClicked: panel.close() }
    NotchMenuSurface {
        id: surface
        transition: menuTransition
        color: ThemePalette.Theme.notchBg
        border.width: 1
        border.color: ThemePalette.Theme.border
        Keys.onEscapePressed: panel.close()
        MouseArea { anchors.fill: parent }
        MenuBodyLoader {
            id: bodyLoader
            engaged: menuTransition.active || menuTransition.pendingOpen
            width: panel.expandedWidth - 36
            height: panel.expandedHeight - 34
            anchors.horizontalCenter: parent.horizontalCenter
            y: 17 * Math.min(1, bodyStretch.unfold)
            enabled: panel.opened
            visible: panel.opened || panel.closing
            transform: NotchContentStretch {
                id: bodyStretch
                transition: menuTransition
                canvasWidth: panel.expandedWidth - 36
                horizontalInset: 36
            }
            sourceComponent: NotificationCenterBody {
                service: panel.service
                onCloseRequested: panel.close()
            }
        }
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: menuTransition.snapshotWidth
            height: menuTransition.snapshotHeight
            source: menuTransition.snapshot ? menuTransition.snapshot.url : ""
            visible: !menuTransition.dropdown && menuTransition.snapshot !== null && (!panel.closing || menuTransition.wideReturn)
            transform: NotchContentStretch { transition: menuTransition; canvasWidth: menuTransition.snapshotWidth; compact: true }
            fillMode: Image.Stretch
            onStatusChanged: {
                menuTransition.snapshotReady = status === Image.Ready || status === Image.Error;
                if (menuTransition.preparing && surface.Window.window) surface.Window.window.update();
            }
        }
        CompactNotch {
            anchors.horizontalCenter: parent.horizontalCenter
            clockValue: panel.clockValue
            batteryLevel: panel.batteryLevel
            batteryCharging: panel.batteryCharging
            visible: !menuTransition.dropdown && ((panel.closing && !menuTransition.wideReturn) || menuTransition.snapshot === null)
            transform: NotchContentStretch { transition: menuTransition; canvasWidth: 236; compact: true }
        }
        Rectangle { visible: !menuTransition.dropdown; x: 0; y: 0; width: parent.width; height: parent.border.width; color: parent.color; z: 100 }
    }
}
