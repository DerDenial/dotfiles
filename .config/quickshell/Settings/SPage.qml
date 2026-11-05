import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../Theme" as ThemeApi
SMomentumFlickable {
    id: root
    property var controller: null
    property bool active: true
    kineticEnabled: active
    default property alias content: stack.data
    clip: true
    contentWidth: width
    contentHeight: stack.implicitHeight + 24
    interactive: contentHeight > height
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    ScrollBar.vertical: ScrollBar {
        policy: root.contentHeight > root.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        contentItem: Rectangle { implicitWidth: 4; radius: 2; color: ThemeApi.Theme.mutedStrong; opacity: parent.active ? 0.8 : 0.35 }
        background: Item {}
    }
    property ColumnLayout stackLayout: ColumnLayout {
        id: stack
        parent: root.contentItem
        width: root.width - 10
        spacing: 18
    }
}
