# Notification service

`import "Notifications" as Notifications` exposes `Notifications.Service`.
The singleton owns the native Quickshell notification server. It replaces
SwayNC for new notifications; the packaged daemon cannot own the same DBus name
at the same time. Old SwayNC history cannot be imported through its public API.

- `entries` contains at most 100 live, actionable non-transient notifications,
  newest first. `count` and `unreadCount` summarize those entries.
- `timestamp(notification)` returns received/updated epoch milliseconds, or 0
  after removal. Reload carries native objects over without replaying previews;
  timestamps and read state reset on reload. A full process restart clears history.
- `toast`, `toastActive`, `toastHovered` expose the current preview. Hover pauses
  its remaining timeout. `hideToast()` hides a normal preview while retaining its
  history/actions; a transient preview expires instead.
- `blocked` pauses the current preview and queues at most eight previews while
  another menu/hover/transition owns the surface. It does not remove history.
- `centerOpen` marks history read and suppresses queued/incoming previews while
  the center is open. `markAllRead()` can also be called explicitly.
- `setDnd(bool)` changes DND immediately and writes only `{ "dnd": boolean }` to
  `~/.config/quickshell/Notifications/state.json`. `persistenceError` reports save
  failure. DND suppresses all previews, including critical ones; ordinary history
  remains available. Suppressed/dropped transient notifications expire.
- `dismiss(notification)`, `clearAll()`, `invoke(notification, action)` and
  `reply(notification, text)` delegate to the live native object. Foreign/stale
  actions and empty/unsupported replies are rejected. Resident objects remain
  actionable after invocation. No application command is constructed from text.
- `requestCenter()` emits `centerRequested()` for the root surface to handle.

Only DND is stored on disk. No notification text, image, title, action or history
is persisted. No additional daemon, disk history, shell polling or idle worker is
introduced. Observers are removed when notifications close. Preview expiry does
not discard ordinary native objects, preserving their actions in history.

Quickshell 0.3.2 exposes the raw DBus `expire_timeout` in milliseconds despite its
API documentation saying seconds. Positive values are bounded to 250–600000 ms,
zero does not expire, and default values use 5 s (8 s for critical). Replacements
update existing objects through their change signals and do not duplicate entries.
The native server's new-notification signal is not emitted again on replacement.

Validation:

- `python3 tests/backend/run.py`: 21 native Qt checks with inert notification,
  action and storage mocks; covers queue/history bounds, DND, hover pause,
  replacement/closure races, transient conversion, history preservation,
  inline replies and foreign action rejection.
- `python3 tests/backend/native-api.py`: two offscreen Quickshell processes parse
  the actual NotificationServer/FileView types and verify DND persistence using a
  temporary file. `DBUS_SESSION_BUS_ADDRESS` points to a nonexistent private path.
- A real private `dbus-run-session` could not start because this environment
  rejects binding even a fresh `/tmp/dbus-*` socket. Native Notify/ActionInvoked
  delivery has therefore not been exercised; no real desktop bus or notification
  was used during validation.

API behavior checked against the installed QML type metadata and official source:
https://github.com/quickshell-mirror/quickshell/blob/v0.3.2/src/services/notifications/server.cpp
https://github.com/quickshell-mirror/quickshell/blob/v0.3.2/src/services/notifications/notification.cpp
https://github.com/ErikReider/SwayNotificationCenter/blob/v0.12.6/src/swayncDaemon/swayncDaemon.vala
