import QtQuick
import "Theme" as ThemePalette

Item {
    id: root

    property bool animated: true
    property string value: "0"
    property string previousValue: value
    property string displayValue: value
    property real progress: 1
    property int fontSize: 18
    property color textColor: ThemePalette.Theme.textBright
    property bool initialized: false

    implicitWidth: fontSize * 0.64
    implicitHeight: fontSize * 1.32
    clip: true
    Component.onCompleted: {
        previousValue = value;
        displayValue = value;
        initialized = true;
    }
    onValueChanged: {
        if (!initialized)
            return ;

        if (!animated) {
            flip.stop();
            previousValue = displayValue = value;
            progress = 1;
            return;
        }
        previousValue = displayValue;
        displayValue = value;
        progress = 0;
        flip.restart();
    }

    onAnimatedChanged: if (!animated) {
        flip.stop();
        previousValue = displayValue = value;
        progress = 1;
    }

    Text {
        text: root.previousValue
        x: 0
        y: root.progress * root.height
        width: root.width
        height: root.height
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: root.textColor
        font.family: "Inter"
        font.italic: false
        font.pixelSize: root.fontSize
        font.weight: Font.ExtraBold

        transform: Rotation {
            origin.x: parent.width / 2
            origin.y: 0
            axis.x: 1
            axis.y: 0
            axis.z: 0
            angle: 82 * root.progress
        }

    }

    Text {
        text: root.displayValue
        x: 0
        y: (root.progress - 1) * root.height
        width: root.width
        height: root.height
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: root.textColor
        font.family: "Inter"
        font.italic: false
        font.pixelSize: root.fontSize
        font.weight: Font.ExtraBold

        transform: Rotation {
            origin.x: parent.width / 2
            origin.y: parent.height
            axis.x: 1
            axis.y: 0
            axis.z: 0
            angle: -82 * (1 - root.progress)
        }

    }

    NumberAnimation {
        id: flip

        target: root
        property: "progress"
        from: 0
        to: 1
        duration: 420
        easing.type: Easing.OutBack
        easing.overshoot: 0.35
    }

}
