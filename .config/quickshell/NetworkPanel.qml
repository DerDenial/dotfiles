import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "Theme" as ThemePalette

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
    property bool canOpen: true
    property Item sourceNotch: null
    property string clockValue: "00:00"
    property int batteryLevel: 0
    property bool batteryCharging: false
    property string hotkeyText: "Super + Shift + N"
    readonly property real expandedWidth: Math.min(550, width - 32)
    // A fixed surface keeps asynchronous network samples from resizing the morph.
    readonly property real expandedHeight: Math.min(550, height - (menuTransition.dropdown ? 58 : 24))
    property bool checkingConnection: false
    signal aboutToOpen()
    readonly property var networkDevice: Networking.devices.values.find(device => device.name === monitor.snapshot.interface.name) || null
    readonly property var wifiNetwork: networkDevice && networkDevice.type === DeviceType.Wifi
        ? networkDevice.networks.values.find(network => network.connected) || null : null
    readonly property string connectionName: wifiNetwork ? wifiNetwork.name : ""
    readonly property real signalPercent: wifiNetwork ? Math.round(wifiNetwork.signalStrength * 100) : -1

    NetworkTelemetry { id: monitor; enabled: panel.opened }
    ConnectionCheckState { id: connectionCheck; enabled: panel.opened }
    function showConnectionCheck() {
        checkingConnection = true;
        if (bodyLoader.item) bodyLoader.item.resetScroll();
        connectionCheck.start();
    }
    function showTraffic() {
        connectionCheck.cancel();
        checkingConnection = false;
        if (bodyLoader.item) bodyLoader.item.resetScroll();
    }
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
            if (panel.opened) surface.forceActiveFocus();
        })
    }
    function open() {
        if (!active) checkingConnection = false;
        if (bodyLoader.ensureLoaded()) menuTransition.open();
    }
    function close() { connectionCheck.cancel(); menuTransition.close(); }
    function toggle() { if (opened || pendingOpen || capturePending || preparing) close(); else open(); }
    visible: menuTransition.visible
    anchors.fill: parent
    IpcHandler {
        target: "networkPanel"
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
            sourceComponent: NetworkPanelBody {
                telemetry: monitor
                diagnostics: connectionCheck
                checkMode: panel.checkingConnection
                onCheckRequested: panel.showConnectionCheck()
                onTrafficRequested: panel.showTraffic()
                connectionName: panel.connectionName
                signalPercent: panel.signalPercent
                hotkeyText: panel.hotkeyText
                onCloseRequested: panel.close()
            }
        }
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: menuTransition.snapshotWidth
            height: menuTransition.snapshotHeight
            source: menuTransition.snapshot ? menuTransition.snapshot.url : ""
            visible: !menuTransition.dropdown && menuTransition.snapshot !== null && (!panel.closing || menuTransition.wideReturn)
            transform: NotchContentStretch {
                transition: menuTransition
                canvasWidth: menuTransition.snapshotWidth
                compact: true
            }
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
        Rectangle {
            visible: !menuTransition.dropdown
            x: 0; y: 0
            width: parent.width; height: parent.border.width
            color: parent.color
            z: 100
        }
    }
}
