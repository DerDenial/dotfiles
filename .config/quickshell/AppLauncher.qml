import QtQuick
import QtCore
import QtQuick.Window
import QtQuick.Controls
import "Theme" as ThemePalette
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "Calculator.js" as Calculator

PanelWindow {
    id: launcher

    property alias opened: menuTransition.opened
    property alias closing: menuTransition.closing
    readonly property bool active: menuTransition.active
    readonly property bool ownsSurface: menuTransition.ownsSurface
    readonly property bool returning: menuTransition.returning
    readonly property real morphProgress: menuTransition.motion.amount
    property Item sourceNotch: null
    property bool canOpen: true
    signal aboutToOpen()
    NotchTransition {
        id: menuTransition
        dropdownAlignment: 0
        surface: card
        sourceNotch: launcher.sourceNotch
        expandedWidth: Math.min(560, launcher.width - 48)
        expandedHeight: Math.min(launcher.closing ? launcher.closingExpandedHeight : launcher.expandedHeight, launcher.height - (menuTransition.dropdown ? 58 : 24))
        canOpen: launcher.canOpen
        onAboutToOpen: launcher.aboutToOpen()
        onActivated: Qt.callLater(function() {
            if (!launcher.opened) return;
            launcher.resetViewToTop();
            if (launcher.searchField) launcher.searchField.forceActiveFocus();
        })
    }

    property string clockValue: "00:00"
    property int batteryLevel: 0
    property bool batteryCharging: false
    property int selectedMode: 0
    property int selectedIndex: 0
    property string homePath: Quickshell.env("HOME") || StandardPaths.writableLocation(StandardPaths.HomeLocation)
    readonly property var searchField: bodyLoader.item ? bodyLoader.item.searchInput : null
    readonly property var results: bodyLoader.item ? bodyLoader.item.resultsView : null
    property string query: searchField ? searchField.text.trim() : ""
    readonly property var calculation: selectedMode === 0 ? Calculator.evaluate(query) : ({intent: false, ok: false})
    readonly property bool calculating: calculation.intent === true
    property string calculationCopyError: ""
    property bool calculationCopyInFlight: false
    readonly property bool calculationCopyBusy: calculationCopyInFlight || calculationCopy.running
    property string copiedResult: ""
    property string copiedQuery: ""
    property int launcherSession: 0
    property int copiedSession: -1
    property bool closingFileBusy: false
    readonly property bool fileSearchBusy: closing && !opened ? closingFileBusy : fileSearch.busy
    readonly property bool showSections: selectedMode === 0 && (!query || query.length >= 2)
        || selectedMode === 2 && !query
    readonly property int fileCount: items.filter(item => item.kind === "file" || item.kind === "directory").length

    FileSearchState {
        id: fileSearch
        homePath: launcher.homePath
        query: launcher.query
        engaged: launcher.opened && ((launcher.selectedMode === 0 && !launcher.calculating) || launcher.selectedMode === 2)
        placesRequested: launcher.selectedMode === 2
    }

    readonly property var items: bodyLoader.active ? filteredItems() : []
    // Keep one logical selection order: pinned icons first, then ordinary rows.
    readonly property var pinnedItems: selectedMode === 0 && !query ? items.filter(item => item.favorite) : []
    readonly property int pinnedCount: pinnedItems.length
    readonly property var listItems: pinnedCount ? items.slice(pinnedCount) : items
    readonly property int pinnedColumns: Math.max(1, Math.min(6, Math.floor((menuTransition.expandedWidth - 24) / 72)))
    readonly property int pinnedRows: Math.ceil(pinnedCount / pinnedColumns)
    readonly property int pinnedHeaderHeight: pinnedCount ? 26 + pinnedRows * 68 + Math.max(0, pinnedRows - 1) * 8 + 12 : 0
    onItemsChanged: {
        selectedIndex = Math.min(selectedIndex, Math.max(0, items.length - 1));
        Qt.callLater(ensureSelectionVisible);
    }
    onSelectedIndexChanged: Qt.callLater(ensureSelectionVisible)
    readonly property int visibleRows: Math.min(listItems.length, pinnedCount ? 3 : 5)
    readonly property int visibleSectionCount: {
        if (!showSections) return 0;
        let count = 0;
        let previous = "";
        for (let i = 0; i < visibleRows; ++i) {
            if (listItems[i].group !== previous) { ++count; previous = listItems[i].group; }
        }
        return count;
    }
    readonly property real desiredExpandedHeight: Math.min(580, 158 + Math.max(112, pinnedHeaderHeight + visibleRows * 64 + Math.max(0, visibleRows - 1) * 6 + visibleSectionCount * 26))
    property real expandedHeight: desiredExpandedHeight
    property real closingExpandedHeight: desiredExpandedHeight
    Timer {
        id: resizeDebounce
        interval: 16
        onTriggered: if (launcher.opened) menuTransition.motion.moveTo(menuTransition.expandedWidth, menuTransition.expandedHeight, menuTransition.dropdown ? 24 : 28, 1, true)
    }
    onExpandedHeightChanged: if (opened) resizeDebounce.restart()


    FileView {
        id: launcherState
        path: launcher.homePath + "/.config/quickshell/launcher-state.json"
        blockLoading: true
        printErrors: false
        onAdapterUpdated: writeAdapter()
        JsonAdapter {
            id: history
            property var favoriteIds: []
            property var recentIds: []
        }
    }

    function toggleFavorite(id) {
        if (typeof id !== "string" || !id) return;
        const favorites = Array.from(history.favoriteIds || []);
        const index = favorites.indexOf(id);
        if (index >= 0) favorites.splice(index, 1);
        else favorites.push(id);
        history.favoriteIds = favorites;
        selectedIndex = Math.max(0, filteredItems().findIndex(item => item.id === id));
        if (selectedIndex === 0)
            Qt.callLater(function() { if (launcher.opened && launcher.results) launcher.results.positionViewAtBeginning(); });
    }

    function rememberApp(id) {
        history.recentIds = [id].concat(Array.from(history.recentIds || []).filter(value => value !== id)).slice(0, 12);
    }

    function focusSearch() { if (opened && searchField) searchField.forceActiveFocus(); }

    readonly property var modeNames: ["Apps", "Run", "Files"]
    readonly property var modeIcons: ["apps", "terminal", "folder_open"]

    function resolveAppIcon(icon) {
        const name = String(icon || "");
        if (!name) return "";
        // Desktop entries can supply a filename instead of a theme icon name.
        if (name.startsWith("/"))
            return "file://" + name.split("/").map(part => encodeURIComponent(part)).join("/");
        if (name.startsWith("file:")) return name;
        return Quickshell.iconPath(name, true);
    }

    function filteredItems() {
        if (!bodyLoader.active) return [];
        const q = query.toLocaleLowerCase();
        let items = [];

        if (selectedMode === 0) {
            if (calculating) return [{
                kind: "calculation", id: "calculator-result", icon: "calculate", group: "Calculator",
                title: calculation.ok ? "= " + calculation.text : "Calculator",
                detail: calculationCopyError || (calculationCopyBusy ? "Copying result…"
                    : calculation.ok ? calculation.expression + " · Enter to copy" : calculation.error || "Enter a calculation"),
                copyable: calculation.ok === true, ref: calculation.ok ? calculation.text : ""
            }];
            const favorites = Array.from(history.favoriteIds || []);
            const recent = Array.from(history.recentIds || []);
            const entries = Array.from(DesktopEntries.applications.values);
            for (const app of entries) {
                const name = String(app.name || "");
                const haystack = [name, app.genericName, app.comment, app.id, (app.keywords || []).join(" ")].join(" ").toLocaleLowerCase();
                if (q && !haystack.includes(q)) continue;
                const favoriteRank = favorites.indexOf(app.id);
                const recentRank = recent.indexOf(app.id);
                const normalizedName = name.toLocaleLowerCase();
                const score = !q ? 0 : normalizedName === q ? 0 : normalizedName.startsWith(q) ? 1 : normalizedName.split(/\s+/).some(word => word.startsWith(q)) ? 2 : normalizedName.includes(q) ? 3 : 4;
                items.push({
                    title: name,
                    detail: app.genericName || app.comment || "Application",
                    icon: app.icon,
                    kind: "app",
                    id: app.id,
                    favorite: favoriteRank >= 0,
                    group: q ? "Applications" : favoriteRank >= 0 ? "Pinned" : recentRank >= 0 ? "Recently used" : "Applications",
                    groupRank: favoriteRank >= 0 ? 0 : recentRank >= 0 ? 1 : 2,
                    order: favoriteRank >= 0 ? favoriteRank : recentRank,
                    score: score,
                    ref: app
                });
            }
            items.sort((a, b) => q
                ? a.score - b.score || Number(b.favorite) - Number(a.favorite) || a.title.localeCompare(b.title)
                : a.groupRank - b.groupRank || (a.groupRank < 2 ? a.order - b.order : a.title.localeCompare(b.title)));
            if (q.length >= 2) {
                const fileHits = fileSearch.items.slice(0, 8);
                items = items.slice(0, 80 - fileHits.length).concat(fileHits);
            }
        } else if (selectedMode === 1) {
            if (q) {
                items.push({
                    title: query,
                    detail: "Run command",
                    icon: "terminal",
                    kind: "command",
                    ref: query
                });
            }
        } else if (selectedMode === 2) {
            items = !q ? fileSearch.locations : q.length >= 2 ? fileSearch.items : [];
        }

        return items.slice(0, 80);
    }

    function chooseMode(index) {
        if (!Number.isInteger(index) || index < 0 || index >= modeNames.length) return;
        if (!bodyLoader.ensureLoaded()) return;
        if (index === selectedMode)
            return;
        selectedMode = index;
        selectedIndex = 0;
        searchField.text = "";
        modeAnimation.stop();
        contentStretch = 0.94;
        contentOffset = index > previousMode ? 14 : -14;
        previousMode = index;
        modeAnimation.start();
        searchField.forceActiveFocus();
    }

    property int previousMode: 0
    property real contentStretch: 1
    property real contentOffset: 0

    function resetViewToTop() {
        if (!results) return;
        results.cancelFlick();
        results.forceLayout();
        // Beginning includes the favorites header, unlike positioning row zero.
        results.positionViewAtBeginning();
        results.queueSelection(true);
    }

    function open() {
        if (opened || menuTransition.preparing || menuTransition.capturePending) return;
        if (!bodyLoader.ensureLoaded()) return;
        ++launcherSession;
        calculationCopyError = "";
        selectedMode = previousMode = 0;
        selectedIndex = 0;
        searchField.text = "";
        modeAnimation.stop();
        contentStretch = 1;
        contentOffset = 0;
        resetViewToTop();
        menuTransition.open();
    }

    function close() {
        resizeDebounce.stop();
        if (results) results.cancelFlick();
        if (opened) {
            closingExpandedHeight = Math.min(expandedHeight, height - (menuTransition.dropdown ? 58 : 24));
            closingFileBusy = fileSearch.busy;
        }
        menuTransition.close();
        if (searchField) searchField.focus = false;
    }

    function toggle() {
        if (opened || menuTransition.pendingOpen || menuTransition.preparing || menuTransition.capturePending) close();
        else open();
    }

    function fileUrl(path) {
        return "file://" + String(path).split("/").map(part => encodeURIComponent(part)).join("/");
    }

    function openFile(item, containingFolder) {
        const target = containingFolder && item.parent ? fileUrl(item.parent) : item.ref;
        if (!target) return;
        Quickshell.execDetached(["env", "QT_QPA_PLATFORMTHEME=gtk3",
            "GTK2_RC_FILES=/etc/gtk-2.0/gtkrc:" + launcher.homePath + "/.config/gtk-2.0/gtkrc", "xdg-open", target]);
        close();
    }

    function activateItem(index, containingFolder) {
        const entries = items;
        if (index < 0 || index >= entries.length)
            return;
        const item = entries[index];

        if (item.kind === "calculation") {
            copyCalculation(item);
        } else if (item.kind === "app") {
            rememberApp(item.id);
            Quickshell.execDetached({
                command: ["env", "QT_QPA_PLATFORMTHEME=gtk3", "GTK2_RC_FILES=/etc/gtk-2.0/gtkrc:" + launcher.homePath + "/.config/gtk-2.0/gtkrc"].concat(item.ref.command),
                workingDirectory: item.ref.workingDirectory
            });
            close();
        } else if (item.kind === "command") {
            Quickshell.execDetached(["env", "GTK2_RC_FILES=/etc/gtk-2.0/gtkrc:" + launcher.homePath + "/.config/gtk-2.0/gtkrc", "sh", "-lc", "export QT_QPA_PLATFORMTHEME=gtk3; " + item.ref]);
            close();
        } else if (item.kind === "directory" || item.kind === "file") {
            openFile(item, containingFolder);
        }
    }

    function copyCalculation(item) {
        if (!opened || calculationCopyBusy || !item || item.kind !== "calculation" || !item.copyable || typeof item.ref !== "string" || !item.ref) return;
        copiedResult = item.ref;
        copiedQuery = query;
        copiedSession = launcherSession;
        calculationCopyError = "";
        calculationCopyInFlight = true;
        calculationCopy.stdinEnabled = true;
        calculationCopyDeadline.restart();
        calculationCopy.running = true;
    }
    function finishCalculationCopy(code, status) {
        if (!calculationCopyInFlight) return;
        calculationCopyDeadline.stop();
        calculationCopyInFlight = false;
        if (code !== 0 || status !== 0) {
            if (selectedMode === 0 && copiedSession === launcherSession && query === copiedQuery)
                calculationCopyError = "Could not copy the result. Please try again.";
            return;
        }
        // An old copy must not dismiss a different query or a reopened launcher.
        if (opened && selectedMode === 0 && copiedSession === launcherSession && query === copiedQuery) close();
    }
    onQueryChanged: calculationCopyError = ""
    Process {
        id: calculationCopy
        command: ["wl-copy", "--type", "text/plain;charset=utf-8"]
        stderr: StdioCollector { }
        onStarted: {
            write(launcher.copiedResult);
            stdinEnabled = false;
        }
        onExited: (code, status) => launcher.finishCalculationCopy(code, status)
        onRunningChanged: if (!running && launcher.calculationCopyInFlight) Qt.callLater(function() {
            if (!calculationCopy.running && launcher.calculationCopyInFlight) launcher.finishCalculationCopy(-1, -1);
        })
    }
    Timer {
        id: calculationCopyDeadline
        interval: 3000
        onTriggered: {
            if (calculationCopy.running && Number(calculationCopy.processId) > 0) calculationCopy.signal(15);
            launcher.finishCalculationCopy(-1, -1);
        }
    }

    function ensureSelectionVisible() {
        if (!opened || !results) return;
        if (selectedIndex < pinnedCount) {
            if (results.headerItem) results.headerItem.ensureVisible(selectedIndex);
        } else if (listItems.length) {
            results.positionViewAtIndex(selectedIndex - pinnedCount, ListView.Contain);
        }
        results.queueSelection(false);
    }

    function moveSelection(direction) {
        const count = items.length;
        if (!count) return;
        if (pinnedCount && selectedIndex < pinnedCount) {
            const row = Math.floor(selectedIndex / pinnedColumns);
            if (direction > 0) {
                selectedIndex = row + 1 < pinnedRows
                    ? Math.min(selectedIndex + pinnedColumns, pinnedCount - 1)
                    : pinnedCount < count ? pinnedCount : selectedIndex % pinnedColumns;
            } else {
                selectedIndex = row > 0 ? selectedIndex - pinnedColumns : count - 1;
            }
        } else {
            selectedIndex = (selectedIndex + direction + count) % count;
        }
    }

    function movePinnedHorizontal(direction) {
        if (!pinnedCount || selectedIndex >= pinnedCount) return;
        const next = selectedIndex + direction;
        selectedIndex = next < 0 ? pinnedCount - 1
            : next < pinnedCount ? next : pinnedCount < items.length ? pinnedCount : 0;
    }

    visible: menuTransition.visible
    WlrLayershell.keyboardFocus: opened || menuTransition.preparing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    IpcHandler {
        target: "appLauncher"
        function toggle(): void { launcher.toggle(); }
        function open(): void { launcher.open(); }
        function close(): void { launcher.close(); }
    }

    MouseArea {
        anchors.fill: parent
        enabled: launcher.opened
        onClicked: launcher.close()
    }

    NotchMenuSurface {
        id: card
        transition: menuTransition
        color: ThemePalette.Theme.notchBg
        border.width: 1
        border.color: ThemePalette.Theme.border

        // Meet the display edge without a horizontal border.
        Rectangle {
            visible: !menuTransition.dropdown
            x: 0; y: 0
            width: parent.width
            height: parent.border.width
            color: parent.color
            z: 100
        }

        MenuBodyLoader {
            id: bodyLoader
            engaged: menuTransition.active || menuTransition.pendingOpen
            width: menuTransition.expandedWidth - 32
            height: menuTransition.expandedHeight - 30
            anchors.horizontalCenter: parent.horizontalCenter
            y: 16 * Math.min(1, bodyStretch.unfold)
            visible: launcher.opened || launcher.closing
            transform: NotchContentStretch {
                id: bodyStretch
                transition: menuTransition
                canvasWidth: menuTransition.expandedWidth - 32
                horizontalInset: 32
            }
            enabled: launcher.opened
            sourceComponent: ColumnLayout {
                property alias searchInput: searchField
                property alias resultsView: results
                anchors.fill: parent
                spacing: 10

                TextField {
                    id: searchField
                    focus: launcher.opened
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    verticalAlignment: TextInput.AlignVCenter
                    color: ThemePalette.Theme.textBright
                    selectionColor: ThemePalette.Theme.accent
                    selectedTextColor: ThemePalette.Theme.bg0
                    font.family: "Inter"
                    font.pixelSize: 15
                    clip: true
                    leftPadding: 46
                    rightPadding: 40
                    placeholderText: launcher.selectedMode === 0 ? "Search apps, files or calculate…"
                        : launcher.selectedMode === 1 ? "Run a command…"
                        : "Search files and folders…"
                    placeholderTextColor: ThemePalette.Theme.muted
                    background: Rectangle {
                        radius: 16
                        color: ThemePalette.Theme.surface
                        border.width: 1
                        border.color: searchField.activeFocus ? Qt.rgba(ThemePalette.Theme.accent.r, ThemePalette.Theme.accent.g, ThemePalette.Theme.accent.b, 0.45) : ThemePalette.Theme.border
                        Behavior on border.color { ColorAnimation { duration: 180 } }
                    }
                    Text {
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: "search"
                        color: searchField.activeFocus ? ThemePalette.Theme.accent : ThemePalette.Theme.muted
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 22
                    }
                    ToolButton {
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        height: 34
                        visible: searchField.text.length > 0
                        text: "close"
                        Accessible.name: "Clear search"
                        contentItem: Text { text: parent.text; color: ThemePalette.Theme.muted; font.family: "Material Symbols Rounded"; font.pixelSize: 18; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { radius: 10; color: parent.hovered ? ThemePalette.Theme.surfaceRaised : "transparent" }
                        onClicked: { searchField.clear(); searchField.forceActiveFocus(); }
                    }
                    onTextChanged: {
                        launcher.selectedIndex = 0;
                        Qt.callLater(function() { if (launcher.opened && launcher.results) launcher.results.positionViewAtBeginning(); });
                    }
                    Keys.onEscapePressed: launcher.close()
                    Keys.onReturnPressed: event => launcher.activateItem(launcher.selectedIndex, !!(event.modifiers & Qt.ControlModifier))
                    Keys.onEnterPressed: event => launcher.activateItem(launcher.selectedIndex, !!(event.modifiers & Qt.ControlModifier))
                    Keys.onDownPressed: launcher.moveSelection(1)
                    Keys.onUpPressed: launcher.moveSelection(-1)
                    Keys.onPressed: function(event) {
                        if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) && !searchField.text.length && launcher.pinnedCount && launcher.selectedIndex < launcher.pinnedCount && !(event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier | Qt.AltModifier | Qt.MetaModifier))) {
                            launcher.movePinnedHorizontal(event.key === Qt.Key_Right ? 1 : -1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier) && launcher.selectedMode === 0 && launcher.items.length && launcher.items[launcher.selectedIndex].kind === "app") {
                            launcher.toggleFavorite(launcher.items[launcher.selectedIndex].id);
                            event.accepted = true;
                        } else if (event.key >= Qt.Key_1 && event.key < Qt.Key_1 + launcher.modeNames.length && (event.modifiers & Qt.ControlModifier)) {
                            launcher.chooseMode(event.key - Qt.Key_1);
                            event.accepted = true;
                        }
                    }
                    Keys.onTabPressed: launcher.chooseMode((launcher.selectedMode + 1) % launcher.modeNames.length)
                    Keys.onBacktabPressed: launcher.chooseMode((launcher.selectedMode + launcher.modeNames.length - 1) % launcher.modeNames.length)
                }

                Item {
                    id: modeRail
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    Row {
                        anchors.fill: parent
                        Repeater {
                            model: launcher.modeNames
                            delegate: Button {
                                required property string modelData
                                required property int index
                                width: modeRail.width / launcher.modeNames.length
                                height: 30
                                text: modelData
                                contentItem: Text { text: parent.text; color: index === launcher.selectedMode ? ThemePalette.Theme.accent : ThemePalette.Theme.muted; font.family: "Inter"; font.pixelSize: 12; font.weight: Font.Medium; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                background: Rectangle { radius: 10; color: parent.hovered ? ThemePalette.Theme.surface : "transparent" }
                                onClicked: launcher.chooseMode(index)
                            }
                        }
                    }
                    Rectangle {
                        y: 30
                        x: modeRail.width / launcher.modeNames.length * launcher.selectedMode + 14
                        width: modeRail.width / launcher.modeNames.length - 28
                        height: 2
                        radius: 1
                        color: ThemePalette.Theme.accent
                        Behavior on x { NumberAnimation { duration: 230; easing.type: Easing.OutBack; easing.overshoot: 0.65 } }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: launcher.contentOffset
                        anchors.rightMargin: -launcher.contentOffset
                        transform: Scale {
                            origin.x: (menuTransition.expandedWidth - 32) / 2
                            origin.y: 0
                            xScale: 1 + (1 - launcher.contentStretch) * 0.5
                            yScale: launcher.contentStretch
                        }

                        ListView {
                            id: results
                            property rect selectionRect: Qt.rect(0, 0, 0, 0)
                            property real selectionCorner: 16
                            property bool selectionReady: false
                            property bool pendingSelectionSnap: true
                            readonly property bool selectingPin: launcher.pinnedCount > 0 && launcher.selectedIndex < launcher.pinnedCount

                            function queueSelection(reset) {
                                if (reset) pendingSelectionSnap = true;
                                Qt.callLater(updateSelection);
                            }

                            function updateSelection() {
                                if (!launcher.items.length) {
                                    selectionReady = false;
                                    pendingSelectionSnap = true;
                                    return;
                                }
                                let rect = null;
                                if (selectingPin) {
                                    if (headerItem) rect = headerItem.selectedTileRect(launcher.selectedIndex);
                                } else if (currentItem && currentItem.itemIndex === launcher.selectedIndex) {
                                    const point = currentItem.mapToItem(contentItem, 0, 0);
                                    // Leave room for the small rebound at the clipped viewport edges.
                                    rect = Qt.rect(point.x + 2, point.y + 2, currentItem.width - 4, currentItem.height - 4);
                                }
                                // Delegates may briefly be absent while ListView lays out a new index.
                                // Retain the previous geometry until the real target becomes available.
                                if (!rect || rect.width <= 0 || rect.height <= 0) return;
                                const reset = pendingSelectionSnap || !selectionReady
                                    || Math.abs(rect.y - selectionRect.y) > Math.max(1, height) * 1.5;
                                selectionRect = rect;
                                selectionCorner = selectingPin ? 16 : 15;
                                selectionReady = true;
                                if (reset) resultSelection.snap();
                                pendingSelectionSnap = false;
                            }

                            onCurrentIndexChanged: queueSelection(false)
                            onCurrentItemChanged: queueSelection(false)
                            onModelChanged: queueSelection(true)
                            onWidthChanged: queueSelection(true)
                            Component.onCompleted: queueSelection(true)

                            Connections {
                                target: launcher
                                function onSelectedIndexChanged() { results.queueSelection(false); }
                                function onPinnedItemsChanged() { results.queueSelection(true); }
                                function onPinnedColumnsChanged() { results.queueSelection(true); }
                                function onOpenedChanged() { if (launcher.opened) results.queueSelection(true); }
                            }
                            Connections {
                                target: results.currentItem
                                function onXChanged() { results.queueSelection(false); }
                                function onYChanged() { results.queueSelection(false); }
                                function onWidthChanged() { results.queueSelection(false); }
                                function onHeightChanged() { results.queueSelection(false); }
                            }
                            SelectionTrail {
                                id: resultSelection
                                parent: results.contentItem
                                z: 0
                                width: results.width
                                height: results.height
                                targetRect: results.selectionRect
                                radius: results.selectionCorner
                                leadingAccent: !results.selectingPin
                                engaged: results.selectionReady && launcher.items.length > 0 && (launcher.opened || launcher.closing)
                                animate: launcher.opened && !launcher.closing
                                accentColor: ThemePalette.Theme.accent
                                surfaceColor: ThemePalette.Theme.surface
                            }
                            anchors.fill: parent
                            clip: true
                            spacing: 6
                            boundsBehavior: Flickable.StopAtBounds
                            currentIndex: launcher.selectedIndex >= launcher.pinnedCount ? launcher.selectedIndex - launcher.pinnedCount : -1
                            model: launcher.listItems
                            highlightRangeMode: ListView.ApplyRange
                            preferredHighlightBegin: 0
                            preferredHighlightEnd: height
                            header: Item {
                                id: pinnedHeader
                                z: 1
                                width: results.width
                                onYChanged: results.queueSelection(false)
                                onHeightChanged: results.queueSelection(true)
                                height: launcher.pinnedHeaderHeight
                                visible: launcher.pinnedCount > 0

                                function ensureVisible(index) {
                                    const tile = pinnedRepeater.itemAt(index);
                                    if (!tile) return;
                                    const top = tile.mapToItem(results.contentItem, 0, 0).y;
                                    const bottom = top + tile.height;
                                    if (top < results.contentY + 8)
                                        results.contentY = top - 8;
                                    else if (bottom > results.contentY + results.height - 8)
                                        results.contentY = bottom - results.height + 8;
                                }

                                function selectedTileRect(index) {
                                    const tile = pinnedRepeater.itemAt(index);
                                    if (!tile) return null;
                                    const point = tile.mapToItem(results.contentItem, 0, 0);
                                    return Qt.rect(point.x, point.y, tile.width, tile.height);
                                }

                                function resetSelection() { results.queueSelection(true); }

                                Text {
                                    x: 10
                                    height: 26
                                    verticalAlignment: Text.AlignVCenter
                                    text: "PINNED"
                                    color: ThemePalette.Theme.muted
                                    font.family: "Inter"
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 1.4
                                }
                                Grid {
                                    id: pinnedGrid
                                    x: 4
                                    y: 26
                                    width: pinnedHeader.width - 8
                                    columns: launcher.pinnedColumns
                                    spacing: 8
                                    onWidthChanged: pinnedHeader.resetSelection()

                                    Repeater {
                                        id: pinnedRepeater
                                        model: launcher.pinnedItems
                                        onItemAdded: pinnedHeader.resetSelection()
                                        delegate: Item {
                                            id: pinnedTile
                                            required property int index
                                            required property var modelData
                                            readonly property bool selected: index === launcher.selectedIndex
                                            width: (pinnedGrid.width - (launcher.pinnedColumns - 1) * pinnedGrid.spacing) / launcher.pinnedColumns
                                            height: 68
                                            scale: pinMouse.pressed && (pinMouse.pressedButtons & Qt.LeftButton) ? 0.95 : 1
                                            Accessible.role: Accessible.Button
                                            Accessible.name: modelData.title
                                            Accessible.description: "Pinned application. Ctrl+D or right click to unpin."
                                            Accessible.onPressAction: launcher.activateItem(pinnedTile.index)
                                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 16
                                                color: pinMouse.containsMouse && !pinnedTile.selected ? ThemePalette.Theme.surface : "transparent"
                                                Behavior on color { ColorAnimation { duration: 140 } }
                                            }
                                            Image {
                                                id: pinnedIcon
                                                anchors.centerIn: parent
                                                width: 36
                                                height: 36
                                                source: launcher.resolveAppIcon(pinnedTile.modelData.icon)
                                                sourceSize.width: 72
                                                sourceSize.height: 72
                                                asynchronous: true
                                                fillMode: Image.PreserveAspectFit
                                                visible: status === Image.Ready
                                            }
                                            Text {
                                                anchors.centerIn: parent
                                                text: "apps"
                                                color: ThemePalette.Theme.accent
                                                font.family: "Material Symbols Rounded"
                                                font.pixelSize: 30
                                                visible: pinnedIcon.status !== Image.Ready
                                            }
                                            MouseArea {
                                                id: pinMouse
                                                anchors.fill: parent
                                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: function(mouse) {
                                                    if (mouse.button === Qt.RightButton) {
                                                        launcher.toggleFavorite(pinnedTile.modelData.id);
                                                        launcher.focusSearch();
                                                    } else {
                                                        launcher.selectedIndex = pinnedTile.index;
                                                        launcher.activateItem(pinnedTile.index);
                                                    }
                                                }
                                            }
                                            ToolTip.visible: pinMouse.containsMouse
                                            ToolTip.delay: 450
                                            ToolTip.text: pinnedTile.modelData.title + " · Right click to unpin"
                                        }
                                    }
                                }
                            }
                            section.property: launcher.showSections ? "group" : ""
                            section.criteria: ViewSection.FullString
                            section.delegate: Item {
                                z: 1
                                required property string section
                                width: results.width
                                height: 26
                                Text {
                                    x: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: section.toUpperCase()
                                    color: ThemePalette.Theme.muted
                                    font.family: "Inter"
                                    font.pixelSize: 9
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 1.4
                                }
                            }
                            highlight: null
                            delegate: Item {
                                id: resultRow
                                z: 1
                                required property int index
                                required property var modelData
                                readonly property int itemIndex: index + launcher.pinnedCount
                                readonly property bool selected: itemIndex === launcher.selectedIndex
                                readonly property string appIconSource: modelData.kind === "app" ? launcher.resolveAppIcon(modelData.icon)
                                    : modelData.themeIcon ? launcher.resolveAppIcon(modelData.themeIcon) : ""
                                width: results.width
                                height: 64
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 15
                                    color: ThemePalette.Theme.surface
                                    opacity: rowMouse.containsMouse && !resultRow.selected ? 0.65 : 0
                                    Behavior on opacity { NumberAnimation { duration: 140 } }
                                }
                                MouseArea {
                                    id: rowMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { launcher.selectedIndex = resultRow.itemIndex; launcher.activateItem(resultRow.itemIndex); }
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 12
                                    Rectangle {
                                        Layout.preferredWidth: 42
                                        Layout.preferredHeight: 42
                                        radius: 12
                                        color: ThemePalette.Theme.surfaceAlt
                                        Image {
                                            id: appIcon
                                            anchors.centerIn: parent
                                            width: 32
                                            height: 32
                                            visible: status === Image.Ready
                                            source: resultRow.appIconSource
                                            sourceSize.width: 48
                                            sourceSize.height: 48
                                            asynchronous: true
                                            fillMode: Image.PreserveAspectFit
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            visible: appIcon.status !== Image.Ready
                                            text: resultRow.modelData.kind === "app" ? "apps" : resultRow.modelData.icon
                                            color: ThemePalette.Theme.accent
                                            font.family: "Material Symbols Rounded"
                                            font.pixelSize: 25
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3
                                        Text {
                                            Layout.fillWidth: true
                                            text: resultRow.modelData.title
                                            textFormat: Text.PlainText
                                            color: ThemePalette.Theme.textBright
                                            font.family: "Inter"
                                            font.pixelSize: resultRow.modelData.kind === "calculation" && resultRow.modelData.copyable ? 23 : 15
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: resultRow.modelData.detail
                                            textFormat: Text.PlainText
                                            color: ThemePalette.Theme.muted
                                            font.family: "Inter"
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                        }
                                    }
                                    ToolButton {
                                        Layout.preferredWidth: 30
                                        Layout.preferredHeight: 32
                                        visible: resultRow.modelData.kind === "calculation"
                                        enabled: !!resultRow.modelData.copyable && !launcher.calculationCopyBusy
                                        text: "content_copy"
                                        Accessible.name: "Copy calculation result"
                                        ToolTip.visible: hovered
                                        ToolTip.delay: 450
                                        ToolTip.text: "Copy result · Enter"
                                        contentItem: Text { text: parent.text; color: parent.enabled ? ThemePalette.Theme.accent : ThemePalette.Theme.muted; font.family: "Material Symbols Rounded"; font.pixelSize: 18; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        background: Rectangle { radius: 9; color: parent.hovered ? ThemePalette.Theme.surfaceAlt : "transparent" }
                                        onClicked: launcher.copyCalculation(resultRow.modelData)
                                    }
                                    ToolButton {
                                        Layout.preferredWidth: 30
                                        Layout.preferredHeight: 32
                                        visible: resultRow.modelData.kind === "file" || resultRow.modelData.kind === "directory"
                                        text: "folder_open"
                                        Accessible.name: "Open containing folder"
                                        ToolTip.visible: hovered
                                        ToolTip.delay: 450
                                        ToolTip.text: "Open containing folder · Ctrl+Enter"
                                        contentItem: Text { text: parent.text; color: parent.hovered ? ThemePalette.Theme.accent : ThemePalette.Theme.muted; font.family: "Material Symbols Rounded"; font.pixelSize: 18; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        background: Rectangle { radius: 9; color: parent.hovered ? ThemePalette.Theme.surfaceRaised : "transparent" }
                                        onClicked: launcher.openFile(resultRow.modelData, true)
                                    }
                                    ToolButton {
                                        Layout.preferredWidth: 30
                                        Layout.preferredHeight: 32
                                        visible: resultRow.modelData.kind === "app"
                                        text: "push_pin"
                                        Accessible.name: resultRow.modelData.favorite ? "Unpin application" : "Pin application"
                                        ToolTip.visible: hovered
                                        ToolTip.delay: 400
                                        ToolTip.text: resultRow.modelData.favorite ? "Unpin · Ctrl+D" : "Pin · Ctrl+D"
                                        contentItem: Text { text: parent.text; color: resultRow.modelData.favorite ? ThemePalette.Theme.accent : ThemePalette.Theme.muted; opacity: resultRow.modelData.favorite || parent.hovered ? 1 : 0.4; font.family: "Material Symbols Rounded"; font.pixelSize: 18; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                        background: Rectangle { radius: 9; color: parent.hovered ? ThemePalette.Theme.surfaceRaised : "transparent" }
                                        onClicked: { launcher.toggleFavorite(resultRow.modelData.id); launcher.focusSearch(); }
                                    }
                                }
                            }
                        }
                        Column {
                            anchors.centerIn: parent
                            spacing: 8
                            visible: launcher.items.length === 0
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: launcher.selectedMode === 1 ? "terminal" : launcher.fileSearchBusy ? "manage_search" : "search_off"; color: ThemePalette.Theme.accent; opacity: 0.7; font.family: "Material Symbols Rounded"; font.pixelSize: 28 }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: launcher.selectedMode === 1 ? "Ready when you are" : launcher.fileSearchBusy ? "Searching your files…" : launcher.selectedMode === 2 && launcher.query.length < 2 ? "Your files, one search away" : "Nothing found"; color: ThemePalette.Theme.textBright; font.family: "Inter"; font.pixelSize: 14; font.weight: Font.Medium }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: launcher.selectedMode === 1 ? "Type a command above to run it" : launcher.fileSearchBusy ? "Matching filenames in Home" : fileSearch.error ? fileSearch.error : launcher.selectedMode === 2 && launcher.query.length < 2 ? "Type at least two characters to search Home" : fileSearch.partial ? "Try a more specific filename" : "Try a different search"; color: ThemePalette.Theme.muted; font.family: "Inter"; font.pixelSize: 11 }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 18
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        text: launcher.calculating ? launcher.calculation.ok ? "Calculator · Result ready" : "Calculator"
                            : launcher.fileSearchBusy ? "Searching files…"
                            : launcher.selectedMode === 2 ? !launcher.query ? "Quick places · Search Home"
                                : launcher.query.length < 2 ? "Type at least 2 characters"
                                : launcher.items.length + (fileSearch.partial ? "+" : "") + " results · Home"
                            : launcher.selectedMode === 0 && launcher.query.length >= 2 ? (launcher.items.length - launcher.fileCount) + " apps · " + launcher.fileCount + " files"
                            : launcher.items.length + (launcher.selectedMode === 1 ? " command" : launcher.items.length === 1 ? " app" : " apps")
                        color: ThemePalette.Theme.muted
                        font.family: "Inter"
                        font.pixelSize: 10
                        elide: Text.ElideMiddle
                    }
                    Text { text: launcher.calculating ? (launcher.calculation.ok ? "Enter Copy result   ·   Esc Close" : "Finish expression   ·   Esc Close") : (launcher.pinnedCount ? "↑↓←→" : "↑↓") + " Navigate   ·   Enter Open   ·   "
                        + (launcher.items[launcher.selectedIndex] && (launcher.items[launcher.selectedIndex].kind === "file" || launcher.items[launcher.selectedIndex].kind === "directory") ? "Ctrl+Enter Folder" : "Tab Switch"); color: ThemePalette.Theme.muted; font.family: "Inter"; font.pixelSize: 10 }
                }
            }
        }

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            width: menuTransition.snapshotWidth
            height: menuTransition.snapshotHeight
            source: menuTransition.snapshot ? menuTransition.snapshot.url : ""
            visible: !menuTransition.dropdown && menuTransition.snapshot !== null && (!launcher.closing || menuTransition.wideReturn)
            transform: NotchContentStretch {
                transition: menuTransition
                canvasWidth: menuTransition.snapshotWidth
                compact: true
            }
            fillMode: Image.Stretch
            onStatusChanged: {
                menuTransition.snapshotReady = status === Image.Ready || status === Image.Error;
                if (menuTransition.preparing && card.Window.window) card.Window.window.update();
            }
        }
        CompactNotch {
            anchors.horizontalCenter: parent.horizontalCenter
            clockValue: launcher.clockValue
            batteryLevel: launcher.batteryLevel
            batteryCharging: launcher.batteryCharging
            visible: !menuTransition.dropdown && ((launcher.closing && !menuTransition.wideReturn) || menuTransition.snapshot === null)
            transform: NotchContentStretch {
                transition: menuTransition
                canvasWidth: 236
                compact: true
            }
        }
    }

    ParallelAnimation {
        id: modeAnimation
        NumberAnimation {
            target: launcher
            property: "contentStretch"
            to: 1
            duration: 250
            easing.type: Easing.OutBack
            easing.overshoot: 0.65
        }
        NumberAnimation {
            target: launcher
            property: "contentOffset"
            to: 0
            duration: 250
            easing.type: Easing.OutBack
            easing.overshoot: 0.65
        }
    }

}
