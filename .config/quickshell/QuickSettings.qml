import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import "SystemState" as SystemState
import Quickshell.Services.Pipewire
import "Theme" as ThemePalette
import "Notifications" as Notifications

Item {
    id: panel
    TailscaleState { id: tailscale; polling: panel.opened }
    readonly property alias morphSurface: surface
    readonly property var scrollViewport: bodyLoader.item ? bodyLoader.item.scrollViewport : null
    readonly property bool brightnessDragging: bodyLoader.item ? bodyLoader.item.brightnessDragging : false
    property alias opened: menuTransition.opened
    property alias closing: menuTransition.closing
    property alias pendingOpen: menuTransition.pendingOpen
    readonly property bool active: menuTransition.active
    readonly property bool handoffActive: menuTransition.ownsSurface
    readonly property bool dropdownMode: menuTransition.dropdown
    readonly property bool capturePending: menuTransition.capturePending
    readonly property bool preparing: menuTransition.preparing
    readonly property bool returning: menuTransition.returning
    readonly property real morphProgress: menuTransition.motion.amount
    property bool canOpen: true
    property Item sourceNotch: null
    readonly property real expandedWidth: Math.min(480, width - 32)
    readonly property real expandedHeight: Math.min(560, height - (menuTransition.dropdown ? 58 : 24))
    NotchTransition {
        id: menuTransition
        dropdownAlignment: 1
        surface: surface
        sourceNotch: panel.sourceNotch
        expandedWidth: panel.expandedWidth
        expandedHeight: panel.expandedHeight
        canOpen: panel.canOpen
        onAboutToOpen: panel.aboutToOpen()
        onActivated: {
            panel.refreshBrightness();
            if (panel.scrollViewport) panel.scrollViewport.contentY = 0;
            Qt.callLater(function() { surface.forceActiveFocus(); });
        }
    }
    property string clockValue: "00:00"
    property int batteryLevel: 0
    property bool batteryCharging: false
    signal aboutToOpen()
    signal settingsRequested(string page)
    signal networkRequested()
    signal notificationsRequested()

    readonly property var wifiDevice: Networking.devices.values.find(device => device.type === DeviceType.Wifi && device.connected) || Networking.devices.values.find(device => device.type === DeviceType.Wifi) || null
    readonly property string wifiStatus: {
        if (!wifiDevice) return "No Wi-Fi adapter";
        if (!Networking.wifiHardwareEnabled) return "Hardware blocked";
        if (!Networking.wifiEnabled) return "Turned off";
        if (wifiDevice.state === ConnectionState.Connecting) return "Connecting…";
        const network = wifiDevice.networks.values.find(entry => entry.connected);
        return network ? network.name : "Not connected";
    }
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool bluetoothBusy: adapter && (adapter.state === BluetoothAdapterState.Enabling || adapter.state === BluetoothAdapterState.Disabling)
    readonly property string bluetoothStatus: {
        if (!adapter) return "No Bluetooth adapter";
        if (adapter.state === BluetoothAdapterState.Blocked) return "Hardware blocked";
        if (bluetoothBusy) return adapter.state === BluetoothAdapterState.Enabling ? "Turning on…" : "Turning off…";
        if (!adapter.enabled) return "Turned off";
        const connected = adapter.devices.values.filter(device => device.connected);
        return connected.length ? connected.map(device => device.name || "Device").join(", ") : "On · no connected devices";
    }
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink && sink.ready ? sink.audio : null
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sourceAudio: source && source.ready ? source.audio : null
    PwObjectTracker { objects: [panel.sink, panel.source].filter(node => !!node) }

    property bool brightnessAvailable: false
    property real brightnessPercent: 0
    property string brightnessDevice: ""
    property string brightnessError: ""
    property int pendingBrightness: -1

    function refreshBrightness() {
        if (!brightnessRead.running) brightnessRead.running = true;
    }
    function requestBrightness(percent) {
        if (!brightnessAvailable) return;
        pendingBrightness = Math.max(1, Math.min(100, Math.round(percent)));
        brightnessPercent = pendingBrightness;
        brightnessError = "";
        brightnessDebounce.restart();
    }
    function flushBrightness() {
        if (pendingBrightness < 0 || brightnessWrite.running || !brightnessDevice) return;
        const target = pendingBrightness;
        pendingBrightness = -1;
        brightnessWrite.command = ["brightnessctl", "-d", brightnessDevice, "set", target + "%"];
        brightnessWrite.running = true;
    }
    Process {
        id: brightnessRead
        command: ["brightnessctl", "-c", "backlight", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const fields = text.trim().split("\n")[0].split(",");
                const percent = Number((fields[3] || "").replace("%", ""));
                if (fields.length >= 5 && Number.isFinite(percent)) {
                    panel.brightnessAvailable = true;
                    panel.brightnessDevice = fields[0];
                    if (!panel.brightnessDragging && panel.pendingBrightness < 0 && !brightnessWrite.running)
                        panel.brightnessPercent = percent;
                } else panel.brightnessAvailable = false;
            }
        }
        onExited: function(code, status) {
            if (code !== 0) { panel.brightnessAvailable = false; panel.brightnessError = "Brightness unavailable"; }
        }
    }
    Process {
        id: brightnessWrite
        onExited: function(code, status) {
            if (code !== 0) panel.brightnessError = "Could not change brightness";
            if (panel.pendingBrightness >= 0) brightnessDebounce.restart();
            else panel.refreshBrightness();
        }
    }
    Timer { id: brightnessDebounce; interval: 50; onTriggered: panel.flushBrightness() }
    Timer { interval: 1000; running: panel.opened; repeat: true; onTriggered: panel.refreshBrightness() }

    // One in-process owner keeps this tile and the center in sync without polling.
    property var notificationService: Notifications.Service
    readonly property bool dndAvailable: true
    readonly property bool dndEnabled: notificationService.dnd
    readonly property string dndError: ""
    readonly property bool dndBusy: false
    function toggleDnd() { notificationService.setDnd(!notificationService.dnd); }

    function open() {
        // Build synchronously before capture/reveal, so the first frame is ready.
        if (bodyLoader.ensureLoaded()) menuTransition.open();
    }
    function close() { flushBrightness(); menuTransition.close(); }
    function toggle() {
        if (opened || pendingOpen || capturePending || preparing) close();
        else open();
    }
    function showSettings(page) { close(); settingsRequested(page); }
    visible: menuTransition.visible
    anchors.fill: parent
    IpcHandler {
        target: "quickSettings"
        function toggle(): void { panel.toggle(); }
        function open(): void { panel.open(); }
        function close(): void { panel.close(); }
    }
    MouseArea { anchors.fill: parent; enabled: panel.opened; onClicked: panel.close() }
    NotchMenuSurface {
        id: surface
        transition: menuTransition
        color: ThemePalette.Theme.notchBg
        border.width: 1; border.color: ThemePalette.Theme.border
        Keys.onEscapePressed: panel.close()
        MouseArea { anchors.fill: parent }

        MenuBodyLoader {
            id: bodyLoader
            engaged: menuTransition.active || menuTransition.pendingOpen
            width: panel.expandedWidth - 40
            height: panel.expandedHeight - 36
            anchors.horizontalCenter: parent.horizontalCenter
            y: 18 * Math.min(1, bodyStretch.unfold)
            enabled: panel.opened
            visible: panel.opened || panel.closing
            transform: NotchContentStretch {
                id: bodyStretch
                transition: menuTransition
                canvasWidth: panel.expandedWidth - 40
                horizontalInset: 40
            }
            sourceComponent: Item {
                anchors.fill: parent
                property alias scrollViewport: viewport
                readonly property bool brightnessDragging: brightnessControl.dragging
                Flickable {
                    id: viewport
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: body.implicitHeight
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    ScrollBar.vertical: ScrollBar {
                        policy: viewport.contentHeight > viewport.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                        width: 3
                    }
                    Column {
                        id: body
                        width: viewport.width
                        spacing: 10
                        Item {
                            width: parent.width; height: 46
                            Text {
                                text: "CONTROL CENTER"
                                color: ThemePalette.Theme.mutedStrong
                                font.family: "Inter"; font.pixelSize: 9; font.weight: Font.DemiBold; font.letterSpacing: 1.2
                            }
                            Text {
                                y: 16
                                text: "Quick settings"
                                color: ThemePalette.Theme.textBright
                                font.family: "Inter"; font.pixelSize: 21; font.weight: Font.DemiBold
                            }
                            ToolButton {
                                id: notificationsShortcut
                                objectName: "notificationsShortcut"
                                anchors.right: networkShortcut.left
                                anchors.rightMargin: 8
                                y: 2
                                width: 34; height: 34
                                Accessible.name: "Notifications"
                                ToolTip.visible: hovered
                                ToolTip.text: "Notifications"
                                contentItem: Text {
                                    text: "notifications"; color: ThemePalette.Theme.accent
                                    font.family: "Material Symbols Rounded"; font.pixelSize: 20
                                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle { radius: 12; color: parent.hovered ? ThemePalette.Theme.surfaceRaised : ThemePalette.Theme.surface }
                                onClicked: panel.notificationsRequested()
                            }
                            ToolButton {
                                id: networkShortcut
                                anchors.right: closeQuickSettings.left
                                anchors.rightMargin: 8
                                y: 2
                                width: 34; height: 34
                                Accessible.name: "Live network traffic"
                                ToolTip.visible: hovered
                                ToolTip.text: "Live network traffic"
                                contentItem: Text {
                                    text: "monitoring"; color: ThemePalette.Theme.accent
                                    font.family: "Material Symbols Rounded"; font.pixelSize: 20
                                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle { radius: 12; color: parent.hovered ? ThemePalette.Theme.surfaceRaised : ThemePalette.Theme.surface }
                                onClicked: panel.networkRequested()
                            }
                            ToolButton {
                                id: closeQuickSettings
                                anchors.right: parent.right
                                y: 2
                                width: 34; height: 34
                                Accessible.name: "Close quick settings"
                                contentItem: Text {
                                    text: "close"; color: ThemePalette.Theme.muted
                                    font.family: "Material Symbols Rounded"; font.pixelSize: 20
                                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle { radius: 12; color: parent.hovered ? ThemePalette.Theme.surfaceRaised : ThemePalette.Theme.surface }
                                onClicked: panel.close()
                            }
                        }
                        RowLayout {
                            width: parent.width; height: 108
                            spacing: 10
                            QuickToggle {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                title: "Wi-Fi"
                                status: panel.wifiStatus
                                iconName: Networking.wifiEnabled ? "wifi" : "wifi_off"
                                active: Networking.wifiEnabled
                                available: panel.wifiDevice !== null && Networking.wifiHardwareEnabled
                                onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
                                onDetailsRequested: panel.showSettings("network")
                            }
                            QuickToggle {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                title: "Bluetooth"
                                status: panel.bluetoothStatus
                                iconName: panel.adapter && panel.adapter.enabled ? "bluetooth" : "bluetooth_disabled"
                                active: panel.adapter !== null && panel.adapter.enabled
                                filled: false
                                available: panel.adapter !== null && !panel.bluetoothBusy && panel.adapter.state !== BluetoothAdapterState.Blocked
                                onToggled: if (panel.adapter) SystemState.BluetoothPower.setEnabled(!panel.adapter.enabled)
                                onDetailsRequested: panel.showSettings("bluetooth")
                            }
                        }
                        QuickToggle {
                            width: parent.width; height: 56
                            compact: true; filled: false; showDetails: false
                            title: "Tailscale"
                            status: tailscale.status
                            iconName: "vpn_lock"
                            active: tailscale.active
                            available: tailscale.reachable && !tailscale.busy
                            error: !!tailscale.error
                            onToggled: tailscale.toggle()
                        }
                        QuickSlider {
                            id: brightnessControl
                            width: parent.width; height: 78
                            title: "Display"
                            subtitle: panel.brightnessError || (panel.brightnessAvailable ? "Brightness" : "No controllable display")
                            iconName: "brightness_6"
                            minimum: 1
                            percent: panel.brightnessPercent
                            available: panel.brightnessAvailable
                            onValueRequested: percentage => panel.requestBrightness(percentage)
                            onInteractionFinished: panel.flushBrightness()
                        }
                        QuickSlider {
                            id: volumeControl
                            width: parent.width; height: 78
                            title: "Sound"
                            subtitle: !panel.audio ? "No output device" : panel.audio.muted ? "Muted" : panel.sink.nickname || panel.sink.description || "Current output device"
                            iconName: !panel.audio || panel.audio.muted || panel.audio.volume === 0 ? "volume_off" : panel.audio.volume < 0.5 ? "volume_down" : "volume_up"
                            percent: panel.audio ? panel.audio.volume * 100 : 0
                            available: panel.audio !== null
                            muted: panel.audio !== null && panel.audio.muted
                            iconClickable: true
                            onValueRequested: percentage => {
                                if (panel.audio) {
                                    panel.audio.volume = percentage / 100;
                                    if (percentage > 0) panel.audio.muted = false;
                                }
                            }
                            onIconClicked: if (panel.audio) panel.audio.muted = !panel.audio.muted
                        }
                        RowLayout {
                            width: parent.width; height: 54
                            spacing: 10
                            QuickToggle {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                compact: true; filled: false; showDetails: false
                                title: "Microphone"
                                status: panel.sourceAudio ? panel.sourceAudio.muted ? "Muted" : "Ready" : "No input device"
                                iconName: panel.sourceAudio && !panel.sourceAudio.muted ? "mic" : "mic_off"
                                active: panel.sourceAudio !== null && !panel.sourceAudio.muted
                                available: panel.sourceAudio !== null
                                onToggled: if (panel.sourceAudio) panel.sourceAudio.muted = !panel.sourceAudio.muted
                            }
                            QuickToggle {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                compact: true; filled: false; showDetails: false
                                title: "Do not disturb"
                                status: panel.dndEnabled ? "Pop-ups paused" : "Notifications on"
                                iconName: panel.dndEnabled ? "do_not_disturb_on" : "notifications"
                                active: panel.dndEnabled
                                available: panel.dndAvailable && !panel.dndBusy
                                error: !!panel.dndError
                                onToggled: panel.toggleDnd()
                            }
                        }
                        RowLayout {
                            width: parent.width; height: 30
                            ToolButton {
                                Layout.preferredHeight: 30
                                leftPadding: 4; rightPadding: 8
                                Accessible.name: "Open all settings"
                                contentItem: Row {
                                    spacing: 7
                                    Text { text: "settings"; color: ThemePalette.Theme.muted; font.family: "Material Symbols Rounded"; font.pixelSize: 17 }
                                    Text { text: "All settings"; color: ThemePalette.Theme.text; font.family: "Inter"; font.pixelSize: 11; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
                                    Text { text: "arrow_outward"; color: ThemePalette.Theme.mutedStrong; font.family: "Material Symbols Rounded"; font.pixelSize: 15 }
                                }
                                background: Rectangle { radius: 10; color: parent.hovered ? ThemePalette.Theme.surface : "transparent" }
                                onClicked: panel.showSettings("overview")
                            }
                            Item { Layout.fillWidth: true }
                            BatteryIndicator {
                                level: panel.batteryLevel
                                charging: panel.batteryCharging
                                showPercentage: true
                                Layout.preferredWidth: 72; Layout.preferredHeight: 18
                            }
                        }
                    }
                }
            }
        }
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
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
            transform: NotchContentStretch {
                transition: menuTransition
                canvasWidth: 236
                compact: true
            }
        }
        // Meet the display edge without a horizontal border.
        Rectangle {
            visible: !menuTransition.dropdown
            x: 0; y: 0
            width: parent.width
            height: parent.border.width
            color: parent.color
            z: 100
        }
    }
}

