# SwingBarMidnight architecture

## Ownership

`core.lua` is the only runtime/timing owner. It owns `SwingBarMidnightDB`, accessibility gates, cached MH/OH periods, prediction phase origins, frame creation, visual update, movement/resizing, combat visibility, events, slash commands, and the out-of-combat apply boundary.

`options.lua` is a Settings writer for the same DB. It does not compute speed, phase, progress, visibility, or layout. Every value-change callback invokes `ns.ApplySettings`.

## Load order

```text
SwingBarMidnight.toc
  -> core.lua
  -> options.lua
```

There are no runtime dependencies and no GitHub Actions workflow.

## Input boundary

The only game timing input is `UnitAttackSpeed("player")`.

```text
accessible positive MH -> mhPeriod
accessible positive OH -> ohPeriod
accessible nil OH      -> absent
inaccessible value     -> inaccessible, period=nil
API failure/missing    -> unavailable/missing, period=nil
```

`canaccessvalue` or `issecretvalue` is evaluated before the result is treated as an ordinary number. No inaccessible value reaches comparison, modulo, division, formatting, status output, or SavedVariables.

The runtime does not read aura state, proc state, action slots, macros, target/range state, combat log, SpellActivationOverlay, or spell casts to establish phase.

## Prediction model

Each hand has:

```text
period
t0 phase origin
accessibility/status label
```

Progress is:

```text
phase = (now - t0) % period
progress = phase / period
remaining = period - phase
```

This is a prediction from a chosen seed, not an observed hit timestamp.

When an accessible period changes, `PreserveFraction` retains the prior fractional progress. If either old or new period is unavailable, phase reseeds at the current time and stale period data is discarded.

`ResetBarPhase` seeds both hands at the current accessible clock and records an ordinary reason string.

## Dual wield

The default presentation shows main hand only. When `showOffhand` is enabled, the frame displays independent MH and OH rows if OH is accessible or explicitly inaccessible. The addon does not combine periods harmonically and does not claim the real inter-hand phase offset.

## Frame and hot path

The addon owns one top-level frame and two pre-created child bars. One `OnUpdate` script is attached to the top-level frame and therefore stops when the frame is hidden. It reads only cached ordinary periods/origins plus accessible `GetTime`; `UnitAttackSpeed` is never called per frame.

The hot path is throttled to approximately 20 ms and performs bounded arithmetic and two texture-width/text updates at most.

## Events

```text
PLAYER_REGEN_DISABLED
PLAYER_REGEN_ENABLED
UNIT_ATTACK_SPEED player
PLAYER_EQUIPMENT_CHANGED
```

Attack-speed/equipment events recompute cached periods. Combat events control visibility and complete one pending settings apply. There are no aura, overlay, action-bar, target, spellcast, timer, or polling events.

## Combat boundary

Point, size, scale, visual configuration, drag registration, and lock/resizer state are not changed in combat. `ns.ApplySettings` sets one pending flag; `PLAYER_REGEN_ENABLED` applies current DB state once.

The animation itself uses addon-owned textures and ordinary cached values. It does not mutate Blizzard protected state.

## Retired model

Schema v2 removes persisted settings for glow/aura/attack anchors, action fallback, range gating, freeze behavior, suppression windows, watched spell lists, and debug heuristics. The old hard-coded 2.0 fallback and harmonic combined period are removed.

## Evidence boundary

The deterministic regression proves the local access/prediction/combat contract against mocks. It does not prove that a predicted phase matches actual live melee hits. Exact swing phase remains unavailable without a separately proven legal event source.
