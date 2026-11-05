import QtQuick

// A notch still morphs. A full-width taskbar keeps its own surface and opens
// a separate, fixed-size dropdown below it instead of stretching its texture.
Rectangle {
    id: menu
    required property NotchTransition transition
    readonly property real alignment: Math.max(0, Math.min(1, transition.dropdownAlignment))
    readonly property real reveal: transition.dropdownReveal
    readonly property real availableWidth: parent ? parent.width : width

    // Dropdown motion starts at its final width/height. Later content resizes
    // can still interpolate without changing the dimensions of its text.
    width: transition.motion.surfaceWidth
    height: transition.motion.surfaceHeight
    x: transition.dropdown
        ? 16 + Math.max(0, availableWidth - width - 32) * alignment
        : (availableWidth - width) / 2
    y: transition.dropdown ? 42 - 12 * (1 - reveal) : 0
    topLeftRadius: transition.dropdown ? 24 : 0
    topRightRadius: topLeftRadius
    bottomLeftRadius: transition.dropdown ? 24 : Math.max(0, transition.motion.radius)
    bottomRightRadius: bottomLeftRadius
    opacity: transition.dropdown ? transition.motion.amount
        : transition.preparing && transition.snapshot !== null && !transition.snapshotReady ? 0 : 1
    clip: true

    transform: Scale {
        origin.x: menu.width * menu.alignment
        origin.y: 0
        xScale: menu.transition.dropdown ? 0.985 + 0.015 * menu.reveal : 1
        yScale: xScale
    }
}
