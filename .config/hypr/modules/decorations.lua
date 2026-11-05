-----------------------
---- LOOK AND FEEL ----
-----------------------

-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/
local paletteOk, desktopPalette = pcall(dofile, os.getenv("HOME") .. "/.config/hypr/modules/theme-colors.lua")
if not paletteOk or type(desktopPalette) ~= "table" then
    desktopPalette = { active_border = "rgba(88888870)", inactive_border = "rgba(33333355)" }
end
hl.config({
    general = {
        gaps_in  = 8,
        gaps_out = { top = 6, right = 20, bottom = 20, left = 20 },

        border_size = 1,

        col = {
            active_border   = desktopPalette.active_border,
            inactive_border = desktopPalette.inactive_border,
        },

        -- Set to true to enable resizing windows by clicking and dragging on borders and gaps
        resize_on_border = false,

        -- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
        allow_tearing = false,
    },

    decoration = {
        rounding       = 10,
        rounding_power = 2,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = { enabled = false },

        blur = {
            enabled   = true,
            size      = 20,
            passes    = 3,
            vibrancy  = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },
})

-- Default curves and animations, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })
hl.curve("easeInOutQuart", { type = "bezier", points = { {0.76, 0},    {0.24, 1}    } })

-- A faster spring keeps a small opening bounce; layout movement settles without overshoot.
hl.curve("windowSnap",     { type = "spring", mass = 1, stiffness = 500, dampening = 35 })
hl.curve("windowFlow",     { type = "bezier", points = { {0.16, 1}, {0.30, 1} } })

hl.animation({ leaf = "global",        enabled = true,  speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true,  speed = 3.39, bezier = "quick" })
hl.animation({ leaf = "windows",       enabled = true,  speed = 2.6,  bezier = "windowFlow" })
hl.animation({ leaf = "windowsMove",   enabled = true,  speed = 2.6,  bezier = "windowFlow" })
hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 2.8,  spring = "windowSnap",  style = "popin 94%" })
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 1.6,  bezier = "windowFlow",   style = "popin 96%" })
hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 1.6,  bezier = "windowFlow" })
hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true,  speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true,  speed = 3.81, bezier = "easeInOutQuart" })
hl.animation({ leaf = "layersIn",      enabled = true,  speed = 4,    bezier = "easeInOutQuart", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true,  speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true,  speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = true,  speed = 7,    bezier = "quick" })
