--[[
    spui/sprites.lua
    Instanced sprite engine factory for PetsReborn.
    Each newEngine() call returns an isolated sprite context.
    A single global D3DXSprite and imageCache are shared across all engines.
]]

require('common')
local d3d8 = require('d3d8')
local ffi  = require('ffi')

local M = {}

local d3dDevice = d3d8.get_device()
local d3dSprite = nil          -- single D3DXSprite shared across all engines
local imageCache = {}          -- path -> {texture, width, height}; shared (textures are immutable)
local engines = {}             -- ordered list of all engine instances (controls cross-system z-order)

-- Pre-allocated FFI structs for 9-slice rendering (reused each frame; single-threaded safe)
local nsRect     = ffi.new('RECT[9]')
local nsVecPos   = ffi.new('D3DXVECTOR2[9]')
local nsVecScale = ffi.new('D3DXVECTOR2[9]')

local function createD3DSprite()
    local ptr = ffi.new('ID3DXSprite*[1]')
    if ffi.C.D3DXCreateSprite(d3dDevice, ptr) ~= ffi.C.S_OK then
        error('[PetsReborn] Failed to create D3DXSprite')
    end
    return d3d8.gc_safe_release(ffi.cast('ID3DXSprite*', ptr[0]))
end

local function loadImage(path)
    if imageCache[path] then
        return imageCache[path][1], imageCache[path][2], imageCache[path][3]
    end

    if not path or path == '' or not ashita.fs.exists(path) then
        return nil, 0, 0
    end

    local texPtr  = ffi.new('IDirect3DTexture8*[1]')
    local imgInfo = ffi.new('D3DXIMAGE_INFO')

    local hr = ffi.C.D3DXCreateTextureFromFileExA(
        d3dDevice, path,
        0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
        ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED,
        ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT,
        0x00000000, imgInfo, nil, texPtr)

    if hr == ffi.C.S_OK then
        local tex = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', texPtr[0]))
        imageCache[path] = { tex, imgInfo.Width, imgInfo.Height }
        return tex, imgInfo.Width, imgInfo.Height
    end

    return nil, 0, 0
end

local function renderNineSlice(spr, v)
    local bL, bR, bT, bB = v.nineSlice[1], v.nineSlice[2], v.nineSlice[3], v.nineSlice[4]
    local tw, th = v.nativeW, v.nativeH
    local dw, dh = v.destW, v.destH
    local dx, dy = v.position_x, v.position_y

    -- Derive the UI scale from height (height is pure UI scale; width may be user-resized)
    local uiScale = dh / th

    -- Destination-space border sizes (scaled with the UI, not raw texture pixels)
    local dbL = bL * uiScale
    local dbR = bR * uiScale
    local dbT = bT * uiScale
    local dbB = bB * uiScale

    local mSrcW = math.max(1, tw - bL - bR)
    local mSrcH = math.max(1, th - bT - bB)
    local mDstW = math.max(0, dw - dbL - dbR)
    local mDstH = math.max(0, dh - dbT - dbB)
    local scX = mDstW / mSrcW
    local scY = mDstH / mSrcH

    -- 9 slices: TL, TC, TR, ML, MC, MR, BL, BC, BR
    -- each entry: { srcLeft, srcTop, srcRight, srcBottom, dstX, dstY, scaleX, scaleY }
    local slices = {
        { 0,     0,     bL,    bT,    dx,           dy,           uiScale, uiScale },
        { bL,    0,     tw-bR, bT,    dx+dbL,       dy,           scX,     uiScale },
        { tw-bR, 0,     tw,    bT,    dx+dw-dbR,    dy,           uiScale, uiScale },
        { 0,     bT,    bL,    th-bB, dx,           dy+dbT,       uiScale, scY     },
        { bL,    bT,    tw-bR, th-bB, dx+dbL,       dy+dbT,       scX,     scY     },
        { tw-bR, bT,    tw,    th-bB, dx+dw-dbR,    dy+dbT,       uiScale, scY     },
        { 0,     th-bB, bL,    th,    dx,           dy+dh-dbB,    uiScale, uiScale },
        { bL,    th-bB, tw-bR, th,    dx+dbL,       dy+dh-dbB,    scX,     uiScale },
        { tw-bR, th-bB, tw,    th,    dx+dw-dbR,    dy+dh-dbB,    uiScale, uiScale },
    }
    for i, s in ipairs(slices) do
        local idx = i - 1
        nsRect[idx].left = s[1]; nsRect[idx].top = s[2]; nsRect[idx].right = s[3]; nsRect[idx].bottom = s[4]
        nsVecPos[idx].x = s[5]; nsVecPos[idx].y = s[6]
        nsVecScale[idx].x = s[7]; nsVecScale[idx].y = s[8]
        spr:Draw(v.texture, nsRect[idx], nsVecScale[idx], nil, 0.0, nsVecPos[idx], v.color)
    end
