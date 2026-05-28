addon.name      = 'TreasurePool'
addon.author    = 'Shiyo, Zaldas'
addon.version   = '2.5'
addon.desc      = 'Displays your current treasure pool with lot/pass buttons.'
addon.link      = 'https://ashitaxi.com/'

require('common')
local imgui      = require('imgui')
local settings   = require('settings')
local ffi        = require('ffi')
local bit        = require('bit')
local chat       = require('chat')

local lootWindow = require('elements/lootWindow')
local state      = require('state')
local layout     = require('layouts/default')

-- Ashita 4.3 changed BeginChild: boolean cflags replaced with ImGuiChildFlags_* enum.
-- Wrap to handle both branches transparently.
local _newChildFlags = ImGuiChildFlags_None ~= nil
local function imguiBeginChild(id, size, borders)
    if _newChildFlags then
        return imgui.BeginChild(id, size, borders and ImGuiChildFlags_Borders or ImGuiChildFlags_None)
    end
    return imgui.BeginChild(id, size, borders)
end

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
local tpSettings       = default_settings
local settingsOpen     = { false }
local logged_in        = false
local lotDetailsSlot   = nil
local lotDetailsOpen   = { false }
local rareOwnedCache   = {}
local rareOwnedFrame   = 0

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
                result[name] = 65535
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

-- All personal storage containers; excludes Temporary (3) and Recycle (17).
local OWNED_CONTAINERS = { 0, 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }

local function playerOwnsRareItem(itemId, inv)
    for _, container in ipairs(OWNED_CONTAINERS) do
        local max = inv:GetContainerCountMax(container)
        for slot = 0, max - 1 do
            local item = inv:GetContainerItem(container, slot)
            if item and item.Id == itemId then return true end
        end
    end
    return false
end

