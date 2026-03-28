------------------------------------------------------------
-- libs/spui/uiButton.lua
-- A uiContainer subclass: uiImage background + uiText label.
-- Used for Lot/Pass/LotAll/PassAll buttons.
------------------------------------------------------------

local bit         = require('bit')
local classes     = require('libs/spui/classes')
local uiContainer = require('libs/spui/uiContainer')
local uiImage     = require('libs/spui/uiImage')
local uiText      = require('libs/spui/uiText')
local utils       = require('libs/spui/utils')

local uiButton = classes.class(uiContainer)

local function d3dToRgbaTable(d)
    return {
        a = bit.band(bit.rshift(d, 24), 0xFF),
        r = bit.band(bit.rshift(d, 16), 0xFF),
        g = bit.band(bit.rshift(d, 8), 0xFF),
        b = bit.band(d, 0xFF),
    }
end

-- @param layout table with pos, size, label, colors, zOrder
-- @param engine sprite engine instance
function uiButton:init(layout, engine)
    self.super:init(layout)

    local w = (layout and layout.size and layout.size[1]) or 44
    local h = (layout and layout.size and layout.size[2]) or 18
    self.width  = w
    self.height = h

    self.colors = (layout and layout.colors) or {
        normal   = 0xFF2A5F85,
        hover    = 0xFF3A7FAA,
        pressed  = 0xFF1A4060,
        disabled = 0xFF333333,
    }

    self.isHover    = false
    self.isDown     = false
    self.btnEnabled = true
    self.onClick    = nil

    -- Background image (pixel.png stretched to button size, or custom path with optional 9-slice)
    self.bg = uiImage.new({
        path        = (layout and layout.path) or 'layouts/assets/pixel.png',
        sliceBorder = (layout and layout.sliceBorder) or nil,
        size        = { w, h },
        pos         = { 0, 0 },
        color       = '#FFFFFFFF',
    }, engine)
    self:addChild(self.bg)

    -- Label text
    if layout and layout.label then
        self.label = uiText.new(layout.label)
        self:addChild(self.label)
    else
        self.label = nil
    end
end

function uiButton:createPrimitives()
    if not self.isEnabled or self.isCreated then return end

    self.super:createPrimitives()

    -- Apply initial button color now that bg sprite exists
    self:_updateColor()
end

function uiButton:_updateColor()
    if not self.bg then return end

    local d
    if not self.btnEnabled then
        d = self.colors.disabled
    elseif self.isDown then
        d = self.colors.pressed
    elseif self.isHover then
        d = self.colors.hover
    else
        d = self.colors.normal
    end

    local c = d3dToRgbaTable(d)
    self.bg:color(c)
end

function uiButton:setHover(v)
    if self.isHover ~= v then
        self.isHover = v
        self:_updateColor()
    end
end

function uiButton:setPressed(v)
    if self.isDown ~= v then
        self.isDown = v
        self:_updateColor()
    end
end

function uiButton:setEnabled(v)
    if self.btnEnabled ~= v then
        self.btnEnabled = v
        self:_updateColor()
    end
end

function uiButton:setText(str)
    if self.label then
        self.label:update(str)
    end
end

function uiButton:hitTest(mx, my)
    if not self.btnEnabled then return false end
    if not self.absoluteVisibility then return false end

    local ax = self.absolutePos.x
    local ay = self.absolutePos.y
    local aw = self.width  * self.absoluteScale.x
    local ah = self.height * self.absoluteScale.y

    return mx >= ax and mx < ax + aw and my >= ay and my < ay + ah
end

return uiButton
