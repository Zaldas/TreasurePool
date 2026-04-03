------------------------------------------------------------
-- elements/lootWindow.lua
-- Module that owns the sprite engine, root container,
-- and manages all lootItem instances.
------------------------------------------------------------

local sprites      = require('libs/spui/sprites')
local uiContainer  = require('libs/spui/uiContainer')
local uiBackground = require('libs/spui/uiBackground')
local uiImage      = require('libs/spui/uiImage')
local uiText       = require('libs/spui/uiText')
local uiButton     = require('libs/spui/uiButton')
local lootItem     = require('elements/lootItem')
local utils        = require('libs/spui/utils')
local bit          = require('bit')

local lootWindow = {}

-- Module-level state
local engine        = nil
local root          = nil
local windowBg      = nil
local bgMode        = 'flat'    -- 'flat' | '3slice' | 'window'; set in initialize
local borderEngine  = nil
local windowBorders = nil       -- { tl, tr, bl, br } uiImages when bgMode='window', else nil
local bgBorderSize  = 21
local bgBorderOffset = 1
local titleText   = nil
local lotAllBtn   = nil
local passAllBtn  = nil
local lootItems   = {}
local lastCount   = -1
local hoveredIdx  = nil
local pressedBtn  = nil
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

local function updateBorders(totalH)
    if not windowBorders then return end
    local W      = layout.window.width
    local bSize  = bgBorderSize
    local bOff   = bgBorderOffset

    local brX    = W - (bSize - bOff)      -- x where right-side pieces start
    local brY    = totalH - (bSize - bOff) -- y where bottom-side pieces start
    local leftW  = brX + bOff              -- width of tl and bl pieces
    local edgeH  = brY + bOff              -- height of tl and tr pieces

    windowBorders.tl.posX = -bOff
    windowBorders.tl.posY = -bOff
    windowBorders.tl:size(leftW, edgeH)

    windowBorders.tr.posX = brX
    windowBorders.tr.posY = -bOff
    windowBorders.tr:size(bSize, edgeH)

    windowBorders.bl.posX = -bOff
    windowBorders.bl.posY = brY
    windowBorders.bl:size(leftW, bSize)

    windowBorders.br.posX = brX
    windowBorders.br.posY = brY
    windowBorders.br:size(bSize, bSize)
end

local function relayout(count)
    local W   = layout.window.width
    local H_H = layout.window.headerH
    local R_H = layout.window.rowH
    local F_H = layout.window.footerH
    local PAD = layout.window.pad
    local totalH = H_H + count * R_H + F_H

    if bgMode == '3slice' then
        windowBg:setHeight(totalH)
    else
        windowBg:size(W, totalH)
    end
    if bgMode == 'window' then
        updateBorders(totalH)
    end

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

