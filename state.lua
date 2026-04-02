------------------------------------------------------------
-- state.lua
-- Packet state logic for TreasurePool.
-- Handles 0x00D2 (Trophy List) and 0x00D3 (Trophy Solution)
-- server-to-client packets, plus lot/pass queue draining.
------------------------------------------------------------

local ffi = require('ffi')
local bit = require('bit')

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
local memberLots   = {}
local lotAllQueue  = {}
local passAllQueue = {}
local frameCount   = 0

------------------------------------------------------------
-- Packet handling
------------------------------------------------------------
function state.handlePacketIn(e)
    -- 0x00D2: Trophy List — clear member lots for this slot
    if e.id == 0x00D2 and not e.injected then
        local packet = ffi.cast('tp_packet_trophylist_s2c_t*', e.data_modified_raw)
        if packet.TrophyItemNo ~= 0 then
            local slotIdx = packet.TrophyItemIndex
            memberLots[slotIdx] = {}
        end
        return
    end

    -- 0x00D3: Trophy Solution — track member lots, handle inventory full
    if e.id == 0x00D3 and not e.injected then
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
                if packet.EntryFlg == 0 then
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
            print('[TreasurePool] Cannot obtain ' .. itemName .. ' - inventory full.')
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
    end
    if #passAllQueue > 0 then
        local s = table.remove(passAllQueue, 1)
        if sendPass then sendPass(s) end
    end
end

-- Fills lotAllQueue with slots where lot == 0
function state.addLotAll(items)
    lotAllQueue = {}
    for _, entry in ipairs(items) do
        if entry.lot == 0 then
            lotAllQueue[#lotAllQueue + 1] = entry.slot
        end
    end
end

-- Fills passAllQueue with slots where lot == 0
function state.addPassAll(items)
    passAllQueue = {}
    for _, entry in ipairs(items) do
        if entry.lot == 0 then
            passAllQueue[#passAllQueue + 1] = entry.slot
        end
    end
end

function state.reset()
    memberLots   = {}
    lotAllQueue  = {}
    passAllQueue = {}
    frameCount   = 0
end

function state.getMemberLots()
    return memberLots
end

return state
