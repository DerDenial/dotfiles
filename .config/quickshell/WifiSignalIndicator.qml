import QtQuick
import Quickshell.Networking
import "Theme" as ThemePalette

Item {
    id: indicator
    implicitWidth: 17
    implicitHeight: 14

    // Resolve through the live device models so reconnects and adapter changes update too.
    readonly property var wifiDevice: Networking.devices.values.find(device =>
        device.type === DeviceType.Wifi && device.connected) || null
    readonly property var network: Networking.wifiEnabled && Networking.wifiHardwareEnabled
        && wifiDevice ? wifiDevice.networks.values.find(entry => entry.connected) || null : null
    readonly property bool connected: network !== null
    readonly property real strength: connected ? Math.max(0, Math.min(1, network.signalStrength)) : 0
    readonly property int bars: connected ? Math.max(1, Math.ceil(strength * 4)) : 0

    Row {
        anchors.bottom: parent.bottom
        spacing: 2
        Repeater {
            model: [4, 7, 10, 13]
            delegate: Item {
                required property int index
                required property int modelData
                width: 2.5
                height: 14
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: modelData
                    radius: 1.2
                    color: ThemePalette.Theme.accent
                    opacity: index < indicator.bars ? 0.96 : 0.18
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                }
            }
        }
    }
}
