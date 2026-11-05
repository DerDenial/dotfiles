//@ pragma UseQApplication
//@ pragma IconTheme Colloid-Dark
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Theme" as ThemePalette
import "SystemState" as SystemState
import "Notifications" as Notifications

PanelWindow {
    Component.onCompleted: {
        SystemState.BluetoothPower.initialize();
        bar.edgeReady = true;
        if (bar.edgeRequested) {
            bar.edgePresented = true;
            hoverMotion.snap(bar.width, 34, 0, 1);
        } else Qt.callLater(bar.syncEdgeMode);
    }
    /*
    -- Music Player kinda Useless ngl --

    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null

    RowLayout {
        anchors.left: parent.left
        anchors.verticalCenter:  parent.verticalCenter
        anchors.leftMargin: 14
        spacing: 8

        Pill {
            icon: "music_note"
            maxLabelWidth: 200
            label: bar.player ? `${bar.play.trackArtist || "Unkown"} — ${bar.player.trackTitle || ""}` : "Nothing playing"
        }
    }

*/

    id: bar

    readonly property bool menuActive: appLauncher.active || themeSwitcher.active || quickSettings.active || hardwarePanel.active || networkPanel.active || speedTestPanel.active || notificationCenter.active || clipboardHistory.active || quickNotes.active || emojiPicker.active || powerMenu.active || windowBar.active || screenshotEditor.active
    readonly property bool menuOwnsSurface: appLauncher.ownsSurface || themeSwitcher.ownsSurface || quickSettings.handoffActive || hardwarePanel.handoffActive || networkPanel.handoffActive || speedTestPanel.handoffActive || notificationCenter.handoffActive || clipboardHistory.ownsSurface || quickNotes.ownsSurface || emojiPicker.ownsSurface || powerMenu.ownsSurface
    EdgeBarState { id: edgeState }
    property bool edgeReady: false
    readonly property bool edgeRequested: edgeState.activeOnScreen(bar.screen ? bar.screen.name : "")
    property bool edgePresented: false
    property bool edgeReturning: false
    readonly property bool edgeVisible: edgePresented || edgeReturning
    readonly property bool edgeMotionPending: edgeVisible && hoverMotion.running
    readonly property real edgeAmount: edgeVisible
        ? Math.max(0, Math.min(1, (hoverMotion.surfaceWidth - 236) / Math.max(1, bar.width - 236))) : 0

    function syncEdgeMode() {
        // Menus keep the source geometry they captured until the return handoff.
        if (!edgeReady || menuActive || menuOwnsSurface || hoverFrozen) return;
        if (edgePresented === edgeRequested) return;
        edgeReturning = !edgeRequested;
        edgePresented = edgeRequested;
        hoverLatched = false;
        hoverArmed = false;
        hoverCloseDelay.stop();
        showingOsd = false;
        updateHoverMotion();
    }
    onEdgeRequestedChanged: syncEdgeMode()
    onWidthChanged: if (edgeVisible && !hoverFrozen) updateHoverMotion()
    IpcHandler {
        target: "edgeBar"
        function refresh(): void { edgeState.refresh(); }
    }

    FileShelfState { id: shelfController }
    FileShelf {
        id: fileShelf
        z: 40
        anchors.fill: parent
        shelfState: shelfController
        notch: notchSurface
        available: !bar.menuActive && !settingsApp.opened
        canOpen: available && !bar.hoverFrozen && !hoverMotion.running
        onAboutToOpen: {
            bar.hoverArmed = false;
            bar.hoverLatched = false;
            hoverCloseDelay.stop();
            bar.showingOsd = false;
            bar.hoverFrozen = false;
            bar.updateHoverMotion();
        }
        onFullyClosed: { bar.refreshNotchHover(); bar.syncEdgeMode(); }
    }

    property bool hoverArmed: true
    property bool hoverLatched: false
    property bool hoverFrozen: false
    property bool showingOsd: false

    readonly property bool notificationWanted: Notifications.Service.toastActive && !Notifications.Service.blocked
    property bool showingNotification: false
    property bool notificationDropdown: false
    readonly property real notificationWidth: Math.min(380, bar.width - 32)
    readonly property real notificationHeight: 100
    Binding {
        target: Notifications.Service
        property: "blocked"
        value: bar.menuActive || fileShelf.active || settingsApp.opened || bar.hoverLatched || bar.hoverFrozen || bar.edgeMotionPending
    }
    Binding { target: Notifications.Service; property: "centerOpen"; value: notificationCenter.opened }
    Binding { target: Notifications.Service; property: "toastHovered"; value: normalNotification.hovered || edgeNotification.hovered }
    Connections {
        target: Notifications.Service
        function onCenterRequested() { notificationCenter.open(); }
    }
    onNotificationWantedChanged: syncNotification()
    function syncNotification() {
        if (notificationWanted) {
            if (!showingNotification) notificationDropdown = bar.edgeVisible;
            showingNotification = true;
            showingOsd = false;
            if (notificationDropdown)
                notificationMotion.moveTo(notificationWidth, notificationHeight, 22, 1, true);
        } else if (showingNotification && notificationDropdown) {
            notificationMotion.moveTo(notificationWidth, 0, 22, 0, false);
        }
        updateHoverMotion();
    }
    NotchMotion {
        id: notificationMotion
        fromHeight: 0
        toHeight: 0
        onSettled: {
            if (!bar.notificationWanted && bar.notificationDropdown) {
                bar.showingNotification = false;
                bar.refreshNotchHover();
            }
        }
    }

    property bool suppressHoverReset: false
    property int hoverResetGeneration: 0
    readonly property bool notchExpanded: !edgeVisible && !menuActive && !fileShelf.active && !settingsApp.opened && hoverArmed && hoverLatched
    readonly property bool hoverHitExpanded: !edgeVisible && (hoverLatched || (!showingOsd && !menuActive && !settingsApp.opened && !hoverFrozen && hoverMotion.running && hoverMotion.surfaceHeight > 34.1))
    readonly property real notchMorph: hoverMotion.amount
    NotchMotion {
        id: hoverMotion
        onSettled: {
            if (bar.edgeReturning && !bar.edgePresented) {
                bar.edgeReturning = false;
                // Re-evaluate the pointer after the full-width hit area has
                // returned to the compact notch. Outside pointers re-arm now.
                bar.refreshNotchHover();
            }
            if (!bar.hoverFrozen && !bar.notificationWanted && bar.showingNotification && !bar.notificationDropdown) {
                bar.showingNotification = false;
                bar.refreshNotchHover();
            }
            if (!bar.hoverFrozen && !bar.menuActive && !notchOsd.active && !bar.notchExpanded)
                bar.showingOsd = false;
        }
    }
    NotchOsdState {
        id: notchOsd
        blocked: bar.menuActive || fileShelf.active || settingsApp.opened || bar.hoverLatched || bar.hoverFrozen || bar.showingNotification
        onActiveChanged: {
            if (bar.hoverFrozen) return;
            if (active) bar.showingOsd = true;
            else if (bar.notchExpanded) bar.showingOsd = false;
            bar.updateHoverMotion();
        }
    }
    function pauseNotchForMenu() {
        fileShelf.requestClose();
        hoverFrozen = true;
        hoverArmed = false;
        hoverLatched = false;
        hoverCloseDelay.stop();
        if (edgeVisible) { showingOsd = false; hoverFrozen = false; updateHoverMotion(); }
        else hoverMotion.freeze();
    }
    function updateHoverMotion() {
        if (hoverFrozen) return;
        if (edgeVisible) {
            hoverMotion.moveTo(edgePresented ? bar.width : 236, 34, edgePresented ? 0 : 17,
                edgePresented ? 1 : 0, edgePresented);
            return;
        }
        const toast = notificationWanted && showingNotification && !notificationDropdown;
        const status = !toast && notchOsd.active && !notchExpanded && !settingsApp.opened;
        hoverMotion.moveTo(toast ? notificationWidth : notchExpanded ? expandedNotchWidth : status ? notchOsd.requestedWidth : 236,
            toast ? notificationHeight : notchExpanded ? 64 : status ? notchOsd.requestedHeight : 34,
            toast ? 25 : notchExpanded ? 25 : status ? 23 : 17,
            toast || notchExpanded || status ? 1 : 0, toast || notchExpanded || status);
    }
    onNotchExpandedChanged: {
        if (notchExpanded) {
            hoverCloseDelay.stop();
            showingOsd = false;
        }
        updateHoverMotion();
    }
    onMenuOwnsSurfaceChanged: {
        if (menuOwnsSurface) {
            if (!notificationDropdown) showingNotification = false;
            hoverMotion.snap(edgePresented ? bar.width : 236, 34, edgePresented ? 0 : 17, edgePresented ? 1 : 0);
            showingOsd = false;
        }
    }
    onMenuActiveChanged: {
        if (menuActive) {
            hoverArmed = false;
            hoverLatched = false;
            hoverCloseDelay.stop();
        } else {
            hoverFrozen = false;
            hoverLatched = false;
            // A dismissed menu must not immediately expand again under the pointer.
            refreshNotchHover();
            syncEdgeMode();
            if (!menuOwnsSurface) updateHoverMotion();
        }
    }
    Timer {
        id: hoverCloseDelay
        interval: 140
        onTriggered: if (!notchHover.hovered && !bar.menuActive) bar.hoverLatched = false
    }
    onExpandedNotchWidthChanged: if (notchExpanded && !hoverFrozen) updateHoverMotion()
    readonly property real expandedNotchWidth: hoverContent.expandedWidth

    function refreshNotchHover() {
        const ticket = ++hoverResetGeneration;
        const origin = notchHost.mapToItem(null, 0, 0);
        const point = notchHover.point.scenePosition;
        const restingWidth = bar.edgeVisible ? bar.width : 236;
        const restingLeft = origin.x + (notchHost.width - restingWidth) / 2;
        const wasInsideResting = notchHover.hovered && point.x >= restingLeft
            && point.x < restingLeft + restingWidth && point.y >= origin.y && point.y < origin.y + 34;
        // Keep real inside/outside tracking alive. Disabling an observer that is
        // still under the pointer loses its next leave event in Qt. Only flush
        // a stale hit inherited from the old wide/expanded geometry.
        const staleHover = notchHover.hovered && !wasInsideResting;
        hoverArmed = false;
        hoverLatched = false;
        suppressHoverReset = true;
        if (staleHover) notchHover.enabled = false;
        Qt.callLater(function() {
            if (ticket !== bar.hoverResetGeneration) return;
            notchHover.enabled = true;
            Qt.callLater(function() {
                if (ticket !== bar.hoverResetGeneration) return;
                bar.suppressHoverReset = false;
                if (bar.menuActive || settingsApp.opened) return;
                if (!notchHover.hovered) bar.hoverArmed = true;
                else if (!wasInsideResting) {
                    // A fresh entry during the handoff should respond without
                    // requiring another exit and entry.
                    bar.hoverArmed = true;
                    if (!bar.edgeVisible && !fileShelf.active && !bar.hoverFrozen) bar.hoverLatched = true;
                }
            });
        });
    }

    // Notch and quick settings share one permanently mapped surface.
    // The input mask keeps the rest of the screen click-through while idle.
    implicitHeight: screen ? screen.height : 1080
    WlrLayershell.keyboardFocus: quickSettings.opened || hardwarePanel.opened || networkPanel.opened || speedTestPanel.opened || notificationCenter.opened ? WlrKeyboardFocus.Exclusive
        : fileShelf.opened && !shelfController.dragging ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    exclusiveZone: 34
    color: "transparent"
    aboveWindows: true

    anchors {
        top: true
        left: true
        right: true
    }

    margins {
        top: 0
        bottom: 0
        left: 0
        right: 0
    }

    // Clock updates follow minute boundaries without periodic shell commands.
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
        readonly property string value: Qt.formatDateTime(date, "HH:mm")
    }
    QtObject {
        id: dateLabel
        readonly property string value: clock.date.toLocaleDateString(Qt.locale("en_US"), "ddd, MMM d")
    }

    // Keep the direct battery fallback independent of the UPower service.
    Poller {
        id: bat
        command: "cat /sys/class/power_supply/BAT0/capacity"
        interval: 10000
    }
    Poller {
        id: batStatus
        command: "cat /sys/class/power_supply/BAT0/status"
        interval: 10000
    }

    // The hover observer is an ancestor of every notch button, so child hover
    // handling cannot cut off delivery. Its hit area stays still while the shape bounces.
    Item {
        id: notchHost
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        width: bar.edgeVisible ? bar.width : bar.hoverHitExpanded ? bar.expandedNotchWidth + 16 : 236
        height: bar.hoverHitExpanded ? 72 : 34
        HoverHandler {
            id: notchHover
            blocking: false
            onHoveredChanged: {
                if (hovered) {
                    hoverCloseDelay.stop();
                    if (!bar.edgeVisible && !bar.showingNotification && !bar.suppressHoverReset && !bar.menuActive && !fileShelf.active && !settingsApp.opened && bar.hoverArmed && !bar.hoverFrozen)
                        bar.hoverLatched = true;
                } else if (!bar.showingNotification && !bar.suppressHoverReset && !bar.menuActive && !settingsApp.opened) {
                    bar.hoverArmed = true;
                    hoverCloseDelay.restart();
                }
            }
        }

        Rectangle {
            id: notchSurface
            readonly property bool edgeTaskbar: bar.edgePresented

            visible: !bar.menuOwnsSurface
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            width: Math.min(bar.width, hoverMotion.surfaceWidth)
            height: hoverMotion.surfaceHeight
            topLeftRadius: 0
            topRightRadius: 0
            bottomLeftRadius: Math.max(0, hoverMotion.radius)
            bottomRightRadius: hoverMotion.radius
            color: ThemePalette.Theme.notchBg
            border.width: bar.edgeVisible ? 0 : 1
            border.color: ThemePalette.Theme.border

            // Meet the display edge without a horizontal border.
            Rectangle {
                x: 0; y: 0
                width: parent.width
                height: parent.border.width
                color: parent.color
                z: 100
            }
            clip: true

            HoverNotchContent {
                id: hoverContent
                visible: !bar.showingOsd && !bar.showingNotification && bar.edgeAmount < 0.999
                opacity: 1 - bar.edgeAmount
                anchors.fill: parent
                panelWindow: bar
                availableWidth: bar.width - 32
                clockValue: clock.value || "00:00"
                dateValue: dateLabel.value
                batteryLevel: Number(bat.value)
                batteryCharging: batStatus.value.trim() === "Charging"
                animated: !bar.menuActive
                shelfCount: shelfController.count
                notificationCount: Notifications.Service.unreadCount
                notificationsPaused: Notifications.Service.dnd
                onNotificationsRequested: notificationCenter.toggle()
                onShelfRequested: fileShelf.toggle()
                onQuickSettingsRequested: quickSettings.toggle()
            }
            EdgeTaskbarContent {
                anchors.fill: parent
                panelWindow: bar
                active: bar.edgePresented && !bar.menuActive && !settingsApp.opened && !bar.edgeMotionPending
                amount: bar.edgeAmount
                statusActive: bar.showingOsd
                clockValue: clock.value || "00:00"
                batteryLevel: Number(bat.value)
                batteryCharging: batStatus.value.trim() === "Charging"
                shelfCount: shelfController.count
                notificationCount: Notifications.Service.unreadCount
                notificationsPaused: Notifications.Service.dnd
                onNotificationsRequested: notificationCenter.toggle()
                onShelfRequested: fileShelf.toggle()
                onQuickSettingsRequested: quickSettings.toggle()
                onPowerRequested: powerMenu.toggle()
                onWindowBarRequested: windowBar.toggle()
            }
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: bar.edgeVisible ? Math.min(420, parent.width - 32) : parent.width
                height: parent.height
                visible: bar.showingOsd
                NotchOsdContent {
                    id: osdContent
                    anchors.fill: parent
                    osd: notchOsd
                    compactMode: bar.edgeVisible
                }
            }
            NotificationToastContent {
                id: normalNotification
                anchors.fill: parent
                visible: bar.showingNotification && !bar.notificationDropdown
                enabled: bar.notificationWanted && visible
                expandedWidth: bar.notificationWidth
                expandedHeight: bar.notificationHeight
            }
            CompactNotch {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: (bar.showingOsd || (bar.showingNotification && !bar.notificationDropdown)) && !bar.edgeVisible
                clockValue: clock.value || "00:00"
                batteryLevel: Number(bat.value)
                batteryCharging: batStatus.value.trim() === "Charging"
                transform: Scale {
                    origin.x: 118
                    xScale: hoverMotion.surfaceWidth / 236
                    yScale: 1 - hoverMotion.smoothstep(34, osdContent.foldHeight, hoverMotion.surfaceHeight)
                }
            }

        }

    }


    Rectangle {
        id: edgeNotificationSurface
        z: 30
        anchors.horizontalCenter: parent.horizontalCenter
        y: 42
        width: bar.notificationWidth
        height: Math.max(0, notificationMotion.surfaceHeight)
        radius: 22
        color: ThemePalette.Theme.notchBg
        border.width: 1
        border.color: ThemePalette.Theme.border
        clip: true
        visible: bar.showingNotification && bar.notificationDropdown && !bar.menuActive && !settingsApp.opened
        NotificationToastContent {
            id: edgeNotification
            width: parent.width
            height: bar.notificationHeight
            expandedWidth: bar.notificationWidth
            expandedHeight: bar.notificationHeight
            compactMode: true
            enabled: bar.notificationWanted && edgeNotificationSurface.visible
            transform: Scale {
                origin.x: edgeNotification.width / 2
                xScale: 1
                yScale: notificationMotion.surfaceHeight / bar.notificationHeight
            }
        }
    }

    // A regular desktop window; process sampling exists only while it is open.
    TaskManager {
        id: taskManager
        canOpen: !bar.menuActive && !settingsApp.visible && !fileShelf.active && !bar.hoverFrozen && !hoverMotion.running
        onAboutToOpen: {
            fileShelf.requestClose();
            screenshotEditor.close();
            windowBar.close();
            powerMenu.close();
            emojiPicker.close();
            quickNotes.close();
            clipboardHistory.close();
            appLauncher.close();
            themeSwitcher.close();
            quickSettings.close();
            hardwarePanel.close();
            networkPanel.close();
            speedTestPanel.close();
            notificationCenter.close();
            settingsApp.close();
            bar.refreshNotchHover();
            hoverCloseDelay.stop();
            bar.updateHoverMotion();
        }
    }

    // RAM lifecycle: idle visual bodies retire; native clock avoids shell polling.
    // Settings includes saved native window layouts and layout-specific controls.
    SettingsApp {
        id: settingsApp
        canOpen: !quickNotes.active && !emojiPicker.active && !powerMenu.active && !windowBar.active && !screenshotEditor.active && !bar.edgeMotionPending && !fileShelf.active
        onAboutToOpen: { fileShelf.requestClose(); screenshotEditor.close(); windowBar.close(); quickNotes.close(); emojiPicker.close(); powerMenu.close(); }
    }

    QuickSettings {
        id: quickSettings
        sourceNotch: notchSurface
        clockValue: clock.value || "00:00"
        batteryLevel: Number(bat.value)
        batteryCharging: batStatus.value.trim() === "Charging"
        canOpen: !hardwarePanel.active && !networkPanel.active && !speedTestPanel.active && !notificationCenter.active && !appLauncher.active && !themeSwitcher.active && !clipboardHistory.active && !quickNotes.active && !emojiPicker.active && !powerMenu.active && !windowBar.active && !screenshotEditor.active && !bar.edgeMotionPending && !fileShelf.active
        onAboutToOpen: {
            hardwarePanel.close();
            networkPanel.close();
            speedTestPanel.close();
            notificationCenter.close();
            screenshotEditor.close();
            windowBar.close();
            bar.pauseNotchForMenu();
            powerMenu.close();
            emojiPicker.close();
            quickNotes.close();
            clipboardHistory.close();
            appLauncher.close();
            themeSwitcher.close();
            settingsApp.close();
        }
        onSettingsRequested: page => settingsApp.open(page)
        onNetworkRequested: networkPanel.open()
        onNotificationsRequested: notificationCenter.open()
    }

    // Live hardware snapshots share the notch's morph and input handoff.
    HardwarePanel {
        id: hardwarePanel
        sourceNotch: notchSurface
        clockValue: clock.value || "00:00"
        batteryLevel: Number(bat.value)
        batteryCharging: batStatus.value.trim() === "Charging"
        hotkeyText: "Super + H"
        canOpen: !networkPanel.active && !speedTestPanel.active && !notificationCenter.active && !appLauncher.active && !themeSwitcher.active && !quickSettings.active && !clipboardHistory.active && !quickNotes.active && !emojiPicker.active && !powerMenu.active && !windowBar.active && !screenshotEditor.active && !bar.edgeMotionPending && !fileShelf.active
        onAboutToOpen: {
            networkPanel.close();
            speedTestPanel.close();
            notificationCenter.close();
            screenshotEditor.close();
            windowBar.close();
            bar.pauseNotchForMenu();
            powerMenu.close();
            emojiPicker.close();
            quickNotes.close();
            clipboardHistory.close();
            appLauncher.close();
            themeSwitcher.close();
            quickSettings.close();
            settingsApp.close();
        }
    }

    // Physical-link traffic, sampled only while its live panel is open.
    NetworkPanel {
        id: networkPanel
        sourceNotch: notchSurface
        clockValue: clock.value || "00:00"
        batteryLevel: Number(bat.value)
        batteryCharging: batStatus.value.trim() === "Charging"
        hotkeyText: "Super + Shift + N"
        canOpen: !speedTestPanel.active && !notificationCenter.active && !appLauncher.active && !themeSwitcher.active && !quickSettings.active && !hardwarePanel.active && !clipboardHistory.active && !quickNotes.active && !emojiPicker.active && !powerMenu.active && !windowBar.active && !screenshotEditor.active && !bar.edgeMotionPending && !fileShelf.active
        onAboutToOpen: {
            speedTestPanel.close();
            notificationCenter.close();
            screenshotEditor.close();
            windowBar.close();
            bar.pauseNotchForMenu();
            powerMenu.close();
            emojiPicker.close();
            quickNotes.close();
            clipboardHistory.close();
            appLauncher.close();
            themeSwitcher.close();
            quickSettings.close();
            hardwarePanel.close();
            settingsApp.close();
        }
    }

    // An explicit on-demand internet benchmark; opening never starts traffic.
    SpeedTestPanel {
        id: speedTestPanel
        sourceNotch: notchSurface
        clockValue: clock.value || "00:00"
        batteryLevel: Number(bat.value)
        batteryCharging: batStatus.value.trim() === "Charging"
        hotkeyText: "Super + Alt + S"
        canOpen: !appLauncher.active && !themeSwitcher.active && !quickSettings.active && !hardwarePanel.active && !networkPanel.active && !notificationCenter.active && !clipboardHistory.active && !quickNotes.active && !emojiPicker.active && !powerMenu.active && !windowBar.active && !screenshotEditor.active && !bar.edgeMotionPending && !fileShelf.active
        onAboutToOpen: {
            screenshotEditor.close();
            windowBar.close();
            bar.pauseNotchForMenu();
            powerMenu.close();
            emojiPicker.close();
            quickNotes.close();
            clipboardHistory.close();
            appLauncher.close();
            themeSwitcher.close();
            quickSettings.close();
            hardwarePanel.close();
            networkPanel.close();
            notificationCenter.close();
            settingsApp.close();
        }
    }

    NotificationCenter {
        id: notificationCenter
        sourceNotch: notchSurface
        clockValue: clock.value || "00:00"
        batteryLevel: Number(bat.value)
        batteryCharging: batStatus.value.trim() === "Charging"
        canOpen: !appLauncher.active && !themeSwitcher.active && !quickSettings.active && !hardwarePanel.active && !networkPanel.active && !speedTestPanel.active && !clipboardHistory.active && !quickNotes.active && !emojiPicker.active && !powerMenu.active && !windowBar.active && !screenshotEditor.active && !bar.edgeMotionPending && !fileShelf.active
        onAboutToOpen: {
            screenshotEditor.close();
            windowBar.close();
            bar.pauseNotchForMenu();
            powerMenu.close();
            emojiPicker.close();
            quickNotes.close();
            clipboardHistory.close();
            appLauncher.close();
            themeSwitcher.close();
            quickSettings.close();
            hardwarePanel.close();
            networkPanel.close();
            speedTestPanel.close();
            settingsApp.close();
        }
    }

    Connections {
        target: settingsApp
        function onOpenedChanged() {
            if (settingsApp.opened) {
                screenshotEditor.close();
                windowBar.close();
                powerMenu.close();
                emojiPicker.close();
                quickNotes.close();
                quickSettings.close();
                hardwarePanel.close();
                networkPanel.close();
                speedTestPanel.close();
                notificationCenter.close();
                appLauncher.close();
                themeSwitcher.close();
                clipboardHistory.close();
                bar.hoverArmed = false;
                bar.hoverLatched = false;
                hoverCloseDelay.stop();
            } else if (!bar.menuActive) { bar.refreshNotchHover(); bar.syncEdgeMode(); }
        }
    }

    // Reopening starts in Apps at the favorites header, including closing reversals.
    // Launcher arithmetic includes multi-digit Unicode superscript powers.
    AppLauncher {
        id: appLauncher
        sourceNotch: notchSurface
        canOpen: !themeSwitcher.active && !quickSettings.active && !hardwarePanel.active && !networkPanel.active && !speedTestPanel.active && !notificationCenter.active && !clipboardHistory.active && !quickNotes.active && !emojiPicker.active && !powerMenu.active && !windowBar.active && !screenshotEditor.active && !bar.edgeMotionPending && !fileShelf.active
        onAboutToOpen: {
            screenshotEditor.close();
            windowBar.close();
            bar.pauseNotchForMenu();
            powerMenu.close();
            emojiPicker.close();
            quickNotes.close();
            clipboardHistory.close();
            themeSwitcher.close();
            quickSettings.close();
            hardwarePanel.close();
            networkPanel.close();
            speedTestPanel.close();
            notificationCenter.close();
            settingsApp.close();
        }

        clockValue: clock.value || "00:00"
        batteryLevel: Number(bat.value)
        batteryCharging: batStatus.value.trim() === "Charging"
    }

    ThemeSwitcher {
        id: themeSwitcher
        sourceNotch: notchSurface
        canOpen: !appLauncher.active && !quickSettings.active && !hardwarePanel.active && !networkPanel.active && !speedTestPanel.active && !notificationCenter.active && !clipboardHistory.active && !quickNotes.active && !emojiPicker.active && !powerMenu.active && !windowBar.active && !screenshotEditor.active && !bar.edgeMotionPending && !fileShelf.active
        onAboutToOpen: {
            screenshotEditor.close();
            windowBar.close();
            bar.pauseNotchForMenu();
            powerMenu.close();
            emojiPicker.close();
            quickNotes.close();
            clipboardHistory.close();
            appLauncher.close();
            quickSettings.close();
            hardwarePanel.close();
            networkPanel.close();
            speedTestPanel.close();
            notificationCenter.close();
            settingsApp.close();
        }

        clockValue: clock.value || "00:00"
        batteryLevel: Number(bat.value)
        batteryCharging: batStatus.value.trim() === "Charging"
    }

    ClipboardHistory {
        id: clipboardHistory
        sourceNotch: notchSurface
        clockValue: clock.value || "00:00"
        batteryLevel: Number(bat.value)
        batteryCharging: batStatus.value.trim() === "Charging"
        canOpen: !appLauncher.active && !themeSwitcher.active && !quickSettings.active && !hardwarePanel.active && !networkPanel.active && !speedTestPanel.active && !notificationCenter.active && !quickNotes.active && !emojiPicker.active && !powerMenu.active && !windowBar.active && !screenshotEditor.active && !bar.edgeMotionPending && !fileShelf.active
        onAboutToOpen: {
            screenshotEditor.close();
            windowBar.close();
            bar.pauseNotchForMenu();
            powerMenu.close();
            emojiPicker.close();
            quickNotes.close();
            appLauncher.close();
            themeSwitcher.close();
            quickSettings.close();
            hardwarePanel.close();
            networkPanel.close();
            speedTestPanel.close();
            notificationCenter.close();
            settingsApp.close();
        }
    }

    QuickNotes {
        id: quickNotes
        sourceNotch: notchSurface
        clockValue: clock.value || "00:00"
        batteryLevel: Number(bat.value)
        batteryCharging: batStatus.value.trim() === "Charging"
        canOpen: !appLauncher.active && !themeSwitcher.active && !quickSettings.active && !hardwarePanel.active && !networkPanel.active && !speedTestPanel.active && !notificationCenter.active && !clipboardHistory.active && !emojiPicker.active && !powerMenu.active && !windowBar.active && !screenshotEditor.active && !bar.edgeMotionPending && !fileShelf.active
        onAboutToOpen: {
            screenshotEditor.close();
            windowBar.close();
            bar.pauseNotchForMenu();
            powerMenu.close();
            emojiPicker.close();
            appLauncher.close();
            themeSwitcher.close();
            quickSettings.close();
            hardwarePanel.close();
            networkPanel.close();
            speedTestPanel.close();
            notificationCenter.close();
            clipboardHistory.close();
            settingsApp.close();
        }
    }

    EmojiState {
        id: emojiState
        engaged: emojiPicker.active || emojiPicker.requestPending || opening
        onReadyToOpen: emojiPicker.reveal()
    }

    EmojiPicker {
        id: emojiPicker
        sourceNotch: notchSurface
        clockValue: clock.value || "00:00"
        batteryLevel: Number(bat.value)
        batteryCharging: batStatus.value.trim() === "Charging"
        catalog: emojiState.catalog
        recentEmojis: emojiState.recentEmojis
        loading: emojiState.loading
        busy: emojiState.busy
        opening: emojiState.opening
        inputSuspended: emojiState.inputSuspended
        error: emojiState.error
        canOpen: !appLauncher.active && !themeSwitcher.active && !quickSettings.active && !hardwarePanel.active && !networkPanel.active && !speedTestPanel.active && !notificationCenter.active && !clipboardHistory.active && !quickNotes.active && !powerMenu.active && !windowBar.active && !screenshotEditor.active && !bar.edgeMotionPending && !fileShelf.active
        onOpenRequested: emojiState.prepareOpen()
        onDismissed: emojiState.cancelOpen()
        onInsertRequested: emoji => emojiState.queueInsert(emoji)
        onInputReleased: emojiState.inputReleased()
        onAboutToOpen: {
            screenshotEditor.close();
            windowBar.close();
            bar.pauseNotchForMenu();
            powerMenu.close();
            appLauncher.close();
            themeSwitcher.close();
            quickSettings.close();
            hardwarePanel.close();
            networkPanel.close();
            speedTestPanel.close();
            notificationCenter.close();
            clipboardHistory.close();
            quickNotes.close();
            settingsApp.close();
        }
    }

    // Small power-action strip with a visible accent trail below the symbols.
    PowerMenu {
        id: powerMenu
        sourceNotch: notchSurface
        clockValue: clock.value || "00:00"
        batteryLevel: Number(bat.value)
        batteryCharging: batStatus.value.trim() === "Charging"
        canOpen: !appLauncher.active && !themeSwitcher.active && !quickSettings.active && !hardwarePanel.active && !networkPanel.active && !speedTestPanel.active && !notificationCenter.active && !clipboardHistory.active && !quickNotes.active && !emojiPicker.active && !settingsApp.visible && !windowBar.active && !screenshotEditor.active && !bar.edgeMotionPending && !fileShelf.active
        onAboutToOpen: {
            screenshotEditor.close();
            windowBar.close();
            bar.pauseNotchForMenu();
            emojiPicker.close();
            quickNotes.close();
            clipboardHistory.close();
            appLauncher.close();
            themeSwitcher.close();
            quickSettings.close();
            hardwarePanel.close();
            networkPanel.close();
            speedTestPanel.close();
            notificationCenter.close();
            settingsApp.close();
        }
    }

    // Glass dock: icon and selection share one center; status markers sit below the frame.
    WindowBar {
        id: windowBar
        canOpen: !appLauncher.active && !themeSwitcher.active && !quickSettings.active && !hardwarePanel.active && !networkPanel.active && !speedTestPanel.active && !notificationCenter.active && !clipboardHistory.active && !quickNotes.active && !emojiPicker.active && !powerMenu.active && !settingsApp.visible && !screenshotEditor.active && !bar.edgeMotionPending && (!fileShelf.active || shelfController.dragging)
        onAboutToOpen: {
            fileShelf.requestClose();
            screenshotEditor.close();
            // This surface rises from the bottom and does not borrow the notch.
            bar.hoverArmed = false;
            bar.hoverLatched = false;
            hoverCloseDelay.stop();
            powerMenu.close();
            emojiPicker.close();
            quickNotes.close();
            clipboardHistory.close();
            appLauncher.close();
            themeSwitcher.close();
            quickSettings.close();
            hardwarePanel.close();
            networkPanel.close();
            speedTestPanel.close();
            notificationCenter.close();
            settingsApp.close();
            bar.hoverFrozen = false;
            bar.updateHoverMotion();
        }
    }

    ScreenshotEditor {
        id: screenshotEditor
        canCapture: !appLauncher.active && !themeSwitcher.active && !quickSettings.active && !hardwarePanel.active && !networkPanel.active && !speedTestPanel.active && !notificationCenter.active
            && !clipboardHistory.active && !quickNotes.active && !emojiPicker.active
            && !powerMenu.active && !windowBar.active && !settingsApp.visible && !fileShelf.active && !hoverMotion.running
        onAboutToCapture: {
            fileShelf.requestClose();
            bar.hoverArmed = false;
            bar.hoverLatched = false;
            hoverCloseDelay.stop();
            windowBar.close();
            powerMenu.close();
            emojiPicker.close();
            quickNotes.close();
            clipboardHistory.close();
            appLauncher.close();
            themeSwitcher.close();
            quickSettings.close();
            hardwarePanel.close();
            networkPanel.close();
            speedTestPanel.close();
            notificationCenter.close();
            settingsApp.close();
            bar.hoverFrozen = false;
            bar.updateHoverMotion();
        }
    }

    HotkeyGuideState {
        id: hotkeyGuide
        blocked: bar.menuActive || fileShelf.active || settingsApp.opened
    }

    HotkeyOverview {
        shown: hotkeyGuide.shown
        groups: hotkeyGuide.groups
        loading: hotkeyGuide.loading
        status: hotkeyGuide.status
        error: hotkeyGuide.error
    }

    mask: Region {
        item: speedTestPanel.opened ? speedTestPanel
            : speedTestPanel.handoffActive || speedTestPanel.returning || (speedTestPanel.dropdownMode && speedTestPanel.active) ? speedTestPanel.morphSurface
            : notificationCenter.opened ? notificationCenter
            : notificationCenter.handoffActive || notificationCenter.returning || (notificationCenter.dropdownMode && notificationCenter.active) ? notificationCenter.morphSurface
            : networkPanel.opened ? networkPanel
            : networkPanel.handoffActive || networkPanel.returning || (networkPanel.dropdownMode && networkPanel.active) ? networkPanel.morphSurface
            : hardwarePanel.opened ? hardwarePanel
            : hardwarePanel.handoffActive || hardwarePanel.returning || (hardwarePanel.dropdownMode && hardwarePanel.active) ? hardwarePanel.morphSurface
            : quickSettings.opened ? quickSettings
            : quickSettings.handoffActive || quickSettings.returning || (quickSettings.dropdownMode && quickSettings.active) ? quickSettings.morphSurface
            : bar.menuActive ? notchSurface : notchHost
        Region { item: fileShelf.inputSurface; intersection: Intersection.Combine }
        Region {
            item: bar.showingNotification && !bar.menuActive && !settingsApp.opened
                ? bar.notificationDropdown ? edgeNotificationSurface : notchSurface : null
            intersection: Intersection.Combine
        }
    }

}
