import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
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
    signal aboutToOpen()
    readonly property var searchField: bodyLoader.item ? bodyLoader.item.searchField : null
    readonly property var themeRail: bodyLoader.item ? bodyLoader.item.themeRail : null
    readonly property var wallpaperRail: bodyLoader.item ? bodyLoader.item.wallpaperRail : null
    readonly property var wallpaperFiles: wallpaperModelLoader.item
    readonly property bool wallpaperPreviewsActive: menuTransition.active && (page === 1 || Math.abs(pageSlide) > 0.001)
    readonly property color selectionAccent: selectedTheme.colors.accent || selectedTheme.colors.aqua
    readonly property color selectionOnAccent: selectedTheme.colors.onAccent || selectedTheme.colors.bg0
    readonly property string selectedWallpaperFolder: ThemeApi.Theme.wallpaperRoot + "/" + selectedTheme.folder
    readonly property bool wallpaperModelReady: wallpaperFiles && wallpaperFiles.status === FolderListModel.Ready
        && (wallpaperFiles.count === 0 || String(wallpaperFiles.get(0, "filePath")).startsWith(selectedWallpaperFolder + "/"))
    readonly property int wallpaperCount: wallpaperModelReady ? wallpaperFiles.count : 0
    readonly property bool validThemeSelection: filteredThemes().some(item => item.id === selectedThemeId)
    readonly property bool validWallpaperSelection: wallpaperModelReady && wallpaperCount > 0
        && selectedWallpaperPath.startsWith(selectedWallpaperFolder + "/")
    readonly property bool canApplySelection: !pendingApply && (page === 0 ? validThemeSelection : validWallpaperSelection)
    NotchTransition {
        id: menuTransition
        dropdownAlignment: 0.5
        surface: card
        sourceNotch: picker.sourceNotch
        expandedWidth: Math.min(900, picker.width - 40)
        expandedHeight: Math.min(366, picker.height - (menuTransition.dropdown ? 58 : 24))
        canOpen: picker.canOpen
        onAboutToOpen: picker.aboutToOpen()
        onActivated: Qt.callLater(picker.focusPage)
    }

    property bool pendingApply: false
    property int page: 0
    property real pageSlide: page
    Behavior on pageSlide {
        enabled: picker.opened
        NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 0.65 }
    }
    property string selectedThemeId: ThemeApi.Theme.activeThemeId
    property string selectedWallpaperPath: ""
    property int selectedWallpaperIndex: 0
    property string clockValue: "00:00"
    property int batteryLevel: 0
    property bool batteryCharging: false
    readonly property var selectedTheme: ThemeApi.Theme.themes.find(item => item.id === selectedThemeId) || ThemeApi.Theme.themes[0]
    onSelectedThemeIdChanged: {
        pendingApply = false;
        selectedWallpaperIndex = 0;
        selectedWallpaperPath = selectedThemeId === ThemeApi.Theme.activeThemeId ? ThemeApi.Theme.activeWallpaper : "";
    }

    function open() {
        if (opened || menuTransition.preparing || menuTransition.capturePending) return;
        if (!bodyLoader.ensureLoaded()) return;
        if (!closing && !returning) {
            pendingApply = false;
            page = 0;
            selectedThemeId = ThemeApi.Theme.activeThemeId;
            selectedWallpaperPath = ThemeApi.Theme.activeWallpaper;
            selectedWallpaperIndex = 0;
            searchField.text = "";
        }
        menuTransition.open();
    }

    function close() {
        pendingApply = false;
        menuTransition.close();
        if (searchField) searchField.focus = false;
    }

    function toggle() {
        if (opened || menuTransition.pendingOpen || menuTransition.preparing || menuTransition.capturePending) close();
        else open();
    }

    function filteredThemes() {
        const q = searchField ? searchField.text.trim().toLocaleLowerCase() : "";
        const matches = ThemeApi.Theme.themes.filter(item => !q || (item.name + " " + item.flavor).toLocaleLowerCase().includes(q));
        return matches.filter(item => item.id === "material").concat(matches.filter(item => item.id !== "material"));
    }

    function filteredThemeIndex() {
        return filteredThemes().findIndex(item => item.id === selectedThemeId);
    }

    function focusPage() {
        if (!opened) return;
        if (page === 0 && searchField) searchField.forceActiveFocus();
        else card.forceActiveFocus();
    }

    function chooseTheme(id) {
        if (!opened || !filteredThemes().some(item => item.id === id)) return;
        pendingApply = false;
        selectedThemeId = id;
        focusPage();
    }

    function leaveWallpapers() {
        if (!opened) return;
        pendingApply = false;
        page = 0;
        Qt.callLater(picker.focusPage);
    }

    function moveTheme(direction) {
        pendingApply = false;
        const list = filteredThemes();
        if (list.length === 0)
            return;
        let index = filteredThemeIndex();
        if (index < 0)
            index = 0;
        else
            index = (index + direction + list.length) % list.length;
        selectedThemeId = list[index].id;
        selectedWallpaperPath = "";
        selectedWallpaperIndex = 0;
    }

    function enterWallpapers() {
        if (!opened || !bodyLoader.item) return;
        pendingApply = false;
        page = 1;
        if (selectedWallpaperPath === "" && wallpaperModelReady && wallpaperCount > 0) {
            selectedWallpaperIndex = 0;
            selectedWallpaperPath = wallpaperFiles.get(0, "filePath");
        } else {
            const idx = wallpaperIndexForPath(selectedWallpaperPath);
            if (idx >= 0)
                selectedWallpaperIndex = idx;
        }
        syncWallpaperSelection();
        card.forceActiveFocus();
    }

    function chooseWallpaper(index) {
        if (!opened || !wallpaperModelReady || index < 0 || index >= wallpaperCount) return;
        pendingApply = false;
        selectedWallpaperIndex = index;
        selectedWallpaperPath = wallpaperFiles.get(index, "filePath");
        card.forceActiveFocus();
    }

    function openWallpaperFolder() {
        const folder = selectedWallpaperFolder;
        close();
        Quickshell.execDetached(["xdg-open", folder]);
    }

    function syncWallpaperSelection() {
        if (!wallpaperModelReady || wallpaperCount === 0)
            return;
        const expectedFolder = ThemeApi.Theme.wallpaperRoot + "/" + selectedTheme.folder + "/";
        if (!wallpaperFiles.get(0, "filePath").startsWith(expectedFolder))
            return;
        const rememberedIndex = wallpaperIndexForPath(selectedWallpaperPath);
        selectedWallpaperIndex = rememberedIndex >= 0 ? rememberedIndex : Math.max(0, Math.min(selectedWallpaperIndex, wallpaperFiles.count - 1));
        selectedWallpaperPath = wallpaperFiles.get(selectedWallpaperIndex, "filePath");
        Qt.callLater(function() {
            if (picker.opened && picker.page === 1 && picker.wallpaperRail)
                picker.wallpaperRail.centerCurrent(true);
        });
    }

    function wallpaperIndexForPath(path) {
        if (!wallpaperFiles) return -1;
        for (let i = 0; i < wallpaperFiles.count; ++i) {
            if (wallpaperFiles.get(i, "filePath") === path)
                return i;
        }
        return -1;
    }

    function moveWallpaper(direction) {
        pendingApply = false;
        const count = wallpaperCount;
        if (count === 0)
            return;
        selectedWallpaperIndex = (selectedWallpaperIndex + direction + count) % count;
        selectedWallpaperPath = wallpaperFiles.get(selectedWallpaperIndex, "filePath");
    }

    function refreshWallpaperModel() {
        // Folder scans can finish after the visual body has been released.
        if (!bodyLoader.item && !pendingApply) return;
        if (bodyLoader.item) syncWallpaperSelection();
        if (pendingApply) applySelection();
    }

    function applySelection() {
        if (!opened && !pendingApply) return;
        if (page === 0 && !validThemeSelection) return;
        if (page === 1 && !validWallpaperSelection) return;
        let wallpaper = selectedWallpaperPath;
        if (page === 0) {
            const folder = ThemeApi.Theme.wallpaperRoot + "/" + selectedTheme.folder + "/";
            if (!wallpaperModelReady) {
                pendingApply = true;
                return;
            }
            const previous = ThemeApi.Theme.rememberedWallpaper(selectedThemeId);
            const candidates = [];
            for (let i = 0; i < wallpaperFiles.count; ++i) {
                const path = wallpaperFiles.get(i, "filePath");
                if (path.startsWith(folder) && (wallpaperFiles.count === 1 || path !== previous))
                    candidates.push(path);
            }
            wallpaper = candidates.length ? candidates[Math.floor(Math.random() * candidates.length)] : "";
        }
        pendingApply = false;
        ThemeApi.Theme.selectTheme(selectedThemeId, wallpaper);
        close();
    }

    visible: menuTransition.visible
    WlrLayershell.keyboardFocus: opened || menuTransition.preparing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }


    IpcHandler {
        target: "themeSwitcher"
        function randomWallpaper(): void { ThemeApi.Theme.randomWallpaper(); }
        function toggle(): void { picker.toggle(); }
        function open(): void { picker.open(); }
        function close(): void { picker.close(); }
    }

    Loader {
        id: wallpaperModelLoader
        active: bodyLoader.active || picker.pendingApply
        asynchronous: false
        sourceComponent: FolderListModel {
            folder: "file://" + ThemeApi.Theme.wallpaperRoot + "/" + picker.selectedTheme.folder
            showDirs: false
            caseSensitive: false
            nameFilters: ["*.[pP][nN][gG]", "*.[jJ][pP][gG]", "*.[jJ][pP][eE][gG]", "*.[wW][eE][bB][pP]", "*.[bB][mM][pP]"]
            sortField: FolderListModel.Name
            onStatusChanged: if (status === FolderListModel.Ready) Qt.callLater(picker.refreshWallpaperModel)
            onCountChanged: Qt.callLater(picker.refreshWallpaperModel)
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: picker.opened
        onClicked: picker.close()
    }

    Rectangle {
        x: 0
        y: menuTransition.dropdown ? 34 : 0
        width: parent.width
        height: parent.height - y
        color: "#40000000"
        opacity: picker.morphProgress * 0.35
        MouseArea { anchors.fill: parent; onClicked: picker.close() }
    }

    NotchMenuSurface {
        id: card
        transition: menuTransition
        color: ThemeApi.Theme.notchBg
        border.width: 1
        border.color: ThemeApi.Theme.border

        // Meet the display edge without a horizontal border.
        Rectangle {
            visible: !menuTransition.dropdown
            x: 0; y: 0
            width: parent.width
            height: parent.border.width
            color: parent.color
            z: 100
        }

        MouseArea { anchors.fill: parent; enabled: picker.opened; acceptedButtons: Qt.AllButtons }

        Keys.onPressed: function(event) {
            if (!picker.opened || !bodyLoader.item) return;
            if (event.key === Qt.Key_Escape) {
                picker.close();
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                picker.applySelection();
                event.accepted = true;
            } else if (event.key === Qt.Key_Left) {
                picker.page === 0 ? picker.moveTheme(-1) : picker.moveWallpaper(-1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Right) {
                picker.page === 0 ? picker.moveTheme(1) : picker.moveWallpaper(1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Down && picker.page === 0) {
                picker.enterWallpapers();
                event.accepted = true;
            } else if (event.key === Qt.Key_Up && picker.page === 1) {
                picker.leaveWallpapers();
                event.accepted = true;
            } else if (event.key === Qt.Key_Tab) {
                picker.page === 0 ? picker.enterWallpapers() : picker.leaveWallpapers();
                event.accepted = true;
            }
        }

        MenuBodyLoader {
            id: bodyLoader
            engaged: menuTransition.active || menuTransition.pendingOpen || picker.pendingApply
            width: menuTransition.expandedWidth - 40
            height: menuTransition.expandedHeight - 32
            anchors.horizontalCenter: parent.horizontalCenter
            y: 16 * Math.min(1, bodyStretch.unfold)
            clip: true
            enabled: picker.opened
            visible: picker.opened || picker.closing
            transform: NotchContentStretch {
                id: bodyStretch
                transition: menuTransition
                canvasWidth: menuTransition.expandedWidth - 40
                horizontalInset: 40
            }

            sourceComponent: Item {
                id: bodyItem
                anchors.fill: parent
                property alias searchField: themeSearchField
                property alias themeRail: themeList
                property alias wallpaperRail: wallpaperList

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        spacing: 12
                        Rectangle {
                            Layout.preferredWidth: 38
                            Layout.preferredHeight: 38
                            radius: 13
                            color: Qt.rgba(picker.selectionAccent.r, picker.selectionAccent.g, picker.selectionAccent.b, 0.13)
                            Text {
                                anchors.centerIn: parent
                                text: "palette"
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 23
                                color: picker.selectionAccent
                            }
                        }
                        Column {
                            Layout.fillWidth: true
                            spacing: 3
                            Text { text: "Appearance"; color: ThemeApi.Theme.textBright; font.family: "Inter"; font.pixelSize: 18; font.weight: Font.DemiBold }
                            Text { text: "Themes & wallpapers"; color: ThemeApi.Theme.muted; font.family: "Inter"; font.pixelSize: 10 }
                        }
                        Row {
                            visible: bodyItem.width > 560
                            spacing: 6
                            Rectangle { width: 5; height: 5; radius: 3; color: ThemeApi.Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "Current: " + ThemeApi.Theme.activeTheme.name; color: ThemeApi.Theme.muted; font.family: "Inter"; font.pixelSize: 10 }
                        }
                        PickerButton { implicitWidth: 34; symbol: "close"; ToolTip.text: "Close · Esc"; onClicked: picker.close() }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        spacing: 16
                        Rectangle {
                            id: pageTabs
                            Layout.preferredWidth: Math.min(248, bodyItem.width * 0.48)
                            Layout.preferredHeight: 36
                            radius: 12
                            color: ThemeApi.Theme.surface
                            Rectangle {
                                x: 3 + picker.page * (pageTabs.width - 6) / 2
                                y: 3
                                width: (pageTabs.width - 6) / 2
                                height: 30
                                radius: 9
                                color: Qt.rgba(picker.selectionAccent.r, picker.selectionAccent.g, picker.selectionAccent.b, 0.15)
                                border.width: 1
                                border.color: Qt.rgba(picker.selectionAccent.r, picker.selectionAccent.g, picker.selectionAccent.b, 0.2)
                                Behavior on x {
                                    enabled: picker.opened && picker.morphProgress > 0.999
                                    NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 0.55 }
                                }
                            }
                            Row {
                                x: 3
                                y: 3
                                Repeater {
                                    model: ["Themes", "Wallpapers"]
                                    delegate: Button {
                                        id: tabButton
                                        required property string modelData
                                        required property int index
                                        width: (pageTabs.width - 6) / 2
                                        height: 30
                                        focusPolicy: Qt.NoFocus
                                        Accessible.name: modelData
                                        contentItem: Text {
                                            text: tabButton.modelData
                                            color: picker.page === tabButton.index ? picker.selectionAccent : ThemeApi.Theme.muted
                                            font.family: "Inter"
                                            font.pixelSize: 11
                                            font.weight: picker.page === tabButton.index ? Font.DemiBold : Font.Medium
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        background: Rectangle { radius: 9; color: tabButton.hovered ? Qt.rgba(1, 1, 1, 0.035) : "transparent" }
                                        onClicked: index === 0 ? picker.leaveWallpapers() : picker.enterWallpapers()
                                    }
                                }
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 36
                            TextField {
                                id: themeSearchField
                                anchors.fill: parent
                                visible: picker.page === 0
                                enabled: picker.opened && picker.page === 0
                                focus: picker.opened && picker.page === 0
                                color: ThemeApi.Theme.textBright
                                placeholderText: "Find a theme…"
                                placeholderTextColor: ThemeApi.Theme.muted
                                selectionColor: ThemeApi.Theme.accent
                                selectedTextColor: ThemeApi.Theme.onAccent
                                font.family: "Inter"
                                font.pixelSize: 12
                                leftPadding: 35
                                rightPadding: 35
                                topPadding: 0
                                bottomPadding: 0
                                verticalAlignment: TextInput.AlignVCenter
                                maximumLength: 128
                                selectByMouse: true
                                clip: true
                                background: Rectangle {
                                    radius: 12
                                    color: ThemeApi.Theme.surface
                                    border.width: 1
                                    border.color: themeSearchField.activeFocus
                                        ? Qt.rgba(picker.selectionAccent.r, picker.selectionAccent.g, picker.selectionAccent.b, 0.35)
                                        : "transparent"
                                    Behavior on border.color { ColorAnimation { duration: 140 } }
                                }
                                Text { x: 11; anchors.verticalCenter: parent.verticalCenter; text: "search"; color: ThemeApi.Theme.muted; font.family: "Material Symbols Rounded"; font.pixelSize: 18 }
                                PickerButton {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 3
                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    symbol: "close"
                                    visible: themeSearchField.text.length > 0
                                    ToolTip.text: "Clear search"
                                    onClicked: { themeSearchField.clear(); picker.focusPage(); }
                                }
                                onTextChanged: {
                                    picker.pendingApply = false;
                                    const list = picker.filteredThemes();
                                    if (list.length > 0 && !list.some(item => item.id === picker.selectedThemeId))
                                        picker.chooseTheme(list[0].id);
                                }
                                Keys.onPressed: function(event) {
                                    if (event.key === Qt.Key_Left) { picker.moveTheme(-1); event.accepted = true; }
                                    else if (event.key === Qt.Key_Right) { picker.moveTheme(1); event.accepted = true; }
                                    else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) { picker.enterWallpapers(); event.accepted = true; }
                                    else if (event.key === Qt.Key_Escape) { picker.close(); event.accepted = true; }
                                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { picker.applySelection(); event.accepted = true; }
                                }
                            }
                            RowLayout {
                                anchors.fill: parent
                                visible: picker.page === 1
                                spacing: 8
                                Text { text: "folder_open"; color: ThemeApi.Theme.muted; font.family: "Material Symbols Rounded"; font.pixelSize: 18 }
                                Text { Layout.fillWidth: true; text: picker.selectedTheme.name + " collection"; color: ThemeApi.Theme.muted; font.family: "Inter"; font.pixelSize: 11; elide: Text.ElideRight }
                                Text { text: picker.wallpaperModelReady ? picker.wallpaperCount + (picker.wallpaperCount === 1 ? " image" : " images") : "Loading…"; color: ThemeApi.Theme.muted; font.family: "Inter"; font.pixelSize: 10 }
                            }
                        }
                    }

                    Item {
                        id: pages
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 110
                        clip: true
                        readonly property real pageStride: height + 18

                        Item {
                            width: parent.width
                            height: parent.height
                            y: -picker.pageSlide * pages.pageStride
                            enabled: picker.opened && picker.page === 0
                            PickerRail {
                                id: themeList
                                anchors.fill: parent
                                tileWidth: 220
                                selectionColor: picker.selectionAccent
                                navigationEnabled: picker.opened && picker.page === 0
                                animateSelection: navigationEnabled && picker.morphProgress > 0.999
                                model: picker.filteredThemes()
                                currentIndex: count > 0 ? Math.max(0, picker.filteredThemeIndex()) : -1
                                onIndexPicked: function(index) {
                                    const list = picker.filteredThemes();
                                    if (index >= 0 && index < list.length) picker.chooseTheme(list[index].id);
                                }
                                onStepRequested: function(direction) { picker.moveTheme(direction); }
                                delegate: PickerThemeCard {
                                    required property var modelData
                                    required property int index
                                    width: themeList.tileWidth
                                    height: 176
                                    y: (themeList.height - height) / 2
                                    scale: Math.min(1, themeList.height / 176)
                                    profile: modelData
                                    selected: picker.selectedThemeId === modelData.id
                                    externalSelection: themeList.selectionReady
                                    applied: ThemeApi.Theme.activeThemeId === modelData.id
                                    animationsEnabled: themeList.animateSelection
                                    onChosen: picker.chooseTheme(modelData.id)
                                    onAccepted: { picker.chooseTheme(modelData.id); picker.applySelection(); }
                                }
                            }
                            Column {
                                anchors.centerIn: parent
                                visible: themeList.count === 0
                                spacing: 7
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "search_off"; color: ThemeApi.Theme.mutedStrong; font.family: "Material Symbols Rounded"; font.pixelSize: 30 }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "No matching themes"; color: ThemeApi.Theme.textBright; font.family: "Inter"; font.pixelSize: 13; font.weight: Font.Medium }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Try a different name or clear your search."; color: ThemeApi.Theme.muted; font.family: "Inter"; font.pixelSize: 11 }
                            }
                        }

                        Item {
                            width: parent.width
                            height: parent.height
                            y: (1 - picker.pageSlide) * pages.pageStride
                            enabled: picker.opened && picker.page === 1
                            PickerRail {
                                id: wallpaperList
                                anchors.fill: parent
                                tileWidth: 264
                                selectionColor: picker.selectionAccent
                                navigationEnabled: picker.opened && picker.page === 1
                                animateSelection: navigationEnabled && picker.morphProgress > 0.999
                                model: picker.wallpaperFiles
                                currentIndex: count > 0 ? picker.selectedWallpaperIndex : -1
                                onIndexPicked: function(index) { picker.chooseWallpaper(index); }
                                onStepRequested: function(direction) { picker.moveWallpaper(direction); }
                                delegate: PickerWallpaperCard {
                                    required property string filePath
                                    required property url fileUrl
                                    required property var fileModified
                                    required property var fileSize
                                    required property int index
                                    width: wallpaperList.tileWidth
                                    height: 176
                                    y: (wallpaperList.height - height) / 2
                                    scale: Math.min(1, wallpaperList.height / 176)
                                    imageUrl: fileUrl
                                    imagePath: filePath
                                    imageRevision: String(fileModified.valueOf()) + ":" + String(fileSize)
                                    selected: index === picker.selectedWallpaperIndex
                                    externalSelection: wallpaperList.selectionReady
                                    applied: filePath === ThemeApi.Theme.activeWallpaper
                                    previewsActive: picker.wallpaperPreviewsActive
                                        && x + width > wallpaperList.contentX
                                        && x < wallpaperList.contentX + wallpaperList.width
                                    animationsEnabled: wallpaperList.animateSelection
                                    accent: picker.selectionAccent
                                    onAccent: picker.selectionOnAccent
                                    onChosen: picker.chooseWallpaper(index)
                                    onAccepted: { picker.chooseWallpaper(index); picker.applySelection(); }
                                }
                            }
                            Column {
                                anchors.centerIn: parent
                                visible: !picker.wallpaperModelReady || picker.wallpaperCount === 0
                                spacing: 7
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: picker.wallpaperModelReady ? "photo_library" : "wallpaper"; color: ThemeApi.Theme.mutedStrong; font.family: "Material Symbols Rounded"; font.pixelSize: 28 }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: picker.wallpaperModelReady ? "This collection is empty" : "Loading your wallpapers…"; color: ThemeApi.Theme.textBright; font.family: "Inter"; font.pixelSize: 13; font.weight: Font.Medium }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Wallpapers/" + picker.selectedTheme.folder; color: ThemeApi.Theme.muted; font.family: "Inter"; font.pixelSize: 11 }
                                PickerButton { anchors.horizontalCenter: parent.horizontalCenter; visible: picker.wallpaperModelReady; text: "Open folder"; symbol: "folder_open"; onClicked: picker.openWallpaperFolder() }
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        Rectangle { x: 0; y: -6; width: parent.width; height: 1; color: ThemeApi.Theme.border; opacity: 0.45 }
                        RowLayout {
                            anchors.fill: parent
                            spacing: 14
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 3
                                Text {
                                    Layout.fillWidth: true
                                    text: picker.page === 0 ? (picker.validThemeSelection ? picker.selectedTheme.name : "No theme selected")
                                        : picker.selectedWallpaperPath.split("/").pop().replace(/\.[^.]+$/, "").replace(/_/g, " ") || "Choose a wallpaper"
                                    color: ThemeApi.Theme.textBright
                                    font.family: "Inter"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideMiddle
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: picker.page === 0 ? (picker.validThemeSelection ? picker.selectedTheme.flavor + " · Random matching wallpaper" : "Clear your search to see all themes")
                                        : picker.selectedTheme.name + " · " + (picker.wallpaperCount ? picker.selectedWallpaperIndex + 1 : 0) + " / " + picker.wallpaperCount
                                    color: ThemeApi.Theme.muted
                                    font.family: "Inter"
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                }
                            }
                            Text {
                                visible: bodyItem.width > 680
                                text: picker.page === 0 ? "← → Select    ↓ Wallpapers" : "← → Select    ↑ Themes"
                                color: ThemeApi.Theme.muted
                                font.family: "Inter"
                                font.pixelSize: 10
                            }
                            PickerButton {
                                Layout.preferredWidth: 106
                                Layout.preferredHeight: 34
                                text: picker.pendingApply ? "Applying…" : "Apply"
                                symbol: "keyboard_return"
                                emphasized: true
                                tint: picker.selectionAccent
                                onTint: picker.selectionOnAccent
                                enabled: picker.canApplySelection
                                ToolTip.text: "Apply selection · Enter"
                                onClicked: picker.applySelection()
                            }
                        }
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
            clockValue: picker.clockValue
            batteryLevel: picker.batteryLevel
            batteryCharging: picker.batteryCharging
            visible: !menuTransition.dropdown && ((picker.closing && !menuTransition.wideReturn) || menuTransition.snapshot === null)
            transform: NotchContentStretch {
                transition: menuTransition
                canvasWidth: 236
                compact: true
            }
        }
    }
}
