import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "Theme" as ThemeApi

PanelWindow {
    id: clipboard

    property alias opened: menuTransition.opened
    property alias closing: menuTransition.closing
    readonly property bool active: menuTransition.active
    readonly property bool ownsSurface: menuTransition.ownsSurface
    readonly property bool returning: menuTransition.returning
    readonly property real morphProgress: menuTransition.motion.amount
    property Item sourceNotch: null
    property bool canOpen: true
    property string clockValue: "00:00"
    property int batteryLevel: 0
    property bool batteryCharging: false
    property int filterIndex: 0
    property int selectedIndex: 0
    property string selectedId: ""
    property real ageNow: Date.now()
    property bool clearConfirmation: false
    property string searchQuery: ""
    readonly property var filterNames: ["All", "Text", "Images", "Pinned"]
    readonly property var filterIcons: ["view_agenda", "notes", "image", "push_pin"]
    readonly property var filterKeys: ["all", "text", "image", "pinned"]
    readonly property var selectedItem: selectedIndex >= 0 && selectedIndex < state.items.length ? state.items[selectedIndex] : null
    readonly property bool canAct: state.available && !state.busy && !state.queryPending
    readonly property int unpinnedCount: Math.max(0, state.total - state.pinnedCount)
    readonly property var searchControl: bodyLoader.item ? bodyLoader.item.searchControl : null
    readonly property var entriesView: bodyLoader.item ? bodyLoader.item.entriesView : null
    signal aboutToOpen()

    property ClipboardState state: ClipboardState {
        polling: clipboard.opened
        query: clipboard.searchQuery.trim()
        filter: clipboard.filterKeys[clipboard.filterIndex]
        onCopied: clipboard.close()
        onItemsChanged: clipboard.retainSelection()
    }

    NotchTransition {
        id: menuTransition
        dropdownAlignment: 0.5
        surface: card
        sourceNotch: clipboard.sourceNotch
        expandedWidth: Math.min(720, clipboard.width - 40)
        expandedHeight: Math.min(620, clipboard.height - (menuTransition.dropdown ? 58 : 24))
        canOpen: clipboard.canOpen
        onAboutToOpen: clipboard.aboutToOpen()
        onActivated: Qt.callLater(function() { if (clipboard.opened && clipboard.searchControl) clipboard.searchControl.forceActiveFocus(); })
    }

    function open() {
        if (opened || menuTransition.preparing || menuTransition.capturePending) return;
        if (!bodyLoader.ensureLoaded()) return;
        if (!closing && !returning) {
            filterIndex = 0;
            selectedIndex = 0;
            selectedId = "";
            clearConfirmation = false;
            if (searchControl) searchControl.clear();
            state.actionError = "";
        }
        state.refresh();
        menuTransition.open();
    }
    function close() {
        clearConfirmation = false;
        menuTransition.close();
        if (searchControl) searchControl.focus = false;
    }
    function toggle() {
        if (opened || menuTransition.pendingOpen || menuTransition.preparing || menuTransition.capturePending) close();
        else open();
    }
    function focusSearch() { if (searchControl) searchControl.forceActiveFocus(); }
    function retainSelection() {
        const found = state.items.findIndex(item => String(item.id) === selectedId);
        selectedIndex = found >= 0 ? found : Math.max(0, Math.min(selectedIndex, state.items.length - 1));
        selectedId = state.items.length ? String(state.items[selectedIndex].id) : "";
    }
    function select(index) {
        if (index < 0 || index >= state.items.length) return;
        selectedIndex = index;
        selectedId = String(state.items[index].id);
        if (entriesView) entriesView.positionViewAtIndex(index, ListView.Contain);
    }
    function moveSelection(direction) {
        if (!state.items.length) return;
        select((selectedIndex + direction + state.items.length) % state.items.length);
    }
    function chooseFilter(index) {
        filterIndex = index;
        selectedIndex = 0;
        selectedId = "";
        clearConfirmation = false;
        if (entriesView) entriesView.positionViewAtBeginning();
        focusSearch();
    }
    function copySelection() {
        if (selectedItem && canAct) state.copy(selectedItem.id);
    }
    function handleKey(event) {
        if (event.key === Qt.Key_Escape) {
            if (clearConfirmation) clearConfirmation = false;
            else close();
        } else if (event.key === Qt.Key_Up) moveSelection(-1);
        else if (event.key === Qt.Key_Down) moveSelection(1);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (!clearConfirmation) copySelection();
        } else if (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier)) {
            if (selectedItem && canAct) state.togglePin(selectedItem.id);
        } else if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ControlModifier)) {
            if (selectedItem && canAct) state.remove(selectedItem.id);
        } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_4 && (event.modifiers & Qt.ControlModifier)) {
            chooseFilter(event.key - Qt.Key_1);
        } else return;
        event.accepted = true;
    }
    function itemTitle(item) {
        if (!item) return "";
        return item.title || (item.type === "image" ? "Image" : String(item.preview || "Text").split(/\r?\n/)[0]) || "Text";
    }
    function sizeLabel(size) {
        const bytes = Number(size || 0);
        if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MB";
        if (bytes >= 1024) return Math.round(bytes / 1024) + " KB";
        return bytes + " B";
    }
    function ageLabel(created) {
        const date = new Date(Number(created || 0));
        const elapsed = Math.max(0, Math.floor((ageNow - date.getTime()) / 60000));
        if (elapsed < 1) return "Just now";
        if (elapsed < 60) return elapsed + " min ago";
        if (elapsed < 1440) return Math.floor(elapsed / 60) + " h ago";
        return Qt.formatDateTime(date, "d MMM");
    }
    function imageSource(item) {
        if (!item || item.type !== "image") return "";
        return item.imageUrl || (item.imagePath ? "file://" + item.imagePath : "");
    }

    visible: menuTransition.visible
    WlrLayershell.keyboardFocus: opened || menuTransition.preparing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    onOpenedChanged: if (opened) ageNow = Date.now()
    Timer { interval: 60000; repeat: true; running: clipboard.opened; onTriggered: clipboard.ageNow = Date.now() }

    IpcHandler {
        target: "clipboardHistory"
        function toggle(): void { clipboard.toggle(); }
        function open(): void { clipboard.open(); }
        function close(): void { clipboard.close(); }
    }

    component IconAction: ToolButton {
        id: iconButton
        required property string symbol
        property bool destructive: false
        implicitWidth: 34
        implicitHeight: 34
        focusPolicy: Qt.NoFocus
        Accessible.name: ToolTip.text
        ToolTip.visible: hovered
        ToolTip.delay: 450
        contentItem: Text {
            text: iconButton.symbol
            color: !iconButton.enabled ? ThemeApi.Theme.mutedStrong : iconButton.destructive ? ThemeApi.Theme.red : iconButton.highlighted ? ThemeApi.Theme.accent : ThemeApi.Theme.muted
            font.family: "Material Symbols Rounded"
            font.pixelSize: 19
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 11
            color: iconButton.down ? ThemeApi.Theme.surfaceRaised : iconButton.hovered || iconButton.highlighted ? ThemeApi.Theme.surfaceAlt : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
        }
    }
    component ActionButton: Button {
        id: actionButton
        property string symbol: ""
        property bool emphasized: false
        property bool destructive: false
        implicitHeight: 36
        implicitWidth: contentItem.implicitWidth + 24
        leftPadding: 12
        rightPadding: 12
        focusPolicy: Qt.NoFocus
        contentItem: Row {
            spacing: 6
            Text {
                visible: actionButton.symbol !== ""
                text: actionButton.symbol
                anchors.verticalCenter: parent.verticalCenter
                color: !actionButton.enabled ? ThemeApi.Theme.mutedStrong : actionButton.emphasized ? ThemeApi.Theme.onAccent : actionButton.destructive ? ThemeApi.Theme.red : ThemeApi.Theme.text
                font.family: "Material Symbols Rounded"
                font.pixelSize: 17
            }
            Text {
                text: actionButton.text
                anchors.verticalCenter: parent.verticalCenter
                color: !actionButton.enabled ? ThemeApi.Theme.mutedStrong : actionButton.emphasized ? ThemeApi.Theme.onAccent : actionButton.destructive ? ThemeApi.Theme.red : ThemeApi.Theme.text
                font.family: "Inter"
                font.pixelSize: 11
                font.weight: Font.Medium
            }
        }
        background: Rectangle {
            radius: 12
            color: actionButton.emphasized && actionButton.enabled ? ThemeApi.Theme.accent : actionButton.down ? ThemeApi.Theme.surfaceRaised : actionButton.hovered ? ThemeApi.Theme.surfaceRaised : ThemeApi.Theme.surface
            border.width: actionButton.emphasized ? 0 : 1
            border.color: ThemeApi.Theme.border
            opacity: actionButton.enabled ? 1 : 0.55
        }
    }

    MouseArea { anchors.fill: parent; enabled: clipboard.opened; onClicked: clipboard.close() }

    NotchMenuSurface {
        id: card
        transition: menuTransition
        color: ThemeApi.Theme.notchBg
        border.width: 1
        border.color: ThemeApi.Theme.border
        Keys.onPressed: function(event) { clipboard.handleKey(event); }

        Rectangle { visible: !menuTransition.dropdown; x: 0; y: 0; width: parent.width; height: parent.border.width; color: parent.color; z: 100 }
        MouseArea { anchors.fill: parent; enabled: clipboard.opened }

        MenuBodyLoader {
            id: bodyLoader
            engaged: menuTransition.active || menuTransition.pendingOpen || clipboard.state.busy || (retained && clipboard.state.loading)
            width: menuTransition.expandedWidth - 40
            height: menuTransition.expandedHeight - 36
            anchors.horizontalCenter: parent.horizontalCenter
            y: 18 * Math.min(1, bodyStretch.unfold)
            enabled: clipboard.opened
            visible: clipboard.opened || clipboard.closing
            transform: NotchContentStretch {
                id: bodyStretch
                transition: menuTransition
                canvasWidth: menuTransition.expandedWidth - 40
                horizontalInset: 40
            }
            onLoaded: {
                item.searchControl.text = clipboard.searchQuery;
                item.initializingSearch = false;
            }
            sourceComponent: Component {
                ColumnLayout {
                    id: clipboardBody
                    property bool initializingSearch: true
                    property alias searchControl: searchField
                    property alias entriesView: entries
                    anchors.fill: parent
                    spacing: 12

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                spacing: 12
                Rectangle {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    radius: 15
                    color: ThemeApi.Theme.accentSoft
                    Text { anchors.centerIn: parent; text: "content_paste"; color: ThemeApi.Theme.accent; font.family: "Material Symbols Rounded"; font.pixelSize: 24 }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Text { text: "Clipboard"; color: ThemeApi.Theme.textBright; font.family: "Inter"; font.pixelSize: 20; font.weight: Font.DemiBold }
                    Text {
                        Layout.fillWidth: true
                        text: clipboard.state.paused ? "History paused · existing items stay available" : "Your recent text and images, within reach"
                        color: ThemeApi.Theme.muted
                        font.family: "Inter"
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }
                ActionButton {
                    text: clipboard.state.paused ? "Resume" : "Pause"
                    symbol: clipboard.state.paused ? "play_arrow" : "pause"
                    enabled: clipboard.canAct
                    onClicked: { clipboard.state.togglePaused(); clipboard.focusSearch(); }
                    ToolTip.visible: hovered
                    ToolTip.delay: 400
                    ToolTip.text: clipboard.state.paused ? "Resume saving new clipboard items" : "Stop saving new clipboard items"
                }
                IconAction {
                    symbol: "delete_sweep"
                    ToolTip.text: "Clear unpinned history"
                    enabled: clipboard.canAct && clipboard.unpinnedCount > 0
                    highlighted: clipboard.clearConfirmation
                    onClicked: { clipboard.clearConfirmation = !clipboard.clearConfirmation; clipboard.focusSearch(); }
                }
                IconAction { symbol: "close"; ToolTip.text: "Close · Esc"; onClicked: clipboard.close() }
            }

            TextField {
                id: searchField
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                focus: clipboard.opened
                leftPadding: 42
                rightPadding: 38
                verticalAlignment: TextInput.AlignVCenter
                placeholderText: "Search clipboard history…"
                placeholderTextColor: ThemeApi.Theme.muted
                color: ThemeApi.Theme.textBright
                selectionColor: ThemeApi.Theme.accent
                selectedTextColor: ThemeApi.Theme.onAccent
                font.family: "Inter"
                font.pixelSize: 14
                clip: true
                background: Rectangle {
                    radius: 15
                    color: ThemeApi.Theme.surface
                    border.width: 1
                    border.color: searchField.activeFocus ? ThemeApi.Theme.accent : ThemeApi.Theme.border
                }
                Text { x: 13; anchors.verticalCenter: parent.verticalCenter; text: "search"; color: ThemeApi.Theme.accent; font.family: "Material Symbols Rounded"; font.pixelSize: 21 }
                IconAction {
                    anchors.right: parent.right
                    anchors.rightMargin: 3
                    anchors.verticalCenter: parent.verticalCenter
                    symbol: "close"
                    ToolTip.text: "Clear search"
                    visible: searchField.text.length > 0
                    onClicked: { searchField.clear(); clipboard.focusSearch(); }
                }
                onTextChanged: {
                    if (clipboardBody.initializingSearch) return;
                    clipboard.searchQuery = text;
                    clipboard.selectedIndex = 0;
                    clipboard.selectedId = "";
                    clipboard.clearConfirmation = false;
                }
                Keys.onPressed: function(event) { clipboard.handleKey(event); }
                Keys.onTabPressed: clipboard.chooseFilter((clipboard.filterIndex + 1) % 4)
                Keys.onBacktabPressed: clipboard.chooseFilter((clipboard.filterIndex + 3) % 4)
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                spacing: 6
                Repeater {
                    model: clipboard.filterNames
                    delegate: Button {
                        id: filterButton
                        required property string modelData
                        required property int index
                        readonly property bool chosen: index === clipboard.filterIndex
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        focusPolicy: Qt.NoFocus
                        contentItem: Item {
                            implicitWidth: filterLabel.implicitWidth
                            implicitHeight: filterLabel.implicitHeight
                            Row {
                                id: filterLabel
                                spacing: 6
                                anchors.centerIn: parent
                                Text { text: clipboard.filterIcons[filterButton.index]; color: filterButton.chosen ? ThemeApi.Theme.accent : ThemeApi.Theme.muted; font.family: "Material Symbols Rounded"; font.pixelSize: 16 }
                                Text { text: filterButton.modelData; color: filterButton.chosen ? ThemeApi.Theme.accent : ThemeApi.Theme.muted; font.family: "Inter"; font.pixelSize: 11; font.weight: filterButton.chosen ? Font.DemiBold : Font.Normal }
                            }
                        }
                        background: Rectangle {
                            radius: 11
                            color: filterButton.chosen ? ThemeApi.Theme.accentSoft : filterButton.hovered ? ThemeApi.Theme.surface : "transparent"
                            border.width: filterButton.chosen ? 1 : 0
                            border.color: ThemeApi.Theme.accent
                        }
                        onClicked: clipboard.chooseFilter(index)
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: clearRow.implicitHeight + 20
                visible: clipboard.clearConfirmation
                radius: 14
                color: ThemeApi.Theme.surfaceAlt
                border.width: 1
                border.color: ThemeApi.Theme.border
                RowLayout {
                    id: clearRow
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        text: "Clear " + clipboard.unpinnedCount + " unpinned items?\nPinned items stay in your history."
                        color: ThemeApi.Theme.text
                        font.family: "Inter"
                        font.pixelSize: 11
                    }
                    ActionButton { text: "Cancel"; onClicked: { clipboard.clearConfirmation = false; clipboard.focusSearch(); } }
                    ActionButton {
                        text: "Clear history"
                        destructive: true
                        enabled: clipboard.canAct
                        onClicked: { clipboard.state.clearUnpinned(); clipboard.clearConfirmation = false; clipboard.focusSearch(); }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: errorRow.implicitHeight + 20
                visible: clipboard.state.error !== ""
                radius: 14
                color: ThemeApi.Theme.surface
                RowLayout {
                    id: errorRow
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8
                    Text { text: "info"; color: ThemeApi.Theme.red; font.family: "Material Symbols Rounded"; font.pixelSize: 20 }
                    Text { Layout.fillWidth: true; text: clipboard.state.error; color: ThemeApi.Theme.text; font.family: "Inter"; font.pixelSize: 11; wrapMode: Text.Wrap }
                    ActionButton { text: "Retry"; onClicked: { clipboard.state.actionError = ""; clipboard.state.restartRecorder(); clipboard.focusSearch(); } }
                }
            }

            RowLayout {
                id: body
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 120
                spacing: 12

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    ListView {
                        id: entries
                        anchors.fill: parent
                        spacing: 7
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: clipboard.state.items
                        currentIndex: clipboard.selectedIndex
                        interactive: contentHeight > height
                        ScrollBar.vertical: ScrollBar { policy: entries.contentHeight > entries.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                        delegate: Rectangle {
                            id: entry
                            required property int index
                            required property var modelData
                            readonly property bool selected: index === clipboard.selectedIndex
                            width: entries.width - 4
                            height: 82
                            radius: 15
                            color: selected ? ThemeApi.Theme.accentSoft : rowMouse.containsMouse ? ThemeApi.Theme.surfaceAlt : ThemeApi.Theme.surface
                            border.width: selected ? 1 : 0
                            border.color: ThemeApi.Theme.accent
                            Behavior on color { ColorAnimation { duration: 130 } }
                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { clipboard.select(entry.index); clipboard.focusSearch(); }
                                onDoubleClicked: { clipboard.select(entry.index); clipboard.copySelection(); }
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 9
                                Rectangle {
                                    Layout.preferredWidth: 46
                                    Layout.preferredHeight: 56
                                    radius: 10
                                    color: entry.selected ? ThemeApi.Theme.surfaceRaised : ThemeApi.Theme.surfaceAlt
                                    clip: true
                                    Image {
                                        anchors.fill: parent
                                        visible: entry.modelData.type === "image"
                                        source: menuTransition.active ? clipboard.imageSource(entry.modelData) : ""
                                        cache: false
                                        sourceSize.width: 128
                                        sourceSize.height: 128
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }
                                    Text { anchors.centerIn: parent; visible: entry.modelData.type !== "image"; text: "notes"; color: entry.selected ? ThemeApi.Theme.accent : ThemeApi.Theme.muted; font.family: "Material Symbols Rounded"; font.pixelSize: 23 }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Text {
                                        Layout.fillWidth: true
                                        text: clipboard.itemTitle(entry.modelData)
                                        textFormat: Text.PlainText
                                        color: ThemeApi.Theme.textBright
                                        font.family: "Inter"
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: entry.modelData.type === "image" ? clipboard.sizeLabel(entry.modelData.size) : String(entry.modelData.preview || "").replace(/\s+/g, " ")
                                        textFormat: Text.PlainText
                                        color: ThemeApi.Theme.muted
                                        font.family: "Inter"
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                    }
                                    Text { text: clipboard.ageLabel(entry.modelData.created); color: ThemeApi.Theme.mutedStrong; font.family: "Inter"; font.pixelSize: 9 }
                                }
                                IconAction {
                                    Layout.preferredWidth: 29
                                    symbol: "push_pin"
                                    highlighted: Boolean(entry.modelData.pinned)
                                    ToolTip.text: entry.modelData.pinned ? "Unpin item" : "Pin item"
                                    enabled: clipboard.canAct
                                    onClicked: { clipboard.select(entry.index); clipboard.state.togglePin(entry.modelData.id); clipboard.focusSearch(); }
                                }
                            }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 24, 260)
                        spacing: 10
                        visible: clipboard.state.items.length === 0
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: !clipboard.state.available && clipboard.state.error ? "info" : !clipboard.state.loaded ? "hourglass_empty" : searchField.text ? "search_off" : clipboard.filterIndex === 3 ? "push_pin" : "content_paste"
                            color: ThemeApi.Theme.accent
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 33
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: !clipboard.state.available && clipboard.state.error ? "History unavailable" : !clipboard.state.loaded ? "Loading clipboard…" : searchField.text ? "No matching items" : clipboard.filterIndex === 3 ? "Nothing pinned yet" : "A fresh clipboard"
                            color: ThemeApi.Theme.textBright
                            font.family: "Inter"
                            font.pixelSize: 14
                            font.weight: Font.Medium
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            text: !clipboard.state.available && clipboard.state.error ? "Use Retry above to reconnect." : searchField.text ? "Try another search or filter." : clipboard.filterIndex === 3 ? "Pin text or images to keep them within reach." : clipboard.state.paused ? "Resume history to save new copies." : "Copy text or an image to get started."
                            color: ThemeApi.Theme.muted
                            font.family: "Inter"
                            font.pixelSize: 11
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: Math.max(190, (menuTransition.expandedWidth - 40) * 0.38)
                    Layout.fillHeight: true
                    visible: clipboard.selectedItem !== null
                    radius: 17
                    color: ThemeApi.Theme.surface
                    border.width: 1
                    border.color: ThemeApi.Theme.border
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10
                        RowLayout {
                            Layout.fillWidth: true
                            Text { Layout.fillWidth: true; text: "PREVIEW"; color: ThemeApi.Theme.mutedStrong; font.family: "Inter"; font.pixelSize: 9; font.weight: Font.DemiBold; font.letterSpacing: 1.3 }
                            Text { visible: clipboard.selectedItem && clipboard.selectedItem.pinned; text: "push_pin"; color: ThemeApi.Theme.accent; font.family: "Material Symbols Rounded"; font.pixelSize: 15 }
                        }
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            Image {
                                anchors.fill: parent
                                visible: clipboard.selectedItem && clipboard.selectedItem.type === "image"
                                source: menuTransition.active ? clipboard.imageSource(clipboard.selectedItem) : ""
                                cache: false
                                sourceSize.width: 600
                                sourceSize.height: 600
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }
                            Flickable {
                                id: textPreview
                                anchors.fill: parent
                                visible: clipboard.selectedItem && clipboard.selectedItem.type !== "image"
                                contentWidth: width
                                contentHeight: previewText.implicitHeight
                                interactive: contentHeight > height
                                boundsBehavior: Flickable.StopAtBounds
                                clip: true
                                onVisibleChanged: contentY = 0
                                Connections { target: clipboard; function onSelectedItemChanged() { textPreview.contentY = 0; } }
                                Text {
                                    id: previewText
                                    width: textPreview.width
                                    text: clipboard.selectedItem ? String(clipboard.selectedItem.preview || "") : ""
                                    textFormat: Text.PlainText
                                    wrapMode: Text.WrapAnywhere
                                    color: ThemeApi.Theme.text
                                    font.family: "Inter"
                                    font.pixelSize: 12
                                    lineHeight: 1.3
                                }
                                ScrollBar.vertical: ScrollBar { policy: textPreview.contentHeight > textPreview.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                            }
                            Text { anchors.centerIn: parent; visible: !clipboard.selectedItem; text: "Select an item"; color: ThemeApi.Theme.mutedStrong; font.family: "Inter"; font.pixelSize: 11 }
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: clipboard.selectedItem !== null
                            text: clipboard.selectedItem ? (clipboard.selectedItem.type === "image" ? "Image" : "Text") + " · " + clipboard.sizeLabel(clipboard.selectedItem.size) + " · " + clipboard.ageLabel(clipboard.selectedItem.created) : ""
                            color: ThemeApi.Theme.muted
                            font.family: "Inter"
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            ActionButton {
                                Layout.fillWidth: true
                                text: clipboard.state.busy ? "Working…" : "Copy"
                                symbol: "content_copy"
                                emphasized: true
                                enabled: clipboard.selectedItem !== null && clipboard.canAct
                                onClicked: clipboard.copySelection()
                            }
                            IconAction {
                                symbol: "push_pin"
                                highlighted: Boolean(clipboard.selectedItem && clipboard.selectedItem.pinned)
                                ToolTip.text: highlighted ? "Unpin · Ctrl+P" : "Pin · Ctrl+P"
                                enabled: clipboard.selectedItem !== null && clipboard.canAct
                                onClicked: { clipboard.state.togglePin(clipboard.selectedItem.id); clipboard.focusSearch(); }
                            }
                            IconAction {
                                symbol: "delete"
                                destructive: true
                                ToolTip.text: "Remove · Ctrl+Delete"
                                enabled: clipboard.selectedItem !== null && clipboard.canAct
                                onClicked: { clipboard.state.remove(clipboard.selectedItem.id); clipboard.focusSearch(); }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 20
                spacing: 6
                Text { text: clipboard.state.paused ? "pause_circle" : "lock"; color: clipboard.state.paused ? ThemeApi.Theme.accent : ThemeApi.Theme.mutedStrong; font.family: "Material Symbols Rounded"; font.pixelSize: 13 }
                Text {
                    Layout.fillWidth: true
                    text: clipboard.state.paused ? "History paused" : clipboard.state.total + " saved · " + clipboard.state.pinnedCount + " pinned"
                    color: ThemeApi.Theme.muted
                    font.family: "Inter"
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
                Text { text: "↑↓ Select   ·   Enter Copy   ·   Ctrl+P Pin"; color: ThemeApi.Theme.muted; font.family: "Inter"; font.pixelSize: 10 }
            }
                }
            }
        }

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            width: menuTransition.snapshotWidth
            height: menuTransition.snapshotHeight
            source: menuTransition.snapshot ? menuTransition.snapshot.url : ""
            visible: !menuTransition.dropdown && menuTransition.snapshot !== null && (!clipboard.closing || menuTransition.wideReturn)
            transform: NotchContentStretch { transition: menuTransition; canvasWidth: menuTransition.snapshotWidth; compact: true }
            fillMode: Image.Stretch
            onStatusChanged: {
                menuTransition.snapshotReady = status === Image.Ready || status === Image.Error;
                if (menuTransition.preparing && card.Window.window) card.Window.window.update();
            }
        }
        CompactNotch {
            anchors.horizontalCenter: parent.horizontalCenter
            clockValue: clipboard.clockValue
            batteryLevel: clipboard.batteryLevel
            batteryCharging: clipboard.batteryCharging
            visible: !menuTransition.dropdown && ((clipboard.closing && !menuTransition.wideReturn) || menuTransition.snapshot === null)
            transform: NotchContentStretch { transition: menuTransition; canvasWidth: 236; compact: true }
        }
    }
}
