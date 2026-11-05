-- See https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/ for more
hl.config({
    general = {
        layout = "scrolling"
    },
    
    dwindle = {
        preserve_split = true, -- You probably want this
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Master-Layout/ for more
hl.config({
    master = {
        new_status = "master",
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/ for more
hl.config({
    scrolling = {
        fullscreen_on_one_column = true,
    },
})

-- Saved window preferences override the layout defaults after each reload.
local qsWindowsPath = os.getenv("HOME") .. "/.config/quickshell/Settings/window-overrides.lua"
local qsWindowsFile = io.open(qsWindowsPath, "r")
if qsWindowsFile then
    qsWindowsFile:close()
    dofile(qsWindowsPath)
end
