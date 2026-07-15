addon.name      = 'TreasurePool'
addon.author    = 'Shiyo, Zaldas'
addon.version   = '2.6'
addon.desc      = 'Displays your current treasure pool with lot/pass buttons.'
addon.link      = 'https://ashitaxi.com/'

require('common')
local settings   = require('settings')
local bit        = require('bit')
local chat       = require('chat')

local lootWindow     = require('elements/lootWindow')
local settingsWindow = require('elements/settingsWindow')
local lotDetails     = require('elements/lotDetails')
local itemTooltip    = require('elements/itemTooltip')
local state          = require('state')
local layout         = require('layouts/default')

------------------------------------------------------------
-- Default Settings
------------------------------------------------------------
local defaultSettings = T{
    anchor = {
        x = 200,
        y = 200,
    },
    showLotButtons    = true,
    lockPosition      = false,
    collapsible       = true,
    collapsed         = false,
    scale             = 0,    -- 0 = auto (resY/1440); >0 = custom multiplier (0.25-2.5)
    debugCount        = 10,
    theme             = 'Plain',
    tooltip = {
        enabled    = true,
        gear       = true,   -- Weapon (4), Armor (5)
        usables    = true,   -- UsableItem (7)
        items      = true,   -- everything else: seals, crystals, key items, etc.
        lotDetails = true,   -- show lot details popup on row click
    },
}

-- Must be kept in sync with the theme files shipped under layouts/themes/
-- (used only to sort built-in themes after custom ones in the dropdown).
local BUILTIN_THEMES = {
    Plain=true, xiv=true, ffxi=true,
    Window1=true, Window2=true, Window3=true, Window4=true,
    Window5=true, Window6=true, Window7=true, Window8=true,
}

