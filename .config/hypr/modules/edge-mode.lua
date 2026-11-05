-- Super + Up: expand a scrolling column (or maximize another tiled layout),
-- then fill the area below the bar. The window tag is the shell's durable state.
local edgeMode = {}
local tag = "qs-edge"
local gapRules = {}
local changing = false
local reconciling = false
local watching = false
local settleTimer
local pendingLayoutChange
local pendingOpens = {}

hl.window_rule({
    name = "quickshell-edge-window",
    match = { tag = tag, fullscreen_state_internal = 1 },
    border_size = 0,
    rounding = 0,
    no_shadow = true,
})

local function hasTag(window)
    if not window then return false end
    for _, value in ipairs(window.tags or {}) do
        if tostring(value):gsub("%*$", "") == tag then return true end
    end
    return false
end

local function isEdge(window)
    return hasTag(window) and window.mapped and not window.floating
        and window.fullscreen == 1 and window.fullscreen_handler == "default"
        and window.workspace and window.monitor
end

local function scopeSelector(workspace)
    if not workspace or not workspace.id then return nil end
    local id = tonumber(workspace.id)
    if id and id > 0 then
        -- A separate, equivalent selector keeps our toggleable rule independent
        -- of a user's ordinary `workspace = "1"` rule (identical strings merge).
        return "r[" .. tostring(id) .. "-" .. tostring(id) .. "] s[false]"
    end
    local name = workspace.config_name
    if not name or name == "" then return nil end
    -- Named/special IDs are negative, while r[] accepts only positive IDs.
    -- Selector matching trims whitespace; rule identity preserves it. This
    -- alias therefore matches exactly the same name without merging its rule.
    return name .. string.rep(" ", 17)
end

local function setGapRule(selector, enabled)
    local entry = gapRules[selector]
    if not entry then
        if not enabled then return end
        entry = {
            rule = hl.workspace_rule({
                workspace = selector,
                enabled = false,
                gaps_in = 0,
                gaps_out = 0,
                float_gaps = 0,
            }),
            enabled = false,
        }
        gapRules[selector] = entry
    end
    if entry.enabled ~= enabled then
        entry.rule:set_enabled(enabled)
        entry.enabled = enabled
    end
end

local function refreshShell()
    -- Fixed command, with no window title, address or workspace interpolated.
    hl.exec_cmd("qs ipc call edgeBar refresh >/dev/null 2>&1")
end

local function reconcile()
    if changing or reconciling then return end
    reconciling = true
    local wanted = {}
    for _, window in ipairs(hl.get_windows()) do
        if hasTag(window) then
            if isEdge(window) then
                local selector = scopeSelector(window.workspace)
                if selector then wanted[selector] = true end
            elseif window.mapped then
                -- F11, floating, or leaving maximized mode must not leave a
                -- normal window tagged/borderless or keep zero workspace gaps.
                hl.dispatch(hl.dsp.window.tag({ window = window, tag = "-" .. tag }))
            end
        end
    end
    for selector in pairs(wanted) do setGapRule(selector, true) end
    for selector in pairs(gapRules) do
        if not wanted[selector] then setGapRule(selector, false) end
    end
    watching = next(wanted) ~= nil
    reconciling = false
    refreshShell()
end

local function scheduleReconcile()
    -- Ordinary desktop activity has no timer or CLI process overhead until a
    -- managed window exists. The shell already follows workspace/focus events.
    if changing or reconciling or not watching then return end
    if settleTimer then
        -- In 0.56 set_timeout calls updateTimeout and rearms a disabled timer.
        settleTimer:set_timeout(25)
    else
        -- One reusable timer, dormant between events; no polling and no timer
        -- created while Hyprland is merely verifying the configuration.
        settleTimer = hl.timer(function()
            settleTimer:set_enabled(false)
            reconcile()
        end, { timeout = 25, type = "repeat" })
    end
end

local function resetColumn()
    local width = tonumber(hl.get_config("scrolling.column_width")) or 0.5
    width = math.max(0.1, math.min(1.0, width))
    hl.dispatch(hl.dsp.layout("colresize " .. tostring(width)))
    hl.dispatch(hl.dsp.layout("fit_into_view"))
end

local function checked(action)
    local result = hl.dispatch(action)
    if type(result) ~= "table" or result.ok ~= true then
        error("Window layout: " .. tostring(type(result) == "table" and result.error or "window action failed"), 0)
    end
end

local function isTiledCandidate(window)
    return window and window.mapped and not window.floating and not window.pinned
        and window.workspace and window.monitor
        and (window.fullscreen == 0
            or (window.fullscreen == 1 and window.fullscreen_handler == "default"))
end

