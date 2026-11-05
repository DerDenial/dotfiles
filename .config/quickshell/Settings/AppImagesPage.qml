pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import "../Theme" as ThemeApi

SPage {
    id: page
    objectName: "appImagesPage"
    property var preferences: controller ? controller.appImagePreferences : null
    readonly property var info: preferences ? preferences.info : ({ apps: [], warnings: [] })
    readonly property var apps: Array.isArray(info.apps) ? info.apps : []
    readonly property var candidate: preferences ? preferences.candidate : null
    readonly property bool busy: preferences ? preferences.busy : false
    readonly property bool integrating: candidate !== null && apps.some(entry => entry.id === candidate.targetId && !entry.managed)
    property string fileTarget: ""

    function localFile(path) {
        if (!path) return "";
        if (String(path).startsWith("file:")) return path;
        return "file://" + String(path).split("/").map(encodeURIComponent).join("/");
    }
    function bytes(value) {
        if (!Number.isFinite(Number(value)) || value <= 0) return "";
        return (value / 1048576).toFixed(1) + " MiB";
    }
    function chooseFile(id) {
        if (busy) return;
        fileTarget = id || "";
        picker.open();
    }
    function chooseReplacement(entry) { chooseFile(entry.id); }
    function restore(entry) {
        if (busy || !preferences || !entry.canRollback || !controller) return;
        const appId = entry.id;
        controller.confirm("Restore " + entry.name + "?", "Replace the current AppImage and launcher with the previous version saved by this manager.", function() { if (page.preferences) page.preferences.restore(appId); });
    }
    onActiveChanged: {
        if (!active && picker) picker.close();
        else if (active && preferences) preferences.refresh();
    }
    Component.onCompleted: if (active && preferences) preferences.refresh()
    property Popup picker: Popup {
        id: filePicker
        objectName: "appImageFilePicker"
        parent: Overlay.overlay
        property string folderPath: Quickshell.env("HOME") + "/Downloads"
        property string selectedPath: ""
        width: Math.min(700, parent ? parent.width - 48 : 650)
        height: Math.min(560, parent ? parent.height - 48 : 500)
        x: parent ? Math.round((parent.width - width) / 2) : 0
        y: parent ? Math.round((parent.height - height) / 2) : 0
        modal: true
        focus: true
        padding: 20
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: { selectedPath = ""; location.text = folderPath; fileList.currentIndex = -1; location.forceActiveFocus(); }
        function navigate(path) {
            let next = String(path).trim();
            if (next.startsWith("~/")) next = Quickshell.env("HOME") + next.slice(1);
            if (!next.startsWith("/")) return;
            folderPath = next.replace(/\/$/, "") || "/";
            location.text = folderPath;
            selectedPath = "";
            fileList.currentIndex = -1;
        }
        function choose(path) {
            if (!path || !page.preferences) return;
            close();
            page.preferences.inspect(path, page.fileTarget);
        }
        function openLocation() {
            let path = location.text.trim();
            if (path.startsWith("~/")) path = Quickshell.env("HOME") + path.slice(1);
            if (/\.appimage$/i.test(path)) choose(path);
            else navigate(path);
        }
        function openIndex(index) {
            if (index < 0 || index >= files.count) return;
            const path = String(files.get(index, "filePath"));
            if (files.get(index, "fileIsDir")) navigate(path);
            else choose(path);
        }
        background: Rectangle { color: ThemeApi.Theme.bg0; radius: 22; border.width: 1; border.color: ThemeApi.Theme.border }
        contentItem: ColumnLayout {
            spacing: 14
            RowLayout {
                Layout.fillWidth: true
                SLabel { Layout.fillWidth: true; text: page.fileTarget ? "Choose replacement" : "Choose an AppImage"; font.pixelSize: 20; font.weight: Font.DemiBold; color: ThemeApi.Theme.textBright }
                SButton { iconName: "close"; Accessible.name: "Close file chooser"; onClicked: filePicker.close() }
            }
            SLabel { Layout.fillWidth: true; text: "Select a downloaded .AppImage, or paste its full path."; font.pixelSize: 11; color: ThemeApi.Theme.muted; wrapMode: Text.WordWrap }
            RowLayout {
                Layout.fillWidth: true
                spacing: 7
                SButton {
                    iconName: "arrow_upward"
                    Accessible.name: "Parent folder"
                    enabled: filePicker.folderPath !== "/"
                    onClicked: filePicker.navigate(filePicker.folderPath.slice(0, filePicker.folderPath.lastIndexOf("/")) || "/")
                }
                TextField {
                    id: location
                    objectName: "appImageFileLocation"
                    Layout.fillWidth: true
                    implicitHeight: 38
                    font.family: "Inter"; font.pixelSize: 11
                    color: ThemeApi.Theme.textBright
                    selectionColor: ThemeApi.Theme.accent
                    selectedTextColor: ThemeApi.Theme.onAccent
                    placeholderText: "/path/to/application.AppImage"
                    placeholderTextColor: ThemeApi.Theme.muted
                    selectByMouse: true
                    onAccepted: filePicker.openLocation()
                    background: Rectangle { radius: 11; color: ThemeApi.Theme.surface; border.width: 1; border.color: location.activeFocus ? ThemeApi.Theme.accent : ThemeApi.Theme.border }
                }
                SButton { iconName: "arrow_forward"; Accessible.name: "Open entered path"; onClicked: filePicker.openLocation() }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 7
                SButton { text: "Downloads"; iconName: "download"; onClicked: filePicker.navigate(Quickshell.env("HOME") + "/Downloads") }
                SButton { text: "Home"; iconName: "home"; onClicked: filePicker.navigate(Quickshell.env("HOME")) }
                Item { Layout.fillWidth: true }
                SLabel { text: "AppImages only"; color: ThemeApi.Theme.muted; font.pixelSize: 10 }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 13
                color: ThemeApi.Theme.surface
                clip: true
                ListView {
                    id: fileList
                    objectName: "appImageFiles"
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    spacing: 3
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { }
                    model: FolderListModel {
                        id: files
                        folder: page.localFile(filePicker.folderPath)
                        showDirs: true
                        showDotAndDotDot: false
                        showDirsFirst: true
                        showOnlyReadable: true
                        caseSensitive: false
                        nameFilters: ["*.[aA][pP][pP][iI][mM][aA][gG][eE]"]
                        sortField: FolderListModel.Name
                    }
                    Keys.onReturnPressed: filePicker.openIndex(currentIndex)
                    Keys.onEnterPressed: filePicker.openIndex(currentIndex)
                    onCurrentIndexChanged: {
                        if (currentIndex >= 0 && currentIndex < files.count)
                            filePicker.selectedPath = files.get(currentIndex, "fileIsDir") ? "" : String(files.get(currentIndex, "filePath"));
                    }
                    delegate: ItemDelegate {
                        id: fileEntry
                        required property int index
                        required property string fileName
                        required property string filePath
                        required property bool fileIsDir
                        width: fileList.width
                        height: 44
                        highlighted: ListView.isCurrentItem
                        leftPadding: 12; rightPadding: 12
                        Accessible.name: fileName
                        onClicked: { fileList.currentIndex = index; fileList.forceActiveFocus(); }
                        onDoubleClicked: filePicker.openIndex(index)
                        contentItem: RowLayout {
                            spacing: 11
                            Text { text: fileEntry.fileIsDir ? "folder" : "deployed_code"; font.family: "Material Symbols Rounded"; font.pixelSize: 21; color: ThemeApi.Theme.accent }
                            SLabel { Layout.fillWidth: true; text: fileEntry.fileName; elide: Text.ElideMiddle; font.pixelSize: 12; color: ThemeApi.Theme.textBright }
                            Text { visible: fileEntry.fileIsDir; text: "chevron_right"; font.family: "Material Symbols Rounded"; font.pixelSize: 18; color: ThemeApi.Theme.muted }
                        }
                        background: Rectangle { radius: 9; color: fileEntry.highlighted ? ThemeApi.Theme.accentSoft : fileEntry.hovered ? ThemeApi.Theme.surfaceRaised : "transparent" }
                    }
                }
                SLabel { anchors.centerIn: parent; width: parent.width - 36; horizontalAlignment: Text.AlignHCenter; visible: files.count === 0; text: files.status === FolderListModel.Loading ? "Reading folder…" : "No AppImages in this folder.\nChoose another folder or paste a file path."; font.pixelSize: 12; color: ThemeApi.Theme.muted; wrapMode: Text.WordWrap }
            }
            RowLayout {
                Layout.fillWidth: true
                SLabel { Layout.fillWidth: true; text: filePicker.selectedPath ? filePicker.selectedPath.slice(filePicker.selectedPath.lastIndexOf("/") + 1) : ""; elide: Text.ElideMiddle; font.pixelSize: 11; color: ThemeApi.Theme.muted }
                SButton { text: "Cancel"; onClicked: filePicker.close() }
                SButton { objectName: "appImageFileOpen"; text: "Choose file"; accent: true; enabled: filePicker.selectedPath.length > 0; onClicked: filePicker.choose(filePicker.selectedPath) }
            }
        }
    }

    SNotice {
        objectName: "appImageError"
        text: page.preferences ? page.preferences.error : ""
        warning: true
    }
    SNotice {
        objectName: "appImageWarnings"
        text: Array.isArray(page.info.warnings) ? page.info.warnings.join("\n") : ""
        warning: true
    }
    SCard {
        objectName: "appImageLibraryHeader"
        title: "Your AppImages"
        subtitle: "Install local files and keep their launcher entries up to date."
        iconName: "deployed_code"
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            SLabel {
                Layout.fillWidth: true
                text: page.preferences && page.preferences.loading ? "Finding your applications…" : page.apps.length + (page.apps.length === 1 ? " application" : " applications") + " in Programs"
                color: ThemeApi.Theme.muted
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
            SButton {
                objectName: "refreshAppImages"
                iconName: "refresh"
                enabled: !page.busy
                Accessible.name: "Refresh AppImages"
                ToolTip.visible: hovered
                ToolTip.text: "Refresh applications"
                onClicked: if (page.preferences) page.preferences.refresh()
            }
            SButton {
                objectName: "installAppImage"
                text: "Install AppImage"
                iconName: "add"
                accent: true
                enabled: !page.busy
                onClicked: page.chooseFile("")
            }
        }
        SLabel {
            Layout.fillWidth: true
            text: "Choose a downloaded .AppImage to add or replace an app. New installs are stored in Programs/AppImages."
            color: ThemeApi.Theme.muted
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
    }
    SCard {
        id: reviewCard
        objectName: "appImageReview"
        visible: page.candidate !== null || (page.preferences && page.preferences.inspecting)
        title: page.preferences && page.preferences.inspecting ? "Checking AppImage…" : page.integrating ? "Review launcher entry" : page.candidate && page.candidate.operation === "update" ? "Review replacement" : "Review installation"
        subtitle: page.preferences && page.preferences.inspecting ? "Reading the file, architecture and launcher details." : "Nothing changes until you confirm below."
        iconName: "fact_check"
        RowLayout {
            Layout.fillWidth: true
            visible: page.candidate !== null
            spacing: 12
            Rectangle {
                Layout.preferredWidth: 54
                Layout.preferredHeight: 54
                radius: 15
                color: ThemeApi.Theme.surfaceAlt
                Image {
                    id: candidateIcon
                    anchors.centerIn: parent
                    width: 34; height: 34
                    source: page.candidate ? page.localFile(page.candidate.icon) : ""
                    sourceSize.width: 68; sourceSize.height: 68
                    asynchronous: true; cache: false
                    fillMode: Image.PreserveAspectFit
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: candidateIcon.status !== Image.Ready
                    text: "deployed_code"
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 27
                    color: ThemeApi.Theme.accent
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                SLabel { Layout.fillWidth: true; text: page.candidate ? page.candidate.name : ""; font.pixelSize: 15; font.weight: Font.DemiBold; color: ThemeApi.Theme.textBright; elide: Text.ElideMiddle }
                SLabel {
                    Layout.fillWidth: true
                    text: page.candidate ? (page.candidate.version || "Version unavailable") + " · " + page.candidate.architecture + (page.bytes(page.candidate.size) ? " · " + page.bytes(page.candidate.size) : "") : ""
                    color: ThemeApi.Theme.muted; font.pixelSize: 11; wrapMode: Text.WordWrap
                }
            }
            Text {
                visible: page.candidate !== null
                text: page.candidate && page.candidate.compatible ? "check_circle" : "error"
                color: page.candidate && page.candidate.compatible ? ThemeApi.Theme.accent : ThemeApi.Theme.red
                font.family: "Material Symbols Rounded"; font.pixelSize: 22
            }
        }
        SNotice {
            objectName: "appImageIncompatible"
            warning: true
            text: page.candidate && !page.candidate.compatible ? page.candidate.errorMessage || "This AppImage is not compatible with this computer." : ""
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: page.candidate !== null
            spacing: 5
            SLabel { text: "INSTALL LOCATION"; color: ThemeApi.Theme.mutedStrong; font.pixelSize: 9; font.letterSpacing: 0.9; font.weight: Font.DemiBold }
            SLabel { objectName: "appImageDestination"; Layout.fillWidth: true; text: page.candidate ? page.candidate.targetPath : ""; font.pixelSize: 11; color: ThemeApi.Theme.muted; wrapMode: Text.WrapAnywhere }
            SLabel { visible: page.candidate && page.candidate.operation === "update" && !page.integrating; Layout.fillWidth: true; text: "The previous version is kept so you can restore it. Reopen the app after replacing it."; font.pixelSize: 11; color: ThemeApi.Theme.muted; wrapMode: Text.WordWrap }
        }
        RowLayout {
            Layout.fillWidth: true
            visible: page.candidate !== null
            Item { Layout.fillWidth: true }
            SButton { objectName: "cancelAppImage"; text: "Cancel"; enabled: !page.busy; onClicked: if (page.preferences) page.preferences.discard() }
            SButton {
                objectName: "applyAppImage"
                text: page.preferences && page.preferences.writing ? "Installing…" : page.integrating ? "Add to launcher" : page.candidate && page.candidate.operation === "update" ? "Replace AppImage" : "Install"
                iconName: page.candidate && page.candidate.operation === "update" ? "upgrade" : "download"
                accent: true
                enabled: page.candidate !== null && page.candidate.compatible === true && !page.busy
                onClicked: if (page.preferences) page.preferences.apply()
            }
        }
    }
    SNotice {
        objectName: "appImageProgress"
        text: page.preferences && page.preferences.writing ? (page.preferences.operation === "restore" ? "Restoring the previous version…" : "Installing AppImage and updating its launcher…") : ""
        iconName: "pending"
    }
    Repeater {
        model: page.apps
        delegate: SCard {
            id: appCard
            required property var modelData
            objectName: "appImage_" + modelData.id
            padding: 16
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Rectangle {
                    Layout.preferredWidth: 48; Layout.preferredHeight: 48
                    radius: 13
                    color: ThemeApi.Theme.surfaceAlt
                    Image {
                        id: appIcon
                        anchors.centerIn: parent
                        width: 30; height: 30
                        source: page.localFile(appCard.modelData.icon)
                        sourceSize.width: 60; sourceSize.height: 60
                        asynchronous: true; cache: false
                        fillMode: Image.PreserveAspectFit
                        visible: status === Image.Ready
                    }
                    Text { anchors.centerIn: parent; visible: appIcon.status !== Image.Ready; text: "deployed_code"; font.family: "Material Symbols Rounded"; font.pixelSize: 24; color: ThemeApi.Theme.accent }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5
                    SLabel { Layout.fillWidth: true; text: appCard.modelData.name; font.pixelSize: 14; font.weight: Font.DemiBold; color: ThemeApi.Theme.textBright; elide: Text.ElideMiddle }
                    SLabel {
                        Layout.fillWidth: true
                        text: (appCard.modelData.version || "Version unavailable") + " · " + appCard.modelData.architecture + (page.bytes(appCard.modelData.size) ? " · " + page.bytes(appCard.modelData.size) : "")
                        font.pixelSize: 11; color: ThemeApi.Theme.muted; wrapMode: Text.WordWrap
                    }
                }
                SButton {
                    objectName: "replaceAppImage_" + appCard.modelData.id
                    text: appCard.modelData.managed ? "Replace" : "Add to launcher"
                    iconName: appCard.modelData.managed ? "upgrade" : "add"
                    enabled: !page.busy
                    onClicked: {
                        if (appCard.modelData.managed) page.chooseReplacement(appCard.modelData);
                        else if (page.preferences) page.preferences.inspect(appCard.modelData.path, appCard.modelData.id);
                    }
                }
            }
            SLabel { Layout.fillWidth: true; text: appCard.modelData.path; color: ThemeApi.Theme.muted; font.pixelSize: 10; elide: Text.ElideMiddle }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: appCard.modelData.managed && appCard.modelData.executable ? "check_circle" : "info"
                    color: appCard.modelData.managed && appCard.modelData.executable ? ThemeApi.Theme.accent : ThemeApi.Theme.muted
                    font.family: "Material Symbols Rounded"; font.pixelSize: 15
                }
                SLabel {
                    Layout.fillWidth: true
                    text: !appCard.modelData.managed ? "Not yet available in the launcher" : !appCard.modelData.executable ? "Not executable · replace to repair" : "Available in the launcher"
                    color: ThemeApi.Theme.muted; font.pixelSize: 10; wrapMode: Text.WordWrap
                }
                SButton {
                    objectName: "restoreAppImage_" + appCard.modelData.id
                    visible: appCard.modelData.canRollback
                    text: "Restore previous"
                    iconName: "history"
                    enabled: !page.busy
                    onClicked: page.restore(appCard.modelData)
                }
            }
        }
    }
    SCard {
        visible: !page.apps.length && !(page.preferences && page.preferences.loading)
        title: "Start with an AppImage"
        subtitle: "Choose a local file above. Its icon and launcher entry will be added automatically when available."
        iconName: "add_box"
    }
}
