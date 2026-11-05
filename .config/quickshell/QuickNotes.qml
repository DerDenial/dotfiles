import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "Theme" as ThemeApi

PanelWindow {
    id: quickNotes

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
    property bool deleteConfirmation: false
    property bool syncingEditor: false
    property string editorId: ""
    property string pendingFocus: ""
    property real ageNow: Date.now()
    readonly property bool hasSelection: notes.selectedId !== ""
    readonly property var selectedEntry: notes.items.find(item => String(item.id) === notes.selectedId) || null
    property string searchQuery: ""
    readonly property var searchControl: bodyLoader.item ? bodyLoader.item.searchInput : null
    readonly property var titleControl: bodyLoader.item ? bodyLoader.item.titleInput : null
    readonly property var bodyControl: bodyLoader.item ? bodyLoader.item.bodyInput : null
    readonly property var notesView: bodyLoader.item ? bodyLoader.item.noteEntries : null
    readonly property int wordCount: bodyControl && bodyControl.text.trim() ? bodyControl.text.trim().split(/\s+/).length : 0
    signal aboutToOpen()

    property NotesState notes: NotesState {
        query: quickNotes.searchQuery
        onEditorChanged: quickNotes.syncEditor()
        onClosedReady: {
            quickNotes.deleteConfirmation = false;
            quickNotes.pendingFocus = "";
            menuTransition.close();
            if (quickNotes.titleControl) quickNotes.titleControl.focus = false;
            if (quickNotes.bodyControl) quickNotes.bodyControl.focus = false;
            if (quickNotes.searchControl) quickNotes.searchControl.focus = false;
        }
        onEditorBusyChanged: if (!editorBusy) Qt.callLater(quickNotes.applyPendingFocus)
        onCreated: {
            quickNotes.pendingFocus = "title";
            Qt.callLater(quickNotes.applyPendingFocus);
        }
    }

    NotchTransition {
        id: menuTransition
        dropdownAlignment: 0.5
        surface: card
        sourceNotch: quickNotes.sourceNotch
        expandedWidth: Math.min(780, quickNotes.width - 40)
        expandedHeight: Math.min(580, quickNotes.height - (menuTransition.dropdown ? 58 : 24))
        canOpen: quickNotes.canOpen
        onAboutToOpen: quickNotes.aboutToOpen()
        onActivated: {
            quickNotes.notes.refresh();
            Qt.callLater(function() {
                if (!quickNotes.opened) return;
                quickNotes.pendingFocus = quickNotes.hasSelection ? "editor" : "search";
                quickNotes.applyPendingFocus();
            });
        }
    }

    function open() {
        if (opened || menuTransition.preparing || menuTransition.capturePending) return;
        if (!bodyLoader.ensureLoaded()) return;
        deleteConfirmation = false;
        searchControl.clear();
        ageNow = Date.now();
        menuTransition.open();
    }
    function close() { notes.requestClose(); }
    function toggle() {
        if (opened || menuTransition.pendingOpen || menuTransition.preparing || menuTransition.capturePending) close();
        else open();
    }
    function syncEditor() {
        if (!titleControl || !bodyControl) return;
        const changedNote = editorId !== notes.selectedId;
        syncingEditor = true;
        if (titleControl.text !== notes.title) titleControl.text = notes.title;
        if (bodyControl.text !== notes.content) bodyControl.text = notes.content;
        editorId = notes.selectedId;
        syncingEditor = false;
        deleteConfirmation = false;
        if (changedNote) {
            titleControl.cursorPosition = 0;
            bodyControl.cursorPosition = 0;
            if (pendingFocus !== "search" && pendingFocus !== "title") pendingFocus = "editor";
            Qt.callLater(quickNotes.applyPendingFocus);
        }
    }
    function applyPendingFocus() {
        if (!opened || !bodyLoader.item || notes.editorBusy || !pendingFocus) return;
        const target = pendingFocus;
        pendingFocus = "";
        if (target === "title" && hasSelection) {
            titleControl.forceActiveFocus();
            titleControl.selectAll();
        } else if (target === "editor" && hasSelection) bodyControl.forceActiveFocus();
        else searchControl.forceActiveFocus();
    }
    function newNote() {
        if (!searchControl) return;
        deleteConfirmation = false;
        pendingFocus = "title";
        searchControl.clear();
        notes.create();
    }
    function focusSearch() {
        if (!searchControl) return;
        searchControl.forceActiveFocus();
        searchControl.selectAll();
    }
    function chooseSearchResult(direction) {
        if (!notesView || notes.editorBusy || !notes.items.length) return;
        let index = notes.items.findIndex(item => String(item.id) === notes.selectedId);
        index = index < 0 ? 0 : Math.max(0, Math.min(notes.items.length - 1, index + direction));
        pendingFocus = "search";
        notes.select(String(notes.items[index].id));
        notesView.positionViewAtIndex(index, ListView.Contain);
    }
    function noteTitle(item) { return String(item.title || "").trim() || "Untitled note"; }
    function ageLabel(value) {
        if (!value) return "Just now";
        const numeric = Number(value);
        const date = isNaN(numeric) ? new Date(value) : new Date(numeric < 100000000000 ? numeric * 1000 : numeric);
        const elapsed = Math.max(0, Math.floor((ageNow - date.getTime()) / 60000));
        if (elapsed < 1) return "Just now";
        if (elapsed < 60) return elapsed + " min ago";
        if (elapsed < 1440) return Math.floor(elapsed / 60) + " h ago";
        return Qt.formatDateTime(date, "d MMM");
    }

    visible: menuTransition.visible
    WlrLayershell.keyboardFocus: opened || menuTransition.preparing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }

    Timer { interval: 60000; repeat: true; running: quickNotes.opened; onTriggered: quickNotes.ageNow = Date.now() }
    IpcHandler {
        target: "quickNotes"
        function toggle(): void { quickNotes.toggle(); }
        function open(): void { quickNotes.open(); }
        function close(): void { quickNotes.close(); }
    }
    Shortcut {
        sequence: "Escape"
        enabled: quickNotes.opened
        autoRepeat: false
        onActivated: {
            if (quickNotes.deleteConfirmation) quickNotes.deleteConfirmation = false;
            else quickNotes.close();
        }
    }
    Shortcut { sequence: "Ctrl+N"; enabled: quickNotes.opened && notes.loaded && notes.available && !notes.editorBusy; autoRepeat: false; onActivated: quickNotes.newNote() }
    Shortcut { sequence: "Ctrl+F"; enabled: quickNotes.opened; autoRepeat: false; onActivated: quickNotes.focusSearch() }
    Shortcut { sequence: "Ctrl+S"; enabled: quickNotes.opened; autoRepeat: false; onActivated: notes.saveNow() }

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
            color: !iconButton.enabled ? ThemeApi.Theme.mutedStrong : iconButton.destructive ? ThemeApi.Theme.red : ThemeApi.Theme.muted
            font.family: "Material Symbols Rounded"
            font.pixelSize: 20
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 11
            color: iconButton.down ? ThemeApi.Theme.surfaceRaised : iconButton.hovered ? ThemeApi.Theme.surfaceAlt : "transparent"
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
            color: actionButton.emphasized && actionButton.enabled ? ThemeApi.Theme.accent : actionButton.down || actionButton.hovered ? ThemeApi.Theme.surfaceRaised : ThemeApi.Theme.surface
            border.width: actionButton.emphasized ? 0 : 1
            border.color: ThemeApi.Theme.border
            opacity: actionButton.enabled ? 1 : 0.55
        }
    }

    MouseArea { anchors.fill: parent; enabled: quickNotes.opened; onClicked: quickNotes.close() }

    NotchMenuSurface {
        id: card
        transition: menuTransition
        color: ThemeApi.Theme.notchBg
        border.width: 1
        border.color: ThemeApi.Theme.border

        Rectangle { visible: !menuTransition.dropdown; x: 0; y: 0; width: parent.width; height: parent.border.width; color: parent.color; z: 100 }
        MouseArea { anchors.fill: parent; enabled: quickNotes.opened }

        MenuBodyLoader {
            id: bodyLoader
            engaged: menuTransition.active || menuTransition.pendingOpen || notes.dirty || notes.busy && retained
            width: menuTransition.expandedWidth - 40
            height: menuTransition.expandedHeight - 36
            anchors.horizontalCenter: parent.horizontalCenter
            y: 18 * Math.min(1, bodyStretch.unfold)
            enabled: quickNotes.opened
            visible: quickNotes.opened || quickNotes.closing
            transform: NotchContentStretch {
                id: bodyStretch
                transition: menuTransition
                canvasWidth: menuTransition.expandedWidth - 40
                horizontalInset: 40
            }
            onLoaded: {
                item.searchInput.text = quickNotes.searchQuery;
                quickNotes.editorId = "";
                quickNotes.syncEditor();
                item.editorReady = true;
            }
            sourceComponent: Component {
                ColumnLayout {
                    id: notesBody
                    anchors.fill: parent
                    spacing: 16
                    property alias searchInput: searchField
                    property alias titleInput: titleField
                    property alias bodyInput: bodyField
                    property alias noteEntries: noteList
                    property bool editorReady: false
                    Component.onDestruction: editorReady = false

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 46
                        spacing: 12
                        Rectangle {
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 44
                            radius: 15
                            color: ThemeApi.Theme.accentSoft
                            Text { anchors.centerIn: parent; text: "edit_note"; color: ThemeApi.Theme.accent; font.family: "Material Symbols Rounded"; font.pixelSize: 25 }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Text { text: "Quick notes"; color: ThemeApi.Theme.textBright; font.family: "Inter"; font.pixelSize: 20; font.weight: Font.DemiBold }
                            Text { Layout.fillWidth: true; text: "Make room for a thought"; color: ThemeApi.Theme.muted; font.family: "Inter"; font.pixelSize: 10; elide: Text.ElideRight }
                        }
                        ActionButton {
                            text: "New note"
                            symbol: "add"
                            emphasized: true
                            enabled: notes.loaded && notes.available && !notes.editorBusy
                            onClicked: quickNotes.newNote()
                            ToolTip.visible: hovered
                            ToolTip.delay: 450
                            ToolTip.text: "New note · Ctrl+N"
                        }
                        IconAction { symbol: "close"; ToolTip.text: "Close · Esc"; onClicked: quickNotes.close() }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: errorRow.implicitHeight + 20
                        visible: notes.error !== ""
                        radius: 13
                        color: ThemeApi.Theme.surface
                        border.width: 1
                        border.color: ThemeApi.Theme.border
                        RowLayout {
                            id: errorRow
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8
                            Text { text: "info"; color: ThemeApi.Theme.red; font.family: "Material Symbols Rounded"; font.pixelSize: 20 }
                            Text { Layout.fillWidth: true; text: notes.error; color: ThemeApi.Theme.text; font.family: "Inter"; font.pixelSize: 11; wrapMode: Text.Wrap }
                            ActionButton { text: "Save a copy"; visible: notes.conflict; enabled: !notes.editorBusy; onClicked: notes.saveCopy() }
                            ActionButton { text: notes.dirty ? "Save again" : "Retry"; visible: !notes.conflict; enabled: !notes.editorBusy; onClicked: { if (notes.dirty) notes.saveNow(); else notes.refresh(); } }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumWidth: 0
                        Layout.minimumHeight: 150
                        spacing: 18
                        clip: true

                        ColumnLayout {
                            id: notesSidebar
                            readonly property real paneWidth: Math.min(228, (menuTransition.expandedWidth - 40) * 0.32)
                            Layout.fillWidth: false
                            Layout.minimumWidth: paneWidth
                            Layout.preferredWidth: paneWidth
                            Layout.maximumWidth: paneWidth
                            Layout.fillHeight: true
                            spacing: 12
                            clip: true

                            TextField {
                                id: searchField
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.preferredHeight: 40
                                leftPadding: 35
                                rightPadding: 30
                                verticalAlignment: TextInput.AlignVCenter
                                maximumLength: 512
                                placeholderText: "Find a note…"
                                placeholderTextColor: ThemeApi.Theme.muted
                                color: ThemeApi.Theme.textBright
                                selectionColor: ThemeApi.Theme.accent
                                selectedTextColor: ThemeApi.Theme.onAccent
                                font.family: "Inter"
                                font.pixelSize: 12
                                clip: true
                                background: Rectangle {
                                    radius: 13
                                    color: ThemeApi.Theme.surface
                                    border.width: 1
                                    border.color: searchField.activeFocus ? ThemeApi.Theme.accent : ThemeApi.Theme.border
                                }
                                Text { x: 11; anchors.verticalCenter: parent.verticalCenter; text: "search"; color: ThemeApi.Theme.muted; font.family: "Material Symbols Rounded"; font.pixelSize: 18 }
                                IconAction {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 1
                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitWidth: 28
                                    implicitHeight: 30
                                    symbol: "close"
                                    visible: searchField.text !== ""
                                    ToolTip.text: "Clear search"
                                    onClicked: { searchField.clear(); searchField.forceActiveFocus(); }
                                }
                                onTextChanged: {
                                    if (notesBody.editorReady) quickNotes.searchQuery = text.trim();
                                    quickNotes.deleteConfirmation = false;
                                }
                                onAccepted: {
                                    if (notes.editorBusy || !notes.items.length) return;
                                    const index = notes.items.findIndex(item => String(item.id) === notes.selectedId);
                                    notes.select(String(notes.items[Math.max(0, index)].id));
                                    quickNotes.pendingFocus = "editor";
                                    Qt.callLater(quickNotes.applyPendingFocus);
                                }
                                Keys.onDownPressed: quickNotes.chooseSearchResult(1)
                                Keys.onUpPressed: quickNotes.chooseSearchResult(-1)
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 14
                                Text { Layout.fillWidth: true; text: searchField.text ? "RESULTS" : "YOUR NOTES"; color: ThemeApi.Theme.mutedStrong; font.family: "Inter"; font.pixelSize: 9; font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
                                Text { text: notes.items.length; color: ThemeApi.Theme.muted; font.family: "Inter"; font.pixelSize: 10 }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                ListView {
                                    id: noteList
                                    anchors.fill: parent
                                    model: notes.items
                                    spacing: 7
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    interactive: contentHeight > height
                                    ScrollBar.vertical: ScrollBar { policy: noteList.contentHeight > noteList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                                    delegate: Rectangle {
                                        id: noteRow
                                        required property var modelData
                                        required property int index
                                        readonly property bool chosen: String(modelData.id) === notes.selectedId
                                        width: noteList.width - 4
                                        height: 94
                                        radius: 14
                                        color: chosen ? ThemeApi.Theme.accentSoft : noteMouse.containsMouse ? ThemeApi.Theme.surfaceAlt : "transparent"
                                        border.width: chosen ? 1 : 0
                                        border.color: ThemeApi.Theme.accent
                                        Behavior on color { ColorAnimation { duration: 130 } }
                                        MouseArea {
                                            id: noteMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            enabled: !notes.editorBusy
                                            onClicked: {
                                                quickNotes.deleteConfirmation = false;
                                                quickNotes.pendingFocus = "editor";
                                                notes.select(String(noteRow.modelData.id));
                                                Qt.callLater(quickNotes.applyPendingFocus);
                                            }
                                        }
                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 5
                                            Text {
                                                Layout.fillWidth: true
                                                text: noteRow.chosen && notes.dirty ? quickNotes.noteTitle({ title: notes.title }) : quickNotes.noteTitle(noteRow.modelData)
                                                textFormat: Text.PlainText
                                                color: ThemeApi.Theme.textBright
                                                font.family: "Inter"
                                                font.pixelSize: 12
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                text: String(noteRow.chosen && notes.dirty ? notes.content.slice(0, 180) : noteRow.modelData.preview || "").replace(/\s+/g, " ").trim() || "Write something…"
                                                textFormat: Text.PlainText
                                                color: ThemeApi.Theme.muted
                                                font.family: "Inter"
                                                font.pixelSize: 10
                                                elide: Text.ElideRight
                                                maximumLineCount: 1
                                            }
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text { Layout.fillWidth: true; text: quickNotes.ageLabel(noteRow.modelData.updated); color: ThemeApi.Theme.mutedStrong; font.family: "Inter"; font.pixelSize: 9 }
                                                Rectangle { visible: noteRow.chosen && notes.dirty; Layout.preferredWidth: 5; Layout.preferredHeight: 5; radius: 3; color: ThemeApi.Theme.accent }
                                            }
                                        }
                                    }
                                }
                                Column {
                                    anchors.centerIn: parent
                                    width: parent.width - 24
                                    spacing: 10
                                    visible: notes.items.length === 0
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: searchField.text ? "search_off" : "sticky_note_2"; color: ThemeApi.Theme.mutedStrong; font.family: "Material Symbols Rounded"; font.pixelSize: 30 }
                                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: !notes.loaded ? "Loading your notes…" : searchField.text ? "No matching notes" : "A fresh page awaits"; color: ThemeApi.Theme.muted; font.family: "Inter"; font.pixelSize: 11 }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: false
                            Layout.minimumWidth: 1
                            Layout.preferredWidth: 1
                            Layout.maximumWidth: 1
                            Layout.fillHeight: true
                            color: ThemeApi.Theme.border
                            opacity: 0.55
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.preferredWidth: 0
                            Layout.fillHeight: true
                            clip: true

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 12
                                visible: quickNotes.hasSelection

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: 5
                                    TextField {
                                        id: titleField
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        Layout.preferredHeight: 42
                                        leftPadding: 0
                                        rightPadding: 4
                                        maximumLength: 200
                                        enabled: !notes.editorBusy
                                        placeholderText: "Untitled note"
                                        placeholderTextColor: ThemeApi.Theme.muted
                                        color: ThemeApi.Theme.textBright
                                        selectionColor: ThemeApi.Theme.accent
                                        selectedTextColor: ThemeApi.Theme.onAccent
                                        font.family: "Inter"
                                        font.pixelSize: 21
                                        font.weight: Font.DemiBold
                                        background: null
                                        clip: true
                                        onTextChanged: if (notesBody.editorReady && !quickNotes.syncingEditor && quickNotes.hasSelection) notes.updateTitle(text)
                                        onAccepted: bodyField.forceActiveFocus()
                                    }
                                    IconAction {
                                        symbol: "delete"
                                        destructive: quickNotes.deleteConfirmation
                                        ToolTip.text: "Delete note"
                                        enabled: !notes.editorBusy
                                        onClicked: quickNotes.deleteConfirmation = !quickNotes.deleteConfirmation
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 14
                                    spacing: 5
                                    Text { text: "schedule"; color: ThemeApi.Theme.mutedStrong; font.family: "Material Symbols Rounded"; font.pixelSize: 13 }
                                    Text { Layout.fillWidth: true; text: quickNotes.selectedEntry ? "Edited " + quickNotes.ageLabel(quickNotes.selectedEntry.updated).toLocaleLowerCase() : "A new thought"; color: ThemeApi.Theme.muted; font.family: "Inter"; font.pixelSize: 10; elide: Text.ElideRight }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: deleteRow.implicitHeight + 20
                                    visible: quickNotes.deleteConfirmation
                                    radius: 13
                                    color: ThemeApi.Theme.surface
                                    border.width: 1
                                    border.color: ThemeApi.Theme.border
                                    RowLayout {
                                        id: deleteRow
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 6
                                        Text { Layout.fillWidth: true; text: "Delete this note?"; color: ThemeApi.Theme.text; font.family: "Inter"; font.pixelSize: 11; wrapMode: Text.Wrap }
                                        ActionButton { text: "Keep"; onClicked: quickNotes.deleteConfirmation = false }
                                        ActionButton { text: "Delete"; destructive: true; enabled: !notes.editorBusy; onClicked: { quickNotes.deleteConfirmation = false; notes.removeSelected(); } }
                                    }
                                }

                                ScrollView {
                                    id: editorScroll
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.minimumWidth: 0
                                    Layout.minimumHeight: 0
                                    implicitWidth: 0
                                    contentWidth: availableWidth
                                    clip: true
                                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                                    TextArea {
                                        id: bodyField
                                        enabled: !notes.editorBusy
                                        width: editorScroll.availableWidth
                                        implicitHeight: Math.max(contentHeight + topPadding + bottomPadding, editorScroll.availableHeight)
                                        padding: 0
                                        rightPadding: 12
                                        topPadding: 4
                                        bottomPadding: 18
                                        placeholderText: "What's on your mind?"
                                        placeholderTextColor: ThemeApi.Theme.mutedStrong
                                        color: ThemeApi.Theme.text
                                        selectionColor: ThemeApi.Theme.accent
                                        selectedTextColor: ThemeApi.Theme.onAccent
                                        font.family: "Inter"
                                        font.pixelSize: 14
                                        wrapMode: TextEdit.Wrap
                                        textFormat: TextEdit.PlainText
                                        persistentSelection: true
                                        selectByMouse: true
                                        background: null
                                        onTextChanged: if (notesBody.editorReady && !quickNotes.syncingEditor && quickNotes.hasSelection) notes.updateBody(text)
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 22
                                    spacing: 5
                                    Text { text: notes.error ? "error_outline" : notes.saving ? "sync" : notes.dirty ? "edit" : "check_circle"; color: notes.error ? ThemeApi.Theme.red : notes.dirty || notes.saving ? ThemeApi.Theme.accent : ThemeApi.Theme.mutedStrong; font.family: "Material Symbols Rounded"; font.pixelSize: 14 }
                                    Text { Layout.fillWidth: true; text: notes.saveStatus; color: ThemeApi.Theme.muted; font.family: "Inter"; font.pixelSize: 10; elide: Text.ElideRight }
                                    Text { text: quickNotes.wordCount + (quickNotes.wordCount === 1 ? " word" : " words"); color: ThemeApi.Theme.mutedStrong; font.family: "Inter"; font.pixelSize: 10 }
                                }
                            }

                            Column {
                                anchors.centerIn: parent
                                width: Math.min(parent.width - 36, 280)
                                spacing: 13
                                visible: !quickNotes.hasSelection
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 72
                                    height: 72
                                    radius: 24
                                    color: ThemeApi.Theme.accentSoft
                                    Text { anchors.centerIn: parent; text: "edit_note"; color: ThemeApi.Theme.accent; font.family: "Material Symbols Rounded"; font.pixelSize: 36 }
                                }
                                Text { width: parent.width; text: "Keep a little thought"; horizontalAlignment: Text.AlignHCenter; color: ThemeApi.Theme.textBright; font.family: "Inter"; font.pixelSize: 18; font.weight: Font.DemiBold; wrapMode: Text.Wrap }
                                Text { width: parent.width; text: "Ideas, reminders, the thing you nearly forgot. Your notes save as you write."; horizontalAlignment: Text.AlignHCenter; color: ThemeApi.Theme.muted; font.family: "Inter"; font.pixelSize: 12; wrapMode: Text.Wrap }
                                ActionButton { anchors.horizontalCenter: parent.horizontalCenter; text: "Write a note"; symbol: "add"; emphasized: true; enabled: notes.loaded && notes.available && !notes.editorBusy; onClicked: quickNotes.newNote() }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 16
                        spacing: 5
                        Text { text: "lock"; color: ThemeApi.Theme.mutedStrong; font.family: "Material Symbols Rounded"; font.pixelSize: 12 }
                        Text { Layout.fillWidth: true; text: "On this device"; color: ThemeApi.Theme.mutedStrong; font.family: "Inter"; font.pixelSize: 9; elide: Text.ElideRight }
                        Text { text: "Ctrl+N New   ·   Ctrl+F Find   ·   Esc Close"; color: ThemeApi.Theme.muted; font.family: "Inter"; font.pixelSize: 9 }
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
            visible: !menuTransition.dropdown && menuTransition.snapshot !== null && (!quickNotes.closing || menuTransition.wideReturn)
            transform: NotchContentStretch { transition: menuTransition; canvasWidth: menuTransition.snapshotWidth; compact: true }
            fillMode: Image.Stretch
            onStatusChanged: {
                menuTransition.snapshotReady = status === Image.Ready || status === Image.Error;
                if (menuTransition.preparing && card.Window.window) card.Window.window.update();
            }
        }
        CompactNotch {
            anchors.horizontalCenter: parent.horizontalCenter
            clockValue: quickNotes.clockValue
            batteryLevel: quickNotes.batteryLevel
            batteryCharging: quickNotes.batteryCharging
            visible: !menuTransition.dropdown && ((quickNotes.closing && !menuTransition.wideReturn) || menuTransition.snapshot === null)
            transform: NotchContentStretch { transition: menuTransition; canvasWidth: 236; compact: true }
        }
    }
}
