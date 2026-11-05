import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Theme" as ThemeApi

PanelWindow {
    id: picker

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

    // Entries contain emoji, name, category and optional keywords/search fields.
    property var catalog: []
    property var recentEmojis: []
    property bool loading: false
    property bool busy: false
    property bool inputSuspended: false
    property bool inputReleaseAcknowledged: false
    property string error: ""
    property bool opening: false
    property bool requestPending: false
    property string query: ""
    property string category: "faces"
    property int selectedIndex: 0
    property var filteredEmojis: []
    readonly property var selectedEmoji: selectedIndex >= 0 && selectedIndex < filteredEmojis.length ? filteredEmojis[selectedIndex] : null
    readonly property var searchControl: bodyLoader.item ? bodyLoader.item.searchControl : null
    readonly property var emojiView: bodyLoader.item ? bodyLoader.item.emojiView : null
    readonly property var categories: [
        { key: "recent", name: "Recently used", icon: "history" },
        { key: "faces", name: "Smileys & emotion", icon: "sentiment_satisfied" },
        { key: "people", name: "People & gestures", icon: "waving_hand" },
        { key: "nature", name: "Animals & nature", icon: "eco" },
        { key: "food", name: "Food & drink", icon: "restaurant" },
        { key: "travel", name: "Travel & places", icon: "flight" },
        { key: "activities", name: "Activities", icon: "sports_basketball" },
        { key: "objects", name: "Objects", icon: "lightbulb" },
        { key: "symbols", name: "Symbols", icon: "favorite" },
        { key: "flags", name: "Flags", icon: "flag" }
    ]
    readonly property string categoryName: {
        const entry = categories.find(item => item.key === category);
        return query.trim() !== "" ? "Search results" : entry ? entry.name : "Emoji";
    }

    signal openRequested()
    signal aboutToOpen()
    signal dismissed()
    signal insertRequested(string emoji)
    signal inputReleased()

    NotchTransition {
        id: menuTransition
        dropdownAlignment: 0.5
        surface: card
        sourceNotch: picker.sourceNotch
        expandedWidth: Math.min(560, picker.width - 32)
        expandedHeight: Math.min(548, picker.height - (menuTransition.dropdown ? 58 : 24))
        canOpen: picker.canOpen
        onAboutToOpen: picker.aboutToOpen()
        onActivated: Qt.callLater(function() {
            if (picker.opened && !picker.inputSuspended && picker.searchControl) picker.searchControl.forceActiveFocus();
        })
    }

    // Capture the focused application before the panel takes keyboard focus.
    function open() {
        if (busy || opened || opening || requestPending || menuTransition.preparing || menuTransition.capturePending) return;
        requestPending = true;
        openRequested();
    }
    function reveal() {
        if (!requestPending) return;
        requestPending = false;
        if (!bodyLoader.ensureLoaded()) return;
        query = "";
        category = recentEmojis.length ? "recent" : "faces";
        selectedIndex = 0;
        if (searchControl) searchControl.clear();
        rebuildModel(false);
        menuTransition.open();
    }
    function close() {
        requestPending = false;
        menuTransition.close();
        if (searchControl) searchControl.focus = false;
        dismissed();
    }
    function toggle() {
        if (opened || opening || requestPending || menuTransition.pendingOpen || menuTransition.preparing || menuTransition.capturePending) close();
        else open();
    }
    function focusSearch() { if (opened && !inputSuspended && searchControl) searchControl.forceActiveFocus(); }
    function acknowledgeInputRelease() {
        if (!inputSuspended || inputReleaseAcknowledged || !card.Window.window) return;
        if (!card.Window.window.active) {
            inputReleaseAcknowledged = true;
            inputReleased();
        }
    }
    function restoreInputFocus() {
        if (opened && !inputSuspended && card.Window.window && card.Window.window.active && searchControl)
            searchControl.forceActiveFocus();
    }
    function entrySearch(entry) {
        const keywords = Array.isArray(entry.keywords) ? entry.keywords.join(" ") : String(entry.keywords || "");
        return String(entry.search || (String(entry.name || "") + " " + String(entry.nameEn || "") + " " + keywords + " " + String(entry.emoji || ""))).toLocaleLowerCase();
    }
    function rebuildModel(retainSelection) {
        searchDelay.stop();
        // The controller outlives its visual body; drop its view-only references too.
        if (!bodyLoader.active) {
            filteredEmojis = [];
            selectedIndex = 0;
            return;
        }
        const previous = retainSelection && selectedEmoji ? selectedEmoji.emoji : "";
        const terms = query.toLocaleLowerCase().trim().split(/\s+/).filter(Boolean);
        const source = terms.length ? catalog : category === "recent" ? recentEmojis : catalog;
        filteredEmojis = source.filter(function(entry) {
            if (!entry || !entry.emoji) return false;
            if (!terms.length) return category === "recent" || entry.category === category;
            const search = entrySearch(entry);
            return terms.every(term => search.indexOf(term) !== -1);
        });
        const found = previous ? filteredEmojis.findIndex(item => item.emoji === previous) : -1;
        selectedIndex = found >= 0 ? found : 0;
        if (emojiView) emojiView.positionViewAtBeginning();
    }
    function chooseCategory(key) {
        category = key;
        query = "";
        if (searchControl) searchControl.clear();
        rebuildModel(false);
        focusSearch();
    }
    function nextCategory(direction) {
        const current = Math.max(0, categories.findIndex(item => item.key === category));
        chooseCategory(categories[(current + direction + categories.length) % categories.length].key);
    }
    function select(index) {
        if (index < 0 || index >= filteredEmojis.length) return;
        selectedIndex = index;
        if (emojiView) emojiView.positionViewAtIndex(index, GridView.Contain);
    }
    function moveSelection(amount) {
        if (!filteredEmojis.length) return;
        select(Math.max(0, Math.min(filteredEmojis.length - 1, selectedIndex + amount)));
    }
    function insert(index) {
        if (busy || loading || index < 0 || index >= filteredEmojis.length) return;
        selectedIndex = index;
        insertRequested(String(filteredEmojis[index].emoji));
    }
    function handleKey(event) {
        if (event.key === Qt.Key_Escape) close();
        else if (event.key === Qt.Key_Left) moveSelection(-1);
        else if (event.key === Qt.Key_Right) moveSelection(1);
        else if (event.key === Qt.Key_Up) moveSelection(-8);
        else if (event.key === Qt.Key_Down) moveSelection(8);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) insert(selectedIndex);
        else if (event.key === Qt.Key_Tab) nextCategory(event.modifiers & Qt.ShiftModifier ? -1 : 1);
        else return;
        event.accepted = true;
    }

    onCatalogChanged: if (bodyLoader.retained) rebuildModel(true)
    onRecentEmojisChanged: if (bodyLoader.retained && category === "recent") rebuildModel(true)
    onQueryChanged: if (bodyLoader.retained) searchDelay.restart()
    onInputSuspendedChanged: {
        inputReleaseAcknowledged = false;
        if (inputSuspended) {
            if (searchControl) searchControl.focus = false;
            Qt.callLater(acknowledgeInputRelease);
        } else Qt.callLater(restoreInputFocus);
    }
    Timer { id: searchDelay; interval: 70; onTriggered: picker.rebuildModel(false) }
    property Connections inputFocusConnection: Connections {
        target: card.Window.window
        function onActiveChanged() {
            if (picker.inputSuspended) picker.acknowledgeInputRelease();
            else Qt.callLater(picker.restoreInputFocus);
        }
    }

    visible: menuTransition.visible
    color: "transparent"
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "qs-emoji-picker"
    WlrLayershell.keyboardFocus: !inputSuspended && (opened || menuTransition.preparing) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    IpcHandler {
        target: "emojiPicker"
        function toggle(): void { picker.toggle(); }
        function open(): void { picker.open(); }
        function close(): void { picker.close(); }
    }

    component IconAction: ToolButton {
        id: action
        required property string symbol
        implicitWidth: 34
        implicitHeight: 34
        focusPolicy: Qt.NoFocus
        Accessible.name: ToolTip.text
        ToolTip.visible: hovered
        ToolTip.delay: 400
        contentItem: Text {
            text: action.symbol
            color: action.hovered ? ThemeApi.Theme.textBright : ThemeApi.Theme.muted
            font.family: "Material Symbols Rounded"
            font.pixelSize: 20
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle { radius: 12; color: action.down || action.hovered ? ThemeApi.Theme.surfaceAlt : "transparent" }
    }

    MouseArea { anchors.fill: parent; enabled: picker.opened; onClicked: picker.close() }

    NotchMenuSurface {
        id: card
        transition: menuTransition
        color: ThemeApi.Theme.notchBg
        border.width: 1
        border.color: ThemeApi.Theme.border
        Keys.onPressed: function(event) { picker.handleKey(event); }
        Rectangle { visible: !menuTransition.dropdown; x: 0; y: 0; width: parent.width; height: parent.border.width; color: parent.color; z: 100 }
        MouseArea { anchors.fill: parent; enabled: picker.opened }

        MenuBodyLoader {
            id: bodyLoader
            engaged: menuTransition.active || menuTransition.pendingOpen || picker.busy
            onActiveChanged: if (!active) picker.rebuildModel(false)
            width: menuTransition.expandedWidth - 40
            height: menuTransition.expandedHeight - 36
            anchors.horizontalCenter: parent.horizontalCenter
            y: 18 * Math.min(1, bodyStretch.unfold)
            enabled: picker.opened
            visible: picker.opened || picker.closing
            transform: NotchContentStretch {
                id: bodyStretch
                transition: menuTransition
                canvasWidth: menuTransition.expandedWidth - 40
                horizontalInset: 40
            }
            onLoaded: item.searchControl.text = picker.query
            sourceComponent: Component {
                ColumnLayout {
                    id: pickerBody
                    property alias searchControl: searchField
                    property alias emojiView: emojis
                    anchors.fill: parent
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        spacing: 12
                        Rectangle {
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 44
                            radius: 15
                            color: ThemeApi.Theme.accentSoft
                            Text { anchors.centerIn: parent; text: "sentiment_very_satisfied"; color: ThemeApi.Theme.accent; font.family: "Material Symbols Rounded"; font.pixelSize: 25 }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Text { text: "Emoji"; color: ThemeApi.Theme.textBright; font.family: "Inter"; font.pixelSize: 21; font.weight: Font.DemiBold }
                            Text { text: "A little more expression"; color: ThemeApi.Theme.muted; font.family: "Inter"; font.pixelSize: 11 }
                        }
                        Rectangle {
                            Layout.preferredWidth: shortcut.implicitWidth + 14
                            Layout.preferredHeight: 25
                            radius: 8
                            color: ThemeApi.Theme.surface
                            Text { id: shortcut; anchors.centerIn: parent; text: "Super + ."; color: ThemeApi.Theme.muted; font.family: "Inter"; font.pixelSize: 10 }
                        }
                        IconAction { symbol: "close"; ToolTip.text: "Close · Esc"; onClicked: picker.close() }
                    }

                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        Layout.preferredHeight: 46
                        leftPadding: 42
                        rightPadding: 38
                        verticalAlignment: TextInput.AlignVCenter
                        placeholderText: "Search emoji…"
                        placeholderTextColor: ThemeApi.Theme.muted
                        color: ThemeApi.Theme.textBright
                        selectionColor: ThemeApi.Theme.accent
                        selectedTextColor: ThemeApi.Theme.onAccent
                        font.family: "Inter"
                        font.pixelSize: 14
                        clip: true
                        enabled: !picker.busy
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
                            visible: searchField.text.length > 0
                            symbol: "close"
                            ToolTip.text: "Clear search"
                            onClicked: { searchField.clear(); picker.focusSearch(); }
                        }
                        onTextChanged: if (picker.query !== text) picker.query = text
                        Keys.onPressed: function(event) { picker.handleKey(event); }
                        Keys.onTabPressed: picker.nextCategory(1)
                        Keys.onBacktabPressed: picker.nextCategory(-1)
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        spacing: 3
                        Repeater {
                            model: picker.categories
                            delegate: ToolButton {
                                id: categoryButton
                                required property var modelData
                                readonly property bool chosen: picker.query.trim() === "" && picker.category === modelData.key
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                focusPolicy: Qt.NoFocus
                                enabled: !picker.busy
                                Accessible.name: modelData.name
                                ToolTip.text: modelData.name
                                ToolTip.visible: hovered
                                ToolTip.delay: 400
                                contentItem: Text {
                                    text: categoryButton.modelData.icon
                                    color: categoryButton.chosen ? ThemeApi.Theme.accent : categoryButton.hovered ? ThemeApi.Theme.textBright : ThemeApi.Theme.muted
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: 21
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    radius: 12
                                    color: categoryButton.chosen ? ThemeApi.Theme.accentSoft : categoryButton.hovered ? ThemeApi.Theme.surface : "transparent"
                                    border.width: categoryButton.chosen ? 1 : 0
                                    border.color: ThemeApi.Theme.accent
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                                onClicked: picker.chooseCategory(modelData.key)
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 16
                        Text { Layout.fillWidth: true; text: picker.categoryName; color: ThemeApi.Theme.muted; font.family: "Inter"; font.pixelSize: 11; font.weight: Font.Medium; elide: Text.ElideRight }
                        Text { text: picker.loading ? "Loading…" : picker.filteredEmojis.length; color: ThemeApi.Theme.mutedStrong; font.family: "Inter"; font.pixelSize: 10 }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 100
                        clip: true

                        GridView {
                            id: emojis
                            anchors.fill: parent
                            clip: true
                            model: picker.filteredEmojis
                            currentIndex: picker.selectedIndex
                            cellWidth: width / 8
                            cellHeight: 58
                            cacheBuffer: 58
                            interactive: contentHeight > height
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar { policy: emojis.contentHeight > emojis.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                            delegate: Item {
                                id: emojiCell
                                required property var modelData
                                required property int index
                                readonly property bool selected: index === picker.selectedIndex
                                width: emojis.cellWidth
                                height: emojis.cellHeight
                                Rectangle {
                                    width: Math.min(54, parent.width - 6)
                                    height: 52
                                    anchors.centerIn: parent
                                    radius: 15
                                    color: emojiCell.selected ? ThemeApi.Theme.accentSoft : emojiHover.containsMouse ? ThemeApi.Theme.surfaceAlt : "transparent"
                                    border.width: emojiCell.selected ? 1 : 0
                                    border.color: ThemeApi.Theme.accent
                                    scale: emojiHover.pressed ? 0.94 : emojiHover.containsMouse ? 1.07 : 1
                                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: emojiCell.modelData.emoji
                                        textFormat: Text.PlainText
                                        font.family: "Noto Color Emoji"
                                        font.pixelSize: 30
                                        color: ThemeApi.Theme.textBright
                                    }
                                    MouseArea {
                                        id: emojiHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: !picker.busy
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: picker.selectedIndex = emojiCell.index
                                        onClicked: picker.insert(emojiCell.index)
                                    }
                                    Accessible.role: Accessible.Button
                                    Accessible.name: emojiCell.modelData.name || emojiCell.modelData.emoji
                                    Accessible.onPressAction: picker.insert(emojiCell.index)
                                    ToolTip.text: emojiCell.modelData.name || ""
                                    ToolTip.visible: emojiHover.containsMouse
                                    ToolTip.delay: 600
                                }
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            width: parent.width - 40
                            spacing: 8
                            visible: picker.filteredEmojis.length === 0
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: picker.loading ? "hourglass_empty" : picker.query.trim() ? "search_off" : "history"
                                color: ThemeApi.Theme.accent
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 32
                            }
                            Text {
                                width: parent.width
                                text: picker.loading ? "Getting your emoji ready…" : picker.query.trim() ? "No emoji found" : picker.category === "recent" ? "Your recent emoji will appear here" : "No emoji in this category"
                                color: ThemeApi.Theme.muted
                                font.family: "Inter"
                                font.pixelSize: 12
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.Wrap
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: ThemeApi.Theme.border; opacity: 0.6 }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        spacing: 11
                        Text {
                            text: picker.selectedEmoji ? picker.selectedEmoji.emoji : ""
                            Layout.preferredWidth: 34
                            font.family: "Noto Color Emoji"
                            font.pixelSize: 25
                            horizontalAlignment: Text.AlignHCenter
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Text {
                                Layout.fillWidth: true
                                text: picker.error || (picker.selectedEmoji ? picker.selectedEmoji.name : "Choose an emoji")
                                color: picker.error ? ThemeApi.Theme.red : ThemeApi.Theme.text
                                font.family: "Inter"
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: picker.busy ? "Inserting…" : "Click or Enter to insert into your app"
                                color: ThemeApi.Theme.muted
                                font.family: "Inter"
                                font.pixelSize: 9
                                elide: Text.ElideRight
                            }
                        }
                        Text { text: "Tab Category  ·  Esc Close"; color: ThemeApi.Theme.muted; font.family: "Inter"; font.pixelSize: 9 }
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
            visible: !menuTransition.dropdown && menuTransition.snapshot !== null && (!picker.closing || menuTransition.wideReturn)
            transform: NotchContentStretch { transition: menuTransition; canvasWidth: menuTransition.snapshotWidth; compact: true }
            fillMode: Image.Stretch
            onStatusChanged: {
                menuTransition.snapshotReady = status === Image.Ready || status === Image.Error;
                if (menuTransition.preparing && card.Window.window) card.Window.window.update();
            }
        }
        CompactNotch {
            anchors.horizontalCenter: parent.horizontalCenter
            clockValue: picker.clockValue
            batteryLevel: picker.batteryLevel
            batteryCharging: picker.batteryCharging
            visible: !menuTransition.dropdown && ((picker.closing && !menuTransition.wideReturn) || menuTransition.snapshot === null)
            transform: NotchContentStretch { transition: menuTransition; canvasWidth: 236; compact: true }
        }
    }
}
