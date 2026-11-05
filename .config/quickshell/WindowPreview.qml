pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell.Wayland
import "Theme" as ThemeApi

// A single, temporary capture of the selected window; never saved to disk.
Item {
    id: preview

    required property var entry
    required property bool capturing
    required property real reveal
    readonly property var windowSource: entry ? entry.ref : null
    readonly property ScreencopyView captureView: captureLoader.item as ScreencopyView
    readonly property bool hasFrame: captureView ? captureView.hasContent
        && captureView.sourceSize.width > 0 && captureView.sourceSize.height > 0 : false
    property bool componentReady: false
    property real selectionReveal: 1
    property bool previewPending: true

    signal activated()
    signal contextRequested(point position)
    signal closeRequested(string key)
    signal pinRequested(string key)

    function replaceCapture() {
        if (!componentReady) return;
        // Recreate for each source: old-window destruction must not clear a
        // newer capture in Quickshell 0.3.2. Metadata-only updates keep it alive.
        captureLoader.active = false;
        captureLoader.windowSource = windowSource;
        captureLoader.active = !!windowSource;
        previewPending = true;
        fallbackDelay.restart();
        selectionMotion.stop();
        selectionReveal = 0;
        selectionMotion.start();
    }

    onWindowSourceChanged: replaceCapture()
    onHasFrameChanged: if (hasFrame) {
        previewPending = false;
        fallbackDelay.stop();
    }
    Component.onCompleted: {
        componentReady = true;
        replaceCapture();
    }

    opacity: Math.max(0, Math.min(1, reveal * 1.6))
    scale: (0.96 + 0.04 * Math.max(0, Math.min(1, reveal)))
        * (0.985 + 0.015 * selectionReveal)
    visible: entry !== null && height >= 100

    NumberAnimation {
        id: selectionMotion
        target: preview
        property: "selectionReveal"
        to: 1
        duration: 185
        easing.type: Easing.OutBack
        easing.overshoot: 0.45
    }

    Timer {
        id: fallbackDelay
        interval: 400
        onTriggered: preview.previewPending = false
    }

    Rectangle {
        x: -5
        y: 6
        width: parent.width + 10
        height: parent.height + 6
        radius: 26
        color: Qt.alpha(ThemeApi.Theme.bg0, 0.20)
    }

    // Content clicks activate the window; header controls receive input first.
    MouseArea {
        anchors.fill: parent
        enabled: preview.capturing
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) preview.contextRequested(Qt.point(mouse.x, mouse.y));
            else preview.activated();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 22
        color: Qt.alpha(ThemeApi.Theme.notchBg, 0.96)
        border.width: 1
        border.color: Qt.alpha(ThemeApi.Theme.border, 0.78)

        Item {
            id: header
            objectName: "windowPreviewHeader"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            height: 28
            readonly property real sideReserve: Math.max(workspaceLabel.width, rightControls.width) + 12

            Text {
                id: workspaceLabel
                objectName: "windowPreviewWorkspace"
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: visible ? Math.min(implicitWidth, header.width * 0.28) : 0
                visible: !!(preview.entry && preview.entry.workspace)
                text: "Workspace " + (preview.entry ? preview.entry.workspace : "")
                textFormat: Text.PlainText
                color: ThemeApi.Theme.muted
                font.family: "Inter"
                font.pixelSize: 10
                elide: Text.ElideRight
            }

            Row {
                objectName: "windowPreviewApplication"
                anchors.centerIn: parent
                height: parent.height
                spacing: 8

                Item {
                    width: 20
                    height: 20
                    anchors.verticalCenter: parent.verticalCenter
                    Image {
                        id: appIcon
                        anchors.fill: parent
                        source: preview.entry ? preview.entry.icon : ""
                        sourceSize.width: 40
                        sourceSize.height: 40
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        visible: status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: appIcon.status !== Image.Ready
                        text: "web_asset"
                        color: ThemeApi.Theme.accent
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 20
                    }
                }
                Text {
                    width: Math.max(0, Math.min(implicitWidth, header.width - 2 * header.sideReserve - 28))
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: preview.entry ? preview.entry.appName || preview.entry.title || "Window" : ""
                    textFormat: Text.PlainText
                    color: ThemeApi.Theme.textBright
                    font.family: "Inter"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
            }

            Row {
                id: rightControls
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 28
                spacing: 4
                ToolButton {
                    id: pinButton
                    objectName: "windowPreviewPin"
                    width: 28
                    height: 28
                    enabled: preview.capturing && !!preview.entry && preview.entry.manageable
                        && preview.entry.pinSupported && preview.entry.pinnedKnown && !preview.entry.pinBusy
                    focusPolicy: Qt.NoFocus
                    Accessible.name: preview.entry && preview.entry.pinned ? "Unpin window" : "Pin on all workspaces"
                    Accessible.description: preview.entry && preview.entry.pinned
                        ? "Show this window on its own workspace"
                        : "Keep this window visible on every workspace"
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: preview.entry && preview.entry.pinBusy ? "Updating…" : Accessible.name
                    contentItem: Text {
                        text: "push_pin"
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 18
                        color: preview.entry && preview.entry.pinned ? ThemeApi.Theme.accent
                            : pinButton.enabled ? ThemeApi.Theme.muted : ThemeApi.Theme.mutedStrong
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 9
                        color: preview.entry && preview.entry.pinned ? ThemeApi.Theme.accentSoft
                            : pinButton.hovered ? ThemeApi.Theme.surfaceRaised : "transparent"
                    }
                    onClicked: if (preview.entry) preview.pinRequested(preview.entry.key)
                }
                ToolButton {
                    id: closeButton
                    objectName: "windowPreviewClose"
                    width: 28
                    height: 28
                    enabled: preview.capturing && !!preview.entry
                    focusPolicy: Qt.NoFocus
                    Accessible.name: "Close window"
                    ToolTip.visible: hovered
                    ToolTip.delay: 500
                    ToolTip.text: "Close window"
                    contentItem: Text {
                        text: "close"
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 18
                        color: closeButton.hovered ? ThemeApi.Theme.red : ThemeApi.Theme.muted
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 9
                        color: closeButton.hovered ? Qt.alpha(ThemeApi.Theme.red, 0.12) : "transparent"
                    }
                    onClicked: if (preview.entry) preview.closeRequested(preview.entry.key)
                }
            }
        }

        Rectangle {
            id: viewport
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            radius: 14
            color: Qt.alpha(ThemeApi.Theme.surface, 0.70)
            clip: true

            Column {
                anchors.centerIn: parent
                width: Math.max(0, parent.width - 32)
                spacing: 9
                visible: !preview.hasFrame

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "web_asset"
                    color: ThemeApi.Theme.accent
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 30
                    opacity: 0.70
                }
                Text {
                    width: parent.width
                    text: preview.previewPending ? "Loading preview…" : "Preview unavailable"
                    color: ThemeApi.Theme.muted
                    font.family: "Inter"
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }

            Loader {
                id: captureLoader
                anchors.centerIn: parent
                active: false
                asynchronous: false
                property var windowSource: null

                sourceComponent: ScreencopyView {
                    captureSource: captureLoader.windowSource
                    paintCursor: false
                    live: preview.capturing
                    constraintSize: Qt.size(Math.max(1, viewport.width), Math.max(1, viewport.height))
                    width: hasContent && sourceSize.width > 0 && sourceSize.height > 0 ? Math.max(1, implicitWidth) : 1
                    height: hasContent && sourceSize.width > 0 && sourceSize.height > 0 ? Math.max(1, implicitHeight) : 1
                    layer.enabled: hasContent
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: frameMask
                        autoPaddingEnabled: false
                    }
                }
            }

            // A sibling in this window supplies the rounded texture mask.
            Rectangle {
                id: frameMask
                width: Math.max(1, captureLoader.width)
                height: Math.max(1, captureLoader.height)
                radius: 12
                color: "white"
                layer.enabled: true
                visible: false
            }
        }
    }
}
