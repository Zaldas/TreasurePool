-- width (size[1]) is filled in at runtime from layout.window.width
return {
    mode = '3slice',
    imgTop = {
        path        = 'layouts/assets/ffxi/BgTop.png',
        size        = { 0, 6 },
        pos         = { 0, 0 },
        color       = '#FFFFFFBB',
        sliceBorder = { 60, 60, 0, 0 },
    },
    imgMid = {
        path  = 'layouts/assets/ffxi/BgMid.png',
        size  = { 0, 32 },
        pos   = { 0, 6 },
        color = '#FFFFFFBB',
    },
    imgBottom = {
        path        = 'layouts/assets/ffxi/BgBottom.png',
        size        = { 0, 6 },
        pos         = { 0, 38 },
        color       = '#FFFFFFBB',
        sliceBorder = { 60, 60, 0, 0 },
    },
}