local function hitTestWindow(mx, my)
    if not root or not root.absoluteVisibility then return false end
    local ax = root.absolutePos.x
    local ay = root.absolutePos.y
    local W  = layout.window.width * root.absoluteScale.x
    local n  = lastCount > 0 and lastCount or 0
    local H  = (layout.window.headerH + n * layout.window.rowH + layout.window.footerH) * root.absoluteScale.y
    return mx >= ax and mx < ax + W and my >= ay and my < ay + H
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------
function lootWindow.initialize(layoutRef, bgDef, anchorRef, scale)
    layout  = layoutRef
    anchor  = anchorRef
    uiScale = scale
    bgMode  = (bgDef and bgDef.mode) or 'flat'
    engine  = sprites.newEngine()

    root = uiContainer.new()
    root.posX   = anchor.x
    root.posY   = anchor.y
    root.scaleX = uiScale
    root.scaleY = uiScale

    -- Window background (full size computed during relayout; first child = renders behind content)
    if bgMode == '3slice' then
        windowBg = uiBackground.new(bgDef, engine)
    elseif bgMode == 'window' then
        windowBg = uiImage.new({
            path  = bgDef.bgPath,
            size  = { layout.window.width, layout.window.headerH },
            pos   = { 0, 0 },
            color = bgDef.color or '#FFFFFFFF',
        }, engine)
    else
        windowBg = uiImage.new({
            path  = 'layouts/assets/pixel.png',
            size  = { layout.window.width, layout.window.headerH },
            pos   = { 0, 0 },
            color = layout.window.bg.color,
        }, engine)
    end
    root:addChild(windowBg)

    -- Border pieces for 'window' mode: use a second engine created after the main one
    -- so all border sprites render on top of main-engine content (engines render in creation order)
    if bgMode == 'window' and bgDef.borderSet then
        bgBorderSize   = bgDef.borderSize or 21
        bgBorderOffset = bgDef.bgOffset   or 1
        borderEngine = sprites.newEngine()

        local base = 'layouts/assets/backgrounds/' .. bgDef.borderSet
        local W    = layout.window.width
        local bSz  = bgBorderSize
        windowBorders = {
            tl = uiImage.new({ path = base .. '-tl.png', size = { W,   1   }, pos = { 0, 0 }, color = '#FFFFFFFF' }, borderEngine),
            tr = uiImage.new({ path = base .. '-tr.png', size = { bSz, 1   }, pos = { 0, 0 }, color = '#FFFFFFFF' }, borderEngine),
            bl = uiImage.new({ path = base .. '-bl.png', size = { W,   bSz }, pos = { 0, 0 }, color = '#FFFFFFFF' }, borderEngine),
            br = uiImage.new({ path = base .. '-br.png', size = { bSz, bSz }, pos = { 0, 0 }, color = '#FFFFFFFF' }, borderEngine),
        }
        root:addChild(windowBorders.tl)
        root:addChild(windowBorders.tr)
        root:addChild(windowBorders.bl)
        root:addChild(windowBorders.br)
    end

    -- Title text
    titleText = uiText.new(layout.title)
    root:addChild(titleText)

    -- Footer buttons (positions set in relayout)
    lotAllBtn  = uiButton.new(layout.footer.lotAllBtn, engine)
    passAllBtn = uiButton.new(layout.footer.passAllBtn, engine)
    root:addChild(lotAllBtn)
    root:addChild(passAllBtn)
    lotAllBtn:hide(utils.VIS_TOKEN)
    passAllBtn:hide(utils.VIS_TOKEN)

    -- Create all primitives
    root:createPrimitives()

    titleText:update('Treasure Pool')
    lotAllBtn:setText('Lot All')
    passAllBtn:setText('Pass All')

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
        item.lotBtn:setText('Lot')
        item.passBtn:setText('Pass')
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
    local hasUnlotted   = false
    local hasActionable = false
    for i, item in ipairs(lootItems) do
        if items[i] then
            item:update(items[i], hoveredIdx == i)
            if items[i].lot == 0        then hasUnlotted   = true end
            if items[i].lot ~= 65535    then hasActionable = true end
        end
    end

    -- Footer button visibility: Lot All only for unlotted; Pass All for anything not yet passed
    if hasUnlotted then
        lotAllBtn:show(utils.VIS_TOKEN)
    else
        lotAllBtn:hide(utils.VIS_TOKEN)
    end
    if hasActionable then
        passAllBtn:show(utils.VIS_TOKEN)
    else
        passAllBtn:hide(utils.VIS_TOKEN)
    end

    -- Update button hover states every frame
    lotAllBtn:setHover(lotAllBtn.absoluteVisibility and lotAllBtn:hitTest(mouseX, mouseY))
    passAllBtn:setHover(passAllBtn.absoluteVisibility and passAllBtn:hitTest(mouseX, mouseY))
    for _, item in ipairs(lootItems) do
        item.lotBtn:setHover(item.lotBtn.absoluteVisibility and item.lotBtn:hitTest(mouseX, mouseY))
        item.passBtn:setHover(item.passBtn.absoluteVisibility and item.passBtn:hitTest(mouseX, mouseY))
    end

    -- Clear pressed state if button was hidden (e.g. item got lotted)
    if pressedBtn and not pressedBtn.absoluteVisibility then
        pressedBtn:setPressed(false)
        pressedBtn = nil
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

        -- Block all clicks within the window — prevents click-through to game
        if not hitTestWindow(e.x, e.y) then
            return false
        end
        e.blocked = true

        if lootWindow.dragEnabled and hitTestHeader(e.x, e.y) then
            isDragging = true
            dragOff.x = e.x - anchor.x
            dragOff.y = e.y - anchor.y
            return false
        end

        if lotAllBtn:hitTest(e.x, e.y) and lotAllBtn.absoluteVisibility then
            pressedBtn = lotAllBtn
            lotAllBtn:setPressed(true)
            if lootWindow.onLotAll then lootWindow.onLotAll() end
            return false
        end

        if passAllBtn:hitTest(e.x, e.y) and passAllBtn.absoluteVisibility then
            pressedBtn = passAllBtn
            passAllBtn:setPressed(true)
            if lootWindow.onPassAll then lootWindow.onPassAll() end
            return false
        end

        for _, item in ipairs(lootItems) do
            if item.lotBtn:hitTest(e.x, e.y) and item.lotBtn.absoluteVisibility then
                pressedBtn = item.lotBtn
                item.lotBtn:setPressed(true)
                if item.lotBtn.onClick then item.lotBtn.onClick() end
                return false
            end
            if item.passBtn:hitTest(e.x, e.y) and item.passBtn.absoluteVisibility then
                pressedBtn = item.passBtn
                item.passBtn:setPressed(true)
                if item.passBtn.onClick then item.passBtn.onClick() end
                return false
            end
        end

        return false
    end

    if e.message == 514 then  -- left up
        if pressedBtn then
            pressedBtn:setPressed(false)
            pressedBtn = nil
        end
        if isDragging then
            isDragging = false
            e.blocked = true
            return true
        end
        if hitTestWindow(e.x, e.y) then
            e.blocked = true
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
    if borderEngine then
        borderEngine:destroy()
        borderEngine = nil
    end
    if engine then
        engine:destroy()
        engine = nil
    end
    lastCount    = -1
    windowBg     = nil
    windowBorders = nil
    titleText    = nil
    lotAllBtn    = nil
    passAllBtn   = nil
    hoveredIdx   = nil
    pressedBtn   = nil
    isDragging   = false
end

return lootWindow
