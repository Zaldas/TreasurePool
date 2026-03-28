------------------------------------------------------------
-- elements/lootWindow.lua
-- Module that owns the sprite engine, root container,
-- and manages all lootItem instances.
------------------------------------------------------------

local sprites     = require('libs/spui/sprites')
local uiContainer = require('libs/spui/uiContainer')
local uiImage     = require('libs/spui/uiImage')
local uiText      = require('libs/spui/uiText')
local uiButton    = require('libs/spui/uiButton')
local lootItem    = require('elements/lootItem')
local utils       = require('libs/spui/utils')
local bit         = require('bit')

local lootWindow = {}

-- Module-level state
local engine      = nil
local root        = nil
local windowBg    = nil
local titleText   = nil
local lotAllBtn   = nil
local passAllBtn  = nil
local lootItems   = {}
local lastCount   = -1
local hoveredIdx  = nil
local isDragging  = false
local dragOff     = { x = 0, y = 0 }
local mouseX      = 0
local mouseY      = 0
local layout      = nil
local anchor      = nil
local uiScale     = 1

-- Callbacks (set by treasurepool.lua)
lootWindow.onLotSlot  = nil
lootWindow.onPassSlot = nil
lootWindow.onLotAll   = nil
lootWindow.onPassAll  = nil
lootWindow.dragEnabled = true

------------------------------------------------------------
-- Local helpers
------------------------------------------------------------
local function makeLotCallback(item)
    return function()
        local slot = item:getSlot()
        if slot ~= nil and lootWindow.onLotSlot then
            lootWindow.onLotSlot(slot)
        end
    end
end

local function makePassCallback(item)
    return function()
        local slot = item:getSlot()
        if slot ~= nil and lootWindow.onPassSlot then
            lootWindow.onPassSlot(slot)
        end
    end
end

local function relayout(count)
    local W   = layout.window.width
    local H_H = layout.window.headerH
    local R_H = layout.window.rowH
    local F_H = layout.window.footerH
    local PAD = layout.window.pad
    local totalH = H_H + count * R_H + F_H

    windowBg:size(W, totalH)

    -- Title
    titleText.posX = W / 2
    titleText.posY = layout.title.pos[2] or 2
    titleText:layoutElement()

    -- Rows
    for i, item in ipairs(lootItems) do
        item:setPosition(0, H_H + (i - 1) * R_H)
    end

    -- Footer buttons
    local BTN_H   = layout.footer.passAllBtn.size[2]
    local BTN_GAP = 4
    local footerY  = H_H + count * R_H + math.floor((F_H - BTN_H) / 2)
    local passAllW = layout.footer.passAllBtn.size[1]
    local lotAllW  = layout.footer.lotAllBtn.size[1]
    local passAllX = W - PAD - passAllW
    local lotAllX  = passAllX - BTN_GAP - lotAllW

    passAllBtn.posX = passAllX
    passAllBtn.posY = footerY
    passAllBtn:layoutElement()

    lotAllBtn.posX = lotAllX
    lotAllBtn.posY = footerY
    lotAllBtn:layoutElement()

    -- Re-cascade from root
    root:layoutElement()
end

local function hitTestHeader(mx, my)
    if not root then return false end
    local ax = root.absolutePos.x
    local ay = root.absolutePos.y
    local W  = layout.window.width   * root.absoluteScale.x
    local H  = layout.window.headerH * root.absoluteScale.y
    return mx >= ax and mx < ax + W and my >= ay and my < ay + H
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------
function lootWindow.initialize(layoutRef, anchorRef, scale)
    layout  = layoutRef
    anchor  = anchorRef
    uiScale = scale
    engine  = sprites.newEngine()

    root = uiContainer.new()
    root.posX   = anchor.x
    root.posY   = anchor.y
    root.scaleX = uiScale
    root.scaleY = uiScale

    -- Window background (full size computed during relayout)
    windowBg = uiImage.new({
        path  = 'layouts/assets/pixel.png',
        size  = { layout.window.width, layout.window.headerH },
        pos   = { 0, 0 },
        color = layout.window.bg.color,
    }, engine)
    root:addChild(windowBg)

    -- Title text
    titleText = uiText.new(layout.title)
    root:addChild(titleText)
    titleText:update('Treasure Pool')

    -- Footer buttons (positions set in relayout)
    lotAllBtn  = uiButton.new(layout.footer.lotAllBtn, engine)
    passAllBtn = uiButton.new(layout.footer.passAllBtn, engine)
    root:addChild(lotAllBtn)
    root:addChild(passAllBtn)
    lotAllBtn:hide(utils.VIS_TOKEN)
    passAllBtn:hide(utils.VIS_TOKEN)
    lotAllBtn:setText('Lot All')
    passAllBtn:setText('Pass All')

    -- Create all primitives
    root:createPrimitives()

    lootItems = {}
    lastCount = -1
