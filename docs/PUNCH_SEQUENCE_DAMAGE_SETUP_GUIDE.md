# Punch Sequence + Target Health/Damage - Setup Guide

Combined guide for TWO phases implemented together (damage consumes the punch result):
- PART 1: Visual punch sequence (placeholder animations, cartoon impact, placeholder sound, Target camera shake, per-zone presentation, repeat prevention, effect cleanup)
- PART 2: Target health and damage system (server-side match health, damage after valid punch only, duplicate prevention, clamp, zero detection -> mark knocked out + PAUSE)

## A. Goal

### PART 1 - Visual punch sequence (ONLY)
When the Puncher locks the power (server-accepted lock):
- Play preparation animation PLACEHOLDER then punch animation PLACEHOLDER (Config IDs are `rbxassetid://0`, clearly marked - NO real asset IDs invented; replace only when user provides IDs)
- Show clear CARTOON-style impact effect (code-created: expanding neon sphere + force-field ring, particle burst, comic "POW!/BAM!/BOOM!/PERFECT!/MISS" billboard with damage number, light flash) - no asset IDs needed
- Play PLACEHOLDER sound ONLY because no real asset ID provided (`Config.PunchSoundId = "rbxassetid://0"`, pitch/volume differ per zone; prints placeholder note in Output)
- Small camera shake effect for the TARGET (magnitude by zone from `Config.PunchCameraShakeByZone`; binds AFTER camera priority so it stacks with the Target first-person camera)
- DIFFERENT presentation per zone: Miss (grey text, no impact/shake), Weak (POW! yellow, small), Normal (BAM! orange, medium), Strong (BOOM! red-orange, big), Perfect (PERFECT!! gold, biggest + white screen flash + TARGET DOWN! banner)
- Prevent repeated triggering: server `sequenceFired` guard (one sequence per result) + client `playing` guard + duplicate-event rejection
- Clean effects if match ends, state reverts (Puncher disconnect), or local character respawns (client-destroyed folder `workspace.PunchSequenceEffects` + camera shake unbind + Debris on all effect instances)
- SERVER-selected power result (`matchData.powerGaugeResult.zone`) determines the presentation. Visuals NEVER determine the game result. The client sends NOTHING in this phase.

### PART 2 - Target health and damage (ONLY)
- Weak = 10, Normal = 25, Strong = 50, Perfect = 100 + immediate knockout marking, Miss = 0 (uses existing shared `Config.Damage` + `Config.StartingHealth` + `Config.PerfectIsInstantKO`)
- Server stores MATCH health (`matchData.targetHealth`) - SEPARATE from Roblox Humanoid health (`Humanoid.Health` NEVER modified)
- Damage applied ONLY after a valid punch result (locked gauge -> stored server zone), at SERVER contact time
- NEVER accepts client-provided damage (no remote accepts damage values; extra args on lock request are ignored)
- Prevents duplicate damage (`damageApplied` flag)
- Clamps health at zero (`math.max(0, ...)`)
- Detects zero health -> `targetKnockedOut = true`, state = `KnockedOut`, PAUSED (full elimination flow deliberately NOT implemented)
- Handles reset (new match = fresh matchData = full health; new Target mid-match = health reset broadcast) and disconnect (match end / Puncher / Target leaves -> pending sequence cancelled, effects cleaned)
- No guessing, role transfer, complete knockout flow, scoring, monetization, DataStores.

## B. Files (exact paths)
### Changed
1. `src/Shared/Config.luau` - new PUNCH SEQUENCE PRESENTATION section:
   - `PunchSequenceEnabled = true`, `PunchSequencePrepTime = 0.6`, `PunchSequenceContactTime = 0.35` (SERVER-scheduled timings)
   - PLACEHOLDER assets clearly marked: `PunchAnimPrepId = "rbxassetid://0"`, `PunchAnimPunchId = "rbxassetid://0"`, `PunchSoundId = "rbxassetid://0"`
   - `PunchCameraShakeByZone = { Miss = 0, Weak = 0.15, Normal = 0.3, Strong = 0.55, Perfect = 0.9 }`
   - Damage values USE the existing `Config.Damage` (Miss 0 / Weak 10 / Normal 25 / Strong 50 / Perfect 100), `Config.StartingHealth = 100`, `Config.PerfectIsInstantKO = true`
