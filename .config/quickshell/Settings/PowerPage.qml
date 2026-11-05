import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../Theme" as ThemeApi

SPage {
    id: page
    property var details: ({ batteries: [], capabilities: {} })
    property string errorText: ""
    property string requestedProfile: ""
    readonly property var battery: UPower.displayDevice
    readonly property var localBattery: details.batteries && details.batteries.length ? details.batteries[0] : null
    readonly property bool batteryReady: battery && battery.ready && battery.isPresent
    readonly property bool hasBattery: batteryReady || localBattery !== null
    readonly property real level: batteryReady ? battery.percentage * 100 : (localBattery ? localBattery.percent : 0)
    readonly property bool charging: batteryReady ? battery.state === UPowerDeviceState.Charging : localBattery && localBattery.status === "Charging"
    readonly property string batteryState: {
        if (!hasBattery) return "No battery detected";
        if (!batteryReady) return localBattery.status;
        switch (battery.state) {
        case UPowerDeviceState.Charging: return "Charging";
        case UPowerDeviceState.Discharging: return "Running on battery";
        case UPowerDeviceState.FullyCharged: return "Fully charged";
        case UPowerDeviceState.PendingCharge: return "Charging paused";
        case UPowerDeviceState.PendingDischarge: return "Plugged in";
        case UPowerDeviceState.Empty: return "Battery empty";
        default: return "Battery status unavailable";
        }
    }
    readonly property real secondsRemaining: batteryReady ? (charging ? battery.timeToFull : battery.timeToEmpty) : 0
    readonly property var profileOptions: [
        { id: "power-saver", title: "Power saver", icon: "eco", subtitle: "Lower power use" },
        { id: "balanced", title: "Balanced", icon: "balance", subtitle: "Everyday use" },
        { id: "performance", title: "Performance", icon: "speed", subtitle: "Maximum responsiveness" }
    ]

    function refresh() {
        if (!probe.running) probe.running = true;
    }
    function duration(seconds) {
        const minutes = Math.max(1, Math.round(seconds / 60));
        return minutes >= 60 ? Math.floor(minutes / 60) + " h " + minutes % 60 + " min" : minutes + " min";
    }
    function chooseProfile(profile) {
        if (profileChange.running || !details.tlpAvailable) return;
        if (!["performance", "balanced", "power-saver"].includes(profile)) return;
        requestedProfile = profile;
        errorText = "";
        profileChange.command = ["pkexec", "tlp", profile];
        profileChange.running = true;
    }
    function runSession(action) {
        if (sessionCommand.running) return;
        const options = {
            lock: { title: "Lock the screen?", message: "Your session stays open behind the lock screen.", command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/LockScreen/lock.py"] },
            suspend: { title: "Put the computer to sleep?", message: "Your apps stay open. The computer uses a small amount of power.", command: ["systemctl", "suspend"] },
            hibernate: { title: "Hibernate the computer?", message: "Save the current session to disk and power off. Hibernation must be configured on this system.", command: ["systemctl", "hibernate"] },
            logout: { title: "Log out?", message: "This closes your apps and ends the current session. Save your work first.", command: ["hyprctl", "dispatch", "exit"] },
            restart: { title: "Restart the computer?", message: "This closes your apps and restarts the computer. Save your work first.", command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/session-power.py", "reboot"] },
            poweroff: { title: "Shut down the computer?", message: "This closes your apps and powers off the computer. Save your work first.", command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/session-power.py", "poweroff"] }
        };
        const option = options[action];
        if (!option || !controller) return;
        controller.confirm(option.title, option.message, function() {
            page.errorText = "";
            sessionCommand.command = option.command;
            sessionCommand.running = true;
        });
    }

    onActiveChanged: if (active) refresh()
    Component.onCompleted: if (active) refresh()
    property Timer poll: Timer { interval: 10000; running: page.active; repeat: true; onTriggered: page.refresh() }
    property Process probe: Process {
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/Settings/system-info.py", "power"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (!result.error) page.details = result;
                    else page.errorText = result.error;
                } catch (error) { page.errorText = "Could not read power information."; }
            }
        }
    }
    property Process profileChange: Process {
        stderr: StdioCollector { id: profileError }
        onExited: function(code, status) {
            if (code === 0) {
                if (page.controller) page.controller.toast("Power profile applied.");
            } else {
                page.errorText = code === 126 ? "Authentication was cancelled." : profileError.text.trim() || "The power profile could not be changed.";
            }
            page.requestedProfile = "";
            page.refresh();
        }
    }
    property Process sessionCommand: Process {
        stderr: StdioCollector { id: sessionError }
        onExited: function(code, status) {
            if (code !== 0) page.errorText = sessionError.text.trim() || "The requested session action could not be completed.";
        }
    }

    SNotice { text: page.errorText; warning: true; Layout.fillWidth: true }

    SCard {
        Layout.fillWidth: true
        title: "Battery"
        subtitle: page.batteryState
        iconName: page.charging ? "battery_charging_full" : "battery_full"
        RowLayout {
            Layout.fillWidth: true
            spacing: 24
            SLabel {
                text: page.hasBattery ? Math.round(page.level) + "%" : "—"
                font.pixelSize: 48
                font.weight: Font.DemiBold
                color: page.level < 15 && !page.charging ? ThemeApi.Theme.red : ThemeApi.Theme.text
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                SLabel {
                    Layout.fillWidth: true
                    text: UPower.onBattery ? "On battery power" : "External power connected"
                    font.weight: Font.Medium
                }
                SLabel {
                    Layout.fillWidth: true
                    text: page.secondsRemaining > 0 ? page.duration(page.secondsRemaining) + (page.charging ? " until full · estimate" : " remaining · estimate") : "Remaining time is not available yet"
                    color: ThemeApi.Theme.muted
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    visible: page.hasBattery
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 7
            radius: 4
            color: ThemeApi.Theme.surfaceRaised
            visible: page.hasBattery
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, page.level / 100))
                height: parent.height
                radius: parent.radius
                color: page.level < 15 && !page.charging ? ThemeApi.Theme.red : ThemeApi.Theme.accent
                Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
            }
        }
        GridLayout {
            visible: page.localBattery !== null
            Layout.fillWidth: true
            columns: width > 450 ? 3 : 2
            columnSpacing: 20
            rowSpacing: 12
            BatteryMetric {
                title: "Battery health"
                value: page.localBattery && page.localBattery.health !== null ? page.localBattery.health.toFixed(1) + "%" : "Unavailable"
            }
            BatteryMetric {
                title: "Charge cycles"
                value: page.localBattery && page.localBattery.cycles >= 0 ? String(page.localBattery.cycles) : "Unavailable"
            }
            BatteryMetric {
                title: page.charging ? "Charging rate" : "Power draw"
                value: page.batteryReady && page.battery.changeRate > 0 ? page.battery.changeRate.toFixed(1) + " W" : page.localBattery && page.localBattery.rate > 0 ? page.localBattery.rate.toFixed(1) + " W" : "—"
            }
            BatteryMetric {
                title: "Stored energy"
                value: page.localBattery && page.localBattery.energy >= 0 ? page.localBattery.energy.toFixed(1) + " Wh" : "Unavailable"
            }
            BatteryMetric {
                title: "Full capacity"
                value: page.localBattery && page.localBattery.capacity > 0 ? page.localBattery.capacity.toFixed(1) + " Wh" : "Unavailable"
            }
        }
    }

    SCard {
        Layout.fillWidth: true
        title: "Power profile"
        subtitle: profileChange.running ? "Applying profile · authentication may be required" : "Choose how the system balances power use and responsiveness"
        iconName: "energy_savings_leaf"
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: page.profileOptions
                delegate: SButton {
                    required property var modelData
                    Layout.fillWidth: true
                    text: modelData.title
                    iconName: modelData.icon
                    accent: page.details.profile === modelData.id
                    enabled: page.details.tlpAvailable === true && !profileChange.running
                    onClicked: page.chooseProfile(modelData.id)
                }
            }
        }
        SLabel {
            Layout.fillWidth: true
            font.pixelSize: 12
            color: ThemeApi.Theme.muted
            text: "Current: " + (page.details.profile || "Unknown") + (page.details.platformProfile ? " · Platform: " + page.details.platformProfile : "")
            wrapMode: Text.WordWrap
        }
        SNotice {
            Layout.fillWidth: true
            warning: true
            text: page.details.tlpAvailable && page.details.tlpServiceState === "disabled" ? "TLP is installed, but its startup service is disabled. A profile change applies now; boot-time power management is not enabled." : ""
        }
        SNotice {
            Layout.fillWidth: true
            text: page.details.tlpAvailable === false ? "TLP is not installed. Power profiles are unavailable on this system." : ""
        }
    }

    SCard {
        Layout.fillWidth: true
        title: "Session"
        subtitle: "Sleep, secure your screen or end the session"
        iconName: "power_settings_new"
        SRow {
            Layout.fillWidth: true
            title: "Lock screen"
            subtitle: "Keep all apps open"
            iconName: "lock"
            interactive: true
            enabled: page.details.lockAvailable === true && !sessionCommand.running
            onClicked: page.runSession("lock")
        }
        SRow {
            Layout.fillWidth: true
            title: "Sleep"
            subtitle: "Resume quickly with your apps in place"
            iconName: "bedtime"
            interactive: true
            enabled: !sessionCommand.running && page.details.capabilities && !["no", "na"].includes(page.details.capabilities.suspend)
            onClicked: page.runSession("suspend")
        }
        SRow {
            Layout.fillWidth: true
            title: "Hibernate"
            subtitle: "Save the session to disk and power off"
            iconName: "mode_night"
            interactive: true
            enabled: !sessionCommand.running && page.details.capabilities && ["yes", "challenge"].includes(page.details.capabilities.hibernate)
            onClicked: page.runSession("hibernate")
        }
        SRow {
            Layout.fillWidth: true
            title: "Log out"
            subtitle: "End the current Hyprland session"
            iconName: "logout"
            interactive: true
            onClicked: page.runSession("logout")
        }
        SRow {
            Layout.fillWidth: true
            title: "Restart"
            subtitle: "Close apps and restart the computer"
            iconName: "restart_alt"
            interactive: true
            destructive: true
            onClicked: page.runSession("restart")
        }
        SRow {
            Layout.fillWidth: true
            title: "Shut down"
            subtitle: "Close apps and turn off the computer"
            iconName: "power_settings_new"
            interactive: true
            destructive: true
            onClicked: page.runSession("poweroff")
        }
    }

    component BatteryMetric: ColumnLayout {
        property string title: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: 4
        SLabel { text: parent.title; color: ThemeApi.Theme.muted; font.pixelSize: 11 }
        SLabel { text: parent.value; font.weight: Font.DemiBold; font.pixelSize: 16 }
    }
}
