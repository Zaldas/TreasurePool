local imgui      = require('imgui')
local settings   = require('settings')
local lootWindow = require('elements/lootWindow')
local uiTheme    = require('libs/uiTheme')

local settingsWindow = {}

------------------------------------------------------------
-- Settings Window (ImGui)
------------------------------------------------------------
function settingsWindow.draw(tpSettings, settingsOpen, themeList, callbacks)
    if not settingsOpen[1] then return end

    local indent = 6
    local function drawBody()
        local avail  = imgui.GetContentRegionAvail()
        local availW = type(avail) == 'table' and avail[1] or avail

        if imgui.BeginTabBar('tpSettingsTabs') then

            ----------------------------------------------------
            -- Tab: Display
            ----------------------------------------------------
            if imgui.BeginTabItem('Display') then
                imgui.Spacing()
                uiTheme.header('Display')

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
                uiTheme.header('Debug')

                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                local cnt = { tpSettings.debugCount }
                imgui.SetNextItemWidth(80)
                if imgui.InputInt('Items##dbg', cnt) then
                    local v = cnt[1]
                    if v >= 1 and v <= 10 then
                        tpSettings.debugCount = v
                    end
                end
                if imgui.IsItemDeactivatedAfterEdit() then
                    settings.save()
                end

                imgui.Spacing()
                imgui.Separator()
                imgui.Spacing()

                local btnW   = math.floor(availW * 0.80)
                local btnPad = math.floor((availW - btnW) * 0.5)
                imgui.SetCursorPosX(imgui.GetCursorPosX() + btnPad)
                if uiTheme.button('Reload Layout', btnW, 'ghost') then
                    callbacks.onReloadLayout()
                end

                imgui.EndTabItem()
            end

            ----------------------------------------------------
            -- Tab: Interactions
            ----------------------------------------------------
            if imgui.BeginTabItem('Interactions') then
                imgui.Spacing()
                uiTheme.header('Item Tooltip')

                local tt = tpSettings.tooltip
                local ttEnabled = { tt.enabled }

                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                if imgui.Checkbox('Show Item Tooltip', ttEnabled) then
                    tpSettings.tooltip.enabled = ttEnabled[1]
                    settings.save()
                end
                uiTheme.helpMarker('Hover over an item in the loot pool to see its stats and description.')

                if tt.enabled then
                    imgui.Spacing()

                    local subIndent = indent + 10

                    imgui.SetCursorPosX(imgui.GetCursorPosX() + subIndent)
                    local ttGear = { tt.gear }
                    if imgui.Checkbox('Gear##tt', ttGear) then
                        tpSettings.tooltip.gear = ttGear[1]; settings.save()
                    end
                    uiTheme.helpMarker('Weapons and armor.')

                    imgui.SetCursorPosX(imgui.GetCursorPosX() + subIndent)
                    local ttUsables = { tt.usables }
                    if imgui.Checkbox('Usables##tt', ttUsables) then
                        tpSettings.tooltip.usables = ttUsables[1]; settings.save()
                    end
                    uiTheme.helpMarker('Consumable items: food, medicines, scrolls, meds, etc.')

                    imgui.SetCursorPosX(imgui.GetCursorPosX() + subIndent)
                    local ttItems = { tt.items }
                    if imgui.Checkbox('Items##tt', ttItems) then
                        tpSettings.tooltip.items = ttItems[1]; settings.save()
                    end
                    uiTheme.helpMarker('Everything else: seals, crystals, key items, etc.')
                end

                imgui.Spacing()
                uiTheme.header('Lot Details')

                imgui.SetCursorPosX(imgui.GetCursorPosX() + indent)
                local ttLD = { tt.lotDetails }
                if imgui.Checkbox('Show Lot Details', ttLD) then
                    tpSettings.tooltip.lotDetails = ttLD[1]
                    settings.save()
                end
                uiTheme.helpMarker('Left-clicking an item row opens a window\nshowing all party lot and pass results.')

                imgui.Spacing()
                imgui.EndTabItem()
            end

            imgui.EndTabBar()
        end
    end

    local n = uiTheme.push()
    imgui.SetNextWindowSizeConstraints({ 270, 0 }, { 270, 9999 })
    local ok, err = true, nil
    if imgui.Begin('TreasurePool.' .. addon.version, settingsOpen, ImGuiWindowFlags_AlwaysAutoResize) then
        ok, err = pcall(drawBody)
    end
    imgui.End()
    uiTheme.pop(n)
    if not ok then error(err, 0) end
end

return settingsWindow
