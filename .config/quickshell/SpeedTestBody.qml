pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "Theme" as ThemePalette

Flickable {
    id: body
    objectName: "speedTestBody"
    property var controller: null
    property string hotkeyText: "Super + Alt + S"
    readonly property var sample: controller ? controller.snapshot : ({ phase: "idle", progress: 0 })
    readonly property string phase: sample.phase || "idle"
    readonly property bool running: !!controller && controller.running
    readonly property var dialValue: phase === "complete" ? sample.downloadMbps : sample.liveMbps
    readonly property var liveDisplay: valid(sample.liveMbps) && speedDial ? speedDial.smoothedValue : null
    property real dialMaximum: 100
    readonly property string statusText: phase === "latency" ? "Finding your connection’s response time…"
        : phase === "download" ? "Measuring download speed…" : phase === "upload" ? "Measuring upload speed…"
        : phase === "complete" ? "Your connection, measured."
        : phase === "cancelled" ? "Stopped. Start again whenever you’re ready."
        : phase === "error" ? String(sample.error || "The test could not finish. Please try again.")
        : "Measure your internet connection."
    signal closeRequested()
    function resetScroll() { contentY = 0; }
    function valid(value) { return typeof value === "number" && Number.isFinite(value) && value >= 0; }
    function display(value, unit) { return valid(value) ? Number(value).toFixed(unit === "ms" ? 0 : value >= 100 ? 0 : 1) : "—"; }
    function scaleFor(value) {
        for (const scale of [100, 250, 500, 1000, 2500, 5000, 10000]) if (value <= scale * 0.75) return scale;
        return Math.ceil(value / 0.75 / 10000) * 10000;
    }
    function updateScale() {
        const value = sample.phase === "complete" ? sample.downloadMbps : speedDial ? speedDial.smoothedValue : null;
        if (valid(value) && value > dialMaximum * 0.82) dialMaximum = scaleFor(value);
    }
    function startOrCancel() {
        if (!controller) return;
        if (running) controller.cancel();
        else { dialMaximum = 100; controller.start(); }
    }
    onDialValueChanged: if (phase === "complete") updateScale()
    onPhaseChanged: {
        if (phase === "idle" || phase === "latency" || phase === "download" || phase === "upload") dialMaximum = 100;
        if (phase === "complete") updateScale();
    }
    contentWidth: width
    contentHeight: stack.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height + 1
    flickableDirection: Flickable.VerticalFlick
    ScrollBar.vertical: ScrollBar { policy: body.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff; width: 3 }

    component Metric: Rectangle {
        id: metric
        property string label: ""
        property string symbol: ""
        property string unit: "Mbps"
        property var value: null
        property bool selected: false
        width: (body.width - 24) / 4
        height: 82
        radius: 15
        color: selected ? ThemePalette.Theme.accentSoft : ThemePalette.Theme.surface
        border.width: 1
        border.color: selected ? Qt.alpha(ThemePalette.Theme.accent, 0.4) : Qt.alpha(ThemePalette.Theme.border, 0.25)
        Row {
            x: 11; y: 11; spacing: 4
            Text { text: metric.symbol; font.family: "Material Symbols Rounded"; font.pixelSize: 14; color: metric.selected ? ThemePalette.Theme.accent : ThemePalette.Theme.muted }
            Text { text: metric.label; font.family: "Inter"; font.pixelSize: 9; font.weight: Font.Medium; color: ThemePalette.Theme.muted; anchors.verticalCenter: parent.verticalCenter }
        }
        Text {
            objectName: metric.objectName + "Value"
            x: 12; y: 34; width: parent.width - 24
            text: body.display(metric.value, metric.unit)
            font.family: "Inter"; font.pixelSize: 21; font.weight: Font.DemiBold
            color: ThemePalette.Theme.textBright
            elide: Text.ElideRight
        }
        Text { x: 12; y: 61; text: metric.unit; font.family: "Inter"; font.pixelSize: 9; color: ThemePalette.Theme.mutedStrong }
    }
    Column {
        id: stack
        width: parent.width
        spacing: 12
        Item {
            width: parent.width; height: 44
            Text { text: "CONNECTION"; font.family: "Inter"; font.pixelSize: 9; font.weight: Font.DemiBold; font.letterSpacing: 1.2; color: ThemePalette.Theme.mutedStrong }
            Text { y: 15; text: "Speed test"; font.family: "Inter"; font.pixelSize: 21; font.weight: Font.DemiBold; color: ThemePalette.Theme.textBright }
            ToolButton {
                id: closeButton
                objectName: "closeSpeedTest"
                anchors.right: parent.right; y: 2; width: 34; height: 34
                Accessible.name: "Close speed test"
                contentItem: Text { text: "close"; font.family: "Material Symbols Rounded"; font.pixelSize: 20; color: ThemePalette.Theme.muted; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 12; color: closeButton.hovered ? ThemePalette.Theme.surfaceRaised : ThemePalette.Theme.surface }
                ToolTip.visible: hovered
                ToolTip.text: body.hotkeyText + " · Esc to close"
                onClicked: body.closeRequested()
            }
        }
        Speedometer {
            id: speedDial
            objectName: "speedTestDial"
            width: parent.width
            height: 252
            value: body.dialValue
            maximum: body.dialMaximum
            phase: body.phase
            running: body.running
            onSmoothedValueChanged: body.updateScale()
        }
        Row {
            width: parent.width; spacing: 8
            Metric { objectName: "downloadMetric"; label: "Download"; symbol: "south"; value: body.phase === "download" ? body.liveDisplay : body.sample.downloadMbps; selected: body.phase === "download" }
            Metric { objectName: "uploadMetric"; label: "Upload"; symbol: "north"; value: body.phase === "upload" ? body.liveDisplay : body.sample.uploadMbps; selected: body.phase === "upload" }
            Metric { objectName: "pingMetric"; label: "Ping"; symbol: "schedule"; value: body.sample.latencyMs; unit: "ms"; selected: body.phase === "latency" }
            Metric { objectName: "jitterMetric"; label: "Jitter"; symbol: "graphic_eq"; value: body.sample.jitterMs; unit: "ms" }
        }
        Column {
            width: parent.width; spacing: 10
            Rectangle {
                width: parent.width; height: 3; radius: 2
                color: ThemePalette.Theme.surfaceRaised
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, Number(body.sample.progress) || 0))
                    height: parent.height; radius: parent.radius; color: ThemePalette.Theme.accent
                    Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                }
            }
            Text {
                objectName: "speedTestStatus"
                width: parent.width
                text: body.statusText; textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: body.phase === "error" ? ThemePalette.Theme.red : ThemePalette.Theme.muted
                font.family: "Inter"; font.pixelSize: 11
            }
            Button {
                id: actionButton
                objectName: "speedTestAction"
                anchors.horizontalCenter: parent.horizontalCenter
                width: 150; height: 37
                Accessible.name: body.running ? "Cancel speed test" : body.phase === "idle" ? "Start speed test" : "Run speed test again"
                contentItem: Row {
                    spacing: 7
                    Text { text: body.running ? "stop" : "speed"; font.family: "Material Symbols Rounded"; font.pixelSize: 18; color: body.running ? ThemePalette.Theme.text : ThemePalette.Theme.onAccent; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: body.running ? "Cancel test" : body.phase === "idle" ? "Start test" : "Run again"; font.family: "Inter"; font.pixelSize: 11; font.weight: Font.DemiBold; color: body.running ? ThemePalette.Theme.text : ThemePalette.Theme.onAccent; anchors.verticalCenter: parent.verticalCenter }
                }
                leftPadding: 23; rightPadding: 16
                background: Rectangle { radius: 13; color: body.running ? actionButton.hovered ? ThemePalette.Theme.surfaceRaised : ThemePalette.Theme.surface : ThemePalette.Theme.accent; border.width: body.running ? 1 : 0; border.color: ThemePalette.Theme.border }
                onClicked: body.startOrCancel()
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Cloudflare · up to 250 MB per test"
                color: ThemePalette.Theme.mutedStrong
                font.family: "Inter"; font.pixelSize: 9
            }
        }
    }
}
