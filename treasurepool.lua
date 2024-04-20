addon.name      = 'TreasurePool';
addon.author    = 'Shiyo, Zaldas';
addon.version   = '1.1.0.0';
addon.desc      = 'Displays your current treasure pool.';
addon.link      = 'https://ashitaxi.com/';

require('common');
local settings = require('settings');
local gdi = require('gdifonts.include')
local ffi = require('ffi');

-- FFI Trophy Prototypes [TreasurePool]
ffi.cdef[[
    // Packet: 0x00D2 - Server Trophy List (Server to Client)
    typedef struct packet_trophylist_s2c_t {
        uint16_t    id: 9;
        uint16_t    size: 7;
        uint16_t    sync;
        uint32_t    TrophyItemNum;      // PS2: TrophyItemNum
        uint32_t    TargetUniqueNo;     // PS2: TargetUniqueNo
        uint16_t    Gold;               // PS2: Gold
        uint16_t    padding00;          // PS2: (New; was Exp originally.)
        uint16_t    TrophyItemNo;       // PS2: TrophyItemNo
        uint16_t    TargetActIndex;     // PS2: TargetActIndex
        uint8_t     TrophyItemIndex;    // PS2: TrophyItemIndex
        uint8_t     Entry;              // PS2: Entry
        uint8_t     IsContainer;        // PS2: (New; did not exist.)
        uint8_t     padding01;          // PS2: (New; did not exist.)
        uint32_t    StartTime;          // PS2: StartTime
        uint16_t    IsLocallyLotted;    // PS2: (New; did not exist.)
        uint16_t    Point;              // PS2: (New; did not exist.)
        uint32_t    LootUniqueNo;       // PS2: (New; did not exist.)
        uint16_t    LootActIndex;       // PS2: (New; did not exist.)
        uint16_t    LootPoint;          // PS2: (New; did not exist.)
        uint8_t     LootActName[16];    // PS2: (New; did not exist.)
        uint8_t     NamedFlag   : 1;    // PS2: (New; did not exist.)
        uint8_t     SingleFlag  : 1;    // PS2: (New; did not exist.)
        uint8_t     Flags_2     : 2;    // PS2: (New; did not exist.)
        uint8_t     Flags_4     : 1;    // PS2: (New; did not exist.)
        uint8_t     Flags_5     : 1;    // PS2: (New; did not exist.)
        uint8_t     Flags_6     : 1;    // PS2: (New; did not exist.)
        uint8_t     Flags_7     : 1;    // PS2: (New; did not exist.)
        uint8_t     padding02[3];       // PS2: (New; did not exist.)
    } packet_trophylist_s2c_t;

    // Packet: 0x00D3 - Trophy Solution (Server To Client)
    typedef struct packet_trophysolution_s2c_t {
        uint16_t    id: 9;
        uint16_t    size: 7;
        uint16_t    sync;
        uint32_t    LootUniqueNo;           // PS2: LootUniqueNo
        uint32_t    EntryUniqueNo;          // PS2: EntryUniqueNo
        uint16_t    LootActIndex;           // PS2: LootActIndex
        int16_t     LootPoint;              // PS2: LootPoint
        uint16_t    EntryActIndex   : 15;   // PS2: EntryActIndex
        uint16_t    EntryFlg        : 1;    // PS2: EntryFlg
        int16_t     EntryPoint;             // PS2: EntryPoint
        uint8_t     TrophyItemIndex;        // PS2: TrophyItemIndex
        uint8_t     JudgeFlg;               // PS2: JudgeFlg
        uint8_t     sLootName[16];          // PS2: sLootName
        uint8_t     sLootName2[24];         // PS2: (New; did not exist.)
    } packet_trophysolution_s2c_t;

    // Packet: 0x0042 - Trophy Absence (Client to Server)
    typedef struct packet_trophyabsence_c2s_t {
        uint16_t    id: 9;
        uint16_t    size: 7;
        uint16_t    sync;
        uint8_t     TrophyItemIndex;    // PS2: TrophyItemIndex
        uint8_t     padding00;          // PS2: (New; did not exist.)
    } packet_trophyabsence_c2s_t;
        
]];

local windowWidth = AshitaCore:GetConfigurationManager():GetFloat('boot', 'ffxi.registry', '0001', 1024);
local windowHeight = AshitaCore:GetConfigurationManager():GetFloat('boot', 'ffxi.registry', '0002', 768);

