---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",

        follow_mouse = 1,

        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

        touchpad = {
            natural_scroll = true,
        },
    },
})

-- Three-finger horizontal swipe moves through columns in the scrolling layout.
hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "scroll_move",
})

-- Keep horizontal workspace switching available with four fingers.
hl.gesture({
    fingers = 4,
    direction = "horizontal",
    action = "workspace",
})

-- Vertical three-finger swipes open shell panels once the swipe completes.
-- Native gesture cancellation and shortcut inhibitors remain in effect.
hl.gesture({
    fingers = 3,
    direction = "up",
    action = function() hl.exec_cmd("qs ipc call windowBar open") end,
})
hl.gesture({
    fingers = 3,
    direction = "down",
    action = function() hl.exec_cmd("qs ipc call quickSettings open") end,
})

-- Add optional per-device rules here after checking the target device names.

-- Preferences changed in the Quickshell Settings app.
local qsInputPath = os.getenv("HOME") .. "/.config/quickshell/Settings/input-overrides.lua"
local qsInputFile = io.open(qsInputPath, "r")
if qsInputFile then
    qsInputFile:close()
    dofile(qsInputPath)
end