local function rememberEdgeOwner(window)
    if changing or reconciling or not watching or pendingLayoutChange
        or not isTiledCandidate(window) or not window.address then return end
    local selector = scopeSelector(window.workspace)
    local monitor = window.monitor.name
    if not selector or not monitor then return end
    -- open_early runs before the compositor replaces/unmaximizes its old
    -- fullscreen owner. Snapshot a real edge window, never a stale tag.
    for _, source in ipairs(hl.get_windows()) do
        if source ~= window and isEdge(source) and not source.pinned
            and scopeSelector(source.workspace) == selector
            and source.monitor.name == monitor then
            pendingOpens[tostring(window.address)] = {
                window = window, source = source,
                selector = selector, monitor = monitor,
            }
            return
        end
    end
end

local function inheritEdgeMode(window)
    if not window or not window.address then return end
    local key = tostring(window.address)
    local pending = pendingOpens[key]
    pendingOpens[key] = nil
    if not pending or changing or reconciling or not watching or pendingLayoutChange then return end
    local source = pending.source
    -- open (openLate) runs after native mapping/focus/layout. Only the new
    -- focused tile may inherit; background windows and dialogs stay ordinary.
    if hl.get_active_window() ~= window or not isTiledCandidate(window)
        or not isTiledCandidate(source) or not hasTag(source)
        or scopeSelector(window.workspace) ~= pending.selector
        or scopeSelector(source.workspace) ~= pending.selector
        or window.monitor.name ~= pending.monitor or source.monitor.name ~= pending.monitor then
        return
    end
    local previousFullscreen = window.fullscreen
    local tagged, maximized = false, false
    changing = true
    local ok, reason = pcall(function()
        setGapRule(pending.selector, true)
        checked(hl.dsp.window.tag({ window = window, tag = "+" .. tag }))
        tagged = true
        checked(hl.dsp.window.fullscreen({
            window = window, mode = "maximized", action = "set", layout_aware = false,
        }))
        maximized = true
        checked(hl.dsp.window.tag({ window = source, tag = "-" .. tag }))
    end)
    if not ok then
        -- Restore the new tile's native state if any part of the handoff is
        -- rejected, then let reconciliation release invalid tags and gaps.
        if tagged then
            pcall(function()
                checked(hl.dsp.window.tag({ window = window, tag = "-" .. tag }))
            end)
        end
        if maximized and previousFullscreen == 0 and isTiledCandidate(window)
            and window.fullscreen == 1 then
            pcall(function()
                checked(hl.dsp.window.fullscreen({
                    window = window, mode = "maximized", action = "unset", layout_aware = false,
                }))
            end)
        end
        print("Quickshell edge handoff: " .. tostring(reason))
    end
    changing = false
    reconcile()
end

local function discardPending(window)
    for key, pending in pairs(pendingOpens) do
        if pending.window == window or pending.source == window then pendingOpens[key] = nil end
    end
end

local function navigationCandidate(window, selector, monitor)
    return isTiledCandidate(window) and not window.hidden
        and scopeSelector(window.workspace) == selector
        and window.monitor.name == monitor
end

