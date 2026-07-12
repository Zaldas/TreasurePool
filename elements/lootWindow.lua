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
local bgPad         = { left = 0, right = 0, top = 0, bottom = 0 }
local titleText   = nil
local arrowUp     = nil         -- uiImage: shown when collapsible + expanded (click → collapse)
local arrowDown   = nil         -- uiImage: shown when collapsible + collapsed (click → expand)
local isCollapsible = false
local isCollapsed   = false
local lotAllBtn   = nil
local passAllBtn  = nil
local lootItems   = {}
local visibleRows = 0           -- rows currently shown via VIS_POOL; rows beyond this are pooled (hidden)
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

-- TreasurePool-specific visibility flag used to hide rows + footer when the
-- window is collapsed. These flag IDs are integer table keys (not bitmasks);
-- value (4) must be unique — not equal to any key used by the spui framework:
-- VIS_DEFAULT = 1, VIS_TOKEN = 2, VIS_INIT = 3 (libs/spui/utils.lua).
-- Kept local here because it is not part of the upstream spui framework.
local VIS_COLLAPSE = 4

-- TreasurePool-specific visibility flag (also local to this file, not part of
-- the upstream spui framework; ID 5 is unique vs. the flags listed above).
-- Controls pooled-row visibility independent of VIS_COLLAPSE: rows beyond the
-- active pool count are hidden and kept for reuse instead of being destroyed.
-- Both flags compose via uiElement's multi-flag visibility (visible only when
-- ALL flags are true), so neither overrides the other.
local VIS_POOL = 5

-- Callbacks (set by treasurepool.lua)
lootWindow.onLotSlot      = nil
lootWindow.onPassSlot     = nil
lootWindow.onLotAll       = nil
lootWindow.onPassAll      = nil
lootWindow.onItemClick    = nil
lootWindow.onCollapseToggle = nil
lootWindow.dragEnabled    = true
lootWindow.lotAllEnabled  = true   -- set false before deployment on servers where Lot All is banned

------------------------------------------------------------
-- Local helpers
------------------------------------------------------------
local function updateArrowVisibility()
    if not arrowUp or not arrowDown then return end
    if isCollapsible then
        if isCollapsed then
            arrowUp:hide(utils.VIS_TOKEN)
            arrowDown:show(utils.VIS_TOKEN)
        else
            arrowUp:show(utils.VIS_TOKEN)
            arrowDown:hide(utils.VIS_TOKEN)
        end
    else
        arrowUp:hide(utils.VIS_TOKEN)
        arrowDown:hide(utils.VIS_TOKEN)
    end
end

local function applyCollapseVisibility(collapsed)
    for _, item in ipairs(lootItems) do
        if collapsed then item:hide(VIS_COLLAPSE) else item:show(VIS_COLLAPSE) end
    end
    if collapsed then
        lotAllBtn:hide(VIS_COLLAPSE)
        passAllBtn:hide(VIS_COLLAPSE)
    else
        lotAllBtn:show(VIS_COLLAPSE)
        passAllBtn:show(VIS_COLLAPSE)
    end
end

local function hitTestArrow(mx, my)
    if not isCollapsible or not arrowUp then return false end
    local ax = arrowUp.absolutePos.x
    local ay = arrowUp.absolutePos.y
    local aw = arrowUp.absoluteWidth
    local ah = arrowUp.absoluteHeight
    return mx >= ax and mx < ax + aw and my >= ay and my < ay + ah
