local bit         = require('bit')
local classes     = require('libs/spui/classes')
local uiContainer = require('libs/spui/uiContainer')
local uiText      = require('libs/spui/uiText')
local uiButton    = require('libs/spui/uiButton')
local uiBar       = require('libs/spui/uiBar')
local uiImage     = require('libs/spui/uiImage')
local utils       = require('libs/spui/utils')
local state       = require('state')

local lootItem = classes.class(uiContainer)

local private = {}

local function formatTimer(remaining)
    if remaining <= 0 then return '0:00' end
    local m = math.floor(remaining / 60)
    local s = remaining % 60
    return m .. ':' .. string.format('%02d', s)
end

local function d3dToRgba(d)
    return {
        a = bit.band(bit.rshift(d, 24), 0xFF),
        r = bit.band(bit.rshift(d, 16), 0xFF),
        g = bit.band(bit.rshift(d, 8), 0xFF),
        b = bit.band(d, 0xFF),
    }
end

-- Fixed colors used every frame in update(); allocated once here instead of
-- per-frame table literals. Downstream color()/setColor() copy the values out,
-- so sharing these tables is safe.
local COLOR_OWNED_RED       = { r = 195, g = 85,  b = 85,  a = 255 }  -- Red: already own this
local COLOR_NAME_WHITE      = { r = 232, g = 232, b = 232, a = 255 }  -- Default name color
local COLOR_PASSED_BLUE     = { r = 100, g = 150, b = 220, a = 255 }  -- Blue: passed
local COLOR_WINNING_GOLD    = { r = 255, g = 200, b = 50,  a = 255 }  -- Gold: winning
local COLOR_LOSING_ORANGE   = { r = 255, g = 140, b = 40,  a = 255 }  -- Orange: losing
local COLOR_NO_ACTION_WHITE = { r = 220, g = 220, b = 220, a = 255 }  -- White: no action

function lootItem:init(engine, layout)
    self.super:init()

    local rDef = layout.nameText and layout.nameText.rareImg
    local eDef = layout.nameText and layout.nameText.exImg

    -- Pre-convert the three timer colors once (text variant + bar variant with
    -- a=128) instead of calling d3dToRgba every frame in update().
    local tc = layout.timerText.colors
    local timerTextRgba = {
        critical = d3dToRgba(tc.critical),
        warning  = d3dToRgba(tc.warning),
        normal   = d3dToRgba(tc.normal),
    }
    local timerBarRgba = {}
    for k, c in pairs(timerTextRgba) do
        timerBarRgba[k] = { r = c.r, g = c.g, b = c.b, a = 128 }
    end

    private[self] = {
        timerTextRgba  = timerTextRgba,
        timerBarRgba   = timerBarRgba,
        rowWidth       = 0,
        rowHeight      = 0,
        currentSlot    = nil,
        engine         = engine,
        nameTextX      = layout.nameText and layout.nameText.pos and layout.nameText.pos[1] or 0,
        rareImgDef     = rDef,
        exImgDef       = eDef,
        lastIconItemId = nil,
        isRare         = false,
        isEx           = false,
    }

    self.timerBar = uiBar.new(layout.timerBar, engine, 1.0)
    self:addChild(self.timerBar)

    self.nameText = uiText.new(layout.nameText)
    self:addChild(self.nameText)

    self.timerText = uiText.new(layout.timerText)
    self:addChild(self.timerText)

    self.statusText = uiText.new(layout.statusText)
    self:addChild(self.statusText)

    self.lotBtn = uiButton.new(layout.lotBtn, engine)
    self:addChild(self.lotBtn)

    self.passBtn = uiButton.new(layout.passBtn, engine)
    self:addChild(self.passBtn)

    self.separator = uiImage.new(layout.separator, engine)
    self:addChild(self.separator)

    self.iconImg = uiImage.new(layout.icon, engine)
    self:addChild(self.iconImg)

    local function makeTagIcon(def)
        if not def or not def.path then return nil end
        local img = uiImage.new({
            path  = def.path,
            size  = def.size or { 12, 12 },
            pos   = { 0, def.y or 4 },
            color = '#FFFFFFFF',
        }, engine)
        self:addChild(img)
        img:hide(utils.VIS_TOKEN)
        return img
    end

    self.rareImg = makeTagIcon(rDef)
    self.exImg   = makeTagIcon(eDef)
end

function lootItem:setPosition(x, y)
    self.posX = x
    self.posY = y
    self:layoutElement()
end

function lootItem:setRowDimensions(w, h)
    private[self].rowWidth  = w
    private[self].rowHeight = h
end

function lootItem:hitTest(mx, my)
    if not self.absoluteVisibility then return false end

    local ax = self.absolutePos.x
    local ay = self.absolutePos.y
    local aw = private[self].rowWidth  * self.absoluteScale.x
    local ah = private[self].rowHeight * self.absoluteScale.y

    return mx >= ax and mx < ax + aw and my >= ay and my < ay + ah
end

function lootItem:getSlot()
    return private[self].currentSlot
end

