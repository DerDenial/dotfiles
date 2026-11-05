import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import "../Theme" as ThemeApi
import "../SystemState" as SystemState

SPage {
    id: page

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool powered: !!adapter && adapter.enabled
    readonly property bool blocked: !!adapter && adapter.state === BluetoothAdapterState.Blocked
    readonly property bool powerChanging: !!adapter && (adapter.state === BluetoothAdapterState.Enabling || adapter.state === BluetoothAdapterState.Disabling)
    readonly property var savedDevices: adapter ? adapter.devices.values.filter(device => device.paired || device.bonded || device.connected).sort((a, b) => Number(b.connected) - Number(a.connected) || a.name.localeCompare(b.name)) : []
    readonly property var nearbyDevices: adapter ? adapter.devices.values.filter(device => !device.paired && !device.bonded && !device.connected).sort((a, b) => a.name.localeCompare(b.name)) : []
    readonly property bool busy: deviceAction.running
    property string expandedAddress: ""
    property string operation: ""
    property string operationAddress: ""
    property string operationName: ""
    property var operationDevice: null
    property bool cancelled: false
    property string notice: ""
    property bool noticeWarning: false
    property bool ownsDiscovery: false
    property bool ownsVisibility: false

    function inform(message, warning) { notice = message; noticeWarning = !!warning; }
    function deviceIcon(device) {
        var icon = device.icon || "";
        if (icon.indexOf("headset") >= 0 || icon.indexOf("headphone") >= 0) return "headphones";
        if (icon.indexOf("audio") >= 0) return "speaker";
        if (icon.indexOf("phone") >= 0) return "smartphone";
        if (icon.indexOf("mouse") >= 0) return "mouse";
        if (icon.indexOf("keyboard") >= 0 || icon.indexOf("input") >= 0) return "keyboard";
        if (icon.indexOf("computer") >= 0) return "computer";
        if (icon.indexOf("gaming") >= 0) return "sports_esports";
        return "bluetooth";
    }
    function deviceStatus(device) {
        if (busy && operationAddress === device.address) {
            if (operation === "pair") return "Pairing… Keep your device in pairing mode";
            if (operation === "connect") return "Connecting…";
            if (operation === "disconnect") return "Disconnecting…";
            if (operation === "remove") return "Removing saved device…";
        }
        var result = device.connected ? "Connected" : device.paired || device.bonded ? "Saved" : "Nearby · ready to pair";
        if (device.batteryAvailable) result += " · " + Math.round(device.battery * 100) + "% battery";
        if (device.blocked) result += " · Blocked";
        return result;
    }
    function runAction(kind, device) {
        if (!powered || busy || !device) return;
        operation = kind;
        operationDevice = device;
        operationAddress = device.address;
        operationName = device.name || device.address;
        cancelled = false;
        notice = "";
        deviceAction.command = kind === "pair" ? ["bluetoothctl", "--timeout", "35", "--agent", "NoInputNoOutput", "pair", device.address] : ["bluetoothctl", "--timeout", "20", kind, device.address];
        deviceAction.running = true;
    }
    function forget(device) {
        if (!device || busy) return;
        var target = device;
        controller.confirm("Forget " + (device.name || device.address) + "?", "The pairing keys will be removed. You will need to pair this device again before reconnecting.", function() { if (target) page.runAction("remove", target); });
    }
    function cancelPairing() {
        if (operation !== "pair" || !busy) return;
        cancelled = true;
        if (operationDevice) operationDevice.cancelPair();
        deviceAction.running = false;
        inform("Pairing cancelled.", false);
    }
    function startScan() {
        if (!adapter || !powered || blocked) return;
        notice = "";
        ownsDiscovery = true;
        adapter.discovering = true;
        scanDeadline.restart();
        scanCheck.restart();
    }
    function stopScan() {
        scanDeadline.stop();
        scanCheck.stop();
        if (ownsDiscovery && adapter) adapter.discovering = false;
        ownsDiscovery = false;
    }
    function makeVisible(enabled) {
        if (!adapter || !powered) return;
        if (enabled) {
            adapter.discoverableTimeout = 120;
            adapter.pairableTimeout = 120;
            adapter.pairable = true;
            adapter.discoverable = true;
            ownsVisibility = true;
            visibilityDeadline.restart();
        } else {
            adapter.discoverable = false;
            ownsVisibility = false;
            visibilityDeadline.stop();
        }
    }
    function cleanup() {
        stopScan();
        if (ownsVisibility && adapter) adapter.discoverable = false;
        ownsVisibility = false;
        visibilityDeadline.stop();
    }
    onActiveChanged: { if (!active) cleanup(); }
    onPoweredChanged: if (!powered) cleanup()
    Component.onDestruction: cleanup()

    property Timer scanDeadline: Timer { interval: 25000; onTriggered: page.stopScan() }
    property Timer scanCheck: Timer {
        interval: 1800
        onTriggered: if (page.ownsDiscovery && page.adapter && !page.adapter.discovering) {
            page.inform("The Bluetooth adapter could not start discovery. Check airplane mode and try again.", true);
            page.stopScan();
        }
    }
    property Timer visibilityDeadline: Timer { interval: 120000; onTriggered: page.makeVisible(false) }
    property Process deviceAction: Process {
        environment: ({ LC_ALL: "C", TERM: "dumb" })
        stdout: StdioCollector { id: actionOutput }
        stderr: StdioCollector { id: actionError }
        onExited: function(code) {
            if (page.cancelled) return;
            var result = (actionError.text + "\n" + actionOutput.text).replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").trim();
            var device = page.operationDevice;
            var confirmed = page.operation === "pair" ? (!!device && device.paired || /Pairing successful/i.test(result))
                : page.operation === "connect" ? (!!device && device.connected || /Connection successful/i.test(result))
                : page.operation === "disconnect" ? (!device || !device.connected || /Successful disconnected|Disconnection successful/i.test(result))
                : page.operation === "remove" ? (!device || /Device has been removed/i.test(result))
                : page.operation === "trust" ? (!!device && device.trusted || /trust succeeded/i.test(result))
                : page.operation === "untrust" ? (!!device && !device.trusted || /trust succeeded/i.test(result))
                : page.operation === "block" ? (!!device && device.blocked || /block succeeded/i.test(result))
                : page.operation === "unblock" ? (!!device && !device.blocked || /block succeeded/i.test(result)) : false;
            var failed = code !== 0 || !confirmed || /Failed|not available|No default controller|org\.bluez\.Error|AuthenticationCanceled|AuthenticationFailed|AuthenticationRejected|NotReady|Timeout/i.test(result);
            if (failed) {
                var lines = result.split("\n").filter(line => /Failed|Error|not available|No default|Authentication|Timeout/i.test(line));
                var reason = lines.length ? lines[lines.length - 1].trim() : code === 124 ? "The device did not respond in time." : "The Bluetooth operation did not complete.";
                if (page.operation === "pair" && /Authentication|Rejected|Canceled|Timeout|Failed to pair/i.test(result))
                    reason += " Put the device in pairing mode and retry. Devices that require a PIN or confirmation code need a Bluetooth pairing agent.";
                page.inform(reason, true);
                return;
            }
            if (page.operation === "pair") {
                var paired = page.operationDevice;
                page.inform("Paired with " + page.operationName + ". Connecting…", false);
                Qt.callLater(function() { if (paired && page.powered) page.runAction("connect", paired); });
            } else if (page.operation === "connect") page.inform("Connected to " + page.operationName + ".", false);
            else if (page.operation === "disconnect") page.inform(page.operationName + " disconnected.", false);
            else if (page.operation === "remove") { page.expandedAddress = ""; page.inform("Saved Bluetooth device removed.", false); }
            else if (page.operation === "trust") page.inform(page.operationName + " is now trusted for automatic connections.", false);
            else if (page.operation === "untrust") page.inform("Automatic trust removed for " + page.operationName + ".", false);
            else if (page.operation === "block") page.inform(page.operationName + " blocked.", false);
            else if (page.operation === "unblock") page.inform(page.operationName + " unblocked.", false);
        }
    }

    SNotice { Layout.fillWidth: true; text: !page.adapter ? "No Bluetooth adapter detected. Check that Bluetooth is available and the bluetooth service is running." : page.blocked ? "Bluetooth is blocked by a hardware switch or airplane mode." : ""; warning: true }
    SNotice { Layout.fillWidth: true; text: page.notice; warning: page.noticeWarning }

    SCard {
        Layout.fillWidth: true
        title: "Bluetooth"
        iconName: "bluetooth"
        SRow {
            Layout.fillWidth: true
            title: page.powerChanging ? (page.powered ? "Turning off…" : "Turning on…") : page.powered ? "Bluetooth is on" : "Bluetooth is off"
            subtitle: "Your choice is saved and restored after a restart"
            iconName: page.powered ? "bluetooth_connected" : "bluetooth_disabled"
            SToggle {
                checked: page.powered
                enabled: !!page.adapter && !page.blocked && !page.powerChanging && !page.busy
                onToggled: { if (!checked) page.cleanup(); SystemState.BluetoothPower.setEnabled(checked); }
            }
        }
        SRow {
            Layout.fillWidth: true
            visible: !!page.adapter
            title: page.adapter ? page.adapter.name : "Adapter"
            subtitle: page.adapter ? page.adapter.adapterId : ""
            iconName: "computer"
            value: page.blocked ? "Blocked" : page.powered ? "Ready" : "Off"
        }
    }

    SCard {
        Layout.fillWidth: true
        visible: page.powered
        title: "Discovery"
        iconName: "radar"
        SRow {
            Layout.fillWidth: true
            title: page.adapter && page.adapter.discovering ? "Looking for devices…" : "Nearby devices"
            subtitle: "Put headphones, speakers or other accessories into pairing mode. Scanning stops automatically after 25 seconds."
            iconName: "search"
            SButton {
                text: page.ownsDiscovery ? "Stop scan" : "Scan"
                iconName: page.ownsDiscovery ? "stop" : "refresh"
                enabled: !page.busy
                accent: !page.ownsDiscovery
                onClicked: page.ownsDiscovery ? page.stopScan() : page.startScan()
            }
        }
        SRow {
            Layout.fillWidth: true
            title: "Visible to other devices"
            subtitle: "Make this computer discoverable for two minutes. Visibility ends when you leave this page."
            iconName: "visibility"
            SToggle { checked: !!page.adapter && page.adapter.discoverable; enabled: !page.busy; onToggled: page.makeVisible(checked) }
        }
    }

    SCard {
        Layout.fillWidth: true
        visible: page.powered
        title: "Your devices"
        subtitle: page.savedDevices.length ? "Saved accessories and active connections" : "No devices paired yet. Scan and pair an accessory below."
        iconName: "devices"
        Repeater {
            model: page.savedDevices
            delegate: ColumnLayout {
                id: savedDelegate
                required property var modelData
                Layout.fillWidth: true
                spacing: 4
                SRow {
                    Layout.fillWidth: true
                    title: savedDelegate.modelData.name || savedDelegate.modelData.address
                    subtitle: page.deviceStatus(savedDelegate.modelData)
                    iconName: page.deviceIcon(savedDelegate.modelData)
                    SButton {
                        text: savedDelegate.modelData.connected ? "Disconnect" : "Connect"
                        accent: !savedDelegate.modelData.connected
                        enabled: !page.busy && !savedDelegate.modelData.blocked
                        onClicked: page.runAction(savedDelegate.modelData.connected ? "disconnect" : "connect", savedDelegate.modelData)
                    }
                    SButton { text: page.expandedAddress === savedDelegate.modelData.address ? "Less" : "Details"; onClicked: page.expandedAddress = page.expandedAddress === savedDelegate.modelData.address ? "" : savedDelegate.modelData.address }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 44
                    visible: page.expandedAddress === savedDelegate.modelData.address
                    spacing: 2
                    SRow { Layout.fillWidth: true; title: "Device address"; value: savedDelegate.modelData.address }
                    SRow {
                        Layout.fillWidth: true
                        title: "Trusted device"
                        subtitle: "Allow this accessory to reconnect without asking"
                        SToggle { checked: savedDelegate.modelData.trusted; enabled: !page.busy; onToggled: page.runAction(checked ? "trust" : "untrust", savedDelegate.modelData) }
                    }
                    SRow {
                        Layout.fillWidth: true
                        title: "Block connections"
                        subtitle: "Prevent this device from connecting to the computer"
                        SToggle { checked: savedDelegate.modelData.blocked; enabled: !page.busy; onToggled: page.runAction(checked ? "block" : "unblock", savedDelegate.modelData) }
                    }
                    SRow {
                        Layout.fillWidth: true
                        title: "Remove saved device"
                        subtitle: "Delete pairing keys and require a new pairing"
                        SButton { text: "Forget"; iconName: "delete"; destructive: true; enabled: !page.busy; onClicked: page.forget(savedDelegate.modelData) }
                    }
                }
            }
        }
    }

    SCard {
        Layout.fillWidth: true
        visible: page.powered
        title: "Nearby devices"
        subtitle: page.nearbyDevices.length ? "Select Pair to save and connect an accessory" : page.ownsDiscovery ? "Searching… Make sure the accessory is in pairing mode." : "Start a scan to find new devices."
        iconName: "bluetooth_searching"
        Repeater {
            model: page.nearbyDevices
            delegate: SRow {
                required property var modelData
                Layout.fillWidth: true
                title: modelData.name || modelData.address
                subtitle: page.deviceStatus(modelData)
                iconName: page.deviceIcon(modelData)
                SButton {
                    text: page.busy && page.operationAddress === modelData.address && page.operation === "pair" ? "Cancel" : "Pair"
                    iconName: "add_link"
                    enabled: !page.busy || page.operationAddress === modelData.address && page.operation === "pair"
                    accent: true
                    onClicked: page.busy ? page.cancelPairing() : page.runAction("pair", modelData)
                }
            }
        }
        SLabel { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Pairing here supports accessories without a PIN prompt, including most headphones and speakers. PIN and confirmation-code devices require a separate Bluetooth pairing agent."; color: ThemeApi.Theme.muted; font.pixelSize: 12 }
    }

    SCard {
        Layout.fillWidth: true
        visible: page.powered && page.savedDevices.some(device => device.connected)
        title: "Connected audio"
        iconName: "headphones"
        SRow {
            Layout.fillWidth: true
            title: "Choose your playback device"
            subtitle: "Manage Bluetooth audio, speakers and microphones in Sound"
            iconName: "volume_up"
            SButton { text: "Sound"; iconName: "arrow_forward"; onClicked: page.controller.navigate("audio") }
        }
    }
}
