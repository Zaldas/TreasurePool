local WINDOW_W    = 380
local HEADER_H    = 26
local ROW_H       = 54
local CONTENT_H   = 50
local FOOTER_H    = 28
local PAD         = 8
local BTN_GAP     = 4
local LOT_BTN_W   = 44
local PASS_BTN_W  = 48
local LOT_ALL_W   = 58
local PASS_ALL_W  = 64
local BTN_H       = 20
local BAR_H       = 4

local PASS_BTN_X  = WINDOW_W - PAD - PASS_BTN_W
local LOT_BTN_X   = PASS_BTN_X - BTN_GAP - LOT_BTN_W
local TIMER_X     = LOT_BTN_X - 8
local BTN_Y       = math.floor((CONTENT_H - BTN_H) / 2)
local TIMER_Y     = math.floor((CONTENT_H - 14) / 2)

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
            color       = '#E8E8E8FF',
            stroke      = '#000000C0',
            strokeWidth = 0,
            bold        = true,
            align       = 'left',
            pos         = { PAD, 6 },
        },

        statusText = {
            font        = 'Lucida Sans Unicode',
            size        = 13,
            color       = '#AAAAAAFF',
            stroke      = '#000000A0',
            strokeWidth = 0,
            bold        = false,
            align       = 'left',
            pos         = { PAD + 10, 27 },
        },

        timerText = {
            font        = 'Lucida Sans Unicode',
            size        = 14,
            color       = '#6EB5FFFF',
            stroke      = '#000000A0',
            strokeWidth = 0,
            bold        = false,
            align       = 'right',
            pos         = { TIMER_X, TIMER_Y },
            colors = {
                normal   = 0xFF6EB5FF,
                warning  = 0xFFFF8C00,
                critical = 0xFFFF4040,
            },
        },

        timerBar = {
            pos       = { 0, CONTENT_H },
            animSpeed = 1,
            imgBg = {
                path  = 'layouts/assets/pixel.png',
                size  = { WINDOW_W, BAR_H },
                color = '#FFFFFF18',
            },
            imgBar = {
                path  = 'layouts/assets/pixel.png',
                size  = { WINDOW_W, BAR_H },
                color = '#6EB5FFFF',
            },
        },

        lotBtn = {
            pos  = { LOT_BTN_X, BTN_Y },
            size = { LOT_BTN_W, BTN_H },
            label = {
                font        = 'Arial',
                size        = 13,
                color       = '#FFFFFFFF',
                strokeWidth = 0,
                align       = 'center',
                pos         = { LOT_BTN_W / 2, math.floor((BTN_H - 13) / 2) },
            },
            colors = {
                normal   = 0xFF2A5F85,
                hover    = 0xFF3A7FAA,
                pressed  = 0xFF1A4060,
                disabled = 0xFF333333,
            },
        },

        passBtn = {
            pos  = { PASS_BTN_X, BTN_Y },
            size = { PASS_BTN_W, BTN_H },
            label = {
                font        = 'Arial',
                size        = 13,
                color       = '#FFFFFFFF',
                strokeWidth = 0,
                align       = 'center',
                pos         = { PASS_BTN_W / 2, math.floor((BTN_H - 13) / 2) },
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
                pos         = { LOT_ALL_W / 2, math.floor((BTN_H - 13) / 2) },
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
                pos         = { PASS_ALL_W / 2, math.floor((BTN_H - 13) / 2) },
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
