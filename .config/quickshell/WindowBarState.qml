pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

// Metadata and object identities only. No title history is persisted and no
// polling process is needed; descriptors are reactive only while the bar is used.
QtObject {
    id: state

    property bool engaged: false
    property var entries: []
    property string activeKey: ""
    property var targetScreen: null
    property var lastFocusedToplevel: null
    property var order: []
    property var identities: ({ serial: 0, objects: [], keys: [] })
    property string actionError: ""
    property bool pinInFlight: false
    property bool pinAwaitingState: false
    property string pinKey: ""
    property bool pinExpected: false
    property bool pinExpectTiled: false
    property string pinReply: ""
    readonly property bool pinBusy: pinInFlight || pinProcess.running
    readonly property var observedEntries: engaged ? describeWindows() : []
    readonly property var workspaceChoices: engaged ? describeWorkspaces() : []

    function workspaceTarget(workspace) {
        if (!workspace) return "";
        if (workspace.id > 0) return String(workspace.id);
        const name = String(workspace.name || "");
        return name.startsWith("special:") ? name : name ? "name:" + name : "";
    }

    function describeWorkspaces() {
        // Include empty workspaces reachable through the configured 1–0 keys.
        const choices = Array.from({length: 10}, (_, i) => ({
            target: String(i + 1), label: String(i + 1), numbered: true
        }));
        for (const workspace of Array.from(Hyprland.workspaces.values)) {
            const target = workspaceTarget(workspace);
            if (!target || /[\u0000-\u001f,;]/.test(target)
                || choices.some(choice => choice.target === target)) continue;
            const name = String(workspace.name || "");
            choices.push({target: target, numbered: false,
                label: name.startsWith("special:") ? "Scratchpad · " + name.slice(8) : name || target});
        }
        return choices;
    }

    function compositorFor(window) {
        if (!window) return null;
        return Array.from(Hyprland.toplevels.values).find(candidate => candidate.wayland === window) || null;
    }

    function windowFor(key) {
        const index = identities.keys.indexOf(String(key));
        const window = index >= 0 ? identities.objects[index] : null;
        return window && Array.from(ToplevelManager.toplevels.values).indexOf(window) >= 0 ? window : null;
    }

    function selectorFor(window) {
        const wrapper = compositorFor(window);
        const address = wrapper ? String(wrapper.address || "").replace(/^0x/i, "") : "";
        return /^[0-9a-f]+$/i.test(address) && /[1-9a-f]/i.test(address) ? "address:0x" + address : "";
    }

    function refreshActions() {
        if (engaged || pinInFlight || pinAwaitingState) {
            Hyprland.refreshToplevels();
            Hyprland.refreshWorkspaces();
        }
    }

    function closeWindow(key) {
        const window = windowFor(key);
        if (!window) return false;
        try {
            window.close();
            return true;
        } catch (error) { return false; }
    }

    function toggleFloating(key) {
        const wrapper = compositorFor(windowFor(key));
        if (pinBusy || wrapper && wrapper.lastIpcObject && wrapper.lastIpcObject.pinned) return false;
        const selector = selectorFor(windowFor(key));
        if (!selector) return false;
        Hyprland.dispatch(Hyprland.usingLua
            ? "hl.dsp.window.float({window=" + JSON.stringify(selector) + ",action=\"toggle\"})"
            : "togglefloating " + selector);
        actionRefresh.restart();
        return true;
    }

    function moveToWorkspace(key, target) {
        const wrapper = compositorFor(windowFor(key));
        if (pinBusy || wrapper && wrapper.lastIpcObject && wrapper.lastIpcObject.pinned) return false;
        const selector = selectorFor(windowFor(key));
        const choice = workspaceChoices.find(candidate => candidate.target === String(target));
        if (!selector || !choice || /[\u0000-\u001f,;]/.test(choice.target)) return false;
        const destination = /^[1-9][0-9]*$/.test(choice.target) ? choice.target : JSON.stringify(choice.target);
        Hyprland.dispatch(Hyprland.usingLua
            ? "hl.dsp.window.move({window=" + JSON.stringify(selector) + ",workspace=" + destination + ",follow=false})"
            : "movetoworkspacesilent " + choice.target + "," + selector);
        actionRefresh.restart();
        return true;
    }

    function togglePinned(key) {
        const window = windowFor(key);
        const wrapper = compositorFor(window);
        const raw = wrapper ? wrapper.lastIpcObject : null;
        const selector = selectorFor(window);
        if (!Hyprland.usingLua || pinBusy || !selector || !raw || typeof raw.pinned !== "boolean") {
            actionError = "Pinning is not available for this window right now.";
            return false;
        }
        const tags = Array.from(raw.tags || []).map(tag => String(tag).replace(/\*$/, ""));
        pinExpected = !raw.pinned;
        pinExpectTiled = !pinExpected && tags.includes("qs-pin-managed") && tags.includes("qs-pin-tiled");
        pinKey = String(key);
        pinReply = actionError = "";
        pinAwaitingState = false;
        pinInFlight = true;
        // A single compositor-side operation floats/pins or restores the exact
        // chosen window. Only a validated hexadecimal address crosses the API.
        pinProcess.command = ["hyprctl", "eval", "require(\"modules.pin-window\").set("
            + JSON.stringify(selector) + "," + (pinExpected ? "true" : "false") + ")"];
        pinDeadline.restart();
        pinProcess.running = true;
        return true;
    }
    function failPin(message) {
        pinDeadline.stop();
        pinAwaitingState = pinInFlight = false;
        pinKey = "";
        actionError = message;
        refreshActions();
    }
    function verifyPinState() {
        if (!pinAwaitingState) return;
        const window = windowFor(pinKey);
        if (!window) { failPin("This window is no longer available."); return; }
        const wrapper = compositorFor(window);
        const raw = wrapper ? wrapper.lastIpcObject : null;
        if (!raw || typeof raw.pinned !== "boolean" || raw.pinned !== pinExpected
            || pinExpected && raw.floating !== true || pinExpectTiled && raw.floating !== false) return;
        pinDeadline.stop();
        pinAwaitingState = pinInFlight = false;
        pinKey = "";
    }

    function rootWindow(window) {
        let current = window;
        for (let depth = 0; current && current.parent && depth < 16; ++depth)
            current = current.parent;
        return current;
    }

    function keyFor(window) {
        if (!window) return "";
        const existing = identities.objects.indexOf(window);
        if (existing >= 0) return identities.keys[existing];
        const key = "window-" + (++identities.serial);
        identities.objects.push(window);
        identities.keys.push(key);
        return key;
    }

    function pruneIdentities(windows) {
        // Mutating this private JS registry does not invalidate the metadata
        // binding. Existing live windows retain their identity across updates.
        for (let i = identities.objects.length - 1; i >= 0; --i) {
            if (!identities.objects[i] || windows.indexOf(identities.objects[i]) < 0) {
                identities.objects.splice(i, 1);
                identities.keys.splice(i, 1);
            }
        }
    }

    function iconSource(icon) {
        const name = String(icon || "");
        if (!name) return "";
        if (name.startsWith("/"))
            return "file://" + name.split("/").map(part => encodeURIComponent(part)).join("/");
        if (name.startsWith("file:")) return name;
        return Quickshell.iconPath(name, true);
    }

    function applicationFor(appId, applications) {
        if (!appId) return null;
        const lowered = appId.toLocaleLowerCase();
        // StartupWMClass is important for Xwayland and Java applications whose
        // window class differs from the installed desktop-entry filename.
        const exact = applications.find(app => String(app.id || "").replace(/\.desktop$/i, "").toLocaleLowerCase() === lowered
            || String(app.startupClass || "").toLocaleLowerCase() === lowered);
        return exact || DesktopEntries.heuristicLookup(appId);
    }

    function describeWindows() {
        const windows = Array.from(ToplevelManager.toplevels.values).filter(window => window && !window.parent);
        const compositorWindows = Array.from(Hyprland.toplevels.values);
        const applications = Array.from(DesktopEntries.applications.values);
        return windows.map(function(window) {
            const compositorWindow = compositorWindows.find(candidate => candidate.wayland === window);
            const raw = compositorWindow ? compositorWindow.lastIpcObject : null;
            const appId = String(window.appId || (raw && raw.class) || "");
            const desktop = applicationFor(appId, applications);
            const key = keyFor(window);
            const workspace = compositorWindow ? compositorWindow.workspace : null;
            let workspaceName = "";
            if (workspace) {
                const name = String(workspace.name || "");
                workspaceName = workspace.id > 0 ? String(workspace.id)
                    : name.startsWith("special:") ? name.slice(8) || "Special" : name;
            }
            return {
                key: key,
                ref: window,
                title: String(window.title || appId || "Window"),
                appName: String(desktop && desktop.name ? desktop.name : appId || "Application"),
                icon: iconSource(desktop && desktop.icon ? desktop.icon : appId),
                active: key === activeKey,
                workspace: workspaceName,
                workspaceTarget: workspaceTarget(workspace),
                manageable: selectorFor(window) !== "",
                pinnedKnown: !!raw && typeof raw.pinned === "boolean",
                pinned: !!raw && raw.pinned === true,
                pinSupported: Hyprland.usingLua,
                pinBusy: pinBusy && pinKey === key,
                floatingKnown: !!raw && typeof raw.floating === "boolean",
                floating: !!raw && raw.floating === true
            };
        });
    }

    function publishEntries(descriptors) {
        const next = descriptors.slice();
        const keys = next.map(entry => entry.key);
        const preserved = order.filter(key => keys.indexOf(key) >= 0);
        for (const key of keys) if (preserved.indexOf(key) < 0) preserved.push(key);
        order = preserved;
        next.sort((left, right) => preserved.indexOf(left.key) - preserved.indexOf(right.key));
        pruneIdentities(next.map(entry => entry.ref));
        entries = next;
    }

    function chooseScreen(window) {
        const screens = Array.from(Quickshell.screens);
        const monitor = Hyprland.focusedMonitor;
        const focused = monitor ? screens.find(screen => screen.name === monitor.name) : null;
        const windowScreens = window ? Array.from(window.screens) : [];
        targetScreen = focused || windowScreens.find(screen => screens.indexOf(screen) >= 0) || screens[0] || null;
    }

    function prepare() {
        actionError = "";
        refreshActions();
        const windows = Array.from(ToplevelManager.toplevels.values).filter(window => window && !window.parent);
        pruneIdentities(windows);
        let source = rootWindow(ToplevelManager.activeToplevel)
            || rootWindow(Hyprland.activeToplevel ? Hyprland.activeToplevel.wayland : null)
            || rootWindow(lastFocusedToplevel);
        if (windows.indexOf(source) < 0) source = null;
        activeKey = source ? keyFor(source) : "";
        chooseScreen(source);
        const initial = describeWindows();
        // Opening establishes the order once; title/focus changes never reshuffle
        // icons under the pointer while the bar remains open.
        initial.sort((left, right) => Number(right.active) - Number(left.active)
            || left.appName.localeCompare(right.appName) || left.title.localeCompare(right.title));
        order = initial.map(entry => entry.key);
        entries = initial;
        return initial.length;
    }

    function activate(key) {
        const window = windowFor(key);
        if (!window) return false;
        try {
            if (window.minimized) window.minimized = false;
            window.activate();
            return true;
        } catch (error) {
            // A window can disappear between the click and the focus handoff.
            return false;
        }
    }

    onObservedEntriesChanged: if (engaged) {
        publishEntries(observedEntries);
        // Completing the operation changes descriptor dependencies. Defer that
        // completion until the metadata binding has finished evaluating.
        Qt.callLater(verifyPinState);
    }
    onEngagedChanged: if (!engaged) entries = []

    property Connections activeWindow: Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() {
            const current = state.rootWindow(ToplevelManager.activeToplevel);
            if (current) state.lastFocusedToplevel = current;
        }
    }
    property Connections screensChanged: Connections {
        target: Quickshell
        function onScreensChanged() {
            if (state.engaged && Array.from(Quickshell.screens).indexOf(state.targetScreen) < 0)
                state.chooseScreen(state.lastFocusedToplevel);
        }
    }
    property Connections floatingChanged: Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (state.engaged && ["changefloatingmode", "pin", "tag", "fullscreen", "movewindow", "closewindow"].includes(event.name)) actionRefresh.restart();
        }
    }
    // One-shot refresh after an action/event; there is no background polling.
    property Timer actionRefresh: Timer {
        interval: 80
        onTriggered: { state.refreshActions(); state.verifyPinState(); }
    }
    property Timer pinDeadline: Timer {
        interval: 6000
        onTriggered: {
            if (state.pinProcess.running) state.pinProcess.signal(15);
            state.failPin("Pinning did not respond. Please try again.");
        }
    }
    property Process pinProcess: Process {
        stdout: StdioCollector { onStreamFinished: state.pinReply = text.trim() }
        stderr: StdioCollector { }
        onExited: (code, status) => {
            if (!state.pinInFlight) return;
            if (code !== 0 || status !== 0 || state.pinReply !== "ok") {
                state.failPin("Could not change window pinning. Please try again.");
                return;
            }
            // Keep controls busy until authoritative metadata confirms the new
            // pin/layout state, avoiding a second toggle against a stale icon.
            state.pinAwaitingState = true;
            state.refreshActions();
            actionRefresh.restart();
            state.verifyPinState();
        }
        onRunningChanged: if (!running && state.pinInFlight && !state.pinAwaitingState) Qt.callLater(function() {
            if (!pinProcess.running && state.pinInFlight && !state.pinAwaitingState)
                state.failPin("Could not change window pinning. Please try again.");
        })
    }
    Component.onCompleted: lastFocusedToplevel = rootWindow(ToplevelManager.activeToplevel)
}