local default_settings = T{
    anchor = {
        x = 200,
        y = 200,
    },
    colors = {
        default = 0xFFD3D3D3, -- light grey
        lot = 0xFFFF8C00, -- dark orange
        pass = 0xFF739BD0, -- icy blue
        winner = 0xFFFECE43, -- gold
    },
    layoutOffset = {
        -- Position Settings to properly align text and BG
        y_offset = 24, -- Offset between rows of each Item
        x_offset = 7, -- Offset between Columns of Item and Lot Results
        header_y_offset = 30, -- Offset header/title
        item_x_offset = 150, -- item offset for left alignment
        bg_x_offset = 160, -- BG rect x offset
        bg_y_offset = 40, -- BG rect y offset
        bg_height_start = 45, -- Initial height of BG without any entries
    },
    tpItemFont = {
        font_color = 0xFFD3D3D3,
        font_family = 'Lucida Sans Unicode', -- This could be Arial but we need to use a font that is most likely installed by default
        font_height = 16,
        outline_color = 0xFFB2BEB5,
        outline_width = 0,
        visible = false,
    },
	tpHeaderFont = {
        font_alignment = gdi.Alignment.Center,
        font_color = 0xFF9FC8F2,
        font_family = 'Arial', -- This could be Arial but we need to use a font that is most likely installed by default
        font_flags = gdi.FontFlags.Underline,
        font_height = 24,
        outline_color = 0xFF0041AB,
        outline_width = 0,
        visible = false,
    },
    bgRect = {
        width = 350,
        height = 45,
        corner_rounding = 5,
        outline_color = 0xFF000000,
        outline_width = 0,
        fill_color = 0xBF010640,
        gradient_style = gdi.Gradient.TopToBottom,
        gradient_color = 0x59010640,
        
        visible = false,
        z_order = -1,
    }
};

local treasurepool = T{
	settings = settings.load(default_settings),
    -- Debug variable for testing/positioning
    debug = false,
    debugCount = 10,
    debugPacket = false,
};

-- Table to hold all items and their lots, and header
local tpText = {}
local tpTitle = nil;
local tpBgRect = nil;

local function formatLot(lot)
    if lot == nil then
        return;
    end
    local lotText = tostring(lot);
    if lot < 10 then
        lotText = '00' .. lotText;
    elseif lot < 100 then
        lotText = '0' .. lotText;
    end
    return lotText;
end

-- Define a table to act as an enum
local TreasureStatus = {
    None = 0,
    Pass = 1,
    Lot = 2,
    Winner = 3
}

local function getTreasureStatusColor(status)
    local c = treasurepool.settings.colors;
    if status == TreasureStatus.Pass then
        return c.pass;
    elseif status == TreasureStatus.Lot then
        return c.lot;
    elseif status == TreasureStatus.Winner then
        return c.winner;
    else
        return c.default;
    end
end

-- Function to add an item and its lot result
local function addItem(i, name, lot, winner, status)
    local s = treasurepool.settings;
    local lotText = '';
    local lotColor = getTreasureStatusColor(status);
    tpText[i].name:set_text(name);
    if status ~= TreasureStatus.Pass then
        if winner == '' then
        -- if no one lotted yet
            lotText = string.format("%s", formatLot(lot));
        else
            lotText = string.format("%s:%s", formatLot(lot), winner);
        end
    end
    tpText[i].lot:set_text(tostring(lotText));

    tpText[i].name:set_font_color(lotColor);
    tpText[i].lot:set_font_color(lotColor);

    tpText[i].name:set_visible(true);
    tpText[i].lot:set_visible(true);
end

