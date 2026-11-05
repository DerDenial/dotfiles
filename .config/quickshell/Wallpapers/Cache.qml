pragma Singleton

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

QtObject {
    id: cache

    readonly property string home: Quickshell.env("HOME") || StandardPaths.writableLocation(StandardPaths.HomeLocation)
    property string interpreter: home + "/.config/quickshell/material-runtime/bin/python"
    property string helper: home + "/.config/quickshell/Wallpapers/thumbnail-cache.py"
    readonly property int metadataLimit: 96
    property var entries: ({})
    property var references: ({})
    property var revisions: ({})
    property var recent: []
    property var queue: []
    property var batch: []
    property var batchRevisions: ({})
    property var received: ({})
    property bool inFlight: false
    property bool cancelled: false
    readonly property bool busy: inFlight || worker.running

    function validPath(path) {
        return typeof path === "string" && path.startsWith("/") && !path.startsWith("//")
            && path.length <= 4096 && !path.includes("\u0000");
    }

    function acquire(path, revision) {
        if (!validPath(path)) return false;
        const next = Object.assign({}, references);
        next[path] = (next[path] || 0) + 1;
        references = next;
        const changed = revisions[path] !== undefined && revisions[path] !== revision;
        revisions[path] = revision;
        touch(path);
        enqueue(path, changed);
        return true;
    }

    function release(path) {
        if (!references[path]) return;
        const next = Object.assign({}, references);
        if (next[path] > 1) next[path]--;
        else delete next[path];
        references = next;
        queue = queue.filter(path => !!references[path]);
        if (!Object.keys(references).length && busy) {
            cancelled = true;
            if (worker.running) worker.running = false;
            killDeadline.restart();
        }
    }

    function enqueue(path, changed) {
        if (!references[path] || queue.includes(path) || (!changed && !cancelled && batch.includes(path))) return;
        if (queue.length >= 64) return;
        queue = queue.concat([path]);
        dispatch.restart();
    }

    function touch(path) {
        recent = recent.filter(value => value !== path).concat([path]);
        if (recent.length <= metadataLimit) return;
        const next = Object.assign({}, entries);
        const retained = [];
        for (let i = recent.length - 1; i >= 0; --i) {
            const value = recent[i];
            if (retained.length < metadataLimit || references[value] || batch.includes(value)) retained.unshift(value);
            else { delete next[value]; delete revisions[value]; }
        }
        recent = retained;
        entries = next;
    }

    function setEntry(path, source, failed) {
        const next = Object.assign({}, entries);
        next[path] = { source: source, failed: failed };
        entries = next;
        touch(path);
    }

    function retry(path, source) {
        if (!references[path] || !entries[path] || entries[path].source !== source) return;
        const next = Object.assign({}, entries);
        delete next[path];
        entries = next;
        enqueue(path, true);
    }

    function pump() {
        if (busy) return;
        const wanted = queue.filter(path => !!references[path]);
        if (!wanted.length) { queue = []; return; }
        batch = wanted.slice(0, 4);
        queue = wanted.slice(4);
        const versions = {};
        for (const path of batch) versions[path] = revisions[path];
        batchRevisions = versions;
        received = {};
        cancelled = false;
        inFlight = true;
        worker.command = [interpreter, helper];
        worker.stdinEnabled = true;
        operationDeadline.restart();
        worker.running = true;
    }

    function accept(line) {
        if (!inFlight || cancelled || line.length > 32768) return;
        let result;
        try { result = JSON.parse(line); } catch (error) { return; }
        if (!result || !batch.includes(result.path) || received[result.path]) return;
        if (result.status !== "ready" && result.status !== "error") return;
        if (result.status === "ready" && (typeof result.source !== "string"
                || !result.source.startsWith("file:///") || result.source.length > 16384)) return;
        received[result.path] = true;
        if (batchRevisions[result.path] !== revisions[result.path]) return;
        setEntry(result.path, result.status === "ready" ? result.source : "", result.status === "error");
    }

    function finish() {
        if (!inFlight) return;
        operationDeadline.stop();
        killDeadline.stop();
        if (!cancelled) {
            for (const path of batch) {
                if (!received[path] && batchRevisions[path] === revisions[path]) setEntry(path, "", true);
            }
        }
        batch = [];
        batchRevisions = ({});
        received = ({});
        inFlight = false;
        if (queue.length) dispatch.restart();
    }

    property Timer dispatch: Timer {
        interval: 12
        onTriggered: cache.pump()
    }

    property Timer operationDeadline: Timer {
        interval: 15000
        onTriggered: {
            if (worker.running) worker.running = false;
            else cache.finish();
            if (cache.inFlight) killDeadline.restart();
        }
    }

    property Timer killDeadline: Timer {
        interval: 750
        onTriggered: {
            if (worker.running) worker.signal(9);
            else cache.finish();
        }
    }

    property Process worker: Process {
        onStarted: {
            if (cache.cancelled) { running = false; return; }
            write(JSON.stringify({ paths: cache.batch }) + "\n");
            stdinEnabled = false;
        }
        stdout: SplitParser { onRead: line => cache.accept(line) }
        stderr: StdioCollector { }
        onExited: cache.finish()
        onRunningChanged: if (!running && cache.inFlight) Qt.callLater(function() {
            if (!worker.running && cache.inFlight) cache.finish();
        })
    }
}
