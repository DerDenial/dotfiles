import QtQuick
import "SystemState" as SystemState
import "Theme" as ThemePalette
import QtQuick.Layouts
import Quickshell

Item {
    id: popup
    property var settingsController: null
    property bool powered: powerPoll.value.trim() === "yes"
    property var devices: devicePoll.value.split("\n").filter(line => line.trim().length > 0).map(line => {
        const p = line.split("|");
        return { address: p[0] || "", name: p[1] || "Bluetooth device", connected: p[2] === "yes", paired: p[3] === "yes" };
    })

    function open() {
        visible = true;
        openAnimation.restart();
        if (powered)
            startScan();
    }
    function close() { if (settingsController) settingsController.close(); else closeAnimation.restart(); }
    function toggle() {
        if (visible) close();
        else open();
    }
    function togglePower() {
        SystemState.BluetoothPower.setEnabled(!powered);
        if (powered) stopScan();
    }
    function startScan() {
        if (!powered) return;
        Quickshell.execDetached(["bluetoothctl", "scan", "on"]);
        scanTimer.restart();
    }
    function stopScan() {
        if (scanTimer.running)
            Quickshell.execDetached(["bluetoothctl", "scan", "off"]);
        scanTimer.stop();
    }
    function activateDevice(device) {
        if (!powered) return;
        const action = device.connected ? "disconnect" : (device.paired ? "connect" : "pair");
        Quickshell.execDetached(["bluetoothctl", action, device.address]);
    }

    onVisibleChanged: if (!visible) stopScan()
    Component.onDestruction: stopScan()


    Poller {
        id: powerPoll
        interval: 2500
        command: "bluetoothctl show 2>/dev/null | awk '/Powered:/ {print tolower($2); exit}'"
    }
    Poller {
        id: devicePoll
        interval: 2500
        command: "bluetoothctl devices 2>/dev/null | while read -r _ address name; do [ -n \"$address\" ] || continue; info=$(bluetoothctl info \"$address\" 2>/dev/null); connected=$(printf '%s\\n' \"$info\" | awk '/Connected:/ {print tolower($2); exit}'); paired=$(printf '%s\\n' \"$info\" | awk '/Paired:/ {print tolower($2); exit}'); [ -n \"$name\" ] || name='Unknown device'; [ -n \"$connected\" ] || connected=no; [ -n \"$paired\" ] || paired=no; printf '%s|%s|%s|%s\\n' \"$address\" \"$name\" \"$connected\" \"$paired\"; done"
    }
    Timer {
        id: scanTimer
        interval: 10000
        repeat: false
        onTriggered: Quickshell.execDetached(["bluetoothctl", "scan", "off"])
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

                SettingsPageHeader {
        title: "Bluetooth"
        subtitle: powered ? "Connect and manage nearby devices" : "Bluetooth is turned off"
        iconName: powered ? "bluetooth_connected" : "bluetooth_disabled"
        accentColor: powered ? ThemePalette.Theme.accent : ThemePalette.Theme.muted
    }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 78
                radius: 22
                color: ThemePalette.Theme.surfaceAlt
                border.width: 1
                border.color: ThemePalette.Theme.border
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 14
                    spacing: 12
                    Rectangle {
                        Layout.preferredWidth: 42
                        Layout.preferredHeight: 42
                        radius: 21
                        color: ThemePalette.Theme.surfaceRaised
                        Text {
                            anchors.centerIn: parent
                            text: powered ? "bluetooth" : "bluetooth_disabled"
                            color: powered ? ThemePalette.Theme.accent : ThemePalette.Theme.muted
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 23
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            text: "Bluetooth adapter"
                            color: ThemePalette.Theme.text
                            font.family: "Inter"
                            font.pixelSize: 15
                        }
                        Text {
                            text: powered ? "Ready to connect" : "Turn on to find devices"
                            color: ThemePalette.Theme.muted
                            font.family: "Inter"
                            font.pixelSize: 11
                        }
                    }
                    Rectangle {
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 32
                        radius: 16
                        color: powered ? ThemePalette.Theme.accent : ThemePalette.Theme.border
                        Rectangle {
                            width: 24
                            height: 24
                            radius: 12
                            anchors.verticalCenter: parent.verticalCenter
                            x: powered ? parent.width - width - 4 : 4
                            color: ThemePalette.Theme.surface
                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: popup.togglePower()
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "DEVICES"
                    color: ThemePalette.Theme.muted
                    font.family: "Inter"
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                    Layout.fillWidth: true
                }
                Text {
                    text: scanTimer.running ? "Scanning…" : "Refresh"
                    color: powered ? ThemePalette.Theme.accent : ThemePalette.Theme.mutedStrong
                    font.family: "Inter"
                    font.pixelSize: 12
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: powered
                    cursorShape: Qt.PointingHandCursor
                    onClicked: popup.startScan()
                }
            }

            ListView {
                id: deviceList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 7
                model: popup.devices
                delegate: Rectangle {
                    required property var modelData
                    width: deviceList.width
                    height: 56
                    radius: 15
                    color: modelData.connected ? ThemePalette.Theme.accentSoft : ThemePalette.Theme.surfaceAlt
                    border.width: 1
                    border.color: modelData.connected ? ThemePalette.Theme.accent : ThemePalette.Theme.border
                    opacity: popup.powered ? 1 : 0.5
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 12
                        spacing: 11
                        Text {
                            text: "bluetooth"
                            color: ThemePalette.Theme.accent
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 22
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                text: modelData.name
                                color: ThemePalette.Theme.text
                                font.family: "Inter"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            Text {
                                text: modelData.connected ? "Connected" : (modelData.paired ? "Paired" : "Nearby · tap to pair")
                                color: modelData.connected ? ThemePalette.Theme.green : ThemePalette.Theme.muted
                                font.family: "Inter"
                                font.pixelSize: 11
                            }
                        }
                        Text {
                            text: modelData.connected ? "check" : (modelData.paired ? "link" : "add")
                            color: modelData.connected ? ThemePalette.Theme.green : ThemePalette.Theme.muted
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 21
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: popup.powered
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.activateDevice(modelData)
                    }
                }
            }

            Text {
                visible: !powered
                text: "Turn Bluetooth on to view nearby and paired devices."
                color: ThemePalette.Theme.muted
                font.family: "Inter"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            Text {
                visible: powered && popup.devices.length === 0
                text: scanTimer.running ? "Looking for Bluetooth devices…" : "No devices found. Tap Refresh to scan."
                color: ThemePalette.Theme.muted
                font.family: "Inter"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
    }

    ParallelAnimation {
        id: openAnimation
        NumberAnimation { target: surface; property: "scale"; from: 0.92; to: 1; duration: 260; easing.type: Easing.OutCubic }
        NumberAnimation { target: surface; property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
        id: closeAnimation
        onFinished: popup.visible = false
        NumberAnimation { target: surface; property: "scale"; from: 1; to: 0.94; duration: 180; easing.type: Easing.InCubic }
        NumberAnimation { target: surface; property: "opacity"; from: 1; to: 0; duration: 130 }
    }
}