local function navigationTarget(source, direction)
    local selector = scopeSelector(source.workspace)
    local monitor = source.monitor.name
    local candidates = {}
    local scrolling = true
    for index, window in ipairs(hl.get_windows()) do
        if navigationCandidate(window, selector, monitor) then
            local layout = window.layout
            local column = layout and layout.column
            local columnIndex = column and tonumber(column.index)
            local rowIndex = layout and tonumber(layout.index_in_column) or 0
            if not layout or layout.name ~= "scrolling" or not columnIndex
                or columnIndex ~= columnIndex or math.abs(columnIndex) == math.huge then
                scrolling = false
            end
            candidates[#candidates + 1] = {
                window = window, order = index, column = columnIndex,
                row = rowIndex and rowIndex == rowIndex and rowIndex or 0,
            }
        end
    end
    -- Maximized geometry covers the screen. The scrolling layout's own column
    -- and row indices retain the actual card order even while occluded.
    if scrolling then
        table.sort(candidates, function(a, b)
            if a.column ~= b.column then return a.column < b.column end
            if a.row ~= b.row then return a.row < b.row end
            return a.order < b.order
        end)
    end
    if #candidates < 2 then return nil end
    for index, entry in ipairs(candidates) do
        if entry.window == source then
            local step = direction == "left" and -1 or 1
            return candidates[((index - 1 + step) % #candidates) + 1].window
        end
    end
end

function edgeMode.focus(direction)
    if direction ~= "left" and direction ~= "right" then return end
    if changing or reconciling or pendingLayoutChange then return end
    local source = hl.get_active_window()
    if not isEdge(source) or source.pinned or source.hidden then
        -- Preserve native directional navigation outside our managed mode,
        -- including ordinary maximized windows and application fullscreen.
        return hl.dispatch(hl.dsp.focus({ direction = direction }))
    end
    local target = navigationTarget(source, direction)
    if not target or target == source then return end
    local selector = scopeSelector(source.workspace)
    local monitor = source.monitor.name
    local previousFullscreen = target.fullscreen
    local previouslyTagged = hasTag(target)
    pendingOpens = {}
    changing = true
    local ok, reason = pcall(function()
        -- Keep the workspace spacing and durable source tag until the target
        -- is ready. Unmaximizing first avoids every global fullscreen-focus
        -- policy, without changing that policy for unrelated windows.
        setGapRule(selector, true)
        checked(hl.dsp.window.fullscreen({
            window = source, mode = "maximized", action = "unset", layout_aware = false,
        }))
        checked(hl.dsp.focus({ window = target }))
        -- A native focus action can report success when a layer/modal refuses
        -- the focus. Do not commit an unfocused or moved window in that case.
        if hl.get_active_window() ~= target
            or not navigationCandidate(target, selector, monitor) then
            error("the selected window could not receive focus", 0)
        end
        checked(hl.dsp.window.tag({ window = target, tag = "+" .. tag }))
        checked(hl.dsp.window.fullscreen({
            window = target, mode = "maximized", action = "set", layout_aware = false,
        }))
        checked(hl.dsp.window.tag({ window = source, tag = "-" .. tag }))
    end)
    if not ok then
        -- Best-effort rollback only touches these two tiles. Preserve a later
        -- F11/floating/moving change instead of resurrecting a closed window.
        if navigationCandidate(target, selector, monitor) then
            if previousFullscreen == 0 and target.fullscreen == 1 then
                pcall(function()
                    checked(hl.dsp.window.fullscreen({
                        window = target, mode = "maximized", action = "unset", layout_aware = false,
                    }))
                end)
            end
            if not previouslyTagged and hasTag(target) then
                pcall(function()
                    checked(hl.dsp.window.tag({ window = target, tag = "-" .. tag }))
                end)
            end
        end
        if navigationCandidate(source, selector, monitor) then
            pcall(function()
                if not hasTag(source) then
                    checked(hl.dsp.window.tag({ window = source, tag = "+" .. tag }))
                end
                checked(hl.dsp.window.fullscreen({
                    window = source, mode = "maximized", action = "set", layout_aware = false,
                }))
                checked(hl.dsp.focus({ window = source }))
            end)
        end
        print("Quickshell edge navigation: " .. tostring(reason))
    end
    changing = false
    reconcile()
end

function edgeMode.left() return edgeMode.focus("left") end
function edgeMode.right() return edgeMode.focus("right") end

-- These three methods form the explicit Settings layout-change transaction.
-- Merely requiring this module never changes a window or starts a timer.
function edgeMode.prepareLayoutChange()
    if pendingLayoutChange then error("Window layout: a previous layout change is still pending", 0) end
    pendingOpens = {}
    local snapshot = {}
    for _, window in ipairs(hl.get_windows()) do
        if isEdge(window) and not window.pinned then
            snapshot[#snapshot + 1] = { window = window, untagged = false, unmaximized = false }
        end
    end
    pendingLayoutChange = snapshot
    changing = true
    local ok, reason = pcall(function()
        -- Restore reserved workspace spacing before unmaximizing the windows.
        for selector in pairs(gapRules) do setGapRule(selector, false) end
        for _, entry in ipairs(snapshot) do
            local window = entry.window
            checked(hl.dsp.window.tag({ window = window, tag = "-" .. tag }))
            entry.untagged = true
            checked(hl.dsp.window.fullscreen({
                window = window, mode = "maximized", action = "unset", layout_aware = false,
            }))
            entry.unmaximized = true
        end
    end)
    changing = false
    if not ok then
        pcall(edgeMode.restoreLayoutChange)
        error(tostring(reason), 0)
    end
    watching = false
    if settleTimer then settleTimer:set_enabled(false) end
    refreshShell()
end

function edgeMode.commitLayoutChange()
    pendingLayoutChange = nil
end

function edgeMode.restoreLayoutChange()
    if not pendingLayoutChange then return end
    changing = true
    local ok, reason = pcall(function()
        for _, entry in ipairs(pendingLayoutChange) do
            local window = entry.window
            -- Native window handles are weak. Skip closed windows and preserve
            -- later floating, pinned, F11 or ordinary maximized user changes.
            if window.mapped and not window.floating and not window.pinned
                and window.workspace and window.monitor then
                local selector = scopeSelector(window.workspace)
                if isEdge(window) then
                    if selector then setGapRule(selector, true) end
                elseif selector and window.fullscreen == 1 and window.fullscreen_handler == "default"
                    and entry.untagged and not entry.unmaximized then
                    -- Preparation failed after tag removal but before native
                    -- unmaximize. Reattach our tag without a fullscreen toggle.
                    setGapRule(selector, true)
                    checked(hl.dsp.window.tag({ window = window, tag = "+" .. tag }))
                elseif window.fullscreen == 0 then
                    if selector then
                        setGapRule(selector, true)
                        checked(hl.dsp.window.tag({ window = window, tag = "+" .. tag }))
                        checked(hl.dsp.window.fullscreen({
                            window = window, mode = "maximized", action = "set", layout_aware = false,
                        }))
                    end
                end
            end
        end
    end)
    changing = false
    if not ok then error(tostring(reason), 0) end
    pendingLayoutChange = nil
    watching = false
    for _, window in ipairs(hl.get_windows()) do
        if isEdge(window) then watching = true; break end
    end
    refreshShell()
end

function edgeMode.up()
    local window = hl.get_active_window()
    if not window or not window.mapped or window.floating then return end
    if isEdge(window) then
        reconcile()
        return
    end
    -- Preserve application fullscreen (for example F11 or a fullscreen game).
    if window.fullscreen == 2 then return end

    local layout = window.layout
    local column = layout and layout.name == "scrolling" and layout.column
    local expanded = column and (tonumber(column.width) or 0) >= 0.995
    if not expanded and window.fullscreen ~= 1 then
        if layout and layout.name == "scrolling" then
            if not column then return end
            hl.dispatch(hl.dsp.layout("colresize 1.0"))
            hl.dispatch(hl.dsp.layout("fit_into_view"))
        else
            hl.dispatch(hl.dsp.window.fullscreen({
                window = window, mode = "maximized", action = "set", layout_aware = false,
            }))
        end
        return
    end

    local selector = scopeSelector(window.workspace)
    if not selector then return end
    changing = true
    watching = true
    setGapRule(selector, true)
    hl.dispatch(hl.dsp.window.tag({ window = window, tag = "+" .. tag }))
    -- Default maximized respects the monitor's reserved top bar. Scrolling's
    -- layout-aware fullscreen does not provide the requested edge-to-edge area.
    hl.dispatch(hl.dsp.window.fullscreen({
        window = window,
        mode = "maximized",
        action = "set",
        layout_aware = false,
    }))
    changing = false
    reconcile()
end

function edgeMode.down()
    pendingOpens = {}
    local window = hl.get_active_window()
    if not window or not window.mapped then return end
    if hasTag(window) then
        changing = true
        local selector = scopeSelector(window.workspace)
        if selector then
            local shared = false
            for _, other in ipairs(hl.get_windows()) do
                if other ~= window and isEdge(other)
                    and scopeSelector(other.workspace) == selector then
                    shared = true
                    break
                end
            end
            -- Restore gaps before native unmaximize recalculates the layout,
            -- preventing a frame at the normal size with the old zero gaps.
            if not shared then setGapRule(selector, false) end
        end
        hl.dispatch(hl.dsp.window.tag({ window = window, tag = "-" .. tag }))
        if window.fullscreen == 1 then
            hl.dispatch(hl.dsp.window.fullscreen({
                window = window,
                mode = "maximized",
                action = "unset",
                layout_aware = false,
            }))
        end
        changing = false
        reconcile()
    end
    if window.floating or window.fullscreen == 2 then return end
    local layout = window.layout
    if layout and layout.name == "scrolling" then
        resetColumn()
    elseif window.fullscreen == 1 then
        hl.dispatch(hl.dsp.window.fullscreen({
            window = window, mode = "maximized", action = "unset", layout_aware = false,
        }))
    end
end

hl.on("window.open_early", rememberEdgeOwner)
hl.on("window.open", inheritEdgeMode)
hl.on("window.close", discardPending)
hl.on("window.destroy", discardPending)

for _, event in ipairs({
    "window.close", "window.destroy", "window.fullscreen",
    "window.update_rules", "window.move_to_workspace", "window.active",
    "workspace.active", "workspace.special_active", "workspace.removed",
    "workspace.move_to_monitor", "monitor.added", "monitor.removed",
    "monitor.layout_changed",
}) do
    -- Deferred until the compositor finishes each move/close/fullscreen event.
    hl.on(event, scheduleReconcile)
end

hl.on("config.reloaded", function()
    pendingOpens = {}
    -- --verify-config also emits this event, without a compositor event loop.
    -- Only a live reload with an existing tagged window needs a native timer.
    watching = #hl.get_windows({ tag = tag }) > 0
    if watching then scheduleReconcile() end
end)

hl.on("hyprland.shutdown", function()
    pendingOpens = {}
    if settleTimer then settleTimer:set_enabled(false) end
end)

return edgeMode
