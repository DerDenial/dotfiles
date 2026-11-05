import QtQuick
import "Theme" as ThemePalette
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    // ---------------------------------------------------------
    // BATTERY STATUS
    // ---------------------------------------------------------
    // ---------------------------------------------------------
    // BATTERY TIME
    // ---------------------------------------------------------
    // ---------------------------------------------------------
    // POWER MODE DETECTION
    // ---------------------------------------------------------
    // ---------------------------------------------------------
    // TLP COMMANDS
    // ---------------------------------------------------------
    // ---------------------------------------------------------
    // AUTO REFRESH
    // ---------------------------------------------------------
    // ---------------------------------------------------------
    // POPUP POSITION
    // ---------------------------------------------------------
    // ---------------------------------------------------------
    // MAIN SURFACE
    // ---------------------------------------------------------
    // ---------------------------------------------------------
    // OPEN ANIMATION
    // ---------------------------------------------------------
    // ---------------------------------------------------------
    // CLOSE ANIMATION
    // ---------------------------------------------------------
    // ---------------------------------------------------------
    // POWER MODE COMPONENT
    // ---------------------------------------------------------

    id: popup
    property var settingsController: null

    property string batteryStatus: "Unknown"
    property string batteryTime: ""
    property string powerMode: "Balanced"
    property bool changingMode: false

    function open() {
        updateBatteryInfo();
        updatePowerMode();
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

    function updateBatteryInfo() {
        batteryStatusProc.running = true;
        batteryTimeProc.running = true;
    }

    function updatePowerMode() {
        powerModeProc.running = true;
    }

    function setPowerMode(mode) {
        changingMode = true;
        if (mode === "Performance")
            performanceProc.running = true;
        else if (mode === "Balanced")
            balancedProc.running = true;
        else if (mode === "Power Saver")
            powerSaverProc.running = true;
        powerMode = mode;
        modeTimer.restart();
    }


    Process {
        id: batteryStatusProc

        command: ["bash", "-c", "cat /sys/class/power_supply/BAT0/status"]

        stdout: SplitParser {
            onRead: (data) => {
                popup.batteryStatus = data.trim();
            }
        }

    }

    Process {
        id: batteryTimeProc

        command: ["bash", "-c", "upower -i /org/freedesktop/UPower/devices/battery_BAT0 | grep -E 'time to (empty|full)' | head -n1"]

        stdout: SplitParser {
            onRead: (data) => {
                let result = data.trim();
                if (result.length === 0) {
                    popup.batteryTime = "";
                    return ;
                }
                let parts = result.split(":");
                if (parts.length < 2) {
                    popup.batteryTime = "";
                    return ;
                }
                popup.batteryTime = parts.slice(1).join(":").trim();
            }
        }

    }

    Process {
        id: powerModeProc

        command: ["bash", "-c", `
        epp=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)
        profile=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null)

        if [ "$epp" = "performance" ] || [ "$profile" = "performance" ]; then
            echo "Performance"
        elif [ "$epp" = "power" ] || [ "$profile" = "low-power" ]; then
            echo "Power Saver"
        else
            echo "Balanced"
        fi
        `]

        stdout: SplitParser {
            onRead: (data) => {
                let result = data.trim();
                if (result === "Performance" || result === "Balanced" || result === "Power Saver")
                    popup.powerMode = result;

            }
        }

    }

    Process {
        id: performanceProc

        command: ["pkexec", "tlp", "performance"]
        onExited: {
            changingMode = false;
            updatePowerMode();
        }
    }

    Process {
        id: balancedProc

        command: ["pkexec", "tlp", "balanced"]
        onExited: {
            changingMode = false;
            updatePowerMode();
        }
    }

    Process {
        id: powerSaverProc

        command: ["pkexec", "tlp", "power-saver"]
        onExited: {
            changingMode = false;
            updatePowerMode();
        }
    }

    Timer {
        id: modeTimer

        interval: 1200
        repeat: false
        onTriggered: {
            updatePowerMode();
            changingMode = false;
        }
    }

    Timer {
        id: refreshTimer

        interval: 5000
        repeat: true
        running: popup.visible
        onTriggered: {
            updateBatteryInfo();
            updatePowerMode();
        }
    }

    Rectangle {
        // -----------------------------------------------------
        // CONTENT
        // -----------------------------------------------------

        id: surface

        anchors.fill: parent
        radius: 0
        color: "transparent"
        border.width: 0
        border.color: "transparent"
        scale: 0.92
        opacity: 0

        ColumnLayout {
            // -------------------------------------------------
            // HEADER
            // -------------------------------------------------
            // -------------------------------------------------
            // BATTERY CARD
            // -------------------------------------------------
            // -------------------------------------------------
            // TIME
            // -------------------------------------------------
            // -------------------------------------------------
            // POWER MODE TITLE
            // -------------------------------------------------
            // -------------------------------------------------
            // POWER MODES
            // -------------------------------------------------
            // -------------------------------------------------
            // FOOTER
            // -------------------------------------------------

            anchors.fill: parent
            anchors.margins: 0
            spacing: 15

                SettingsPageHeader {
        title: "Battery & power"
        subtitle: batteryStatus === "Charging" ? "Charging · power mode controls" : "Battery status and power mode controls"
        iconName: batteryStatus === "Charging" ? "battery_charging_full" : "battery_full"
        accentColor: batteryStatus === "Charging" ? ThemePalette.Theme.green : ThemePalette.Theme.accent
    }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 105
                radius: 22
                color: ThemePalette.Theme.surfaceAlt
                border.width: 1
                border.color: ThemePalette.Theme.border

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 17

                    // BIG ICON
                    Rectangle {
                        Layout.preferredWidth: 58
                        Layout.preferredHeight: 58
                        radius: 29
                        color: batteryStatus === "Charging" ? ThemePalette.Theme.greenSurface : ThemePalette.Theme.surfaceDark

                        Text {
                            anchors.centerIn: parent
                            text: batteryStatus === "Charging" ? "bolt" : "battery_full_alt"
                            color: batteryStatus === "Charging" ? ThemePalette.Theme.green : ThemePalette.Theme.accent
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 29
                        }

                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: bat.value + "%"
                            color: ThemePalette.Theme.text
                            font.family: "Inter"
                            font.pixelSize: 27
                            font.weight: Font.Medium
                        }

                        Text {
                            text: {
                                if (batteryStatus === "Charging")
                                    return "Charging";

                                if (batteryStatus === "Full")
                                    return "Fully charged";

                                if (batteryStatus === "Discharging")
                                    return "Discharging";

                                return batteryStatus;
                            }
                            color: batteryStatus === "Charging" ? ThemePalette.Theme.green : ThemePalette.Theme.muted
                            font.family: "Inter"
                            font.pixelSize: 13
                        }

                    }

                }

            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 68
                radius: 18
                color: ThemePalette.Theme.surfaceAlt
                border.width: 1
                border.color: ThemePalette.Theme.border
                visible: batteryTime.length > 0 && batteryStatus !== "Full"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    spacing: 13

                    Text {
                        text: batteryStatus === "Charging" ? "schedule" : "schedule"
                        color: ThemePalette.Theme.yellow
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 23
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: batteryStatus === "Charging" ? "Time to full" : "Time remaining"
                            color: ThemePalette.Theme.muted
                            font.family: "Inter"
                            font.pixelSize: 12
                        }

                        Text {
                            text: batteryTime
                            color: ThemePalette.Theme.text
                            font.family: "Inter"
                            font.pixelSize: 15
                        }

                    }

                }

            }

            Text {
                text: "POWER MODE"
                color: ThemePalette.Theme.muted
                font.family: "Inter"
                font.pixelSize: 9
                font.weight: Font.Bold
                font.letterSpacing: 1
                Layout.topMargin: 3
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                PowerModeButton {
                    Layout.fillWidth: true
                    title: "Performance"
                    icon: "speed"
                    active: powerMode === "Performance"
                    accent: ThemePalette.Theme.red
                    onClicked: popup.setPowerMode("Performance")
                }

                PowerModeButton {
                    Layout.fillWidth: true
                    title: "Balanced"
                    icon: "balance"
                    active: powerMode === "Balanced"
                    accent: ThemePalette.Theme.yellow
                    onClicked: popup.setPowerMode("Balanced")
                }

            }

            PowerModeButton {
                Layout.fillWidth: true
                title: "Power Saver"
                icon: "eco"
                active: powerMode === "Power Saver"
                accent: ThemePalette.Theme.green
                onClicked: popup.setPowerMode("Power Saver")
            }

            Item {
                Layout.fillHeight: true
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: changingMode ? "Applying power mode…" : "TLP 1.10.2"
                    color: ThemePalette.Theme.mutedStrong
                    font.family: "Inter"
                    font.pixelSize: 11
                    Layout.fillWidth: true
                }

                Text {
                    text: "bolt"
                    color: ThemePalette.Theme.mutedStrong
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 17
                }

            }

        }

        Behavior on scale {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutCubic
            }

        }

        Behavior on opacity {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
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

        onFinished: {
            popup.visible = false;
        }

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

    component PowerModeButton: Rectangle {
        id: modeButton

        property string title: ""
        property string icon: ""
        property bool active: false
        property color accent: ThemePalette.Theme.green

        signal clicked()

        Layout.preferredHeight: 58
        radius: 16
        color: active ? Qt.darker(accent, 2.7) : ThemePalette.Theme.surfaceAlt
        border.width: active ? 1 : 1
        border.color: active ? accent : ThemePalette.Theme.border

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: 9

            Text {
                text: modeButton.icon
                color: active ? accent : ThemePalette.Theme.muted
                font.family: "Material Symbols Rounded"
                font.pixelSize: 20
            }

            Text {
                text: modeButton.title
                color: active ? ThemePalette.Theme.text : ThemePalette.Theme.muted
                font.family: "Inter"
                font.pixelSize: 12
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Text {
                visible: active
                text: "check"
                color: accent
                font.family: "Material Symbols Rounded"
                font.pixelSize: 19
            }

        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: modeButton.clicked()
        }

        Behavior on color {
            ColorAnimation {
                duration: 160
            }

        }

    }

}
