import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Services.Pipewire
import "../Theme" as ThemeApi

SPage {
    id: page

    readonly property var output: Pipewire.defaultAudioSink
    readonly property var input: Pipewire.defaultAudioSource
    readonly property var outputDevices: audioNodes(false, true)
    readonly property var inputDevices: audioNodes(false, false)
    readonly property var streams: audioNodes(true, false)
    property bool microphoneTest: false

    property PwObjectTracker audioTracker: PwObjectTracker {
        objects: page.active ? Pipewire.nodes.values : []
    }

    property PwNodePeakMonitor microphoneMonitor: PwNodePeakMonitor {
        node: page.input
        enabled: page.active && page.microphoneTest && page.input !== null
    }

    onActiveChanged: if (!active) microphoneTest = false
    onInputChanged: microphoneTest = false

    function audioNodes(wantStreams, wantSink) {
        return Pipewire.nodes.values.filter(function(node) {
            return node.audio !== null && node.isStream === wantStreams
                && (wantStreams || node.isSink === wantSink);
        });
    }

    function nodeName(node) {
        if (!node) return "No device connected";
        return node.description || node.nickname || node.name || "Audio device";
    }

    function streamName(node) {
        if (!node) return "Application";
        var properties = node.properties || {};
        return properties["application.name"] || properties["application.process.binary"]
            || node.description || node.name || "Application";
    }

    function percent(node) {
        return node && node.ready && node.audio ? Math.round(node.audio.volume * 100) : 0;
    }

    function isMuted(node) {
        return Boolean(node && node.ready && node.audio && node.audio.muted);
    }

    function canControl(node) {
        return Boolean(Pipewire.ready && node && node.ready && node.audio);
    }

    function adjust(node, delta) {
        if (!canControl(node)) return;
        var next = Math.max(0, node.audio.volume + delta);
        node.audio.volume = delta > 0 ? Math.min(1, next) : next;
    }

    function toggleMute(node) {
        if (canControl(node)) node.audio.muted = !node.audio.muted;
    }

    function selectDevice(node, isInput) {
        if (!node || !node.ready) return;
        if (isInput) Pipewire.preferredDefaultAudioSource = node;
        else Pipewire.preferredDefaultAudioSink = node;
        if (controller) controller.toast(nodeName(node) + " selected");
    }

    function deviceDetail(node, isInput) {
        if (!node) return "";
        var isDefault = isInput ? page.input === node : page.output === node;
        var properties = node.properties || {};
        var bus = properties["device.api"] === "bluez5" || properties["api.bluez5.address"]
            ? "Bluetooth" : properties["device.bus"] === "usb" ? "USB" : "";
        return [isDefault ? "Current device" : "Available", bus].filter(function(value) {
            return value.length > 0;
        }).join(" · ");
    }

    SNotice {
        Layout.fillWidth: true
        visible: !Pipewire.ready
        warning: true
        text: "The audio service is unavailable. Devices and controls will appear when PipeWire reconnects."
    }

    SCard {
        Layout.fillWidth: true
        title: "Sound output"
        subtitle: page.nodeName(page.output)
        iconName: page.isMuted(page.output) ? "volume_off" : "volume_up"

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: page.canControl(page.output) ? page.percent(page.output) + "%" : "—"
                    color: ThemeApi.Theme.textBright
                    font.family: "Inter"
                    font.pixelSize: 38
                    font.weight: Font.DemiBold
                }

                SLabel {
                    text: page.isMuted(page.output) ? "Sound is muted" : "Master volume"
                    color: page.isMuted(page.output) ? ThemeApi.Theme.muted : ThemeApi.Theme.accent
                }
            }

            SButton {
                text: "−"
                enabled: page.canControl(page.output) && page.percent(page.output) > 0
                onClicked: page.adjust(page.output, -0.05)
                ToolTip.visible: hovered
                ToolTip.text: "Decrease by 5%"
            }

            SButton {
                text: "+"
                enabled: page.canControl(page.output) && page.percent(page.output) < 100
                onClicked: page.adjust(page.output, 0.05)
                ToolTip.visible: hovered
                ToolTip.text: "Increase by 5%"
            }

            SButton {
                text: page.isMuted(page.output) ? "Unmute" : "Mute"
                iconName: page.isMuted(page.output) ? "volume_up" : "volume_off"
                accent: page.isMuted(page.output)
                enabled: page.canControl(page.output)
                onClicked: page.toggleMute(page.output)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: ThemeApi.Theme.border
        }

        Repeater {
            model: page.outputDevices
            delegate: SRow {
                required property var modelData
                Layout.fillWidth: true
                title: page.nodeName(modelData)
                subtitle: page.deviceDetail(modelData, false)
                iconName: modelData.name.indexOf("bluez") >= 0 ? "headphones" : "speaker"
                value: page.output === modelData ? "Selected" : ""
                interactive: true
                enabled: modelData.ready
                onClicked: page.selectDevice(modelData, false)
            }
        }

        SLabel {
            Layout.fillWidth: true
            visible: page.outputDevices.length === 0
            text: "No output device detected. Connect speakers, headphones or a Bluetooth audio device."
            wrapMode: Text.WordWrap
            color: ThemeApi.Theme.muted
        }
    }

    SCard {
        Layout.fillWidth: true
        title: "Microphone"
        subtitle: page.nodeName(page.input)
        iconName: page.isMuted(page.input) ? "mic_off" : "mic"

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: page.canControl(page.input) ? page.percent(page.input) + "%" : "—"
                    color: ThemeApi.Theme.textBright
                    font.family: "Inter"
                    font.pixelSize: 38
                    font.weight: Font.DemiBold
                }

                SLabel {
                    text: page.isMuted(page.input) ? "Microphone is muted" : "Input gain"
                    color: page.isMuted(page.input) ? ThemeApi.Theme.muted : ThemeApi.Theme.accent
                }
            }

            SButton {
                text: "−"
                enabled: page.canControl(page.input) && page.percent(page.input) > 0
                onClicked: page.adjust(page.input, -0.05)
                ToolTip.visible: hovered
                ToolTip.text: "Decrease by 5%"
            }

            SButton {
                text: "+"
                enabled: page.canControl(page.input) && page.percent(page.input) < 100
                onClicked: page.adjust(page.input, 0.05)
                ToolTip.visible: hovered
                ToolTip.text: "Increase by 5%"
            }

            SButton {
                text: page.isMuted(page.input) ? "Unmute" : "Mute mic"
                iconName: page.isMuted(page.input) ? "mic" : "mic_off"
                accent: page.isMuted(page.input)
                enabled: page.canControl(page.input)
                onClicked: page.toggleMute(page.input)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: ThemeApi.Theme.border
        }

        Repeater {
            model: page.inputDevices
            delegate: SRow {
                required property var modelData
                Layout.fillWidth: true
                title: page.nodeName(modelData)
                subtitle: page.deviceDetail(modelData, true)
                iconName: modelData.name.indexOf("bluez") >= 0 ? "headset_mic" : "mic"
                value: page.input === modelData ? "Selected" : ""
                interactive: true
                enabled: modelData.ready
                onClicked: page.selectDevice(modelData, true)
            }
        }

        SLabel {
            Layout.fillWidth: true
            visible: page.inputDevices.length === 0
            text: "No microphone detected. Connect an input device to record or join calls."
            wrapMode: Text.WordWrap
            color: ThemeApi.Theme.muted
        }

        SRow {
            Layout.fillWidth: true
            title: "Check your microphone"
            subtitle: page.microphoneTest ? "Listening locally · nothing is recorded" : "Start the input level meter when you need it"
            iconName: "graphic_eq"

            SButton {
                text: page.microphoneTest ? "Stop test" : "Start test"
                accent: page.microphoneTest
                enabled: page.canControl(page.input)
                onClicked: page.microphoneTest = !page.microphoneTest
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: page.microphoneTest
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 8
                radius: 4
                color: ThemeApi.Theme.surfaceRaised

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, page.microphoneMonitor.peak))
                    height: parent.height
                    radius: parent.radius
                    color: ThemeApi.Theme.accent
                    Behavior on width { NumberAnimation { duration: 70; easing.type: Easing.OutCubic } }
                }
            }

            SLabel {
                Layout.fillWidth: true
                text: page.isMuted(page.input) ? "Your microphone is muted. Unmute it to check the level." : "Speak normally. Adjust input gain if the meter is constantly full or barely moves."
                wrapMode: Text.WordWrap
                color: ThemeApi.Theme.muted
            }
        }
    }

    SCard {
        Layout.fillWidth: true
        title: "Applications"
        subtitle: "Live playback and microphone streams"
        iconName: "apps"

        Repeater {
            model: page.streams

            delegate: SRow {
                required property var modelData
                readonly property bool capture: modelData.isSink
                Layout.fillWidth: true
                title: page.streamName(modelData)
                subtitle: (capture ? "Microphone" : "Playback") + " · " + page.percent(modelData) + "%"
                    + (page.isMuted(modelData) ? " · Muted" : "")
                iconName: capture ? "mic" : "music_note"

                SButton {
                    text: "−"
                    enabled: page.canControl(modelData) && page.percent(modelData) > 0
                    onClicked: page.adjust(modelData, -0.05)
                    ToolTip.visible: hovered
                    ToolTip.text: "Decrease by 5%"
                }

                SButton {
                    text: "+"
                    enabled: page.canControl(modelData) && page.percent(modelData) < 100
                    onClicked: page.adjust(modelData, 0.05)
                    ToolTip.visible: hovered
                    ToolTip.text: "Increase by 5%"
                }

                SButton {
                    iconName: page.isMuted(modelData) ? capture ? "mic_off" : "volume_off" : capture ? "mic" : "volume_up"
                    accent: page.isMuted(modelData)
                    enabled: page.canControl(modelData)
                    onClicked: page.toggleMute(modelData)
                    ToolTip.visible: hovered
                    ToolTip.text: page.isMuted(modelData) ? "Unmute application" : "Mute application"
                }
            }
        }

        SRow {
            Layout.fillWidth: true
            visible: page.streams.length === 0
            title: "No active applications"
            subtitle: "Apps appear here when they play sound or use a microphone."
            iconName: "music_off"
        }
    }
}