end

-- Global render dispatcher
ashita.events.register('d3d_present', '__petsreborn_spui_present_cb', function()
    if d3dSprite == nil then return end
    d3dSprite:Begin()
    for _, eng in ipairs(engines) do
        for i = 1, eng.sortedCount do
            local v = eng.renderInfo[eng.sortedKeys[i]]
            if v and v.visible and v.texture ~= nil then
                if v.nineSlice then
                    renderNineSlice(d3dSprite, v)
                else
                    v.rect.right   = v.nativeW
                    v.rect.bottom  = v.nativeH
                    v.vecPos.x     = v.position_x
                    v.vecPos.y     = v.position_y
                    v.vecScale.x   = (v.displayW or v.nativeW) / math.max(1, v.nativeW)
                    v.vecScale.y   = (v.displayH or v.nativeH) / math.max(1, v.nativeH)
                    d3dSprite:Draw(v.texture, v.rect, v.vecScale, nil, 0.0, v.vecPos, v.color)
                end
            end
        end
    end
    d3dSprite:End()
end)

-- Creates and returns a new isolated sprite engine instance.
function M.newEngine()
    local engine = {
        renderInfo  = {},     -- renderKey -> sprite obj
        sortedKeys  = {},     -- ordered for z-rendering
        sortedCount = 0,
        nextKey     = 1,      -- monotonic; never reused
    }

    -- Creates a new sprite object registered with this engine.
    function engine:newSprite()
        local spr = {
            visible    = true,
            position_x = 0,
            position_y = 0,
            nativeW    = 0,
            nativeH    = 0,
            displayW   = 0,
            displayH   = 0,
            color      = d3d8.D3DCOLOR_ARGB(255, 255, 255, 255),
            texture    = nil,
            rect       = ffi.new('RECT', { 0, 0, 0, 0 }),
            vecPos     = ffi.new('D3DXVECTOR2', { 0, 0 }),
            vecScale   = ffi.new('D3DXVECTOR2', { 1, 1 }),
            nineSlice  = nil,
            destW      = 0,
            destH      = 0,
        }
        spr.renderKey = self.nextKey
        self.nextKey = self.nextKey + 1
        self.renderInfo[spr.renderKey] = spr
        self.sortedCount = self.sortedCount + 1
        self.sortedKeys[self.sortedCount] = spr.renderKey
        return spr
    end

    -- Removes a sprite from this engine.
    function engine:destroySprite(spr)
        if not spr then return end
        self.renderInfo[spr.renderKey] = nil
        local key = spr.renderKey
        for i = 1, self.sortedCount do
            if self.sortedKeys[i] == key then
                for j = i, self.sortedCount - 1 do
                    self.sortedKeys[j] = self.sortedKeys[j + 1]
                end
                self.sortedKeys[self.sortedCount] = nil
                self.sortedCount = self.sortedCount - 1
                break
            end
        end
    end

    -- Loads a texture by path, caches globally. Returns texture, nativeW, nativeH.
    function engine:loadImage(path)
        local tex, w, h = loadImage(path)
        if tex ~= nil and d3dSprite == nil then
            d3dSprite = createD3DSprite()
        end
        return tex, w, h
    end

    -- Sets color on a sprite from hex string '#RRGGBBAA' (layout format: red first, alpha last)
    function engine:setColor(spr, hexStr)
        if not hexStr then
            spr.color = d3d8.D3DCOLOR_ARGB(255, 255, 255, 255)
            return
        end
        local hex = hexStr:gsub('#', '')
        local r = tonumber(hex:sub(1, 2), 16) or 255
        local g = tonumber(hex:sub(3, 4), 16) or 255
        local b = tonumber(hex:sub(5, 6), 16) or 255
        local a = 255
        if #hex >= 8 then
            a = tonumber(hex:sub(7, 8), 16) or 255
        end
        spr.color = d3d8.D3DCOLOR_ARGB(a, r, g, b)
    end

    -- Destroys all sprites in this engine and removes it from the global list.
    function engine:destroy()
        self.renderInfo  = {}
        self.sortedKeys  = {}
        self.sortedCount = 0
        for i, e in ipairs(engines) do
            if e == self then
                table.remove(engines, i)
                break
            end
        end
    end

    table.insert(engines, engine)
    return engine
end

-- Clears the image cache (call on addon reload if textures change).
function M.clearCache()
    imageCache = {}
end

return M
