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

    local function drawBody()
        if imgui.BeginTabBar('tpSettingsTabs') then

            ----------------------------------------------------
            -- Tab: Display
            ----------------------------------------------------
            if imgui.BeginTabItem('Display') then
                imgui.Spacing()
                uiTheme.header('Display')

                imgui.Indent(uiTheme.indent)
                local themeIdx = { 0 }
                for i, t in ipairs(themeList) do
                    if t == (tpSettings.theme or 'Plain') then themeIdx[1] = i - 1; break end
                end
                imgui.SetNextItemWidth(uiTheme.comboWidth())
                if imgui.Combo('Theme##theme', themeIdx, table.concat(themeList, '\0') .. '\0') then
                    tpSettings.theme = themeList[themeIdx[1] + 1]
                    settings.save()
                    callbacks.onRebuild()
                end
                imgui.Spacing()

                local lockPos = { tpSettings.lockPosition == true }
                if imgui.Checkbox('Lock position', lockPos) then
                    tpSettings.lockPosition = lockPos[1]
                    lootWindow.dragEnabled = not lockPos[1]
                    settings.save()
                end
                uiTheme.helpMarker('Prevent the loot window from being dragged.')

                local collapsibleOn = { tpSettings.collapsible == true }
                if imgui.Checkbox('Collapsible header', collapsibleOn) then
                    tpSettings.collapsible = collapsibleOn[1]
                    if not collapsibleOn[1] then tpSettings.collapsed = false end
                    settings.save()
                    lootWindow.setCollapsible(collapsibleOn[1])
                end
                uiTheme.helpMarker('Click the loot window header to collapse it.')

                local customScaleOn = { (tpSettings.scale or 0) > 0 }
                if imgui.Checkbox('Custom scale', customScaleOn) then
                    tpSettings.scale = customScaleOn[1] and 1.0 or 0
                    settings.save()
                    callbacks.onRebuild()
                end
                uiTheme.helpMarker('Override the automatic scale with a manual multiplier.')
                if customScaleOn[1] then
                    imgui.Indent(uiTheme.subIndent)
                    local scaleVal = { tpSettings.scale > 0 and tpSettings.scale or 1.0 }
                    imgui.SetNextItemWidth(120)
                    if imgui.SliderFloat('##scale', scaleVal, 0.25, 2.5, 'x%.2f') then
                        tpSettings.scale = scaleVal[1]
                        callbacks.onRebuild()
                    end
                    if imgui.IsItemDeactivatedAfterEdit() then
                        settings.save()
                    end
                    imgui.Unindent(uiTheme.subIndent)
                end
                imgui.Unindent(uiTheme.indent)

                imgui.Spacing()
                uiTheme.header('Debug')

                imgui.Indent(uiTheme.indent)
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
                imgui.Unindent(uiTheme.indent)

                imgui.Spacing()
                imgui.Separator()
                imgui.Spacing()

                if uiTheme.centeredButton('Reload layout', 'ghost') then
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

                imgui.Indent(uiTheme.indent)
                if imgui.Checkbox('Show item tooltip', ttEnabled) then
                    tpSettings.tooltip.enabled = ttEnabled[1]
                    settings.save()
                end
                uiTheme.helpMarker('Hover over an item in the loot pool to see its stats and description.')

                if tt.enabled then
                    imgui.Spacing()

                    imgui.Indent(uiTheme.subIndent)
                    local ttGear = { tt.gear }
                    if imgui.Checkbox('Gear##tt', ttGear) then
                        tpSettings.tooltip.gear = ttGear[1]; settings.save()
                    end
                    uiTheme.helpMarker('Weapons and armor.')

                    local ttUsables = { tt.usables }
                    if imgui.Checkbox('Usables##tt', ttUsables) then
                        tpSettings.tooltip.usables = ttUsables[1]; settings.save()
                    end
                    uiTheme.helpMarker('Consumable items: food, medicines, scrolls, meds, etc.')

                    local ttItems = { tt.items }
                    if imgui.Checkbox('Items##tt', ttItems) then
                        tpSettings.tooltip.items = ttItems[1]; settings.save()
                    end
                    uiTheme.helpMarker('Everything else: seals, crystals, key items, etc.')
                    imgui.Unindent(uiTheme.subIndent)
                end
                imgui.Unindent(uiTheme.indent)

                imgui.Spacing()
                uiTheme.header('Lot Details')

                imgui.Indent(uiTheme.indent)
                local ttLD = { tt.lotDetails }
                if imgui.Checkbox('Show lot details', ttLD) then
                    tpSettings.tooltip.lotDetails = ttLD[1]
                    settings.save()
                end
                uiTheme.helpMarker('Left-clicking an item row opens a window\nshowing all party lot and pass results.')
                imgui.Unindent(uiTheme.indent)

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
