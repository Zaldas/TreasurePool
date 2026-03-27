------------------------------------------------------------
-- layouts/default.lua
-- Default layout for TreasurePool (spui sprite engine)
-- All pixel values are at 1440p baseline.
-- Color strings use '#RRGGBBAA' format for spui.
-- D3DCOLOR integers (0xAARRGGBB) are stored in 'colors'
-- sub-tables for runtime use by Lua code (not passed to spui).
------------------------------------------------------------

local WINDOW_W    = 380
local HEADER_H    = 28
local ROW_H       = 22
local FOOTER_H    = 26
local PAD         = 6
local BTN_GAP     = 4
local LOT_BTN_W   = 44
local PASS_BTN_W  = 48
local LOT_ALL_W   = 58
local PASS_ALL_W  = 64
local BTN_H       = 18   -- ROW_H - 4
local RIGHT_X_OFF = 278

local layout = {
    window = {
        width   = WINDOW_W,
        headerH = HEADER_H,
        rowH    = ROW_H,
        footerH = FOOTER_H,
        pad     = PAD,
        bg = {
            color = '#010640BF',
        },
    },

    title = {
        font      = 'Arial',
        size      = 22,
        color     = '#9FC8F2FF',
        stroke    = '#0041ABFF',
        strokeWidth = 0,
        underline = true,
        bold      = false,
        align     = 'center',
        pos       = { WINDOW_W / 2, 2 },
    },

    lootItem = {
        nameText = {
            font        = 'Lucida Sans Unicode',
            size        = 16,
            color       = '#D3D3D3FF',
            stroke      = '#B2BEB5FF',
            strokeWidth = 0,
            bold        = false,
            align       = 'left',
            pos         = { PAD, 2 },
        },

        timerText = {
            font        = 'Lucida Sans Unicode',
            size        = 16,
            color       = '#6EB5FFFF',
            stroke      = '#B2BEB5FF',
            strokeWidth = 0,
            bold        = false,
            align       = 'right',
            pos         = { PAD + 210 + 52, 2 },  -- NAME_W + TIMER_W
            colors = {
                normal   = 0xFF6EB5FF,
                warning  = 0xFFFF8C00,
                critical = 0xFFFF4040,
            },
        },

        rightText = {
            font        = 'Lucida Sans Unicode',
            size        = 16,
            color       = '#D3D3D3FF',
            stroke      = '#B2BEB5FF',
            strokeWidth = 0,
            bold        = false,
            align       = 'left',
            pos         = { RIGHT_X_OFF, 2 },
        },

        lotBtn = {
            pos  = { RIGHT_X_OFF, 2 },
            size = { LOT_BTN_W, BTN_H },
            label = {
                font        = 'Arial',
                size        = 13,
                color       = '#FFFFFFFF',
                strokeWidth = 0,
                align       = 'center',
                pos         = { 22, 2 },  -- LOT_BTN_W/2, (BTN_H-13)/2
            },
            colors = {
                normal   = 0xFF2A5F85,
                hover    = 0xFF3A7FAA,
                pressed  = 0xFF1A4060,
                disabled = 0xFF333333,
            },
        },

        passBtn = {
            pos  = { RIGHT_X_OFF + LOT_BTN_W + BTN_GAP, 2 },
            size = { PASS_BTN_W, BTN_H },
            label = {
                font        = 'Arial',
                size        = 13,
                color       = '#FFFFFFFF',
                strokeWidth = 0,
                align       = 'center',
                pos         = { 24, 2 },  -- PASS_BTN_W/2, (BTN_H-13)/2
            },
            colors = {
                normal   = 0xFF2A5F85,
                hover    = 0xFF3A7FAA,
                pressed  = 0xFF1A4060,
                disabled = 0xFF333333,
            },
        },
    },

    footer = {
        lotAllBtn = {
            size = { LOT_ALL_W, BTN_H },
            label = {
                font        = 'Arial',
                size        = 13,
                color       = '#FFFFFFFF',
                strokeWidth = 0,
                align       = 'center',
                pos         = { 29, 2 },  -- LOT_ALL_W/2, (BTN_H-13)/2
            },
            colors = {
                normal   = 0xFF2A5F85,
                hover    = 0xFF3A7FAA,
                pressed  = 0xFF1A4060,
                disabled = 0xFF333333,
            },
        },

        passAllBtn = {
            size = { PASS_ALL_W, BTN_H },
            label = {
                font        = 'Arial',
                size        = 13,
                color       = '#FFFFFFFF',
                strokeWidth = 0,
                align       = 'center',
                pos         = { 32, 2 },  -- PASS_ALL_W/2, (BTN_H-13)/2
            },
            colors = {
                normal   = 0xFF2A5F85,
                hover    = 0xFF3A7FAA,
                pressed  = 0xFF1A4060,
                disabled = 0xFF333333,
            },
        },
    },
}

return layout
