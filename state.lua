------------------------------------------------------------
-- state.lua
-- Packet state logic for TreasurePool.
-- Handles 0x00D2 (Trophy List) and 0x00D3 (Trophy Solution)
-- server-to-client packets, plus lot/pass queue draining.
------------------------------------------------------------

local ffi  = require('ffi')
local bit  = require('bit')
local chat = require('chat')

local state = {}

------------------------------------------------------------
-- FFI definitions (server→client packets only)
------------------------------------------------------------
pcall(ffi.cdef, [[
    // Packet: 0x00D2 - Server Trophy List (Server to Client)
    typedef struct tp_packet_trophylist_s2c_t {
        uint16_t    id: 9;
        uint16_t    size: 7;
        uint16_t    sync;
        uint32_t    TrophyItemNum;
        uint32_t    TargetUniqueNo;
        uint16_t    Gold;
        uint16_t    padding00;
        uint16_t    TrophyItemNo;
        uint16_t    TargetActIndex;
        uint8_t     TrophyItemIndex;
        uint8_t     Entry;
        uint8_t     IsContainer;
        uint8_t     padding01;
        uint32_t    StartTime;
        uint16_t    IsLocallyLotted;
        uint16_t    Point;
        uint32_t    LootUniqueNo;
        uint16_t    LootActIndex;
        uint16_t    LootPoint;
        uint8_t     LootActName[16];
        uint8_t     NamedFlag   : 1;
        uint8_t     SingleFlag  : 1;
        uint8_t     Flags_2     : 2;
        uint8_t     Flags_4     : 1;
        uint8_t     Flags_5     : 1;
        uint8_t     Flags_6     : 1;
        uint8_t     Flags_7     : 1;
        uint8_t     padding02[3];
    } tp_packet_trophylist_s2c_t;

    // Packet: 0x00D3 - Trophy Solution (Server To Client)
    typedef struct tp_packet_trophysolution_s2c_t {
        uint16_t    id: 9;
        uint16_t    size: 7;
        uint16_t    sync;
        uint32_t    LootUniqueNo;
        uint32_t    EntryUniqueNo;
        uint16_t    LootActIndex;
        int16_t     LootPoint;
        uint16_t    EntryActIndex   : 15;
        uint16_t    EntryFlg        : 1;
        int16_t     EntryPoint;
        uint8_t     TrophyItemIndex;
        uint8_t     JudgeFlg;
        uint8_t     sLootName[16];
        uint8_t     sLootName2[24];
    } tp_packet_trophysolution_s2c_t;
]])

------------------------------------------------------------
-- State tables
------------------------------------------------------------
-- [slotIdx] = { [name] = { lot=value, passed=bool } }
local memberLots         = {}
local memberLotItemKeys  = {}
local lotAllQueue        = {}
local passAllQueue       = {}
local frameCount         = 0
local cachedItems        = {}

