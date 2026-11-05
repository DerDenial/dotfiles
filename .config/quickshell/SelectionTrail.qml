pragma ComponentBehavior: Bound
import QtQuick

// One animated rectangle across icon cells and full-width result rows.
Item {
    id: trail

    property rect targetRect: Qt.rect(0, 0, 0, 0)
    property bool engaged: false
    property bool animate: true
    property color accentColor: "white"
    property color surfaceColor: "transparent"
    property real radius: 16
    property bool leadingAccent: false
    property bool outlineOnly: false
    property real borderWidth: 1
    property int headDuration: 220
    property int tailDuration: 310
    property int headEasing: Easing.BezierSpline
    property real headOvershoot: 0.45
    property int echoCount: 4
    property real echoOpacity: 1
    property real maxTrailLength: 0

    property bool initialized: false
    property bool componentReady: false
    property rect headStart: Qt.rect(0, 0, 0, 0)
    property rect tailStart: Qt.rect(0, 0, 0, 0)
    property rect destination: Qt.rect(0, 0, 0, 0)
    property real headStartRadius: 16
    property real tailStartRadius: 16
    property real destinationRadius: 16
    property real headProgress: 1
    property real tailProgress: 1
    property var headCurve: [0.1, 0.78, 0.28, 1.02, 0.6, 1.02, 0.74, 1.02, 0.88, 1, 1, 1]

    readonly property real headX: headStart.x + (destination.x - headStart.x) * headProgress
    readonly property real headY: headStart.y + (destination.y - headStart.y) * headProgress
    readonly property real headWidth: Math.max(0, headStart.width + (destination.width - headStart.width) * headProgress)
    readonly property real headHeight: Math.max(0, headStart.height + (destination.height - headStart.height) * headProgress)
    readonly property real headRadius: Math.max(0, headStartRadius + (destinationRadius - headStartRadius) * headProgress)
    readonly property real tailX: tailStart.x + (destination.x - tailStart.x) * tailProgress
    readonly property real tailY: tailStart.y + (destination.y - tailStart.y) * tailProgress
    readonly property real tailWidth: Math.max(0, tailStart.width + (destination.width - tailStart.width) * tailProgress)
    readonly property real tailHeight: Math.max(0, tailStart.height + (destination.height - tailStart.height) * tailProgress)
    readonly property real tailRadius: Math.max(0, tailStartRadius + (destinationRadius - tailStartRadius) * tailProgress)
    readonly property real deltaX: headX - tailX
    readonly property real deltaY: headY - tailY
    readonly property real deltaWidth: headWidth - tailWidth
    readonly property real deltaHeight: headHeight - tailHeight
    readonly property real distance: Math.sqrt(deltaX * deltaX + deltaY * deltaY
        + deltaWidth * deltaWidth * 0.25 + deltaHeight * deltaHeight * 0.25)
    // Bound the smear by the small side, so a full-width row never leaves a
    // viewport-long tail during wrapping or a grid-to-list morph.
    readonly property real tailScale: Math.min(1,
        (maxTrailLength > 0 ? maxTrailLength : Math.max(24, Math.min(headWidth, headHeight) * 1.3))
        / Math.max(1, distance))
    readonly property real smearStrength: engaged && animate ? Math.min(1, distance / 16) : 0

    function snap() {
        if (!componentReady) return;
        headMotion.stop();
        tailMotion.stop();
        headStart = tailStart = destination = targetRect;
        headStartRadius = tailStartRadius = destinationRadius = radius;
        headProgress = tailProgress = 1;
        initialized = true;
    }

    function followTarget() {
        if (!componentReady || !engaged) return;
        if (!animate || !initialized) {
            snap();
            return;
        }
        // Capture every rendered dimension before stopping the previous motion.
        // Repeated keys and reversals therefore continue without a geometry jump.
        const currentHead = Qt.rect(headX, headY, headWidth, headHeight);
        const currentTail = Qt.rect(tailX, tailY, tailWidth, tailHeight);
        const currentHeadRadius = headRadius;
        const currentTailRadius = tailRadius;
        const travel = Math.max(Math.abs(targetRect.x - headX), Math.abs(targetRect.y - headY),
            Math.abs(targetRect.width - headWidth), Math.abs(targetRect.height - headHeight),
            Math.abs(radius - headRadius));
        headMotion.stop();
        tailMotion.stop();
        if (travel < 0.1) {
            snap();
            return;
        }
        headStart = currentHead;
        tailStart = currentTail;
        destination = targetRect;
        headStartRadius = currentHeadRadius;
        tailStartRadius = currentTailRadius;
        destinationRadius = radius;
        // The rebound is limited to two pixels even across a wide row or a
        // large keyboard wrap; ordinary steps get a small visible settle.
        const overshoot = Math.min(0.045, 2 / Math.max(1, travel));
        headCurve = [0.10, 0.78, 0.28, 1 + overshoot, 0.60, 1 + overshoot,
                     0.74, 1 + overshoot, 0.88, 1, 1, 1];
        headProgress = tailProgress = 0;
        headMotion.start();
        tailMotion.start();
    }

    Component.onCompleted: {
        componentReady = true;
        snap();
    }
    onTargetRectChanged: followTarget()
    onRadiusChanged: followTarget()
    onEngagedChanged: {
        if (!componentReady) return;
        if (engaged) snap();
        else {
            headMotion.stop();
            tailMotion.stop();
        }
    }
    onAnimateChanged: if (componentReady && !animate) snap()

    opacity: engaged ? 1 : 0
    visible: opacity > 0.001
    Behavior on opacity {
        enabled: trail.animate
        NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
    }

    Repeater {
        model: Math.max(0, trail.echoCount)
        delegate: Rectangle {
            required property int index
            readonly property real lag: (1 - index / Math.max(1, trail.echoCount)) * trail.tailScale
            x: trail.headX - trail.deltaX * lag
            y: trail.headY - trail.deltaY * lag
            width: Math.max(0, trail.headWidth - trail.deltaWidth * lag)
            height: Math.max(0, trail.headHeight - trail.deltaHeight * lag)
            radius: Math.max(0, trail.headRadius - (trail.headRadius - trail.tailRadius) * lag)
            color: trail.outlineOnly ? "transparent" : trail.accentColor
            border.width: trail.outlineOnly ? trail.borderWidth : 0
            border.color: trail.accentColor
            opacity: trail.echoOpacity * trail.smearStrength * (trail.outlineOnly
                ? 0.13 + index * 0.075 : 0.035 + index * 0.025)
        }
    }

    Rectangle {
        objectName: "selectionHead"
        x: trail.headX
        y: trail.headY
        width: trail.headWidth
        height: trail.headHeight
        radius: trail.headRadius
        color: trail.outlineOnly ? "transparent"
            : Qt.tint(trail.surfaceColor, Qt.rgba(trail.accentColor.r, trail.accentColor.g, trail.accentColor.b, 0.10))
        border.width: trail.borderWidth
        border.color: Qt.rgba(trail.accentColor.r, trail.accentColor.g, trail.accentColor.b, trail.outlineOnly ? 0.95 : 0.30)

        Rectangle {
            x: 0
            y: 16
            width: 3
            height: Math.max(0, parent.height - 32)
            radius: 2
            color: trail.accentColor
            opacity: trail.leadingAccent ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 100 } }
        }
    }

    NumberAnimation {
        id: headMotion
        objectName: "selectionHeadMotion"
        target: trail
        property: "headProgress"
        from: 0
        to: 1
        duration: trail.headDuration
        easing.type: trail.headEasing
        easing.overshoot: trail.headOvershoot
        easing.bezierCurve: trail.headEasing === Easing.BezierSpline ? trail.headCurve : []
    }
    NumberAnimation {
        id: tailMotion
        target: trail
        property: "tailProgress"
        from: 0
        to: 1
        duration: trail.tailDuration
        easing.type: Easing.OutCubic
    }
}