function lootItem:update(entry, isHovered)
    if not self.isEnabled then return end
    if entry == nil then return end

    self.nameText:update(entry.name)
    local isRareOwned = entry.rareOwned
    if isRareOwned then
        self.nameText:color(COLOR_OWNED_RED)
    else
        self.nameText:color(COLOR_NAME_WHITE)
    end

    -- Icon texture + Rare/Ex flags: only look up the resource when the item
    -- changes. Reset when the slot is vacated (itemId == 0) so the next item
    -- triggers a reload and doesn't inherit stale Rare/Ex flags.
    if not entry.itemId or entry.itemId == 0 then
        private[self].lastIconItemId = nil
        private[self].isRare = false
        private[self].isEx   = false
    elseif entry.itemId ~= private[self].lastIconItemId then
        private[self].lastIconItemId = entry.itemId
        local resItem = AshitaCore:GetResourceManager():GetItemById(entry.itemId)
        if resItem and resItem.ImageSize and resItem.ImageSize > 0 then
            local tex, w, h = private[self].engine:loadImageFromMemory(resItem.Bitmap, resItem.ImageSize, entry.itemId)
            self.iconImg:setTexture(tex, w, h)
        end
        local flags = resItem and resItem.Flags or 0
        private[self].isRare = bit.band(flags, 0x8000) ~= 0
        private[self].isEx   = bit.band(flags, 0x4000) ~= 0
    end

    -- Rare/Ex tag icons: position dynamically after name text
    if self.rareImg or self.exImg then
        local isRare = private[self].isRare
        local isEx   = private[self].isEx
        local rDef  = private[self].rareImgDef
        local scale = (self.absoluteScale and self.absoluteScale.x) or 1
        local baseX  = private[self].nameTextX
                     + self.nameText:getRenderedWidth() / scale
                     + (rDef and rDef.gap or 5)

        if self.rareImg then
            if isRare then
                self.rareImg.posX = baseX
                self.rareImg:layoutElement()
                self.rareImg:show(utils.VIS_TOKEN)
            else
                self.rareImg:hide(utils.VIS_TOKEN)
            end
        end

        if self.exImg then
            if isEx then
                local exX = baseX
                if isRare and self.rareImg then
                    exX = baseX + (rDef and rDef.size and rDef.size[1] or 12) + 2
                end
                self.exImg.posX = exX
                self.exImg:layoutElement()
                self.exImg:show(utils.VIS_TOKEN)
            else
                self.exImg:hide(utils.VIS_TOKEN)
            end
        end
    end

    local remaining = math.max(0, (entry.expiresAt or 0) - os.time())
    self.timerText:update(formatTimer(remaining))

    local timerKey
    if remaining < 60 then
        timerKey = 'critical'
    elseif remaining <= 120 then
        timerKey = 'warning'
    else
        timerKey = 'normal'
    end
    self.timerText:color(private[self].timerTextRgba[timerKey])

    -- Color always reflects your state; rareOwned takes precedence over lot state
    local statusColor
    if entry.rareOwned then
        statusColor = COLOR_OWNED_RED
    elseif entry.lot == state.LOT_PASSED then
        statusColor = COLOR_PASSED_BLUE
    elseif entry.lot > 0 then
        if entry.lot == entry.winningLot then
            statusColor = COLOR_WINNING_GOLD
        else
            statusColor = COLOR_LOSING_ORANGE
        end
    else
        statusColor = COLOR_NO_ACTION_WHITE
    end

    -- Text content: hover shows your state, default shows pool state
    local statusStr = '---'
    local playerName = entry.playerName or 'You'
    if isHovered then
        if entry.rareOwned and entry.lot == 0 then
            statusStr = 'Owned'
        elseif entry.lot == state.LOT_PASSED then
            statusStr = 'Passed'
        elseif entry.lot > 0 then
            statusStr = state.formatLot(entry.lot) .. ': ' .. playerName
        end
    else
        if entry.winningLot > 0 and entry.winnerName ~= '' then
            statusStr = state.formatLot(entry.winningLot) .. ': ' .. entry.winnerName
        elseif entry.lot == state.LOT_PASSED then
            statusStr = 'Passed'
        elseif entry.rareOwned then
            statusStr = 'Owned'
        end
    end
    self.statusText:update(statusStr)
    self.statusText:color(statusColor)

    local canAct = isHovered
    if not canAct or entry.lot == state.LOT_PASSED then
        -- Not hovered, or already passed: no buttons
        self.lotBtn:hide(utils.VIS_TOKEN)
        self.passBtn:hide(utils.VIS_TOKEN)
    elseif entry.rareOwned then
        -- Own it: lot always blocked; pass still available
        self.lotBtn:hide(utils.VIS_TOKEN)
        self.passBtn:show(utils.VIS_TOKEN)
    elseif entry.lot == 0 then
        -- No action yet: both available
        self.lotBtn:show(utils.VIS_TOKEN)
        self.passBtn:show(utils.VIS_TOKEN)
    else
        -- Already lotted: can still pass, cannot re-lot
        self.lotBtn:hide(utils.VIS_TOKEN)
        self.passBtn:show(utils.VIS_TOKEN)
    end

    self.lotBtn:update()
    self.passBtn:update()

    local barValue = math.max(0, math.min(1, remaining / state.POOL_TTL))
    self.timerBar:setValue(barValue)
    self.timerBar:setColor(private[self].timerBarRgba[timerKey])
    self.timerBar:update()

    self.separator:update()

    if self.rareImg then self.rareImg:update() end
    if self.exImg   then self.exImg:update()   end

    private[self].currentSlot = entry.slot
end

function lootItem:destroy()
    private[self] = nil
    self:dispose()
end

return lootItem
