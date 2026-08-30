# SwingBarMidnight agent guide

## Start here

Read [`SwingBarMidnight.toc`](SwingBarMidnight.toc), [`core.lua`](core.lua), [`options.lua`](options.lua), and [`ARCHITECTURE.md`](ARCHITECTURE.md).

Target contract:

- Retail / Midnight `12.1.0`;
- Interface `120100`;
- version `0.9.0`;
- verified source baseline `12.1.0.69497`;
- no external dependency;
- no GitHub Actions workflow.

## Product claim

This addon is a **predicted melee cadence display**, not an exact swing-hit parser.

The only permitted timing input is accessible `UnitAttackSpeed("player")`. The phase seed is local prediction state. Never describe the remaining-time text as the actual time to the next real hit unless a separately proven legal hit-event source is added and validated.

## Hard prohibitions

Do not restore:

```text
hard-coded attack-speed fallback
harmonic combined MH/OH stream
UNIT_AURA or AuraUtil proc anchors
SpellActivationOverlay events/method hooks
ActionButton overlay-glow hooks
UseAction hook
action-slot or macro scans
attack-spell cast anchoring
range gating or range polling
suppression/debounce windows presented as hit evidence
combat-log inference
```

Those are correlated presentation or gameplay signals, not proof of an actual main-hand/off-hand swing boundary.

## Access boundary

`ReadAttackSpeeds` must decide accessibility before treating either return as a number.

- inaccessible MH/OH: period `nil`, status `inaccessible`;
- accessible nil OH: status `absent`;
- API failure: status `api error`/`api unavailable`;
- never substitute a period;
- never reuse a stale period after accessibility is lost.

No raw value may be compared, divided, modulo-reduced, formatted, logged, or persisted before the access decision.

## Prediction state

Runtime state contains:

```text
mhPeriod / ohPeriod
mhStatus / ohStatus
t0MH / t0OH
pendingApply
phaseReason
```

`PreserveFraction` is allowed only when both old and new periods are accessible positive numbers. Otherwise reseed at the current time.

`ResetBarPhase` is the only explicit phase-reset boundary. It resets both hands and records an ordinary reason. `/swingbar resetphase` exposes it to the user.

## Dual wield

Do not combine MH/OH periods. `showOffhand` displays separate predictions. The addon does not know the real offset between hands; both seeds normally begin together.

When OH is inaccessible and the option is enabled, retain a visible OH row labelled `inaccessible`. When OH is accessible nil, treat it as absent and hide the row.

## Frame and performance ownership

`core.lua` creates the top-level frame and both bars once. All visual children exist before combat use.

The only `OnUpdate` belongs to the top-level visible bar frame. Hidden frames do not run the updater. The updater:

- uses cached periods only;
- reads accessible `GetTime`;
- is throttled to about 20 ms;
- updates at most two fill widths and labels;
- never calls `UnitAttackSpeed` or other game-state APIs.

Do not create a separate permanently shown updater frame.

## Events

Allowed timing/lifecycle events:

```text
UNIT_ATTACK_SPEED player
PLAYER_EQUIPMENT_CHANGED
PLAYER_REGEN_DISABLED
PLAYER_REGEN_ENABLED
```

Attack-speed/equipment events update cached periods. Combat events control visibility and apply one pending settings update.

## Combat boundary

Do not change point, size, scale, visual assets, drag registration, lock state, or resizer visibility during combat. `ns.ApplySettings` must set `pendingApply` and return. `PLAYER_REGEN_ENABLED` applies current DB state once.

Use `RegisterForDrag()` with no arguments to clear drag buttons while locked; do not pass a literal `nil` argument.

## Settings and schema

`options.lua` uses Blizzard's vertical Settings API and writes only current schema-v2 fields:

- enabled/combat-only/locked;
- separate OH display;
- text;
- width/height/scale/font size;
- background/border alpha.

Legacy glow/aura/action/range/suppression keys are removed by `SanitizeDB`. Do not expose them again.

## Commands

```text
/swingbar options
/swingbar unlock
/swingbar lock
/swingbar reset
/swingbar resetphase
/swingbar toggle
/swingbar status
/swingbar version
```

`status` must retain `prediction only` wording and per-hand accessibility labels.

## Verification

Local:

```text
texlua --luaconly core.lua options.lua tests/test_predicted_cadence_12_1.lua
texlua tests/test_predicted_cadence_12_1.lua
```

Expected:

```text
PASS: inaccessible speeds never receive a fake fallback; MH/OH cadence is explicitly predicted and settings defer in combat
```

Static review must find no aura, overlay, action-slot, range, timer, combat-log, or hard-coded-period path.

Live gates:

- one-hand, dual-wield, equip/unequip and haste changes;
- accessible/inaccessible `UnitAttackSpeed` contexts;
- manual phase reset and honest labels;
- combat-only visibility;
- movement/resizing/locking/Settings/reload persistence;
- no Lua, taint, blocked/forbidden action or meaningful hidden-frame CPU use.

Local/mock success does not prove actual swing-hit synchronization. Record the exact build for all client results.
