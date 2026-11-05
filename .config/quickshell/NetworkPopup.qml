import QtQuick
import "Theme" as ThemePalette
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking

Item {
    id: popup
    property var settingsController: null

    property var wifiDevice: null
    property var selectedNetwork: null
    property bool passwordDialogOpen: false
    property bool connecting: false
    property string connectionError: ""
    property bool showPassword: false
    property bool scanPending: false

    function open() {
        findWifiDevice();
        visible = true;
        openAnimation.restart();
    }

    function close() {
        if (settingsController) settingsController.close();
        else closeAnimation.restart();
    }

    function toggle() {
        if (visible)
            close();
        else
            open();
    }

    function refreshNetworks() {
        if (!wifiDevice || !Networking.wifiEnabled || scanPending)
            return;
        scanPending = true;
        wifiDevice.scannerEnabled = false;
        scanTimer.restart();
    }

    function findWifiDevice() {
        wifiDevice = null;
        for (let i = 0; i < Networking.devices.values.length; ++i) {
            let device = Networking.devices.values[i];
            if (device.type === DeviceType.Wifi) {
                wifiDevice = device;
                break;
            }
        }
        if (wifiDevice)
            wifiDevice.scannerEnabled = true;

    }


    Rectangle {
        id: surface

        anchors.fill: parent
        radius: 0
        color: "transparent"
        border.width: 0
        border.color: "transparent"
        scale: 0.92
        opacity: 0

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 0
            spacing: 18

            // HEADER
                SettingsPageHeader {
        title: "Internet"
        subtitle: Networking.wifiEnabled ? "Manage Wi-Fi networks and connections" : "Wi-Fi is turned off"
        iconName: "wifi"
        accentColor: ThemePalette.Theme.accent

        Rectangle {
            Layout.preferredWidth: 42
            Layout.preferredHeight: 42
            radius: 14
            color: refreshHover.containsMouse ? ThemePalette.Theme.surfaceRaised : ThemePalette.Theme.surfaceAlt
            Text {
                anchors.centerIn: parent
                text: scanPending ? "sync" : "refresh"
                color: wifiDevice && Networking.wifiEnabled ? ThemePalette.Theme.accent : ThemePalette.Theme.mutedStrong
                font.family: "Material Symbols Rounded"
                font.pixelSize: 20
            }
            MouseArea {
                id: refreshHover
                anchors.fill: parent
                hoverEnabled: true
                enabled: Networking.wifiEnabled && wifiDevice !== null
                cursorShape: Qt.PointingHandCursor
                onClicked: popup.refreshNetworks()
            }
        }
    }

            // WIFI TOGGLE
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 78
                radius: 22
                color: ThemePalette.Theme.surfaceAlt
                border.width: 1
                border.color: ThemePalette.Theme.border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 14
                    spacing: 14

                    Rectangle {
                        Layout.preferredWidth: 46
                        Layout.preferredHeight: 46
                        radius: 23
                        color: Networking.wifiEnabled ? ThemePalette.Theme.accent : ThemePalette.Theme.border

                        Text {
                            anchors.centerIn: parent
                            text: Networking.wifiEnabled ? "wifi" : "wifi_off"
                            color: Networking.wifiEnabled ? ThemePalette.Theme.onAccent : ThemePalette.Theme.muted
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 25
                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: 180
                            }

                        }

                    }

                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true

                        Text {
                            text: "Wi-Fi"
                            color: ThemePalette.Theme.text
                            font.family: "Inter"
                            font.pixelSize: 17
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 32
                        radius: 16
                        color: Networking.wifiEnabled ? ThemePalette.Theme.accent : ThemePalette.Theme.mutedStrong

                        Rectangle {
                            width: 24
                            height: 24
                            radius: 12
                            anchors.verticalCenter: parent.verticalCenter
                            x: Networking.wifiEnabled ? parent.width - width - 4 : 4
                            color: Networking.wifiEnabled ? ThemePalette.Theme.onAccent : ThemePalette.Theme.text

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    Networking.wifiEnabled = !Networking.wifiEnabled;
                                }
                            }

                            Behavior on x {
                                NumberAnimation {
                                    duration: 220
                                    easing.type: Easing.OutCubic
                                }

                            }

                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Networking.wifiEnabled = !Networking.wifiEnabled;
                            }
                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: 180
                            }

                        }

                    }

                }

                Behavior on color {
                    ColorAnimation {
                        duration: 180
                    }

                }

            }

            // CURRENT NETWORK
            Text {
                text: "CURRENT NETWORK"
                color: ThemePalette.Theme.muted
                font.family: "Inter"
                font.pixelSize: 9
                font.weight: Font.Bold
                font.letterSpacing: 1
                Layout.topMargin: 2
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                radius: 20
                color: ThemePalette.Theme.surfaceAlt
                border.width: 1
                border.color: ThemePalette.Theme.border
                visible: Networking.wifiEnabled && wifiDevice !== null && wifiDevice.connected

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    spacing: 14

                    Text {
                        text: "wifi"
                        color: ThemePalette.Theme.accent
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 25
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: {
                                if (!wifiDevice)
                                    return "Not connected";

                                for (let i = 0; i < wifiDevice.networks.values.length; ++i) {
                                    let n = wifiDevice.networks.values[i];
                                    if (n.connected)
                                        return n.name;

                                }
                                return "Not connected";
                            }
                            color: ThemePalette.Theme.textBright
                            font.family: "Inter"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            text: "Connected"
                            color: ThemePalette.Theme.green
                            font.family: "Inter"
                            font.pixelSize: 10
                        }

                    }

                    Text {
                        text: "check"
                        color: ThemePalette.Theme.accent
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 23
                    }

                }

            }

            // AVAILABLE
            Text {
                text: "AVAILABLE NETWORKS"
                color: ThemePalette.Theme.muted
                font.family: "Inter"
                font.pixelSize: 9
                font.weight: Font.Bold
                font.letterSpacing: 1
                Layout.topMargin: 4
            }

            ListView {
                id: networkList

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 5
                model: wifiDevice ? wifiDevice.networks : null

                delegate: Rectangle {
                    required property var modelData

                    width: networkList.width
                    height: 56
                    radius: 15
                    color: modelData.connected ? ThemePalette.Theme.surfaceRaised : ThemePalette.Theme.surfaceAlt
                    border.width: 1
                    border.color: modelData.connected ? ThemePalette.Theme.accentDark : ThemePalette.Theme.border

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 14
                        spacing: 12

                        Text {
                            text: modelData.connected ? "wifi" : "wifi"
                            color: modelData.connected ? ThemePalette.Theme.accent : ThemePalette.Theme.muted
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 22
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                text: modelData.name
                                color: ThemePalette.Theme.text
                                font.family: "Inter"
                                font.pixelSize: 14
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                text: modelData.known ? "Saved network" : "Available"
                                color: ThemePalette.Theme.muted
                                font.family: "Inter"
                                font.pixelSize: 11
                            }

                        }

                        Text {
                            text: modelData.connected ? "check" : "chevron_right"
                            color: modelData.connected ? ThemePalette.Theme.green : ThemePalette.Theme.muted
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 20
                        }

                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (modelData.connected)
                                return ;

                            selectedNetwork = modelData;
                            connectionError = "";
                            if (modelData.known) {
                                connecting = true;
                                modelData.connect();
                                connectTimer.restart();
                            } else {
                                passwordDialogOpen = true;
                                passwordField.text = "";
                                passwordField.forceActiveFocus();
                            }
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }

                    }

                }

            }

        }

    }

    Rectangle {
        id: passwordOverlay

        anchors.fill: parent
        visible: passwordDialogOpen
        color: "#99000000"
        z: 100

        Rectangle {
            id: passwordDialog

            width: parent.width - 32
            height: 270
            anchors.centerIn: parent
            radius: 28
            color: ThemePalette.Theme.surfaceAlt
            border.width: 1
            border.color: ThemePalette.Theme.surfaceRaised
            scale: passwordDialogOpen ? 1 : 0.92
            opacity: passwordDialogOpen ? 1 : 0

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 14

                // TITLE
                Text {
                    text: "Connect to Wi-Fi"
                    color: ThemePalette.Theme.text
                    font.family: "Inter"
                    font.pixelSize: 22
                    font.weight: Font.Medium
                }

                // NETWORK NAME
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        text: "wifi"
                        color: ThemePalette.Theme.accent
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 24
                    }

                    Text {
                        text: selectedNetwork ? selectedNetwork.name : ""
                        color: ThemePalette.Theme.muted
                        font.family: "Inter"
                        font.pixelSize: 14
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                }

                // PASSWORD
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 58
                    radius: 17
                    color: ThemePalette.Theme.surfaceRaised
                    border.width: passwordField.activeFocus ? 2 : 1
                    border.color: passwordField.activeFocus ? ThemePalette.Theme.accent : ThemePalette.Theme.border

                    TextInput {
                        id: passwordField

                        anchors.left: parent.left
                        anchors.leftMargin: 17
                        anchors.right: showPasswordButton.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        color: ThemePalette.Theme.text
                        font.family: "Inter"
                        font.pixelSize: 15
                        echoMode: showPassword ? TextInput.Normal : TextInput.Password
                        clip: true
                        selectByMouse: true
                        onAccepted: connectButton.clicked()
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 17
                        anchors.verticalCenter: parent.verticalCenter
                        visible: passwordField.text.length === 0 && !passwordField.activeFocus
                        text: "Password"
                        color: ThemePalette.Theme.muted
                        font.family: "Inter"
                        font.pixelSize: 14
                    }

                    MouseArea {
                        id: showPasswordButton

                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 38
                        height: 38
                        cursorShape: Qt.PointingHandCursor
                        onClicked: showPassword = !showPassword

                        Text {
                            anchors.centerIn: parent
                            text: showPassword ? "visibility_off" : "visibility"
                            color: ThemePalette.Theme.muted
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 21
                        }

                    }

                    Behavior on border.color {
                        ColorAnimation {
                            duration: 150
                        }

                    }

                }

                // ERROR
                Text {
                    visible: connectionError.length > 0
                    text: connectionError
                    color: ThemePalette.Theme.red
                    font.family: "Inter"
                    font.pixelSize: 12
                    Layout.fillWidth: true
                }

                Item {
                    Layout.fillHeight: true
                }

                // BUTTONS
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Item {
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        Layout.preferredWidth: 90
                        Layout.preferredHeight: 44
                        radius: 22
                        color: "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: ThemePalette.Theme.muted
                            font.family: "Inter"
                            font.pixelSize: 14
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                passwordDialogOpen = false;
                                connectionError = "";
                            }
                        }

                    }

                    Rectangle {
                        id: connectButton

                        Layout.preferredWidth: 105
                        Layout.preferredHeight: 44
                        radius: 22
                        color: passwordField.text.length > 0 ? ThemePalette.Theme.accent : ThemePalette.Theme.border

                        Text {
                            anchors.centerIn: parent
                            text: connecting ? "Connecting…" : "Connect"
                            color: passwordField.text.length > 0 ? ThemePalette.Theme.onAccent : ThemePalette.Theme.muted
                            font.family: "Inter"
                            font.pixelSize: 14
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!selectedNetwork || passwordField.text.length === 0 || connecting)
                                    return ;

                                connecting = true;
                                connectionError = "";
                                selectedNetwork.connectWithPsk(passwordField.text);
                                connectTimer.restart();
                                passwordDialogOpen = false;
                            }
                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: 150
                            }

                        }

                    }

                }

            }

            Behavior on scale {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.OutCubic
                }

            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 160
                }

            }

        }

    }

    Timer {
        id: scanTimer
        interval: 250
        repeat: false
        onTriggered: {
            if (wifiDevice && Networking.wifiEnabled)
                wifiDevice.scannerEnabled = true;
            scanPending = false;
        }
    }

    Timer {
        id: connectTimer

        interval: 500
        repeat: true
        onTriggered: {
            if (!selectedNetwork)
                return ;

            if (selectedNetwork.connected) {
                connecting = false;
                restart();
                return ;
            }
            if (!selectedNetwork.stateChanging) {
                connecting = false;
                connectionError = "Connection failed";
                stop();
            }
        }
    }

    ParallelAnimation {
        id: openAnimation

        NumberAnimation {
            target: surface
            property: "scale"
            from: 0.92
            to: 1
            duration: 260
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: surface
            property: "opacity"
            from: 0
            to: 1
            duration: 180
            easing.type: Easing.OutCubic
        }

    }

    ParallelAnimation {
        id: closeAnimation

        onFinished: popup.visible = false

        NumberAnimation {
            target: surface
            property: "scale"
            from: 1
            to: 0.94
            duration: 180
            easing.type: Easing.InCubic
        }

        NumberAnimation {
            target: surface
            property: "opacity"
            from: 1
            to: 0
            duration: 130
        }

    }

}
