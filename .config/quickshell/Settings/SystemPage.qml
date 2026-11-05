import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../Theme" as ThemeApi

SPage {
    id: page
    property var info: ({ storage: [], temperatures: [] })
    property string errorText: ""
    property real cpuPercent: -1
    property real previousTotal: -1
    property real previousIdle: -1
    property string clipboardText: ""

    function refresh() {
        if (!probe.running) probe.running = true;
    }
    function bytes(value) {
        if (!Number.isFinite(Number(value))) return "—";
        const units = ["B", "KiB", "MiB", "GiB", "TiB"];
        let amount = Number(value);
        let index = 0;
        while (amount >= 1024 && index < units.length - 1) { amount /= 1024; index++; }
        return amount.toFixed(index >= 3 ? 1 : 0) + " " + units[index];
    }
    function uptime(value) {
        const minutes = Math.floor((value || 0) / 60);
        const days = Math.floor(minutes / 1440);
        const hours = Math.floor(minutes / 60) % 24;
        return (days ? days + " d " : "") + (hours ? hours + " h " : "") + minutes % 60 + " min";
    }
    function copyDetails() {
        if (copyProcess.running || !info.clipboard) return;
        const lines = [
            "Hostname: " + (info.hostname || "Unknown"),
            "OS: " + (info.os || "Linux"),
            "Kernel: " + (info.kernel || "Unknown"),
            "Architecture: " + (info.architecture || "Unknown"),
            "Processor: " + (info.cpuName || "Unknown"),
            "Memory: " + bytes(info.memoryUsed) + " / " + bytes(info.memoryTotal),
            "Uptime: " + uptime(info.uptime)
        ];
        (info.storage || []).forEach(function(disk) {
            if (!disk.error) lines.push("Storage " + disk.path + ": " + bytes(disk.used) + " / " + bytes(disk.total) + " · " + disk.source);
        });
        clipboardText = lines.join("\n") + "\n";
        copyProcess.stdinEnabled = true;
        copyProcess.running = true;
    }
    onActiveChanged: {
        if (active) {
            previousTotal = -1;
            previousIdle = -1;
            cpuPercent = -1;
            refresh();
        }
    }
    Component.onCompleted: if (active) refresh()
    property Timer poll: Timer { interval: 2500; running: page.active; repeat: true; onTriggered: page.refresh() }
    property Process probe: Process {
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/Settings/system-info.py", "system"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (result.error) { page.errorText = result.error; return; }
                    if (page.previousTotal >= 0 && result.cpuTotal > page.previousTotal) {
                        const total = result.cpuTotal - page.previousTotal;
                        const idle = result.cpuIdle - page.previousIdle;
                        page.cpuPercent = Math.max(0, Math.min(100, 100 * (total - idle) / total));
                    }
                    page.previousTotal = result.cpuTotal;
                    page.previousIdle = result.cpuIdle;
                    page.info = result;
                } catch (error) { page.errorText = "Could not read system information."; }
            }
        }
    }
    property Process copyProcess: Process {
        command: ["wl-copy", "--type", "text/plain;charset=utf-8"]
        onStarted: {
            write(page.clipboardText);
            stdinEnabled = false;
        }
        onExited: function(code, status) {
            if (code === 0 && page.controller) page.controller.toast("System information copied.");
            else if (code !== 0) page.errorText = "Could not copy system information to the clipboard.";
        }
    }
    property Process monitorProcess: Process {
        command: ["qs", "ipc", "call", "taskManager", "open"]
        stderr: StdioCollector { id: monitorError }
        onExited: function(code, status) {
            if (code !== 0) page.errorText = monitorError.text.trim() || "System Monitor could not be opened.";
        }
    }

    SNotice { Layout.fillWidth: true; text: page.errorText; warning: true }

    GridLayout {
        Layout.fillWidth: true
        columns: width > 470 ? 2 : 1
        columnSpacing: 14
        rowSpacing: 14
        SCard {
            Layout.fillWidth: true
            title: "Processor"
            iconName: "memory"
            SLabel {
                text: page.cpuPercent >= 0 ? Math.round(page.cpuPercent) + "%" : "Measuring…"
                font.pixelSize: page.cpuPercent >= 0 ? 38 : 22
                font.weight: Font.DemiBold
            }
            Meter { Layout.fillWidth: true; fraction: Math.max(0, page.cpuPercent) / 100 }
            SLabel {
                Layout.fillWidth: true
                text: (page.info.cpuThreads || "—") + " logical processors"
                font.pixelSize: 12
                color: ThemeApi.Theme.muted
            }
        }
        SCard {
            Layout.fillWidth: true
            title: "Memory"
            iconName: "developer_board"
            SLabel {
                text: page.info.memoryPercent !== undefined ? Math.round(page.info.memoryPercent) + "%" : "—"
                font.pixelSize: 38
                font.weight: Font.DemiBold
            }
            Meter { Layout.fillWidth: true; fraction: (page.info.memoryPercent || 0) / 100 }
            SLabel {
                Layout.fillWidth: true
                text: page.bytes(page.info.memoryUsed) + " / " + page.bytes(page.info.memoryTotal)
                font.pixelSize: 12
                color: ThemeApi.Theme.muted
            }
        }
    }

    SCard {
        Layout.fillWidth: true
        title: "Storage"
        subtitle: "Home and system volumes"
        iconName: "storage"
        Repeater {
            model: page.info.storage || []
            delegate: ColumnLayout {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: 8
                SRow {
                    Layout.fillWidth: true
                    title: index === 0 ? "Home" : "System"
                    subtitle: modelData.error || modelData.path + " · " + (modelData.source || modelData.filesystem || "Volume")
                    iconName: index === 0 ? "home_storage" : "hard_drive"
                    value: modelData.error ? "" : Math.round(modelData.percent || 0) + "% used"
                }
                Meter {
                    Layout.fillWidth: true
                    fraction: (modelData.percent || 0) / 100
                    warning: (modelData.percent || 0) >= 90
                    visible: !modelData.error
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: !modelData.error
                    SLabel {
                        Layout.fillWidth: true
                        text: page.bytes(modelData.used) + " of " + page.bytes(modelData.total) + " used"
                        color: ThemeApi.Theme.muted
                        font.pixelSize: 12
                    }
                    SLabel {
                        text: page.bytes(modelData.free) + " available"
                        color: ThemeApi.Theme.muted
                        font.pixelSize: 12
                    }
                }
                Item { implicitHeight: index === 0 ? 10 : 0 }
            }
        }
    }

    SCard {
        Layout.fillWidth: true
        title: "Temperatures"
        subtitle: "Die wichtigsten Bauteile · live aktualisiert"
        iconName: "thermostat"
        visible: (page.info.temperatures || []).length > 0
        Repeater {
            model: page.info.temperatures || []
            delegate: SRow {
                id: temperatureRow
                required property var modelData
                readonly property string temperatureText: Math.round(Number(modelData.value)) + " °C"
                Layout.fillWidth: true
                title: modelData.name || "Sensor"
                subtitle: modelData.description || ""
                iconName: modelData.icon || "thermostat"
                Accessible.name: title + ", " + subtitle + ", " + temperatureText
                SLabel {
                    text: temperatureRow.temperatureText
                    color: ThemeApi.Theme.textBright
                    font.pixelSize: 23
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    SCard {
        padding: 22

        RowLayout {
            Layout.fillWidth: true
            spacing: 14
            Rectangle {
                Layout.preferredWidth: 54
                Layout.preferredHeight: 54
                radius: 17
                color: ThemeApi.Theme.accentSoft
                Text {
                    anchors.centerIn: parent
                    text: "computer"
                    color: ThemeApi.Theme.accent
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 29
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 3
                SLabel {
                    Layout.fillWidth: true
                    text: "About this computer"
                    color: ThemeApi.Theme.muted
                    font.pixelSize: 11
                }
                SLabel {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: page.info.hostname || "Your computer"
                    color: ThemeApi.Theme.textBright
                    font.pixelSize: 23
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                SLabel {
                    Layout.fillWidth: true
                    text: page.info.os || "Linux"
                    color: ThemeApi.Theme.accent
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 3
            Layout.bottomMargin: 3
            implicitHeight: 1
            color: Qt.alpha(ThemeApi.Theme.border, 0.45)
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                Layout.preferredWidth: 22
                text: "memory"
                color: ThemeApi.Theme.accent
                font.family: "Material Symbols Rounded"
                font.pixelSize: 20
                horizontalAlignment: Text.AlignHCenter
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 4
                SLabel {
                    text: "Processor"
                    color: ThemeApi.Theme.muted
                    font.pixelSize: 11
                }
                SLabel {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: page.info.cpuName || "—"
                    color: ThemeApi.Theme.textBright
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    wrapMode: Text.Wrap
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: width >= 460 ? 2 : 1
            columnSpacing: 24
            rowSpacing: 16
            Repeater {
                model: [
                    { label: "Kernel", detail: page.info.kernel || "—", icon: "code" },
                    { label: "Architecture", detail: page.info.architecture || "—", icon: "developer_board" },
                    { label: "Uptime", detail: page.uptime(page.info.uptime), icon: "schedule" },
                    { label: "Swap", detail: page.info.swapTotal > 0 ? page.bytes(page.info.swapUsed) + " / " + page.bytes(page.info.swapTotal) : "Not configured", icon: "swap_horiz" }
                ]
                delegate: RowLayout {
                    id: fact
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    spacing: 10
                    Accessible.role: Accessible.StaticText
                    Accessible.name: modelData.label + ", " + modelData.detail
                    Text {
                        Layout.preferredWidth: 22
                        text: fact.modelData.icon
                        color: ThemeApi.Theme.accent
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 20
                        horizontalAlignment: Text.AlignHCenter
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 4
                        SLabel {
                            Layout.fillWidth: true
                            text: fact.modelData.label
                            color: ThemeApi.Theme.muted
                            font.pixelSize: 11
                        }
                        SLabel {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: fact.modelData.detail
                            color: ThemeApi.Theme.textBright
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: 2
            implicitHeight: 1
            color: Qt.alpha(ThemeApi.Theme.border, 0.45)
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8
            SButton {
                text: "Copy system info"
                iconName: "content_copy"
                enabled: page.info.clipboard === true && !copyProcess.running
                onClicked: page.copyDetails()
            }
            SButton {
                text: "Task Manager"
                iconName: "monitoring"
                enabled: !monitorProcess.running
                onClicked: monitorProcess.running = true
            }
        }
    }

    component Meter: Rectangle {
        property real fraction: 0
        property bool warning: false
        implicitHeight: 6
        radius: 3
        color: ThemeApi.Theme.surfaceRaised
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, parent.fraction))
            height: parent.height
            radius: parent.radius
            color: parent.warning ? ThemeApi.Theme.red : ThemeApi.Theme.accent
            Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
        }
    }
}
