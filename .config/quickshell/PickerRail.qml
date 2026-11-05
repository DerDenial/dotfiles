import QtQuick

ListView {
    id: rail

    required property real tileWidth
    property bool animateSelection: false
    property bool navigationEnabled: true
    property color selectionColor: "white"
    property rect selectionRect: Qt.rect(0, 0, 0, 0)
    property bool selectionReady: false
    property bool pendingSelectionSnap: true
    property real selectionRadius: 18
    readonly property int selectionDuration: 180

    signal indexPicked(int index)
    signal stepRequested(int direction)

    readonly property real centerInset: (width - tileWidth) / 2
    property bool ready: false
    property bool positionHeld: false
    property bool userMoving: false
    property real wheelRemainder: 0
    property bool wheelUsesPixels: false

    orientation: ListView.Horizontal
    spacing: 12
    leftMargin: centerInset
    rightMargin: centerInset
    clip: true
    cacheBuffer: 0
    focus: false
    activeFocusOnTab: false
    keyNavigationEnabled: false
    interactive: navigationEnabled && count > 1
    boundsBehavior: Flickable.StopAtBounds
    snapMode: ListView.NoSnap
    highlightRangeMode: ListView.NoHighlightRange
    highlightFollowsCurrentItem: false

    // Store targets in content coordinates. Scrolling then carries the frame
    // and its tail with the cards, without restarting either animation.
    function queueSelection(snap) {
        pendingSelectionSnap = pendingSelectionSnap || !!snap;
        // A pending centering step updates the outline in the same frame.
        if (deferredCenter.running) return;
        selectionUpdate.restart();
    }

    function updateSelection() {
        if (!ready) return;
        if (count < 1 || currentIndex < 0) {
            selectionReady = false;
            pendingSelectionSnap = true;
            return;
        }
        const tile = currentItem;
        // A newly selected offscreen delegate can appear on the next layout.
        // Keep the last drawn target until its actual item is available.
        if (!tile || tile.index !== currentIndex || tile.width <= 8 || tile.height <= 8) return;
        const topLeft = tile.mapToItem(contentItem, 4, 4);
        const bottomRight = tile.mapToItem(contentItem, tile.width - 4, tile.height - 4);
        const reset = pendingSelectionSnap || !selectionReady || !animateSelection;
        selectionRadius = 18 * Math.min(1, Math.abs(tile.scale));
        selectionRect = Qt.rect(topLeft.x, topLeft.y,
            bottomRight.x - topLeft.x, bottomRight.y - topLeft.y);
        selectionReady = true;
        if (reset) selectionFrame.snap();
        pendingSelectionSnap = false;
    }

    SelectionTrail {
        id: selectionFrame
        objectName: "pickerSelectionTrail"
        parent: rail.contentItem
        z: 10
        width: rail.contentWidth
        height: rail.height
        targetRect: rail.selectionRect
        radius: rail.selectionRadius
        engaged: rail.selectionReady && rail.count > 0 && rail.currentIndex >= 0
        animate: rail.animateSelection
        accentColor: rail.selectionColor
        outlineOnly: true
        borderWidth: 2
        headDuration: rail.selectionDuration
        tailDuration: 220
        headEasing: Easing.OutBack
        headOvershoot: 0.45
        echoCount: 2
        echoOpacity: 0.45
        maxTrailLength: 18
    }

    Timer {
        id: selectionUpdate
        interval: 0
        onTriggered: rail.updateSelection()
    }

    Connections {
        target: rail.currentItem
        function onXChanged() { rail.queueSelection(false); }
        function onYChanged() { rail.queueSelection(false); }
        function onWidthChanged() { rail.queueSelection(true); }
        function onHeightChanged() { rail.queueSelection(true); }
        function onScaleChanged() { rail.queueSelection(true); }
    }

    // The controller owns currentIndex. Only this imperative path moves the rail;
    // ListView's native highlight scrolling must not compete with the animation.
    function centerCurrent(animated) {
        deferredCenter.stop();
        if (!ready || positionHeld || width <= 0 || tileWidth <= 0 || dragging)
            return;

        centerAnimation.stop();
        userMoving = false;
        cancelFlick();

        // Create the selected delegate before starting either animation. The
        // frame and the scroll share a start frame, duration and easing curve.
        forceLayout();
        selectionUpdate.stop();
        deferredCenter.stop();
        const snapSelection = pendingSelectionSnap || !selectionReady || !animateSelection;
        updateSelection();

        const index = count > 0 ? Math.max(0, Math.min(currentIndex, count - 1)) : 0;
        const destination = originX + index * (tileWidth + spacing) - centerInset;
        const shouldAnimate = navigationEnabled && animateSelection
            && (animated === undefined || animated) && count > 0 && !snapSelection;

        if (shouldAnimate && Math.abs(contentX - destination) > 0.5) {
            centerAnimation.from = contentX;
            centerAnimation.to = destination;
            centerAnimation.start();
        } else {
            contentX = destination;
        }
    }

    function queueCenter(animated) {
        if (!ready || positionHeld || dragging || flicking)
            return;
        deferredCenter.animated = !!animated;
        deferredCenter.restart();
    }

    function stopMotion() {
        const heldX = contentX;
        deferredCenter.stop();
        centerAnimation.stop();
        userMoving = false;
        cancelFlick();
        contentX = heldX;
    }

    function consumeWheel(event, horizontal) {
        event.accepted = true;
        if (count < 1)
            return;

        if (flicking) {
            userMoving = false;
            cancelFlick();
        }

        const pixelDelta = horizontal ? event.pixelDelta.x : event.pixelDelta.y;
        const angleDelta = horizontal ? event.angleDelta.x : event.angleDelta.y;
        const usePixels = pixelDelta !== 0;
        const delta = usePixels ? pixelDelta : angleDelta;
        if (delta === 0)
            return;

        if (wheelUsesPixels !== usePixels
            || (wheelRemainder !== 0 && Math.sign(wheelRemainder) !== Math.sign(delta))) {
            wheelRemainder = 0;
        }
        wheelUsesPixels = usePixels;
        wheelRemainder += delta;
        wheelReset.restart();

        const threshold = usePixels ? 48 : 120;
        while (Math.abs(wheelRemainder) >= threshold) {
            const direction = wheelRemainder < 0 ? 1 : -1;
            wheelRemainder += direction * threshold;
            stepRequested(direction);
        }
    }

    onCurrentIndexChanged: queueCenter(animateSelection)
    onCurrentItemChanged: queueSelection(false)
    onCountChanged: { queueCenter(false); queueSelection(true); }
    onModelChanged: { queueCenter(false); queueSelection(true); }
    onOriginXChanged: { queueCenter(false); queueSelection(true); }
    onWidthChanged: { queueCenter(false); queueSelection(true); }
    onHeightChanged: queueSelection(true)
    onTileWidthChanged: { queueCenter(false); queueSelection(true); }
    onSpacingChanged: { queueCenter(false); queueSelection(true); }
    onAnimateSelectionChanged: {
        if (!animateSelection) stopMotion();
    }
    onNavigationEnabledChanged: {
        wheelRemainder = 0;
        wheelReset.stop();
        positionHeld = !navigationEnabled;
        stopMotion();
        // Closing and page changes keep the last rendered position throughout
        // the morph. Reopening aligns it before interaction resumes.
        if (navigationEnabled) { queueCenter(false); queueSelection(true); }
    }
    onDraggingChanged: {
        if (dragging) {
            deferredCenter.stop();
            centerAnimation.stop();
            userMoving = true;
            wheelRemainder = 0;
        }
    }
    onFlickStarted: {
        deferredCenter.stop();
        centerAnimation.stop();
        userMoving = true;
    }
    onMovementEnded: {
        if (!userMoving)
            return;
        userMoving = false;
        if (!navigationEnabled || count < 1)
            return;

        const nearest = Math.max(0, Math.min(count - 1,
            Math.round((contentX - originX + centerInset) / (tileWidth + spacing))));
        indexPicked(nearest);
        // Let the controller update its selection before centering it.
        queueCenter(animateSelection);
    }

    Component.onCompleted: {
        ready = true;
        // Inactive pages also need a valid initial layout before first reveal.
        positionHeld = false;
        queueCenter(false);
        queueSelection(true);
    }

    Timer {
        id: deferredCenter
        interval: 0
        property bool animated: false
        onTriggered: rail.centerCurrent(animated)
    }

    NumberAnimation {
        id: centerAnimation
        objectName: "pickerCenterMotion"
        target: rail
        property: "contentX"
        duration: rail.selectionDuration
        easing.type: Easing.OutBack
        easing.overshoot: 0.45
    }

    Timer {
        id: wheelReset
        interval: 180
        onTriggered: rail.wheelRemainder = 0
    }

    WheelHandler {
        enabled: rail.navigationEnabled
        target: null
        orientation: Qt.Vertical
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        blocking: true
        onWheel: function(event) { rail.consumeWheel(event, false); }
    }

    WheelHandler {
        enabled: rail.navigationEnabled
        target: null
        orientation: Qt.Horizontal
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        blocking: true
        onWheel: function(event) { rail.consumeWheel(event, true); }
    }
}
