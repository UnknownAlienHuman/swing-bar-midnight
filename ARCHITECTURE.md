# Architecture

The TOC loads [`core.lua`](core.lua) before [`options.lua`](options.lua). Core owns `SwingBarMidnightDB`, cached MH/OH periods, `SwingBarMidnightFrame`, event registration, the display `OnUpdate`, and `/swingbar`; options only edits the same DB and calls `ns.ApplySettings`.

Timing flow is cached attack speed -> `t0MH`/`t0OH` phase -> progress/text in the updater. Overlay/aura/cast events may call `AnchorNow`, while suppression/debounce/range pause gate anchors. Combat-time event registration and protected action hooks are explicitly deferred/guarded.

The debugger is a separate companion that reads the exported state table; it is not a TOC dependency of this addon.
