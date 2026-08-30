# SwingBarMidnight code index

| Path | Responsibility |
|---|---|
| `SwingBarMidnight.toc` | Retail 12.1 metadata and definitive load order |
| `core.lua` | Schema v2 sanitization, access-first `UnitAttackSpeed` boundary, cached MH/OH periods, prediction phase, frame/bars, visible-frame updater, events, combat-deferred apply, drag/resize and slash commands |
| `options.lua` | Current Blizzard vertical Settings category; writes the shared DB and calls `ns.ApplySettings` |
| `tests/test_predicted_cadence_12_1.lua` | Mocked regression for inaccessible/missing/dual speeds, no fake fallback, explicit prediction labels, manual phase reset, hidden-frame updater ownership and combat deferral |

Removed runtime responsibilities:

- aura/proc anchoring;
- SpellActivationOverlay/action-button glow anchoring;
- action-slot/macro/`UseAction` scanning;
- range gating;
- attack-spell anchoring and suppression windows;
- harmonic combined-stream timing;
- fake 2.0-second fallback.
