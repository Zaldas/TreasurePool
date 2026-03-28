addon.name      = 'TreasurePool'
addon.author    = 'Shiyo, Zaldas'
addon.version   = '3.0.0'
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
    debug          = false,
    debugCount     = 10,
}

------------------------------------------------------------
-- Addon State
------------------------------------------------------------
local tpSettings   = nil
local settingsOpen = { false }

-- Compute uiScale from screen resolution (1440p baseline)
local resY    = AshitaCore:GetConfigurationManager():GetFloat('boot', 'ffxi.registry', '0002', 768)
local uiScale = resY / 1440

------------------------------------------------------------
-- Debug test data
------------------------------------------------------------
local dTreasurePool = {
    { name = "Kraken Club",              lot = 0,     lotWinner = "",              winningLot = 0,   dropTime = os.time() - 20  },
    { name = "Osode of Flames",          lot = 0,     lotWinner = "Matsuno",       winningLot = 543, dropTime = os.time() - 80  },
    { name = "Perdu Blade",              lot = 0,     lotWinner = "Jorin",         winningLot = 821, dropTime = os.time() - 210 },
    { name = "Biting Sword",             lot = 0,     lotWinner = "Beatrice",      winningLot = 412, dropTime = os.time() - 265 },
    { name = "Byakko's Haidate",         lot = 765,   lotWinner = "You",           winningLot = 765, dropTime = os.time() - 50  },
    { name = "Martial Anelace",          lot = 312,   lotWinner = "Matsuno",       winningLot = 543, dropTime = os.time() - 100 },
    { name = "Zenith Mitts",             lot = 65535, lotWinner = "Jorin",         winningLot = 720, dropTime = os.time() - 180 },
    { name = "Homam Corazza",            lot = 65535, lotWinner = "",              winningLot = 0,   dropTime = os.time() - 30  },
    { name = "Ridill",                   lot = 0,     lotWinner = "George",        winningLot = 997, dropTime = os.time() - 295 },
    { name = "Joyeuse +1 Augmented Wep", lot = 0,     lotWinner = "Somewhatdamaged", winningLot = 421, dropTime = os.time() - 200 },
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
local function gatherTreasureData()
    local result = {}
    local inv    = AshitaCore:GetMemoryManager():GetInventory()
    local resMgr = AshitaCore:GetResourceManager()

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

            result[#result + 1] = {
                slot       = i,
                itemId     = item.ItemId,
                name       = itemName,
                lot        = item.Lot,
                winningLot = item.WinningLot,
                winnerName = winnerName,
                dropTime   = item.DropTime,
            }
        end
    end
    return result
end

local function gatherDebugData()
    local result = {}
    local count  = tpSettings and tpSettings.debugCount or 10
    for i, item in ipairs(dTreasurePool) do
        if i > count then break end
        result[#result + 1] = {
            slot       = i - 1,
            itemId     = 0,
            name       = item.name,
            lot        = item.lot,
            winningLot = item.winningLot,
            winnerName = item.lotWinner,
            dropTime   = item.dropTime,
        }
    end
    return result
end

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function wireCallbacks()
    lootWindow.onLotSlot = function(slot)
        if not tpSettings.debug then
            sendLotPacket(slot)
        else
            print('[TreasurePool] Debug: Lot slot ' .. tostring(slot))
        end
    end

    lootWindow.onPassSlot = function(slot)
        if not tpSettings.debug then
            sendPassPacket(slot)
        else
            print('[TreasurePool] Debug: Pass slot ' .. tostring(slot))
        end
    end

    lootWindow.onLotAll = function()
        local items = tpSettings.debug and gatherDebugData() or gatherTreasureData()
        state.addLotAll(items)
        if tpSettings.debug then
            print('[TreasurePool] Debug: Lot All queued')
        end
    end

    lootWindow.onPassAll = function()
        local items = tpSettings.debug and gatherDebugData() or gatherTreasureData()
        state.addPassAll(items)
        if tpSettings.debug then
            print('[TreasurePool] Debug: Pass All queued')
        end
    end
end

local function reloadLayout()
    package.loaded['layouts/default'] = nil
    layout = require('layouts/default')
    lootWindow.destroy()
    lootWindow.initialize(layout, tpSettings.anchor, uiScale)
    lootWindow.dragEnabled = tpSettings.dragEnabled
    wireCallbacks()
    print('[TreasurePool] Layout reloaded.')
end

------------------------------------------------------------
-- Event: Load
------------------------------------------------------------
ashita.events.register('load', 'load_cb', function()
    tpSettings = settings.load(default_settings)

    lootWindow.initialize(layout, tpSettings.anchor, uiScale)
    lootWindow.dragEnabled = tpSettings.dragEnabled
    wireCallbacks()

    settings.register('settings', 'settings_update', function(s)
        if s ~= nil then
            lootWindow.destroy()
            tpSettings = s
            lootWindow.initialize(layout, tpSettings.anchor, uiScale)
            lootWindow.dragEnabled = tpSettings.dragEnabled
            wireCallbacks()
        end
    end)
end)

------------------------------------------------------------
-- Event: Unload
------------------------------------------------------------
ashita.events.register('unload', 'unload_cb', function()
    tpSettings.debug = false
    lootWindow.destroy()
    state.reset()
end)

------------------------------------------------------------
-- Settings Window (ImGui)
------------------------------------------------------------
local function drawSettingsWindow()
    if not settingsOpen[1] then return end

    imgui.SetNextWindowSize({ 260, 80 }, ImGuiCond_FirstUseEver)
    if imgui.Begin('TreasurePool Settings', settingsOpen) then
        local drag = { tpSettings.dragEnabled }
        if imgui.Checkbox('Drag Enabled', drag) then
            tpSettings.dragEnabled    = drag[1]
            lootWindow.dragEnabled    = drag[1]
            settings.save()
        end
        imgui.SameLine()
        if imgui.Button('Reload Layout') then
            reloadLayout()
        end
    end
    imgui.End()
end

------------------------------------------------------------
-- Event: d3d_present (render every frame)
------------------------------------------------------------
ashita.events.register('d3d_present', 'present_cb', function()
    drawSettingsWindow()

    if not settings.logged_in then
        lootWindow.update({})
        return
    end

    -- Drain lot/pass all queues
    state.drainQueues(sendLotPacket, sendPassPacket)

    -- Gather data
    local items
    if tpSettings.debug then
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

    -- /treasurepool debug [#]
    if #args >= 2 and args[2]:any('debug') then
        tpSettings.debug = not tpSettings.debug
        if #args == 3 then
            local value = tonumber(args[3])
            if value and value > 0 and value <= 10 then
                tpSettings.debugCount = value
                tpSettings.debug = true
            end
        end
        print('[TreasurePool] Debug: ' .. tostring(tpSettings.debug))
        return
    end

    -- /treasurepool buttons
    if #args >= 2 and args[2]:any('buttons') then
        tpSettings.showLotButtons = not tpSettings.showLotButtons
        settings.save()
        print('[TreasurePool] Lot buttons: ' .. tostring(tpSettings.showLotButtons))
        return
    end

    -- /treasurepool settings
    if #args >= 2 and args[2]:any('settings') then
        settingsOpen[1] = not settingsOpen[1]
        return
    end

    -- Help
    local helpText = 'Treasure Pool:\n'
    helpText = helpText .. '  /treasurepool debug [#] -- toggle debug mode; optional item count 1-10\n'
    helpText = helpText .. '  /treasurepool buttons   -- toggle lot/pass buttons\n'
    helpText = helpText .. '  /treasurepool settings  -- open settings window\n'
    print(helpText)
end)