end

function lootWindow.update(items)
    if not engine then return end

    local n = #items

    -- Sync pool: destroy excess
    while #lootItems > n do
        local item = table.remove(lootItems)
        root:removeChild(item)
        item:destroy()
    end

    -- Sync pool: create new
    while #lootItems < n do
        local item = lootItem.new(engine, layout.lootItem)
        item:setRowDimensions(layout.window.width, layout.window.rowH)
        root:addChild(item)
        item.lotBtn.onClick  = makeLotCallback(item)
        item.passBtn.onClick = makePassCallback(item)
        table.insert(lootItems, item)
    end

    -- Relayout if count changed
    if n ~= lastCount then
        relayout(n)
        lastCount = n
    end

    -- Update hover
    hoveredIdx = nil
    for i, item in ipairs(lootItems) do
        if item:hitTest(mouseX, mouseY) then
            hoveredIdx = i
        end
    end

    -- Update each item
    local hasUnlotted = false
    for i, item in ipairs(lootItems) do
        if items[i] then
            item:update(items[i], hoveredIdx == i)
            if items[i].lot == 0 then hasUnlotted = true end
        end
    end

    -- Footer button visibility
    if hasUnlotted then
        lotAllBtn:show(utils.VIS_TOKEN)
        passAllBtn:show(utils.VIS_TOKEN)
    else
        lotAllBtn:hide(utils.VIS_TOKEN)
        passAllBtn:hide(utils.VIS_TOKEN)
    end

    -- Hide entire window when pool is empty
    if root then
        if n > 0 then
            root:show(utils.VIS_TOKEN)
        else
            root:hide(utils.VIS_TOKEN)
        end
    end

    -- Per-frame uiImage update (handles deferred texture load)
    root:update()
end

-- Returns true if anchor changed (caller should save settings)
function lootWindow.handleMouse(e)
    if not engine then return false end

    if e.message == 512 then   -- mouse move
        mouseX = e.x
        mouseY = e.y
        if isDragging then
            anchor.x = e.x - dragOff.x
            anchor.y = e.y - dragOff.y
            root.posX = anchor.x
            root.posY = anchor.y
            root:layoutElement()
            e.blocked = true
            return true
        end
        return false
    end

    if e.message == 513 then  -- left down
        mouseX = e.x
        mouseY = e.y

        if lootWindow.dragEnabled and hitTestHeader(e.x, e.y) then
            isDragging = true
            dragOff.x = e.x - anchor.x
            dragOff.y = e.y - anchor.y
            e.blocked = true
            return false
        end

        if lotAllBtn:hitTest(e.x, e.y) and lotAllBtn.absoluteVisibility then
            if lootWindow.onLotAll then lootWindow.onLotAll() end
            e.blocked = true
            return false
        end

        if passAllBtn:hitTest(e.x, e.y) and passAllBtn.absoluteVisibility then
            if lootWindow.onPassAll then lootWindow.onPassAll() end
            e.blocked = true
            return false
        end

        if hoveredIdx and lootItems[hoveredIdx] then
            local item = lootItems[hoveredIdx]
            if item.lotBtn:hitTest(e.x, e.y) and item.lotBtn.absoluteVisibility then
                if item.lotBtn.onClick then item.lotBtn.onClick() end
                e.blocked = true
                return false
            end
            if item.passBtn:hitTest(e.x, e.y) and item.passBtn.absoluteVisibility then
                if item.passBtn.onClick then item.passBtn.onClick() end
                e.blocked = true
                return false
            end
        end

        return false
    end

    if e.message == 514 then  -- left up
        if isDragging then
            isDragging = false
            e.blocked = true
            return true
        end
    end

    return false
end

function lootWindow.destroy()
    for _, item in ipairs(lootItems) do
        item:destroy()
    end
    lootItems = {}
    if root then
        root:dispose()
        root = nil
    end
    if engine then
        engine:destroy()
        engine = nil
    end
    lastCount   = -1
    windowBg    = nil
    titleText   = nil
    lotAllBtn   = nil
    passAllBtn  = nil
    hoveredIdx  = nil
    isDragging  = false
end

return lootWindow