2. `src/Shared/MatchStates.luau` - new state `KnockedOut` (mark + PAUSE only), List, Transitions (`PowerGauge -> KnockedOut`; `KnockedOut -> Finished/new Target only`), added to `HiddenPuncherStates`
3. `src/Shared/RemoteNames.luau` - added `PunchSequence = "RE_PunchSequence"` (Server -> ALL match clients at punch moment = official reveal) and `TargetHealthUpdate = "RE_TargetHealthUpdate"` (Server -> ALL match clients)
4. `src/Server/Services/MatchService.luau` (1459 lines) - PUNCH RESULT RESOLUTION section:
   - New matchData fields: `targetHealth = Config.StartingHealth` (fresh per match = reset for new matches), `targetKnockedOut`, `damageApplied`, `sequenceFired`, `sequenceCancelled`
   - `broadcastPunchSequence` (matchId, zone, puncherUserId, targetUserId, timedOut) to all match clients
   - `broadcastTargetHealth` (matchId, targetUserId, health, maxHealth, lastDamage, lastZone) to all match clients
   - `applyPunchDamage`: valid-result only, server damage from `Config.Damage[zone]`, duplicate guard, clamp at 0, zero detection -> `targetKnockedOut` + state `KnockedOut` + PAUSE
   - `schedulePunchSequence`: SERVER-scheduled prep (0.6s) -> fire sequence -> contact (0.35s) -> damage; `sequenceFired` prevents repeats; `sequenceCancelled` on match end/disconnect stops pending sequence/damage
   - Triggered from `TryLockPowerGauge` (locked zones) and gauge TIMEOUT (Miss presentation, 0 damage, no contact)
   - `EndMatch`: `sequenceCancelled = true`; `HandlePlayerLeaving`: Puncher disconnect cancels pending sequence; new Target mid-match resets health/knockout/damage/sequence + broadcasts reset
5. `src/Client/Main.client.luau` - loads PunchSequenceService, wires `UpdateState` + `HandleMatchEnd`
### New
6. `src/Client/Services/PunchSequenceService.luau` (564 lines) - presentation ONLY, sends NOTHING:
   - `ZONE_PRESENTATION` table (text/color/impact/particles/sound pitch-volume/flash per zone)
   - Placeholder animations via `Animation` (PLACEHOLDER `rbxassetid://0`, pcall, printed notes); visible code-created cues so testing works without real assets
   - Cartoon impact: neon expanding sphere + ForceField ring + ParticleEmitter burst + PointLight flash + comic billboard (tilted GothamBlack text with damage number)
   - Placeholder sound: `Config.PunchSoundId` (marked PLACEHOLDER) with per-zone PlaybackSpeed/Volume
   - Target camera shake via `RunService:BindToRenderStep` at `Camera.Value + 2` (works with Target first-person camera)
   - Perfect: white screen flash; KO: "TARGET DOWN!" banner
   - Guards: `playing` flag (repeat prevention), state-change cleanup, `HandleMatchEnd`, `CharacterAdded` cleanup, Debris on every effect, safety timeout
### flat/ sync (Claude MCP)
`flat/Shared_Config.luau`, `flat/Shared_MatchStates.luau`, `flat/Shared_RemoteNames.luau`, `flat/Server_MatchService.luau`, `flat/Client_Main.client.luau`, `flat/Client_PunchSequenceService.luau` (NEW)
### Docs
`docs/PUNCH_SEQUENCE_DAMAGE_SETUP_GUIDE.md` (this file), `docs/CommandBar_PunchSequenceDamage.txt`

## C. Setup (manual objects)
- NO new Workspace objects.
- 2 new RemoteEvents AUTO-CREATED by `MatchService.Init` via `RemoteService.EnsureAllRemotes`. To pre-create manually in `ReplicatedStorage > Remotes` (RemoteEvent each): `RE_PunchSequence`, `RE_TargetHealthUpdate`.
- All previous-phase objects/remotes must still exist.
- OPTIONAL test tuning before starting: `Config.PowerGaugeDuration = 10`, `Config.PowerGaugeSweepDuration = 2`, thresholds unchanged - makes locking specific zones much easier for damage tests.

