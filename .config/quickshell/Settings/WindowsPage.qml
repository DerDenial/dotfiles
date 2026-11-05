pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../Theme" as ThemeApi

SPage {
    id: page
    property var info: ({available: false, values: {}, changed: 0, layouts: []})
    property string readError: ""
    property string writeError: ""
    readonly property string error: writeError || readError
    property bool reading: false
    property bool writing: false
    property string readReply: ""
    property string writeReply: ""
    property real pendingColumnWidth: 0.5
    property real pendingMasterRatio: 0.55
    readonly property bool busy: writing || writer.running
    readonly property string helper: Quickshell.env("HOME") + "/.config/quickshell/Settings/window-preferences.py"
    readonly property var choices: [
        {key: "scrolling", name: "Scrolling", detail: "Side-by-side cards"},
        {key: "dwindle", name: "Dwindle", detail: "Classic tiling · Hyprland default"},
        {key: "master", name: "Master", detail: "A main window and a stack"},
        {key: "monocle", name: "Monocle", detail: "One tiled window at a time"}
    ]
    readonly property var layouts: choices.filter(choice => (info.layouts || []).includes(choice.key))

    function available(key) { return info.available === true && info.values && info.values[key] !== undefined && info.values[key] !== null; }
    function value(key, fallback) { return available(key) ? info.values[key] : fallback; }
    function refresh() {
        if (!active || reading || busy || reader.running || columnDebounce.running || masterDebounce.running) return;
        reading = true;
        readReply = "";
        reader.running = true;
        readGuard.restart();
    }
    function change(key, next) {
        if (!active || busy || reading || !available(key)) return;
        if (value(key, null) === next) return;
        startWrite(["set", key, JSON.stringify(next)]);
    }
    function startWrite(argumentList) {
        if (!active || busy || reading) return;
        writeError = "";
        writing = true;
        writeReply = "";
        writer.command = ["python3", helper].concat(argumentList);
        writer.running = true;
        writeGuard.restart();
    }
    function restore() {
        if (!active || busy || reading || !info.changed || !controller) return;
        controller.confirm("Restore window preferences?", "Restore the window options changed here to their previous values.", function() { if (page.active) page.startWrite(["reset"]); });
    }
    function finishRead(code, status) {
        if (!reading) return;
        readGuard.stop();
        reading = false;
        try {
            const next = JSON.parse(readReply);
            if (code !== 0 || status !== 0 || next.error) throw new Error(next.error || "Could not read window preferences.");
            if (typeof next.available !== "boolean" || !next.values || !Array.isArray(next.layouts)) throw new Error("Could not read window preferences.");
            info = next;
            readError = "";
        } catch (exception) { readError = String(exception.message || "Could not read window preferences."); }
    }
    function finishWrite(code, status) {
        if (!writing) return;
        writeGuard.stop();
        writing = false;
        let saved = false;
        try {
            const result = JSON.parse(writeReply);
            if (code !== 0 || status !== 0 || result.ok !== true) throw new Error(result.error || "Could not save the window preference.");
            saved = true;
        } catch (exception) { writeError = String(exception.message || "Could not save the window preference."); }
        // The chosen card follows the compositor's readback, never an optimistic click.
        Qt.callLater(refresh);
        if (saved && controller) controller.toast("Window preference saved");
    }
    onActiveChanged: {
        if (active) refresh();
        else { columnDebounce.stop(); masterDebounce.stop(); }
    }
    Component.onCompleted: refresh()
    property Process reader: Process {
        command: ["python3", page.helper, "get"]
        stdout: StdioCollector { onStreamFinished: page.readReply = text }
        stderr: StdioCollector { }
        onExited: (code, status) => page.finishRead(code, status)
        onRunningChanged: if (!running && page.reading) Qt.callLater(function() { if (!reader.running && page.reading) page.finishRead(-1, -1); })
    }
    property Process writer: Process {
        stdout: StdioCollector { onStreamFinished: page.writeReply = text }
        stderr: StdioCollector { }
        onExited: (code, status) => page.finishWrite(code, status)
        onRunningChanged: if (!running && page.writing) Qt.callLater(function() { if (!writer.running && page.writing) page.finishWrite(-1, -1); })
    }
    property Timer poll: Timer { interval: 5000; repeat: true; running: page.active; onTriggered: page.refresh() }
    property Timer readGuard: Timer {
        interval: 12000
        onTriggered: { if (reader.running) reader.signal(15); page.finishRead(-1, -1); }
    }
    property Timer writeGuard: Timer {
        interval: 12000
        onTriggered: { if (writer.running) writer.signal(15); page.finishWrite(-1, -1); }
    }
    property Timer columnDebounce: Timer { interval: 260; onTriggered: page.change("columnWidth", page.pendingColumnWidth) }
    property Timer masterDebounce: Timer { interval: 260; onTriggered: page.change("masterRatio", page.pendingMasterRatio) }

    SNotice { text: page.error; warning: true }
    SNotice { text: !page.info.available && !page.reading ? "Window controls are unavailable until Hyprland is reachable." : "" }
    SCard {
        title: "Window layout"
        subtitle: "Default layout for tiled windows. Changing it rearranges open tiles; workspace-specific rules can override this choice."
        iconName: "view_quilt"
        GridLayout {
            id: layoutGrid
            Layout.fillWidth: true
            columns: width >= 740 ? 4 : 2
            columnSpacing: 10
            rowSpacing: 10
            Repeater {
                model: page.layouts
                delegate: Button {
                    id: layoutChoice
                    required property var modelData
                    readonly property bool selected: page.value("layout", "") === modelData.key
                    objectName: "layoutChoice_" + modelData.key
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 158
                    Layout.minimumWidth: 100
                    enabled: page.available("layout") && !page.busy && !page.reading
                    padding: 12
                    Accessible.name: modelData.name + ": " + modelData.detail
                    Accessible.description: selected ? "Current layout" : "Use this layout for tiled windows"
                    onClicked: page.change("layout", modelData.key)
                    background: Rectangle {
                        radius: 15
                        color: layoutChoice.selected ? ThemeApi.Theme.accentSoft : layoutChoice.hovered ? ThemeApi.Theme.surfaceRaised : ThemeApi.Theme.surfaceAlt
                        border.width: layoutChoice.selected || layoutChoice.activeFocus ? 2 : 1
                        border.color: layoutChoice.selected || layoutChoice.activeFocus ? ThemeApi.Theme.accent : Qt.alpha(ThemeApi.Theme.border, 0.45)
                    }
                    contentItem: ColumnLayout {
                        spacing: 8
                        LayoutPreview { Layout.fillWidth: true; Layout.preferredHeight: 66; kind: layoutChoice.modelData.key; selected: layoutChoice.selected }
                        RowLayout {
                            Layout.fillWidth: true
                            SLabel { text: layoutChoice.modelData.name; Layout.fillWidth: true; font.pixelSize: 12; font.weight: Font.DemiBold }
                            Text { text: "check_circle"; visible: layoutChoice.selected; font.family: "Material Symbols Rounded"; font.pixelSize: 16; color: ThemeApi.Theme.accent }
                        }
                        SLabel { text: layoutChoice.modelData.detail; Layout.fillWidth: true; Layout.fillHeight: true; font.pixelSize: 10; color: ThemeApi.Theme.muted; wrapMode: Text.WordWrap }
                    }
                }
            }
        }
        SLabel { visible: page.reading && !page.layouts.length; text: "Reading available layouts…"; color: ThemeApi.Theme.muted; font.pixelSize: 12 }
    }
    SCard {
        visible: page.value("layout", "") === "scrolling"
        title: "Side-by-side cards"
        subtitle: "New windows form columns on a scrolling workspace."
        iconName: "view_carousel"
        SRow { title: "New column width"; subtitle: "The starting width of newly opened columns."; value: Math.round(page.value("columnWidth", 0.5) * 100) + "%" }
        SSlider {
            objectName: "columnWidthSlider"
            Layout.fillWidth: true
            from: 0.1; to: 1; stepSize: 0.05
            value: page.value("columnWidth", 0.5)
            enabled: page.available("columnWidth") && !page.busy && !page.reading
            onMoved: { page.pendingColumnWidth = value; page.columnDebounce.restart(); }
        }
        SRow {
            title: "Fill the screen with one column"
            subtitle: "Use the whole width when a workspace contains only one column."
            SToggle { objectName: "singleColumnToggle"; checked: page.value("singleColumnFull", false); enabled: page.available("singleColumnFull") && !page.busy && !page.reading; onToggled: page.change("singleColumnFull", checked) }
        }
        SRow { title: "New window direction"; subtitle: "Where the next column appears." }
        Flow {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: [{key: "left", title: "Left", icon: "west"}, {key: "right", title: "Right", icon: "east"}, {key: "up", title: "Up", icon: "north"}, {key: "down", title: "Down", icon: "south"}]
                delegate: SButton {
                    required property var modelData
                    text: modelData.title
                    iconName: modelData.icon
                    accent: page.value("scrollDirection", "right") === modelData.key
                    enabled: page.available("scrollDirection") && !page.busy && !page.reading
                    onClicked: page.change("scrollDirection", modelData.key)
                }
            }
        }
    }
    SCard {
        visible: page.value("layout", "") === "dwindle"
        title: "Classic tiling"
        subtitle: "Each new window splits the available space into smaller tiles."
        iconName: "grid_view"
        SRow {
            title: "Keep split direction"
            subtitle: "Keep side-by-side or stacked splits when a window changes shape."
            SToggle { objectName: "preserveSplitToggle"; checked: page.value("preserveSplit", false); enabled: page.available("preserveSplit") && !page.busy && !page.reading; onToggled: page.change("preserveSplit", checked) }
        }
    }
    SCard {
        visible: page.value("layout", "") === "master"
        title: "Main window & stack"
        subtitle: "Give one window more space and keep the rest together."
        iconName: "view_sidebar"
        SRow { title: "Main window width"; value: Math.round(page.value("masterRatio", 0.55) * 100) + "%" }
        SSlider {
            objectName: "masterRatioSlider"
            Layout.fillWidth: true
            from: 0.1; to: 0.9; stepSize: 0.05
            value: page.value("masterRatio", 0.55)
            enabled: page.available("masterRatio") && !page.busy && !page.reading
            onMoved: { page.pendingMasterRatio = value; page.masterDebounce.restart(); }
        }
        SRow { title: "New window placement"; subtitle: "Choose whether a new window becomes the main window or joins the stack." }
        Flow {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: [{key: "master", title: "Main window"}, {key: "slave", title: "Stack"}, {key: "inherit", title: "Follow focused"}]
                delegate: SButton {
                    required property var modelData
                    text: modelData.title
                    accent: page.value("newWindowPosition", "master") === modelData.key
                    enabled: page.available("newWindowPosition") && !page.busy && !page.reading
                    onClicked: page.change("newWindowPosition", modelData.key)
                }
            }
        }
    }
    SCard {
        visible: page.value("layout", "") === "monocle"
        title: "One window at a time"
        subtitle: "Each tiled window fills the workspace. Switch between them with your window shortcuts."
        iconName: "crop_square"
    }
    SRow {
        title: "Restore window preferences"
        subtitle: "Return only the options changed here to their previous values."
        SButton { objectName: "restoreWindows"; text: "Restore"; enabled: page.info.changed > 0 && !page.busy && !page.reading; onClicked: page.restore() }
    }

    component LayoutPreview: Item {
        id: preview
        property string kind: "scrolling"
        property bool selected: false
        readonly property var tiles: kind === "scrolling" ? [[0,0,0.46,1],[0.5,0,0.46,1]]
            : kind === "dwindle" ? [[0,0,0.47,1],[0.51,0,0.49,0.46],[0.51,0.52,0.22,0.48],[0.77,0.52,0.23,0.48]]
            : kind === "master" ? [[0,0,0.60,1],[0.64,0,0.36,0.46],[0.64,0.52,0.36,0.48]]
            : [[0,0,1,1]]
        Rectangle { anchors.fill: parent; radius: 8; color: Qt.alpha(ThemeApi.Theme.bg0, 0.75) }
        Item {
            anchors.fill: parent
            anchors.margins: 7
            clip: true
            Repeater {
                model: preview.tiles
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    x: modelData[0] * parent.width; y: modelData[1] * parent.height
                    width: modelData[2] * parent.width; height: modelData[3] * parent.height
                    radius: 4
                    color: preview.selected ? Qt.alpha(ThemeApi.Theme.accent, index === 0 ? 0.5 : 0.24) : index === 0 ? ThemeApi.Theme.mutedStrong : ThemeApi.Theme.border
                    Rectangle { x: 4; y: 5; width: Math.min(18, parent.width - 8); height: 2; radius: 1; color: Qt.alpha(ThemeApi.Theme.textBright, 0.65) }
                }
            }
        }
    }
}
