# Attack Timer acceptance

The optional tool defaults off. Enable it under Interface > AddOns > RestedXP
Guides > Feature Tools > Attack Timer, then select Open Tool. The shared
guide/minimap Feature Tools menu also opens it. No attacks are automated.
Uncheck **Show Explanatory Text** on the same settings page to hide all footer
notes, including ranged inactivity and dual-wield caveats. It defaults on and
applies live without resetting timers. The limitations below still apply when
their on-window explanation is hidden.

## Initial audit findings (2026-10-13; historical)

This is a basic-attack estimator, not a full server combat simulator. The audit
read the production handlers/model, scheduler, tool-window factory, settings,
and local AzerothCore Unit/Spell/PlayerUpdates implementations. No combat-model
repairs are included in the explanatory-text option change.

| Finding | Effect and evidence | Priority |
| --- | --- | --- |
| Incoming parry haste is unhandled | The handler rejects non-player sources before inspecting the destination. AzerothCore `Unit::DealMeleeDamage` can shorten the victim's melee timer after a parry. The display can consequently predict too late until the next observed swing. Mock confirms no adjustment. | High for melee precision |
| Most ability-specific resets are unhandled | Only an actual Raptor Strike damage/miss has a special branch. Heroic Strike, Cleave, Maul and server spell-attribute-based resets are not a general supported model. A Heroic Strike mock leaves the old deadline unchanged. Do not restore the previous blanket spell-success reset: queued actions are not completed swings. | High outside basic attacks |
| Dual-wield hand assignment is heuristic | Without a hand indicator, the earliest estimated deadline is chosen. Simultaneous attacks, equal-speed weapons, initial off-hand attacks and extra attacks can select the wrong hand. Server off-hand staggering is also not modelled. | Known precision limit |
| Delayed duplicate shot notification | Deduplication uses at most 0.25 seconds, not a shared cast identity. The same release reported through a second source at +0.30 seconds starts another countdown in the mock. Conversely, an unusually fast real shot inside the window can be suppressed. | Medium; event-latency dependent |
| Transient missing equipment/speed data | A nil weapon link or zero speed can erase a deadline; restoring the data does not restore the old deadline. A zero/recovered-speed mock reproduces this. Identical-link weapon swaps are indistinguishable from unchanged-link notifications. | Medium; live reproduction pending |
| Zero is not guaranteed attack readiness | It also represents an unsynchronized state. Range, facing, movement, casting, line of sight and server retry timing may delay an actual attack after zero. No deadline is restarted merely to simulate ongoing attacks. | Intentional display contract |
| Wands and other ranged attacks | Wands have no observed release countdown. Coupled melee resets can still populate a ranged-slot estimate; that must not be interpreted as verified wand timing. Non-Auto-Shot ranged abilities are not fully modelled. | Scope limitation |
| World entry, death and real form changes | These intentionally discard timing. A late event arriving around such a transition can leave synchronization unavailable until the next observed attack. An unchanged form notification now preserves deadlines. | Conservative behavior |

The local AzerothCore `Unit::ApplyAttackTimePercentMod` preserves the remaining
fraction on haste changes, matching the model's proportional speed adjustment.
It does not establish support for every private server's customized timing.

Verified safeguards include first-shot/unchanged-form preservation, localized
Auto Shot recognition, projectile impacts never resetting release timing,
queued Raptor Strike preserving deadlines, its actual strike resetting main
hand, combat-exit continuity, independent/coupled calculations, and no automated
combat actions. Diagnostic data is bounded, opt-in and session-only.

Window/lifecycle checks cover repeated rendering, hide/reopen, distinct display
and diagnostic scheduler ownership, disabling event collection, and live help
visibility retaining the same state/deadline/ticker. Characterization assertions
in `tests/attack-timer.lua` deliberately document known shortcomings; passing
them does not mean those shortcomings have been repaired.

Recommended next work is a separately reviewed ability/parry model, followed by
event-source-aware duplicate handling and evidence-based transient-cache guards.
Verify each against server behavior and captured events rather than weakening
the confirmed first-shot and out-of-range safeguards.

## Follow-up repairs

- Minimum window dimensions are now 190 by 100 logical pixels (previously
  300 by 200). Drag the bottom-right resize grip; overflowing content scrolls.
- Incoming melee parries aimed at the player shorten the selected melee
  estimate by 40% of its interval, with a 20% floor. An already shorter remainder
  is never extended. This applies with the AzerothCore timing option enabled.
  It uses the live client interval: the server's unmodified base interval under
  haste is not exposed here, so this remains approximate under haste and custom
  server rules. It never adjusts ranged or fabricates an unobserved deadline.
- Raptor Strike, Heroic Strike, Cleave and Maul synchronize main hand from actual
  damage/miss events. Localized base-spell names recognize other ranks. Queuing
  remains harmless. Matching spell ID/event timestamp suppresses multiple target
  records for a single Cleave; extremely unusual same-timestamp identical attacks
  cannot be distinguished without a cast identity.
- Dual-wield estimation retains a known main hand for these abilities and models
  AzerothCore's 0.2-second other-hand staggering for already observed deadlines.
  Ordinary stock swing hand assignment still cannot be guaranteed.
