-- A temporary empty workspace preserves every window and its tiling layout.
local desktop = { saved = nil, sequence = 0 }

local function selector(workspace)
    return workspace.id > 0 and workspace.id or "name:" .. workspace.name
end

local function find_window(address)
    for _, window in ipairs(hl.get_windows()) do
        if window.address == address then return window end
    end
end

function desktop.toggle()
    if desktop.saved then
        local saved = desktop.saved
        desktop.saved = nil
        local monitors = {}
        for _, monitor in ipairs(hl.get_monitors()) do monitors[monitor.name] = monitor end
        for _, entry in ipairs(saved.monitors) do
            if monitors[entry.name] then
                hl.dispatch(hl.dsp.focus({ monitor = entry.name }))
                hl.dispatch(hl.dsp.focus({ workspace = entry.workspace }))
                if entry.special then
                    hl.dispatch(hl.dsp.workspace.toggle_special(entry.special))
                end
            end
        end
        for _, address in ipairs(saved.pinned) do
            local window = find_window(address)
            if window and not window.pinned then
                hl.dispatch(hl.dsp.window.pin({ window = window, action = "set" }))
            end
        end
        local window = saved.focused and find_window(saved.focused)
        if window then hl.dispatch(hl.dsp.focus({ window = window }))
        elseif saved.monitor and monitors[saved.monitor] then
            hl.dispatch(hl.dsp.focus({ monitor = saved.monitor }))
        end
        return
    end

    desktop.sequence = desktop.sequence + 1
    local active = hl.get_active_window()
    local monitor = hl.get_active_monitor()
    local saved = { monitors = {}, pinned = {}, focused = active and active.address, monitor = monitor and monitor.name }
    for _, output in ipairs(hl.get_monitors()) do
        if output.active_workspace and not output.is_mirror then
            table.insert(saved.monitors, {
                name = output.name,
                workspace = selector(output.active_workspace),
                special = output.active_special_workspace and output.active_special_workspace.name:gsub("^special:", ""),
                desktop = "name:desktop-view-" .. output.id .. "-" .. desktop.sequence,
            })
        end
    end
    for _, window in ipairs(hl.get_windows()) do
        if window.pinned then
            table.insert(saved.pinned, window.address)
            hl.dispatch(hl.dsp.window.pin({ window = window, action = "unset" }))
        end
    end
    desktop.saved = saved
    for _, entry in ipairs(saved.monitors) do
        hl.dispatch(hl.dsp.focus({ monitor = entry.name }))
        if entry.special then hl.dispatch(hl.dsp.workspace.toggle_special(entry.special)) end
        hl.dispatch(hl.dsp.focus({ workspace = entry.desktop }))
    end
    if saved.monitor then hl.dispatch(hl.dsp.focus({ monitor = saved.monitor })) end
    for _, target in ipairs({ "appLauncher", "themeSwitcher", "quickSettings", "settingsApp", "clipboardHistory", "quickNotes", "notificationCenter" }) do
        hl.dispatch(hl.dsp.exec_cmd("qs ipc call " .. target .. " close"))
    end
end

return desktop
