------------------------------------------------------------
-- elements/lootItem.lua
-- A uiContainer subclass representing one treasure pool row.
-- Contains: nameText, timerText, rightText, lotBtn, passBtn.
------------------------------------------------------------

local bit         = require('bit')
local classes     = require('libs/spui/classes')
local uiContainer = require('libs/spui/uiContainer')
local uiText      = require('libs/spui/uiText')
local uiButton    = require('libs/spui/uiButton')
local utils       = require('libs/spui/utils')

local lootItem = classes.class(uiContainer)

-- Private per-instance storage
local private = {}

------------------------------------------------------------
-- Local helpers
------------------------------------------------------------
local function formatLot(lot)
    if lot == nil then return '---' end
    if lot < 10 then return '00' .. tostring(lot) end
    if lot < 100 then return '0' .. tostring(lot) end
    return tostring(lot)
end

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

------------------------------------------------------------
-- Constructor
------------------------------------------------------------
-- @param engine  sprite engine
-- @param layout  layout.lootItem from default.lua
function lootItem:init(engine, layout)
    self.super:init()

    private[self] = {
        timerColors    = layout.timerText.colors,
        buttonsEnabled = true,
        rowWidth       = 0,
        rowHeight      = 0,
        currentSlot    = nil,
    }

    -- Name text (left column)
    self.nameText = uiText.new(layout.nameText)
    self:addChild(self.nameText)

    -- Timer text (middle column, right-aligned)
    self.timerText = uiText.new(layout.timerText)
    self:addChild(self.timerText)

    -- Right column text (winner info / player lot)
    self.rightText = uiText.new(layout.rightText)
    self:addChild(self.rightText)

    -- Lot button
    self.lotBtn = uiButton.new(layout.lotBtn, engine)
    self:addChild(self.lotBtn)
    self.lotBtn:hide(utils.VIS_TOKEN)

    -- Pass button
    self.passBtn = uiButton.new(layout.passBtn, engine)
    self:addChild(self.passBtn)
    self.passBtn:hide(utils.VIS_TOKEN)
end

------------------------------------------------------------
-- API
------------------------------------------------------------
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

function lootItem:setButtonsEnabled(v)
    private[self].buttonsEnabled = v
end

function lootItem:update(entry, isHovered)
    if not self.isEnabled then return end
    if entry == nil then return end  -- called by spui cascade with no args; skip

    -- Name
    self.nameText:update(entry.name)

    -- Timer
    local remaining = math.max(0, (entry.dropTime + 300) - os.time())
    self.timerText:update(formatTimer(remaining))

    -- Timer color
    local tc = private[self].timerColors
    local timerD3D
    if remaining <= 0 or remaining < 60 then
        timerD3D = tc.critical
    elseif remaining <= 120 then
        timerD3D = tc.warning
    else
        timerD3D = tc.normal
    end
    self.timerText:color(d3dToRgba(timerD3D))

    -- Determine button visibility
    local showButtons = isHovered and entry.lot == 0 and private[self].buttonsEnabled

    if showButtons then
        -- Show buttons, hide right text
        self.rightText:hide(utils.VIS_TOKEN)
        self.lotBtn:show(utils.VIS_TOKEN)
        self.passBtn:show(utils.VIS_TOKEN)
    else
        -- Hide buttons, show right text
        self.lotBtn:hide(utils.VIS_TOKEN)
        self.passBtn:hide(utils.VIS_TOKEN)

        local rightStr   = ' ---'
        local rightColor = { r = 211, g = 211, b = 211, a = 255 }

        if isHovered and entry.lot == 65535 then
            rightStr   = 'You: Pass'
            rightColor = { r = 115, g = 155, b = 208, a = 255 }
        elseif isHovered and entry.lot > 0 then
            rightStr   = 'You: ' .. formatLot(entry.lot)
            rightColor = { r = 254, g = 206, b = 67, a = 255 }
        elseif entry.winningLot > 0 and entry.winnerName ~= '' then
            rightStr   = entry.winnerName .. '  ' .. formatLot(entry.winningLot)
            rightColor = { r = 254, g = 206, b = 67, a = 255 }
        end

        self.rightText:update(rightStr)
        self.rightText:color(rightColor)
        self.rightText:show(utils.VIS_TOKEN)
    end

    -- Store current slot
    private[self].currentSlot = entry.slot
end

function lootItem:destroy()
    private[self] = nil
    self:dispose()
end

return lootItem
