local bit         = require('bit')
local classes     = require('libs/spui/classes')
local uiContainer = require('libs/spui/uiContainer')
local uiText      = require('libs/spui/uiText')
local uiButton    = require('libs/spui/uiButton')
local uiBar       = require('libs/spui/uiBar')
local uiImage     = require('libs/spui/uiImage')
local utils       = require('libs/spui/utils')

local lootItem = classes.class(uiContainer)

local private = {}

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

function lootItem:init(engine, layout)
    self.super:init()

    private[self] = {
        timerColors    = layout.timerText.colors,
        buttonsEnabled = true,
        rowWidth       = 0,
        rowHeight      = 0,
        currentSlot    = nil,
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

function lootItem:setButtonsEnabled(v)
    private[self].buttonsEnabled = v
end

function lootItem:update(entry, isHovered)
    if not self.isEnabled then return end
    if entry == nil then return end

    self.nameText:update(entry.name)

    local remaining = math.max(0, (entry.dropTime + 300) - os.time())
    self.timerText:update(formatTimer(remaining))

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

    -- Color always reflects your state
    local statusColor = { r = 220, g = 220, b = 220, a = 255 }  -- White: no action
    if entry.lot == 65535 then
        statusColor = { r = 100, g = 150, b = 220, a = 255 }  -- Blue: passed
    elseif entry.lot > 0 then
        if entry.lot == entry.winningLot then
            statusColor = { r = 255, g = 200, b = 50,  a = 255 }  -- Gold: winning
        else
            statusColor = { r = 255, g = 140, b = 40,  a = 255 }  -- Orange: losing
        end
    end

    -- Text content: hover shows your state, default shows pool state
    local statusStr = '---'
    local playerName = entry.playerName or 'You'
    if isHovered then
        if entry.lot == 65535 then
            statusStr = playerName .. ': Pass'
        elseif entry.lot > 0 then
            statusStr = formatLot(entry.lot) .. ': ' .. playerName
        end
    else
        if entry.winningLot > 0 and entry.winnerName ~= '' then
            statusStr = formatLot(entry.winningLot) .. ': ' .. entry.winnerName
        end
    end
    self.statusText:update(statusStr)
    self.statusText:color(statusColor)

    local showButtons = (entry.lot == 0) and private[self].buttonsEnabled and isHovered
    if showButtons then
        self.lotBtn:show(utils.VIS_TOKEN)
        self.passBtn:show(utils.VIS_TOKEN)
    else
        self.lotBtn:hide(utils.VIS_TOKEN)
        self.passBtn:hide(utils.VIS_TOKEN)
    end

    self.lotBtn:update()
    self.passBtn:update()

    local barValue = math.max(0, math.min(1, remaining / 300))
    self.timerBar:setValue(barValue)
    local barColor = d3dToRgba(timerD3D)
    barColor.a = 128
    self.timerBar:setColor(barColor)
    self.timerBar:update()

    self.separator:update()

    private[self].currentSlot = entry.slot
end

function lootItem:destroy()
    private[self] = nil
    self:dispose()
end

return lootItem
