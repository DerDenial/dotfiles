import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import "../Theme" as ThemeApi
import "../Wallpapers" as Wallpapers

SPage {
    id: page
    property string pendingThemeId: ""
    property bool pendingThemeApply: false
    property int wallpaperPage: 0
    property int wallpaperRevision: 0
    onPageCountChanged: wallpaperPage = Math.min(wallpaperPage, pageCount - 1)
    readonly property int columns: width >= 690 ? 3 : 2
    readonly property int pageSize: columns * 3
    readonly property int pageCount: Math.max(1, Math.ceil(wallpapers.count / pageSize))
    readonly property var candidateTheme: ThemeApi.Theme.themes.find(theme => theme.id === pendingThemeId) || ThemeApi.Theme.activeTheme
    readonly property var previews: {
        const revision = wallpaperRevision;
        const entries = [];
        const count = wallpapers.count;
        for (let i = wallpaperPage * pageSize; i < Math.min(count, (wallpaperPage + 1) * pageSize); ++i)
            entries.push({ name: wallpapers.get(i, "fileName"), path: wallpapers.get(i, "filePath"), url: wallpapers.get(i, "fileUrl"),
                revision: String(wallpapers.get(i, "fileModified").valueOf()) + ":" + String(wallpapers.get(i, "fileSize")) });
        return entries;
    }
    function chooseTheme(id) {
        if (id === ThemeApi.Theme.activeThemeId) { pendingThemeApply = false; pendingThemeId = id; return; }
        pendingThemeId = id;
        pendingThemeApply = true;
        Qt.callLater(applyPendingTheme);
    }
    function applyPendingTheme() {
        if (!pendingThemeApply || candidates.status !== FolderListModel.Ready) return;
        const prefix = ThemeApi.Theme.wallpaperRoot + "/" + candidateTheme.folder + "/";
        if (candidates.count > 0 && !String(candidates.get(0, "filePath")).startsWith(prefix)) return;
        const previous = ThemeApi.Theme.rememberedWallpaper(pendingThemeId);
        const files = [];
        for (let i = 0; i < candidates.count; ++i) {
            const file = String(candidates.get(i, "filePath"));
            if (file.startsWith(prefix) && (candidates.count === 1 || file !== previous)) files.push(file);
        }
        const wallpaper = files.length ? files[Math.floor(Math.random() * files.length)] : "";
        pendingThemeApply = false;
        ThemeApi.Theme.selectTheme(pendingThemeId, wallpaper);
        wallpaperPage = 0;
        if (controller) controller.toast(candidateTheme.name + " applied");
    }
    property FolderListModel candidates: FolderListModel {
        folder: "file://" + ThemeApi.Theme.wallpaperRoot + "/" + page.candidateTheme.folder
        showDirs: false
        caseSensitive: false
        nameFilters: ["*.[pP][nN][gG]", "*.[jJ][pP][gG]", "*.[jJ][pP][eE][gG]", "*.[wW][eE][bB][pP]", "*.[bB][mM][pP]"]
        onStatusChanged: if (status === FolderListModel.Ready) Qt.callLater(page.applyPendingTheme)
        onCountChanged: Qt.callLater(page.applyPendingTheme)
    }
    property FolderListModel wallpapers: FolderListModel {
        folder: "file://" + ThemeApi.Theme.wallpaperFolder
        showDirs: false
        sortField: FolderListModel.Name
        caseSensitive: false
        nameFilters: ["*.[pP][nN][gG]", "*.[jJ][pP][gG]", "*.[jJ][pP][eE][gG]", "*.[wW][eE][bB][pP]", "*.[bB][mM][pP]"]
        onCountChanged: page.wallpaperPage = Math.min(page.wallpaperPage, page.pageCount - 1)
        onStatusChanged: if (status === FolderListModel.Ready) page.wallpaperRevision++
        onFolderChanged: page.wallpaperRevision++
        onDataChanged: page.wallpaperRevision++
    }
    SNotice { text: (ThemeApi.Theme.materialProcess.running || ThemeApi.Theme.materialPending) ? "Building your Material palette from this wallpaper…" : "" }
    ProfileSettings {
        preferences: page.controller ? page.controller.profilePreferences : null
        active: page.active
    }
    SCard {
        title: "Theme"
        subtitle: "Colors follow your selection across the shell and supported applications. A matching wallpaper is picked at random."
        iconName: "palette"
        GridLayout {
            Layout.fillWidth: true
            columns: page.columns
            rowSpacing: 12
            columnSpacing: 12
            Repeater {
                model: ThemeApi.Theme.themes
                delegate: Rectangle {
                    id: themeTile
                    required property var modelData
                    readonly property bool selected: modelData.id === ThemeApi.Theme.activeThemeId
                    readonly property var palette: modelData.colors
                    Layout.fillWidth: true
                    Layout.preferredHeight: 112
                    Layout.preferredWidth: 200
                    radius: 16
                    color: palette.bg0
                    border.width: selected ? 2 : 1
                    border.color: selected ? palette.accent : Qt.rgba(ThemeApi.Theme.border.r, ThemeApi.Theme.border.g, ThemeApi.Theme.border.b, 0.5)
                    scale: tileMouse.pressed ? 0.97 : 1
                    Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }
                    Column {
                        anchors.centerIn: parent
                        spacing: 10
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 7
                            Repeater {
                                model: [themeTile.palette.red, themeTile.palette.green, themeTile.palette.yellow, themeTile.palette.blue, themeTile.palette.purple, themeTile.palette.accent]
                                delegate: Rectangle { required property color modelData; width: 13; height: 13; radius: 7; color: modelData }
                            }
                        }
                        SLabel { anchors.horizontalCenter: parent.horizontalCenter; text: themeTile.modelData.name; color: themeTile.palette.textBright; font.pixelSize: 12; font.weight: Font.Medium }
                        SLabel { anchors.horizontalCenter: parent.horizontalCenter; text: themeTile.modelData.id === "material" ? "Colors from your wallpaper" : themeTile.modelData.flavor; color: themeTile.palette.muted; font.pixelSize: 9 }
                    }
                    Text { x: parent.width - 25; y: 9; visible: themeTile.selected; text: "check_circle"; color: themeTile.palette.accent; font.family: "Material Symbols Rounded"; font.pixelSize: 17 }
                    MouseArea { id: tileMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.chooseTheme(themeTile.modelData.id) }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.name
                    activeFocusOnTab: true
                    Keys.onReturnPressed: page.chooseTheme(modelData.id)
                }
            }
        }
    }
    CursorSettings {
        preferences: page.controller ? page.controller.cursorPreferences : null
    }
    WallpaperMotionSettings { }
    SCard {
        title: "Wallpaper"
        subtitle: ThemeApi.Theme.activeTheme.name + " collection · " + wallpapers.count + " wallpapers"
        iconName: "wallpaper"
        RowLayout {
            Layout.fillWidth: true
            SButton { text: "Surprise me"; iconName: "shuffle"; accent: true; enabled: wallpapers.count > 0; onClicked: ThemeApi.Theme.randomWallpaper() }
            Item { Layout.fillWidth: true }
            SButton { text: "Open folder"; iconName: "folder_open"; onClicked: Quickshell.execDetached(["nautilus", "--new-window", ThemeApi.Theme.wallpaperFolder]) }
        }
        SNotice { text: wallpapers.count === 0 ? "This collection is empty. Add PNG, JPG or WebP images to its wallpaper folder." : "" }
        GridLayout {
            Layout.fillWidth: true
            columns: page.columns
            rowSpacing: 12
            columnSpacing: 12
            Repeater {
                model: page.previews
                delegate: Item {
                    id: preview
                    required property var modelData
                    readonly property bool selected: modelData.path === ThemeApi.Theme.activeWallpaper
                    Layout.fillWidth: true
                    Layout.preferredWidth: 200
                    Layout.preferredHeight: 140
                    Rectangle {
                        anchors.fill: parent
                        radius: 15
                        color: ThemeApi.Theme.surfaceAlt
                        Wallpapers.Preview {
                            anchors.fill: parent
                            anchors.margins: 4
                            anchors.bottomMargin: 29
                            originalSource: preview.modelData.url
                            filePath: preview.modelData.path
                            fileRevision: preview.modelData.revision
                            previewsActive: page.active
                        }
                        SLabel { x: 10; y: parent.height - 23; width: parent.width - 35; text: preview.modelData.name; font.pixelSize: 10; elide: Text.ElideMiddle }
                        Text { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 9; visible: preview.selected; text: "check_circle"; color: ThemeApi.Theme.accent; font.family: "Material Symbols Rounded"; font.pixelSize: 16 }
                        border.width: preview.selected ? 2 : 1
                        border.color: preview.selected ? ThemeApi.Theme.accent : ThemeApi.Theme.border
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ThemeApi.Theme.selectWallpaper(preview.modelData.path) }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.name
                    activeFocusOnTab: true
                    Keys.onReturnPressed: ThemeApi.Theme.selectWallpaper(modelData.path)
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            visible: page.pageCount > 1
            SButton { iconName: "chevron_left"; Accessible.name: "Previous wallpapers"; enabled: page.wallpaperPage > 0; onClicked: page.wallpaperPage-- }
            Item { Layout.fillWidth: true }
            SLabel { text: (page.wallpaperPage + 1) + " / " + page.pageCount; font.pixelSize: 11; color: ThemeApi.Theme.muted }
            Item { Layout.fillWidth: true }
            SButton { iconName: "chevron_right"; Accessible.name: "Next wallpapers"; enabled: page.wallpaperPage + 1 < page.pageCount; onClicked: page.wallpaperPage++ }
        }
    }
    SNotice { text: ThemeApi.Theme.activeThemeId === "material" ? "Material takes its accent from your wallpaper. Picking another wallpaper also updates the system palette." : "" }
}
