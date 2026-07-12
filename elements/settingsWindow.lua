local imgui      = require('imgui')
local settings   = require('settings')
local lootWindow = require('elements/lootWindow')

local settingsWindow = {}

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
function settingsWindow.draw(tpSettings, settingsOpen, themeList, callbacks)
    if not settingsOpen[1] then return end

    local indent = 6
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 6.0)
    imgui.SetNextWindowSizeConstraints({ 270, 0 }, { 270, 9999 })
    if imgui.Begin('TreasurePool.' .. addon.version, settingsOpen, ImGuiWindowFlags_AlwaysAutoResize) then
        local avail  = imgui.GetContentRegionAvail()
        local availW = type(avail) == 'table' and avail[1] or avail

        if imgui.BeginTabBar('tpSettingsTabs') then

            ----------------------------------------------------
            -- Tab: Display
            ----------------------------------------------------
            if imgui.BeginTabItem('Display') then
                imgui.Spacing()
                drawGradientHeader('Display')

                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                local themeIdx = { 0 }
                for i, t in ipairs(themeList) do
                    if t == (tpSettings.theme or 'Plain') then themeIdx[1] = i - 1; break end
                end
                imgui.SetNextItemWidth(math.floor((availW - indent) * 0.65))
                if imgui.Combo('Theme##theme', themeIdx, table.concat(themeList, '\0') .. '\0') then
                    tpSettings.theme = themeList[themeIdx[1] + 1]
                    settings.save()
                    callbacks.onRebuild()
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
                    callbacks.onRebuild()
                end
                if customScaleOn[1] then
                    imgui.SameLine()
                    local scaleVal = { tpSettings.scale > 0 and tpSettings.scale or 1.0 }
                    imgui.SetNextItemWidth(120)
                    if imgui.SliderFloat('##scale', scaleVal, 0.25, 2.5, 'x%.2f') then
                        tpSettings.scale = scaleVal[1]
                        settings.save()
                        callbacks.onRebuild()
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
                    callbacks.onReloadLayout()
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

return settingsWindow
