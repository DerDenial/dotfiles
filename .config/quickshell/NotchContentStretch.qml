import QtQuick

// Transform a fixed canvas with the notch, without relayout or a separate fade.
Scale {
    id: stretch
    required property NotchTransition transition
    required property real canvasWidth
    property real horizontalInset: 0
    property bool compact: false

    // Only the compact header paints during the final few pixels of rebound.
    readonly property real unfold: transition.dropdown ? 1 : Math.max(0, Math.min(1.06,
        (transition.motion.surfaceHeight - 42) / Math.max(1, transition.expandedHeight - 42)))
    readonly property real fold: transition.dropdown ? 0 : 1 - transition.motion.smoothstep(0, 0.24, transition.motion.amount)

    origin.x: canvasWidth / 2
    origin.y: 0
    xScale: transition.dropdown ? 1 : Math.max(0.001,
        (transition.motion.surfaceWidth - horizontalInset) / Math.max(1, canvasWidth))
    yScale: transition.dropdown ? (compact ? 0 : 1) : compact ? fold : unfold
}
