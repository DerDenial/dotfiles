import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "Theme" as ThemePalette

Item {
    id: audio

    property bool opened: false
    property var settingsController: null
    property var outputDevices: []
    property var inputDevices: []

    function open() {
        opened = true;
    }

    function parseDevices(raw) {
        var sinks = [];
        var sources = [];
        var section = "";
        var lines = String(raw || "").split("\n");
        for (var i = 0; i < lines.length; ++i) {
            var line = lines[i].replace(/[│├└─]/g, "").trim();
            if (line === "Sinks:") {
                section = "output";
                continue;
            }
            if (line === "Sources:") {
                section = "input";
                continue;
            }
            if (/^(Devices|Sink endpoints|Source endpoints|Filters|Streams|Video|Settings):$/.test(line)) {
                section = "";
                continue;
            }
            if (!section)
                continue;
            var match = line.match(/^(\*)?\s*(\d+)\.\s+(.+?)(?:\s+\[vol:.*\])?$/);
            if (!match)
                continue;
            var item = { id: match[2], name: match[3].trim(), isDefault: Boolean(match[1]) };
            if (section === "output")
                sinks.push(item);
            else if (section === "input" && !/monitor/i.test(item.name))
                sources.push(item);
        }
        outputDevices = sinks;
        inputDevices = sources;
    }

    function defaultDeviceName(devices, fallback) {
        for (var i = 0; i < devices.length; ++i) {
            if (devices[i].isDefault)
                return devices[i].name;
        }
        return fallback;
    }

    function setDefaultDevice(deviceId) {
        Quickshell.execDetached(["wpctl", "set-default", String(deviceId)]);
    }

    function toggleMute(target, isMuted) {
        Quickshell.execDetached(["wpctl", "set-mute", target, isMuted ? "0" : "1"]);
    }

    function adjustVolume(target, increase) {
        var args = ["wpctl", "set-volume", target, increase ? "5%+" : "5%-"];
        if (increase)
            args.push("--limit", "1.0");
        Quickshell.execDetached(args);
    }

    Poller {
        id: audioStatus
        command: "wpctl status 2>/dev/null"
        interval: 2000
        onValueChanged: audio.parseDevices(value)
    }

    Poller {
        id: outputVolume
        command: "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{printf \"%d\", $2*100}' || echo 0"
        interval: 700
    }

    Poller {
        id: outputMuted
        command: "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -q MUTED && echo true || echo false"
        interval: 700
    }

    Poller {
        id: inputVolume
        command: "wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | awk '{printf \"%d\", $2*100}' || echo 0"
        interval: 700
    }

    Poller {
        id: inputMuted
        command: "wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null | grep -q MUTED && echo true || echo false"
        interval: 700
    }

    Flickable {
        anchors.fill: parent
        clip: true
        opacity: audio.opened ? 1 : 0
        scale: audio.opened ? 1 : 0.94

        Behavior on opacity {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
        }
        contentWidth: width
        contentHeight: page.implicitHeight + 8
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { }

        ColumnLayout {
            id: page
            width: parent.width
            spacing: 18

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                Rectangle {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    radius: 17
                    color: ThemePalette.Theme.surfaceRaised
                    Text {
                        anchors.centerIn: parent
                        text: "volume_up"
                        color: ThemePalette.Theme.accent
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 25
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: "Audio"
                        color: ThemePalette.Theme.textBright
                        font.family: "Inter"
                        font.pixelSize: 22
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: "Choose your devices and control sound and microphone"
                        color: ThemePalette.Theme.muted
                        font.family: "Inter"
                        font.pixelSize: 11
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: outputCard.implicitHeight + 34
                radius: 22
                color: ThemePalette.Theme.surfaceAlt
                border.width: 1
                border.color: ThemePalette.Theme.border

                ColumnLayout {
                    id: outputCard
                    anchors.fill: parent
                    anchors.margins: 17
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Rectangle {
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 34
                            radius: 12
                            color: ThemePalette.Theme.accentDark
                            Text {
                                anchors.centerIn: parent
                                text: outputMuted.value.trim() === "true" ? "volume_off" : "volume_up"
                                color: ThemePalette.Theme.accent
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 19
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                text: "SOUND OUTPUT"
                                color: ThemePalette.Theme.text
                                font.family: "Inter"
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.letterSpacing: 0.8
                            }
                            Text {
                                text: outputMuted.value.trim() === "true" ? "Sound is muted" : "Playback device"
                                color: ThemePalette.Theme.muted
                                font.family: "Inter"
                                font.pixelSize: 10
                            }
                        }
                        Text {
                            text: outputVolume.value.trim() !== "" ? outputVolume.value.trim() + "%" : "—"
                            color: ThemePalette.Theme.textBright
                            font.family: "Inter"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: audio.defaultDeviceName(outputDevices, "No output device found")
                            color: ThemePalette.Theme.textBright
                            font.family: "Inter"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Rectangle {
                            Layout.preferredWidth: 38
                            Layout.preferredHeight: 38
                            radius: 13
                            color: outputDownHover.containsMouse ? ThemePalette.Theme.surfaceRaised : ThemePalette.Theme.surface
                            Text { anchors.centerIn: parent; text: "remove"; color: ThemePalette.Theme.text; font.family: "Material Symbols Rounded"; font.pixelSize: 19 }
                            MouseArea { id: outputDownHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: audio.adjustVolume("@DEFAULT_AUDIO_SINK@", false) }
                        }
                        Rectangle {
                            Layout.preferredWidth: 38
                            Layout.preferredHeight: 38
                            radius: 13
                            color: outputUpHover.containsMouse ? ThemePalette.Theme.surfaceRaised : ThemePalette.Theme.surface
                            Text { anchors.centerIn: parent; text: "add"; color: ThemePalette.Theme.text; font.family: "Material Symbols Rounded"; font.pixelSize: 19 }
                            MouseArea { id: outputUpHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: audio.adjustVolume("@DEFAULT_AUDIO_SINK@", true) }
                        }
                        Rectangle {
                            Layout.preferredWidth: 126
                            Layout.preferredHeight: 38
                            radius: 13
                            color: outputMuted.value.trim() === "true" ? ThemePalette.Theme.redDark : ThemePalette.Theme.surface
                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 7
                                Text { text: outputMuted.value.trim() === "true" ? "volume_off" : "volume_up"; color: outputMuted.value.trim() === "true" ? ThemePalette.Theme.red : ThemePalette.Theme.text; font.family: "Material Symbols Rounded"; font.pixelSize: 18 }
                                Text { text: outputMuted.value.trim() === "true" ? "Unmute" : "Mute sound"; color: outputMuted.value.trim() === "true" ? ThemePalette.Theme.red : ThemePalette.Theme.text; font.family: "Inter"; font.pixelSize: 10; font.weight: Font.DemiBold }
                            }
                            MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: audio.toggleMute("@DEFAULT_AUDIO_SINK@", outputMuted.value.trim() === "true") }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: ThemePalette.Theme.border }

                    Text {
                        text: "AVAILABLE OUTPUT DEVICES"
                        color: ThemePalette.Theme.mutedStrong
                        font.family: "Inter"
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                    }

                    Repeater {
                        model: outputDevices
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 48
                            radius: 14
                            color: modelData.isDefault ? ThemePalette.Theme.surfaceRaised : outputDeviceHover.containsMouse ? ThemePalette.Theme.surface : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 10
                                spacing: 10
                                Text {
                                    text: /bluetooth|bluez|headphone|headset/i.test(modelData.name) ? "headphones" : "speaker"
                                    color: modelData.isDefault ? ThemePalette.Theme.accent : ThemePalette.Theme.muted
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: 19
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: modelData.isDefault ? ThemePalette.Theme.textBright : ThemePalette.Theme.text
                                    font.family: "Inter"
                                    font.pixelSize: 11
                                    font.weight: modelData.isDefault ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                }
                                Text {
                                    visible: modelData.isDefault
                                    text: "check_circle"
                                    color: ThemePalette.Theme.accent
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: 17
                                }
                            }
                            MouseArea {
                                id: outputDeviceHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: audio.setDefaultDevice(modelData.id)
                            }
                        }
                    }

                    Text {
                        visible: outputDevices.length === 0
                        text: "Connect a speaker or Bluetooth headset to see it here."
                        color: ThemePalette.Theme.muted
                        font.family: "Inter"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: inputCard.implicitHeight + 34
                radius: 22
                color: ThemePalette.Theme.surfaceAlt
                border.width: 1
                border.color: ThemePalette.Theme.border

                ColumnLayout {
                    id: inputCard
                    anchors.fill: parent
                    anchors.margins: 17
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Rectangle {
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 34
                            radius: 12
                            color: ThemePalette.Theme.accentDark
                            Text {
                                anchors.centerIn: parent
                                text: inputMuted.value.trim() === "true" ? "mic_off" : "mic"
                                color: ThemePalette.Theme.accent
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 19
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                text: "MICROPHONE"
                                color: ThemePalette.Theme.text
                                font.family: "Inter"
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.letterSpacing: 0.8
                            }
                            Text {
                                text: inputMuted.value.trim() === "true" ? "Microphone is muted" : "Input device"
                                color: ThemePalette.Theme.muted
                                font.family: "Inter"
                                font.pixelSize: 10
                            }
                        }
                        Text {
                            text: inputVolume.value.trim() !== "" ? inputVolume.value.trim() + "%" : "—"
                            color: ThemePalette.Theme.textBright
                            font.family: "Inter"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: audio.defaultDeviceName(inputDevices, "No microphone found")
                            color: ThemePalette.Theme.textBright
                            font.family: "Inter"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Rectangle {
                            Layout.preferredWidth: 38
                            Layout.preferredHeight: 38
                            radius: 13
                            color: inputDownHover.containsMouse ? ThemePalette.Theme.surfaceRaised : ThemePalette.Theme.surface
                            Text { anchors.centerIn: parent; text: "remove"; color: ThemePalette.Theme.text; font.family: "Material Symbols Rounded"; font.pixelSize: 19 }
                            MouseArea { id: inputDownHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: audio.adjustVolume("@DEFAULT_AUDIO_SOURCE@", false) }
                        }
                        Rectangle {
                            Layout.preferredWidth: 38
                            Layout.preferredHeight: 38
                            radius: 13
                            color: inputUpHover.containsMouse ? ThemePalette.Theme.surfaceRaised : ThemePalette.Theme.surface
                            Text { anchors.centerIn: parent; text: "add"; color: ThemePalette.Theme.text; font.family: "Material Symbols Rounded"; font.pixelSize: 19 }
                            MouseArea { id: inputUpHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: audio.adjustVolume("@DEFAULT_AUDIO_SOURCE@", true) }
                        }
                        Rectangle {
                            Layout.preferredWidth: 126
                            Layout.preferredHeight: 38
                            radius: 13
                            color: inputMuted.value.trim() === "true" ? ThemePalette.Theme.redDark : ThemePalette.Theme.surface
                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 7
                                Text { text: inputMuted.value.trim() === "true" ? "mic_off" : "mic"; color: inputMuted.value.trim() === "true" ? ThemePalette.Theme.red : ThemePalette.Theme.text; font.family: "Material Symbols Rounded"; font.pixelSize: 18 }
                                Text { text: inputMuted.value.trim() === "true" ? "Unmute mic" : "Mute mic"; color: inputMuted.value.trim() === "true" ? ThemePalette.Theme.red : ThemePalette.Theme.text; font.family: "Inter"; font.pixelSize: 10; font.weight: Font.DemiBold }
                            }
                            MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: audio.toggleMute("@DEFAULT_AUDIO_SOURCE@", inputMuted.value.trim() === "true") }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: ThemePalette.Theme.border }

                    Text {
                        text: "AVAILABLE INPUT DEVICES"
                        color: ThemePalette.Theme.mutedStrong
                        font.family: "Inter"
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                    }

                    Repeater {
                        model: inputDevices
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 48
                            radius: 14
                            color: modelData.isDefault ? ThemePalette.Theme.surfaceRaised : inputDeviceHover.containsMouse ? ThemePalette.Theme.surface : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 10
                                spacing: 10
                                Text {
                                    text: /bluetooth|bluez|headphone|headset/i.test(modelData.name) ? "headset_mic" : "mic"
                                    color: modelData.isDefault ? ThemePalette.Theme.accent : ThemePalette.Theme.muted
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: 19
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: modelData.isDefault ? ThemePalette.Theme.textBright : ThemePalette.Theme.text
                                    font.family: "Inter"
                                    font.pixelSize: 11
                                    font.weight: modelData.isDefault ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                }
                                Text {
                                    visible: modelData.isDefault
                                    text: "check_circle"
                                    color: ThemePalette.Theme.accent
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: 17
                                }
                            }
                            MouseArea {
                                id: inputDeviceHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: audio.setDefaultDevice(modelData.id)
                            }
                        }
                    }

                    Text {
                        visible: inputDevices.length === 0
                        text: "No microphone input is currently available."
                        color: ThemePalette.Theme.muted
                        font.family: "Inter"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
