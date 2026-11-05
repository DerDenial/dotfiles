-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

-- Read the cursor selected in Settings on every start and configuration reload.
local cursorConfig = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config"))
    .. "/quickshell/Settings/cursor-overrides.lua"
local cursorFile = io.open(cursorConfig, "r")
if cursorFile then
    cursorFile:close()
    dofile(cursorConfig)
else
    hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")
    hl.env("XCURSOR_SIZE", "24")
    hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Ice")
    hl.env("HYPRCURSOR_SIZE", "24")
end

---- TOOLKIT BACKEND ----
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("CLUTTER_BACKEND", "wayland")

---- XDG SPECIFICATION ----
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

---- QT ----
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
-- Use the GTK palette bridge so Qt apps follow the same desktop theme.
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")

-- Legacy GTK applications use the generated desktop palette.
hl.env("GTK2_RC_FILES", "/etc/gtk-2.0/gtkrc:" .. os.getenv("HOME") .. "/.config/gtk-2.0/gtkrc")