end

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
    local totalH = isCollapsed and H_H or (H_H + count * R_H + F_H)

    if bgMode == '3slice' then
        windowBg:setHeight(totalH + bgPad.top + bgPad.bottom)
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

    -- Collapse arrow (same screen position for both up/down images)
    if arrowUp and layout.collapseArrow then
        local ar  = layout.collapseArrow
        local arX = ar.pos[1]
        local arY = ar.pos[2]
        arrowUp.posX  = arX;  arrowUp.posY  = arY;  arrowUp:layoutElement()
        arrowDown.posX = arX; arrowDown.posY = arY; arrowDown:layoutElement()
    end

    -- Rows (always positioned for expand; hidden via VIS_COLLAPSE when collapsed)
    for i, item in ipairs(lootItems) do
        item:setPosition(0, H_H + (i - 1) * R_H)
    end

    -- Footer buttons (always positioned; hidden via VIS_COLLAPSE when collapsed)
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
    local totalH
    if isCollapsed then
        totalH = layout.window.headerH
    else
        totalH = layout.window.headerH + n * layout.window.rowH + layout.window.footerH
    end
    local H = totalH * root.absoluteScale.y
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
        -- Inherit width from layout.window.width; theme files leave size[1] = 0 as a placeholder
        -- pad offsets background beyond content bounds (e.g. right = 10 to cover a fading edge)
        local p = bgDef.pad or {}
        bgPad = { left = p.left or 0, right = p.right or 0, top = p.top or 0, bottom = p.bottom or 0 }
        local W  = layout.window.width + bgPad.left + bgPad.right
        local bg = {
            mode      = bgDef.mode,
            imgTop    = { path = bgDef.imgTop.path,    size = { W, bgDef.imgTop.size[2] },    pos = bgDef.imgTop.pos,    color = bgDef.imgTop.color,    sliceBorder = bgDef.imgTop.sliceBorder },
            imgMid    = { path = bgDef.imgMid.path,    size = { W, bgDef.imgMid.size[2] },    pos = bgDef.imgMid.pos,    color = bgDef.imgMid.color },
            imgBottom = { path = bgDef.imgBottom.path, size = { W, bgDef.imgBottom.size[2] }, pos = bgDef.imgBottom.pos, color = bgDef.imgBottom.color, sliceBorder = bgDef.imgBottom.sliceBorder },
        }
        windowBg = uiBackground.new(bg, engine)
        windowBg.posX = -bgPad.left
        windowBg.posY = -bgPad.top
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

    -- Collapse arrows (hidden until setCollapsible(true) is called)
    arrowUp   = nil
    arrowDown = nil
    if layout.collapseArrow then
        local ar = layout.collapseArrow
        local arDef = {
            size  = ar.size,
            pos   = { 0, 0 },  -- positioned in relayout
            color = ar.color or '#FFFFFFFF',
        }
        arDef.path = ar.upPath
        arrowUp = uiImage.new(arDef, engine)
        root:addChild(arrowUp)
        arrowUp:hide(utils.VIS_TOKEN)

        arDef = {
            size  = ar.size,
            pos   = { 0, 0 },
            color = ar.color or '#FFFFFFFF',
            path  = ar.downPath,
        }
        arrowDown = uiImage.new(arDef, engine)
        root:addChild(arrowDown)
        arrowDown:hide(utils.VIS_TOKEN)
    end

    -- Footer buttons (positions set in relayout)
    lotAllBtn  = uiButton.new(layout.footer.lotAllBtn, engine)
    passAllBtn = uiButton.new(layout.footer.passAllBtn, engine)
    root:addChild(lotAllBtn)
    root:addChild(passAllBtn)
    lotAllBtn:hide(utils.VIS_TOKEN)
    passAllBtn:hide(utils.VIS_TOKEN)

    -- Create all primitives
    root:createPrimitives()
    root:hide(utils.VIS_TOKEN)  -- prevent flash before first update(); shown when n > 0

    titleText:update('Treasure Pool')
    lotAllBtn:setText('Lot All')
    passAllBtn:setText('Pass All')

    lootItems = {}
    visibleRows = 0
    lastCount = -1
end

