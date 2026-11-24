# CloudeMap

> **AI disclaimer:** CloudeMap's code, its icon and this README were written with an AI
> assistant (Claude, by Anthropic), directed, tested and reviewed in game by a human. Expect the
> occasional rough edge; use it at your own risk.

A lightweight, seamless world map for WoW Forever (Interface 16001). One window, every zone of a
continent stitched together, zoomable from the whole world down to street level.

CloudeMap started as a personal addon, made to fit the way I like to play. It has grown into
something I'm happy to share with the WoW community, so here it is. It's still mainly my own
project: features and fixes follow what I need in game, but feedback is welcome.

**Inspired by Carbonite.** Thanks to its developers. No Carbonite code was reused; CloudeMap is
written from scratch.

Version 0.19.11 · SavedVariables: CloudeMapDB

---

## Features

### Map
- Whole continents as one seamless map; pan and zoom across zone borders.
- Two modes: **parchment** (zone art) and **satellite** (minimap terrain).
- The zone under the pointer and your own zone are shown in full detail.
- Cities take priority over the surrounding zone.
- Unexplored areas shown dimmed.

### Window
- Move, resize, set opacity; position and size are remembered.
- Big window button (or double-click the title bar): switches between normal and big size, each
  remembering its own size and position. Big starts centred at about 88% of the screen.
- Frame fades out when the pointer leaves, like Carbonite; map and text stay.
- Title bar: your zone, its level range and your position.
- Pointer readout: zone, level range, position and distance from you in yards.
- Level ranges coloured by faction: green yours, orange contested, red enemy.
- Zoom level shown while zooming: x1 is the whole world, the wheel steps through round figures (x1.5, x2, x3 … x24, x32 …).
- Toolbar: parchment/satellite, Follow, Options, plus Dungeon Journal and BG when available.
- Options: Size and opacity (window opacity, pin, party pin, player marker and GatherMate pin
  sizes), Pins, Quest areas and Pings each open their own list beside the menu with a click (one
  at a time, a second click closes it).
- Minimap button to show/hide the map.

### You and your group
- Player arrow, always on top, with its own size slider.
- Follow mode keeps the map centred on you.
- Party and raid members in class colours, the same size at every zoom (own size slider in Options).
- Death marker at your corpse.

### Pins
- Flight masters, dungeons and raids, trainers, innkeepers, mailboxes, auctioneers, bankers,
  anvils and forges, zone links.
- The game's map pin: Ctrl+right click to set or remove.
- Quest markers and quest areas (all quests with others dimmed, or tracked only).
- Ley lines and elemental convergences for the Skyborne racial. **Until further notice this includes
  unverified places:** player reports to the LeyLines addon still waiting for its maintainer's
  review, marked "Unconfirmed" in their tooltip (they may be off or missing).
- Every category has its own toggle; one switch turns all pins off and back on.
- Pin size adjustable.

### Group pings
- Alt+click the map to ping a spot for your party or raid; group members with CloudeMap see it.
- Drawn like the minimap ping (the game's own ping pictures), at the minimap's size at any zoom.
- A ping outside the part of the map in view shows at the window's edge, pointing towards it.
- A ping within your minimap is also placed on your minimap. Minimap pings are not shown on this
  map: the game doesn't let addons listen for them.
- Sound to choose (map ping by default, whisper, boss warning, ready check, raid warning, or none)
  and an optional chat line, off by default, in Options -> Pings.

### Battlegrounds
- BG button appears inside a battleground and shows its map with landmarks and your team.

### Performance
- Redraws only what changed; panning is cheap.
- Large pin sets load over several frames.
- Optional update cap (Options, clock button): 60 or 30 map updates per second.

## Addon compatibility

All of these are optional and detected automatically. Their pins are listed under
**Options → Pins → Other addons**, each with its own toggle.

| Addon | What CloudeMap does with it |
|---|---|
| **Questie** | Quest giver, available quest and objective pins. |
| **HandyNotes** | Pins from every plugin, one toggle per plugin. |
| **GatherMate2** | Gathering nodes, one toggle per node type, own size slider. |
| **RareScanner** | Rare pins and spawn areas, sized like RareScanner's own; its tooltip stays while hovered. |
| **Spy** | Nearby enemy players as red dots at your exact position when last seen (kill on sight brighter, inactive dimmed), its fight markers, and enemies reported by other Spy users. Follows Spy's own timeouts and options. |
| **ForeverDungeonJournal** | Its dungeon maps drawn by CloudeMap itself (both windows can show them at once): floors, bosses with portraits, entrances, ladders between floors, quest spots; fitted to the window, wheel zoom and drag, dungeon picker; switched on automatically inside a dungeon. Optional sync (Options): a dungeon or floor picked in one window is shown in the other. Its "Show on Map" X marker (left click targets and marks, right click removes) and dungeon entrance pins on the world map. |
| **HereBeDragons-Pins** | World map icons from any addon that uses this library. |
| **Other addons' map pins** | Waypoints set through the game's map pin show up too. |

Other addons can add their own pin categories through `_G.CloudeMap`, and plugins can draw on
the map itself through `CloudeMap.Map` (map position, conversions, redraw, click and status
callbacks; documented in Bridge.lua). Categories can set a minimum on-screen size so their pins
stay visible zoomed right out.

## Slash commands

`/cmap` or `/cloudemap`

| Command | What it does |
|---|---|
| *(none)* | show / hide the window |
| `help` | list the commands in chat |
| `show`, `hide` | show or hide the window |
| `me` | back to the hero, Follow on |
| `follow` | toggle Follow |
| `map`, `sat`, `mode` | parchment map, satellite, or toggle |
| `quests dim` / `quests tracked` | quest area mode |
| `reset` | reset the window position and size |
| `status`, `debug` | status report in a copy window |
| `where` | what is under the middle of the view |
| `prof` | start / stop the profiler (report in a copy window) |
| `fade` | 3 s log of zone uncovering (diagnostics) |

## Credits

- Unexplored-area data: OpenMap contributors (MIT, see `Reveal.LICENSE.txt`).
- Ley line positions: the LeyLines addon by Wafhien and contributors (github.com/Wafhi3n/LeyLines).

## Copyleft

CloudeMap is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, either version 3 of
the License, or (at your option) any later version. Any copy or modified version you
distribute must stay under the same license, with its source available.

CloudeMap is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details: <https://www.gnu.org/licenses/gpl-3.0.html>.

Bundled third-party data keeps its own license (see Credits). World of Warcraft and its art are
trademarks and property of Blizzard Entertainment; CloudeMap is not affiliated with or endorsed
by Blizzard.
