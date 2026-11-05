pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

QtObject {
    id: service

    // Contents stay in memory. Only the user's DND choice is written to disk.
    readonly property bool dnd: saved.dnd
    property var entries: []
    readonly property int count: entries.length
    property int unreadCount: 0
    property var toast: null
    readonly property bool toastActive: toast !== null
    property bool blocked: false
    property bool centerOpen: false
    property bool toastHovered: false
    property string persistenceError: ""

    property var records: ({})
    property var queue: []
    property real toastDeadline: 0
    property real toastRemaining: 0
    property bool clearing: false
    signal centerRequested

    function key(notification) {
        return notification ? String(notification.id) : "";
    }
    function record(notification) {
        const value = records[key(notification)];
        return value && value.notification === notification ? value : null;
    }
    function timestamp(notification) {
        const value = record(notification);
        return value ? value.received : 0;
    }
    function recountUnread() {
        unreadCount = entries.reduce(function (total, notification) {
            const value = record(notification);
            return total + (value && value.unread ? 1 : 0);
        }, 0);
    }
    function markAllRead() {
        Object.keys(records).forEach(function (id) {
            records[id].unread = false;
        });
        recountUnread();
    }
    function setDnd(enabled) {
        if (saved.dnd === Boolean(enabled))
            return;
        saved.dnd = Boolean(enabled);
        stateFile.writeAdapter();
    }
    function requestCenter() {
        centerRequested();
    }

    function timeout(notification) {
        // Quickshell 0.3.2 exposes the raw DBus timeout in milliseconds.
        // Zero means no expiration; -1 requests the server's normal policy.
        const requested = Number(notification.expireTimeout);
        if (requested === 0)
            return 0;
        if (Number.isFinite(requested) && requested > 0)
            return Math.min(600000, Math.max(250, requested));
        return notification.urgency === NotificationUrgency.Critical ? 8000 : 5000;
    }
    function pauseCountdown() {
        if (toastTimer.running)
            toastRemaining = Math.max(1, toastDeadline - Date.now());
        toastTimer.stop();
    }
    function resumeCountdown() {
        toastTimer.stop();
        if (!toast || blocked || centerOpen || toastHovered || toastRemaining <= 0)
            return;
        toastDeadline = Date.now() + toastRemaining;
        toastTimer.interval = Math.max(1, Math.ceil(toastRemaining));
        toastTimer.start();
    }
    function expireTransient(notification) {
        const value = record(notification);
        if (!value || !notification.transient)
            return;
        // Notify's ID is inserted into the native map only after onNotification
        // returns. Defer closing so the native server can complete that step.
        Qt.callLater(function () {
            if (service.record(notification))
                notification.expire();
        });
    }
    function dropQueued(notification) {
        queue = queue.filter(function (item) {
            return item !== notification;
        });
    }
    function enqueue(notification, first) {
        if (!record(notification))
            return;
        dropQueued(notification);
        queue = first ? [notification].concat(queue) : queue.concat([notification]);
        while (queue.length > 8) {
            const discardIndex = first ? 1 : 0;
            const discarded = queue[discardIndex];
            queue = queue.filter(function (item, index) {
                return index !== discardIndex;
            });
            expireTransient(discarded);
        }
        scheduleNext();
    }
    function scheduleNext() {
        if (!toast && !blocked && !centerOpen && !dnd && queue.length && !nextToast.running)
            nextToast.start();
    }
    function showNext() {
        if (toast || blocked || centerOpen || dnd)
            return;
        while (queue.length) {
            const notification = queue[0];
            queue = queue.slice(1);
            const value = record(notification);
            if (!value)
                continue;
            toastRemaining = value.remaining >= 0 ? value.remaining : timeout(notification);
            value.remaining = -1;
            toast = notification;
            resumeCountdown();
            break;
        }
    }
    function releaseToast(expireTransientItem) {
        pauseCountdown();
        const previous = toast;
        toast = null;
        toastRemaining = 0;
        toastDeadline = 0;
        if (expireTransientItem && previous)
            expireTransient(previous);
        scheduleNext();
    }
    function hideToast() {
        releaseToast(true);
    }
    function silenceToasts() {
        nextToast.stop();
        const pending = queue;
        queue = [];
        releaseToast(true);
        pending.forEach(expireTransient);
    }
    function dismiss(notification) {
        if (record(notification))
            notification.dismiss();
    }
    function clearAll() {
        clearing = true;
        nextToast.stop();
        const notifications = Object.keys(records).map(function (id) {
            return records[id].notification;
        });
        queue = [];
        releaseToast(false);
        notifications.forEach(dismiss);
        clearing = false;
    }
    function invoke(notification, action) {
        if (!record(notification) || !action || notification.actions.indexOf(action) < 0)
            return false;
        record(notification).unread = false;
        recountUnread();
        action.invoke();
        if (record(notification)) {
            if (toast === notification)
                hideToast();
            dropQueued(notification);
        }
        return true;
    }
    function reply(notification, text) {
        if (!record(notification) || !notification.hasInlineReply || !String(text).trim())
            return false;
        record(notification).unread = false;
        recountUnread();
        notification.sendInlineReply(String(text));
        if (record(notification)) {
            if (toast === notification)
                hideToast();
            dropQueued(notification);
        }
        return true;
    }
    function received(notification) {
        notification.tracked = true;
        if (record(notification)) {
            updated(notification);
            return;
        }
        const value = {
            notification: notification,
            received: Date.now(),
            unread: !notification.lastGeneration && !centerOpen && !notification.transient,
            remaining: -1,
            observer: observerFactory.createObject(service, {
                notification: notification
            })
        };
        records[key(notification)] = value;
        if (!notification.transient) {
            // The native reload re-emits oldest first, so prepending retains
            // the same newest-first order without writing notification data.
            entries = [notification].concat(entries);
            while (entries.length > 100)
                dismiss(entries[entries.length - 1]);
        }
        recountUnread();
        if (notification.lastGeneration || centerOpen || dnd) {
            expireTransient(notification);
            return;
        }
        enqueue(notification, false);
    }
    function updated(notification) {
        const value = record(notification);
        if (!value)
            return;
        value.received = Date.now();
        value.unread = !centerOpen && !notification.transient;
        value.remaining = -1;
        entries = entries.filter(function (item) {
            return item !== notification;
        });
        if (!notification.transient)
            entries = [notification].concat(entries);
        while (entries.length > 100)
            dismiss(entries[entries.length - 1]);
        recountUnread();
        if (centerOpen || dnd) {
            dropQueued(notification);
            if (toast === notification)
                hideToast();
            expireTransient(notification);
        } else if (toast === notification) {
            toastRemaining = timeout(notification);
            resumeCountdown();
        } else
            enqueue(notification, false);
    }
    function removed(notification) {
        const value = record(notification);
        if (!value)
            return;
        delete records[key(notification)];
        dropQueued(notification);
        entries = entries.filter(function (item) {
            return item !== notification;
        });
        if (toast === notification)
            releaseToast(false);
        recountUnread();
        value.observer.notification = null;
        value.observer.destroy();
        if (!clearing)
            scheduleNext();
    }

    onDndChanged: if (dnd)
        silenceToasts()
    onCenterOpenChanged: {
        if (centerOpen) {
            markAllRead();
            silenceToasts();
        } else
            scheduleNext();
    }
    onBlockedChanged: {
        if (blocked) {
            nextToast.stop();
            if (toast) {
                const previous = toast;
                pauseCountdown();
                const value = record(previous);
                if (value)
                    value.remaining = toastRemaining;
                releaseToast(false);
                enqueue(previous, true);
            }
        } else
            scheduleNext();
    }
    onToastHoveredChanged: {
        if (toastHovered)
            pauseCountdown();
        else
            resumeCountdown();
    }
    Component.onCompleted: stateFile.text()

    property Timer toastTimer: Timer {
        onTriggered: service.hideToast()
    }
    // One small gap allows close/morph animations and native close signals to
    // unwind before the next notification replaces the current one.
    property Timer nextToast: Timer {
        interval: 60
        onTriggered: service.showNext()
    }

    property Component observerFactory: Component {
        QtObject {
            id: observer
            property var notification: null
            property bool updateScheduled: false
            function changed() {
                if (updateScheduled || !notification)
                    return;
                updateScheduled = true;
                Qt.callLater(function () {
                    if (!observer)
                        return;
                    observer.updateScheduled = false;
                    if (observer.notification)
                        service.updated(observer.notification);
                });
            }
            property Connections connection: Connections {
                target: observer.notification
                function onClosed(reason) {
                    service.removed(observer.notification);
                }
                function onSummaryChanged() {
                    observer.changed();
                }
                function onBodyChanged() {
                    observer.changed();
                }
                function onAppNameChanged() {
                    observer.changed();
                }
                function onAppIconChanged() {
                    observer.changed();
                }
                function onImageChanged() {
                    observer.changed();
                }
                function onActionsChanged() {
                    observer.changed();
                }
                function onExpireTimeoutChanged() {
                    observer.changed();
                }
                function onUrgencyChanged() {
                    observer.changed();
                }
                function onTransientChanged() {
                    observer.changed();
                }
            }
        }
    }
    property NotificationServer server: NotificationServer {
        keepOnReload: true
        persistenceSupported: true
        actionsSupported: true
        imageSupported: true
        bodySupported: true
        bodyMarkupSupported: false
        bodyHyperlinksSupported: false
        bodyImagesSupported: false
        actionIconsSupported: false
        inlineReplySupported: true
        onNotification: function (notification) {
            service.received(notification);
        }
    }
    property FileView stateFile: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/Notifications/state.json"
        blockLoading: true
        blockWrites: true
        printErrors: false
        onSaveFailed: function (error) {
            service.persistenceError = "Do not disturb could not be saved.";
        }
        onSaved: service.persistenceError = ""
        JsonAdapter {
            id: saved
            property bool dnd: false
        }
    }
}
