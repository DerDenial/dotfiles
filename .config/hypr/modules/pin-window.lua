-- Native Hyprland pinning follows workspaces on the window's monitor.
-- Loaded by the Lua configuration or hyprctl eval. Loading only registers a
-- disabled rule and event hooks; it dispatches no window actions or timers.
local pinWindow = {}
local managedTag = "qs-pin-managed"
local tiledTag = "qs-pin-tiled"
local edgeTag = "qs-edge"
local managed = {}
local settleTimer
local raising = false
-- Native alter_zorder simulates pointer motion. The pointer may be over any
-- window, not just the pin being raised, so guard every window for this one
-- synchronous operation. Ordinary mouse hover keeps working immediately after.
local raiseRule = hl.window_rule({
    name = "quickshell-pin-raise-focus-guard",
    enabled = false,
    match = { class = ".*" },
    no_follow_mouse = true,
})

local function hasTag(window, tag)
    for _, value in ipairs(window.tags or {}) do
        if tostring(value):gsub("%*$", "") == tag then return true end
    end
    return false
end

local function dispatch(name, options)
    local result = hl.dispatch(hl.dsp.window[name](options))
    if type(result) ~= "table" or result.ok ~= true then
        error("Window pin: " .. tostring(type(result) == "table" and result.error or "action failed"), 0)
    end
end

local function tag(window, name, enabled)
    if hasTag(window, name) ~= enabled then
        dispatch("tag", { window = window, tag = (enabled and "+" or "-") .. name })
    end
end

local function raiseWithoutFocus(window)
    raiseRule:set_enabled(true)
    local ok, result = pcall(dispatch, "alter_zorder", { window = window, mode = "top" })
    raiseRule:set_enabled(false)
    if not ok then error(tostring(result), 0) end
end

local function remember(window)
    if window.address then managed[window.address] = window end
end

local function isManagedPin(window)
    return window.mapped and window.pinned and window.floating and hasTag(window, managedTag)
end

local function discover()
    managed = {}
    for _, window in ipairs(hl.get_windows({ tag = managedTag })) do
        if window.mapped and hasTag(window, managedTag) then remember(window) end
    end
end

