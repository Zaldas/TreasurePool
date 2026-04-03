local W = 250

return {
    mode = '3slice',
    imgTop = {
        path        = 'layouts/assets/xiv/BgTop.png',
        size        = { W, 6 },
        pos         = { 0, 0 },
        color       = '#FFFFFFBB',
        sliceBorder = { 60, 60, 0, 0 },
    },
    imgMid = {
        path  = 'layouts/assets/xiv/BgMid.png',
        size  = { W, 32 },
        pos   = { 0, 6 },
        color = '#FFFFFFBB',
    },
    imgBottom = {
        path        = 'layouts/assets/xiv/BgBottom.png',
        size        = { W, 6 },
        pos         = { 0, 38 },
        color       = '#FFFFFFBB',
        sliceBorder = { 60, 60, 0, 0 },
    },
}
