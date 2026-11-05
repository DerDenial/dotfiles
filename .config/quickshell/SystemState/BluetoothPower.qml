pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

QtObject {
    id: power
    readonly property var adapter: Bluetooth.defaultAdapter
    property bool loaded: false
    property int restoreAttempts: 0

    function initialize() {
        storage.text();
        Qt.callLater(restore);
    }

    function setEnabled(enabled) {
        if (!adapter || adapter.state === BluetoothAdapterState.Blocked) return;
        restoreTimer.stop();
        saved.enabled = enabled;
        saved.hasChoice = true;
        storage.writeAdapter();
        adapter.enabled = enabled;
    }

    function restore() {
        if (!loaded || !adapter || !saved.hasChoice) return;
        if (adapter.state === BluetoothAdapterState.Blocked) return;
        adapter.enabled = saved.enabled;
    }

    onAdapterChanged: {
        restoreAttempts = 0;
        restoreTimer.restart();
        Qt.callLater(restore);
    }

    property FileView storage: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/SystemState/bluetooth-power.json"
        blockLoading: true
        blockWrites: true
        printErrors: true
        onAdapterUpdated: writeAdapter()
        onLoaded: {
            power.loaded = true;
            Qt.callLater(power.restore);
            restoreTimer.start();
        }
        onLoadFailed: {
            power.loaded = true;
            Qt.callLater(function() { storage.writeAdapter(); power.restore(); restoreTimer.start(); });
        }
        onSaveFailed: function(error) { console.error("Bluetooth power state could not be saved:", error); }
        JsonAdapter {
            id: saved
            property bool hasChoice: true
            property bool enabled: false
        }
    }

    // Allow BlueZ startup and controller enumeration to settle before the final restore.
    property Timer restoreTimer: Timer {
        interval: 1000
        repeat: true
        onTriggered: {
            power.restore();
            power.restoreAttempts++;
            if (power.restoreAttempts >= 30) stop();
        }
    }
}