function lootWindow.update(items, passAllActive)
    if not engine then return end

    local n = #items

    -- Sync pool: rows are pooled, never destroyed mid-session. The game's
    -- treasure pool has 10 slots (gatherTreasureData's `for i = 0, 9`), so at
    -- most 10 rows are ever constructed; after that, count changes only toggle
    -- VIS_POOL visibility on existing rows.
    if n < visibleRows then
        -- Shrink: hide excess rows but keep them in lootItems for reuse
        for i = n + 1, visibleRows do
            lootItems[i]:hide(VIS_POOL)
        end
    elseif n > visibleRows then
        -- Grow: re-show pooled rows; construct new ones only when n exceeds
        -- the pool size for the first time
        for i = visibleRows + 1, n do
            local item = lootItems[i]
            if item then
                -- Rewire callbacks on reuse: a no-op in practice (the closures
                -- capture the item itself, not the slot), kept for clarity and
                -- to match the per-item wiring pattern below
                item.lotBtn.onClick  = makeLotCallback(item)
                item.passBtn.onClick = makePassCallback(item)
            else
                item = lootItem.new(engine, layout.lootItem)
                item:setRowDimensions(layout.window.width, layout.window.rowH)
                root:addChild(item)
                item.lotBtn:setText('Lot')
                item.passBtn:setText('Pass')
                item.lotBtn.onClick  = makeLotCallback(item)
                item.passBtn.onClick = makePassCallback(item)
                table.insert(lootItems, item)
            end
            item:show(VIS_POOL)
        end
    end
    visibleRows = n

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
    local hasPending = false
    for i, item in ipairs(lootItems) do
        if items[i] then
            item:update(items[i], hoveredIdx == i)
            if items[i].lot == 0 then hasPending = true end
        end
    end

    -- Footer buttons: visible while there are un-actioned items.
    -- Pass All is dominant: while it drains, Lot All is locked out.
    -- Lot All draining keeps Pass All visible so the user can still bail/interrupt.
    if hasPending then
        if passAllActive or not lootWindow.lotAllEnabled then
            lotAllBtn:hide(utils.VIS_TOKEN)
        else
            lotAllBtn:show(utils.VIS_TOKEN)
        end
        passAllBtn:show(utils.VIS_TOKEN)
    else
        lotAllBtn:hide(utils.VIS_TOKEN)
        passAllBtn:hide(utils.VIS_TOKEN)
    end

    -- Collapsed: hide all rows and footer buttons regardless of hasPending
    applyCollapseVisibility(isCollapsed)

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

        -- Arrow click: toggle collapse (checked before drag so it takes priority)
        if hitTestArrow(e.x, e.y) then
            isCollapsed = not isCollapsed
            applyCollapseVisibility(isCollapsed)
            updateArrowVisibility()
            relayout(math.max(lastCount, 0))
            if lootWindow.onCollapseToggle then lootWindow.onCollapseToggle(isCollapsed) end
            return false
        end

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
            if item:hitTest(e.x, e.y) then
                if lootWindow.onItemClick then lootWindow.onItemClick(item:getSlot()) end
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

-- Enable or disable the collapsible arrow. Disabling while collapsed auto-expands.
function lootWindow.setCollapsible(enabled)
    if not engine then return end
    enabled = (enabled == true)
    if isCollapsible == enabled then return end
    isCollapsible = enabled
    if not enabled and isCollapsed then
        isCollapsed = false
        applyCollapseVisibility(false)
    end
    updateArrowVisibility()
    relayout(math.max(lastCount, 0))
end

-- Collapse or expand the window.
function lootWindow.setCollapsed(collapsed)
    if not engine then return end
    collapsed = (collapsed == true)
    if isCollapsed == collapsed then return end
    isCollapsed = collapsed
    applyCollapseVisibility(collapsed)
    updateArrowVisibility()
    relayout(math.max(lastCount, 0))
end

function lootWindow.getHoveredEntry(items)
    if hoveredIdx == nil then return nil end
    return items[hoveredIdx]
end

function lootWindow.destroy()
    for _, item in ipairs(lootItems) do
        item:destroy()
    end
    lootItems = {}
    visibleRows = 0
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
    lastCount     = -1
    isCollapsible = false
    isCollapsed   = false
    windowBg      = nil
    windowBorders = nil
    titleText     = nil
    arrowUp       = nil
    arrowDown     = nil
    lotAllBtn     = nil
    passAllBtn    = nil
    hoveredIdx    = nil
    pressedBtn    = nil
    isDragging    = false
end

return lootWindow
