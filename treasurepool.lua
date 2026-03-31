addon.name      = 'TreasurePool'
addon.author    = 'Shiyo, Zaldas'
addon.version   = '2.0.1'
addon.desc      = 'Displays your current treasure pool with lot/pass buttons.'
addon.link      = 'https://ashitaxi.com/'

require('common')
local imgui      = require('imgui')
local settings   = require('settings')
local ffi        = require('ffi')
local bit        = require('bit')

local lootWindow = require('elements/lootWindow')
local state      = require('state')
local layout     = require('layouts/default')

------------------------------------------------------------
-- FFI for client-to-server packets (lot 0x0041, pass 0x0042)
------------------------------------------------------------
pcall(ffi.cdef, [[
    // Packet: 0x0042 - Trophy Absence (Client to Server)
    typedef struct tp_packet_trophyabsence_c2s_t {
        uint16_t    id: 9;
        uint16_t    size: 7;
        uint16_t    sync;
        uint8_t     TrophyItemIndex;
        uint8_t     padding00;
    } tp_packet_trophyabsence_c2s_t;
]])

------------------------------------------------------------
-- Default Settings
------------------------------------------------------------
local default_settings = T{
    anchor = {
        x = 200,
        y = 200,
    },
    showLotButtons = true,
    dragEnabled    = true,
    scale          = 0,    -- 0 = auto (resY/1440); >0 = custom multiplier (0.25-2.5)
    debugCount     = 10,
}

------------------------------------------------------------
-- Addon State
------------------------------------------------------------
local tpSettings       = nil
local settingsOpen     = { false }
local settingsWasOpen  = false
local debugMode        = false  -- transient, never persisted

-- Compute getEffectiveScale() from screen resolution (1440p baseline)
local resY = AshitaCore:GetConfigurationManager():GetFloat('boot', 'ffxi.registry', '0002', 768)

local function getEffectiveScale()
    if tpSettings and tpSettings.scale and tpSettings.scale > 0 then
        return tpSettings.scale
    end
    return resY / 1440
end

------------------------------------------------------------
-- Debug test data
------------------------------------------------------------
local dTreasurePool = {
    { name = "Kraken Club",              lot = 0,     lotWinner = "",              winningLot = 0,   timeToLive = 280 },
    { name = "Osode of Flames",          lot = 0,     lotWinner = "Matsuno",       winningLot = 543, timeToLive = 220 },
    { name = "Perdu Blade",              lot = 0,     lotWinner = "Jorin",         winningLot = 821, timeToLive = 90  },
    { name = "Biting Sword",             lot = 0,     lotWinner = "Beatrice",      winningLot = 412, timeToLive = 35  },
    { name = "Byakko's Haidate",         lot = 765,   lotWinner = "You",           winningLot = 765, timeToLive = 250 },
    { name = "Martial Anelace",          lot = 312,   lotWinner = "Matsuno",       winningLot = 543, timeToLive = 200 },
    { name = "Zenith Mitts",             lot = 65535, lotWinner = "Jorin",         winningLot = 720, timeToLive = 120 },
    { name = "Homam Corazza",            lot = 65535, lotWinner = "",              winningLot = 0,   timeToLive = 270 },
    { name = "Ridill",                   lot = 0,     lotWinner = "George",        winningLot = 997, timeToLive = 5   },
    { name = "Assassin's Armlets",       lot = 0,     lotWinner = "Somewhatdamaged", winningLot = 421, timeToLive = 100 },
}

------------------------------------------------------------
-- Packet Sending Helpers
------------------------------------------------------------
local function sendLotPacket(slotIndex)
    local lotValue = math.random(1, 999)
    AshitaCore:GetPacketManager():AddOutgoingPacket(0x0041, {
        0x41, 0x04, 0x00, 0x00,
        slotIndex, 0x00,
        bit.band(lotValue, 0xFF), bit.rshift(lotValue, 8),
    })
end

local function sendPassPacket(slotIndex)
    AshitaCore:GetPacketManager():AddOutgoingPacket(0x0042, {
        0x42, 0x04, 0x00, 0x00,
        slotIndex, 0x00,
    })
end

------------------------------------------------------------
-- Gather Treasure Pool Data
------------------------------------------------------------

-- Maps FFXI DropTime value -> Unix expiry timestamp (os.time() + 300).
-- DropTime is an FFXI-epoch timestamp, not Unix, so we can't do math on it
-- directly. Instead we use it as a unique key and record when we first saw
-- each item.
local dropTimeCache = {}

