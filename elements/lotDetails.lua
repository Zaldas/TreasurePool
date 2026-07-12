local imgui = require('imgui')
local state = require('state')

local lotDetails = {}

-- Ashita 4.3 changed BeginChild: boolean cflags replaced with ImGuiChildFlags_* enum.
-- Wrap to handle both branches transparently.
local _newChildFlags = ImGuiChildFlags_None ~= nil
local function imguiBeginChild(id, size, borders)
    if _newChildFlags then
        return imgui.BeginChild(id, size, borders and ImGuiChildFlags_Borders or ImGuiChildFlags_None)
    end
    return imgui.BeginChild(id, size, borders)
end

local function buildLotRow(name, lot, winningLot)
    local statusStr, statusColor
    if lot == nil then
        statusStr   = 'Pending'
        statusColor = { 0.5, 0.5, 0.5, 1.0 }
    elseif lot == state.LOT_PASSED then
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

function lotDetails.draw(items, lotDetailsSlot, lotDetailsOpen)
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

return lotDetails
