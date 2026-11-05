# Shortcut catalogue

Run `python3 catalog.py` when opening the overview. It prints one JSON object and
exits. It has no daemon, shell invocation, persistent cache or storage writes.

## UI contract

```json
{
  "ok": true,
  "source": "hyprland",
  "sourceLabel": "Live keybindings",
  "notice": "",
  "count": 31,
  "bindingCount": 55,
  "groups": [
    {
      "id": "apps",
      "title": "Apps & tools",
      "icon": "apps",
      "entries": [
        {
          "id": "stable-friendly-text-hash",
          "keys": ["Super", "Space"],
          "label": "App launcher",
          "hint": "",
          "search": "app launcher super space",
          "bindingCount": 1
        }
      ]
    }
  ]
}
```

The example counts are illustrative. `count` is the number of visible rows;
`bindingCount` is the number of underlying bindings represented. Group IDs are
`apps`, `windows`, `workspaces`, and `system`; empty groups are omitted. `keys`
contains separate keycap labels in display order. `hint` may describe a submap,
release binding, hold or mouse drag. QML should render text as plain text. Search
can filter the casefolded `search` field or recompute from labels and keycaps.

An error returns `ok: false`, `groups: []`, zero counts, and a friendly `error`.
The process still exits normally so the UI can display that state.

## Authority and fallback

The default source is the session's documented UNIX IPC socket using `j/binds`.
The reply is bounded to 2 MiB/2048 bindings, with a 0.8 second socket timeout.
The socket must belong to the current user. No window, clipboard or app history
queries are used. No dispatches, Lua evaluation, subprocesses or reloads occur.

Hyprland 0.56 registers Lua callbacks with the opaque dispatcher `__lua` and a
registry reference. Its JSON cannot describe these functions. Existing explicit
descriptions are preferred. Otherwise, a name may be enriched by an unambiguous
exact combination/modifier/submap/release/hold match in the current
`hypr/modules/binds.lua`. The current configuration name can differ if edited
without a reload, but live IPC remains authoritative about which combinations
are actually present. Unknown callbacks display `Custom action`.

If IPC is unavailable, the safe static reader supplies only recognised literal
`hl.bind` declarations, with `source: "config"`,
`sourceLabel: "From configuration"`, and a prominent `notice` that the active
session may differ. It reads at most 512 KiB. It lexes quoted strings/comments,
simple literal local constants, concatenations and bounded numeric workspace
loops. It never evaluates Lua, imports, expressions, functions or commands.
It does not follow other modules or claim to support arbitrary Lua control flow.

Only complete matching 1–10 workspace series, verified arrow/media pairs and
verified workspace scroll pairs are collapsed. Partial sets remain individual
rows. Binding parameters, paths, session signatures and opaque callback IDs are
never included in the JSON or logs. Known command names are mapped to friendly
actions; unknown commands expose at most a simple executable name.

## Source references

- [Hyprland IPC](https://wiki.hypr.land/IPC/)
- [Hyprland 0.56 JSON binds response](https://github.com/hyprwm/Hyprland/blob/v0.56.0/src/debug/HyprCtl.cpp#L948)
- [Lua binding registration](https://github.com/hyprwm/Hyprland/blob/v0.56.0/src/config/lua/bindings/LuaBindingsToplevel.cpp#L122)

The helper is only read on demand. Its output should not be persisted by the UI.