local function getPlayerName()
    local party = AshitaCore:GetMemoryManager():GetParty()
    local name  = party and party:GetMemberName(0)
    return (type(name) == 'string' and #name > 0) and name or 'You'
end

local function gatherTreasureData()
    local result     = {}
    local inv        = AshitaCore:GetMemoryManager():GetInventory()
    local resMgr     = AshitaCore:GetResourceManager()
    local playerName = getPlayerName()
    local now        = os.time()

    for i = 0, 9 do
        local item = inv:GetTreasurePoolItem(i)
        if item and item.ItemId > 0 then
            local resource = resMgr:GetItemById(item.ItemId)
            local itemName = (resource and resource.Name[1]) or 'Unknown'

            local winnerName = item.WinningEntityName
            if item.WinningLot == 0 then
                winnerName = ''
            elseif type(winnerName) ~= 'string' or string.len(winnerName) < 3 then
                winnerName = 'Unknown'
            end

            -- First time we see this DropTime, record expiry as now + 300s
            if not dropTimeCache[item.DropTime] then
                dropTimeCache[item.DropTime] = now + 300
            end

            result[#result + 1] = {
                slot       = i,
                itemId     = item.ItemId,
                name       = itemName,
                lot        = item.Lot,
                winningLot = item.WinningLot,
                winnerName = winnerName,
                expiresAt  = dropTimeCache[item.DropTime],
                playerName = playerName,
            }
        end
    end
    return result
end

local function gatherDebugData()
    local result     = {}
    local count      = tpSettings and tpSettings.debugCount or 10
    local playerName = getPlayerName()
    for i, item in ipairs(dTreasurePool) do
        if i > count then break end
        result[#result + 1] = {
            slot       = i - 1,
            itemId     = 0,
            name       = item.name,
            lot        = item.lot,
            winningLot = item.winningLot,
            winnerName = item.lotWinner == 'You' and playerName or item.lotWinner,
            expiresAt  = os.time() + item.timeToLive,
            playerName = playerName,
        }
    end
    return result
end

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function wireCallbacks()
    lootWindow.onLotSlot = function(slot)
        if debugMode then
            print('[TreasurePool] Debug: Lot slot ' .. tostring(slot))
        else
            sendLotPacket(slot)
        end
    end

    lootWindow.onPassSlot = function(slot)
        if debugMode then
            print('[TreasurePool] Debug: Pass slot ' .. tostring(slot))
        else
            sendPassPacket(slot)
        end
    end

    lootWindow.onLotAll = function()
        local items = debugMode and gatherDebugData() or gatherTreasureData()
        state.addLotAll(items)
        if debugMode then
            print('[TreasurePool] Debug: Lot All queued')
        end
    end

    lootWindow.onPassAll = function()
        local items = debugMode and gatherDebugData() or gatherTreasureData()
        state.addPassAll(items)
        if debugMode then
            print('[TreasurePool] Debug: Pass All queued')
        end
    end
end

local function rebuildWindow()
    lootWindow.destroy()
    lootWindow.initialize(layout, tpSettings.anchor, getEffectiveScale())
    lootWindow.dragEnabled = tpSettings.dragEnabled
    wireCallbacks()
end

local function reloadLayout()
    package.loaded['layouts/default'] = nil
    layout = require('layouts/default')
    rebuildWindow()
    print('[TreasurePool] Layout reloaded.')
end

------------------------------------------------------------
-- Event: Load
------------------------------------------------------------
ashita.events.register('load', 'load_cb', function()
    tpSettings = settings.load(default_settings)

    lootWindow.initialize(layout, tpSettings.anchor, getEffectiveScale())
    lootWindow.dragEnabled = tpSettings.dragEnabled
    wireCallbacks()

    settings.register('settings', 'settings_update', function(s)
        if s ~= nil then
            lootWindow.destroy()
            tpSettings = s
            lootWindow.initialize(layout, tpSettings.anchor, getEffectiveScale())
            lootWindow.dragEnabled = tpSettings.dragEnabled
            wireCallbacks()
        end
    end)
end)

------------------------------------------------------------
-- Event: Unload
------------------------------------------------------------
ashita.events.register('unload', 'unload_cb', function()
    lootWindow.destroy()
    state.reset()
end)

------------------------------------------------------------
-- Settings Window helpers
------------------------------------------------------------
local function drawGradientHeader(text)
    local drawlist = imgui.GetWindowDrawList()
    local avail    = imgui.GetContentRegionAvail()
    local availW   = type(avail) == 'table' and avail[1] or avail
    local x, y     = imgui.GetCursorScreenPos()
    local lineH    = imgui.GetTextLineHeightWithSpacing()
    local cL       = imgui.GetColorU32({ 0.25, 0.40, 0.85, 1.00 })
    local cR       = imgui.GetColorU32({ 0.25, 0.40, 0.85, 0.00 })
    drawlist:AddRectFilledMultiColor({ x, y }, { x + availW * 0.75, y + lineH }, cL, cR, cR, cL)
    imgui.SetCursorScreenPos({ x + 4, y + 2 })
    imgui.Text(text)
    local _, newY = imgui.GetCursorScreenPos()
    imgui.SetCursorScreenPos({ x, newY })
    imgui.Spacing()
end

local function styledButton(label, width, isPrimary)
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 6.0)
    if isPrimary then
        imgui.PushStyleColor(ImGuiCol_Button,        { 0.25, 0.40, 0.85, 1.00 })
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 0.30, 0.48, 0.95, 1.00 })
        imgui.PushStyleColor(ImGuiCol_ButtonActive,  { 0.18, 0.32, 0.70, 1.00 })
    else
        imgui.PushStyleColor(ImGuiCol_Button,        { 0.00, 0.00, 0.00, 0.00 })
        imgui.PushStyleColor(ImGuiCol_ButtonHovered, { 1.00, 1.00, 1.00, 0.12 })
        imgui.PushStyleColor(ImGuiCol_ButtonActive,  { 1.00, 1.00, 1.00, 0.20 })
    end
    local clicked = imgui.Button(label, { width, 0 })
    imgui.PopStyleColor(3)
    imgui.PopStyleVar(1)
    return clicked
