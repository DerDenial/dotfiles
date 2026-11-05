-- Hold either Super key on its own to reveal the shortcut guide.
-- Hyprland 0.56 Lua API: event driven; one dormant timer; no input capture.
local guide = {}
local delayMs = 650
local pressedKeys = {}
local pressedButtons = {}
local lastPressedCode = nil
local armedCode = nil
local activeToken = nil
local showSent = false
local sequence = 0
-- Process CPU time remains monotonic across Lua config reloads. It only orders
-- epochs; the actual hold delay uses Hyprland's steady-clock native timer.
local epoch = string.format("%.0f", math.floor(os.clock() * 1000000))
local sessionTag = epoch .. "-" .. string.format("%08x", math.random(0, 0x7fffffff))
local delayTimer

local function notify(method, token)
    -- Both arguments are generated here, and contain only letters, digits or '-'.
    hl.exec_cmd("qs ipc call hotkeyGuide " .. method .. " " .. token .. " >/dev/null 2>&1")
end

local function cancel()
    if delayTimer then delayTimer:set_enabled(false) end
    local token = activeToken
    local wasSent = showSent
    armedCode = nil
    activeToken = nil
    showSent = false
    if token and wasSent then notify("holdHide", token) end
end

local function onlyKeyDown(code)
    if not code or not pressedKeys[code] or not hl.is_key_down(code) then return false end
    for other in pairs(pressedKeys) do
        if not hl.is_key_down(other) then
            pressedKeys[other] = nil
        elseif other ~= code then
            return false
        end
    end
    return next(pressedButtons) == nil
end

-- A disabled repeat timer can be rearmed indefinitely. Cancelled native oneshot
-- timers retain their callbacks until the next config reload in Hyprland 0.56.
local function reveal()
    delayTimer:set_enabled(false)
    if not activeToken or not onlyKeyDown(armedCode) then
        cancel()
        return
    end
    showSent = true
    notify("holdShow", activeToken)
end

local function arm()
    -- The keyboard event runs immediately before its normal keybind. Taking its
    -- physical code also supports keys mapped to Super, rather than fixed codes.
    local code = lastPressedCode
    if not onlyKeyDown(code) then
        cancel()
        return
    end
    if armedCode == code then return end
    cancel()
    sequence = sequence + 1
    armedCode = code
    activeToken = sessionTag .. "-" .. tostring(sequence)
    if delayTimer then
        delayTimer:set_timeout(delayMs)
    else
        -- Creating lazily avoids touching the compositor event loop while a
        -- configuration is only being parsed (for example, --verify-config).
        delayTimer = hl.timer(reveal, { timeout = delayMs, type = "repeat" })
    end
end

hl.on("input.keyboard.key", function(code, _, state)
    if state == 1 then
        pressedKeys[code] = true
        lastPressedCode = code
        if armedCode and code ~= armedCode then cancel() end
    else
        pressedKeys[code] = nil
        if code == armedCode then cancel() end
        if code == lastPressedCode then lastPressedCode = nil end
    end
end)

-- Normal binds keep the compositor's lock and shortcut inhibition protections.
-- Non-consuming and transparent binds preserve existing Super combinations.
for _, key in ipairs({ "Super_L", "Super_R" }) do
    hl.bind(key, arm, {
        non_consuming = true,
        transparent = true,
        ignore_mods = true,
        description = "Hotkey guide: hold Super",
    })
end

-- These observe button presses without taking over window dragging/resizing.
-- Bind matching runs every matching callback, while non_consuming never changes
-- the consumption decision made by an existing mouse binding.
for button = 272, 279 do
    local name = "mouse:" .. tostring(button)
    hl.bind(name, function()
        pressedButtons[name] = true
        cancel()
    end, {
        non_consuming = true,
        transparent = true,
        ignore_mods = true,
        submap_universal = true,
        locked = true,
        dont_inhibit = true,
        allow_input_capture = true,
        description = "Hotkey guide: cancel on pointer button",
    })
    hl.bind(name, function()
        pressedButtons[name] = nil
        cancel()
    end, {
        release = true,
        non_consuming = true,
        transparent = true,
        ignore_mods = true,
        submap_universal = true,
        locked = true,
        dont_inhibit = true,
        allow_input_capture = true,
        description = "Hotkey guide: release pointer button",
    })
end

for _, key in ipairs({ "mouse_up", "mouse_down", "mouse_left", "mouse_right" }) do
    hl.bind(key, cancel, {
        non_consuming = true,
        transparent = true,
        ignore_mods = true,
        submap_universal = true,
        description = "Hotkey guide: cancel on mouse wheel",
    })
end

hl.on("keybinds.submap", cancel)
hl.on("config.reloaded", function()
    cancel()
    -- The previous Lua state is already gone on reload. Give the shell the new
    -- epoch so delayed messages from an earlier state cannot reopen its guide.
    notify("reset", sessionTag)
end)
hl.on("hyprland.shutdown", cancel)

guide.cancel = cancel
return guide
