import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Theme" as ThemeApi
import "Settings" as Settings

PanelWindow {
    id: app
    property bool opened: false
    property bool canOpen: true
    property bool pendingOpen: false
    signal aboutToOpen()
    property string selectedPage: "overview"
    property bool surfaceMapped: false
    property real reveal: 0
    property real pageStretch: 1
    property string toastText: ""
    property string confirmTitle: ""
    property string confirmMessage: ""
    property var confirmCallback: null
    property bool windowPreferenceWritePending: false
    // Cursor changes outlive page navigation and the lazy visual body.
    property QtObject cursorPreferences: Settings.CursorPreferences {
        onApplied: app.toast(info.warnings.length ? "Cursor saved with a notice" : "Cursor applied")
    }
    property QtObject profilePreferences: Settings.ProfilePreferences {
        onApplied: message => app.toast(message)
    }
    // Installation finishes even when its visual page is closed or unloaded.
    property QtObject appImagePreferences: Settings.AppImagePreferences {
        onApplied: message => app.toast(message)
    }
    readonly property var windowSurface: bodyLoader.item
    readonly property var searchField: bodyLoader.item ? bodyLoader.item.searchField : null
    readonly property var cancelConfirmation: bodyLoader.item ? bodyLoader.item.cancelConfirmation : null
    readonly property string currentPage: searchField && searchField.text.trim() ? "search" : selectedPage
    readonly property var currentEntry: pages.find(entry => entry.id === currentPage) || pages[0]
    readonly property var pages: [
        { id: "overview", title: "Overview", subtitle: "Your workspace at a glance.", icon: "space_dashboard", group: "", keywords: "home start status übersicht" },
        { id: "network", title: "Network", subtitle: "Stay connected, at home and on the go.", icon: "wifi", group: "CONNECTIONS", keywords: "internet wlan wifi wireless ethernet lan vpn tailscale ip dns" },
        { id: "bluetooth", title: "Bluetooth", subtitle: "Your headphones, peripherals and nearby devices.", icon: "bluetooth", group: "", keywords: "pair connect koppeln verbinden headphones kopfhörer mouse maus" },
        { id: "audio", title: "Sound", subtitle: "The right device, the right level, for every app.", icon: "volume_up", group: "DEVICES", keywords: "audio volume lautstärke mic microphone mikrofon mute stumm speaker lautsprecher" },
        { id: "display", title: "Display", subtitle: "A comfortable view of your workspace.", icon: "desktop_windows", group: "", keywords: "monitor bildschirm brightness helligkeit resolution auflösung refresh hz" },
        { id: "appearance", title: "Appearance", subtitle: "Make the whole desktop feel like yours.", icon: "palette", group: "PERSONALIZATION", keywords: "theme material wallpaper hintergrund farbe colors gruvbox catppuccin cursor pointer mauszeiger zeiger size größe profile picture avatar profilbild animation transition wipe" },
        { id: "windows", title: "Windows & layout", subtitle: "Choose how tiled windows open and share your workspace.", icon: "view_quilt", group: "", keywords: "hyprland windows fenster layout tiling kacheln scrolling cards karten dwindle default master monocle" },
        { id: "input", title: "Input & shortcuts", subtitle: "Make the keyboard and pointer work your way.", icon: "keyboard", group: "", keywords: "keyboard tastatur maus touchpad scroll repeat shortcuts hotkeys sensitivity" },
        { id: "notifications", title: "Notifications", subtitle: "Choose when you want to be interrupted.", icon: "notifications", group: "", keywords: "dnd focus benachrichtigungen störung swaync history verlauf" },
        { id: "power", title: "Power & session", subtitle: "Balance battery life, performance and your session.", icon: "battery_charging_full", group: "SYSTEM", keywords: "battery akku energie power performance profile tlp lock sperren sleep suspend shutdown reboot restart" },
        { id: "appimages", title: "AppImages", subtitle: "Keep your portable apps and their launchers in one place.", icon: "deployed_code", group: "", keywords: "appimage applications apps programme install installieren update aktualisieren office pdfcraft wordcraft gridcraft deckcraft cadcraft" },
        { id: "system", title: "System", subtitle: "Know what is running and where your space goes.", icon: "info", group: "", keywords: "info about storage speicher festplatte home ram cpu temperature temperatur kernel hostname" }
    ]
    readonly property var searchIndex: pages.concat([
        { id: "network", title: "Wi-Fi networks & passwords", subtitle: "Connect, disconnect or forget a saved network.", icon: "wifi", keywords: "wlan internet password passwort ssid saved vergessen" },
        { id: "network", title: "Tailscale VPN", subtitle: "Manage your private network connection.", icon: "vpn_lock", keywords: "tailscale vpn remote privat verbindung" },
        { id: "network", title: "IP address & DNS", subtitle: "Inspect the current connection details.", icon: "lan", keywords: "ip gateway dns address adresse" },
        { id: "bluetooth", title: "Pair a Bluetooth device", subtitle: "Connect headphones, mice and other accessories.", icon: "headphones", keywords: "pairing koppeln bluetooth connect headphones kopfhörer battery" },
        { id: "audio", title: "Microphone & mute", subtitle: "Select an input device, mute it or test its level.", icon: "mic", keywords: "mic microphone mikrofon test mute stumm pegel" },
        { id: "audio", title: "Application volume", subtitle: "Control sound separately for each running app.", icon: "equalizer", keywords: "volume lautstärke application stream apps sound" },
        { id: "display", title: "Screen brightness", subtitle: "Adjust the built-in display brightness.", icon: "brightness_6", keywords: "brightness backlight helligkeit dim" },
        { id: "appearance", title: "Material colors from wallpaper", subtitle: "Let your wallpaper define the system palette.", icon: "auto_awesome", keywords: "material you picker farben color wallpaper hintergrund" },
        { id: "appearance", title: "Cursor theme & size", subtitle: "Choose a pointer for the desktop and your applications.", icon: "mouse", keywords: "cursor pointer mauszeiger zeiger größe size bibata adwaita" },
        { id: "appearance", title: "Wallpaper collections", subtitle: "Choose a matching wallpaper or pick one at random.", icon: "wallpaper", keywords: "wallpaper jpg png random zufall hintergrund sammlung" },
        { id: "appearance", title: "Profile picture", subtitle: "Choose your photo for the lock screen and sign-in screen.", icon: "account_circle", keywords: "profile photo picture avatar profilbild bild benutzer login lock screen sperrbildschirm" },
        { id: "appearance", title: "Wallpaper animation", subtitle: "Choose how your next wallpaper appears.", icon: "animation", keywords: "wallpaper transition wipe fade wave animation übergang wechsel" },
        { id: "windows", title: "Window layout", subtitle: "Choose Scrolling, Dwindle, Master or Monocle.", icon: "view_quilt", keywords: "hyprland default layout tile tiling fenster anordnung karten nebeneinander" },
        { id: "windows", title: "New window behavior", subtitle: "Adjust new card widths, split direction and the main-window area.", icon: "open_in_new", keywords: "new windows neue fenster width breite direction richtung main master stack" },
        { id: "input", title: "Touchpad & scrolling", subtitle: "Natural scrolling, tap to click and typing protection.", icon: "touchpad_mouse", keywords: "touchpad natural scroll tap click klicken tippen" },
        { id: "input", title: "Keyboard repeat", subtitle: "Adjust repeat delay and repeat rate.", icon: "keyboard", keywords: "keyboard tastatur repeat delay rate wiederholung" },
        { id: "input", title: "Keyboard shortcuts", subtitle: "Find your desktop hotkeys in one place.", icon: "keyboard_command_key", keywords: "hotkey shortcut super tasten druck screenshot" },
        { id: "notifications", title: "Do not disturb", subtitle: "Pause pop-ups while retaining notification history.", icon: "do_not_disturb_on", keywords: "dnd focus ruhe störung notifications" },
        { id: "power", title: "Battery health", subtitle: "Charge, health, cycles and estimated time remaining.", icon: "battery_full", keywords: "battery akku health gesundheit cycles zyklen time zeit" },
        { id: "power", title: "Power profiles", subtitle: "Choose power saver, balanced or performance.", icon: "speed", keywords: "tlp energie leistung power profile performance" },
        { id: "power", title: "Lock, sleep & shut down", subtitle: "Manage your current session.", icon: "power_settings_new", keywords: "lock logout restart reboot shutdown suspend sperren neustart herunterfahren schlafen" },
        { id: "appimages", title: "Install or update an AppImage", subtitle: "Choose a local file, check its architecture and keep its launcher up to date.", icon: "install_desktop", keywords: "appimage download installieren update ersetzen executable ausführbar arm x86 office" },
        { id: "appimages", title: "Restore an AppImage", subtitle: "Return to the previous version after a managed update.", icon: "restore", keywords: "appimage rollback backup restore previous version zurück wiederherstellen" },
        { id: "system", title: "Storage & memory", subtitle: "Inspect home and root storage, RAM and live usage.", icon: "storage", keywords: "disk storage lv_home lv_root ram memory cpu festplatte speicher" }
    ])
    function results() {
        const terms = (searchField ? searchField.text : "").trim().toLocaleLowerCase().split(/\s+/).filter(term => term);
        return searchIndex.filter(entry => terms.every(term => (entry.title + " " + entry.subtitle + " " + entry.keywords).toLocaleLowerCase().includes(term)));
    }
    function canonical(page) {
        return ({wifi: "network", battery: "power", session: "power", performance: "system", calendar: "overview", sound: "audio", layout: "windows", window: "windows", tiling: "windows"})[page] || page;
    }
    function navigate(page) {
        confirmCallback = null;
        const next = canonical(page);
        selectedPage = pages.some(entry => entry.id === next) ? next : "overview";
        if (searchField) searchField.clear();
    }
    function open(page) {
        if (!bodyLoader.ensureLoaded()) return;
        if (page) navigate(page);
        else searchField.clear();
        if (!opened) aboutToOpen();
        if (!canOpen) { pendingOpen = true; return; }
        pendingOpen = false;
        opened = true;
        Qt.callLater(function() { if (app.opened && windowSurface) windowSurface.forceActiveFocus(); });
    }
    function close() {
        pendingOpen = false;
        if (!opened) return;
        confirmCallback = null;
        opened = false;
    }
    function toggle() { if (opened || pendingOpen) close(); else open(); }
    onCanOpenChanged: if (canOpen && pendingOpen) open(selectedPage)
    function toast(message) { toastText = message; toastTimer.restart(); }
    function confirm(title, message, callback) {
        confirmTitle = title; confirmMessage = message; confirmCallback = callback;
        Qt.callLater(function() { if (app.opened && app.confirmCallback && cancelConfirmation) cancelConfirmation.forceActiveFocus(); });
    }

    // Keep the layer mapped continuously until the close animation finishes.
    // Binding visibility to Animation.running can unmap and remap it on Escape.
    visible: surfaceMapped
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    onOpenedChanged: {
        revealAnimation.stop();
        if (opened) surfaceMapped = true;
        revealAnimation.from = reveal;
        revealAnimation.to = opened ? 1 : 0;
        revealAnimation.duration = opened ? 320 : 200;
        revealAnimation.easing.type = opened ? Easing.OutBack : Easing.OutCubic;
        revealAnimation.start();
    }
    NumberAnimation {
        id: revealAnimation
        target: app
        property: "reveal"
        easing.overshoot: 0.65
        onFinished: if (!app.opened) app.surfaceMapped = false
    }
    NumberAnimation { id: pageAnimation; target: app; property: "pageStretch"; from: 0.965; to: 1; duration: 240; easing.type: Easing.OutBack; easing.overshoot: 0.6 }
    Timer { id: toastTimer; interval: 3200; onTriggered: app.toastText = "" }
    IpcHandler {
        target: "settingsApp"
        function toggle(): void { app.toggle(); }
        function open(): void { app.open(); }
        function openPage(page: string): void { app.open(page); }
        function close(): void { app.close(); }
    }
    Shortcut {
        sequence: "Escape"; enabled: app.opened; autoRepeat: false
        onActivated: { if (app.confirmCallback) app.confirmCallback = null; else if (searchField.text) searchField.clear(); else app.close(); }
    }
    Shortcut { sequence: "Ctrl+K"; enabled: app.opened && !app.confirmCallback; onActivated: { searchField.forceActiveFocus(); searchField.selectAll(); } }
    Shortcut { sequence: "Ctrl+F"; enabled: app.opened && !app.confirmCallback; onActivated: { searchField.forceActiveFocus(); searchField.selectAll(); } }
    Rectangle {
        anchors.fill: parent
        color: ThemeApi.Theme.bgDim
        opacity: 0.65 * Math.max(0, Math.min(1, app.reveal))
        MouseArea { anchors.fill: parent; enabled: app.opened; onClicked: app.close() }
    }
    MenuBodyLoader {
        id: bodyLoader
        width: Math.min(1200, parent.width - 48)
        height: Math.min(820, parent.height - 48)
        anchors.centerIn: parent
        // Keep the native-layout writer alive even after closing or navigating.
        engaged: app.surfaceMapped || app.pendingOpen || app.windowPreferenceWritePending
        sourceComponent: Component {
            Rectangle {
                id: windowSurface
                property alias searchField: searchField
                property alias cancelConfirmation: cancelConfirmation
                anchors.fill: parent
                radius: 26
                color: ThemeApi.Theme.bg0
                border.width: 1
                border.color: ThemeApi.Theme.border
                clip: true
                enabled: app.opened
                opacity: Math.max(0, Math.min(1, app.reveal))
                transform: [
                    Scale { origin.x: windowSurface.width / 2; origin.y: windowSurface.height / 2; xScale: 0.965 + 0.035 * app.reveal; yScale: xScale },
                    Translate { y: 18 * (1 - app.reveal) }
                ]
                MouseArea { anchors.fill: parent }
                Item {
                    id: sidebar
                    enabled: app.confirmCallback === null
                    width: windowSurface.width < 1050 ? 216 : 240
                    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 18; anchors.rightMargin: 18
                        anchors.topMargin: 25; anchors.bottomMargin: 18
                        spacing: 20
                        RowLayout {
                            spacing: 12
                            Rectangle {
                                Layout.preferredWidth: 38; Layout.preferredHeight: 38
                                radius: 13; color: ThemeApi.Theme.accentSoft
                                Text { anchors.centerIn: parent; text: "tune"; font.family: "Material Symbols Rounded"; font.pixelSize: 23; color: ThemeApi.Theme.accent }
                            }
                            Settings.SLabel { text: "Settings"; font.pixelSize: 20; font.weight: Font.DemiBold; color: ThemeApi.Theme.textBright }
                        }
                        TextField {
                            id: searchField
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            placeholderText: "Search settings"
                            placeholderTextColor: ThemeApi.Theme.muted
                            color: ThemeApi.Theme.textBright
                            selectionColor: ThemeApi.Theme.accent
                            selectedTextColor: ThemeApi.Theme.onAccent
                            font.family: "Inter"; font.pixelSize: 12
                            leftPadding: 34; rightPadding: text ? 30 : 10
                            background: Rectangle { radius: 12; color: ThemeApi.Theme.surface; border.width: searchField.activeFocus ? 1 : 0; border.color: ThemeApi.Theme.accent }
                            Text { x: 11; anchors.verticalCenter: parent.verticalCenter; text: "search"; color: ThemeApi.Theme.muted; font.family: "Material Symbols Rounded"; font.pixelSize: 18 }
                            Text { anchors.right: parent.right; anchors.rightMargin: 9; anchors.verticalCenter: parent.verticalCenter; text: "close"; visible: searchField.text.length > 0; color: ThemeApi.Theme.muted; font.family: "Material Symbols Rounded"; font.pixelSize: 16; MouseArea { anchors.fill: parent; onClicked: searchField.clear() } }
                            Keys.onReturnPressed: { const matches = app.results(); if (matches.length) app.navigate(matches[0].id); }
                        }
                        Settings.SMomentumFlickable {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            kineticEnabled: app.opened
                            contentHeight: nav.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true
                            interactive: contentHeight > height
                            ColumnLayout {
                                id: nav
                                width: parent.width
                                spacing: 4
                                Repeater {
                                    model: app.pages
                                    delegate: ColumnLayout {
                                        id: navEntry
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Settings.SLabel {
                                            visible: navEntry.modelData.group.length > 0
                                            text: navEntry.modelData.group
                                            color: ThemeApi.Theme.muted
                                            font.pixelSize: 9
                                            font.weight: Font.DemiBold
                                            font.letterSpacing: 1.15
                                            Layout.leftMargin: 12
                                            Layout.topMargin: 17
                                            Layout.bottomMargin: 4
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 42
                                            radius: 12
                                            color: app.currentPage === navEntry.modelData.id ? ThemeApi.Theme.accentSoft : navMouse.containsMouse ? ThemeApi.Theme.surface : "transparent"
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12; anchors.rightMargin: 12
                                                spacing: 12
                                                Text { text: navEntry.modelData.icon; color: app.currentPage === navEntry.modelData.id ? ThemeApi.Theme.accent : ThemeApi.Theme.muted; font.family: "Material Symbols Rounded"; font.pixelSize: 19 }
                                                Settings.SLabel { text: navEntry.modelData.title; Layout.fillWidth: true; font.pixelSize: 12; font.weight: app.currentPage === navEntry.modelData.id ? Font.DemiBold : Font.Normal; color: app.currentPage === navEntry.modelData.id ? ThemeApi.Theme.textBright : ThemeApi.Theme.text; elide: Text.ElideRight }
                                            }
                                            MouseArea { id: navMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: app.navigate(navEntry.modelData.id) }
                                            Accessible.role: Accessible.Button
                                            Accessible.name: navEntry.modelData.title
                                            activeFocusOnTab: true
                                            Keys.onReturnPressed: app.navigate(navEntry.modelData.id)
                                        }
                                    }
                                }
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 54
                            radius: 14
                            color: ThemeApi.Theme.surface
                            RowLayout {
                                anchors.fill: parent; anchors.margins: 12
                                spacing: 10
                                Rectangle { width: 9; height: 9; radius: 5; color: ThemeApi.Theme.accent }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3
                                    Settings.SLabel { text: ThemeApi.Theme.activeTheme.name; font.pixelSize: 11; font.weight: Font.Medium; elide: Text.ElideRight; Layout.fillWidth: true }
                                    Settings.SLabel { text: "Super + I  ·  Ctrl + K to search"; font.pixelSize: 9; color: ThemeApi.Theme.muted }
                                }
                            }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: app.navigate("appearance") }
                        }
                    }
                }
                Rectangle {
                    enabled: app.confirmCallback === null
                    x: sidebar.width
                    y: 1; width: parent.width - x - 1; height: parent.height - 2
                    topRightRadius: 25; bottomRightRadius: 25
                    color: ThemeApi.Theme.bgDim
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 30; anchors.rightMargin: 26
                        anchors.topMargin: 25; anchors.bottomMargin: 0
                        spacing: 24
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 16
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 7
                                Settings.SLabel { text: app.currentPage === "search" ? "Search results" : app.currentEntry.title; font.pixelSize: 28; font.weight: Font.DemiBold; color: ThemeApi.Theme.textBright }
                                Settings.SLabel { text: app.currentPage === "search" ? "Find a setting, device or action." : app.currentEntry.subtitle; font.pixelSize: 12; color: ThemeApi.Theme.muted; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                            }
                            Settings.SButton { iconName: "close"; Accessible.name: "Close settings"; onClicked: app.close(); Layout.alignment: Qt.AlignTop }
                        }
                        Item {
                            id: pageHost
                            Layout.fillWidth: true; Layout.fillHeight: true
                            clip: true
                            Loader {
                                id: pageLoader
                                anchors.fill: parent
                                active: app.visible && app.currentPage !== "windows"
                                sourceComponent: ({ overview: overviewPage, network: networkPage, bluetooth: bluetoothPage, audio: audioPage, display: displayPage, appearance: appearancePage, input: inputPage, notifications: notificationsPage, power: powerPage, appimages: appimagesPage, system: systemPage, search: searchPage })[app.currentPage] || overviewPage
                                transform: Scale { origin.x: pageHost.width / 2; origin.y: 0; xScale: 1 + (1 - app.pageStretch) * 0.3; yScale: app.pageStretch }
                                onLoaded: pageAnimation.restart()
                            }
                            // A page change must not destroy its writer halfway through
                            // saving a native layout change. Release it after completion.
                            Loader {
                                id: windowsPageLoader
                                anchors.fill: parent
                                active: (app.visible && app.currentPage === "windows") || app.windowPreferenceWritePending
                                visible: app.visible && app.currentPage === "windows"
                                sourceComponent: windowsPage
                                transform: Scale { origin.x: pageHost.width / 2; origin.y: 0; xScale: 1 + (1 - app.pageStretch) * 0.3; yScale: app.pageStretch }
                                onLoaded: pageAnimation.restart()
                            }
                            Connections {
                                target: windowsPageLoader.item
                                function onBusyChanged() {
                                    if (windowsPageLoader.item && windowsPageLoader.item.busy) app.windowPreferenceWritePending = true;
                                    else Qt.callLater(function() {
                                        if (!windowsPageLoader.item || !windowsPageLoader.item.busy) app.windowPreferenceWritePending = false;
                                    });
                                }
                            }
                        }
                    }
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 18
                    width: Math.min(parent.width - 80, toastLabel.implicitWidth + 42)
                    height: toastLabel.implicitHeight + 24
                    visible: app.toastText.length > 0
                    color: ThemeApi.Theme.surfaceRaised
                    radius: 14
                    border.width: 1; border.color: ThemeApi.Theme.border
                    z: 50
                    Settings.SLabel { id: toastLabel; anchors.centerIn: parent; text: app.toastText; width: Math.min(implicitWidth, windowSurface.width - 130); horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; font.pixelSize: 12 }
                }
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(ThemeApi.Theme.bgDim.r, ThemeApi.Theme.bgDim.g, ThemeApi.Theme.bgDim.b, 0.85)
                    visible: app.confirmCallback !== null
                    z: 100
                    MouseArea { anchors.fill: parent }
                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(440, parent.width - 80)
                        height: confirmBody.implicitHeight + 48
                        radius: 24
                        color: ThemeApi.Theme.surface
                        border.width: 1; border.color: ThemeApi.Theme.border
                        ColumnLayout {
                            id: confirmBody
                            x: 24; y: 24; width: parent.width - 48
                            spacing: 18
                            Settings.SLabel { text: app.confirmTitle; font.pixelSize: 21; font.weight: Font.DemiBold; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: ThemeApi.Theme.textBright }
                            Settings.SLabel { text: app.confirmMessage; font.pixelSize: 13; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: ThemeApi.Theme.muted }
                            RowLayout {
                                Layout.fillWidth: true
                                Item { Layout.fillWidth: true }
                                Settings.SButton { id: cancelConfirmation; text: "Cancel"; onClicked: { app.confirmCallback = null; windowSurface.forceActiveFocus(); } }
                                Settings.SButton { text: "Confirm"; accent: true; onClicked: { const callback = app.confirmCallback; app.confirmCallback = null; if (callback) callback(); } }
                            }
                        }
                    }
                }
            }
        }
    }
    Component { id: overviewPage; Settings.OverviewPage { controller: app; active: app.opened } }
    Component { id: networkPage; Settings.NetworkPage { controller: app; active: app.opened } }
    Component { id: bluetoothPage; Settings.BluetoothPage { controller: app; active: app.opened } }
    Component { id: audioPage; Settings.AudioPage { controller: app; active: app.opened } }
    Component { id: displayPage; Settings.DisplayPage { controller: app; active: app.opened } }
    Component { id: appearancePage; Settings.AppearancePage { controller: app; active: app.opened } }
    Component { id: windowsPage; Settings.WindowsPage { controller: app; active: app.opened && app.currentPage === "windows" } }
    Component { id: inputPage; Settings.InputPage { controller: app; active: app.opened } }
    Component { id: notificationsPage; Settings.NotificationsPage { controller: app; active: app.opened } }
    Component { id: powerPage; Settings.PowerPage { controller: app; active: app.opened } }
    Component { id: appimagesPage; Settings.AppImagesPage { controller: app; preferences: app.appImagePreferences; active: app.opened } }
    Component { id: systemPage; Settings.SystemPage { controller: app; active: app.opened } }
    Component {
        id: searchPage
        Settings.SPage {
            controller: app
            Settings.SCard {
                title: app.results().length + (app.results().length === 1 ? " result" : " results")
                Repeater {
                    model: app.results()
                    delegate: Settings.SRow { required property var modelData; title: modelData.title; subtitle: modelData.subtitle; iconName: modelData.icon; interactive: true; onClicked: app.navigate(modelData.id) }
                }
                Settings.SLabel { visible: app.results().length === 0; text: "No matching settings. Try a device name, Wi-Fi, microphone or wallpaper."; color: ThemeApi.Theme.muted; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            }
        }
    }
}
