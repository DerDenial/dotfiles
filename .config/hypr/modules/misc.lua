----------------
----  MISC  ----
----------------

local paletteOk, desktopPalette = pcall(dofile, os.getenv("HOME") .. "/.config/hypr/modules/theme-colors.lua")
if not paletteOk or type(desktopPalette) ~= "table" then desktopPalette = {} end

hl.config({
    misc = {
        force_default_wallpaper = 0,    -- Set to 0 or 1 to disable the anime mascot wallpapers
        disable_hyprland_logo   = true, -- If true disables the random hyprland logo / anime girl background. :(
        disable_splash_rendering = true,
        background_color = desktopPalette.background_color or "rgb(111111)",
        font_family = "Inter",
    },
})
