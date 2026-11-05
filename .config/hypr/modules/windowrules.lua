--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

-- Example window rules that are useful

-- Task Manager is a movable, resizable companion window.
hl.window_rule({
    name = "quickshell-task-manager",
    match = { title = "^Quickshell Task Manager$" },
    float = true,
    center = true,
})

local suppressMaximizeRule = hl.window_rule({
    -- Ignore maximize requests from all apps. You'll probably like this.
    name           = "suppress-maximize-events",
    match          = { class = ".*" },

    suppress_event = "maximize",
})
-- suppressMaximizeRule:set_enabled(false)

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name     = "fix-xwayland-drags",
    match    = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

hl.layer_rule({
    name = "rofi-dropdown",
    match = { namespace = "rofi" },
    animation = "fade in",
    dim_around = true
})

hl.layer_rule ({
    name = "notification-animation",
    match = { namespace = "swaync-control-center"},
    animation = "slide right",
    blur = true,
    ignore_alpha = 0.05
})

hl.layer_rule({
    name = "notification-toast-blur",
    match = { namespace = "swaync-notification-window" },
    blur = true,
    ignore_alpha = 0.05,
})

-- Quickshell owns its surface morphs and waits for the first/last painted frame.
-- A second compositor fade would delay their response and their final handoff.
hl.layer_rule({
    name = "quickshell-owned-motion",
    match = { namespace = "quickshell" },
    no_anim = true,
})

-- The emoji picker uses the same Quickshell morph as the other notch menus.
hl.layer_rule({
    name = "emoji-picker-owned-motion",
    match = { namespace = "qs-emoji-picker" },
    no_anim = true,
})

-- The shortcut guide animates itself and keeps the desktop interactive.
hl.layer_rule({
    name = "hotkey-guide-glass",
    match = { namespace = "qs-hotkey-guide" },
    no_anim = true,
    blur = true,
    ignore_alpha = 0.05,
})

-- The floating window bar owns its slide and bounce animation.
hl.layer_rule({
    name = "window-hotbar-owned-motion",
    match = { namespace = "qs-window-hotbar" },
    no_anim = true,
    blur = true,
    ignore_alpha = 0.05,
})

-- The screenshot editor owns its preview/toolbar entrance and fade.
hl.layer_rule({
    name = "screenshot-editor-owned-motion",
    match = { namespace = "qs-screenshot-editor" },
    no_anim = true,
})

-- A screenshot freeze is a still image, presented without a compositor fade.
hl.layer_rule({
    name = "screenshot-freeze-still",
    match = { namespace = "^(hyprpicker|selection)$" },
    no_anim = true,
})