local function raiseManaged()
    raising = true
    local ordered = {}
    for address, window in pairs(managed) do
        if not window.mapped or not hasTag(window, managedTag) then
            managed[address] = nil
        elseif isManagedPin(window) and window.visible and not window.hidden and window.fullscreen == 0 then
            ordered[#ordered + 1] = window
        end
    end
    table.sort(ordered, function(a, b)
        -- Keep the active pinned window above other pinned windows without
        -- changing input focus or the order of unrelated windows.
        if a.active ~= b.active then return not a.active end
        return a.address < b.address
    end)
    for _, window in ipairs(ordered) do
        -- A stale/dead window must not break future raises or leave the
        -- temporary focus guard enabled.
        pcall(raiseWithoutFocus, window)
    end
    raising = false
end

local function scheduleRaise()
    if raising then return end
    local wanted = false
    for address, window in pairs(managed) do
        if not window.mapped or not hasTag(window, managedTag) then
            managed[address] = nil
        elseif isManagedPin(window) then
            wanted = true
        end
    end
    if not wanted then return end
    if settleTimer then
        settleTimer:set_timeout(10)
    else
        -- Dormant between events. No timers are allocated while verifying or
        -- parsing configuration, nor when no managed window is pinned.
        settleTimer = hl.timer(function()
            settleTimer:set_enabled(false)
            raiseManaged()
        end, { timeout = 10, type = "repeat" })
    end
end

local function leaveFullscreen(window)
    if (tonumber(window.fullscreen) or 0) ~= 0 or (tonumber(window.fullscreen_client) or 0) ~= 0 then
        dispatch("fullscreen_state", {
            window = window, internal = 0, client = 0, action = "set", layout_aware = false,
        })
    end
    -- The existing edge-mode watcher restores its workspace gaps and shell bar
    -- after this tag disappears. Its window rule also releases border/shadow overrides.
    tag(window, edgeTag, false)
end

local function resolve(selector)
    local digits = type(selector) == "string" and selector:match("^address:0x([%da-fA-F]+)$")
    if not digits or #digits > 16 or not digits:find("[1-9a-fA-F]") then
        error("Window pin: invalid window address", 0)
    end

    local window = hl.get_window(selector)
    if not window or not window.mapped then error("Window pin: window is no longer available", 0) end
    if type(window.floating) ~= "boolean" or type(window.pinned) ~= "boolean" then
        error("Window pin: unavailable window state", 0)
    end
    return window
end

function pinWindow.toggle(selector)
    local window = resolve(selector)

    if window.pinned then
        -- Restore tiling only when this tool originally changed a tiled window.
        -- Manually/external pinned windows retain their floating layout.
        local restoreTiling = hasTag(window, managedTag) and hasTag(window, tiledTag)
        local wasManaged, wasTiled = hasTag(window, managedTag), hasTag(window, tiledTag)
        local wasEdge = hasTag(window, edgeTag)
        local oldFullscreen, oldClient = tonumber(window.fullscreen) or 0, tonumber(window.fullscreen_client) or 0
        local ok, reason = pcall(function()
            leaveFullscreen(window)
            dispatch("pin", { window = window, action = "unset" })
            if window.pinned then error("Window pin: window could not be unpinned", 0) end
            if restoreTiling and window.floating then
                dispatch("float", { window = window, action = "unset" })
                if window.floating then error("Window pin: tiling could not be restored", 0) end
            end
            tag(window, tiledTag, false)
            tag(window, managedTag, false)
        end)
        if not ok then
            pcall(function()
                if not window.floating then dispatch("float", { window = window, action = "set" }) end
                tag(window, managedTag, wasManaged)
                tag(window, tiledTag, wasTiled)
                if not window.pinned then dispatch("pin", { window = window, action = "set" }) end
                tag(window, edgeTag, wasEdge)
                if oldFullscreen ~= 0 or oldClient ~= 0 then
                    dispatch("fullscreen_state", {
                        window = window, internal = oldFullscreen, client = oldClient,
                        action = "set", layout_aware = false,
                    })
                end
            end)
            error(tostring(reason), 0)
        end
        managed[window.address] = nil
        return
    end

    local wasFloating = window.floating
    local wasManaged = hasTag(window, managedTag)
    local wasTiled = hasTag(window, tiledTag)
    local oldFullscreen = tonumber(window.fullscreen) or 0
    local oldClient = tonumber(window.fullscreen_client) or 0
    local wasEdge = hasTag(window, edgeTag)
    local ok, reason = pcall(function()
        leaveFullscreen(window)
        if not window.floating then dispatch("float", { window = window, action = "set" }) end
        if not window.floating then error("Window pin: window could not be floated", 0) end
        tag(window, managedTag, true)
        tag(window, tiledTag, not wasFloating or (wasManaged and wasTiled))
        dispatch("pin", { window = window, action = "set" })
        if not window.pinned then error("Window pin: window could not be pinned", 0) end
        -- This is targeted; bring_to_top() would act on the focused window.
        raiseWithoutFocus(window)
        remember(window)
    end)
    if not ok then
        -- A failed action must not leave a formerly tiled window floating or
        -- claim that a native pin succeeded. Only this exact window is touched.
        pcall(function()
            if window.pinned then dispatch("pin", { window = window, action = "unset" }) end
            if not wasFloating and window.floating then dispatch("float", { window = window, action = "unset" }) end
            tag(window, tiledTag, wasTiled)
            tag(window, managedTag, wasManaged)
            tag(window, edgeTag, wasEdge)
            if oldFullscreen ~= 0 or oldClient ~= 0 then
                dispatch("fullscreen_state", {
                    window = window, internal = oldFullscreen, client = oldClient,
                    action = "set", layout_aware = false,
                })
            end
        end)
        error(tostring(reason), 0)
    end
end

function pinWindow.set(selector, wanted)
    if type(wanted) ~= "boolean" then error("Window pin: desired state must be a boolean", 0) end
    local window = resolve(selector)
    -- Explicit desired states make a delayed/double UI request idempotent.
    -- Existing native/user pins are not silently adopted as managed windows.
    if window.pinned == wanted then return end
    return pinWindow.toggle(selector)
end

for _, event in ipairs({
    "window.open", "window.active", "window.close", "window.destroy",
    "window.fullscreen", "window.move_to_workspace", "workspace.active",
    "workspace.special_active", "monitor.layout_changed",
}) do
    hl.on(event, scheduleRaise)
end

-- Super+D temporarily unpins windows; keep their durable origin tags and
-- tracked references so returning from the desktop restores the same pin.
-- Native userdata are weak references and do not keep closed windows alive.
discover()
hl.on("config.reloaded", discover)
hl.on("hyprland.shutdown", function()
    if settleTimer then settleTimer:set_enabled(false) end
end)

return pinWindow
