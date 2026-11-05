import QtQuick

// Keep the surface/controller alive, release only its idle visual body.
Loader {
    id: loader
    required property bool engaged
    property int idleDelay: 10000
    property bool retained: false
    active: retained
    asynchronous: false

    function ensureLoaded() {
        releaseDelay.stop();
        retained = true;
        if (!engaged) releaseDelay.restart();
        return status === Loader.Ready && item !== null;
    }

    onEngagedChanged: {
        if (engaged) ensureLoaded();
        else if (retained) releaseDelay.restart();
    }

    Component.onCompleted: if (engaged) ensureLoaded()

    Timer {
        id: releaseDelay
        interval: loader.idleDelay
        onTriggered: if (!loader.engaged) loader.retained = false
    }
}
