local W = 300

return {
    mode = '3slice',
    imgTop = {
        path        = 'layouts/assets/ffxi/BgTop.png',
        size        = { W, 6 },
        pos         = { 0, 0 },
        color       = '#FFFFFFBB',
        sliceBorder = { 60, 60, 0, 0 },
    },
    imgMid = {
        path  = 'layouts/assets/ffxi/BgMid.png',
        size  = { W, 32 },
        pos   = { 0, 6 },
        color = '#FFFFFFBB',
    },
    imgBottom = {
        path        = 'layouts/assets/ffxi/BgBottom.png',
        size        = { W, 6 },
        pos         = { 0, 38 },
        color       = '#FFFFFFBB',
        sliceBorder = { 60, 60, 0, 0 },
    },
}