## D. Hierarchy (Studio explorer after setup)
```
ReplicatedStorage
└── Remotes (Folder)
    ├── RE_PunchSequence (RemoteEvent)     [NEW: Server -> ALL match clients at punch moment]
    └── RE_TargetHealthUpdate (RemoteEvent) [NEW: Server -> ALL match clients]
ServerScriptService > Services > MatchService (ModuleScript) [updated 1459 lines]
ReplicatedStorage > Shared: Config / MatchStates / RemoteNames (updated)
StarterPlayer > StarterPlayerScripts > GuessThePuncherClient (LocalScript) [updated]
    └── Services (Folder)
        └── PunchSequenceService (ModuleScript) [NEW]
workspace (runtime, client-created)
└── PunchSequenceEffects (Folder) - all local effect instances, destroyed on cleanup
PlayerGui (runtime, client-created)
└── PunchSequenceFlash / PunchSequenceKO (ScreenGuis, Perfect flash / KO banner)
```

## E. Properties
- New RemoteEvents: class RemoteEvent, exact names, Parent `ReplicatedStorage.Remotes`. No other properties.
- `PunchSequenceService` ModuleScript: Name exactly `PunchSequenceService`, Parent `GuessThePuncherClient > Services`.
- Effect parts created by code: Anchored true, CanCollide/CanQuery/CanTouch false, Neon/ForceField materials - do NOT create manually.
- No Attributes, no CFrames to set, no SpawnLocations in this phase.

## F. Copy instructions
1. `src/Shared/Config.luau` -> `ReplicatedStorage > Shared > Config`
2. `src/Shared/MatchStates.luau` -> `ReplicatedStorage > Shared > MatchStates`
3. `src/Shared/RemoteNames.luau` -> `ReplicatedStorage > Shared > RemoteNames`
4. `src/Server/Services/MatchService.luau` -> `ServerScriptService > Services > MatchService` (REPLACE WHOLE script)
5. `src/Client/Main.client.luau` -> `StarterPlayer > StarterPlayerScripts > GuessThePuncherClient`
6. NEW ModuleScript `PunchSequenceService` in `GuessThePuncherClient > Services`, paste `src/Client/Services/PunchSequenceService.luau`
7. Claude MCP: use flat/ files (flat/Client_PunchSequenceService.luau -> PunchSequenceService etc.)
8. Or run `docs/CommandBar_PunchSequenceDamage.txt` first to create the ModuleScript shell + remotes

## G. Tests (multiplayer: Test > Clients and Servers > 2+ players)
Tip: set `Config.PowerGaugeDuration = 10` / `PowerGaugeSweepDuration = 2` while testing to hit zones easily.
### Punch sequence tests (PART 1)
1. **Full sequence**: Play, join Slot2, press F as PotentialPuncher, prep 3s, lock with E. Expect: puncher "..." prep billboard (~0.6s), then cartoon impact at Target, "POW!/BAM!/BOOM!" billboard, particles, placeholder sound note in Output, Target camera shake. Server: `Punch sequence FIRED ... zone=...` then `DAMAGE ...`.
2. **Per-zone presentation**: Repeat matches (or tune thresholds): Weak -> small yellow POW! + shake 0.15; Normal -> medium orange BAM!; Strong -> big red BOOM!; Perfect -> gold PERFECT!!, white flash (Target), TARGET DOWN! banner. Each looks clearly different.
3. **Miss presentation**: Do NOT press E -> after 5s: grey "MISS" billboard near puncher, NO impact burst, NO shake, server `0 damage, no contact`, health unchanged.
4. **Repeat prevention**: Lock, then immediately spam E and fire `RE_PowerGaugeStopRequest:FireServer(matchId)` via command bar -> server `Gauge already locked` + `Punch sequence already fired - repeat prevented` (only ONE sequence/impact ever plays).
5. **Cleanup on match end**: During sequence, end match (e.g. a 3rd player in a Slot4 match leaves making <2) -> `workspace.PunchSequenceEffects` folder disappears on all clients, no leftover particles/billboards, shake unbound.
6. **Cleanup on disconnect**: Puncher leaves during the 0.95s sequence window -> server `Punch sequence cancelled before contact`, clients clean effects, no damage applied.
### Damage tests (PART 2)
7. **Weak 10**: Lock in Weak band -> server `[MatchService] DAMAGE ... takes 10 (Weak) -> health 90/100`; all clients `[Health] ... health=90/100 (last: -10 Weak)`.
8. **Normal 25 / Strong 50**: New matches -> health 100->75 / 100->50 respectively per zone locked.
9. **Perfect 100 + KO mark**: Lock in Perfect band -> `takes 100 (Perfect) -> health 0/100`, `TARGET KNOCKED OUT ... PAUSED, marked only`, state `KnockedOut` broadcast, banner shows. Match stays paused (no elimination flow).
10. **Miss 0**: Timeout -> `health=100/100 (last: -0 Miss)`, `damageApplied` consumed.
11. **Duplicate damage prevention**: After any punch, re-fire `RE_PowerGaugeStopRequest:FireServer(matchId)` -> `Gauge already locked`; verify health never drops twice (only one `DAMAGE` line per match round).
12. **Never accepts client damage**: Fire `RE_PowerGaugeStopRequest:FireServer(matchId, 99999, "Perfect", 999)` post-lock -> extra args IGNORED, no health change. No other remote accepts damage (verify no remote exists that does).
13. **Humanoid health untouched**: As Target, select your character in Explorer during/after damage -> `Humanoid.Health` stays 100 (match health is separate). Your character does NOT die on Perfect.
14. **Reset for new match**: After a KO'd match ends, queue again -> new match health starts at 100 (fresh matchData). New Target mid-match (Target leaves with 3+ players): `[Health] ... health=100/100 (last: -0 Reset)`.
15. **Clamp at zero**: Config `StartingHealth = 30` test -> Perfect still clamps to 0, never negative.

