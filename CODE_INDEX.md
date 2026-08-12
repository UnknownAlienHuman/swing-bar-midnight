# Code index

| File/area | Exact anchors |
| --- | --- |
| [`core.lua`](core.lua) defaults/state | `CopyDefaults`, `ParseSpellIDList`, `RecomputeSpeedsAndPeriods`, `state`, `_G.SwingBarMidnightState` |
| [`core.lua`](core.lua) UI | `CreateBar`, `ApplyVisual`, `UpdateLayout`, `CreateMainFrame`, `SetLocked`, `SavePosition` |
| [`core.lua`](core.lua) timing | `AnchorNow`, `CanAcceptAnchor`, `SetPaused`, updater `OnUpdate` |
| [`core.lua`](core.lua) signals/events | `OnGlowShow`, `ScanPlayerAuras`, `OnSpellcastSucceeded`, `UpdateRangeState`, `RegisterEventsNow`, event-frame `OnEvent` |
| [`core.lua`](core.lua) user API | `ns.ApplySettings`, `ns.ResetBarPhase`, `SlashCmdList["SWINGBARMIDNIGHT"]` |
| [`options.lua`](options.lua) | Settings panel, widget writers, `ApplyFromUI`, category opening |

`SwingBarMidnightDB` and the exposed `SwingBarMidnightState` are the cross-file contracts.
