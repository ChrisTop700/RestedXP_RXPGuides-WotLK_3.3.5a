# Attack Timer acceptance

The optional tool defaults off. Enable it under Interface > AddOns > RestedXP
Guides > Feature Tools > Attack Timer, then select Open Tool. The shared
guide/minimap Feature Tools menu also opens it. No attacks are automated.

## Scope

- Main/off-hand and ranged damage are live character-sheet ranges, not predicted
  target damage or future random rolls. Forms use the client's active values.
- Timers are estimates synchronized from stock 3.3.5 events. Auto Shot uses
  player spell success ID 75, never projectile impact. If a client does not
  supply that event/ID, timing stays unknown; do not substitute damage time.
- Single-weapon swings include misses. Dual-wield events do not reliably identify
  hands on stock 3.3.5; their hand estimates become unknown after a swing.
- Wands display damage/interval only. Abilities, equipment/form changes and combat
  exit invalidate estimates. Extra attacks can reduce accuracy; this is not a
  rotation or damage-gain advisor.
- AzerothCore coupled melee/ranged resets are on by default. The separate option
  allows independent timers on servers whose behavior has been verified to differ.
- No combat identities/history are persisted. No protected actions are called.

## In-game checks still required

1. Confirm disabled login has no attack-timer events or scheduled display work.
2. Enable without reloading. Open on the first click; move/resize it, alter font,
   opacity and scale, close/reopen, and verify placement. Escape must not close it.
3. With a Hunter, compare ranges and intervals against the character sheet.
   Shoot at near and far targets: timer starts on release, not impact. Check misses.
4. Repeat single-weapon melee and transitions between melee and ranged; confirm
   both directions of coupled resets against actual server behavior.
5. Equip two weapons: both damage ranges remain visible, but ambiguous hand
   countdowns become unknown. Do not claim accurate off-hand timing.
6. Check Druid Cat/Bear shifts, haste changes, weapon swaps and temporary buffs:
   values refresh and stale countdowns disappear. Check a caster wand shows stats
   without a fabricated countdown. Check the other melee classes normally.
7. Toggle every display option; change profile; disable while open. No reload,
   residual window, duplicate timer or Lua error should occur. Closing the window
   stops display work but keeps enabled event synchronization available.
8. Repeat with Questie tracking enabled. This tool never touches quest/map state.

Automated coverage: `tests/attack-timer.lua` runs production timing and event
handlers plus mocked window lifecycle through `tests/run.lua`. Gameplay checks
above remain unverified until performed on a stock 3.3.5 client.
