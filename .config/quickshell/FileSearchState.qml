pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

// Filename metadata only. One bounded helper per query, no index or idle worker.
QtObject {
    id: state

    property bool engaged: false
    property bool placesRequested: false
    property string query: ""
    property string homePath: Quickshell.env("HOME") || StandardPaths.writableLocation(StandardPaths.HomeLocation)
    readonly property string helperPath: homePath + "/.config/quickshell/Files/files.py"
    readonly property string searchText: query.trim()
    readonly property bool eligible: engaged && searchText.length >= 2
    readonly property bool placesWanted: engaged && placesRequested

    property var items: []
    property var locations: []
    property bool busy: false
    property bool partial: false
    property string error: ""

    property int revision: 0
    property int runningRevision: -1
    property string runningQuery: ""
    property bool debounceReady: false
    property bool inFlight: false
    property bool received: false
    property bool cancelled: false
    property bool componentReady: false

    property bool placesLoaded: false
    property bool placesInFlight: false
    property bool placesReceived: false
    property bool placesCancelled: false
    property string placesHome: ""

    function cleanItems(value) {
        if (!Array.isArray(value)) return [];
        return value.slice(0, 64).filter(item => item
            && typeof item.title === "string" && item.title.length <= 16384
            && typeof item.detail === "string" && item.detail.length <= 16384
            && typeof item.path === "string" && item.path.startsWith("/")
            && typeof item.parent === "string" && item.parent.startsWith("/")
            && typeof item.ref === "string" && item.ref.startsWith("file:///")
            && (item.kind === "file" || item.kind === "directory"));
    }

    function cancelSearch() {
        if (!componentReady) return;
        if (!inFlight && !searchJob.running) return;
        cancelled = true;
        // signal() must never be called with PID 0 while QProcess is starting.
        searchJob.running = false;
        if (searchJob.running) searchKillDelay.restart();
    }

    function schedule(preserveResults) {
        if (!componentReady) return;
        ++revision;
        debounce.stop();
        debounceReady = false;
        // Keep the last tiny metadata model through the closing morph while
        // cancelling its worker. New queries and reopening always clear it.
        if (!preserveResults) {
            items = [];
            partial = false;
            error = "";
        }
        cancelSearch();
        busy = eligible;
        if (eligible) debounce.restart();
    }

    function startSearch() {
        if (!eligible || !debounceReady || inFlight || searchJob.running) return;
        debounceReady = false;
        inFlight = true;
        cancelled = false;
        received = false;
        runningRevision = revision;
        runningQuery = searchText;
        searchKillDelay.stop();
        searchJob.command = ["python3", helperPath, "search", "--query=" + runningQuery,
            "--request", String(runningRevision)];
        searchDeadline.restart();
        searchJob.running = true;
    }

    function receiveSearch(text) {
        if (!inFlight || cancelled || !eligible || runningRevision !== revision
            || runningQuery !== searchText) return;
        try {
            const result = JSON.parse(text);
            // Validate the response's own identity as well as the active job.
            if (result.request !== revision || result.query !== searchText) return;
            received = true;
            items = cleanItems(result.items);
            partial = result.partial === true;
            error = typeof result.error === "string" ? result.error : "";
            busy = false;
        } catch (parseError) {
            // completeSearch reports one neutral error for malformed/empty output.
        }
    }

    function completeSearch() {
        if (!inFlight || searchJob.running) return;
        searchDeadline.stop();
        searchKillDelay.stop();
        if (!cancelled && eligible && runningRevision === revision && runningQuery === searchText) {
            if (!received) error = "File search is unavailable. Please try again.";
            busy = false;
        }
        inFlight = false;
        // The newest query may have finished its debounce while cancellation
        // was in progress. Never let an old process overlap that next query.
        startSearch();
    }

    function cancelPlaces() {
        if (!componentReady) return;
        if (!placesInFlight && !placesJob.running) return;
        placesCancelled = true;
        placesJob.running = false;
        if (placesJob.running) placesKillDelay.restart();
    }

    function ensurePlaces() {
        if (!componentReady || !placesWanted || placesLoaded || placesInFlight || placesJob.running) return;
        placesInFlight = true;
        placesReceived = false;
        placesCancelled = false;
        placesHome = homePath;
        placesKillDelay.stop();
        placesJob.command = ["python3", helperPath, "locations"];
        placesDeadline.restart();
        placesJob.running = true;
    }

    function receivePlaces(text) {
        if (!placesInFlight || placesCancelled || !placesWanted || placesHome !== homePath) return;
        try {
            const result = JSON.parse(text);
            locations = cleanItems(result.items);
            placesReceived = true;
            placesLoaded = true;
        } catch (parseError) { }
    }

    function completePlaces() {
        if (!placesInFlight || placesJob.running) return;
        placesDeadline.stop();
        placesKillDelay.stop();
        if (!placesCancelled && placesWanted && placesHome === homePath && !placesReceived) {
            locations = [];
            placesLoaded = true;
        }
        placesInFlight = false;
        ensurePlaces();
    }

    onQueryChanged: schedule()
    onEngagedChanged: {
        schedule(!engaged);
        if (!engaged) cancelPlaces();
        else ensurePlaces();
    }
    onPlacesRequestedChanged: {
        if (placesWanted) ensurePlaces();
        else cancelPlaces();
    }
    onHomePathChanged: {
        locations = [];
        placesLoaded = false;
        cancelPlaces();
        schedule();
        ensurePlaces();
    }
    Component.onCompleted: {
        componentReady = true;
        schedule();
        ensurePlaces();
    }

    property Timer debounce: Timer {
        interval: 180
        onTriggered: {
            state.debounceReady = true;
            state.startSearch();
        }
    }
    property Timer searchDeadline: Timer {
        interval: 5000
        onTriggered: {
            if (!state.inFlight) return;
            if (!state.cancelled && state.eligible && state.runningRevision === state.revision) {
                state.received = true;
                state.error = "Search took too long. Try a more specific name.";
                state.busy = false;
            }
            state.cancelSearch();
        }
    }
    property Timer searchKillDelay: Timer {
        interval: 300
        onTriggered: {
            if (state.cancelled && state.searchJob.running && Number(state.searchJob.processId) > 0)
                state.searchJob.signal(9);
        }
    }
    property Timer placesDeadline: Timer {
        interval: 3000
        onTriggered: {
            if (!state.placesInFlight) return;
            if (state.placesWanted && state.placesHome === state.homePath) {
                state.locations = [];
                state.placesLoaded = true;
            }
            state.cancelPlaces();
        }
    }
    property Timer placesKillDelay: Timer {
        interval: 300
        onTriggered: {
            if (state.placesCancelled && state.placesJob.running && Number(state.placesJob.processId) > 0)
                state.placesJob.signal(9);
        }
    }

    property Process searchJob: Process {
        stdout: StdioCollector { onStreamFinished: state.receiveSearch(text) }
        stderr: StdioCollector { }
        onStarted: if (state.cancelled || !state.eligible || state.runningRevision !== state.revision) state.cancelSearch()
        onExited: Qt.callLater(state.completeSearch)
        // FailedToStart has no exited signal in Quickshell 0.3.2.
        onRunningChanged: if (!running) Qt.callLater(state.completeSearch)
    }
    property Process placesJob: Process {
        stdout: StdioCollector { onStreamFinished: state.receivePlaces(text) }
        stderr: StdioCollector { }
        onStarted: if (state.placesCancelled || !state.placesWanted || state.placesHome !== state.homePath) state.cancelPlaces()
        onExited: Qt.callLater(state.completePlaces)
        onRunningChanged: if (!running) Qt.callLater(state.completePlaces)
    }
}
