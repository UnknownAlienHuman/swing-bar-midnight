# Architecture

`core.lua` owns `SwingBarMidnightDB`, main-frame creation, visual application, timing state, an updater frame, event registration, and `/swingbar`. It has helpers for attack-speed recomputation, aura presence, range state, and phase anchoring. `options.lua` builds a scrollable configuration panel and routes Apply/reset settings into the core namespace.

The TOC loads the core before options, so options consume the runtime namespace and persisted settings established by the core.
