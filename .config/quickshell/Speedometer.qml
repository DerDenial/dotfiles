pragma ComponentBehavior: Bound
import QtQuick
import "Theme" as ThemePalette

Item {
    id: dial
    objectName: "speedometer"
    property var value: null
    property real maximum: 100
    property string phase: "idle"
    property bool running: false
    readonly property bool hasValue: typeof value === "number" && Number.isFinite(value) && value >= 0
    readonly property real targetValue: hasValue ? Math.max(0, value) : 0
    readonly property real targetFraction: Math.min(1, targetValue / Math.max(1, maximum))
    // Follow bursty samples on each rendered frame instead of restarting an
    // easing curve for every 200 ms sample. Scale changes retain the needle pose.
    property real smoothedValue: 0
    property real needleFraction: 0
    readonly property bool livePhase: running && (phase === "download" || phase === "upload")
    readonly property real displayValue: phase === "complete" ? targetValue : smoothedValue
    readonly property bool motionActive: motion.running
    readonly property bool needsMotion: Math.abs(smoothedValue - targetValue) > 0.025
        || Math.abs(needleFraction - targetFraction) > 0.0001
    readonly property real fraction: Math.max(0, Math.min(1, needleFraction))
    property color accent: phase === "upload" ? ThemePalette.Theme.green : ThemePalette.Theme.accent
    property color trackColor: ThemePalette.Theme.surfaceRaised
    property color tickColor: ThemePalette.Theme.mutedStrong
    readonly property string phaseLabel: phase === "latency" ? "MEASURING LATENCY"
        : phase === "download" ? "DOWNLOAD" : phase === "upload" ? "UPLOAD"
        : phase === "complete" ? "TEST COMPLETE" : phase === "cancelled" ? "TEST CANCELLED"
        : phase === "error" ? "TEST UNAVAILABLE" : "READY WHEN YOU ARE"
    implicitWidth: 440
    implicitHeight: 252
    onPhaseChanged: {
        // Start a fresh rate filter for each measurement, but keep angular
        // continuity when switching from download to upload or final results.
        if (phase === "idle" || phase === "latency" || phase === "download" || phase === "upload")
            smoothedValue = 0;
    }
    onVisibleChanged: if (!visible) {
        smoothedValue = targetValue;
        needleFraction = targetFraction;
    }
    FrameAnimation {
        id: motion
        running: dial.visible && dial.needsMotion
        onTriggered: {
            const dt = Math.max(0, Math.min(0.05, frameTime));
            const alpha = 1 - Math.exp(-dt / (dial.livePhase ? 0.55 : 0.25));
            const rate = dial.smoothedValue + (dial.targetValue - dial.smoothedValue) * alpha;
            const angle = dial.needleFraction + (dial.targetFraction - dial.needleFraction) * alpha;
            dial.smoothedValue = Math.abs(rate - dial.targetValue) <= 0.025 ? dial.targetValue : rate;
            dial.needleFraction = Math.abs(angle - dial.targetFraction) <= 0.0001 ? dial.targetFraction : angle;
        }
    }
    onFractionChanged: face.requestPaint()
    onMaximumChanged: face.requestPaint()
    onAccentChanged: face.requestPaint()
    onTrackColorChanged: face.requestPaint()
    onTickColorChanged: face.requestPaint()
    onWidthChanged: face.requestPaint()
    onHeightChanged: face.requestPaint()
    Canvas {
        id: face
        anchors.fill: parent
        renderTarget: Canvas.Image
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const cx = width / 2, cy = 145, radius = Math.min(133, width / 2 - 26);
            const start = 145 * Math.PI / 180, sweep = 250 * Math.PI / 180;
            const end = start + sweep;
            ctx.lineCap = "round";
            ctx.lineWidth = 8;
            ctx.strokeStyle = dial.trackColor;
            ctx.beginPath(); ctx.arc(cx, cy, radius, start, end); ctx.stroke();
            if (dial.fraction > 0.001) {
                ctx.strokeStyle = dial.accent;
                ctx.beginPath(); ctx.arc(cx, cy, radius, start, start + sweep * dial.fraction); ctx.stroke();
            }
            ctx.lineCap = "butt";
            for (let i = 0; i <= 40; ++i) {
                const angle = start + sweep * i / 40;
                const major = i % 10 === 0;
                const outer = radius - 13, inner = outer - (major ? 10 : 4);
                ctx.strokeStyle = i / 40 <= dial.fraction && dial.hasValue ? dial.accent : dial.tickColor;
                ctx.lineWidth = major ? 1.5 : 1;
                ctx.globalAlpha = major ? 0.9 : 0.44;
                ctx.beginPath(); ctx.moveTo(cx + Math.cos(angle) * inner, cy + Math.sin(angle) * inner);
                ctx.lineTo(cx + Math.cos(angle) * outer, cy + Math.sin(angle) * outer); ctx.stroke();
            }
            ctx.globalAlpha = 1;
            const angle = start + sweep * dial.fraction;
            const point = radius - 4;
            ctx.fillStyle = dial.accent;
            ctx.beginPath(); ctx.arc(cx + Math.cos(angle) * point, cy + Math.sin(angle) * point, 4.5, 0, Math.PI * 2); ctx.fill();
            // A short tapered needle leaves the central reading unobstructed.
            const needleTip = radius - 27, needleBase = radius - 48;
            ctx.beginPath();
            ctx.moveTo(cx + Math.cos(angle) * needleTip, cy + Math.sin(angle) * needleTip);
            ctx.lineTo(cx + Math.cos(angle) * needleBase + Math.sin(angle) * 3, cy + Math.sin(angle) * needleBase - Math.cos(angle) * 3);
            ctx.lineTo(cx + Math.cos(angle) * needleBase - Math.sin(angle) * 3, cy + Math.sin(angle) * needleBase + Math.cos(angle) * 3);
            ctx.closePath(); ctx.fill();
        }
    }
    Repeater {
        model: 5
        delegate: Text {
            required property int index
            readonly property real angle: (145 + 250 * index / 4) * Math.PI / 180
            readonly property real ringRadius: Math.min(133, dial.width / 2 - 26) - 36
            x: dial.width / 2 + Math.cos(angle) * ringRadius - width / 2
            y: 145 + Math.sin(angle) * ringRadius - height / 2
            text: Number(dial.maximum * index / 4).toLocaleString(Qt.locale("en_US"), "f", 0)
            color: ThemePalette.Theme.mutedStrong
            font.family: "Inter"; font.pixelSize: 9; font.weight: Font.Medium
        }
    }
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 102
        spacing: 2
        Text {
            objectName: "speedometerValue"
            anchors.horizontalCenter: parent.horizontalCenter
            text: dial.hasValue ? Number(dial.displayValue).toFixed(dial.displayValue >= 100 ? 0 : 1) : "—"
            color: ThemePalette.Theme.textBright
            font.family: "Inter"; font.pixelSize: 43; font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Mbps"
            color: ThemePalette.Theme.muted
            font.family: "Inter"; font.pixelSize: 11; font.weight: Font.Medium
        }
    }
    Text {
        objectName: "speedometerPhase"
        anchors.horizontalCenter: parent.horizontalCenter
        y: 218
        text: dial.phaseLabel
        color: dial.running || dial.phase === "complete" ? dial.accent : ThemePalette.Theme.muted
        font.family: "Inter"; font.pixelSize: 9; font.weight: Font.DemiBold; font.letterSpacing: 1.1
    }
}
