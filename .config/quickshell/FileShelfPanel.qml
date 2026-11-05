pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "Theme" as ThemeApi

Item {
    id: panel
    required property var shelf
    property bool opened: false
    property bool presented: opened
    readonly property int itemCount: Array.isArray(shelf.items) ? shelf.items.length : 0
    readonly property int columns: Math.max(1, Math.min(4, Math.floor(width / 112)))
    readonly property int visibleRows: Math.min(2, Math.ceil(itemCount / columns))
    implicitWidth: 528
    implicitHeight: itemCount ? 84 + visibleRows * 104 : 180

    signal closeRequested()
    signal dragStarted()
    signal dragFinished(int action)

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        Item {
            id: header
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            Rectangle {
                x: 0; y: 1
                width: 38; height: 38
                radius: 13
                color: ThemeApi.Theme.accentSoft
                Text {
                    anchors.centerIn: parent
                    text: "inventory_2"
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 22
                    color: ThemeApi.Theme.accent
                }
            }
            Column {
                x: 48; y: 3
                width: Math.max(0, header.width - 48 - (panel.itemCount ? 76 : 38))
                spacing: 2
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: "File shelf"
                    color: ThemeApi.Theme.textBright
                    font.family: "Inter"
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: panel.shelf.busy ? "Updating…"
                        : panel.itemCount ? panel.itemCount + (panel.itemCount === 1 ? " item ready" : " items ready")
                        : "A little space between windows"
                    color: ThemeApi.Theme.muted
                    font.family: "Inter"
                    font.pixelSize: 10
                }
            }
            ToolButton {
                id: clearButton
                objectName: "shelfClear"
                anchors.right: closeButton.left
                anchors.rightMargin: 6
                y: 4
                width: 32; height: 32
            visible: panel.itemCount > 0 || panel.shelf.error !== ""
                enabled: panel.opened && !panel.shelf.busy && !panel.shelf.dragging
                focusPolicy: Qt.NoFocus
                Accessible.name: "Clear shelf"
                ToolTip.visible: hovered
                ToolTip.delay: 450
                ToolTip.text: "Clear shelf"
                contentItem: Text {
                    text: "playlist_remove"
                    color: clearButton.enabled ? ThemeApi.Theme.muted : ThemeApi.Theme.mutedStrong
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 20
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 10
                    color: clearButton.hovered ? ThemeApi.Theme.surfaceRaised : "transparent"
                }
                onClicked: panel.shelf.clear()
            }
            ToolButton {
                id: closeButton
                objectName: "shelfClose"
                anchors.right: parent.right
                y: 4
                width: 32; height: 32
                enabled: panel.opened && !panel.shelf.dragging
                focusPolicy: Qt.NoFocus
                Accessible.name: "Close file shelf"
                ToolTip.visible: hovered
                ToolTip.delay: 450
                ToolTip.text: "Close"
                contentItem: Text {
                    text: "close"
                    color: closeButton.enabled ? ThemeApi.Theme.muted : ThemeApi.Theme.mutedStrong
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 20
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 10
                    color: closeButton.hovered ? ThemeApi.Theme.surfaceRaised : "transparent"
                }
                onClicked: panel.closeRequested()
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: panel.itemCount ? 104 : 88
            clip: true

            Column {
                anchors.centerIn: parent
                visible: panel.itemCount === 0
                spacing: 6
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "file_copy"
                    color: ThemeApi.Theme.accent
                    opacity: 0.75
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 30
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: panel.shelf.loaded ? "Drop files here" : "Opening your shelf…"
                    color: ThemeApi.Theme.textBright
                    font.family: "Inter"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Keep them handy while switching windows"
                    color: ThemeApi.Theme.muted
                    font.family: "Inter"
                    font.pixelSize: 10
                }
            }

            GridView {
                id: files
                objectName: "shelfFiles"
                anchors.fill: parent
                clip: true
                visible: panel.itemCount > 0
                cellWidth: Math.floor(width / panel.columns)
                cellHeight: 104
                cacheBuffer: 0
                interactive: panel.opened && !panel.shelf.dragging && contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                model: panel.presented || panel.shelf.dragging ? panel.shelf.items : []
                ScrollBar.vertical: ScrollBar {
                    width: 3
                    policy: files.contentHeight > files.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    contentItem: Rectangle { radius: 2; color: Qt.alpha(ThemeApi.Theme.accent, 0.55) }
                    background: Item {}
                }
                delegate: Item {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property string fileIconName: String(modelData.iconName || (modelData.isDir ? "folder" : "text-x-generic"))
                    property bool dragPrepared: false
                    property bool nativeDragStarted: false
                    readonly property bool dragAvailable: fileDrag.enabled
                    objectName: "shelfFile" + index
                    width: files.cellWidth
                    height: files.cellHeight
                    opacity: modelData.missing ? 0.5 : 1
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.name
                    Accessible.description: modelData.missing ? "Unavailable. Remove from shelf." : "Drag into another app"

                    Drag.dragType: Drag.Automatic
                    Drag.active: fileDrag.active && dragPrepared
                    Drag.source: tile
                    Drag.supportedActions: Qt.CopyAction
                    Drag.proposedAction: Qt.CopyAction
                    Drag.mimeData: ({ "text/uri-list": [String(tile.modelData.fileUrl)] })
                    Drag.imageSource: fileIcon.status === Image.Ready ? fileIcon.source : ""
                    Drag.imageSourceSize: Qt.size(48, 48)
                    Drag.hotSpot: Qt.point(20, 20)
                    Drag.onDragStarted: {
                        tile.nativeDragStarted = true;
                        panel.shelf.markDragStarted();
                        panel.dragStarted();
                    }
                    Drag.onDragFinished: action => {
                        tile.nativeDragStarted = false;
                        tile.dragPrepared = false;
                        panel.shelf.endDrag(action);
                        panel.dragFinished(action);
                    }

                    HoverHandler { id: fileHover }
                    DragHandler {
                        id: fileDrag
                        objectName: "shelfDrag" + tile.index
                        target: null
                        acceptedButtons: Qt.LeftButton
                        enabled: panel.opened && !tile.modelData.missing && !panel.shelf.busy
                            && (!panel.shelf.dragging || tile.dragPrepared)
                            && (tile.dragPrepared || !removeButton.hovered)
                        onActiveChanged: {
                            if (active) {
                                tile.nativeDragStarted = false;
                                // Arm the local gate before beginDrag freezes the model;
                                // that state change must not disable this handler.
                                tile.dragPrepared = true;
                                if (panel.shelf.beginDrag(String(tile.modelData.id)) !== true)
                                    tile.dragPrepared = false;
                            } else {
                                // Releasing before the queued native drag starts has no
                                // dragFinished signal; don't leave the model frozen.
                                Qt.callLater(function() {
                                    if (tile.dragPrepared && !tile.nativeDragStarted && !tile.Drag.active) {
                                        tile.dragPrepared = false;
                                        panel.shelf.endDrag(Qt.IgnoreAction);
                                        panel.dragFinished(Qt.IgnoreAction);
                                    }
                                });
                            }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: 16
                        color: tile.dragPrepared ? ThemeApi.Theme.accentSoft
                            : fileHover.hovered ? ThemeApi.Theme.surfaceRaised : Qt.alpha(ThemeApi.Theme.surface, 0.7)
                        border.width: 1
                        border.color: tile.dragPrepared ? ThemeApi.Theme.accent : Qt.alpha(ThemeApi.Theme.border, 0.45)
                        Image {
                            id: fileIcon
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 10
                            width: 32
                            height: 32
                            source: Quickshell.iconPath(tile.fileIconName, true)
                            sourceSize.width: 48
                            sourceSize.height: 48
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            visible: status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: fileIcon
                            visible: fileIcon.status !== Image.Ready
                            text: tile.modelData.isDir ? "folder" : "description"
                            color: ThemeApi.Theme.accent
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 30
                        }
                        Text {
                            x: 10
                            y: 49
                            width: parent.width - 20
                            height: 30
                            text: tile.modelData.name
                            textFormat: Text.PlainText
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            wrapMode: Text.WrapAnywhere
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            color: ThemeApi.Theme.text
                            font.family: "Inter"
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 25
                            visible: !!tile.modelData.missing
                            text: "warning"
                            color: ThemeApi.Theme.red
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 15
                        }
                    }
                    ToolButton {
                        id: removeButton
                        objectName: "shelfRemove" + tile.index
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.rightMargin: 5
                        anchors.topMargin: 5
                        width: 24
                        height: 24
                        z: 2
                        visible: fileHover.hovered || hovered || !!tile.modelData.missing
                        enabled: panel.opened && !panel.shelf.busy && !panel.shelf.dragging
                        focusPolicy: Qt.NoFocus
                        Accessible.name: "Remove " + tile.modelData.name + " from shelf"
                        ToolTip.visible: hovered
                        ToolTip.delay: 450
                        ToolTip.text: "Remove from shelf"
                        contentItem: Text {
                            text: "close"
                            color: ThemeApi.Theme.muted
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 14
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 8
                            color: removeButton.hovered ? ThemeApi.Theme.surface : "transparent"
                        }
                        onClicked: panel.shelf.remove(String(tile.modelData.id))
                    }
                    ToolTip {
                        visible: panel.opened && fileHover.hovered && !removeButton.hovered && !panel.shelf.dragging
                        delay: 650
                        width: Math.min(380, Math.max(180, panel.width - 32))
                        contentItem: Text {
                            text: tile.modelData.name + "\n" + tile.modelData.parent
                                + (tile.modelData.missing ? "\nUnavailable" : "")
                            textFormat: Text.PlainText
                            wrapMode: Text.WrapAnywhere
                            color: ThemeApi.Theme.text
                            font.family: "Inter"
                            font.pixelSize: 10
                        }
                        background: Rectangle {
                            radius: 10
                            color: ThemeApi.Theme.surface
                            border.width: 1
                            border.color: ThemeApi.Theme.border
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 20
            spacing: 6
            Text {
                text: panel.shelf.error || panel.shelf.notice ? "info" : "drag_indicator"
                color: panel.shelf.error ? ThemeApi.Theme.red : ThemeApi.Theme.mutedStrong
                font.family: "Material Symbols Rounded"
                font.pixelSize: 15
            }
            Text {
                Layout.fillWidth: true
                text: panel.shelf.error || panel.shelf.notice
                    || (panel.itemCount ? "Drag a file into another app" : "Drop files on the notch to collect them")
                textFormat: Text.PlainText
                color: panel.shelf.error ? ThemeApi.Theme.red : ThemeApi.Theme.muted
                font.family: "Inter"
                font.pixelSize: 10
                elide: Text.ElideRight
            }
        }
    }
}
