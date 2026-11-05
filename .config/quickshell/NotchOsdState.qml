import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Observe the actual system state; controls and hardware shortcuts keep their own owners.
QtObject {
    id: state

    property bool blocked: false
    property bool active: false
    property string kind: "volume"
    property string title: "Volume"
    property string iconName: "volume_up"
    property real level: 0
    property int percentage: 0
    property bool muted: false
    readonly property real requestedWidth: 340
    readonly property real requestedHeight: 66

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var outputAudio: sink && sink.ready ? sink.audio : null
    readonly property var inputAudio: source && source.ready ? source.audio : null

    property bool armed: false
    property bool outputBaseline: false
    property bool inputBaseline: false
    property int lastOutputPercent: -1
    property int lastInputPercent: -1
    property bool lastOutputMuted: false
    property bool lastInputMuted: false
    property string backlightPath: ""
    property real backlightMaximum: 0
    property real lastBrightness: -1

    property PwObjectTracker tracker: PwObjectTracker {
        objects: [state.sink, state.source].filter(function(node) { return node !== null; })
    }

    onBlockedChanged: {
        if (blocked) {
            active = false;
            dismissTimer.stop();
        }
    }
    onOutputAudioChanged: {
        outputBaseline = false;
        outputSettle.restart();
    }
    onInputAudioChanged: {
        inputBaseline = false;
        inputSettle.restart();
    }

    function present(nextKind, nextTitle, nextIcon, nextLevel, nextPercentage, nextMuted) {
        if (!armed || blocked) return;
        kind = nextKind;
        title = nextTitle;
        iconName = nextIcon;
        level = Math.max(0, Math.min(1, nextLevel));
        percentage = nextPercentage;
        muted = nextMuted;
        active = true;
        dismissTimer.restart();
    }

    function observeAudio(isInput, announce) {
        var audio = isInput ? inputAudio : outputAudio;
        if (!audio) return;
        var percent = Math.round(audio.volume * 100);
        if (!Number.isFinite(percent)) return;
        var nextMuted = audio.muted;
        var baseline = isInput ? inputBaseline : outputBaseline;
        var changed = baseline && (percent !== (isInput ? lastInputPercent : lastOutputPercent)
            || nextMuted !== (isInput ? lastInputMuted : lastOutputMuted));
        if (isInput) {
            inputBaseline = true;
            lastInputPercent = percent;
            lastInputMuted = nextMuted;
        } else {
            outputBaseline = true;
            lastOutputPercent = percent;
            lastOutputMuted = nextMuted;
        }
        if (changed && announce) {
            present(isInput ? "microphone" : "volume",
                isInput ? (nextMuted ? "Microphone muted" : "Microphone") : (nextMuted ? "Sound muted" : "Volume"),
                isInput ? (nextMuted ? "mic_off" : "mic") : (nextMuted ? "volume_off" : (percent < 40 ? "volume_down" : "volume_up")),
                audio.volume, percent, nextMuted);
        }
    }

    function observeBrightness(value) {
        if (!(backlightMaximum > 0) || !Number.isFinite(value) || value < 0) return;
        var previous = lastBrightness;
        lastBrightness = value;
        if (previous < 0 || value === previous) return;
        var fraction = Math.max(0, Math.min(1, value / backlightMaximum));
        present("brightness", "Brightness", "brightness_6", fraction, Math.round(fraction * 100), false);
    }

    function refreshBrightness() {
        if (backlightPath) brightnessFile.reload();
        else if (!backlightDiscovery.running) backlightDiscovery.running = true;
    }

    property Connections outputChanges: Connections {
        target: state.outputAudio
        function onVolumesChanged() { outputDebounce.restart(); }
        function onMutedChanged() { outputDebounce.restart(); }
    }
    property Connections inputChanges: Connections {
        target: state.inputAudio
        function onVolumesChanged() { inputDebounce.restart(); }
        function onMutedChanged() { inputDebounce.restart(); }
    }
    property Timer outputDebounce: Timer {
        interval: 18
        onTriggered: if (!outputSettle.running) state.observeAudio(false, true)
    }
    property Timer inputDebounce: Timer {
        interval: 18
        onTriggered: if (!inputSettle.running) state.observeAudio(true, true)
    }
    // New audio devices and shell reloads establish a baseline, never an OSD banner.
    property Timer outputSettle: Timer {
        interval: 300
        onTriggered: state.observeAudio(false, false)
    }
    property Timer inputSettle: Timer {
        interval: 300
        onTriggered: state.observeAudio(true, false)
    }
    property Timer startup: Timer {
        interval: 1200
        running: true
        onTriggered: {
            state.observeAudio(false, false);
            state.observeAudio(true, false);
            state.armed = true;
        }
    }
    property Timer dismissTimer: Timer {
        interval: 1400
        onTriggered: state.active = false
    }

    property Process backlightDiscovery: Process {
        running: true
        command: ["python3", Quickshell.shellPath("Osd/backlight.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text);
                    if (data.path && data.maximum > 0) {
                        state.lastBrightness = Number(data.current);
                        state.backlightMaximum = data.maximum;
                        state.backlightPath = data.path;
                    }
                } catch (error) { /* No backlight means there is no brightness OSD. */ }
            }
        }
    }
    property FileView brightnessFile: FileView {
        path: state.backlightPath
        printErrors: false
        preload: true
        onLoaded: {
            var value = brightnessFile.text().trim();
            if (value.length) state.observeBrightness(Number(value));
        }
        onLoadFailed: {
            state.lastBrightness = -1;
            state.backlightPath = "";
        }
    }
    property Timer brightnessPoll: Timer {
        interval: 400
        repeat: true
        running: state.backlightPath.length > 0
        onTriggered: brightnessFile.reload()
    }
    property Timer backlightRetry: Timer {
        interval: 10000
        repeat: true
        running: state.backlightPath.length === 0
        onTriggered: if (!backlightDiscovery.running) backlightDiscovery.running = true
    }

    property IpcHandler ipc: IpcHandler {
        target: "notchOsd"
        function brightness(): void { state.refreshBrightness(); }
        function volume(): void { outputDebounce.restart(); }
        function microphone(): void { inputDebounce.restart(); }
    }
}
