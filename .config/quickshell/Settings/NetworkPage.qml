import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "../Theme" as ThemeApi
import "../" as Shell

SPage {
    id: page

    readonly property var wifiDevice: Networking.devices.values.find(device => device.type === DeviceType.Wifi) || null
    readonly property var connectedNetwork: wifiDevice ? wifiDevice.networks.values.find(network => network.connected) || null : null
    readonly property var availableNetworks: wifiDevice ? wifiDevice.networks.values.filter(network => !network.connected && network.name.length > 0).sort((a, b) => Number(b.known) - Number(a.known) || b.signalStrength - a.signalStrength || a.name.localeCompare(b.name)) : []
    readonly property var wiredDevices: Networking.devices.values.filter(device => device.type === DeviceType.Wired)
    readonly property bool supported: Networking.backend !== NetworkBackendType.None
    readonly property bool busy: pendingKind.length > 0 || disconnectAction.running
    property var pendingNetwork: null
    property string pendingKind: ""
    property string pendingName: ""
    property var passwordNetwork: null
    property bool revealPassword: false
    property string notice: ""
    property bool noticeWarning: false
    property var connectionDetails: ({})

    function inform(message, warning) {
        notice = message;
        noticeWarning = !!warning;
    }
    function securityLabel(network) {
        if (!network) return "";
        switch (network.security) {
        case WifiSecurityType.Open: return "Open network";
        case WifiSecurityType.Owe: return "Enhanced open";
        case WifiSecurityType.Sae: return "WPA3 Personal";
        case WifiSecurityType.Wpa2Psk: return "WPA2 Personal";
        case WifiSecurityType.WpaPsk: return "WPA Personal";
        case WifiSecurityType.Wpa3SuiteB192:
        case WifiSecurityType.Wpa2Eap:
        case WifiSecurityType.WpaEap:
        case WifiSecurityType.DynamicWep:
        case WifiSecurityType.Leap: return "Enterprise authentication";
        case WifiSecurityType.StaticWep: return "WEP · legacy security";
        default: return "Secured network";
        }
    }
    function needsEnterprise(network) {
        return [WifiSecurityType.Wpa3SuiteB192, WifiSecurityType.Wpa2Eap, WifiSecurityType.WpaEap, WifiSecurityType.DynamicWep, WifiSecurityType.Leap].indexOf(network.security) >= 0;
    }
    function beginConnection(network, withPassword) {
        if (!network || busy || !Networking.wifiEnabled) return;
        if (!network.known && needsEnterprise(network)) {
            inform("This network needs an identity or a certificate. Create its profile in Advanced connection profiles, then connect here.", true);
            return;
        }
        if (!withPassword && !network.known && network.security !== WifiSecurityType.Open && network.security !== WifiSecurityType.Owe) {
            passwordNetwork = network;
            passwordField.clear();
            revealPassword = false;
            Qt.callLater(function() { passwordField.forceActiveFocus(); });
            return;
        }
        pendingNetwork = network;
        pendingName = network.name;
        pendingKind = "connect";
        inform("Connecting to " + pendingName + "…", false);
        operationTimeout.restart();
        if (withPassword) network.connectWithPsk(passwordField.text);
        else network.connect();
        passwordField.clear();
        passwordNetwork = null;
    }
    function finishOperation(message, warning) {
        operationTimeout.stop();
        pendingKind = "";
        pendingNetwork = null;
        inform(message, warning);
        refreshDetails();
    }
    function forgetNetwork(network) {
        if (!network || busy) return;
        var target = network;
        controller.confirm("Forget " + network.name + "?", "The saved password and connection profile will be removed. You can reconnect later.", function() {
            if (!target) return;
            page.pendingNetwork = target;
            page.pendingName = target.name;
            page.pendingKind = "forget";
            page.inform("Removing saved connection…", false);
            page.operationTimeout.restart();
            target.forget();
        });
    }
    function refreshDetails() {
        if (!active || !wifiDevice || !connectedNetwork || detailsQuery.running) return;
        detailsQuery.networkName = connectedNetwork.name;
        detailsQuery.command = ["nmcli", "--terse", "--escape", "no", "--fields", "GENERAL.CONNECTION,GENERAL.HWADDR,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS", "device", "show", wifiDevice.name];
        detailsQuery.running = true;
    }
    function scan() {
        if (!wifiDevice || !Networking.wifiEnabled || rescan.running) return;
        notice = "";
        rescan.command = ["nmcli", "--wait", "12", "device", "wifi", "rescan", "ifname", wifiDevice.name];
        rescan.running = true;
    }
    function updateScanner() {
        if (wifiDevice) wifiDevice.scannerEnabled = active && Networking.wifiEnabled;
    }
    onActiveChanged: { updateScanner(); if (active) refreshDetails(); }
    onWifiDeviceChanged: updateScanner()
    onPendingNetworkChanged: {
        if (!pendingNetwork && pendingKind === "forget") finishOperation("Saved connection removed.", false);
    }
    onConnectedNetworkChanged: { connectionDetails = ({}); refreshDetails(); }
    Component.onCompleted: { updateScanner(); refreshDetails(); }
    Component.onDestruction: if (wifiDevice) wifiDevice.scannerEnabled = false

    property Connections wifiState: Connections {
        target: Networking
        function onWifiEnabledChanged() {
            page.updateScanner();
            if (!Networking.wifiEnabled) {
                page.passwordNetwork = null;
                passwordField.clear();
            }
        }
    }
    property Connections pendingState: Connections {
        target: page.pendingNetwork
        function onConnectionFailed(reason) {
            var explanation = "Connection failed. Try again or check the connection profile.";
            switch (reason) {
            case ConnectionFailReason.NoSecrets: explanation = "A password or another credential is required. Try entering the password again."; break;
            case ConnectionFailReason.WifiAuthTimeout: explanation = "Authentication timed out. Check the password and try again."; break;
            case ConnectionFailReason.WifiNetworkLost: explanation = "The Wi-Fi network disappeared or is out of range."; break;
            case ConnectionFailReason.WifiClientDisconnected: explanation = "The access point disconnected this device."; break;
            case ConnectionFailReason.WifiClientFailed: explanation = "The Wi-Fi adapter could not establish the connection."; break;
            }
            if (reason === ConnectionFailReason.NoSecrets && page.pendingNetwork && !page.needsEnterprise(page.pendingNetwork)) {
                page.passwordNetwork = page.pendingNetwork;
                passwordField.clear();
                Qt.callLater(function() { passwordField.forceActiveFocus(); });
            }
            page.finishOperation(explanation, true);
        }
        function onConnectedChanged() {
            if (page.pendingKind === "connect" && page.pendingNetwork && page.pendingNetwork.connected)
                page.finishOperation("Connected to " + page.pendingName + ".", false);
        }
        function onKnownChanged() {
            if (page.pendingKind === "forget" && page.pendingNetwork && !page.pendingNetwork.known)
                page.finishOperation("Saved connection removed.", false);
        }
    }
    property Timer operationTimeout: Timer {
        interval: 30000
        onTriggered: page.finishOperation(page.pendingKind === "forget" ? "The profile could not be removed. Check your NetworkManager permissions." : "The connection did not complete. Check the password, signal or authentication settings.", true)
    }
    property Timer detailTimer: Timer { interval: 8000; running: page.active && !!page.connectedNetwork; repeat: true; onTriggered: page.refreshDetails() }
    property Process detailsQuery: Process {
        property string networkName: ""
        environment: ({ LC_ALL: "C" })
        stdout: StdioCollector {
            onStreamFinished: {
                if (!page.connectedNetwork || page.connectedNetwork.name !== page.detailsQuery.networkName) return;
                var result = {};
                text.split("\n").forEach(function(line) {
                    var index = line.indexOf(":");
                    if (index < 0) return;
                    var key = line.slice(0, index).replace(/\[\d+\]$/, "");
                    var value = line.slice(index + 1).trim();
                    if (value && value !== "--") result[key] = result[key] ? result[key] + ", " + value : value;
                });
                page.connectionDetails = result;
            }
        }
    }
    property Process rescan: Process {
        environment: ({ LC_ALL: "C" })
        stderr: StdioCollector { id: scanErrors }
        onExited: function(code) {
            if (code !== 0) page.inform(scanErrors.text.trim() || "NetworkManager could not start a scan. Please wait a moment and try again.", true);
        }
    }
    property Process disconnectAction: Process {
        environment: ({ LC_ALL: "C" })
        stderr: StdioCollector { id: disconnectErrors }
        onExited: function(code) { page.inform(code === 0 ? "Wi-Fi disconnected." : disconnectErrors.text.trim() || "Could not disconnect this adapter.", code !== 0); }
    }
    property Process profileEditor: Process {
        command: ["kitty", "--class", "quickshell-network-editor", "--title", "Connection profiles", "-e", "nmtui", "edit"]
        stderr: StdioCollector { id: editorErrors }
        onExited: function(code) { if (code !== 0) page.inform(editorErrors.text.trim() || "The connection profile editor could not be opened.", true); }
    }
    property Shell.TailscaleState tailscale: Shell.TailscaleState { polling: page.active }

    SNotice { Layout.fillWidth: true; text: !page.supported ? "NetworkManager is unavailable. Start the NetworkManager service to manage connections here." : !Networking.wifiHardwareEnabled ? "Wi-Fi is blocked by a hardware switch or airplane mode." : ""; warning: true }
    SNotice { Layout.fillWidth: true; text: page.notice; warning: page.noticeWarning }

    SCard {
        Layout.fillWidth: true
        title: "Wireless"
        iconName: "wifi"
        SRow {
            Layout.fillWidth: true
            title: "Wi-Fi"
            subtitle: !page.wifiDevice ? "No Wi-Fi adapter detected" : Networking.wifiEnabled ? "Available networks update while this page is open" : "Turn on to discover nearby networks"
            iconName: Networking.wifiEnabled ? "wifi" : "wifi_off"
            SToggle { checked: Networking.wifiEnabled; enabled: page.supported && !!page.wifiDevice && Networking.wifiHardwareEnabled; onToggled: Networking.wifiEnabled = checked }
        }
        SRow {
            Layout.fillWidth: true
            visible: Networking.wifiEnabled && !!page.wifiDevice
            title: page.rescan.running ? "Scanning nearby networks…" : "Nearby networks"
            subtitle: "Connect to a saved network or enter a password for a new one"
            SButton { text: page.rescan.running ? "Scanning…" : "Scan"; iconName: "refresh"; enabled: !page.rescan.running; onClicked: page.scan() }
        }
    }

    SCard {
        Layout.fillWidth: true
        visible: Networking.wifiEnabled && !!page.connectedNetwork
        title: "Connected network"
        iconName: "wifi"
        SRow {
            Layout.fillWidth: true
            title: page.connectedNetwork ? page.connectedNetwork.name : ""
            subtitle: (Networking.connectivity === NetworkConnectivity.Full ? "Internet access" : Networking.connectivity === NetworkConnectivity.Portal ? "Sign-in required by this network" : Networking.connectivity === NetworkConnectivity.Limited ? "Limited internet access" : "Connected") + (page.connectedNetwork ? " · " + Math.round(page.connectedNetwork.signalStrength * 100) + "% signal" : "")
            iconName: "check_circle"
            SButton {
                text: "Disconnect"
                enabled: !page.busy
                onClicked: { page.disconnectAction.command = ["nmcli", "--wait", "15", "device", "disconnect", page.wifiDevice.name]; page.disconnectAction.running = true; }
            }
        }
        SRow { Layout.fillWidth: true; title: "IPv4 address"; value: page.connectionDetails["IP4.ADDRESS"] || "—"; iconName: "lan" }
        SRow { Layout.fillWidth: true; title: "Gateway"; value: page.connectionDetails["IP4.GATEWAY"] || "—"; iconName: "router" }
        SRow { Layout.fillWidth: true; title: "DNS servers"; subtitle: page.connectionDetails["IP4.DNS"] || "Assigned by the network"; iconName: "dns" }
        SRow {
            Layout.fillWidth: true
            title: "Connection profile"
            subtitle: page.securityLabel(page.connectedNetwork) + (page.wifiDevice ? " · " + page.wifiDevice.name + " · " + page.wifiDevice.address : "")
            iconName: "shield"
            SButton { text: "Forget"; destructive: true; enabled: !page.busy && !!page.connectedNetwork && page.connectedNetwork.known; onClicked: page.forgetNetwork(page.connectedNetwork) }
        }
    }

    SCard {
        Layout.fillWidth: true
        visible: Networking.wifiEnabled && !!page.wifiDevice
        title: "Available networks"
        subtitle: page.availableNetworks.length ? page.availableNetworks.length + " networks in range" : "No networks found. Move closer to an access point or scan again."
        iconName: "wifi_find"
        Repeater {
            model: page.availableNetworks
            delegate: SRow {
                required property var modelData
                Layout.fillWidth: true
                title: modelData.name
                subtitle: (modelData.stateChanging ? ConnectionState.toString(modelData.state) : modelData.known ? "Saved" : page.securityLabel(modelData)) + " · " + Math.round(modelData.signalStrength * 100) + "% signal"
                iconName: modelData.security === WifiSecurityType.Open ? "wifi" : "wifi_lock"
                SButton { text: page.pendingKind === "connect" && page.pendingName === modelData.name ? "Connecting…" : "Connect"; accent: modelData.known; enabled: !page.busy; onClicked: page.beginConnection(modelData, false) }
                SButton { text: "Forget"; visible: modelData.known; enabled: !page.busy; onClicked: page.forgetNetwork(modelData) }
            }
        }
    }

    SCard {
        Layout.fillWidth: true
        visible: !!page.passwordNetwork
        title: page.passwordNetwork ? "Connect to " + page.passwordNetwork.name : "Enter password"
        subtitle: "Your password is sent directly to NetworkManager and is never logged."
        iconName: "key"
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            TextField {
                id: passwordField
                Layout.fillWidth: true
                implicitHeight: 46
                font.family: "Inter"
                font.pixelSize: 14
                color: ThemeApi.Theme.text
                placeholderText: "Wi-Fi password"
                placeholderTextColor: ThemeApi.Theme.muted
                selectionColor: ThemeApi.Theme.accent
                selectedTextColor: ThemeApi.Theme.onAccent
                echoMode: page.revealPassword ? TextInput.Normal : TextInput.Password
                background: Rectangle { radius: 12; color: ThemeApi.Theme.bg0; border.width: 1; border.color: passwordField.activeFocus ? ThemeApi.Theme.accent : ThemeApi.Theme.border }
                onAccepted: if (text.length && !page.busy) page.beginConnection(page.passwordNetwork, true)
            }
            SButton { text: page.revealPassword ? "Hide" : "Show"; iconName: page.revealPassword ? "visibility_off" : "visibility"; onClicked: page.revealPassword = !page.revealPassword }
        }
        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: 8
            SButton { text: "Cancel"; onClicked: { page.passwordNetwork = null; passwordField.clear(); } }
            SButton { text: "Connect"; accent: true; enabled: passwordField.text.length > 0 && !page.busy; onClicked: page.beginConnection(page.passwordNetwork, true) }
        }
    }

    SCard {
        Layout.fillWidth: true
        visible: page.wiredDevices.length > 0
        title: "Wired connections"
        iconName: "settings_ethernet"
        Repeater {
            model: page.wiredDevices
            delegate: SRow {
                required property var modelData
                Layout.fillWidth: true
                title: modelData.name
                subtitle: modelData.connected ? "Connected · " + modelData.linkSpeed + " Mb/s" : modelData.hasLink ? "Cable connected" : "Cable unplugged"
                iconName: "settings_ethernet"
            }
        }
    }

    SCard {
        Layout.fillWidth: true
        title: "Private network"
        iconName: "vpn_lock"
        SRow {
            Layout.fillWidth: true
            title: "Tailscale"
            subtitle: page.tailscale.status
            iconName: "hub"
            SToggle { checked: page.tailscale.active; enabled: page.tailscale.reachable && !page.tailscale.busy; onToggled: page.tailscale.toggle() }
        }
        SNotice { Layout.fillWidth: true; text: page.tailscale.error === "Operator permission required" ? "Tailscale needs permission for your user. Run sudo tailscale set --operator=$USER once in a terminal." : ""; warning: true }
    }

    SCard {
        Layout.fillWidth: true
        title: "Advanced"
        iconName: "tune"
        SRow {
            Layout.fillWidth: true
            title: "Connection profiles"
            subtitle: "Edit static IP addresses, DNS, enterprise credentials, hidden networks and automatic connection in NetworkManager’s profile editor."
            iconName: "manage_accounts"
            SButton { text: "Open editor"; iconName: "open_in_new"; enabled: page.supported && !page.profileEditor.running; onClicked: page.profileEditor.running = true }
        }
    }
}
