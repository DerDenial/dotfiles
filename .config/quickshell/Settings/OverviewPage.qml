import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import "../Theme" as ThemeApi

SPage {
    id: page
    property var info: ({})
    readonly property var wifiDevice: Networking.devices.values.find(device => device.type === DeviceType.Wifi && device.connected) || Networking.devices.values.find(device => device.type === DeviceType.Wifi) || null
    readonly property var wifiNetwork: wifiDevice ? wifiDevice.networks.values.find(network => network.connected) || null : null
    readonly property bool wiredConnected: Networking.devices.values.some(device => device.type === DeviceType.Wired && device.connected)
    readonly property string networkSummary: {
        if (wiredConnected) return "Wired connection";
        if (wifiNetwork) return wifiNetwork.name;
        if (!Networking.wifiHardwareEnabled) return "Wi-Fi blocked";
        if (!Networking.wifiEnabled) return "Wi-Fi off";
        if (wifiDevice && wifiDevice.state === ConnectionState.Connecting) return "Connecting…";
        return "Not connected";
    }
    readonly property var output: Pipewire.defaultAudioSink
    readonly property var input: Pipewire.defaultAudioSource
    readonly property bool audioReady: Pipewire.ready && output && output.ready && output.audio
    readonly property string soundSummary: audioReady ? (output.audio.muted ? "Sound muted" : Math.round(output.audio.volume * 100) + "% volume") : "No output device"
    readonly property var battery: UPower.displayDevice
    readonly property bool batteryReady: battery && battery.ready && battery.isPresent
    readonly property bool charging: batteryReady && battery.state === UPowerDeviceState.Charging
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var connectedBluetooth: adapter ? adapter.devices.values.filter(device => device.connected) : []
    readonly property string bluetoothSummary: !adapter ? "No adapter" : !adapter.enabled ? "Off" : connectedBluetooth.length ? connectedBluetooth.length + (connectedBluetooth.length === 1 ? " connected device" : " connected devices") : "On · ready to connect"

    property PwObjectTracker audioTracker: PwObjectTracker { objects: page.active ? [page.output, page.input].filter(node => node !== null) : [] }

    function refresh() { if (!probe.running) probe.running = true; }
    function bytes(value) { return Number.isFinite(Number(value)) ? (Number(value) / 1073741824).toFixed(1) + " GiB" : "—"; }
    function navigate(target) { if (controller) controller.navigate(target); }
    onActiveChanged: if (active) refresh()
    Component.onCompleted: if (active) refresh()
    property Timer poll: Timer { interval: 10000; running: page.active; repeat: true; onTriggered: page.refresh() }
    property Process probe: Process {
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/Settings/system-info.py", "system"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (!result.error) page.info = result;
                } catch (error) { }
            }
        }
    }

    SCard {
        Layout.fillWidth: true
        padding: 22
        RowLayout {
            Layout.fillWidth: true
            spacing: 22
            Item {
                visible: page.width > 510
                Layout.preferredWidth: 176
                Layout.preferredHeight: 126
                Image {
                    id: wallpaperPreview
                    anchors.fill: parent
                    source: ThemeApi.Theme.activeWallpaper ? "file://" + ThemeApi.Theme.activeWallpaper : ""
                    sourceSize.width: 440
                    sourceSize.height: 315
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    visible: false
                }
                Rectangle {
                    id: previewMask
                    anchors.fill: parent
                    radius: 14
                    layer.enabled: true
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: wallpaperPreview
                    maskEnabled: true
                    maskSource: previewMask
                    autoPaddingEnabled: false
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 9
                SLabel {
                    text: "MAKE IT YOURS"
                    color: ThemeApi.Theme.accent
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                }
                SLabel {
                    Layout.fillWidth: true
                    text: ThemeApi.Theme.activeTheme.name
                    font.pixelSize: 26
                    font.weight: Font.DemiBold
                    color: ThemeApi.Theme.textBright
                    elide: Text.ElideRight
                }
                SLabel {
                    Layout.fillWidth: true
                    text: ThemeApi.Theme.activeThemeId === "material" ? "Your wallpaper sets the colors across your desktop." : "A coordinated theme for your entire desktop."
                    font.pixelSize: 12
                    color: ThemeApi.Theme.muted
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    Layout.topMargin: 3
                    spacing: 8
                    SButton { text: "Personalize"; iconName: "palette"; accent: true; onClicked: page.navigate("appearance") }
                    SButton {
                        text: ""
                        iconName: "shuffle"
                        Accessible.name: "Choose a random wallpaper from the current theme"
                        onClicked: ThemeApi.Theme.randomWallpaper()
                    }
                }
            }
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: width > 470 ? 2 : 1
        columnSpacing: 14
        rowSpacing: 14
        StatusCard {
            Layout.fillWidth: true
            title: "Network"
            iconName: page.wiredConnected ? "lan" : "wifi"
            mainText: page.wifiNetwork || page.wiredConnected ? "Connected" : "Offline"
            detail: page.networkSummary
            onActivated: page.navigate("network")
        }
        StatusCard {
            Layout.fillWidth: true
            title: "Sound"
            iconName: page.audioReady && page.output.audio.muted ? "volume_off" : "volume_up"
            mainText: page.soundSummary
            detail: page.output ? page.output.description || page.output.nickname || page.output.name : "Choose playback and microphone devices"
            onActivated: page.navigate("audio")
        }
        StatusCard {
            Layout.fillWidth: true
            title: "Power"
            iconName: page.charging ? "battery_charging_full" : "battery_full"
            mainText: page.batteryReady ? Math.round(page.battery.percentage * 100) + "% battery" : "Power & session"
            detail: page.charging ? "Charging" : UPower.onBattery ? "Running on battery" : "External power connected"
            onActivated: page.navigate("power")
        }
        StatusCard {
            Layout.fillWidth: true
            title: "System"
            iconName: "memory"
            mainText: page.info.memoryTotal ? Math.round(page.info.memoryPercent) + "% memory" : "System information"
            detail: page.info.memoryTotal ? page.bytes(page.info.memoryUsed) + " of " + page.bytes(page.info.memoryTotal) + " in use" : "Performance, storage and device information"
            onActivated: page.navigate("system")
        }
    }

    SCard {
        Layout.fillWidth: true
        padding: 16
        SRow {
            Layout.fillWidth: true
            title: "Bluetooth"
            subtitle: page.connectedBluetooth.length ? page.connectedBluetooth.map(device => device.name || "Bluetooth device").join(", ") : "Headphones, keyboards and nearby devices"
            iconName: "bluetooth"
            value: page.bluetoothSummary
            interactive: true
            onClicked: page.navigate("bluetooth")
        }
        SRow {
            Layout.fillWidth: true
            title: page.info.hostname || "This computer"
            subtitle: page.info.os ? page.info.os + " · " + (page.info.architecture || "") : "Hardware and operating system details"
            iconName: "computer"
            interactive: true
            onClicked: page.navigate("system")
        }
    }

    component StatusCard: SCard {
        id: tile
        property string mainText: ""
        property string detail: ""
        signal activated()
        padding: 20
        color: tileMouse.containsMouse ? ThemeApi.Theme.surfaceAlt : ThemeApi.Theme.surface
        border.width: activeFocus ? 2 : 1
        border.color: activeFocus ? ThemeApi.Theme.accent : Qt.rgba(ThemeApi.Theme.border.r, ThemeApi.Theme.border.g, ThemeApi.Theme.border.b, 0.55)
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: title + ": " + mainText + ". " + detail
        Keys.onReturnPressed: activated()
        Keys.onSpacePressed: activated()
        Behavior on color { ColorAnimation { duration: 150 } }
        SLabel {
            Layout.fillWidth: true
            text: tile.mainText
            font.pixelSize: 23
            font.weight: Font.DemiBold
            color: ThemeApi.Theme.textBright
            elide: Text.ElideRight
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            SLabel {
                Layout.fillWidth: true
                text: tile.detail
                font.pixelSize: 11
                color: ThemeApi.Theme.muted
                elide: Text.ElideRight
            }
            Text {
                text: "arrow_forward"
                color: ThemeApi.Theme.accent
                font.family: "Material Symbols Rounded"
                font.pixelSize: 18
            }
        }
        property MouseArea clickArea: MouseArea {
            id: tileMouse
            parent: tile
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.activated()
        }
    }
}
