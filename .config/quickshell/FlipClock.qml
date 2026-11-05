import QtQuick
import "Theme" as ThemePalette

Item {
    id: root

    property bool animated: true
    property string time: "00:00"
    property int fontSize: 18

    implicitWidth: fontSize * 2.9
    implicitHeight: fontSize * 1.32

    Row {
        anchors.centerIn: parent
        spacing: 0

        FlipDigit {
            animated: root.animated
            value: root.time.length > 0 ? root.time.charAt(0) : "0"
            fontSize: root.fontSize
        }

        FlipDigit {
            animated: root.animated
            value: root.time.length > 1 ? root.time.charAt(1) : "0"
            fontSize: root.fontSize
        }

        Text {
            text: ":"
            width: root.fontSize * 0.34
            height: root.height
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: ThemePalette.Theme.muted
            font.family: "Inter"
            font.italic: false
            font.pixelSize: root.fontSize
            font.weight: Font.ExtraBold
        }

        FlipDigit {
            animated: root.animated
            value: root.time.length > 3 ? root.time.charAt(3) : "0"
            fontSize: root.fontSize
        }

        FlipDigit {
            animated: root.animated
            value: root.time.length > 4 ? root.time.charAt(4) : "0"
            fontSize: root.fontSize
        }

    }

}
