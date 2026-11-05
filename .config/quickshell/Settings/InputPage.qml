import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../Theme" as ThemeApi

SPage {
    id: page
    property var info: ({ values: {}, changed: 0, available: false })
    property string error: ""
    property real pendingSensitivity: 0
    readonly property string helper: Quickshell.env("HOME") + "/.config/quickshell/Settings/input-preferences.py"
    readonly property bool busy: writer.running
    function available(key) { return info.values[key] !== undefined && info.values[key] !== null; }
    function value(key, fallback) { return available(key) ? info.values[key] : fallback; }
    function refresh() { if (!reader.running && !writer.running) reader.running = true; }
    function change(key, value) {
        if (busy) return;
        error = "";
        writer.command = ["python3", helper, "set", key, JSON.stringify(value)];
        writer.running = true;
    }
    Component.onCompleted: refresh()
    property Process reader: Process {
        command: ["python3", page.helper, "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { page.info = JSON.parse(text); }
                catch (e) { page.error = "Could not read input settings."; }
            }
        }
    }
    property Process writer: Process {
        stdout: StdioCollector { onStreamFinished: { try { const result = JSON.parse(text); if (result.error) page.error = result.error; } catch(e) { page.error = "Could not update the setting."; } } }
        onExited: function(code) { page.refresh(); if (code === 0 && page.controller) page.controller.toast("Input preference saved"); }
    }
    property Timer refreshTimer: Timer { interval: 5000; running: page.active; repeat: true; onTriggered: page.refresh() }
    property Timer sensitivityDebounce: Timer { interval: 250; onTriggered: page.change("sensitivity", page.pendingSensitivity) }
    SNotice { text: page.error; warning: true }
    SNotice { text: !page.info.available && !page.reader.running ? "Input controls are unavailable until the compositor is reachable." : "" }
    SCard {
        title: "Touchpad"
        subtitle: "Saved preferences are applied again at login and after a configuration reload."
        iconName: "touchpad_mouse"
        SRow {
            title: "Natural scrolling"
            subtitle: "Move the content in the direction of your fingers."
            SToggle { checked: page.value("naturalScroll", false); enabled: page.available("naturalScroll") && !page.busy; onToggled: page.change("naturalScroll", checked) }
        }
        SRow {
            title: "Tap to click"
            subtitle: "Tap the touchpad instead of pressing it."
            SToggle { checked: page.value("tapToClick", false); enabled: page.available("tapToClick") && !page.busy; onToggled: page.change("tapToClick", checked) }
        }
        SRow {
            title: "Disable while typing"
            subtitle: "Avoid accidental pointer movement while using the keyboard."
            SToggle { checked: page.value("disableWhileTyping", false); enabled: page.available("disableWhileTyping") && !page.busy; onToggled: page.change("disableWhileTyping", checked) }
        }
    }
    SCard {
        title: "Touchpad gestures"
        subtitle: "Swipe with three or four fingers to navigate your desktop."
        iconName: "swipe"
        SRow { title: "Open windows"; value: "3 fingers ↑"; iconName: "arrow_upward" }
        SRow { title: "Quick settings"; value: "3 fingers ↓"; iconName: "arrow_downward" }
        SRow { title: "Move between columns"; value: "3 fingers ↔"; iconName: "swipe" }
        SRow { title: "Switch workspaces"; value: "4 fingers ↔"; iconName: "view_carousel" }
    }
    SCard {
        title: "Pointer"
        iconName: "mouse"
        SRow { title: "Pointer sensitivity"; value: Number(page.value("sensitivity", 0)).toFixed(2); subtitle: "Applies to the default mouse and touchpad configuration." }
        SSlider {
            Layout.fillWidth: true
            from: -1; to: 1; stepSize: 0.05
            value: page.value("sensitivity", 0)
            enabled: page.available("sensitivity") && !page.busy
            onMoved: { page.pendingSensitivity = value; page.sensitivityDebounce.restart(); }
        }
        SRow {
            title: "Focus follows pointer"
            subtitle: "Focus the window underneath your pointer."
            SToggle { checked: page.value("followMouse", 0) !== 0; enabled: page.available("followMouse") && !page.busy; onToggled: page.change("followMouse", checked ? 1 : 0) }
        }
    }
    SCard {
        title: "Keyboard"
        iconName: "keyboard"
        SRow {
            title: "Key repeat rate"
            subtitle: "Characters per second when holding a key."
            value: page.value("repeatRate", "—") + " / s"
            SButton { iconName: "remove"; Accessible.name: "Reduce key repeat rate"; enabled: page.available("repeatRate") && !page.busy && page.value("repeatRate",0)>1; onClicked: page.change("repeatRate", Math.max(1, page.value("repeatRate",25)-5)) }
            SButton { iconName: "add"; Accessible.name: "Increase key repeat rate"; enabled: page.available("repeatRate") && !page.busy && page.value("repeatRate",0)<80; onClicked: page.change("repeatRate", Math.min(80, page.value("repeatRate",25)+5)) }
        }
        SRow {
            title: "Repeat delay"
            subtitle: "How long to hold a key before repeating starts."
            value: page.value("repeatDelay", "—") + " ms"
            SButton { iconName: "remove"; Accessible.name: "Reduce key repeat delay"; enabled: page.available("repeatDelay") && !page.busy && page.value("repeatDelay",0)>100; onClicked: page.change("repeatDelay", Math.max(100, page.value("repeatDelay",600)-50)) }
            SButton { iconName: "add"; Accessible.name: "Increase key repeat delay"; enabled: page.available("repeatDelay") && !page.busy && page.value("repeatDelay",0)<1000; onClicked: page.change("repeatDelay", Math.min(1000, page.value("repeatDelay",600)+50)) }
        }
    }
    SCard {
        title: "Your shortcuts"
        subtitle: "Super is the Windows key."
        Repeater {
            model: [
                { title: "App launcher", key: "Super + Space" },
                { title: "Open windows", key: "Super + Tab" },
                { title: "Settings", key: "Super + I" },
                { title: "Lock screen", key: "Super + L" },
                { title: "Power menu", key: "Super + Esc" },
                { title: "Quick notes", key: "Super + N" },
                { title: "Quick settings", key: "Super + Q" },
                { title: "Hardware monitor", key: "Super + H" },
                { title: "Live network traffic", key: "Super + Shift + N" },
                { title: "Internet speed test", key: "Super + Alt + S" },
                { title: "Clipboard history", key: "Super + Alt + V" },
                { title: "Theme & wallpaper switcher", key: "Super + Shift + T" },
                { title: "Random wallpaper", key: "Super + Shift + R" },
                { title: "Notification center", key: "Super + T" },
                { title: "File manager", key: "Super + E" },
                { title: "Show desktop", key: "Super + D" },
                { title: "Expand window / full-width taskbar", key: "Super + ↑" },
                { title: "Restore window and notch", key: "Super + ↓" },
                { title: "Capture and edit region", key: "Print" }
            ]
            delegate: SRow { required property var modelData; title: modelData.title; value: modelData.key; implicitHeight: 44 }
        }
    }
    SRow {
        title: "Restore input preferences"
        subtitle: "Restore the values from before you changed them here."
        SButton {
            text: "Restore"
            enabled: page.info.changed > 0 && !page.busy
            onClicked: if(page.controller) page.controller.confirm("Restore input preferences?", "This restores only the input options changed in this app.", function() { page.writer.command = ["python3", page.helper, "reset"]; page.writer.running = true; })
        }
    }
}