local function buildItemFromPacket(packet)
    local itemId   = packet.TrophyItemNo
    local slotIdx  = packet.TrophyItemIndex
    local resource = AshitaCore:GetResourceManager():GetItemById(itemId)

    local winnerName = ffi.string(packet.LootActName, 16):match('^[^%z]*')
    if packet.LootPoint == 0 or #winnerName < 3 then
        winnerName = ''
    end

    return {
        slot       = slotIdx,
        itemId     = itemId,
        name       = (resource and resource.Name[1]) or 'Unknown',
        lot        = packet.IsLocallyLotted,
        winningLot = packet.LootPoint,
        winnerName = winnerName,
        expiresAt  = os.time() + 300,
        playerName = getPlayerName(),
        -- populated by 0x00D3 lot/pass packets as they arrive
        partyLots  = {},
    }
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
    ['George']   = 65535,  -- passed
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
    { itemId = 14488, name = "Homam Corazza",      lot = 65535, lotWinner = "",         winningLot = 0,   timeToLive = 270 }, -- Rare+Ex
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
    local result     = {}
    local inv        = AshitaCore:GetMemoryManager():GetInventory()
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
                winnerName = 'Unknown'
            end

            -- DropTime is the server Unix timestamp when the item entered the pool.
            -- TimeToLive is in an unknown unit (not seconds), so derive expiry from DropTime.
            local dropRem  = item.DropTime + 300 - os.time()
            local expiresAt = (dropRem >= 0 and dropRem <= 310) and (item.DropTime + 300) or (os.time() + 300)

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

        local inv      = AshitaCore:GetMemoryManager():GetInventory()
        local resMgr   = AshitaCore:GetResourceManager()
        local items    = gatherTreasureData()
        local lottable = {}

        for _, entry in ipairs(items) do
            if entry.lot ~= 0 then goto continue end
            local resource = resMgr:GetItemById(entry.itemId)
            local isRare   = resource and bit.band(resource.Flags, 0x8000) ~= 0
            if isRare and inv and playerOwnsRareItem(entry.itemId, inv) then goto continue end
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
    tpSettings = settings.load(default_settings)
    logged_in  = GetPlayerEntity() ~= nil

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
    if not settingsOpen[1] then return end

    local indent = 6
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 6.0)
    imgui.SetNextWindowSize({ 270, 0 }, ImGuiCond_Always)
    if imgui.Begin('TreasurePool', settingsOpen, ImGuiWindowFlags_NoResize) then
        local availW = 270 - 16  -- window width minus padding

        if imgui.BeginTabBar('tpSettingsTabs') then

            ----------------------------------------------------
            -- Tab: Display
            ----------------------------------------------------
            if imgui.BeginTabItem('Display') then
                imgui.Spacing()
                drawGradientHeader('Display')

                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                local themeIdx = { 0 }
                for i, t in ipairs(THEME_LIST) do
                    if t == (tpSettings.theme or 'Plain') then themeIdx[1] = i - 1; break end
                end
                imgui.SetNextItemWidth(math.floor((availW - indent) * 0.65))
                if imgui.Combo('Theme##theme', themeIdx, table.concat(THEME_LIST, '\0') .. '\0') then
                    tpSettings.theme = THEME_LIST[themeIdx[1] + 1]
                    settings.save()
                    rebuildWindow()
                end
                imgui.Spacing()

                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                local lockPos = { tpSettings.lockPosition == true }
                if imgui.Checkbox('Lock position', lockPos) then
                    tpSettings.lockPosition = lockPos[1]
                    lootWindow.dragEnabled = not lockPos[1]
                    settings.save()
                end

                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                local collapsibleOn = { tpSettings.collapsible == true }
                if imgui.Checkbox('Collapsible header', collapsibleOn) then
                    tpSettings.collapsible = collapsibleOn[1]
                    if not collapsibleOn[1] then tpSettings.collapsed = false end
                    settings.save()
                    lootWindow.setCollapsible(collapsibleOn[1])
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
                drawGradientHeader('Debug')

                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                local cnt = { tpSettings.debugCount }
                imgui.SetNextItemWidth(80)
                if imgui.InputInt('Items##dbg', cnt) then
                    local v = cnt[1]
                    if v >= 1 and v <= 10 then
                        tpSettings.debugCount = v
                    end
                end

                imgui.Spacing()
                imgui.Separator()
                imgui.Spacing()

                local btnW   = math.floor(availW * 0.80)
                local btnPad = math.floor((availW - btnW) * 0.5)
                imgui.SetCursorPosX(imgui.GetCursorPosX() + btnPad)
                if styledButton('Reload Layout', btnW, false) then
                    reloadLayout()
                end

                imgui.EndTabItem()
            end

            ----------------------------------------------------
            -- Tab: Interactions
            ----------------------------------------------------
            if imgui.BeginTabItem('Interactions') then
                imgui.Spacing()

                local tt = tpSettings.tooltip
                local ttEnabled = { tt and tt.enabled or false }

                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                if imgui.Checkbox('Show Item Tooltip', ttEnabled) then
                    tpSettings.tooltip.enabled = ttEnabled[1]
                    settings.save()
                end
                imgui.SameLine()
                imgui.TextDisabled('(?)')
                if imgui.IsItemHovered() then
                    imgui.BeginTooltip()
                    imgui.PushTextWrapPos(imgui.GetFontSize() * 18)
                    imgui.TextUnformatted('Hover over an item in the loot pool to see its stats and description.')
                    imgui.PopTextWrapPos()
                    imgui.EndTooltip()
                end

                if tt and tt.enabled then
                    imgui.Spacing()

                    local subIndent = indent + 10
                    local function ttHint(text)
                        imgui.SameLine()
                        imgui.TextDisabled('(?)')
                        if imgui.IsItemHovered() then
                            imgui.BeginTooltip()
                            imgui.TextUnformatted(text)
                            imgui.EndTooltip()
                        end
                    end

                    imgui.SetCursorPosX(imgui.GetCursorPosX() + subIndent)
                    local ttGear = { tt.gear }
                    if imgui.Checkbox('Gear##tt', ttGear) then
                        tpSettings.tooltip.gear = ttGear[1]; settings.save()
                    end
                    ttHint('Weapons and armor.')

                    imgui.SetCursorPosX(imgui.GetCursorPosX() + subIndent)
                    local ttUsables = { tt.usables }
                    if imgui.Checkbox('Usables##tt', ttUsables) then
                        tpSettings.tooltip.usables = ttUsables[1]; settings.save()
                    end
                    ttHint('Consumable items: food, medicines, scrolls, meds, etc.')

                    imgui.SetCursorPosX(imgui.GetCursorPosX() + subIndent)
                    local ttItems = { tt.items }
                    if imgui.Checkbox('Items##tt', ttItems) then
                        tpSettings.tooltip.items = ttItems[1]; settings.save()
                    end
                    ttHint('Everything else: seals, crystals, key items, etc.')
                end

                imgui.Spacing()
                imgui.Separator()
                imgui.Spacing()

                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                local ttLD = { tt and tt.lotDetails or false }
                if imgui.Checkbox('Show Lot Details', ttLD) then
                    tpSettings.tooltip.lotDetails = ttLD[1]
                    settings.save()
                end
                imgui.SameLine()
                imgui.TextDisabled('(?)')
                if imgui.IsItemHovered() then
                    imgui.BeginTooltip()
                    imgui.TextUnformatted('Left-clicking an item row opens a window\nshowing all party lot and pass results.')
                    imgui.EndTooltip()
                end

                imgui.Spacing()
                imgui.EndTabItem()
            end

            imgui.EndTabBar()
        end
    end
    imgui.End()
    imgui.PopStyleVar(1)
