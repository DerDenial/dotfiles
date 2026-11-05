import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../Theme" as ThemeApi

SPage {
    id: page
    property var monitors: []
    property string monitorError: ""
    property bool brightnessAvailable: false
    property string brightnessDevice: ""
    property real brightnessPercent: 0
    property int pendingBrightness: -1
    property string errorText: ""

    function refresh() {
        if (!probe.running) probe.running = true;
    }
    function setBrightness(value) {
        if (!brightnessAvailable) return;
        pendingBrightness = Math.max(1, Math.min(100, Math.round(value)));
        brightnessPercent = pendingBrightness;
        errorText = "";
        debounce.restart();
    }
    function flushBrightness() {
        if (pendingBrightness < 0 || brightnessWrite.running || !brightnessDevice) return;
        const percent = pendingBrightness;
        pendingBrightness = -1;
        brightnessWrite.command = ["brightnessctl", "-d", brightnessDevice, "set", percent + "%"];
        brightnessWrite.running = true;
    }
    onActiveChanged: {
        if (active) refresh();
        else flushBrightness();
    }
    Component.onCompleted: if (active) refresh()
    property Timer poll: Timer { interval: 3000; running: page.active; repeat: true; onTriggered: page.refresh() }
    property Timer debounce: Timer { interval: 65; onTriggered: page.flushBrightness() }
    property Process probe: Process {
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/Settings/system-info.py", "display"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (data.error) { page.errorText = data.error; return; }
                    page.monitors = data.monitors || [];
                    page.monitorError = data.monitorError || "";
                    const brightness = data.brightness || {};
                    page.brightnessAvailable = brightness.available === true;
                    page.brightnessDevice = brightness.device || "";
                    if (!brightnessSlider.pressed && page.pendingBrightness < 0 && !brightnessWrite.running)
                        page.brightnessPercent = brightness.percent || 0;
                } catch (error) { page.errorText = "Could not read display information."; }
            }
        }
    }
    property Process brightnessWrite: Process {
        stderr: StdioCollector { id: writeError }
        onExited: function(code, status) {
            if (code !== 0) page.errorText = writeError.text.trim() || "Brightness could not be changed. Check backlight permissions.";
            if (page.pendingBrightness >= 0) debounce.restart();
            else page.refresh();
        }
    }

    SNotice { Layout.fillWidth: true; text: page.errorText; warning: true }

    SCard {
        Layout.fillWidth: true
        title: "Brightness"
        subtitle: page.brightnessAvailable ? "Built-in display · " + page.brightnessDevice : "No controllable backlight was detected"
        iconName: "brightness_6"
        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            SButton {
                text: "−"
                enabled: page.brightnessAvailable
                onClicked: page.setBrightness(page.brightnessPercent - 5)
                Accessible.name: "Lower brightness"
            }
            SSlider {
                id: brightnessSlider
                Layout.fillWidth: true
                from: 1
                to: 100
                stepSize: 1
                value: page.brightnessPercent
                enabled: page.brightnessAvailable
                onMoved: page.setBrightness(value)
                onPressedChanged: if (!pressed) page.flushBrightness()
                Accessible.name: "Display brightness"
            }
            SButton {
                text: "+"
                enabled: page.brightnessAvailable
                onClicked: page.setBrightness(page.brightnessPercent + 5)
                Accessible.name: "Raise brightness"
            }
            SLabel {
                Layout.preferredWidth: 44
                text: page.brightnessAvailable ? Math.round(page.brightnessPercent) + "%" : "—"
                horizontalAlignment: Text.AlignRight
                font.weight: Font.DemiBold
            }
        }
        SLabel {
            Layout.fillWidth: true
            text: "Brightness is applied immediately. The minimum stays at 1% so the display remains visible."
            color: ThemeApi.Theme.muted
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            visible: page.brightnessAvailable
        }
    }

    SCard {
        Layout.fillWidth: true
        title: "Connected displays"
        subtitle: page.monitors.length + (page.monitors.length === 1 ? " active display" : " active displays")
        iconName: "desktop_windows"
        Repeater {
            model: page.monitors
            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 6
                SRow {
                    Layout.fillWidth: true
                    title: modelData.description || modelData.name || "Display"
                    subtitle: modelData.name || ""
                    iconName: (modelData.name || "").startsWith("eDP") ? "laptop_windows" : "desktop_windows"
                    value: modelData.focused ? "Focused" : "Connected"
                }
                GridLayout {
                    Layout.fillWidth: true
                    columns: width > 420 ? 3 : 2
                    columnSpacing: 16
                    rowSpacing: 12
                    DisplayMetric { title: "Resolution"; value: modelData.width + " × " + modelData.height }
                    DisplayMetric { title: "Refresh rate"; value: Number(modelData.refreshRate || 0).toFixed(2) + " Hz" }
                    DisplayMetric { title: "Scale"; value: Math.round(Number(modelData.scale || 1) * 100) + "%" }
                    DisplayMetric { title: "Position"; value: (modelData.x || 0) + ", " + (modelData.y || 0) }
                    DisplayMetric { title: "Rotation"; value: [0, 90, 180, 270, 0, 90, 180, 270][Number(modelData.transform || 0)] + "°" }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 12
                    Layout.bottomMargin: 8
                    implicitHeight: 1
                    color: ThemeApi.Theme.border
                    opacity: 0.5
                }
            }
        }
        SNotice { Layout.fillWidth: true; text: page.monitorError }
        RowLayout {
            Layout.fillWidth: true
            SLabel {
                Layout.fillWidth: true
                text: "Live information from Hyprland"
                color: ThemeApi.Theme.muted
                font.pixelSize: 12
            }
            SButton { text: "Refresh"; iconName: "refresh"; enabled: !probe.running; onClicked: page.refresh() }
        }
    }

    SCard {
        Layout.fillWidth: true
        title: "Personalize your display"
        subtitle: "Wallpaper and colors share the same system theme"
        iconName: "palette"
        SRow {
            Layout.fillWidth: true
            title: "Appearance & wallpaper"
            subtitle: "Choose a theme or extract colors from your wallpaper"
            iconName: "wallpaper"
            interactive: true
            onClicked: if (page.controller) page.controller.navigate("appearance")
        }
    }

    component DisplayMetric: ColumnLayout {
        property string title: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: 4
        SLabel { text: parent.title; font.pixelSize: 11; color: ThemeApi.Theme.muted }
        SLabel { text: parent.value; font.pixelSize: 14; font.weight: Font.Medium }
    }
}
