import QtQuick

Image {
    id: preview

    required property string filePath
    required property url originalSource
    property string fileRevision: ""
    property bool previewsActive: true
    property string heldPath: ""
    property string heldRevision: ""
    property string retriedSource: ""
    property bool initialized: false
    readonly property var entry: Cache.entries[filePath] || null
    readonly property string thumbnail: entry ? entry.source : ""
    readonly property int previewStatus: !previewsActive ? Image.Null
        : source.toString() === "" ? Image.Loading : status

    source: !previewsActive ? "" : thumbnail || (entry && entry.failed ? originalSource : "")
    sourceSize.width: 528
    sourceSize.height: 352
    asynchronous: true
    autoTransform: true
    cache: thumbnail !== ""
    fillMode: Image.PreserveAspectCrop

    function synchronize() {
        // Declarative property bindings can fire before internal state has
        // finished initializing. Subscribe only once construction is complete.
        if (!initialized) return;
        const next = previewsActive ? filePath : "";
        if (heldPath === next && heldRevision === fileRevision) return;
        if (heldPath) Cache.release(heldPath);
        heldPath = "";
        heldRevision = fileRevision;
        retriedSource = "";
        if (next && Cache.acquire(next, fileRevision)) heldPath = next;
    }

    onFilePathChanged: synchronize()
    onFileRevisionChanged: synchronize()
    onPreviewsActiveChanged: synchronize()
    Component.onCompleted: { initialized = true; synchronize(); }
    Component.onDestruction: if (heldPath) Cache.release(heldPath)
    onStatusChanged: {
        if (status !== Image.Error || !thumbnail) return;
        // A bounded disk cache may have evicted this URL while it was hidden.
        // Recreate it once; a persistent decoder error falls back to the original.
        if (retriedSource !== thumbnail) {
            retriedSource = thumbnail;
            Cache.retry(filePath, thumbnail);
        } else {
            Cache.setEntry(filePath, "", true);
        }
    }
}
