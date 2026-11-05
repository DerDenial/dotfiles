import QtQuick

Flickable {
    id: root
    property bool kineticEnabled: true
    flickDeceleration: 1600
    maximumFlickVelocity: 1800
    pixelAligned: false

    property real releaseVelocity: 0
    property double sampleTime: 0
    property bool systemMomentum: false
    property bool ownCoast: false

    function stopScrollMotion() {
        if (releaseDelay) releaseDelay.stop();
        releaseVelocity = 0;
        sampleTime = 0;
        systemMomentum = false;
        ownCoast = false;
        cancelFlick();
    }
    function stopOwnCoast() {
        if (!ownCoast) return;
        ownCoast = false;
        cancelFlick();
    }
    function observeWheel(event) {
        // Native content and child controls handle the actual wheel delta.
        // This observer only supplies the missing release phase afterwards.
        if (event.phase === Qt.NoScrollPhase) {
            // Ordinary wheels already have a native easing animation. A second
            // delayed tail could otherwise restart it after a stopping click.
            releaseDelay.stop();
            stopOwnCoast();
            releaseVelocity = 0;
            sampleTime = 0;
            systemMomentum = false;
            return;
        }
        if (event.phase === Qt.ScrollBegin) {
            stopScrollMotion();
        }
        if (event.phase === Qt.ScrollMomentum) {
            releaseDelay.stop();
            stopOwnCoast();
            systemMomentum = true;
            releaseVelocity = 0;
            return;
        }
        if (event.phase === Qt.ScrollEnd) {
            releaseDelay.stop();
            if (!systemMomentum && sampleTime > 0) {
                releaseDelay.interval = 1;
                releaseDelay.restart();
            }
            return;
        }

        const pixels = event.pixelDelta;
        const angle = event.angleDelta;
        const dy = pixels.y !== 0 ? pixels.y : angle.y;
        const dx = pixels.x !== 0 ? pixels.x : angle.x;
        if (dy === 0 || Math.abs(dx) > Math.abs(dy)) {
            releaseDelay.stop();
            releaseVelocity = 0;
            return;
        }
        stopOwnCoast();
        releaseDelay.stop();
        const now = Date.now();
        const elapsed = sampleTime > 0 ? now - sampleTime : 16;
        const continuous = sampleTime > 0 && elapsed < 100 && !systemMomentum;
        const speed = pixels.y !== 0
            ? dy * 1000 / Math.max(8, Math.min(50, elapsed || 16))
            : dy / 120 * 320;
        const sameDirection = continuous && releaseVelocity * speed > 0;
        releaseVelocity = Math.max(-1200, Math.min(1200,
            sameDirection ? releaseVelocity * 0.4 + speed * 0.6 : speed));
        sampleTime = now;
        systemMomentum = false;
    }
    function releaseCoast() {
        if (!kineticEnabled || !interactive || !visible || !enabled || dragging
                || systemMomentum || flicking || Date.now() - sampleTime > 130)
            return;
        const speed = releaseVelocity;
        releaseVelocity = 0;
        sampleTime = 0;
        if (Math.abs(speed) < 80 || (speed > 0 && atYBeginning) || (speed < 0 && atYEnd))
            return;
        ownCoast = true;
        flick(0, speed);
    }

    onFlickEnded: ownCoast = false
    onDraggingChanged: {
        if (dragging) {
            releaseDelay.stop();
            releaseVelocity = 0;
            sampleTime = 0;
        } else if (sampleTime > 0 && !systemMomentum && kineticEnabled) {
            // Also cover platforms that omit a zero-delta end notification
            // from pointer handlers but end the native drag normally.
            releaseDelay.interval = 1;
            releaseDelay.restart();
        }
    }
    onKineticEnabledChanged: if (!kineticEnabled) stopScrollMotion()
    onVisibleChanged: if (!visible) stopScrollMotion()
    onEnabledChanged: if (!enabled) stopScrollMotion()
    onInteractiveChanged: if (!interactive) stopScrollMotion()

    property Timer releaseDelay: Timer {
        interval: 1
        onTriggered: root.releaseCoast()
    }
    property WheelHandler coastObserver: WheelHandler {
        parent: root
        target: null
        blocking: false
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        acceptedModifiers: Qt.NoModifier
        enabled: root.kineticEnabled && root.interactive && root.visible && root.enabled
        onWheel: event => root.observeWheel(event)
    }
    property TapHandler pressObserver: TapHandler {
        parent: root
        target: null
        enabled: root.kineticEnabled && root.interactive
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressedChanged: if (pressed) root.stopScrollMotion()
    }
}