end

------------------------------------------------------------
-- Settings Window (ImGui)
------------------------------------------------------------
local function drawSettingsWindow()
    -- Reset debug when the window is closed
    if settingsWasOpen and not settingsOpen[1] then
        debugMode = false
    end
    settingsWasOpen = settingsOpen[1]

    if not settingsOpen[1] then return end

    local indent = 6
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 6.0)
    if imgui.Begin('TreasurePool Settings', settingsOpen, ImGuiWindowFlags_AlwaysAutoResize) then
        local avail  = imgui.GetContentRegionAvail()
        local availW = type(avail) == 'table' and avail[1] or avail

        -- Display section
        drawGradientHeader('Display')

        imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
        local drag = { tpSettings.dragEnabled }
        if imgui.Checkbox('Drag Enabled', drag) then
            tpSettings.dragEnabled = drag[1]
            lootWindow.dragEnabled = drag[1]
            settings.save()
        end

        imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
        local customScaleOn = { (tpSettings.scale or 0) > 0 }
        if imgui.Checkbox('Custom Scale', customScaleOn) then
            tpSettings.scale = customScaleOn[1] and 1.0 or 0
            settings.save()
            rebuildWindow()
        end
        if customScaleOn[1] then
            imgui.SameLine()
            local scaleVal = { tpSettings.scale > 0 and tpSettings.scale or 1.0 }
            imgui.SetNextItemWidth(120)
            if imgui.SliderFloat('##scale', scaleVal, 0.25, 2.5, 'x%.2f') then
                tpSettings.scale = scaleVal[1]
                settings.save()
                rebuildWindow()
            end
        end

        imgui.Spacing()

        -- Debug section
        drawGradientHeader('Debug')

        imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
        local dbg = { debugMode }
        if imgui.Checkbox('Debug Mode', dbg) then
            debugMode = dbg[1]
        end
        if debugMode then
            imgui.SameLine()
            local cnt = { tpSettings.debugCount }
            imgui.SetNextItemWidth(80)
            if imgui.InputInt('Items##dbg', cnt) then
                local v = cnt[1]
                if v >= 1 and v <= 10 then
                    tpSettings.debugCount = v
                end
            end
        end

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        if styledButton('Reload Layout', availW, false) then
            reloadLayout()
        end
    end
    imgui.End()
    imgui.PopStyleVar(1)
end

------------------------------------------------------------
-- Event: d3d_present (render every frame)
------------------------------------------------------------
ashita.events.register('d3d_present', 'present_cb', function()
    drawSettingsWindow()

    if not settings.logged_in and not debugMode then
        lootWindow.update({})
        return
    end

    -- Drain lot/pass all queues
    state.drainQueues(sendLotPacket, sendPassPacket)

    -- Gather data
    local items
    if debugMode then
        items = gatherDebugData()
    else
        items = gatherTreasureData()
    end

    -- Update the window
    lootWindow.update(items)
end)

------------------------------------------------------------
-- Event: Mouse
------------------------------------------------------------
ashita.events.register('mouse', 'mouse_cb', function(e)
    if lootWindow.handleMouse(e) then
        settings.save()
    end
end)

------------------------------------------------------------
-- Event: Packet In
------------------------------------------------------------
ashita.events.register('packet_in', 'treasurepool_packet_in', function(e)
    state.handlePacketIn(e)
end)

------------------------------------------------------------
-- Event: Command
------------------------------------------------------------
ashita.events.register('command', 'treasurepool_command', function(e)
    local args = e.command:args()
    if #args == 0 or args[1] ~= '/treasurepool' then
        return
    end
    e.blocked = true
    settingsOpen[1] = not settingsOpen[1]
end)
