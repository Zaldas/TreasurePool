local WINDOW_W    = 250
local HEADER_H    = 26
local ROW_H       = 37
local FOOTER_H    = 28
local PAD         = 8
local BTN_GAP     = 4
local LOT_BTN_W   = 44
local PASS_BTN_W  = 48
local LOT_ALL_W   = 58
local PASS_ALL_W  = 64
local BTN_H       = 16
local BTN_FONT    = 11

local PASS_BTN_X  = WINDOW_W - PAD - PASS_BTN_W
local LOT_BTN_X   = PASS_BTN_X - BTN_GAP - LOT_BTN_W
local TIMER_X     = WINDOW_W - PAD - 10
local BTN_Y       = 4
local TIMER_Y     = 19

local layout = {
    window = {
        width   = WINDOW_W,
        headerH = HEADER_H,
        rowH    = ROW_H,
        footerH = FOOTER_H,
        pad     = PAD,
        bg = {
            color = '#1A1A1ADD',
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
            size        = 13,
            color       = '#E8E8E8FF',
            stroke      = '#000000C0',
            strokeWidth = 0,
            bold        = true,
            align       = 'left',
            pos         = { PAD, 3 },
        },

        statusText = {
            font        = 'Lucida Sans Unicode',
            size        = 11,
            color       = '#AAAAAAFF',
            stroke      = '#000000A0',
            strokeWidth = 0,
            bold        = false,
            align       = 'left',
            pos         = { PAD + 10, 19 },
        },

        timerText = {
            font        = 'Lucida Sans Unicode',
            size        = 11,
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
            pos       = { 0, 33 },
            animSpeed = 1,
            imgBg = {
                path  = 'layouts/assets/pixel.png',
                size  = { WINDOW_W, 2 },
                color = '#FFFFFF08',
            },
            imgBar = {
                path  = 'layouts/assets/pixel.png',
                size  = { WINDOW_W, 2 },
                color = '#6EB5FF80',
            },
        },

        lotBtn = {
            pos        = { LOT_BTN_X, BTN_Y },
            size       = { LOT_BTN_W, BTN_H },
            path       = 'layouts/assets/rounded.png',
            sliceBorder = 4,
            label = {
                font        = 'Arial',
                size        = BTN_FONT,
                color       = '#FFFFFFFF',
                strokeWidth = 0,
                align       = 'center',
                pos         = { LOT_BTN_W / 2, math.floor((BTN_H - BTN_FONT) / 2) },
            },
            colors = {
                normal   = 0xFF2A5F85,
                hover    = 0xFF3A7FAA,
                pressed  = 0xFF1A4060,
                disabled = 0xFF333333,
            },
        },

        passBtn = {
            pos        = { PASS_BTN_X, BTN_Y },
            size       = { PASS_BTN_W, BTN_H },
            path       = 'layouts/assets/rounded.png',
            sliceBorder = 4,
            label = {
                font        = 'Arial',
                size        = BTN_FONT,
                color       = '#FFFFFFFF',
                strokeWidth = 0,
                align       = 'center',
                pos         = { PASS_BTN_W / 2, math.floor((BTN_H - BTN_FONT) / 2) },
            },
            colors = {
                normal   = 0xFF2A5F85,
                hover    = 0xFF3A7FAA,
                pressed  = 0xFF1A4060,
                disabled = 0xFF333333,
            },
        },

        separator = {
            path  = 'layouts/assets/pixel.png',
            size  = { WINDOW_W, 1 },
            pos   = { 0, 35 },
            color = '#FFFFFF30',
        },
    },

    footer = {
        lotAllBtn = {
            size        = { LOT_ALL_W, BTN_H },
            path        = 'layouts/assets/rounded.png',
            sliceBorder = 4,
            label = {
                font        = 'Arial',
                size        = BTN_FONT,
                color       = '#FFFFFFFF',
                strokeWidth = 0,
                align       = 'center',
                pos         = { LOT_ALL_W / 2, math.floor((BTN_H - BTN_FONT) / 2) },
            },
            colors = {
                normal   = 0xFF2A5F85,
                hover    = 0xFF3A7FAA,
                pressed  = 0xFF1A4060,
                disabled = 0xFF333333,
            },
        },

        passAllBtn = {
            size        = { PASS_ALL_W, BTN_H },
            path        = 'layouts/assets/rounded.png',
            sliceBorder = 4,
            label = {
                font        = 'Arial',
                size        = BTN_FONT,
                color       = '#FFFFFFFF',
                strokeWidth = 0,
                align       = 'center',
                pos         = { PASS_ALL_W / 2, math.floor((BTN_H - BTN_FONT) / 2) },
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

-- Background theme definitions
-- mode = 'flat'   : solid color pixel fill (uses layout.window.bg.color)
-- mode = '3slice' : top cap / stretchable mid / bottom cap textures
-- mode = 'window' : single bg texture + optional L-shaped border pieces on top
--
-- Themes are auto-loaded from layouts/themes/*.lua — drop a file in to add one.
-- Each file returns a theme definition table; the filename (minus .lua) is the theme name.
local function loadThemes()
    local themes = {}

    local src = debug.getinfo(1, 'S').source:sub(2)
    local layoutsDir = src:match('(.+)[/\\][^/\\]+$')
    local themesDir  = (layoutsDir .. '\\themes'):gsub('/', '\\')

    local handle = io.popen('dir /b "' .. themesDir .. '\\*.lua" 2>nul')
    if handle then
        for filename in handle:lines() do
            local name = filename:match('^(.+)%.lua$')
            if name then
                local modPath = 'layouts/themes/' .. name
                package.loaded[modPath] = nil
                local ok, def = pcall(require, modPath)
                if ok and type(def) == 'table' then
                    themes[name] = def
                end
            end
        end
        handle:close()
    end

    return themes
end

layout.themes = loadThemes()

return layout