## H. Expected results
- Exactly ONE punch sequence per accepted lock; preparation placeholder -> punch placeholder -> cartoon impact (zone-styled) -> placeholder sound note -> Target shake. Timed-out Miss = grey MISS text only, no damage.
- Server fires the zone; clients only present it. Client sends nothing during the sequence.
- Damage: Weak 10 / Normal 25 / Strong 50 / Perfect 100+KO mark / Miss 0 - applied once, at server contact time, to MATCH health only (Humanoid untouched), clamped at 0.
- Health 0 -> `targetKnockedOut = true`, state `KnockedOut`, match PAUSES (no elimination/role transfer). Leaves KnockedOut only via match end or new Target selection.
- New matches / new Targets start at full health. Disconnects and match ends cancel pending sequences and clean all effects on every client.
- Target and everyone receive health updates (public info); state payloads still NEVER contain puncherUserId; `RE_PunchSequence` carries puncher identity ONLY at the punch moment (official reveal by the punch itself).

## I. Common errors and fixes
- No impact effect visible: You locked but watched the wrong client - effects spawn for ALL match clients at the Target; check `workspace.PunchSequenceEffects` exists during sequence; ensure `Config.PunchSequenceEnabled = true`.
- No animations/sound playing: EXPECTED with placeholders (`rbxassetid://0`, clearly marked). Output shows `[PunchSequence] Animation placeholder ...` / `Sound placeholder ...`. Replace Config IDs ONLY with real asset IDs the user provides.
- No damage in Output: Sequence cancelled (match ended/disconnect), or zone was Miss (0 damage by design), or gauge result missing - check server for `Punch sequence cancelled before contact` / `No valid punch result`.
- Double damage: Should be impossible (`damageApplied` guard). If seen, you mixed old/new MatchService - REPLACE the whole 1459-line file and restart Play.
- Target character dies on Perfect: Should NOT happen (Humanoid never touched). If it does, an old script (or Studio test) is setting Humanoid.Health - verify only MatchService damage path exists and it uses `matchData.targetHealth`.
- Camera shake never ends: `stopCameraShake` unbinds; if it persists, another script bound the same name - re-copy PunchSequenceService (564 lines).
- Shake fights the Target camera: Shake binds at `Camera.Value + 2` (after camera scripts). If the Target first-person camera overrides it, re-copy the service; both can coexist by design.
- `KnockedOut` state never reached: Health must hit EXACTLY 0 (Perfect = 100 = full health). With lower StartingHealth any Strong/Perfect can do it; check `DAMAGE` line shows health 0.
- `RE_PunchSequence not found`: Ensure updated MatchService ran (auto-creates) or create the RemoteEvent manually in ReplicatedStorage.Remotes.
- Effects remain after match end: Re-copy PunchSequenceService and Main.client (cleanup wiring), confirm `[PunchSequence] Effects cleaned: match ended` prints on MatchEnd.
- State stuck at KnockedOut: EXPECTED - paused by design until future phases (match end or Target leave with 3+ players also exits).

## J. Not implemented (future phases - do not test for these)
- Complete knockout/elimination flow (role transfer, round restart, elimination handling) - KnockedOut only MARKS + PAUSES
- Guessing phase, official reveal flow, scoring, winner determination
- Real punch animations/sounds (placeholders clearly marked; awaiting real asset IDs from user)
- Damage to Humanoid/character death, hitboxes, punches reacting to distance/blocking
- Health GUI bars (health shown via Output prints only), monetization, DataStores