- Auto Shot now pairs unit/log notifications from different sources within a
  bounded window (the smaller of one second and 75% of the weapon interval).
  A repeated same-source signal is not suppressed merely because it arrives
  quickly. Tests cover the former +0.30-second duplicate. Arbitrarily late,
  dropped, or same-source duplicated events still cannot be correlated perfectly.
- Temporary zero speed or a missing link with positive slot-texture evidence is
  tolerated for at most one second, with keyed 0.2-second retries. Recovery
  preserves synchronization; prolonged uncertainty or empty slots clear it.
  This is not proof that two indistinguishable item copies were not swapped.

Automated regression cases now assert these repairs, not the former broken
behaviors. In-game checks still required: resize with help hidden; parry with
single/dual weapons; each next-swing ability queued out of range and then landed
(including misses and multiple Cleave targets); haste/buff changes; swap/unequip;
and first Auto Shot after stopping. Generic spell-specific resets, exact wand
timing and deterministic hand identity remain outside verified coverage.

## Scope

- Main/off-hand and ranged damage are live character-sheet ranges, not predicted
  target damage or future random rolls. Forms use the client's active values.
- Timers are estimates synchronized from stock 3.3.5 events. Auto Shot uses
  localized player spell-success names (resolved with GetSpellInfo(75)), or
  combat-log cast-success ID 75, never projectile impact. Duplicate release
  notifications are coalesced. If neither release event is available, timing
  stays at 0.0s while waiting for an attack; do not substitute damage time.
- Single-weapon swings include misses. Dual-wield events do not reliably identify
  hands on stock 3.3.5. The first observed swing seeds main hand; subsequent
  swings use the earliest predicted hand deadline. This is explicitly labeled
  estimated and can misassign hands, particularly with equal-speed weapons.
- Wands display damage/interval only. Weapon/form changes invalidate estimates.
  Queuing an ability does not reset timers. Raptor Strike, Heroic Strike, Cleave
  and Maul reset main hand on actual combat-log damage/miss, not queued success.
  Other ability-specific timer effects are not modelled. Combat exit retains countdowns, which settle at 0.0s
  rather than restarting fictitious attacks. Extra attacks can reduce accuracy; this is not a
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
5. Equip two weapons: both damage ranges remain visible, with explicitly estimated
   hand countdowns after swings. Do not claim exact off-hand timing. Leave combat:
   remaining countdowns must continue and settle at 0.0s, not disappear.
   On a fresh login, unsynchronized counters stay at 0.0s until an attack occurs.
   A localized Attack notification after a swing must not clear its countdown.
   Armor changes, unchanged weapon notifications and display settings must retain
   running counters. Weapon swaps clear only the changed slot; haste updates
   rescale its remaining estimate using the live attack speed.
6. Check Druid Cat/Bear shifts, haste changes, weapon swaps and temporary buffs:
   values refresh and stale countdowns disappear. Check a caster wand shows stats
   without a fabricated countdown. Check the other melee classes normally.
   Repeated UPDATE_SHAPESHIFT_FORM notifications with an unchanged active form
   must preserve both deadlines, including a notification immediately after the
   first Auto Shot. Unknown form data must not fabricate a transformation.
7. Toggle every display option; change profile; disable while open. No reload,
   residual window, duplicate timer or Lua error should occur. Closing the window
   stops display work but keeps enabled event synchronization available.
8. Repeat with Questie tracking enabled. This tool never touches quest/map state.
9. Queue Raptor Strike outside melee range: existing counters must be unchanged.
   Move into range and let it strike: main-hand countdown starts even on a miss.

If a real first attack still leaves zero counters, call
the following after melee and Auto Shot tests:

```lua
/run for _,a in LibStub("AceAddon-3.0"):IterateAddons() do if a.attackTimer then a.attackTimer:PrintDiagnostics() end end
```

The public `RXPGuides` global is a separate guide-registration facade, not the
private addon namespace. Iterating AceAddon also supports renamed addon folders.
For a first-shot-only failure, collect output after the first Auto Shot and
again after the second; do not use other abilities between these captures.
For precise event ordering, start the bounded 20-second capture instead:

```lua
/run for _,a in LibStub("AceAddon-3.0"):IterateAddons() do if a.attackTimer then a.attackTimer:StartDiagnostics() end end
```

Fire Auto Shots without other abilities and wait for the automatic report.
The last 32 timing records show elapsed time, recognized shot signals, impacts
(which never reset timing), weapon/speed changes and explicit resets. Negative
remaining values in this diagnostic mean an existing deadline has expired;
`unset` means there is no deadline. Capture is transient, bounded and opt-in.
This prints session-only event counts and numeric intervals/remaining times,
never identities or combat text. Compare `combat`, `player`, `swings`, `shots`
and `draws` to distinguish missing event delivery from rendering failures.

Automated coverage: `tests/attack-timer.lua` runs production timing and event
handlers plus mocked window lifecycle through `tests/run.lua`. Gameplay checks
above remain unverified until performed on a stock 3.3.5 client.