local function GetTreasureData()
    local outTable = T{};
    for i = 0,9 do
        local treasureItem = AshitaCore:GetMemoryManager():GetInventory():GetTreasurePoolItem(i);
        if treasureItem and (treasureItem.ItemId > 0) then
            local resource = AshitaCore:GetResourceManager():GetItemById(treasureItem.ItemId);
            outTable:append({ Item=treasureItem, Resource = resource}); --This creates a table entry with both the resource and item.  This is all you care about.
            --outTable[#outTable + 1] = { Item=treasureItem, Resource = resource.Name };
        end
    end
    return outTable;
end

-- create treasure pool objects
local function initTreasurePoolText()
    local s = treasurepool.settings;
    for i = 1, 10 do
        table.insert(tpText, {
            name = gdi:create_object(s.tpItemFont),
            lot = gdi:create_object(s.tpItemFont),
        })
    end
    
    tpTitle = gdi:create_object(s.tpHeaderFont);
    tpTitle:set_text('Treasure Pool');

    tpBgRect = gdi:create_rect(s.bgRect, false);
end

local function destroyTreasurePoolText()
    for i = 1, 10 do
        gdi:destroy_object(tpText[i].name);
        gdi:destroy_object(tpText[i].lot);
    end
    
    gdi:destroy_object(tpTitle);
    gdi:destroy_object(tpBgRect);
end

-- layout trasure pool objects
local function layoutTreasurePool()
    local s = treasurepool.settings;
    local l = s.layoutOffset;
    for i = 1, 10 do
        tpText[i].name:set_font_alignment(gdi.Alignment.Left);
        tpText[i].name:set_position_x(s.anchor.x - l.item_x_offset);
        tpText[i].name:set_position_y(s.anchor.y + (i-1) * l.y_offset);

        tpText[i].lot:set_font_alignment(gdi.Alignment.Left);
        tpText[i].lot:set_position_x(s.anchor.x + l.x_offset);
        tpText[i].lot:set_position_y(s.anchor.y + (i-1) * l.y_offset);
    end
    
    local title_x_offset = (s.bgRect.width/2 - l.item_x_offset) / 2;
    tpTitle:set_position_x(s.anchor.x + title_x_offset);
    tpTitle:set_position_y(s.anchor.y - l.header_y_offset);

    tpBgRect:set_position_x(s.anchor.x - l.bg_x_offset);
    tpBgRect:set_position_y(s.anchor.y - l.bg_y_offset);
end

local UpdateSettings = function(settings)
    treasurepool.settings = settings;
end

ashita.events.register('load', 'load_cb', function ()
    initTreasurePoolText();
    layoutTreasurePool();
    settings.register('settings', 'settingchange', UpdateSettings);
end);

-- Hardcoded table of items and their lots
-- lot/pass support not yet working
local dTreasurePool = {
    {name = "Suzaku's Sune-Ate", lot = 987, lotWinner = "George", winningLot = 987},
    {name = "Crystal Orb", lot = 0, lotWinner = "Beatrice", winningLot = 243},
    {name = "Magic Shield", lot = 56, lotWinner = "Charlotte", winningLot = 756},
    {name = "Enchanted Rod", lot = 0, lotWinner = "", winningLot = 0},
    {name = "Dragon Helm", lot = 65535, lotWinner = "Eleanor", winningLot = 720},
    {name = "Wizard Cloak", lot = 0, lotWinner = "", winningLot = 0},
    {name = "Silver Ring", lot = 890, lotWinner = "George", winningLot = 890},
    {name = "Healing Potion", lot = 65535, lotWinner = "", winningLot = 0},
    {name = "Mystic Boots", lot = 8, lotWinner = "Isabella", winningLot = 52},
    {name = "Golden Coin", lot = 901, lotWinner = "Jacob", winningLot = 997},
}

local function clearTreasurePool()
    local s = treasurepool.settings;
    for i, item in ipairs(dTreasurePool) do
        tpText[i].name:set_visible(false);
        tpText[i].lot:set_visible(false);
        tpText[i].name:set_font_color(s.colors.default);
        tpText[i].lot:set_font_color(s.colors.default);
    end
    tpTitle:set_visible(false);
    tpBgRect:set_visible(false);
end

local function getTreasureStatus(lot, winningLot)
    if lot > 0 and lot == winningLot then
        return TreasureStatus.Winner;
    elseif lot > 1000 then
        return TreasureStatus.Pass;
    elseif lot > 0 and winningLot > 0 then
        return TreasureStatus.Lot;
    else
        return TreasureStatus.None;
    end
end

ashita.events.register('d3d_present', 'present_cb', function ()
    local l = treasurepool.settings.layoutOffset;
    if treasurepool.debug then
        clearTreasurePool();
        local count = 0;
        for i, item in ipairs(dTreasurePool) do
            --print(i .. ". " .. item.name .. " - Lot: " .. item.lot)
            local tStatus = getTreasureStatus(item.lot, item.winningLot);
            addItem(i, item.name, item.winningLot, item.lotWinner, tStatus);
            count = i;
            if i == treasurepool.debugCount then
                break;
            end
        end
        if count > 0 then
            tpTitle:set_visible(true);
            tpBgRect:set_height(l.bg_height_start + count * l.y_offset);
            tpBgRect:set_visible(true);
        end
    else
        clearTreasurePool();
        local treasurePool = GetTreasureData();
        local count = 0;
        for i, entry in pairs(treasurePool) do
            local name = entry.Item.WinningEntityName
            if (entry.Item.WinningLot == 0) then
                name = '';
            elseif (type(name) ~= 'string') or (string.len(name) < 3) then
                name = 'Unknown';
            end
            local tStatus = getTreasureStatus(entry.Item.Lot, entry.Item.WinningLot);
            addItem(i, entry.Resource.Name[1], entry.Item.WinningLot, name, tStatus);
            count = i;
        end
        -- check we had items in treasure pool
        if count > 0 then
            tpTitle:set_visible(true);
            tpBgRect:set_height(l.bg_height_start + count * l.y_offset);
            tpBgRect:set_visible(true);
        end
    end
end);

ashita.events.register('unload', 'unload_cb', function ()
    destroyTreasurePoolText();
    gdi:destroy_interface();
end);

ashita.events.register('command', 'treasurepool_command', function (e)
    -- Parse the command arguments..
    local args = e.command:args()
    if (#args == 0 or args[1] ~= '/treasurepool') then
        return
    end
    e.blocked = true

    -- Handle: /treasurepool debug [#]- Force display the trasure pool window
    -- optional # for number of items in treasure pool
    if (#args >= 2 and args[2]:any('debug')) then
        treasurepool.debug = not treasurepool.debug;
        if (#args == 3) then
            local value = tonumber(args[3])
            if value and value > 0 and value <= 10 then
                treasurepool.debugCount = value;
                treasurepool.debug = true;
            end
        end
        print('Debug: ' .. tostring(treasurepool.debug));
        return
    end

    if (#args > 2 and args[2]:any('setx', 'sety')) then
        local value = tonumber(args[3]);
        if value and value >= 0 then
            print(args[2] .. ':' .. tostring(args[3]));
            if args[2]:any('setx') and value < windowWidth then
                treasurepool.settings.anchor.x = value;
            end

            if args[2]:any('sety') and value < windowHeight then
                treasurepool.settings.anchor.y = value;
            end
        end
        layoutTreasurePool();
        settings.save();
        return
    end

    -- no found arguments
    local helpText = 'Treasure Pool:\n';
    helpText = helpText .. '  debug # -- enables debug; optional number of treasure pool items 1-10\n';
    helpText = helpText .. '  setx # -- set x anchor point\n';
    helpText = helpText .. '  sety # -- set y anchor point\n';
    print(helpText)
end)

-- Debugging for packet
-- Improvement to pass/lot
local function appendPacketInfo(text, field, value)
    if value ~= nil then
        return text .. ' ' .. field .. ':' .. tostring(value) .. '\n';
    end
    return text .. 'Error\n';
end

-- Function to get the enum name from a given numeric value
local function getTreasureStatus(value)
    for name, num in pairs(TreasureStatus) do
        if num == value then
            return name
        end
    end
    return nil  -- If no matching value is found
end

ashita.events.register('packet_in', 'treasurepool_packet_in', function(e)
    if not treasurepool.debugPacket then
        return;
    end

    local text = '';
    if e.id == 0x00D2 and not e.injected then  -- Check if it's a trophy list
        local packet = ffi.cast('packet_trophylist_s2c_t*', e.data_modified_raw);
        if (packet.TrophyItemNo ~= 0) then  -- check for item drops only
            text = 'Trophy List\n';
            text = appendPacketInfo(text, 'TrophyItemIndex', packet.TrophyItemIndex);
            text = appendPacketInfo(text, 'Entry', getTreasureStatus(packet.Entry));
            text = appendPacketInfo(text, 'IsLocallyLotted', packet.IsLocallyLotted);
        end
    elseif e.id == 0x00D3 and not e.injected then  -- Check if it's a trophy solution
        text = 'Trophy Solution\n';
        local packet = ffi.cast('packet_trophysolution_s2c_t*', e.data_modified_raw);
        text = appendPacketInfo(text, 'TrophyItemIndex', packet.TrophyItemIndex);
        text = appendPacketInfo(text, 'EntryFlg', packet.EntryFlg);
    end
    
    if text ~= '' then
        print(text);
    end
end)

ashita.events.register('packet_out', 'treasurepool_packet_out', function(e)
    if not treasurepool.debugPacket then
        return;
    end

    local text = '';
    if e.id == 0x0042 and not e.injected then  -- Check trophy absence (pass)
        text = 'Trophy Absence\n';
        local packet = ffi.cast('packet_trophyabsence_c2s_t*', e.data_modified_raw);
        text = appendPacketInfo(text, 'TrophyItemIndex', packet.TrophyItemIndex);
    end

    if text ~= '' then
        print(text);
    end
end)