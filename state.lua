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

state.LOT_PASSED = 65535
state.POOL_TTL   = 300

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
        uint8_t     sLootName2[16];
        uint8_t     padding36[6];
    } tp_packet_trophysolution_s2c_t;

    // Packet: 0x0020 - Item Attr (Server to Client)
    // Sent to populate an item's full information; fires whenever an
    // inventory item slot changes. Only ItemNo is read; the remaining
    // fields exist so ffi.sizeof matches the wire format (0x2C bytes)
    // for bounds-checking.
    typedef struct tp_packet_itemattr_s2c_t {
        uint16_t    id: 9;
        uint16_t    size: 7;
        uint16_t    sync;
        uint32_t    ItemNum;
        uint32_t    Price;
        uint16_t    ItemNo;
        uint8_t     Category;
        uint8_t     ItemIndex;
        uint8_t     LockFlg;
        uint8_t     Attr[24];
        uint8_t     padding29[3];
    } tp_packet_itemattr_s2c_t;
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
local reconcileFrame     = 0
local cachedItems        = {}

-- Deferred 0x0020 rare-recompute queue (see state.processPendingRareRecompute
-- for why this can't be computed synchronously inside handlePacketIn).
local pendingRareRecomputeAll = false
local pendingRareRecomputeIds = {}

------------------------------------------------------------
-- Rare ownership
------------------------------------------------------------
-- All personal storage containers; excludes Temporary (3) and Recycle (17).
local OWNED_CONTAINERS = { 0, 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }

-- Returns true if the player already owns a copy of itemId in any personal
-- storage container. Self-sufficient: fetches inventory directly.
function state.playerOwnsRareItem(itemId)
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    if not inv then return false end
    for _, container in ipairs(OWNED_CONTAINERS) do
        local max = inv:GetContainerCountMax(container)
        for slot = 0, max - 1 do
            local item = inv:GetContainerItem(container, slot)
            if item and item.Id == itemId then return true end
        end
    end
    return false
end

-- Returns whether the player owns itemId, but only scans inventory when the
-- item is actually flagged Rare (0x8000); non-rare items are never "owned"
-- for pool purposes.
local function computeRareOwned(itemId)
    local resource = AshitaCore:GetResourceManager():GetItemById(itemId)
    local isRare   = resource and bit.band(resource.Flags, 0x8000) ~= 0
    if isRare then
        return state.playerOwnsRareItem(itemId)
    end
    return false
end

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

-- Replaces cachedItems with the provided table and sorts it descending by
-- expiresAt. Used only by the load-event prime from gatherTreasureData().
-- Entries arriving without a rareOwned field get it computed here, since the
-- packet-driven paths (0x00D2 insert / 0x0020 invalidation) never saw them.
function state.setItems(items)
    cachedItems = items
    table.sort(cachedItems, function(a, b) return a.expiresAt > b.expiresAt end)
    for _, item in ipairs(cachedItems) do
        if item.rareOwned == nil then
            item.rareOwned = computeRareOwned(item.itemId)
        end
    end
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

-- Clears stale winner entries when the winning member is no longer in the
-- local player's zone. The server retracts lots on zone-out but sends no
-- packet for it, so this is a periodic reconciliation against party memory.
-- Throttled to run its scan once every 30 calls (mirrors the 30-frame cache
-- refresh cadence elsewhere in the addon). Call this once per frame.
function state.reconcileWinners()
    reconcileFrame = reconcileFrame + 1
    if reconcileFrame % 30 ~= 0 then return end

    if #cachedItems == 0 then return end

    local partyMem = AshitaCore:GetMemoryManager():GetParty()
    if not partyMem then return end

    local myZone = partyMem:GetMemberZone(0)
    local inZone = {}
    for i = 0, 17 do
        if partyMem:GetMemberIsActive(i) ~= 0 and partyMem:GetMemberZone(i) == myZone then
            local n = partyMem:GetMemberName(i)
            if type(n) == 'string' and #n >= 3 then
                inZone[n] = true
            end
        end
    end

    for _, entry in ipairs(cachedItems) do
        if entry.winnerName ~= '' and not inZone[entry.winnerName] then
            entry.winningLot = 0
            entry.winnerName = ''
        end
    end
end

-- Applies rare-ownership recomputes queued by the 0x0020 handler in
-- handlePacketIn. packet_in fires before the client applies the packet to
-- its own inventory memory, so computeRareOwned would read stale pre-packet
-- state if called synchronously there; queuing here and consuming on the
-- next d3d_present frame lets the client settle the packet first.
-- Unlike reconcileWinners, this is intentionally unthrottled: it's a cheap
-- no-op when nothing is queued, and the whole point of deferring is minimal
-- added latency ("next frame," not "next 30 frames"). Call this once per
-- frame.
function state.processPendingRareRecompute()
    if pendingRareRecomputeAll then
        for _, entry in ipairs(cachedItems) do
            if entry.rareOwned then
                entry.rareOwned = computeRareOwned(entry.itemId)
            end
        end
        pendingRareRecomputeAll = false
    end
    if next(pendingRareRecomputeIds) then
        for _, entry in ipairs(cachedItems) do
            if pendingRareRecomputeIds[entry.itemId] then
                entry.rareOwned = computeRareOwned(entry.itemId)
            end
        end
        pendingRareRecomputeIds = {}
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
local function getPlayerName()
    local party = AshitaCore:GetMemoryManager():GetParty()
    local name  = party and party:GetMemberName(0)
    return (type(name) == 'string' and #name > 0) and name or 'You'
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
        expiresAt  = os.time() + state.POOL_TTL,
        playerName = getPlayerName(),
        -- populated by 0x00D3 lot/pass packets as they arrive
        partyLots  = {},
    }
end

function state.handlePacketIn(e)
    -- 0x00D2: Trophy List — clear member lots for this slot only when the item changes
    if e.id == 0x00D2 then
        if e.size < ffi.sizeof('tp_packet_trophylist_s2c_t') then return end
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

        if packet.TrophyItemNo == 0 then
            state.removeFromCache(slotIdx)
        else
            local item = buildItemFromPacket(packet)
            item.rareOwned = computeRareOwned(item.itemId)
            state.insertSorted(item)
        end
        return
    end

    -- 0x0020: Item Attr — an inventory item slot changed; queue rare
    -- ownership recompute for any pool entries matching the affected item.
    -- Deferred: packet_in fires before the client applies this packet to
    -- inventory memory, so a synchronous read here would see stale
    -- pre-packet state. Actual recompute happens next frame in
    -- state.processPendingRareRecompute().
    if e.id == 0x0020 then
        if e.size < ffi.sizeof('tp_packet_itemattr_s2c_t') then return end
        local packet = ffi.cast('tp_packet_itemattr_s2c_t*', e.data_modified_raw)
        local itemNo = packet.ItemNo
        if itemNo == 0 then
            -- Removal/slot-clear event (item used/traded/sold/dropped, or
            -- quantity hit 0): the server omits ItemNo when PItem is null,
            -- so the affected item can't be identified from the packet.
            -- Only previously-owned entries can flip to unowned on a
            -- removal, so re-check every entry currently flagged owned.
            pendingRareRecomputeAll = true
        else
            pendingRareRecomputeIds[itemNo] = true
        end
        return
    end

    -- 0x00D3: Trophy Solution — track member lots, handle inventory full
    if e.id == 0x00D3 then
        if e.size < ffi.sizeof('tp_packet_trophysolution_s2c_t') then return end
        local packet = ffi.cast('tp_packet_trophysolution_s2c_t*', e.data_modified_raw)
        local slotIdx  = packet.TrophyItemIndex
        local judgeFlg = packet.JudgeFlg

        -- Extract actor name from sLootName2
        local actorName = ffi.string(packet.sLootName2, 16):match('^[^%z]*')

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

            -- Update existing cache entry in-place (no re-sort; expiresAt unchanged)
            for _, entry in ipairs(cachedItems) do
                if entry.slot == slotIdx then
                    -- Update current winner
                    local winnerName = ffi.string(packet.sLootName, 16):match('^[^%z]*')
                    entry.winningLot = packet.LootPoint
                    entry.winnerName = (packet.LootPoint > 0 and #winnerName >= 3) and winnerName or ''

                    -- Record this actor's lot/pass in partyLots
                    if #actorName >= 3 then
                        entry.partyLots[actorName] = (packet.EntryPoint < 0) and state.LOT_PASSED or packet.EntryPoint
                    end

                    -- Update local lot if this action was ours
                    if actorName == getPlayerName() then
                        entry.lot = entry.partyLots[actorName]
                    end
                    break
                end
            end
        elseif judgeFlg == 1 then
            -- Item awarded — remove from pool
            state.removeFromCache(slotIdx)
        elseif judgeFlg == 2 then
            -- Inventory full notification
            local inv = AshitaCore:GetMemoryManager():GetInventory()
            local itemName = 'item'
            if inv then
                local item = inv:GetTreasurePoolItem(slotIdx)
                if item and item.ItemId > 0 then
                    local resource = AshitaCore:GetResourceManager():GetItemById(item.ItemId)
                    if resource then
                        itemName = resource.Name[1] or 'item'
                    end
                end
            end
            print(chat.header('TreasurePool') .. chat.warning('Cannot obtain ' .. itemName .. ' - item lost.'))
            state.removeFromCache(slotIdx)
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

function state.isPassAllActive()
    return #passAllQueue > 0
end

function state.reset()
    memberLots              = {}
    memberLotItemKeys       = {}
    lotAllQueue             = {}
    passAllQueue            = {}
    frameCount              = 0
    cachedItems             = {}
    pendingRareRecomputeAll = false
    pendingRareRecomputeIds = {}
end

function state.getMemberLots()
    return memberLots
end

return state
