# SwingBarMidnight agent guide

## Start here

Read [`SwingBarMidnight.toc`](SwingBarMidnight.toc), then [`core.lua`](core.lua) from defaults/state through `CreateMainFrame`, timing/update loop, events, and slash commands. [`options.lua`](options.lua) is a UI writer for the same `SwingBarMidnightDB`; it must not duplicate timing logic.

TOC release metadata is `0.8.1` (`SwingBarMidnight.toc`, `## Version`).

## Load order and execution path

Complete `loadedFiles` inventory (root `docs/addon-architecture.json`, in execution order):

```text
core.lua
options.lua
```

The TOC loads [`core.lua`](core.lua) and then [`options.lua`](options.lua). Core merges defaults, creates `SwingBarMidnightFrame` with MH/OH bars, caches weapon periods, and installs a 16 ms-ish `OnUpdate` display loop. The loop computes phase from `t0MH`/`t0OH`, applies optional combat visibility, range pause, and text/progress rendering.

Event registration (`RegisterEventsNow`) covers combat transitions, attack speed/equipment, SpellActivationOverlay show/hide, target changes, player aura/spellcast, action-slot and macro changes. Registration is deferred out of combat when the addon is loaded during combat. Glow/aura/cast signals call `AnchorNow` subject to suppression/debounce; `OnAttackSpeedChanged` rescales phase to avoid jumps.

## State and surfaces

- SavedVariables: `SwingBarMidnightDB` (`enabled`, combat visibility, lock/position/size/scale, MH/OH rendering, colors/textures, glow/aura/attack anchoring, suppression, range gating, action fallback, debug).
- Runtime globals intentionally exposed for the companion debugger: `_G.SwingBarMidnightState` and `_G.SwingBarMidnight_InternalState` (same table).
- Slash: `/swingbar options|unlock|lock|reset|toggle|attackanchor|auraanchor|range|freeze|version`.
- Settings: `options.lua` registers a Settings category (with compatibility fallback), writes DB fields and calls `ns.ApplySettings`.

## Dependencies and relationships

The addon uses Blizzard spell/aura/range/action/overlay APIs and `hooksecurefunc("UseAction", ...)` when `useActionFallback` is enabled. It has no external TOC dependencies and no checked-in dependency on the debugger; the debugger reads the exposed state/DB conditionally. Avoid assuming `AuraUtil.FindAuraBySpellId` or `C_Spell.IsSpellInRange` exists; both have fallbacks.

Falsification notes: there is no `COMBAT_LOG_EVENT_UNFILTERED` registration, no Masque integration, and no CDM integration. The core has a real permanent display `OnUpdate` (`core.lua:731`) plus a short combat-registration deferral updater (`core.lua:909`); any change must preserve the cached-speed/throttled hot path.

## Change routing

- DB/defaults/secret-safe parsing: top of [`core.lua`](core.lua).
- Swing math/haste/offhand/phase anchoring: `GetAttackSpeeds`, `RecomputeSpeedsAndPeriods`, `GetPeriods`, `AnchorNow`, `CanAcceptAnchor`, `SetPaused`.
- Frame geometry/visuals: `CreateBar`, `ApplyVisual`, `UpdateLayout`, `CreateMainFrame`, `SetLocked`, `SavePosition`.
- Range and suppression: `UpdateRangeState`, `OnSpellcastSucceeded`, `BuildWatchedSlots`, `UseAction` hook.
- Event lifecycle: `RegisterEventsNow` and the core event-frame `OnEvent`; preserve combat deferral.
- Settings controls/application: [`options.lua`](options.lua), `ns.ApplySettings`.

## Invariants and risks

- The `OnUpdate` loop must use cached speeds; it must not call `UnitAttackSpeed` each frame or add expensive aura/range scans. Range checks are throttled to 0.10 s.
- `state` is declared before helpers capture it; do not move the declaration below `GetPeriods`/timing helpers.
- Anchors are rising-edge/debounced and suppressed after Frost Strike, Glacial Advance, Howling Blast, and Empower Rune Weapon. Preserve `suppressUntil`/`lastAnchor` semantics.
- `UseAction` is a secure hook. Only read `watchedSlots`; do not perform protected writes or rebuild slots in combat.
- `BackdropTemplate`/frame movement/resizing can be combat-sensitive. Lock state must disable mouse/drag/resizer while locked.
- Aura presence reads only existence by spell ID; never branch on secret aura fields.

## Verification

1. Verify TOC references and parse Lua.
2. In-game `/reload`; test `/swingbar version`, options, lock/unlock/reset/toggle.
3. Verify one-weapon and dual-wield timing, haste/equipment changes, progress/text, scale/resize/position persistence.
4. Exercise overlay glow show/hide, aura gain, cast suppression, attack-anchor option, action/macro updates, combat transitions and target range gating.
5. Confirm no per-frame API errors, no incorrect phase jumps after haste changes, and no protected/taint errors from drag/resizer or `UseAction` hook.
6. If the debugger is installed, confirm its state sample matches `_G.SwingBarMidnightState` without making the main addon depend on it.

## Uncertain or version-sensitive claims

SpellActivationOverlay event names, `GetSwingSpeeds`, attack speed semantics, `AuraUtil.FindAuraBySpellId`, range APIs, and combat restrictions around event registration vary across Midnight builds. Verify against the current client and Blizzard UI source before changing these paths.
