# SwingBarMidnight

Retail 12.1 predicted melee-cadence display based only on accessible `UnitAttackSpeed("player")` values.

This is **not** an exact swing-hit parser. Retail 12.1 does not provide this addon with a legal, unambiguous main-hand/off-hand hit timestamp. The bar therefore shows a deterministic prediction seeded at load, equipment changes, or an explicit manual phase reset.

## Compatibility

- Game: World of Warcraft Retail / Midnight 12.1.0
- Interface: `120100`
- Version: `0.9.0`
- Verified Blizzard source baseline: `12.1.0.69497`
- SavedVariables: `SwingBarMidnightDB`
- External dependencies: none

## Evidence model

The only timing input is accessible `UnitAttackSpeed`:

- accessible positive main-hand speed → MH period;
- accessible positive off-hand speed → independent OH period;
- accessible `nil` off-hand → no off-hand weapon;
- inaccessible value → `inaccessible`, no fake period;
- missing/API failure → `missing` or `api unavailable`, no fake period.

The removed 0.8.x implementation used a hard-coded `2.0` fallback, harmonic combined-stream math, proc auras, SpellActivationOverlay glows, action-slot scans, `UseAction` hooks, attack-spell casts, range checks, and suppression windows as phase anchors. Those signals do not prove an actual swing boundary and are no longer used.

## Main-hand and off-hand

By default the addon displays only the main-hand prediction. Enable **Show separate off-hand prediction** to display independent MH and OH bars when an off-hand speed exists. The bars do not claim the real offset between hands; both phase origins are seeded together unless manually reset.

When an enabled off-hand value is inaccessible, the OH row remains visible and says `inaccessible` instead of substituting a period.

## Phase

Phase is prediction state, not observed hit history.

- load/equipment acquisition seeds phase at the current time;
- accessible speed changes preserve the fractional progress of the previous prediction;
- transitions to inaccessible/missing values discard the stale period;
- `/swingbar resetphase` explicitly seeds both predictions at the current time.

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

`/swingbar status` labels the output `prediction only` and reports accessibility status for both hands.

## Performance and combat behavior

- one `UNIT_ATTACK_SPEED` unit event and `PLAYER_EQUIPMENT_CHANGED` refresh cached periods;
- the display `OnUpdate` is attached to the visible bar frame, so it does not run while the frame is hidden;
- no aura event, overlay event, action-slot scan, range poll, timer, or secure hook;
- UI geometry, drag registration, scale, width, and height changes defer in combat and apply on `PLAYER_REGEN_ENABLED`;
- inaccessible values are rejected before arithmetic, comparison, formatting, or persistence;
- no GitHub Actions workflow is included.

## Validation status

The exact branch files pass local Lua 5.1 parsing and `tests/test_predicted_cadence_12_1.lua`. The regression verifies inaccessible speeds, no fake fallback, no aura/glow/action-slot events, accessible MH/OH periods, explicit `predicted` text, manual phase reset, stale-period removal, hidden-frame updater ownership, and combat-deferred settings.

Live validation is still required for real `UnitAttackSpeed` accessibility, one-hand/dual-wield equipment changes, haste changes, combat visibility, frame movement/resizing, Settings, reload persistence, taint, errors, and CPU usage.

## Developer documentation

- [Architecture](ARCHITECTURE.md)
- [Agent guide](AGENT_GUIDE.md)
- [Code index](CODE_INDEX.md)
- [Code graph](CODE_GRAPH.md)
- [WoW addon engineering knowledge base](https://github.com/UnknownAlienHuman/wow-addon-engineering-kb)

## License

Licensed under the [MIT License](LICENSE).
