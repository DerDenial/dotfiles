---------------------
---- MY PROGRAMS ----
---------------------

-- Set programs that you use
local terminal    = "kitty"
local fileManager = "nautilus --new-window"
local menu        = "qs ipc call appLauncher toggle"
local nc          = "qs ipc call notificationCenter toggle"

---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

local showDesktop = require("modules.show-desktop")
hl.bind(mainMod .. " + D", showDesktop.toggle, { description = "Show desktop / restore windows" })

hl.bind("Print", hl.dsp.exec_cmd("qs ipc call screenshotEditor capture"), { description = "Capture and edit region" })

-- Example binds, see https://wiki.hypr.land/Configuring/Basics/Binds/ for more
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal), { description = "Terminal" })
hl.bind(mainMod .. " + W", hl.dsp.window.close(), { description = "Close window" })
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("python3 ~/.config/quickshell/Logout/launch.py"), { description = "Log out" })
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd("qs ipc call powerMenu toggle"), { description = "Power menu" })
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager), { description = "File manager" })
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle floating" })
hl.bind(mainMod .. " + ALT + V", hl.dsp.exec_cmd("qs ipc call clipboardHistory toggle"), { description = "Clipboard history" })
hl.bind(mainMod .. " + Space", hl.dsp.exec_cmd(menu), { description = "App launcher" })
hl.bind(mainMod .. " + Tab", hl.dsp.exec_cmd("qs ipc call windowBar toggle"), { description = "Open windows" })
hl.bind(mainMod .. " + period", hl.dsp.exec_cmd("qs ipc call emojiPicker toggle"), { description = "Emoji picker" })
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(nc), { description = "Notifications" })
hl.bind(mainMod .. " + I", hl.dsp.exec_cmd("qs ipc call settingsApp toggle"), { description = "Settings" })
hl.bind("CTRL + SHIFT + Escape", hl.dsp.exec_cmd("qs ipc call taskManager toggle"), { description = "Task Manager" })
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("python3 ~/.config/quickshell/LockScreen/lock.py"), { description = "Lock screen" })
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("qs ipc call quickNotes toggle"), { description = "Quick notes" })
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd("qs ipc call quickSettings toggle"), { description = "Quick settings" })
hl.bind(mainMod .. " + H", hl.dsp.exec_cmd("qs ipc call hardwarePanel toggle"), { description = "Hardware monitor" })
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.exec_cmd("qs ipc call networkPanel toggle"), { description = "Live network traffic" })
hl.bind(mainMod .. " + ALT + S", hl.dsp.exec_cmd("qs ipc call speedTest toggle"), { description = "Internet speed test" })
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("qs ipc call themeSwitcher randomWallpaper"), { description = "Random wallpaper from current theme" })
hl.bind(mainMod .. " + SHIFT + T", hl.dsp.exec_cmd("qs ipc call themeSwitcher toggle"), { description = "Themes & wallpapers" })
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo(), { description = "Toggle pseudo tiling" })
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"), { description = "Toggle split · dwindle" }) -- dwindle only

-- Expand the focused column, then enter edge-to-edge mode below the taskbar.
local edgeMode = require("modules.edge-mode")
hl.bind(mainMod .. " + left",  edgeMode.left, { description = "Focus left / previous fullscreen window" })
hl.bind(mainMod .. " + right", edgeMode.right, { description = "Focus right / next fullscreen window" })
hl.bind(mainMod .. " + up", edgeMode.up, { description = "Expand column / edge-to-edge taskbar" })
hl.bind(mainMod .. " + down", edgeMode.down, { description = "Restore normal column and notch" })

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,             hl.dsp.focus({ workspace = i}), { description = "Workspace " .. tostring(i) })
    hl.bind(mainMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i }), { description = "Move window to workspace " .. tostring(i) })
end

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"), { description = "Toggle scratchpad" })
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }), { description = "Move window to scratchpad" })

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { description = "Next workspace" })
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }), { description = "Previous workspace" })

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true, description = "Move window · drag" })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window · drag" })

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true, description = "Volume up" })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true, description = "Volume down" })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true, description = "Mute sound" })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true, description = "Mute microphone" })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+ && qs ipc call notchOsd brightness"),                  { locked = true, repeating = true, description = "Brightness up" })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%- && qs ipc call notchOsd brightness"),                  { locked = true, repeating = true, description = "Brightness down" })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true, description = "Next track" })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, description = "Play / pause" })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, description = "Play / pause" })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true, description = "Previous track" })

-- Hold-to-peek shortcut guide; observers never consume normal shortcuts.
require("modules.hotkey-guide")
