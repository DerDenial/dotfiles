pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Theme" as ThemeApi

FocusScope {
    id: editor

    required property url source
    required property real imageWidth
    required property real imageHeight
    property bool busy: false
    property string errorText: ""
    property string appName: ""
    property string tool: "pen"
    property string selectedColor: String(ThemeApi.Theme.accent)
    property real brushWidth: 4
    property var commands: []
    property int historyIndex: 0
    property var draft: null
    property bool componentReady: false
    property url loadedSource: ""
    property bool actualSize: false
    readonly property var editState: effectiveEdit()
    readonly property bool canUndo: historyIndex > 0
    readonly property bool canRedo: historyIndex < commands.length
    readonly property bool hasEdits: editState.operations.length > 0 || editState.crop !== null
    readonly property real fitScale: Math.max(0.001, Math.min(1,
        Math.max(1, width - 80) / Math.max(1, imageWidth),
        Math.max(1, height - toolbar.height - 184) / Math.max(1, imageHeight)))
    readonly property real displayScale: actualSize ? 1 : fitScale

    signal copyRequested(var edit)
    signal saveRequested(var edit)
    signal dismissed()
    signal newCaptureRequested()

    focus: true

    function effectiveEdit() {
        let operations = [];
        let crop = null;
        for (let i = 0; i < historyIndex; ++i) {
            const command = commands[i];
            if (command.type === "reset") { operations = []; crop = null; }
            else if (command.type === "crop") crop = {x: command.x, y: command.y, width: command.width, height: command.height};
            else operations.push(command);
        }
        return {operations: operations, crop: crop};
    }

    function commit(command) {
        if (busy || !command || historyIndex >= 40) return;
        commands = commands.slice(0, historyIndex).concat([JSON.parse(JSON.stringify(command))]);
        historyIndex = commands.length;
        drawing.requestPaint();
    }

    function undo() { if (!busy && canUndo) { draft = null; --historyIndex; drawing.requestPaint(); } }
    function redo() { if (!busy && canRedo) { draft = null; ++historyIndex; drawing.requestPaint(); } }
    function reset() {
        if (busy || !hasEdits) return;
        if (historyIndex >= 40) { commands = []; historyIndex = 0; draft = null; }
        else commit({type: "reset"});
        drawing.requestPaint();
    }

    function loadSource() {
        if (!componentReady || !drawing.available || !String(source)) return;
        if (String(loadedSource) !== String(source)) {
            if (String(loadedSource)) drawing.unloadImage(loadedSource);
            loadedSource = source;
            actualSize = false;
            commands = [];
            historyIndex = 0;
            draft = null;
        }
        if (!drawing.isImageLoaded(source) && !drawing.isImageLoading(source)) drawing.loadImage(source);
        drawing.requestPaint();
    }

    function pointAt(x, y) {
        // MouseArea coordinates already account for the Canvas view transform.
        return {x: Math.max(0, Math.min(imageWidth, x)),
                y: Math.max(0, Math.min(imageHeight, y))};
    }

    function centerPreview() {
        Qt.callLater(function() {
            imageViewport.contentX = Math.max(0, Math.round((imageViewport.contentWidth - imageViewport.width) / 2));
            imageViewport.contentY = Math.max(0, Math.round((imageViewport.contentHeight - imageViewport.height) / 2));
        });
    }

    function panImage(wheel) {
        if (!actualSize) { wheel.accepted = false; return; }
        const deltaX = wheel.pixelDelta.x || wheel.angleDelta.x / 2;
        const deltaY = wheel.pixelDelta.y || wheel.angleDelta.y / 2;
        if (wheel.modifiers & Qt.ShiftModifier)
            imageViewport.contentX = Math.max(0, Math.min(imageViewport.contentWidth - imageViewport.width,
                imageViewport.contentX - deltaY - deltaX));
        else {
            imageViewport.contentX = Math.max(0, Math.min(imageViewport.contentWidth - imageViewport.width,
                imageViewport.contentX - deltaX));
            imageViewport.contentY = Math.max(0, Math.min(imageViewport.contentHeight - imageViewport.height,
                imageViewport.contentY - deltaY));
        }
        wheel.accepted = true;
    }

    function rectangleBetween(a, b) {
        return {x: Math.min(a.x, b.x), y: Math.min(a.y, b.y),
                width: Math.abs(a.x - b.x), height: Math.abs(a.y - b.y)};
    }

    function beginGesture(x, y) {
        if (busy || historyIndex >= 40 || !drawing.isImageLoaded(source)) return;
        forceActiveFocus();
        const point = pointAt(x, y);
        draft = tool === "pen"
            ? {type: "pen", points: [point], color: selectedColor, width: brushWidth}
            : {type: tool, start: point, end: point, color: selectedColor, opacity: 0.32, blockSize: 16};
        drawing.requestPaint();
    }

    function moveGesture(x, y) {
        if (!draft) return;
        const point = pointAt(x, y);
        if (draft.type === "pen") {
            const previous = draft.points[draft.points.length - 1];
            if (draft.points.length < 3000 && Math.hypot(point.x - previous.x, point.y - previous.y) >= 0.65 / displayScale)
                draft.points.push(point);
        } else draft.end = point;
        drawing.requestPaint();
    }

    function endGesture(x, y) {
        if (!draft) return;
        moveGesture(x, y);
        let operation = draft;
        if (draft.type !== "pen") {
            const rect = rectangleBetween(draft.start, draft.end);
            operation = Object.assign({type: draft.type, color: draft.color, opacity: draft.opacity, blockSize: 16}, rect);
            if (rect.width < 2 || rect.height < 2) operation = null;
        }
        draft = null;
        commit(operation);
        drawing.requestPaint();
    }

    function cancelGesture() { draft = null; drawing.requestPaint(); }
    function exportEdit(save) {
        if (busy || draft || !drawing.isImageLoaded(source)) return;
        const value = JSON.parse(JSON.stringify(editState));
        if (save) saveRequested(value); else copyRequested(value);
    }

    function paintOperation(ctx, operation) {
        const scale = 1;
        ctx.save();
        if (operation.type === "pen") {
            const points = operation.points;
            ctx.strokeStyle = operation.color;
            ctx.fillStyle = operation.color;
            ctx.lineWidth = operation.width * scale;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            ctx.beginPath();
            if (points.length === 1) {
                ctx.arc(points[0].x * scale, points[0].y * scale, operation.width * scale / 2, 0, Math.PI * 2);
                ctx.fill();
            } else if (points.length > 1) {
                ctx.moveTo(points[0].x * scale, points[0].y * scale);
                for (let i = 1; i < points.length; ++i) ctx.lineTo(points[i].x * scale, points[i].y * scale);
                ctx.stroke();
            }
        } else if (operation.type === "highlight") {
            ctx.globalAlpha = operation.opacity;
            ctx.fillStyle = operation.color;
            ctx.fillRect(operation.x * scale, operation.y * scale, operation.width * scale, operation.height * scale);
        } else if (operation.type === "pixelate") {
            const x = Math.max(0, Math.floor(operation.x * scale));
            const y = Math.max(0, Math.floor(operation.y * scale));
            const w = Math.max(0, Math.min(drawing.width, Math.ceil((operation.x + operation.width) * scale)) - x);
            const h = Math.max(0, Math.min(drawing.height, Math.ceil((operation.y + operation.height) * scale)) - y);
            if (w > 0 && h > 0) {
                const pixels = ctx.getImageData(x, y, w, h);
                const step = Math.max(1, operation.blockSize * scale);
                ctx.beginPath(); ctx.rect(x, y, w, h); ctx.clip();
                for (let by = 0; by < h; by += step) {
                    for (let bx = 0; bx < w; bx += step) {
                        const sampleX = Math.min(w - 1, Math.floor(bx + Math.min(step, w - bx) / 2));
                        const sampleY = Math.min(h - 1, Math.floor(by + Math.min(step, h - by) / 2));
                        const at = (sampleY * w + sampleX) * 4;
                        ctx.fillStyle = Qt.rgba(pixels.data[at] / 255, pixels.data[at + 1] / 255,
                            pixels.data[at + 2] / 255, pixels.data[at + 3] / 255);
                        ctx.fillRect(x + bx, y + by, Math.ceil(step), Math.ceil(step));
                    }
                }
            }
        }
        ctx.restore();
    }

    function paintCrop(ctx, crop) {
        const x = crop.x, y = crop.y;
        const w = crop.width, h = crop.height;
        ctx.save();
        ctx.fillStyle = Qt.rgba(0, 0, 0, 0.56);
        ctx.fillRect(0, 0, drawing.width, y);
        ctx.fillRect(0, y + h, drawing.width, drawing.height - y - h);
        ctx.fillRect(0, y, x, h);
        ctx.fillRect(x + w, y, drawing.width - x - w, h);
        ctx.strokeStyle = String(ThemeApi.Theme.accent);
        ctx.lineWidth = 1.5 / displayScale;
        ctx.strokeRect(x, y, w, h);
        ctx.fillStyle = String(ThemeApi.Theme.accent);
        for (const point of [{x:x,y:y},{x:x+w,y:y},{x:x,y:y+h},{x:x+w,y:y+h}])
            ctx.fillRect(point.x - 3 / displayScale, point.y - 3 / displayScale,
                6 / displayScale, 6 / displayScale);
        ctx.restore();
    }

    onSourceChanged: loadSource()
    onDisplayScaleChanged: if (componentReady) drawing.requestPaint()
    onEditStateChanged: if (componentReady) drawing.requestPaint()
    onActualSizeChanged: if (componentReady) { cancelGesture(); centerPreview(); }
    Component.onCompleted: { componentReady = true; loadSource(); forceActiveFocus(); }

    Keys.onPressed: event => {
        const control = !!(event.modifiers & Qt.ControlModifier);
        if (event.key === Qt.Key_Escape) { if (draft) cancelGesture(); else dismissed(); }
        else if (control && event.key === Qt.Key_Z) { if (event.modifiers & Qt.ShiftModifier) redo(); else undo(); }
        else if (control && event.key === Qt.Key_Y) redo();
        else if (control && event.key === Qt.Key_C) { if (!event.isAutoRepeat) exportEdit(false); }
        else if (control && event.key === Qt.Key_S) { if (!event.isAutoRepeat) exportEdit(true); }
        else if (control && event.key === Qt.Key_1) actualSize = true;
        else if (control && event.key === Qt.Key_0) actualSize = false;
        else if (!control && event.key === Qt.Key_C) tool = "crop";
        else if (!control && event.key === Qt.Key_B) tool = "pen";
        else if (!control && event.key === Qt.Key_H) tool = "highlight";
        else if (!control && event.key === Qt.Key_P) tool = "pixelate";
        else return;
        event.accepted = true;
    }

    component IconButton: ToolButton {
        id: button
        property string symbol: ""
        property string tip: ""
        property bool selected: false
        implicitWidth: 36
        implicitHeight: 36
        focusPolicy: Qt.NoFocus
        Accessible.name: tip
        ToolTip.visible: hovered
        ToolTip.delay: 500
        ToolTip.text: tip
        contentItem: Text {
            text: button.symbol
            font.family: "Material Symbols Rounded"
            font.pixelSize: 20
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: button.selected ? ThemeApi.Theme.accent : ThemeApi.Theme.text
            opacity: button.enabled ? 1 : 0.35
        }
        background: Rectangle {
            radius: 10
            color: button.selected ? ThemeApi.Theme.accentSoft : button.hovered ? ThemeApi.Theme.surfaceRaised : "transparent"
        }
    }

    Item {
        id: workspace
        anchors.fill: parent
        anchors.topMargin: 44
        anchors.bottomMargin: toolbar.height + 88

        Flickable {
            id: imageViewport
            anchors.fill: parent
            contentWidth: Math.max(width, previewFrame.width)
            contentHeight: Math.max(height, previewFrame.height + 32)
            interactive: editor.actualSize
            boundsBehavior: Flickable.StopAtBounds
            pixelAligned: true
            clip: true
            ScrollBar.vertical: ScrollBar {
                policy: editor.actualSize ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                width: 6
                contentItem: Rectangle { radius: 3; color: Qt.alpha(ThemeApi.Theme.accent, 0.55) }
                background: Rectangle { color: "transparent" }
            }
            ScrollBar.horizontal: ScrollBar {
                policy: editor.actualSize ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                height: 6
                contentItem: Rectangle { radius: 3; color: Qt.alpha(ThemeApi.Theme.accent, 0.55) }
                background: Rectangle { color: "transparent" }
            }

            Rectangle {
                id: previewFrame
                x: Math.round((imageViewport.contentWidth - width) / 2)
                y: Math.round(32 + Math.max(0, imageViewport.contentHeight - height - 32) / 2)
                width: drawing.width * editor.displayScale + 20
                height: drawing.height * editor.displayScale + 20
                radius: 20
                color: ThemeApi.Theme.notchBg
                border.width: 1
                border.color: Qt.alpha(ThemeApi.Theme.border, 0.8)

                RowLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.top
                    anchors.bottomMargin: 12
                    Text {
                        Layout.fillWidth: true
                        text: editor.appName ? "Screenshot · " + editor.appName : "Screenshot"
                        textFormat: Text.PlainText
                        color: ThemeApi.Theme.textBright
                        font.family: "Inter"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Text {
                        text: Math.round(editor.editState.crop ? editor.editState.crop.width : editor.imageWidth)
                            + " × " + Math.round(editor.editState.crop ? editor.editState.crop.height : editor.imageHeight)
                        color: ThemeApi.Theme.muted
                        font.family: "Inter"
                        font.pixelSize: 10
                    }
                }

                Canvas {
                    id: drawing
                    x: 10; y: 10
                    // Rasterize the source and edits at their original resolution.
                    // Only the view transform fits that texture into the editor.
                    width: Math.max(1, editor.imageWidth)
                    height: Math.max(1, editor.imageHeight)
                    transform: Scale { xScale: editor.displayScale; yScale: editor.displayScale }
                    smooth: !editor.actualSize
                    renderTarget: Canvas.Image
                    onAvailableChanged: if (available) editor.loadSource()
                    onImageLoaded: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        if (!ctx) return;
                        ctx.reset();
                        ctx.clearRect(0, 0, width, height);
                        if (!isImageLoaded(editor.source)) return;
                        ctx.drawImage(editor.source, 0, 0, width, height);
                        for (const operation of editor.editState.operations) editor.paintOperation(ctx, operation);
                        let crop = editor.editState.crop;
                        if (editor.draft) {
                            if (editor.draft.type === "pen") editor.paintOperation(ctx, editor.draft);
                            else {
                                const rect = editor.rectangleBetween(editor.draft.start, editor.draft.end);
                                if (editor.draft.type === "crop") crop = rect;
                                else if (editor.draft.type === "highlight")
                                    editor.paintOperation(ctx, Object.assign({type:"highlight",color:editor.draft.color,opacity:0.32},rect));
                                else {
                                    ctx.strokeStyle = String(ThemeApi.Theme.accent);
                                    ctx.lineWidth = 1.5 / editor.displayScale;
                                    ctx.setLineDash([5 / editor.displayScale, 4 / editor.displayScale]);
                                    ctx.strokeRect(rect.x, rect.y, rect.width, rect.height);
                                    ctx.setLineDash([]);
                                }
                            }
                        }
                        if (crop) editor.paintCrop(ctx, crop);
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !editor.busy
                        acceptedButtons: Qt.LeftButton
                        preventStealing: true
                        cursorShape: Qt.CrossCursor
                        onPressed: mouse => editor.beginGesture(mouse.x, mouse.y)
                        onPositionChanged: mouse => { if (pressed) editor.moveGesture(mouse.x, mouse.y); }
                        onReleased: mouse => editor.endGesture(mouse.x, mouse.y)
                        onCanceled: editor.cancelGesture()
                        onWheel: wheel => editor.panImage(wheel)
                    }
                }
            }
        }
    }

    Rectangle {
        id: toolbar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 44
        width: Math.min(800, Math.max(1, parent.width - 48))
        height: toolbarFlow.implicitHeight + 20
        radius: 20
        color: ThemeApi.Theme.notchBg
        border.width: 1
        border.color: Qt.alpha(ThemeApi.Theme.border, 0.8)

        Flow {
            id: toolbarFlow
            x: 10; y: 10
            width: parent.width - 20
            spacing: 6

            Button {
                id: zoomButton
                text: editor.actualSize ? "100%" : "Fit " + Math.round(editor.displayScale * 100) + "%"
                width: 76; height: 36
                focusPolicy: Qt.NoFocus
                enabled: !editor.busy
                Accessible.name: editor.actualSize ? "Actual size" : "Fit to screen"
                ToolTip.visible: hovered
                ToolTip.delay: 400
                ToolTip.text: "Actual pixels · Ctrl+1\nFit to screen · Ctrl+0\nScroll to pan · Shift+wheel horizontally"
                contentItem: Text {
                    text: zoomButton.text
                    font.family: "Inter"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: editor.actualSize ? ThemeApi.Theme.accent : ThemeApi.Theme.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 11
                    color: editor.actualSize ? ThemeApi.Theme.accentSoft : zoomButton.hovered ? ThemeApi.Theme.surfaceRaised : ThemeApi.Theme.surface
                }
                onClicked: editor.actualSize = !editor.actualSize
            }

            Row {
                spacing: 3
                IconButton { symbol: "crop"; tip: "Crop · C"; selected: editor.tool === "crop"; enabled: !editor.busy; onClicked: editor.tool = "crop" }
                IconButton { symbol: "draw"; tip: "Draw · B"; selected: editor.tool === "pen"; enabled: !editor.busy; onClicked: editor.tool = "pen" }
                IconButton { symbol: "ink_highlighter"; tip: "Highlight · H"; selected: editor.tool === "highlight"; enabled: !editor.busy; onClicked: editor.tool = "highlight" }
                IconButton { symbol: "grid_on"; tip: "Pixelate · P"; selected: editor.tool === "pixelate"; enabled: !editor.busy; onClicked: editor.tool = "pixelate" }
            }
            Row {
                spacing: 1
                IconButton { symbol: "undo"; tip: "Undo · Ctrl+Z"; enabled: !editor.busy && editor.canUndo; onClicked: editor.undo() }
                IconButton { symbol: "redo"; tip: "Redo · Ctrl+Shift+Z"; enabled: !editor.busy && editor.canRedo; onClicked: editor.redo() }
                IconButton { symbol: "restart_alt"; tip: "Reset edits"; enabled: !editor.busy && editor.hasEdits; onClicked: editor.reset() }
            }
            Row {
                height: 36
                spacing: 5
                opacity: editor.tool === "pen" || editor.tool === "highlight" ? 1 : 0.35
                Repeater {
                    model: [String(ThemeApi.Theme.accent), String(ThemeApi.Theme.red), String(ThemeApi.Theme.textBright)]
                    delegate: Rectangle {
                        id: swatch
                        required property string modelData
                        width: 22; height: 22
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 11
                        color: modelData
                        border.width: editor.selectedColor === modelData ? 2 : 0
                        border.color: ThemeApi.Theme.notchBg
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -2
                            radius: 13
                            color: "transparent"
                            border.width: editor.selectedColor === swatch.modelData ? 1 : 0
                            border.color: ThemeApi.Theme.text
                        }
                        MouseArea { anchors.fill: parent; enabled: !editor.busy; cursorShape: Qt.PointingHandCursor; onClicked: editor.selectedColor = swatch.modelData }
                    }
                }
                IconButton {
                    symbol: editor.brushWidth === 4 ? "line_weight" : "line_weight"
                    tip: "Stroke width · " + editor.brushWidth + " px"
                    enabled: !editor.busy
                    implicitWidth: 28
                    onClicked: editor.brushWidth = editor.brushWidth === 4 ? 8 : editor.brushWidth === 8 ? 12 : 4
                }
            }
            Row {
                spacing: 6
                Button {
                    id: copyButton
                    text: editor.busy ? "Working…" : "Copy"
                    width: 76; height: 36
                    focusPolicy: Qt.NoFocus
                    enabled: !editor.busy
                    contentItem: Text { text: copyButton.text; font.family: "Inter"; font.pixelSize: 12; font.weight: Font.DemiBold; color: ThemeApi.Theme.onAccent; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { radius: 11; color: ThemeApi.Theme.accent; opacity: copyButton.enabled ? 1 : 0.55 }
                    ToolTip.visible: hovered; ToolTip.text: "Copy image · Ctrl+C"; ToolTip.delay: 500
                    onClicked: editor.exportEdit(false)
                }
                Button {
                    id: saveButton
                    text: "Save"
                    width: 66; height: 36
                    focusPolicy: Qt.NoFocus
                    enabled: !editor.busy
                    contentItem: Text { text: saveButton.text; font.family: "Inter"; font.pixelSize: 12; font.weight: Font.Medium; color: ThemeApi.Theme.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { radius: 11; color: saveButton.hovered ? ThemeApi.Theme.surfaceRaised : ThemeApi.Theme.surface }
                    ToolTip.visible: hovered; ToolTip.text: "Save PNG · Ctrl+S"; ToolTip.delay: 500
                    onClicked: editor.exportEdit(true)
                }
            }
            IconButton { symbol: "close"; tip: "Discard · Esc"; enabled: !editor.busy; onClicked: editor.dismissed() }
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: toolbar.top
        anchors.bottomMargin: 14
        width: Math.min(parent.width - 64, 700)
        text: editor.errorText || (editor.historyIndex >= 40 ? "Edit limit reached · undo or export your screenshot"
            : editor.tool === "crop" ? "Drag a new crop area · the shaded part will be removed"
            : editor.tool === "pixelate" ? "Drag over the area you want to pixelate"
            : editor.tool === "highlight" ? "Drag to highlight an area" : "Draw on the screenshot · Ctrl+Z to undo")
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        color: editor.errorText ? ThemeApi.Theme.red : ThemeApi.Theme.muted
        font.family: "Inter"
        font.pixelSize: 11
        elide: Text.ElideRight
    }
}
