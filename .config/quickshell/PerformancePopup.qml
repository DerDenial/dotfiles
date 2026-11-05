import QtQuick
import "Theme" as ThemePalette
import QtQuick.Layouts
import Quickshell

Item {
    id: popup
    property var settingsController: null
    property string cpuUsage: cpuPoll.value || "0"
    property var memoryParts: memoryPoll.value.split("|")
    property string memoryPercent: memoryParts.length > 0 && memoryParts[0] !== "" ? memoryParts[0] : "0"
    property string memoryUsed: memoryParts.length > 1 ? memoryParts[1] : "0.0"
    property string memoryTotal: memoryParts.length > 2 ? memoryParts[2] : "0.0"
    property var temperatureRows: temperaturePoll.value.split("\n").filter(line => line.trim().length > 0).map(line => {
        const parts = line.split("|");
        return { label: parts[0] || "Sensor", value: parts[1] || "—" };
    })
    property var processRows: processPoll.value.split("\n").filter(line => line.trim().length > 0).map(line => {
        const parts = line.split("|");
        return { name: parts[0] || "process", cpu: parts[1] || "0", ram: parts[2] || "0" };
    })

    function open() {
        visible = true;
        openAnimation.restart();
    }
    function close() {
        if (settingsController) settingsController.close();
        else closeAnimation.restart();
    }
    function toggle() {
        if (visible) close();
        else open();
    }


    Poller {
        id: cpuPoll
        interval: 2000
        command: "awk 'NR==1 { idle1=$5+$6; total1=$2+$3+$4+$5+$6+$7+$8+$9; close(\"/proc/stat\"); system(\"sleep 0.2\"); getline < \"/proc/stat\"; idle2=$5+$6; total2=$2+$3+$4+$5+$6+$7+$8+$9; delta=total2-total1; if (delta > 0) printf \"%d\", (100*(delta-(idle2-idle1))/delta); exit }' /proc/stat"
    }
    Poller {
        id: memoryPoll
        interval: 2000
        command: "awk '/MemTotal:/ {total=$2} /MemAvailable:/ {available=$2} END {used=total-available; printf \"%d|%.1f|%.1f\", (100*used/total), used/1048576, total/1048576}' /proc/meminfo"
    }
    Poller {
        id: temperaturePoll
        interval: 3000
        command: "for input in /sys/class/hwmon/hwmon*/temp*_input /sys/class/thermal/thermal_zone*/temp; do [ -r \"$input\" ] || continue; raw=$(cat \"$input\" 2>/dev/null); case \"$input\" in */thermal_zone*/temp) labelfile=$(printf '%s\\n' \"$input\" | sed 's#/temp$#/type#');; *) labelfile=$(printf '%s\\n' \"$input\" | sed 's/_input$/_label/');; esac; label=$(cat \"$labelfile\" 2>/dev/null); [ -n \"$label\" ] || label=$(basename \"$(dirname \"$input\")\"); temp=$(awk -v t=\"$raw\" 'BEGIN {printf \"%.1f\", t/1000}'); printf '%s|%s\\n' \"$label\" \"$temp\"; done"
    }
    Poller {
        id: processPoll
        interval: 3000
        command: "ps -eo comm=,%cpu=,%mem= --sort=-%cpu | head -n 5 | awk '{$1=$1; print $1 \"|\" $2 \"|\" $3}'"
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
        title: "Performance"
        subtitle: "Live system usage and running processes"
        iconName: "monitoring"
        accentColor: ThemePalette.Theme.accent

        Rectangle {
            Layout.preferredWidth: 86
            Layout.preferredHeight: 36
            radius: 13
            color: ThemePalette.Theme.surfaceAlt
            RowLayout {
                anchors.centerIn: parent
                spacing: 6
                Text { text: "speed"; color: ThemePalette.Theme.accent; font.family: "Material Symbols Rounded"; font.pixelSize: 16 }
                Text { text: popup.cpuUsage + "%"; color: ThemePalette.Theme.text; font.family: "Inter"; font.pixelSize: 11; font.weight: Font.DemiBold }
            }
        }
    }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 86
                    radius: 18
                    color: ThemePalette.Theme.surfaceAlt
                    border.width: 1
                    border.color: ThemePalette.Theme.border
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 13
                        spacing: 3
                        Text { text: "CPU"; color: ThemePalette.Theme.muted; font.family: "Inter"; font.pixelSize: 11 }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: popup.cpuUsage + "%"; color: ThemePalette.Theme.yellow; font.family: "Inter"; font.pixelSize: 21; Layout.fillWidth: true }
                            Text { text: "Total usage"; color: ThemePalette.Theme.muted; font.family: "Inter"; font.pixelSize: 10 }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 5
                            radius: 3
                            color: ThemePalette.Theme.border
                            Rectangle { width: parent.width * Math.max(0, Math.min(1, Number(popup.cpuUsage) / 100)); height: parent.height; radius: 3; color: ThemePalette.Theme.yellow }
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 86
                    radius: 18
                    color: ThemePalette.Theme.surfaceAlt
                    border.width: 1
                    border.color: ThemePalette.Theme.border
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 13
                        spacing: 3
                        Text { text: "Memory"; color: ThemePalette.Theme.muted; font.family: "Inter"; font.pixelSize: 11 }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: popup.memoryPercent + "%"; color: ThemePalette.Theme.accent; font.family: "Inter"; font.pixelSize: 21; Layout.fillWidth: true }
                            Text { text: popup.memoryUsed + " / " + popup.memoryTotal + " GiB"; color: ThemePalette.Theme.muted; font.family: "Inter"; font.pixelSize: 10 }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 5
                            radius: 3
                            color: ThemePalette.Theme.border
                            Rectangle { width: parent.width * Math.max(0, Math.min(1, Number(popup.memoryPercent) / 100)); height: parent.height; radius: 3; color: ThemePalette.Theme.accent }
                        }
                    }
                }
            }

            Text { text: "TEMPERATURES"; color: ThemePalette.Theme.mutedStrong; font.family: "Inter"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1 }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(52, Math.min(temperatureColumn.implicitHeight + 24, 126))
                radius: 18
                color: ThemePalette.Theme.surfaceAlt
                border.width: 1
                border.color: ThemePalette.Theme.border
                ColumnLayout {
                    id: temperatureColumn
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 5
                    Repeater {
                        model: popup.temperatureRows.slice(0, 4)
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Text { text: modelData.label; color: ThemePalette.Theme.text; font.family: "Inter"; font.pixelSize: 13; Layout.fillWidth: true; elide: Text.ElideRight }
                            Text { text: modelData.value + " °C"; color: Number(modelData.value) >= 80 ? ThemePalette.Theme.red : ThemePalette.Theme.green; font.family: "Inter"; font.pixelSize: 13 }
                        }
                    }
                    Text {
                        visible: popup.temperatureRows.length === 0
                        text: "No temperature sensors found"
                        color: ThemePalette.Theme.muted
                        font.family: "Inter"
                        font.pixelSize: 13
                    }
                }
            }

            Text { text: "TOP PROCESSES"; color: ThemePalette.Theme.mutedStrong; font.family: "Inter"; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1 }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 5
                Repeater {
                    model: popup.processRows
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 42
                        radius: 13
                        color: processHover.containsMouse ? ThemePalette.Theme.surfaceRaised : ThemePalette.Theme.surfaceAlt
                        border.width: 1
                        border.color: ThemePalette.Theme.border
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8
                        Text { text: modelData.name; color: ThemePalette.Theme.text; font.family: "Inter"; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
                        Text { text: modelData.cpu + "% CPU"; color: ThemePalette.Theme.yellow; font.family: "Inter"; font.pixelSize: 11; Layout.preferredWidth: 58; horizontalAlignment: Text.AlignRight }
                        Text { text: modelData.ram + "% RAM"; color: ThemePalette.Theme.accent; font.family: "Inter"; font.pixelSize: 11; Layout.preferredWidth: 58; horizontalAlignment: Text.AlignRight }
                        }
                        MouseArea { id: processHover; anchors.fill: parent; hoverEnabled: true }
                    }
                }
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
