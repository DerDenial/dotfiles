# Emoji picker backend contract

Dependencies: Python 3 standard library, the existing Hyprland 0.56 session and
`wl-copy` from wl-clipboard. No typing daemon, clipboard reader, shell command
interpolation, or extra service is involved.

The root `EmojiPicker.qml` should use process argument arrays directly. Keep
all target metadata in memory. Never save the target object in configuration,
history, or logs. It intentionally omits window titles and document content.

## Commands

Every command writes exactly one compact JSON object to stdout. Exit status is
zero on a handled success and one on failure. Expected failure messages are
safe to display. An emoji copied successfully can have `inserted:false` and
still returns zero: the UI should display `message` if present.

### `python3 Emoji/backend.py capture`

Run and await this **before mapping or focusing the picker**. Returns:

```json
{"ok":true,"target":{"address":"0x...","pid":123,"class":"kitty","initialClass":"kitty","workspace":1,"instance":"...","stableId":"..."}}
```

`target:null` means no normal app window is focused, such as on the desktop.
The picker can still open and copy an emoji, but it will not paste anywhere.
The object is opaque to the UI; pass it unchanged to `insert`.

### `python3 Emoji/backend.py catalog`

Returns `{"ok":true,"emojis":[...]}` with the entries from `emojis.json`. The
catalog may be a top level list or `{"emojis":[...]}`. Entry `emoji` values
and values in their nested `variants` lists form the insertion allowlist.
Complete ZWJ, flag, variation-selector, and skin-tone sequences are preserved.

### `python3 Emoji/backend.py recents`

Returns `{"ok":true,"recents":["😀","🎉"]}`, most recently selected first.
Up to 48 unique catalog emojis are stored. UI maps strings back to catalog
entries and ignores any no longer present.

### `python3 Emoji/backend.py insert --request JSON`

The single argument is `JSON.stringify({emoji: selectedEmoji, target: capturedTarget})`.
When `--request` is omitted a bounded JSON request can instead be read from stdin.
Never interpolate it into shell text.

For a picker that stays open for several insertions:

1. Ignore further selections while an insertion is pending.
2. Keep the surface visible, set `WlrLayershell.keyboardFocus` to `None` and
   await the real underlying `QWindow.active == false` notification.
3. Start `insert` with `JSON.stringify({emoji, target, keepOpen:true,
   inputReleased:true})` only after that acknowledgement. A bounded watchdog
   can report a handoff failure; it must never treat elapsed time as success.
4. The helper checks the exact original app is still active and targets that
   app directly. It skips the unmapped-namespace check in this explicit mode.
5. After the result, re-arm keyboard focus only if the picker is still open.
   Esc or outside-click closure must never be undone by a late result.

`keepOpen:true` with absent/false `inputReleased` fails before copying or sending
keys. This flag is an acknowledgement from the trusted root QML controller,
not a replacement for actually releasing input. No cursor-warping focus
dispatcher is used in multi-insert mode.

Alternatively, for a picker that closes on selection:

1. Ignore further selections while an insertion is pending.
2. Release exclusive keyboard focus immediately and close the picker.
3. Wait for the picker surface to be **unmapped** (`visible:false`, after its
   close transition if desired), then start the insertion process.
4. Use the layer namespace **`qs-emoji-picker`**. The backend also checks for
   its disappearance, waiting only while it remains mapped, for at most 0.9s.
5. Clear the in-memory target and request when done or cancelled.

Example successful result:

```json
{"ok":true,"copied":true,"inserted":true,"recents":["😀"]}
```

The backend waits for `wl-copy` to own the new clipboard before pasting.
Then it verifies the original Hyprland session, stable window ID, address,
process ID, classes and workspace. An intervening different focused app,
closed/moved target, locked session or still mapped picker in closing mode
aborts pasting.
The selected emoji remains on the clipboard with a useful message instead.
It never pastes into whichever app happens to be focused.

In closing mode focus is restored to the exact validated window and checked
again; multi-insert mode requires the original app already active after the
input handoff. The paste shortcut is addressed specifically to that window.
Kitty, Alacritty, WezTerm
and Foot use Ctrl+Shift+V; other apps use Ctrl+V. As with ordinary paste,
the original app must have a text field ready and support pasting. The helper
can confirm shortcut delivery, not whether the app inserted visible text.
The V key uses XKB code 55 (Linux KEY_V + 8) on the configured German keyboard,
avoiding current Shift/Caps state affecting keysym lookup.

## Storage and privacy

Only selected emoji strings are saved in
`$XDG_STATE_HOME/quickshell-emoji/recents.json` (default
`~/.local/state/quickshell-emoji/recents.json`). Directory mode is 0700, files
0600, writes atomic and serialized. No timestamps, app/window metadata,
existing clipboard content, typed text, or document contents are persisted.
Do not include this state directory in a public dotfiles export.

The short-lived insertion lock is in `$XDG_RUNTIME_DIR`. It prevents rapid
duplicate invocations from racing clipboard ownership and paste shortcuts.

## API sources reviewed

- Installed package metadata: Hyprland 0.56.2-4, wl-clipboard 2.3.0-1.
- [Official Hyprland IPC protocol](https://wiki.hypr.land/IPC/).
- [Hyprland v0.56.2 legacy dispatcher translator](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/config/legacy/DispatcherTranslator.cpp):
  addressed `focuswindow` and `sendshortcut` remain supported.
- [Hyprland v0.56.2 HyprCtl](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/debug/HyprCtl.cpp):
  JSON stable window IDs, layer namespace/alpha and locked-session queries.
- [Hyprland v0.56.2 input actions](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/config/shared/actions/ConfigActions.cpp):
  the addressed shortcut temporarily targets the chosen app surface, sends
  complete modifier/key events, then restores the prior surface.

No runtime insertion, clipboard mutation, app launch, or key injection was
performed during implementation; only source and syntax inspection.
