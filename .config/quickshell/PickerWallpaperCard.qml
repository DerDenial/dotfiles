pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import "Theme" as ThemeApi
import "Wallpapers" as Wallpapers

Item {
    id: card

    required property url imageUrl
    required property string imagePath
    required property string fileName
    property string imageRevision: ""
    property bool selected: false
    property bool externalSelection: false
    property bool applied: false
    property bool previewsActive: false
    property bool animationsEnabled: false
    property color accent: ThemeApi.Theme.accent
    property color onAccent: ThemeApi.Theme.onAccent

    readonly property string displayName: fileName.replace(/\.[^.]+$/, "").replace(/_/g, " ")
    readonly property string extension: {
        const match = fileName.match(/\.([^.]+)$/);
        return match ? match[1].toUpperCase() : "IMAGE";
    }
    readonly property var loadedArtwork: artwork.item
    readonly property int previewStatus: loadedArtwork ? loadedArtwork.previewStatus : Image.Null

    signal chosen()
    signal accepted()

    implicitWidth: 264
    implicitHeight: 176

    Accessible.role: Accessible.Button
    Accessible.name: displayName + (applied ? ", current wallpaper" : "")
    Accessible.description: selected ? "Selected. Press Enter to apply." : "Select wallpaper"
    Accessible.onPressAction: chosen()

    Rectangle {
        id: face
        anchors.fill: parent
        anchors.margins: 4
        radius: 18
        color: ThemeApi.Theme.surface
        scale: card.externalSelection ? 1 : card.selected ? 1 : pointer.containsMouse ? 0.985 : 0.96

        Behavior on scale {
            enabled: card.animationsEnabled && !card.externalSelection
            NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 0.65 }
        }

        // Instantiate the rounded artwork surface only for visible previews.
        Loader {
            id: artwork
            anchors.fill: parent
            active: card.visible && card.previewsActive
            asynchronous: false
            sourceComponent: Component {
                ClippingRectangle {
                    radius: 18
                    color: ThemeApi.Theme.surface
                    contentInsideBorder: false
                    readonly property int previewStatus: preview.previewStatus

                    Wallpapers.Preview {
                        id: preview
                        anchors.fill: parent
                        originalSource: card.imageUrl
                        filePath: card.imagePath
                        fileRevision: card.imageRevision
                        previewsActive: card.previewsActive
                    }
                }
            }
        }

        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -14
            spacing: 7
            visible: card.previewStatus !== Image.Ready

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: card.previewStatus === Image.Error ? "broken_image" : "landscape"
                color: ThemeApi.Theme.mutedStrong
                font.family: "Material Symbols Rounded"
                font.pixelSize: 29
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: card.previewStatus === Image.Loading ? "Loading preview" : "No preview"
                color: ThemeApi.Theme.muted
                font.family: "Inter"
                font.pixelSize: 10
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 92
            topLeftRadius: 0
            topRightRadius: 0
            bottomLeftRadius: face.radius
            bottomRightRadius: face.radius
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0) }
                GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.38) }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.78) }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 12
            implicitWidth: currentLabel.implicitWidth + 24
            implicitHeight: 25
            radius: 12.5
            color: Qt.alpha(ThemeApi.Theme.notchBg, 0.84)
            border.width: 1
            border.color: Qt.alpha(ThemeApi.Theme.textBright, 0.15)
            visible: card.applied

            Text {
                id: currentLabel
                anchors.centerIn: parent
                text: "On desktop"
                color: ThemeApi.Theme.textBright
                font.family: "Inter"
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            width: 25
            height: 25
            radius: 12.5
            color: card.accent
            visible: card.selected

            Text {
                anchors.centerIn: parent
                text: "check"
                color: card.onAccent
                font.family: "Material Symbols Rounded"
                font.pixelSize: 17
            }
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.bottomMargin: 14
            spacing: 4

            Text {
                width: parent.width
                text: card.displayName
                color: ThemeApi.Theme.textBright
                font.family: "Inter"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            Text {
                text: card.extension + " · Wallpaper"
                color: Qt.alpha(ThemeApi.Theme.textBright, 0.74)
                font.family: "Inter"
                font.pixelSize: 10
                font.weight: Font.Medium
            }
        }

        // Keep this above the image so the keyboard selection is always clear.
        Rectangle {
            anchors.fill: parent
            radius: face.radius
            color: "transparent"
            border.width: card.selected && card.externalSelection ? 0 : card.selected ? 2 : 1
            border.color: card.selected ? card.accent : Qt.alpha(ThemeApi.Theme.textBright, pointer.containsMouse ? 0.28 : 0.13)
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.chosen()
        onDoubleClicked: card.accepted()
    }
}
