pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell
import "../Theme" as ThemeApi

SCard {
    id: card
    objectName: "profileSettings"
    property var preferences: null
    property bool active: true
    property bool completed: false
    readonly property var current: preferences && preferences.current ? preferences.current : ({ sourcePath: "", fileUrl: "", hasImage: false, mode: "auto" })
    readonly property bool busy: preferences ? preferences.busy : false
    readonly property string home: Quickshell.env("HOME")
    readonly property string initial: (Quickshell.env("USER") || "U").slice(0, 1).toUpperCase()
    title: "Profile picture"
    iconName: "account_circle"

    function localFile(path) {
        return path ? "file://" + String(path).split("/").map(encodeURIComponent).join("/") : "";
    }
    function choosePicture() {
        if (active && !busy && preferences) picker.open();
    }
    onActiveChanged: {
        if (!completed) return;
        if (!active && picker) picker.close();
        else if (active && preferences) preferences.refresh();
    }
    onPreferencesChanged: if (completed && active && preferences) preferences.refresh()
    onBusyChanged: if (completed && picker && busy) picker.close()
    Component.onCompleted: {
        completed = true;
        if (active && preferences) preferences.refresh();
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 16
        Rectangle {
            id: avatar
            Layout.preferredWidth: 76
            Layout.preferredHeight: 76
            radius: width / 2
            color: ThemeApi.Theme.accentSoft
            readonly property bool showingImage: card.current.hasImage && photo.status === Image.Ready && GraphicsInfo.api !== GraphicsInfo.Software
            Accessible.role: Accessible.Graphic
            Accessible.name: showingImage ? "Current profile picture" : "Profile initial " + card.initial
            SLabel {
                anchors.centerIn: parent
                visible: !avatar.showingImage
                text: card.initial
                font.pixelSize: 29
                font.weight: Font.DemiBold
                color: ThemeApi.Theme.accent
            }
            Image {
                id: photo
                objectName: "profileAvatarImage"
                anchors.fill: parent
                source: card.current.hasImage ? card.current.fileUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                autoTransform: true
                sourceSize.width: 128
                sourceSize.height: 128
                visible: false
            }
            Rectangle {
                id: avatarMask
                anchors.fill: parent
                radius: width / 2
                layer.enabled: true
                visible: false
            }
            MultiEffect {
                anchors.fill: parent
                visible: avatar.showingImage
                source: photo
                maskEnabled: true
                maskSource: avatarMask
                autoPaddingEnabled: false
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 9
            SLabel {
                Layout.fillWidth: true
                text: card.busy ? (card.preferences.loading ? "Reading profile picture…" : "Updating profile picture…") : "Used on your lock screen and sign-in screen"
                font.pixelSize: 12
                color: ThemeApi.Theme.muted
                wrapMode: Text.WordWrap
            }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                SButton {
                    objectName: "chooseProfilePicture"
                    text: "Choose picture"
                    iconName: "add_photo_alternate"
                    accent: true
                    enabled: card.active && !card.busy && card.preferences !== null
                    onClicked: card.choosePicture()
                }
                SButton {
                    objectName: "removeProfilePicture"
                    text: "Remove photo"
                    iconName: "person"
                    enabled: card.active && !card.busy && card.preferences !== null && (card.current.hasImage || card.current.mode === "selected")
                    onClicked: if (card.preferences) card.preferences.removePicture()
                }
            }
        }
    }
    SNotice {
        objectName: "profileError"
        text: card.preferences ? card.preferences.error : ""
        warning: true
    }
    SNotice {
        objectName: "profileWarnings"
        text: card.preferences && Array.isArray(card.preferences.warnings) ? card.preferences.warnings.join("\n") : ""
        warning: true
    }

    // The settings window owns exclusive keyboard focus, so use an embedded chooser.
    property Popup picker: Popup {
        id: filePicker
        objectName: "profileFilePicker"
        parent: Overlay.overlay
        property string folderPath: card.home + "/Pictures"
        property string selectedPath: ""
        property bool initialLookup: false
        property bool hasOpened: false
        width: Math.min(700, parent ? parent.width - 48 : 650)
        height: Math.min(560, parent ? parent.height - 48 : 500)
        x: parent ? Math.round((parent.width - width) / 2) : 0
        y: parent ? Math.round((parent.height - height) / 2) : 0
        modal: true
        focus: true
        padding: 20
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: {
            selectedPath = "";
            location.text = folderPath;
            fileList.currentIndex = -1;
            if (!hasOpened) {
                // Inspect Pictures first: an absent Profile Pictures folder is ordinary.
                initialLookup = true;
                hasOpened = true;
            }
            location.forceActiveFocus();
        }
        onClosed: initialLookup = false
        function resolveInitialFolder() {
            if (!initialLookup || !opened || initialFolders.status !== FolderListModel.Ready) return;
            let target = card.home + "/Pictures";
            for (let i = 0; i < initialFolders.count; ++i) {
                if (initialFolders.get(i, "fileName") === "Profile Pictures") {
                    target = String(initialFolders.get(i, "filePath"));
                    break;
                }
            }
            initialLookup = false;
            navigate(target);
        }
        function navigate(path) {
            let next = String(path).trim();
            if (next === "~") next = card.home;
            else if (next.startsWith("~/")) next = card.home + next.slice(1);
            if (!next.startsWith("/")) return;
            initialLookup = false;
            folderPath = next.replace(/\/+$/, "") || "/";
            location.text = folderPath;
            selectedPath = "";
            fileList.currentIndex = -1;
        }
        function choose(path) {
            if (!card.active || card.busy || !card.preferences || !path) return;
            close();
            card.preferences.setPicture(path);
        }
        function openLocation() {
            let path = location.text.trim();
            if (path.startsWith("~/")) path = card.home + path.slice(1);
            if (/\.(png|jpe?g|webp)$/i.test(path)) choose(path);
            else navigate(path);
        }
        function openIndex(index) {
            if (index < 0 || index >= files.count) return;
            const path = String(files.get(index, "filePath"));
            if (files.get(index, "fileIsDir")) navigate(path);
            else choose(path);
        }
        property FolderListModel initialFolders: FolderListModel {
            id: initialFolders
            folder: filePicker.initialLookup ? card.localFile(card.home + "/Pictures") : ""
            showDirs: true
            showFiles: false
            showDotAndDotDot: false
            showOnlyReadable: true
            onStatusChanged: if (status === FolderListModel.Ready) Qt.callLater(filePicker.resolveInitialFolder)
        }
        background: Rectangle { color: ThemeApi.Theme.bg0; radius: 22; border.width: 1; border.color: ThemeApi.Theme.border }
        contentItem: ColumnLayout {
            spacing: 14
            RowLayout {
                Layout.fillWidth: true
                SLabel { Layout.fillWidth: true; text: "Choose a profile picture"; font.pixelSize: 20; font.weight: Font.DemiBold; color: ThemeApi.Theme.textBright }
                SButton { iconName: "close"; Accessible.name: "Close picture chooser"; onClicked: filePicker.close() }
            }
            SLabel { Layout.fillWidth: true; text: "Choose a PNG, JPG, JPEG or WebP picture, or paste its full path."; font.pixelSize: 11; color: ThemeApi.Theme.muted; wrapMode: Text.WordWrap }
            RowLayout {
                Layout.fillWidth: true
                spacing: 7
                SButton { iconName: "arrow_upward"; Accessible.name: "Parent folder"; enabled: filePicker.folderPath !== "/"; onClicked: filePicker.navigate(filePicker.folderPath.slice(0, filePicker.folderPath.lastIndexOf("/")) || "/") }
                TextField {
                    id: location
                    objectName: "profileFileLocation"
                    Layout.fillWidth: true
                    implicitHeight: 38
                    font.family: "Inter"
                    font.pixelSize: 11
                    color: ThemeApi.Theme.textBright
                    selectionColor: ThemeApi.Theme.accent
                    selectedTextColor: ThemeApi.Theme.onAccent
                    placeholderText: "/path/to/picture.png"
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
                SButton { text: "Pictures"; iconName: "photo_library"; onClicked: filePicker.navigate(card.home + "/Pictures") }
                SButton { text: "Home"; iconName: "home"; onClicked: filePicker.navigate(card.home) }
                Item { Layout.fillWidth: true }
                SLabel { text: "Pictures only"; color: ThemeApi.Theme.muted; font.pixelSize: 10 }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 13
                color: ThemeApi.Theme.surface
                clip: true
                ListView {
                    id: fileList
                    objectName: "profileFiles"
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    spacing: 3
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { }
                    model: FolderListModel {
                        id: files
                        // Closing the chooser also releases its directory watcher.
                        folder: filePicker.visible ? card.localFile(filePicker.folderPath) : ""
                        showDirs: true
                        showDotAndDotDot: false
                        showDirsFirst: true
                        showOnlyReadable: true
                        caseSensitive: false
                        nameFilters: ["*.[pP][nN][gG]", "*.[jJ][pP][gG]", "*.[jJ][pP][eE][gG]", "*.[wW][eE][bB][pP]"]
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
                        leftPadding: 12
                        rightPadding: 12
                        Accessible.name: fileName
                        onClicked: { fileList.currentIndex = index; fileList.forceActiveFocus(); }
                        onDoubleClicked: filePicker.openIndex(index)
                        contentItem: RowLayout {
                            spacing: 11
                            Text { text: fileEntry.fileIsDir ? "folder" : "image"; font.family: "Material Symbols Rounded"; font.pixelSize: 21; color: ThemeApi.Theme.accent }
                            SLabel { Layout.fillWidth: true; text: fileEntry.fileName; elide: Text.ElideMiddle; font.pixelSize: 12; color: ThemeApi.Theme.textBright }
                            Text { visible: fileEntry.fileIsDir; text: "chevron_right"; font.family: "Material Symbols Rounded"; font.pixelSize: 18; color: ThemeApi.Theme.muted }
                        }
                        background: Rectangle { radius: 9; color: fileEntry.highlighted ? ThemeApi.Theme.accentSoft : fileEntry.hovered ? ThemeApi.Theme.surfaceRaised : "transparent" }
                    }
                }
                SLabel { anchors.centerIn: parent; width: parent.width - 36; horizontalAlignment: Text.AlignHCenter; visible: files.count === 0; text: files.status === FolderListModel.Loading ? "Reading folder…" : "No pictures in this folder.\nChoose another folder or paste a file path."; font.pixelSize: 12; color: ThemeApi.Theme.muted; wrapMode: Text.WordWrap }
            }
            RowLayout {
                Layout.fillWidth: true
                SLabel { Layout.fillWidth: true; text: filePicker.selectedPath ? filePicker.selectedPath.slice(filePicker.selectedPath.lastIndexOf("/") + 1) : ""; elide: Text.ElideMiddle; font.pixelSize: 11; color: ThemeApi.Theme.muted }
                SButton { text: "Cancel"; onClicked: filePicker.close() }
                SButton { objectName: "profileFileOpen"; text: "Choose picture"; accent: true; enabled: filePicker.selectedPath.length > 0 && !card.busy; onClicked: filePicker.choose(filePicker.selectedPath) }
            }
        }
    }
}
