import QtQuick

// One geometry timeline: reversals always start at the currently rendered shape.
QtObject {
    id: motion
    property real fromWidth: 236
    property real fromHeight: 34
    property real fromRadius: 17
    property real toWidth: 236
    property real toHeight: 34
    property real toRadius: 17
    property real fromAmount: 0
    property real toAmount: 0
    property real progress: 1
    property bool expanding: false
    property int duration: 320
    property var curve: [0.2, 0.7, 0.3, 1, 1, 1]
    readonly property bool running: timeline.running
    readonly property real surfaceWidth: fromWidth + (toWidth - fromWidth) * progress
    readonly property real surfaceHeight: fromHeight + (toHeight - fromHeight) * progress
    readonly property real radius: fromRadius + (toRadius - fromRadius) * progress
    readonly property real amount: Math.max(0, Math.min(1, fromAmount + (toAmount - fromAmount) * progress))
    readonly property real contentOpacity: smoothstep(0.22, 0.72, amount)
    readonly property real compactOpacity: 1 - smoothstep(0, 0.18, amount)
    signal settled()

    function smoothstep(low, high, value) {
        var t = Math.max(0, Math.min(1, (value - low) / (high - low)));
        return t * t * (3 - 2 * t);
    }
    function snap(width, height, radius, amount) {
        timeline.stop();
        fromWidth = toWidth = width;
        fromHeight = toHeight = height;
        fromRadius = toRadius = radius;
        fromAmount = toAmount = amount;
        progress = 1;
    }
    function freeze() { snap(surfaceWidth, surfaceHeight, radius, amount); }
    function moveTo(width, height, radius, amount, expand) {
        var currentWidth = surfaceWidth, currentHeight = surfaceHeight;
        var currentRadius = motion.radius, currentAmount = motion.amount;
        timeline.stop();
        fromWidth = currentWidth; fromHeight = currentHeight; fromRadius = currentRadius;
        fromAmount = currentAmount;
        toWidth = width; toHeight = height; toRadius = radius; toAmount = amount;
        expanding = expand;
        var distance = Math.max(Math.abs(width - currentWidth), Math.abs(height - currentHeight));
        if (distance < 0.1 && Math.abs(amount - currentAmount) < 0.001) {
            progress = 1;
            Qt.callLater(function() { if (!timeline.running) motion.settled(); });
            return;
        }
        // Respond early, then settle with a small rebound bounded in pixels.
        var overshoot = Math.min(0.035, 5 / Math.max(1, distance));
        var cushion = Math.min(0.012, 1.2 / Math.max(1, distance));
        var rebound = Math.min(0.04, 3 / Math.max(1, distance));
        curve = expand
            ? [0.12, 0.78, 0.28, 1 + overshoot, 0.60, 1 + overshoot,
               0.74, 1 + overshoot, 0.88, 1, 1, 1]
            : [0.14, 0.54, 0.30, 1 - cushion, 0.60, 1 - cushion,
               0.68, 1 - cushion, 0.74, 1 - rebound, 0.82, 1 - rebound,
               0.90, 1 - rebound, 0.96, 1, 1, 1];
        // Short resizes and reversals should not replay a full menu-length motion.
        var travel = Math.max(distance, Math.abs(amount - currentAmount) * 120);
        var distanceScale = Math.min(1, Math.sqrt(travel / 320));
        duration = Math.round(Math.max(expand ? 180 : 140, (expand ? 320 : 240) * distanceScale));
        progress = 0;
        timeline.start();
    }
    property NumberAnimation timeline: NumberAnimation {
        target: motion
        property: "progress"
        from: 0; to: 1
        duration: motion.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: motion.curve
        onFinished: motion.settled()
    }
}
