# TreasurePool

**An FFXI addon for HorizonXI (Ashita v4) that displays your treasure pool with interactive lot and pass controls.**

TreasurePool shows every item currently in the loot pool alongside a live countdown timer, the current winning lotter, and hover-activated lot/pass buttons. It tracks all party and alliance members' lot and pass results in real time via server packets.

> Based on the original [TreasurePool](https://github.com/ShiyoKozuki/TreasurePool) by Shiyo. Rewritten with a sprite render system, GDI font rendering, packet-driven state, and extended UI features.

<img width="448" height="725" alt="image" src="https://github.com/user-attachments/assets/433b9caf-d2f4-419d-96b2-4faa196983a1" />

---

## Features

- Live countdown timer bar per item with urgency color shifts
- Lot/Pass buttons appear on hover; suppressed when already actioned
- **Lot All** / **Pass All** footer buttons for batch actions
- Rare item ownership detection — lot button is suppressed and item name turns red if you already own a Rare item in the pool
- **Lot Details popup** — click any item row to see every party and alliance member's lot/pass status
- **Item tooltip** on hover — shows item description, equip level, and usable jobs
- Collapsible header (arrow click or toggle in settings)
- 11 built-in themes plus support for custom themes
- Custom UI scale with auto-detect from resolution (1440p baseline)
- Alliance-aware: supports up to 18 members across three parties
- Packet-driven state — zero memory reads per frame during normal rendering

---

## Display

### Item Row

Each row in the pool shows:
- **Item icon** (loaded from game resources)
- **Item name** — red if it is Rare and you already own one
- **Rare / Ex tags** next to the name where applicable
- **Status line** (below the name) — shows the current leading lotter by default; switches to your own status on hover
- **Timer** — countdown in `M:SS` format, color-coded by urgency
- **Timer bar** — thin bar spanning the row width, fades as time runs out

### Status Colors

| Color | Meaning |
|-------|---------|
| White | No action taken |
| Blue | Passed |
| Gold | Lotted — currently winning |
| Orange | Lotted — currently losing |

### Lot Details Popup

Click any item row (when **Show Lot Details** is enabled) to open a popup showing all party and alliance members and their current status for that item.

| Status | Color |
|--------|-------|
| Pending | Gray |
| Pass | Blue |
| Lot number | White (losing) / Gold (winning) |

Members no longer in the party who have actioned the item (e.g. Dynamis cross-alliance lots) appear at the bottom of the list.

---

## Commands

| Command | Action |
|---------|--------|
| `/treasurepool` | Toggle the settings window |

---

## Settings

Open with `/treasurepool`.

### Display Tab

| Setting | Description |
|---------|-------------|
| **Theme** | Visual style for the window background. See [Themes](#themes). |
| **Lock position** | Disables dragging the window. |
| **Collapsible header** | Shows a collapse arrow in the header. Click it to hide all rows and show only the title bar. State is saved between sessions. |
| **Custom Scale** | Override the auto-detected UI scale. Drag the slider between ×0.25 and ×2.5. Auto-detect uses screen height ÷ 1440. |
| **Items** *(Debug)* | Number of fake items to show when the settings window is open (1–10). Used for previewing layout and theme changes without being in a live loot scenario. |
| **Reload Layout** | Hot-reloads `layouts/default.lua` and all theme files without restarting the addon. |

### Interactions Tab

| Setting | Description |
|---------|-------------|
| **Show Item Tooltip** | Enables hover tooltips showing item stats and description. |
| — Gear | Include tooltips for weapons and armor. |
| — Usables | Include tooltips for consumables (food, medicines, scrolls, etc.). |
| — Items | Include tooltips for everything else (seals, crystals, key items, etc.). |
| **Show Lot Details** | Enables the click-to-open lot details popup per item row. |

---

## Themes

The **Theme** dropdown in settings lists all available themes. Custom themes appear above built-in ones.

**Built-in themes:** `Plain`, `xiv`, `ffxi`, `Window1` – `Window8`

**Custom themes:** Drop a `.lua` file into `layouts/themes/`. The filename (without `.lua`) becomes the theme name. Click **Reload Layout** to pick it up without restarting. See existing theme files for the definition format.

---

## Fonts

TreasurePool uses three fonts that must be installed before launching the game client. They are included in the release download.

| Font | Used for |
|------|----------|
| Penumbra Serif Std | Window title |
| Grammara | Item countdown timers |
| Tahoma | Item names, status text, buttons |
