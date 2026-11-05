import QtQuick
import QtQuick.Window

// Keeps the source notch painted until the new surface has rendered its first frame.
QtObject {
    id: transition
    property Item surface: null
    property Item sourceNotch: null
    property real expandedWidth: 560
    property real expandedHeight: 440
    property bool canOpen: true
    property bool pendingOpen: false
    property bool opened: false
    property bool closing: false
    property bool capturePending: false
    property bool preparing: false
    property bool returning: false
    property bool snapshotReady: false
    property var snapshot: null
    // Capture dimensions must stay fixed: each moveTo replaces motion.from*.
    property real snapshotWidth: 236
    property real snapshotHeight: 34
    property bool snapshotWide: false
    // Taskbar menus retain their own card while the source bar stays painted.
    // Latch the presentation for the entire open/close cycle, including reversals.
    property bool dropdown: false
    property real dropdownAlignment: 0.5
    readonly property real dropdownReveal: motion.fromAmount
        + (motion.toAmount - motion.fromAmount) * motion.progress
    readonly property bool sourceWide: sourceNotch && sourceNotch["edgeTaskbar"] === true
    readonly property bool wideReturn: snapshotWide && snapshot !== null && sourceWide
    readonly property real returnWidth: dropdown ? expandedWidth : wideReturn ? Math.max(1, sourceNotch.width) : 236
    readonly property real returnHeight: dropdown ? expandedHeight : wideReturn ? Math.max(1, sourceNotch.height) : 34
    readonly property real returnRadius: dropdown ? 24 : wideReturn ? Math.max(0, sourceNotch.bottomLeftRadius) : 17
    property int generation: 0
    property int returnedFrames: 0
    readonly property bool active: opened || closing || capturePending || preparing || returning
    readonly property bool visible: opened || closing || preparing || returning
    readonly property bool ownsSurface: !dropdown && (opened || (closing && !returning))
    property NotchMotion motion: NotchMotion {
        onSettled: {
            if (!transition.opened && transition.closing) {
                if (transition.dropdown) {
                    transition.finishClose();
                    return;
                }
                transition.returnedFrames = 0;
                transition.returning = true;
                if (transition.sourceNotch && transition.sourceNotch.Window.window)
                    transition.sourceNotch.Window.window.update();
                else transition.finishClose();
            }
        }
    }
    signal aboutToOpen()
    signal activated()

    function open() {
        if (opened || capturePending || preparing) return;
        aboutToOpen();
        if (!canOpen) { pendingOpen = true; return; }
        reveal();
    }
    function reveal() {
        pendingOpen = false;
        watchdog.stop();
        if (closing || returning) {
            // A wide source image also paints the return header after reversals.
            if (!wideReturn) snapshot = null;
            opened = true;
            returning = closing = false;
            motion.moveTo(expandedWidth, expandedHeight, dropdown ? 24 : 28, 1, true);
            activated();
            return;
        }
        dropdown = sourceWide;
        var width = sourceNotch ? sourceNotch.width : 236;
        var height = sourceNotch ? sourceNotch.height : 34;
        var radius = sourceNotch ? sourceNotch.bottomLeftRadius : 17;
        var wide = sourceWide;
        var ticket = ++generation;
        snapshotReady = false;
        capturePending = true;
        if (dropdown) {
            prepare(null, expandedWidth, expandedHeight, 24, false);
            return;
        }
        if (sourceNotch && sourceNotch.visible) {
            var captured = sourceNotch.grabToImage(function(result) {
                if (ticket === transition.generation && transition.capturePending)
                    transition.prepare(result, width, height, radius, wide);
            });
            if (captured) return;
        }
        prepare(null, width, height, radius, wide);
    }
    function prepare(image, width, height, radius, wide) {
        // Without a source texture the existing compact renderer is the fallback.
        if (dropdown) {
            width = expandedWidth; height = expandedHeight; radius = 24;
            image = null; wide = false;
        } else if (!image && wide) { width = 236; height = 34; radius = 17; }
        snapshotWidth = width;
        snapshotHeight = height;
        snapshotWide = !!image && wide;
        motion.snap(width, height, radius, 0);
        snapshot = image;
        preparing = true;
        capturePending = false;
        if (surface && surface.Window.window) surface.Window.window.update();
    }
    function beginOpen() {
        opened = true;
        preparing = false;
        motion.moveTo(expandedWidth, expandedHeight, dropdown ? 24 : 28, 1, true);
        activated();
    }
    function close() {
        pendingOpen = false;
        ++generation;
        if (capturePending || preparing) {
            capturePending = preparing = false;
            snapshot = null;
            snapshotWide = false;
            dropdown = false;
            return;
        }
        if (!opened) return;
        closing = true;
        opened = false;
        // A contained rebound approaches the compact size from above; never through it.
        motion.moveTo(returnWidth, returnHeight, returnRadius, 0, false);
        watchdog.restart();
    }
    function finishClose() {
        watchdog.stop();
        closing = false;
        returning = false;
        snapshot = null;
        snapshotWide = false;
        dropdown = false;
    }
    function toggle() { opened || pendingOpen || capturePending || preparing ? close() : open(); }
    onCanOpenChanged: if (canOpen && pendingOpen) reveal()

    property Connections painted: Connections {
        target: transition.surface ? transition.surface.Window.window : null
        function onFrameSwapped() {
            if (transition.preparing && (!transition.snapshot || transition.snapshotReady))
                transition.beginOpen();
        }
    }
    property Connections returned: Connections {
        target: transition.sourceNotch ? transition.sourceNotch.Window.window : null
        function onFrameSwapped() {
            if (!transition.returning) return;
            if (++transition.returnedFrames >= 2) transition.finishClose();
            else transition.sourceNotch.Window.window.update();
        }
    }
    property Timer watchdog: Timer {
        interval: 900
        onTriggered: {
            if (!transition.opened && transition.closing) {
                transition.motion.snap(transition.returnWidth, transition.returnHeight, transition.returnRadius, 0);
                transition.finishClose();
            }
        }
    }
}