end

------------------------------------------------------------
-- Lot Details Window
------------------------------------------------------------
local function buildLotRow(name, lot, winningLot)
    local statusStr, statusColor
    if lot == nil then
        statusStr   = 'Pending'
        statusColor = { 0.5, 0.5, 0.5, 1.0 }
    elseif lot == 65535 then
        statusStr   = 'Pass'
        statusColor = { 0.4, 0.6, 0.9, 1.0 }
    else
        statusStr = state.formatLot(lot)
        if lot == winningLot and winningLot > 0 then
            statusColor = { 1.0, 0.80, 0.2, 1.0 }  -- gold: currently winning
        else
            statusColor = { 0.85, 0.85, 0.85, 1.0 }
        end
    end
    return { name = name, status = statusStr, color = statusColor }
end

local function drawLotDetailsWindow(items)
    if not lotDetailsOpen[1] or lotDetailsSlot == nil then return end

    local entry = nil
    for _, item in ipairs(items) do
        if item.slot == lotDetailsSlot then entry = item; break end
    end
    if not entry then lotDetailsOpen[1] = false; return end

    -- Build per-party rows: parties[1..3] map to main party, ally1, ally2.
    -- Members are iterated in party order (0-17); empty slots skipped via GetMemberIsActive.
    local parties   = { {}, {}, {} }
    local seenNames = {}

    local partyMem = AshitaCore:GetMemoryManager():GetParty()
    if partyMem then
        for i = 0, 17 do
            if partyMem:GetMemberIsActive(i) ~= 0 then
                local name = partyMem:GetMemberName(i)
                if name and type(name) == 'string' and #name >= 3 then
                    local partyIdx = math.floor(i / 6) + 1  -- 1=main, 2=ally1, 3=ally2
                    local lot = entry.partyLots and entry.partyLots[name]
                    local row = buildLotRow(name, lot, entry.winningLot)
                    parties[partyIdx][#parties[partyIdx] + 1] = row
                    seenNames[name] = true
                end
            end
        end
    end

    -- Lotters not in the current alliance go in their own section (e.g. Dynamis cross-alliance lots)
    local extraRows = {}
    do
        local extraNames = {}
        for name in pairs(entry.partyLots or {}) do
            if not seenNames[name] then extraNames[#extraNames + 1] = name end
        end
        table.sort(extraNames)
        for _, name in ipairs(extraNames) do
            extraRows[#extraRows + 1] = buildLotRow(name, entry.partyLots[name], entry.winningLot)
        end
    end

    local hasAny = #parties[1] > 0 or #parties[2] > 0 or #parties[3] > 0 or #extraRows > 0

    local statusColW = 60
    local gap        = 8

    local function renderRows(rows)
        for _, row in ipairs(rows) do
            local tw = imgui.CalcTextSize(row.status)
            tw = type(tw) == 'table' and (tw[1] or tw.x) or (tw or 0)
            imgui.SetCursorPosX(statusColW - tw)
            imgui.TextColored(row.color, row.status)
            imgui.SameLine(statusColW + gap)
            imgui.TextColored(row.color, row.name)
        end
    end

    local rowH   = imgui.GetTextLineHeightWithSpacing()

    imgui.SetNextWindowSizeConstraints({ 200, 80 }, { 200, 2000 })
    imgui.SetNextWindowSize({ 200, rowH * 12 }, ImGuiCond_FirstUseEver)
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 6.0)
    if imgui.Begin('Lot Details##lotdetails', lotDetailsOpen) then
        imgui.TextColored({ 1.0, 0.85, 0.2, 1.0 }, entry.name)
        imgui.Separator()
        imgui.Spacing()

        if not hasAny then
            imgui.TextDisabled('No party members found.')
        else
            imguiBeginChild('##lotscroll', { 0, 0 }, false)
            local first = true
            for i = 1, 3 do
                if #parties[i] > 0 then
                    if not first then
                        imgui.Spacing()
                        imgui.Separator()
                        imgui.Spacing()
                    end
                    renderRows(parties[i])
                    first = false
                end
            end
            if #extraRows > 0 then
                if not first then
                    imgui.Spacing()
                    imgui.Separator()
                    imgui.Spacing()
                end
                renderRows(extraRows)
            end
            imgui.EndChild()
        end
    end
    imgui.End()
    imgui.PopStyleVar(1)
end

------------------------------------------------------------
-- Item Tooltip
------------------------------------------------------------
-- Item type buckets (from FFXI ItemType enum)
local TOOLTIP_GEAR    = { [4]=true, [5]=true }   -- Weapon, Armor
local TOOLTIP_USABLES = { [7]=true }              -- UsableItem

-- FFXI item descriptions contain SJIS special byte sequences for element icons
-- and color codes that ImGui cannot render.  Strip/replace them before display.
local _EF = string.char(239)   -- 0xEF: prefix for icon sequences
local _1E = string.char(30)    -- 0x1E: color-code prefix
local _ELEM_MAP = {
    { string.char(31), '[Fire]'     },  -- 0x1F
    { string.char(32), '[Ice]'      },  -- 0x20
    { string.char(33), '[Wind]'     },  -- 0x21
    { string.char(34), '[Earth]'    },  -- 0x22
    { string.char(35), '[Thunder]'  },  -- 0x23
    { string.char(36), '[Water]'    },  -- 0x24
    { string.char(37), '[Light]'    },  -- 0x25
    { string.char(38), '[Darkness]' },  -- 0x26
}

-- Plain (non-pattern) find+replace — avoids gsub pattern issues with bytes
-- like 0x25 (37 = '%'), which is the Lua pattern escape character.
local function strReplaceAll(s, from, to)
    local parts = {}
    local i = 1
    while i <= #s do
        local j = string.find(s, from, i, true)
        if j then
            parts[#parts + 1] = string.sub(s, i, j - 1)
            parts[#parts + 1] = to
            i = j + #from
        else
            parts[#parts + 1] = string.sub(s, i)
            break
        end
    end
    return table.concat(parts)
end

local function cleanDescription(desc)
    if not desc or #desc == 0 then return desc end
    local s = desc
    -- Replace known element icon sequences (\xEF + element byte) with labels.
    -- Done with plain string search to avoid pattern issues (byte 0x25 = '%').
    for _, pair in ipairs(_ELEM_MAP) do
        s = strReplaceAll(s, _EF .. pair[1], pair[2])
    end
    -- Strip any remaining \xEF + byte (unknown icon sequences).
    -- 0xEF (239) is not a Lua pattern special char, so gsub is safe here.
    s = s:gsub(_EF .. '.', '')
    -- Strip FFXI color codes: \x1E + any byte.
    s = s:gsub(_1E .. '.', '')
    return s
end

-- Job abbreviations indexed by FFXI job ID (1=WAR … 22=RUN).
-- Jobs bitmask: bit.band(item.Jobs, 2^jobId) ~= 0  (confirmed from luashitacast)
local _JOB_ABBR = {
    'WAR','MNK','WHM','BLM','RDM','THF','PLD','DRK',
    'BST','BRD','RNG','SAM','NIN','DRG','SMN','BLU',
    'COR','PUP','DNC','SCH','GEO','RUN',
}
local _JOB_COUNT = 22
local _JOB_ALL_MASK = (function()
    local m = 0
    for i = 1, _JOB_COUNT do m = m + 2^i end
    return m
end)()

-- Returns a list of lines, each with at most 7 job abbreviations.
local function buildJobsLines(jobsMask)
    if not jobsMask or jobsMask == 0 then return nil end
    if bit.band(jobsMask, _JOB_ALL_MASK) == _JOB_ALL_MASK then return { 'All Jobs' } end
    local list = {}
    for i = 1, _JOB_COUNT do
        if bit.band(jobsMask, 2^i) ~= 0 then
            list[#list + 1] = _JOB_ABBR[i]
        end
    end
    if #list == 0 then return nil end
    local lines = {}
    for i = 1, #list, 7 do
        local chunk = {}
        for j = i, math.min(i + 6, #list) do chunk[#chunk + 1] = list[j] end
        lines[#lines + 1] = table.concat(chunk, ' ')
    end
    return lines
end

local function tooltipAllowedForType(itemType)
    local tt = tpSettings and tpSettings.tooltip
    if not tt or not tt.enabled then return false end
    if TOOLTIP_GEAR[itemType]    then return tt.gear end
    if TOOLTIP_USABLES[itemType] then return tt.usables end
    return tt.items  -- catch-all: seals, crystals, key items, fish, etc.
end

local function drawItemTooltip(items)
    local entry = lootWindow.getHoveredEntry(items)
    if not entry or not entry.itemId or entry.itemId == 0 then return end

    local item = AshitaCore:GetResourceManager():GetItemById(entry.itemId)
    if not item then return end

    if not tooltipAllowedForType(item.Type) then return end

    imgui.BeginTooltip()

    imgui.TextColored({ 1.0, 0.85, 0.2, 1.0 }, entry.name)

    if item.ItemLevel and item.ItemLevel > 0 then
        imgui.Text('Item Level ' .. tostring(item.ItemLevel))
    elseif item.Level and item.Level > 0 then
        imgui.Text('Lv. ' .. tostring(item.Level))
    end

    local jobsLines = buildJobsLines(item.Jobs)
    if jobsLines then
        for _, line in ipairs(jobsLines) do
            imgui.TextDisabled(line)
        end
    end

    local desc = item.Description and item.Description[1]
    if desc and #desc > 0 then
        imgui.Separator()
        imgui.PushTextWrapPos(imgui.GetFontSize() * 22)
        imgui.TextUnformatted(cleanDescription(desc))
        imgui.PopTextWrapPos()
    end

    imgui.EndTooltip()
end

------------------------------------------------------------
-- Event: d3d_present (render every frame)
------------------------------------------------------------
ashita.events.register('d3d_present', 'present_cb', function()
    drawSettingsWindow()

    if not logged_in and not settingsOpen[1] then
        lootWindow.update({})
        return
    end

    -- Drain lot/pass all queues
    state.drainQueues(sendLotPacket, sendPassPacket)

    -- Prune items that expired >30s ago (safety net for missed clear packets)
    local now = os.time()
    state.pruneExpired(now)

    -- Clear stale winner when they've left the zone.
    -- Server retracts lots on zone-out but sends no packet; GetMemberIsActive
    -- returns 0 for out-of-zone members, which is the only reliable signal we have.
    if not settingsOpen[1] and #state.getItems() > 0 then
        local partyMem = AshitaCore:GetMemoryManager():GetParty()
        if partyMem then
            local inZone = {}
            for i = 0, 17 do
                if partyMem:GetMemberIsActive(i) ~= 0 then
                    local n = partyMem:GetMemberName(i)
                    if type(n) == 'string' and #n >= 3 then
                        inZone[n] = true
                    end
                end
            end
            for _, entry in ipairs(state.getItems()) do
                if entry.winnerName ~= '' and not inZone[entry.winnerName] then
                    entry.winningLot = 0
                    entry.winnerName = ''
                end
            end
        end
    end

    -- Debug mode re-generates fake data each frame (responds to debugCount changes)
    local items = settingsOpen[1] and gatherDebugData() or state.getItems()

    -- Refresh Rare ownership cache every 30 frames; apply cached values every frame.
    -- Stays at frame 0 until inventory is confirmed loaded (GetContainerCountMax > 0).
    if not settingsOpen[1] then
        if rareOwnedFrame == 0 then
            local inv = AshitaCore:GetMemoryManager():GetInventory()
            if inv and inv:GetContainerCountMax(0) > 0 then
                local resMgr = AshitaCore:GetResourceManager()
                rareOwnedCache = {}
                for _, entry in ipairs(items) do
                    if entry.lot == 0 and rareOwnedCache[entry.itemId] == nil then
                        local resource = resMgr:GetItemById(entry.itemId)
                        local isRare   = resource and bit.band(resource.Flags, 0x8000) ~= 0
                        if isRare then
                            rareOwnedCache[entry.itemId] = playerOwnsRareItem(entry.itemId, inv)
                        else
                            rareOwnedCache[entry.itemId] = false
                        end
                    end
                end
                rareOwnedFrame = 1
            end
        else
            rareOwnedFrame = (rareOwnedFrame + 1) % 30
        end

        for _, entry in ipairs(items) do
            if entry.lot == 0 then
                entry.rareOwned = rareOwnedCache[entry.itemId] or false
            else
                entry.rareOwned = false
            end
        end
    end

    lootWindow.update(items, state.isPassAllActive())
    drawItemTooltip(items)
    drawLotDetailsWindow(items)
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
        logged_in = true
        return
    end

    -- 0x000B: zone leave / warp — clear stale pool immediately
    if e.id == 0x000B then
        logged_in      = false
        rareOwnedCache = {}
        rareOwnedFrame = 0
        state.reset()
        return
    end

    -- 0x00D2: item added/updated or removed from pool slot
    if e.id == 0x00D2 then
        if e.size < ffi.sizeof('tp_packet_trophylist_s2c_t') then return end
        local packet = ffi.cast('tp_packet_trophylist_s2c_t*', e.data_modified_raw)
        if packet.TrophyItemNo == 0 then
            state.removeFromCache(packet.TrophyItemIndex)
        else
            state.insertSorted(buildItemFromPacket(packet))
        end
        return
    end

    -- 0x00D3: lot/pass update or item awarded
    if e.id == 0x00D3 then
        if e.size < ffi.sizeof('tp_packet_trophysolution_s2c_t') then return end
        local packet  = ffi.cast('tp_packet_trophysolution_s2c_t*', e.data_modified_raw)
        local slotIdx = packet.TrophyItemIndex

        if packet.JudgeFlg == 1 or packet.JudgeFlg == 2 then
            -- Item awarded (1) or failed/lost — rare/ex conflict, inventory full (2) — remove from pool
            state.removeFromCache(slotIdx)
        elseif packet.JudgeFlg == 0 then
            -- Lot/pass — update existing entry in-place (no re-sort; expiresAt unchanged)
            for _, entry in ipairs(state.getItems()) do
                if entry.slot == slotIdx then
                    -- Update current winner
                    local winnerName = ffi.string(packet.sLootName, 16):match('^[^%z]*')
                    entry.winningLot = packet.LootPoint
                    entry.winnerName = (packet.LootPoint > 0 and #winnerName >= 3) and winnerName or ''

                    -- Record this actor's lot/pass in partyLots
                    local actorName = ffi.string(packet.sLootName2, 16):match('^[^%z]*')
                    if #actorName >= 3 then
                        entry.partyLots[actorName] = (packet.EntryPoint < 0) and 65535 or packet.EntryPoint
                    end

                    -- Update local lot if this action was ours
                    if actorName == getPlayerName() then
                        entry.lot = entry.partyLots[actorName]
                    end
                    break
                end
            end
        end
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
