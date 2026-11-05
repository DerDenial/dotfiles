import QtQuick
import QtQuick.Layouts
import "Theme" as ThemePalette

Item {
    id: root

    property string clockValue: "00:00"
    property int batteryLevel: 0
    property bool batteryCharging: false

    implicitWidth: 236
    implicitHeight: 34

    WorkspaceIndicators {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 50
        height: 16
        maxIndicators: 5
        animated: false
    }

    Item {
        anchors.centerIn: parent
        width: 52
        height: 26

        FlipClock {
            anchors.centerIn: parent
            time: root.clockValue
            // Match HoverNotchContent's compact glyph rendering at the handoff.
            fontSize: 18
            scale: 15 / 18
            animated: false
        }
    }

    RowLayout {
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 50
        spacing: 5

        WifiSignalIndicator {
            Layout.preferredWidth: 17
            Layout.preferredHeight: 14
        }

        BatteryIndicator {
            level: root.batteryLevel
            charging: root.batteryCharging
            Layout.preferredWidth: 28
            Layout.preferredHeight: 18
        }
    }
}
