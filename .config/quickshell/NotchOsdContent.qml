import QtQuick
import "Theme" as ThemePalette

// The parent owns the one notch surface and its geometry timeline.
Item {
    id: root
    required property var osd
    property real expandedWidth: osd ? osd.requestedWidth : 340
    property real expandedHeight: osd ? osd.requestedHeight : 66
    property bool compactMode: false
    // Reserve the final eight pixels of collapse for the compact clock/status.
    // The progress bar must be fully folded before that content returns.
    readonly property real foldHeight: 42
    readonly property real stretch: compactMode ? 1
        : Math.max(0, Math.min(1.08, (height - foldHeight) / Math.max(1, expandedHeight - foldHeight)))
    readonly property real reveal: Math.min(1, stretch)
    readonly property color indicatorColor: osd && osd.muted ? ThemePalette.Theme.muted : ThemePalette.Theme.accent

    // The same geometry timeline drives clipping and scale, including reversals.
    Item {
        width: Math.max(0, root.width - 44)
        height: root.compactMode ? 30 : 42 * root.reveal
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.compactMode ? 1 : 12
        clip: true

        Item {
            width: root.compactMode ? Math.max(0, root.width - 44) : root.expandedWidth - 44
            height: root.compactMode ? 30 : 42
            anchors.horizontalCenter: parent.horizontalCenter
            transform: Scale {
                origin.x: (root.compactMode ? root.width - 44 : root.expandedWidth - 44) / 2
                xScale: root.compactMode ? 1 : (root.width - 44) / Math.max(1, root.expandedWidth - 44)
                yScale: root.stretch
            }

            Text {
                x: 0; y: root.compactMode ? 3 : -1
                width: 28; height: root.compactMode ? 24 : 27
                text: root.osd ? root.osd.iconName : "volume_up"
                font.family: "Material Symbols Rounded"
                font.pixelSize: root.compactMode ? 18 : 25
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                color: root.indicatorColor
            }
            Text {
                x: 39; y: root.compactMode ? 0 : 2
                width: parent.width - 103
                text: root.osd ? root.osd.title : "Volume"
                color: ThemePalette.Theme.textBright
                font.family: "Inter"
                font.pixelSize: root.compactMode ? 11 : 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                anchors.right: parent.right
                y: root.compactMode ? 0 : 2
                text: root.osd && root.osd.muted ? "Muted" : (root.osd ? root.osd.percentage : 0) + "%"
                color: root.osd && root.osd.muted ? ThemePalette.Theme.muted : ThemePalette.Theme.accent
                font.family: "Inter"
                font.pixelSize: root.compactMode ? 11 : 12
                font.weight: Font.DemiBold
            }

            Rectangle {
                x: 39; y: root.compactMode ? 23 : 31
                width: parent.width - 39
                height: root.compactMode ? 3 : 5
                radius: 2.5
                color: ThemePalette.Theme.surfaceRaised

                Rectangle {
                    width: parent.width * (root.osd && !root.osd.muted ? root.osd.level : 0)
                    height: parent.height
                    radius: parent.radius
                    color: root.indicatorColor
                    Behavior on width { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                }
            }
        }
    }
}