------------------------------------------------------------
-- Cache helpers
------------------------------------------------------------
function state.insertSorted(item)
    -- Remove any existing entry for this slot, preserving accumulated partyLots.
    for i = #cachedItems, 1, -1 do
        if cachedItems[i].slot == item.slot then
            item.partyLots = cachedItems[i].partyLots or {}
            table.remove(cachedItems, i)
            break
        end
    end
    -- Insert at first position where our expiresAt is greater (descending order).
    for i = 1, #cachedItems do
        if item.expiresAt > cachedItems[i].expiresAt then
            table.insert(cachedItems, i, item)
            return
        end
    end
    cachedItems[#cachedItems + 1] = item
end

function state.removeFromCache(slot)
    for i = 1, #cachedItems do
        if cachedItems[i].slot == slot then
            table.remove(cachedItems, i)
            return
        end
    end
end

------------------------------------------------------------
-- Cache accessors
------------------------------------------------------------
-- Returns the live cachedItems table. Callers may mutate entries in-place
-- (e.g. rareOwned, winnerName) without needing a copy.
function state.getItems()
    return cachedItems
end

function state.clearItems()
    cachedItems = {}
end

-- Replaces cachedItems with the provided table and sorts it descending by
-- expiresAt. Used only by the load-event prime from gatherTreasureData().
function state.setItems(items)
    cachedItems = items
    table.sort(cachedItems, function(a, b) return a.expiresAt > b.expiresAt end)
end

-- Removes entries that expired more than 30 seconds ago. Iterates backwards
-- so removals do not shift unvisited indices.
function state.pruneExpired(now)
    for i = #cachedItems, 1, -1 do
        if cachedItems[i].expiresAt < now - 30 then
            table.remove(cachedItems, i)
        end
    end
end

------------------------------------------------------------
-- Lot formatting
------------------------------------------------------------
-- Returns a zero-padded 3-character string for display.
-- nil  -> '---'
-- 0-9  -> '00X'
-- 10-99 -> '0XX'
-- 100+ -> 'XXX'
function state.formatLot(lot)
    if lot == nil then return '---' end
    if lot < 10   then return '00' .. tostring(lot) end
    if lot < 100  then return '0'  .. tostring(lot) end
    return tostring(lot)
end

------------------------------------------------------------
-- Packet handling
------------------------------------------------------------
function state.handlePacketIn(e)
    -- 0x00D2: Trophy List — clear member lots for this slot only when the item changes
    if e.id == 0x00D2 and not e.injected then
        if e.data_length < ffi.sizeof('tp_packet_trophylist_s2c_t') then return end
        local packet = ffi.cast('tp_packet_trophylist_s2c_t*', e.data_modified_raw)
        local slotIdx = packet.TrophyItemIndex
        if packet.TrophyItemNo == 0 then
            memberLots[slotIdx] = nil
            memberLotItemKeys[slotIdx] = nil
        else
            local itemKey = tostring(packet.TrophyItemNo) .. ':' .. tostring(packet.StartTime)
            if memberLotItemKeys[slotIdx] ~= itemKey then
                memberLots[slotIdx] = {}
                memberLotItemKeys[slotIdx] = itemKey
            end
        end
        return
    end

    -- 0x00D3: Trophy Solution — track member lots, handle inventory full
    if e.id == 0x00D3 and not e.injected then
        if e.data_length < ffi.sizeof('tp_packet_trophysolution_s2c_t') then return end
        local packet = ffi.cast('tp_packet_trophysolution_s2c_t*', e.data_modified_raw)
        local slotIdx  = packet.TrophyItemIndex
        local judgeFlg = packet.JudgeFlg

        -- Extract actor name from sLootName2
        local actorName = ffi.string(packet.sLootName2, 24):match('^[^%z]*')

        if judgeFlg == 0 then
            -- Someone lotted or passed
            if not memberLots[slotIdx] then
                memberLots[slotIdx] = {}
            end
            if actorName ~= '' then
                if packet.EntryPoint < 0 then
                    memberLots[slotIdx][actorName] = { lot = nil, passed = true }
                else
                    memberLots[slotIdx][actorName] = { lot = packet.EntryPoint, passed = false }
                end
            end
        elseif judgeFlg == 2 then
            -- Inventory full notification
            local inv = AshitaCore:GetMemoryManager():GetInventory()
            local item = inv:GetTreasurePoolItem(slotIdx)
            local itemName = 'item'
            if item and item.ItemId > 0 then
                local resource = AshitaCore:GetResourceManager():GetItemById(item.ItemId)
                if resource then
                    itemName = resource.Name[1] or 'item'
                end
            end
            print(chat.header('TreasurePool') .. chat.warning('Cannot obtain ' .. itemName .. ' - item lost.'))
        end
        return
    end
end

------------------------------------------------------------
-- Queue management
------------------------------------------------------------

-- Called each frame. Drains one item from each queue every 3 frames.
-- sendLot(slot) and sendPass(slot) are callbacks from treasurepool.lua.
function state.drainQueues(sendLot, sendPass)
    frameCount = frameCount + 1
    if frameCount % 3 ~= 0 then return end

    if #lotAllQueue > 0 then
        local s = table.remove(lotAllQueue, 1)
        if sendLot then sendLot(s) end
    elseif #passAllQueue > 0 then
        local s = table.remove(passAllQueue, 1)
        if sendPass then sendPass(s) end
    end
end

-- Fills lotAllQueue with slots where lot == 0; cancels any pending pass-all.
function state.addLotAll(items)
    passAllQueue = {}
    lotAllQueue  = {}
    for _, entry in ipairs(items) do
        if entry.lot == 0 then
            lotAllQueue[#lotAllQueue + 1] = entry.slot
        end
    end
end

-- Fills passAllQueue with slots where lot == 0; cancels any pending lot-all.
function state.addPassAll(items)
    lotAllQueue  = {}
    passAllQueue = {}
    for _, entry in ipairs(items) do
        if entry.lot == 0 then
            passAllQueue[#passAllQueue + 1] = entry.slot
        end
    end
end

function state.isLotAllActive()
    return #lotAllQueue > 0
end

function state.isPassAllActive()
    return #passAllQueue > 0
end

function state.reset()
    memberLots         = {}
    memberLotItemKeys  = {}
    lotAllQueue        = {}
    passAllQueue       = {}
    frameCount         = 0
    cachedItems        = {}
end

function state.getMemberLots()
    return memberLots
end

return state
