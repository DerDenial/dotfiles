# Local quick notes

`store.py` is a Python standard library helper for the Quickshell notes UI. It has
no clipboard access, network calls, shell execution or package dependencies.

## Storage

The default storage directory is `~/.local/state/quickshell-notes`, or
`$XDG_STATE_HOME/quickshell-notes` when `XDG_STATE_HOME` is set. It must be an
absolute path. The final directory is private (`0700`) and SQLite/lock files are
private (`0600`). Existing foreign-owned, symlink or nonregular storage files are
rejected. SQLite uses WAL, full synchronous commits and a process lock to
serialize mutations. Note IDs are never reused after deletion.

Limits: 200 characters per title, 1 MiB of UTF-8 per note, 5,000 notes and 256 MiB
of combined note text. Plain text is preserved in the body. Empty titles are
displayed/stored as “Neue Notiz”. Titles are normalized to one line.

This is local storage, not encrypted storage. Deleted notes are removed from the
app, but secure deletion from filesystem snapshots or storage hardware is not
guaranteed.

## Protocol

Run with `python3 /absolute/path/to/Notes/store.py COMMAND`. One compact JSON
response is returned on stdout. Do not log stdout: note text and previews are
intended only for the local UI. There is no diagnostic logging.

Commands:

| Command | Input | Result |
| --- | --- | --- |
| `status` | none | `{ok, available, total, bytes, revision, maxNoteBytes, maxNotes}` |
| `list --query=<text> --limit=500` | none | Status fields, `count`, `notes`, `hasMore` |
| `get ID` | none | `{ok, note}` including the body |
| `create` | stdin JSON `{title, content}` | `{ok, note}` |
| `save ID` | stdin JSON `{title?, content?, expectedRevision?}` | `{ok, note, unchanged?}` |
| `delete ID` | stdin JSON `{expectedRevision?}` | `{ok, deletedId}` |

Each note has `id` (integer), `title`, `content`, `preview`, `created`, `updated`
(epoch milliseconds), `revision` (positive integer), and `size` (UTF-8 bytes).
List entries omit `content` and cap previews at 180 characters plus an ellipsis.
Lists sort by latest edit first. Search matches every whitespace-separated word
against the title and body, using Unicode case folding. The query is capped at
512 characters. Use the `--query=` form so a query beginning with a dash is text.
Default list size is 500; maximum is 1,000. `count` counts all matches while
`hasMore` indicates truncation.

For **every mutation**, write one JSON object to stdin and then close the write
channel. An empty delete payload is `{}`. Note content must never be interpolated
into a shell or passed as command arguments. Requests are bounded and expire if
the input writer never closes its channel.

Save supports partial updates. When fields are unchanged no new note/global
revision is created. Include `expectedRevision` when saving or deleting a note
read earlier. If it changed meanwhile, the request returns
`{ok:false,code:"CONFLICT",error,note}` with the current stored note. The UI should
keep the user's unsaved text and offer recovery; it must not silently replace it
with the conflicting version.

Other failures return `{ok:false,code,error}` and exit with code 1. Codes include
`INPUT`, `LIMIT`, `NOT_FOUND`, `VERSION` and `STORAGE`. These errors do not erase or
truncate the existing note. The UI must retain unsaved edits when a request fails.
