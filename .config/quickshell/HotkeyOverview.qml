pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "Theme" as ThemeApi

// A passive hold-to-peek surface: input always reaches the existing desktop.
PanelWindow {
    id: guide

    property bool shown: false
    property var groups: []
    property bool loading: false
    property string status: ""
    property string error: ""

    readonly property real cardWidth: Math.max(240, Math.min(980, width - 48))
    readonly property real maximumCardHeight: Math.max(180, Math.min(720, height - 104))
    readonly property int columnCount: cardWidth >= 820 ? 3 : cardWidth >= 540 ? 2 : 1
    readonly property var visibleGroups: groups.filter(group => group && Array.isArray(group.entries) && group.entries.length)
    readonly property var columns: buildColumns()
    readonly property int totalBindings: visibleGroups.reduce((total, group) => total + group.entries.length, 0)
    readonly property int densestColumn: columns.reduce((most, column) => Math.max(most, column.entries), 0)
    readonly property real maximumGroupChrome: columns.reduce((most, column) => Math.max(most, column.groups.length * 50 + Math.max(0, column.groups.length - 1) * 10), 0)
    readonly property real rowHeight: Math.max(21, Math.min(29, Math.floor((maximumCardHeight - 126 - maximumGroupChrome) / Math.max(1, densestColumn))))
    readonly property real bodyHeight: Math.max(100, Math.min(maximumCardHeight - 126, columns.reduce((tallest, column) => Math.max(tallest, column.entries * rowHeight + column.groups.length * 50 + Math.max(0, column.groups.length - 1) * 10), 0)))
    property real reveal: 0

    function buildColumns() {
        const result = [];
        for (let i = 0; i < columnCount; ++i) result.push({ groups: [], entries: 0, weight: 0 });
        for (const group of visibleGroups) {
            let target = 0;
            for (let i = 1; i < result.length; ++i) {
                if (result[i].weight < result[target].weight) target = i;
            }
            result[target].groups.push(group);
            result[target].entries += group.entries.length;
            result[target].weight += group.entries.length + 2.5;
        }
        return result;
    }
    function keyLabel(key) {
        const value = String(key);
        const replacements = {
            "SUPER": "Super", "Super": "Super", "META": "Super", "Meta": "Super",
            "SHIFT": "⇧", "Shift": "⇧", "CTRL": "Ctrl", "CONTROL": "Ctrl", "Control": "Ctrl",
            "ALT": "Alt", "Alt": "Alt", "Up": "↑", "Down": "↓", "Left": "←", "Right": "→",
            "UP": "↑", "DOWN": "↓", "LEFT": "←", "RIGHT": "→", "Return": "Enter", "RETURN": "Enter",
            "Escape": "Esc", "ESCAPE": "Esc", "space": "Space", "Space": "Space", "SPACE": "Space",
            "period": ".", "PERIOD": ".", "Print": "Print", "PRINT": "Print", "mouse_down": "↓ wheel", "mouse_up": "↑ wheel"
        };
        return replacements[value] || value;
    }

    visible: shown || reveal > 0.001 || revealAnimation.running
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    aboveWindows: true
    WlrLayershell.namespace: "qs-hotkey-guide"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    onShownChanged: {
        if (shown) bodyLoader.ensureLoaded();
        revealAnimation.stop();
        revealAnimation.to = shown ? 1 : 0;
        revealAnimation.duration = shown ? 230 : 145;
        revealAnimation.start();
    }
    Component.onCompleted: if (shown) {
        bodyLoader.ensureLoaded();
        reveal = 1;
    }

    NumberAnimation {
        id: revealAnimation
        target: guide
        property: "reveal"
        easing.type: guide.shown ? Easing.OutBack : Easing.InCubic
        easing.overshoot: 0.55
    }

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: 54 - (1 - guide.reveal) * 9
        width: guide.cardWidth
        height: guide.bodyHeight + 126
        radius: 26
        color: Qt.alpha(ThemeApi.Theme.notchBg, 0.94)
        border.width: 1
        border.color: Qt.alpha(ThemeApi.Theme.border, 0.7)
        opacity: Math.max(0, Math.min(1, guide.reveal * 1.8))
        scale: 0.97 + guide.reveal * 0.03
        transformOrigin: Item.Top

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            width: 64
            height: 2
            radius: 1
            color: Qt.alpha(ThemeApi.Theme.accent, 0.8)
        }

        MenuBodyLoader {
            id: bodyLoader
            anchors.fill: parent
            anchors.margins: 20
            engaged: guide.shown || revealAnimation.running
            sourceComponent: Component {
                Item {
                    id: body

                    RowLayout {
                        id: header
                        width: parent.width
                        height: 44
                        spacing: 12

                        Rectangle {
                            Layout.preferredWidth: 42
                            Layout.preferredHeight: 42
                            radius: 14
                            color: ThemeApi.Theme.accentSoft
                            Text {
                                anchors.centerIn: parent
                                text: "keyboard_command_key"
                                color: ThemeApi.Theme.accent
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 25
                            }
                        }
                        Column {
                            Layout.fillWidth: true
                            spacing: 4
                            Text {
                                text: "Your shortcuts"
                                color: ThemeApi.Theme.textBright
                                font.family: "Inter"
                                font.pixelSize: 21
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: guide.loading ? "Reading your keyboard shortcuts…" : "A little reminder, right when you need it"
                                textFormat: Text.PlainText
                                color: ThemeApi.Theme.muted
                                font.family: "Inter"
                                font.pixelSize: 11
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: heldKey.implicitWidth + 20
                            Layout.preferredHeight: 30
                            radius: 10
                            color: Qt.alpha(ThemeApi.Theme.accent, 0.1)
                            border.width: 1
                            border.color: Qt.alpha(ThemeApi.Theme.accent, 0.28)
                            Text {
                                id: heldKey
                                anchors.centerIn: parent
                                text: "Super held"
                                color: ThemeApi.Theme.accent
                                font.family: "Inter"
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }
                        }
                    }

                    Row {
                        id: categoryColumns
                        y: 62
                        width: parent.width
                        height: guide.bodyHeight
                        spacing: 10
                        visible: guide.totalBindings > 0

                        Repeater {
                            model: guide.columns
                            delegate: ListView {
                                id: categoryColumn
                                required property var modelData
                                width: (categoryColumns.width - (guide.columnCount - 1) * categoryColumns.spacing) / guide.columnCount
                                height: categoryColumns.height
                                model: modelData.groups
                                spacing: 10
                                interactive: false
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                cacheBuffer: 0

                                delegate: GroupCard {
                                    required property var modelData
                                    width: categoryColumn.width
                                    group: modelData
                                }
                            }
                        }
                    }

                    Column {
                        anchors.centerIn: categoryColumns
                        width: parent.width - 40
                        spacing: 10
                        visible: guide.totalBindings === 0
                        Text {
                            width: parent.width
                            text: guide.error ? "keyboard_off" : "keyboard"
                            color: ThemeApi.Theme.accent
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 32
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            width: parent.width
                            text: guide.error || (guide.loading ? "Getting your shortcuts ready…" : "No shortcuts available")
                            textFormat: Text.PlainText
                            color: ThemeApi.Theme.muted
                            font.family: "Inter"
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                        }
                    }

                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 22
                        spacing: 8
                        Text {
                            text: "info"
                            color: ThemeApi.Theme.mutedStrong
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 15
                        }
                        Text {
                            Layout.fillWidth: true
                            text: guide.error && guide.totalBindings > 0 ? guide.error : guide.status || "Keep holding Super to peek · shortcuts work as usual"
                            textFormat: Text.PlainText
                            color: ThemeApi.Theme.muted
                            font.family: "Inter"
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                        Text {
                            text: guide.totalBindings + " shortcuts"
                            visible: guide.totalBindings > 0
                            color: ThemeApi.Theme.mutedStrong
                            font.family: "Inter"
                            font.pixelSize: 10
                        }
                        Rectangle {
                            Layout.preferredWidth: 1
                            Layout.preferredHeight: 12
                            color: ThemeApi.Theme.border
                        }
                        Text {
                            text: "Release Super to close"
                            color: ThemeApi.Theme.accent
                            font.family: "Inter"
                            font.pixelSize: 10
                            font.weight: Font.Medium
                        }
                    }
                }
            }
        }
    }

    component Keycap: Rectangle {
        id: keycap
        required property string keyName
        readonly property bool superKey: keyName.toLowerCase() === "super" || keyName.toLowerCase() === "meta"
        width: keyText.implicitWidth + (superKey ? 12 : 10)
        height: Math.min(23, guide.rowHeight - 3)
        radius: 6
        color: superKey ? Qt.alpha(ThemeApi.Theme.accent, 0.11) : Qt.alpha(ThemeApi.Theme.surfaceRaised, 0.7)
        border.width: 1
        border.color: superKey ? Qt.alpha(ThemeApi.Theme.accent, 0.23) : Qt.alpha(ThemeApi.Theme.border, 0.6)
        Text {
            id: keyText
            anchors.centerIn: parent
            text: guide.keyLabel(keycap.keyName)
            textFormat: Text.PlainText
            color: keycap.superKey ? ThemeApi.Theme.accent : ThemeApi.Theme.text
            font.family: "Inter"
            font.pixelSize: guide.rowHeight < 25 ? 9 : 10
            font.weight: Font.Medium
        }
    }

    component GroupCard: Rectangle {
        id: groupCard
        required property var group
        height: 50 + group.entries.length * guide.rowHeight
        radius: 17
        color: Qt.alpha(ThemeApi.Theme.surface, 0.64)
        border.width: 1
        border.color: Qt.alpha(ThemeApi.Theme.border, 0.38)

        Row {
            x: 12
            y: 12
            spacing: 7
            Text {
                text: groupCard.group.icon || "keyboard"
                textFormat: Text.PlainText
                color: ThemeApi.Theme.accent
                font.family: "Material Symbols Rounded"
                font.pixelSize: 18
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: groupCard.group.title
                textFormat: Text.PlainText
                color: ThemeApi.Theme.textBright
                font.family: "Inter"
                font.pixelSize: 11
                font.weight: Font.DemiBold
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Column {
            x: 12
            y: 39
            width: parent.width - 24
            Repeater {
                model: groupCard.group.entries
                delegate: Item {
                    id: shortcutRow
                    required property var modelData
                    required property int index
                    width: Math.max(0, groupCard.width - 24)
                    height: guide.rowHeight
                    Rectangle {
                        x: 0
                        y: 0
                        width: parent.width
                        height: 1
                        visible: shortcutRow.index > 0
                        color: Qt.alpha(ThemeApi.Theme.border, 0.13)
                    }
                    Column {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, caps.x - 6)
                        spacing: 0
                        Text {
                            width: parent.width
                            text: shortcutRow.modelData.label
                            textFormat: Text.PlainText
                            color: ThemeApi.Theme.text
                            font.family: "Inter"
                            font.pixelSize: guide.rowHeight < 25 ? 10 : 11
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            visible: Boolean(shortcutRow.modelData.hint)
                            text: shortcutRow.modelData.hint || ""
                            textFormat: Text.PlainText
                            color: ThemeApi.Theme.muted
                            font.family: "Inter"
                            font.pixelSize: 8
                            elide: Text.ElideRight
                        }
                    }
                    Row {
                        id: caps
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Repeater {
                            model: shortcutRow.modelData.keys || []
                            delegate: Keycap {
                                required property var modelData
                                keyName: String(modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
