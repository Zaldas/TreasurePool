local imgui      = require('imgui')
local bit        = require('bit')
local lootWindow = require('elements/lootWindow')

local itemTooltip = {}

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

local function tooltipAllowedForType(itemType, tpSettings)
    local tt = tpSettings and tpSettings.tooltip
    if not tt or not tt.enabled then return false end
    if TOOLTIP_GEAR[itemType]    then return tt.gear end
    if TOOLTIP_USABLES[itemType] then return tt.usables end
    return tt.items  -- catch-all: seals, crystals, key items, fish, etc.
end

-- Item resource lookups, job lines, and description cleanup are constant per
-- itemId — cache them so hovering a row doesn't recompute them every frame.
-- Keyed by itemId; grows only with distinct items hovered (no eviction needed).
local tooltipCache = {}

local function getTooltipData(itemId)
    local cached = tooltipCache[itemId]
    if cached then return cached end

    local item = AshitaCore:GetResourceManager():GetItemById(itemId)
    if not item then return nil end

    local desc = item.Description and item.Description[1]
    local cleanedDesc = nil
    if desc and #desc > 0 then
        cleanedDesc = cleanDescription(desc)
    end

    cached = {
        item        = item,
        jobsLines   = buildJobsLines(item.Jobs),
        cleanedDesc = cleanedDesc,
    }
    tooltipCache[itemId] = cached
    return cached
end

function itemTooltip.draw(items, tpSettings)
    local entry = lootWindow.getHoveredEntry(items)
    if not entry or not entry.itemId or entry.itemId == 0 then return end

    local data = getTooltipData(entry.itemId)
    if not data then return end
    local item = data.item

    -- Intentionally uncached: depends on live tooltip settings toggles.
    if not tooltipAllowedForType(item.Type, tpSettings) then return end

    imgui.BeginTooltip()

    imgui.TextColored({ 1.0, 0.85, 0.2, 1.0 }, entry.name)

    if item.ItemLevel and item.ItemLevel > 0 then
        imgui.Text('Item Level ' .. tostring(item.ItemLevel))
    elseif item.Level and item.Level > 0 then
        imgui.Text('Lv. ' .. tostring(item.Level))
    end

    if data.jobsLines then
        for _, line in ipairs(data.jobsLines) do
            imgui.TextDisabled(line)
        end
    end

    if data.cleanedDesc then
        imgui.Separator()
        imgui.PushTextWrapPos(imgui.GetFontSize() * 22)
        imgui.TextUnformatted(data.cleanedDesc)
        imgui.PopTextWrapPos()
    end

    imgui.EndTooltip()
end

return itemTooltip