local function buildThemeList()
    local custom, builtin = {}, {}
    for name in pairs(layout.themes) do
        if BUILTIN_THEMES[name] then
            builtin[#builtin + 1] = name
        else
            custom[#custom + 1] = name
        end
    end
    table.sort(custom)
    table.sort(builtin)
    local list = {}
    for _, name in ipairs(custom)  do list[#list + 1] = name end
    for _, name in ipairs(builtin) do list[#list + 1] = name end
    return list
end

local THEME_LIST = buildThemeList()

------------------------------------------------------------
-- Addon State
------------------------------------------------------------
local tpSettings       = defaultSettings
local settingsOpen     = { false }
local loggedIn         = false
local lotDetailsSlot   = nil
local lotDetailsOpen   = { false }

local function getPlayerName()
    local party = AshitaCore:GetMemoryManager():GetParty()
    local name  = party and party:GetMemberName(0)
    return (type(name) == 'string' and #name > 0) and name or 'You'
end

local function buildPartyLotsForSlot(slotIdx)
    local result = {}
    local memberLots = state.getMemberLots()[slotIdx]
    if not memberLots then
        return result
    end
    for name, info in pairs(memberLots) do
        if type(name) == 'string' and #name >= 3 and type(info) == 'table' then
            if info.passed then
                result[name] = state.LOT_PASSED
            elseif type(info.lot) == 'number' then
                result[name] = info.lot
            end
        end
    end
    return result
end

local function isInventoryFull()
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    if not inv then return false end
    return inv:GetContainerCount(0) >= inv:GetContainerCountMax(0)
end

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
local dPartyLots = {
    ['Matsuno']  = 543,
    ['Jorin']    = 821,
    ['Beatrice'] = 412,
    ['George']   = state.LOT_PASSED,  -- passed
    ['Zalyx']    = 765,
}

local dTreasurePool = {
    -- Gear (Weapon/Armor — type 4/5)
    { itemId = 17440, name = "Kraken Club",        lot = 0,     lotWinner = "",         winningLot = 0,   timeToLive = 280 }, -- Rare
    { itemId = 12562, name = "Kirin's Osode",      lot = 0,     lotWinner = "Matsuno",  winningLot = 543, timeToLive = 220, rareOwned = true }, -- Rare (debug: simulated owned)
    { itemId = 18425, name = "Perdu Blade",        lot = 0,     lotWinner = "Jorin",    winningLot = 821, timeToLive = 90  }, -- Rare+Ex
    { itemId = 17707, name = "Martial Anelace",    lot = 0,     lotWinner = "Beatrice", winningLot = 412, timeToLive = 35  }, -- (neither)
    { itemId = 12818, name = "Byakko's Haidate",   lot = 765,   lotWinner = "You",      winningLot = 765, timeToLive = 250 }, -- Rare+Ex
    { itemId = 17707, name = "Martial Anelace",    lot = 312,   lotWinner = "Matsuno",  winningLot = 543, timeToLive = 200 }, -- (neither)
    { itemId = 14488, name = "Homam Corazza",      lot = state.LOT_PASSED, lotWinner = "",         winningLot = 0,   timeToLive = 270 }, -- Rare+Ex
    -- Usables (type 7)
    { itemId = 4247,  name = "Miratete's Memoirs", lot = 0,     lotWinner = "",         winningLot = 0,   timeToLive = 200 }, -- Rare+Ex
    -- Items catch-all (type 1)
    { itemId = 1127,  name = "Kindred's Seal",     lot = 0,     lotWinner = "Fahad",    winningLot = 789, timeToLive = 180 }, -- Ex only
    -- General item
    { itemId = 606,   name = "Quadav Fetich Head", lot = 0,     lotWinner = "",         winningLot = 0,   timeToLive = 150 }, -- Rare
}

------------------------------------------------------------
-- Packet Sending Helpers
------------------------------------------------------------
local function sendLotPacket(slotIndex)
    -- The server rolls the lot value server-side; the client does not send one
    -- (trailing bytes are padding, per XiPackets 0x0041 / LSB 0x041_trophy_entry.cpp).
    AshitaCore:GetPacketManager():AddOutgoingPacket(0x0041, {
        0x41, 0x04, 0x00, 0x00,
        slotIndex, 0x00, 0x00, 0x00,
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
    local result     = {}
    local inv        = AshitaCore:GetMemoryManager():GetInventory()
    if not inv then return result end
    local resMgr     = AshitaCore:GetResourceManager()
    local playerName = getPlayerName()

    for i = 0, 9 do
        local item = inv:GetTreasurePoolItem(i)
        if item and item.ItemId > 0 then
            local resource = resMgr:GetItemById(item.ItemId)
            local itemName = (resource and resource.Name[1]) or 'Unknown'

            local winnerName = item.WinningEntityName
            if item.WinningLot == 0 then
                winnerName = ''
            elseif type(winnerName) ~= 'string' or string.len(winnerName) < 3 then
                winnerName = ''  -- match state.buildItemFromPacket's convention (no winner shown)
            end

            -- DropTime is the server Unix timestamp when the item entered the pool.
            -- TimeToLive is in an unknown unit (not seconds), so derive expiry from DropTime.
            local dropRem  = item.DropTime + state.POOL_TTL - os.time()
            local expiresAt = (dropRem >= 0 and dropRem <= 310) and (item.DropTime + state.POOL_TTL) or (os.time() + state.POOL_TTL)

            result[#result + 1] = {
                slot       = i,
                itemId     = item.ItemId,
                name       = itemName,
                lot        = item.Lot,
                winningLot = item.WinningLot,
                winnerName = winnerName,
                expiresAt  = expiresAt,
                playerName = playerName,
                partyLots  = buildPartyLotsForSlot(i),
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
            itemId     = item.itemId or 0,
            name       = item.name,
            lot        = item.lot,
            winningLot = item.winningLot,
            winnerName = item.lotWinner == 'You' and playerName or item.lotWinner,
            expiresAt  = os.time() + item.timeToLive,
            playerName = playerName,
            partyLots  = dPartyLots,
            rareOwned  = item.rareOwned or false,
        }
    end
    return result
end

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function wireCallbacks()
    lootWindow.onLotSlot = function(slot)
        if settingsOpen[1] then
            print(chat.header('TreasurePool') .. chat.message('Debug: Lot slot ' .. tostring(slot)))
            return
        end

        for _, entry in ipairs(state.getItems()) do
            if entry.slot == slot then
                if entry.rareOwned then return end
                break
            end
        end

        if isInventoryFull() then
            print(chat.header('TreasurePool') .. chat.warning('Inventory full - cannot lot.'))
            return
        end

        sendLotPacket(slot)
    end

    lootWindow.onPassSlot = function(slot)
        if settingsOpen[1] then
            print(chat.header('TreasurePool') .. chat.message('Debug: Pass slot ' .. tostring(slot)))
        else
            sendPassPacket(slot)
        end
    end

    lootWindow.onLotAll = function()
        if settingsOpen[1] then
            state.addLotAll(gatherDebugData())
            print(chat.header('TreasurePool') .. chat.message('Debug: Lot All queued'))
            return
        end

        if isInventoryFull() then
            print(chat.header('TreasurePool') .. chat.warning('Inventory full - cannot lot.'))
            return
        end

        local resMgr   = AshitaCore:GetResourceManager()
        local items    = gatherTreasureData()
        local lottable = {}

        for _, entry in ipairs(items) do
            if entry.lot ~= 0 then goto continue end
            local resource = resMgr:GetItemById(entry.itemId)
            local isRare   = resource and bit.band(resource.Flags, 0x8000) ~= 0
            if isRare and state.playerOwnsRareItem(entry.itemId) then goto continue end
            lottable[#lottable + 1] = entry
            ::continue::
        end

        state.addLotAll(lottable)
    end

    lootWindow.onPassAll = function()
        local items = settingsOpen[1] and gatherDebugData() or gatherTreasureData()
        state.addPassAll(items)
        if settingsOpen[1] then
            print(chat.header('TreasurePool') .. chat.message('Debug: Pass All queued'))
        end
    end

    lootWindow.onItemClick = function(slot)
        local tt = tpSettings and tpSettings.tooltip
        if not tt or not tt.lotDetails then return end
        lotDetailsSlot = slot
        lotDetailsOpen[1] = true
    end

    lootWindow.onCollapseToggle = function(collapsed)
        tpSettings.collapsed = collapsed
        settings.save()
    end
end

local function getActiveBgDef()
    return layout.themes and (layout.themes[tpSettings.theme] or layout.themes['Plain'])
end

local function rebuildWindow()
    lootWindow.destroy()
    lootWindow.initialize(layout, getActiveBgDef(), tpSettings.anchor, getEffectiveScale())
    lootWindow.dragEnabled = tpSettings.lockPosition ~= true
    wireCallbacks()
    local isCollapsible = tpSettings.collapsible == true
    lootWindow.setCollapsible(isCollapsible)
    lootWindow.setCollapsed(isCollapsible and tpSettings.collapsed == true)
end

local function reloadLayout()
    package.loaded['layouts/default'] = nil
    layout = require('layouts/default')
    THEME_LIST = buildThemeList()
    rebuildWindow()
    print(chat.header('TreasurePool') .. chat.message('Layout reloaded.'))
end

------------------------------------------------------------
-- Event: Load
------------------------------------------------------------
ashita.events.register('load', 'load_cb', function()
    tpSettings = settings.load(defaultSettings)
    loggedIn   = GetPlayerEntity() ~= nil

    rebuildWindow()

    -- Prime cache in case addon loads while items are already in the pool
    state.setItems(gatherTreasureData())

    settings.register('settings', 'settings_update', function(s)
        if s ~= nil then
            tpSettings = s
            rebuildWindow()
        end
    end)
end)

------------------------------------------------------------
-- Event: Unload
------------------------------------------------------------
ashita.events.register('unload', 'unload_cb', function()
    lootWindow.destroy()
    state.reset()
    ashita.events.unregister('d3d_present', 'present_cb')
    ashita.events.unregister('mouse', 'mouse_cb')
    ashita.events.unregister('packet_in', 'treasurepool_packet_in')
    ashita.events.unregister('command', 'treasurepool_command')
end)

------------------------------------------------------------
-- Event: d3d_present (render every frame)
------------------------------------------------------------
ashita.events.register('d3d_present', 'present_cb', function()
    settingsWindow.draw(tpSettings, settingsOpen, THEME_LIST, { onRebuild = rebuildWindow, onReloadLayout = reloadLayout })

    if not loggedIn and not settingsOpen[1] then
        lootWindow.update({})
        return
    end

    -- Drain lot/pass all queues
    state.drainQueues(sendLotPacket, sendPassPacket)

    -- Prune items that expired >30s ago (safety net for missed clear packets)
    local now = os.time()
    state.pruneExpired(now)

    -- Clear stale winner when they've left the zone (throttled, see state.reconcileWinners).
    -- Apply any rareOwned recomputes queued by 0x0020 packets last frame
    -- (deferred one frame so the client has settled the packet into inventory
    -- memory first, see state.processPendingRareRecompute).
    if not settingsOpen[1] then
        state.reconcileWinners()
        state.processPendingRareRecompute()
    end

    -- Debug mode re-generates fake data each frame (responds to debugCount changes)
    -- Live entries carry rareOwned directly (computed at pool-insert time in
    -- state.lua, invalidated by 0x0020 item-attr packets).
    local items = settingsOpen[1] and gatherDebugData() or state.getItems()

    lootWindow.update(items, state.isPassAllActive())
    itemTooltip.draw(items, tpSettings)
    lotDetails.draw(items, lotDetailsSlot, lotDetailsOpen)
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
    if e.injected then return end

    state.handlePacketIn(e)

    -- 0x000A: zone enter — player is now logged in / zoned in
    if e.id == 0x000A then
        loggedIn = true
        return
    end

    -- 0x000B: zone leave / warp — clear stale pool immediately
    if e.id == 0x000B then
        loggedIn = false
        state.reset()
        return
    end
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
