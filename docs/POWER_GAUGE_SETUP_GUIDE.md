# Power Gauge Phase - Setup Guide (Server-Authoritative)

## A. Goal
Implement ONLY the server-authoritative Puncher power gauge. No damage application, guessing, knockout, scoring, final animations, or final GUI.

The gauge:
- Zones: Weak, Normal, Strong, Perfect (+ optional Miss as the TIMEOUT/late zone only, not on the track)
- Needle moves continuously and predictably 0 -> 1, REVERSING at the ends (ping-pong), position = power level
- Puncher sends an input request to LOCK the gauge (matchId ONLY)
- Client may display the gauge but must NOT send the final power value
- Server starts gauge with a server-controlled timestamp (`workspace:GetServerTimeNow()`), uses shared config timing, accepts only ONE lock, rejects duplicate/early/late/invalid requests, calculates the zone from the SERVER clock (a client can never claim Perfect), stores the result for the future damage system, handles timeout (-> Miss) and disconnect.

## B. Files (exact paths)
### Changed
1. `src/Shared/Config.luau` - new POWER GAUGE section (all timing tunable):
   - `PowerGaugeEnabled = true`
   - `PowerGaugeDuration = 5` (total server-controlled lock window, seconds)
   - `PowerGaugeSweepDuration = 1.25` (one pass 0->1; needle reverses at ends)
   - `PowerGaugeZoneThresholds = { Weak = 0, Normal = 0.40, Strong = 0.70, Perfect = 0.90 }` (position lower bounds)
   - `PowerGaugeLockLateGrace = 0.15` (locks this many seconds after window end still count - latency tolerance)
   - `PowerGaugeLockCooldown = 0.25`, `PowerGaugeMaxLockRequests = 5` (anti-spam)
   - `PowerGaugeShowDebugDisplay = true`, `PowerGaugeLockKey = Enum.KeyCode.E`
   - `GuessingDuration`, `KnockoutDuration`, `StartingHealth`, `Damage` remain as FUTURE values
2. `src/Shared/PowerZones.luau` - added shared gauge math used by BOTH server and client:
   - `PowerZones.GetNeedlePosition(elapsed, sweepDuration)` - ping-pong position in [0,1]
   - `PowerZones.GetZoneForPosition(position, thresholds)` - zone from position band
3. `src/Shared/MatchStates.luau` - added real state `PowerGauge`, transitions `Punching -> PowerGauge`, `PowerGauge -> WaitingForPuncher/Guessing(future)/Eliminated/Finished`, added `PowerGauge` to `HiddenPuncherStates`
4. `src/Shared/RemoteNames.luau` - gauge remotes now implemented: `PowerGaugeOpen`, `PowerGaugeStopRequest`, `PowerGaugeRejected` (NEW), `PowerGaugeResult`; documented client sends ONLY lock request
5. `src/Server/Services/MatchService.luau` (1314 lines) - gauge implementation:
   - `matchData.powerGauge` = {startServerTime, endServerTime, sweepDuration, locked, resolved, cancelled, lockRequestCount, lastLockRequestTick}
   - `matchData.powerGaugeResult` = {zone, position, lockedTick, serverTime, timedOut, puncherUserId} - STORED for damage system, SERVER-INTERNAL, never broadcast to Target/others
   - `startPowerGauge(matchData)`: server timestamp, state = PowerGauge, fires RE_PowerGaugeOpen to PUNCHER ONLY, starts timeout loop (end + grace -> Miss)
   - `validateGaugeLockRequest`: 9 checks - identity, match identity, is THE Puncher, state = PowerGauge, gauge active, duplicate (locked), cooldown 0.25s + max 5 requests, alive, timing early/late vs SERVER clock
   - `MatchService.TryLockPowerGauge`: accepts ONE lock, computes position via shared ping-pong math with SERVER clock, zone from Config thresholds, stores result, fires RE_PowerGaugeResult to Puncher only; IGNORES any client extra args (power/zone claims)
   - `cancelPowerGauge`: called on Puncher disconnect, Target left (puncher cleared), EndMatch
   - Hook: preparation countdown end in `selectPuncher` now calls `startPowerGauge`
   - `HandlePlayerLeaving`: Puncher disconnect during PowerGauge -> cancel gauge, discard result, revert to WaitingForPuncher (new selection)
   - Filtered payload guarantee: NO gauge timing/position/zone ever in RE_MatchStateUpdate
6. `src/Client/Main.client.luau` - loads PowerGaugeService, wires `UpdateState` + `HandleMatchEnd`
### New
7. `src/Client/Services/PowerGaugeService.luau` (354 lines) - client display + lock input ONLY:
   - Receives RE_PowerGaugeOpen (Puncher only) with server timestamp
   - RenderStepped needle using `PowerZones.GetNeedlePosition(workspace:GetServerTimeNow() - startServerTime, sweep)` - identical math to server
   - Minimal debug display created in code (ScreenGui "PowerGaugeDebugGui": track, zone bands from Config, needle, status) - final GUI comes later
   - Press E (`Config.PowerGaugeLockKey`) -> `RE_PowerGaugeStopRequest:FireServer(matchId)` ONLY - no power/zone/timestamp
   - Shows server result zone, rejection reasons; cleans up on state change/match end
### flat/ sync (Claude MCP)
`flat/Shared_Config.luau`, `flat/Shared_PowerZones.luau` (NEW), `flat/Shared_MatchStates.luau`, `flat/Shared_RemoteNames.luau`, `flat/Server_MatchService.luau`, `flat/Client_Main.client.luau`, `flat/Client_PowerGaugeService.luau` (NEW)
### Docs
`docs/POWER_GAUGE_SETUP_GUIDE.md` (this file), `docs/CommandBar_PowerGauge.txt`

## C. Setup (manual objects)
- NO new physical objects required (no Parts/Folders in Workspace for this phase).
- The 4 RemoteEvents are AUTO-CREATED by MatchService.Init via RemoteService.EnsureAllRemotes. To pre-create manually in `ReplicatedStorage > Remotes` (RemoteEvent each): `RE_PowerGaugeOpen`, `RE_PowerGaugeStopRequest`, `RE_PowerGaugeRejected`, `RE_PowerGaugeResult`.
- Everything from previous phases must still exist (Lobby, MatchSlots, MatchArenas with TargetStand+Chair, PuncherStand, PlayerSpawns).

## D. Hierarchy (Studio explorer after setup)
```
ReplicatedStorage
├── Shared (Folder)
│   ├── Config (ModuleScript)            [updated]
│   ├── PowerZones (ModuleScript)        [updated - SHARED gauge math]
│   ├── MatchStates (ModuleScript)       [updated]
│   ├── RemoteNames (ModuleScript)       [updated]
│   └── ... (Constants, QueueStates, Roles, Types unchanged)
└── Remotes (Folder)
    ├── RE_PowerGaugeOpen (RemoteEvent)      [Server -> Puncher ONLY]
    ├── RE_PowerGaugeStopRequest (RemoteEvent) [Client -> Server LOCK, matchId only]
    ├── RE_PowerGaugeRejected (RemoteEvent)  [Server -> Client, reason]
    └── RE_PowerGaugeResult (RemoteEvent)    [Server -> Puncher ONLY]
ServerScriptService
└── Services (Folder)
    └── MatchService (ModuleScript)      [updated]
StarterPlayer
└── StarterPlayerScripts
    └── GuessThePuncherClient (LocalScript) [updated]
        └── Services (Folder)
            ├── TargetCameraService (ModuleScript)   [unchanged]
            ├── TargetVisibilityService (ModuleScript) [unchanged]
            ├── PuncherSelectionService (ModuleScript) [unchanged]
            └── PowerGaugeService (ModuleScript)      [NEW]
PlayerGui (runtime, client-created)
└── PowerGaugeDebugGui (ScreenGui) - Track Frame with BandNormal/BandStrong/BandPerfect + Needle + Status + ZoneResult
```

## E. Properties
- New RemoteEvents: class RemoteEvent, Name exactly as listed, Parent `ReplicatedStorage.Remotes`. No other properties.
- PowerGaugeService ModuleScript: Name exactly `PowerGaugeService`, Parent `GuessThePuncherClient > Services`.
- Debug GUI is created by CODE at runtime (ScreenGui ResetOnSpawn=false, DisplayOrder=50). Do NOT create it manually.
- No Workspace objects, no Attributes, no CFrame changes in this phase.

## F. Copy instructions
1. Copy `src/Shared/Config.luau` -> `ReplicatedStorage > Shared > Config` (no .luau extension in Studio)
2. Copy `src/Shared/PowerZones.luau` -> `ReplicatedStorage > Shared > PowerZones`
3. Copy `src/Shared/MatchStates.luau` -> `ReplicatedStorage > Shared > MatchStates`
4. Copy `src/Shared/RemoteNames.luau` -> `ReplicatedStorage > Shared > RemoteNames`
5. Copy `src/Server/Services/MatchService.luau` -> `ServerScriptService > Services > MatchService`
6. Copy `src/Client/Main.client.luau` -> `StarterPlayer > StarterPlayerScripts > GuessThePuncherClient` (LocalScript)
7. Create ModuleScript `PowerGaugeService` in `GuessThePuncherClient > Services`, paste `src/Client/Services/PowerGaugeService.luau`
8. For Claude MCP use flat/ files with same names (Shared_PowerZones.luau -> PowerZones etc.)
9. Or run `docs/CommandBar_PowerGauge.txt` in the Command Bar to create the ModuleScript shell + remotes, then paste code

## G. Timing tests (multiplayer: Test > Clients and Servers > 2+ players)
1. **Full flow**: All clients join Slot2 (or walk onto EntryArea). Wait: Preparing -> SelectingTarget -> WaitingForPuncher -> press F as PotentialPuncher -> Puncher selected, prep 3s countdown -> state PowerGauge, puncher's screen shows gauge, needle moves 0->1->0 (reversing at ends).
2. **Lock in zone**: Watch needle; press E while in a band. Server output: `Gauge LOCKED ... zone=... position=... (server-calculated)`. Puncher output: `RESULT: zone=...`. Result shown ~2.5s. Zone should match the band the needle was in (small latency shift is expected).
3. **Only one lock accepted**: Press E twice quickly. Second press: client prints `Already locked - ignoring input`; if forced via command bar `game.ReplicatedStorage.Remotes.RE_PowerGaugeStopRequest:FireServer(matchId)` again -> server rejects `Gauge already locked` via RE_PowerGaugeRejected.
4. **Duplicate from another player**: Non-puncher fires `RE_PowerGaugeStopRequest:FireServer(matchId)` in command bar -> rejected `Not the Puncher`.
5. **Early request**: While still in Punching prep (before gauge opens), fire `RE_PowerGaugeStopRequest:FireServer(matchId)` -> rejected `Wrong state: Punching, must be PowerGauge`.
6. **Late/timeout**: Do NOT press E for the whole window (default 5s) -> server: `Power gauge TIMEOUT ... -> Miss`, puncher sees `TIMEOUT - Miss`. Then firing a lock -> `No active gauge`/`Gauge already resolved`/`Too late`.
7. **Rate limit/spam**: Fire StopRequest 7 times in a loop via command bar during gauge -> after 5 requests: `Rate limited` / `Too many lock requests`.
8. **Cannot claim Perfect**: During gauge, fire `RE_PowerGaugeStopRequest:FireServer(matchId, "Perfect", 1, 99999)` (extra args claiming zone/power/time). Server IGNORES them; zone = server-calculated from real needle position (e.g. `zone=Weak` when needle low). NEVER matches the claim unless genuinely in band.
9. **Disconnect**: Puncher leaves during PowerGauge -> server: `Power gauge CANCELLED`, state back to WaitingForPuncher, remaining players can press F again; no gauge result stored.
10. **Target filtering**: As Target, verify output has NO `[PowerGauge]` lines (no gauge open/result events), and `[Security]` warnings never fire.
11. **Tuning test**: Set `Config.PowerGaugeDuration = 10`, `PowerGaugeSweepDuration = 2` -> slower needle, easier locks. Set `Perfect = 0.99` -> Perfect nearly impossible.

## H. Expected results
- Gauge starts ONLY after Puncher preparation (3s) with a SERVER timestamp; only the Puncher receives timing.
- Needle ping-pongs 0->1->0 predictably; client display uses the same shared math + server clock as the server calculation.
- Exactly one lock accepted; zone computed by SERVER from its clock; result stored in `matchData.powerGaugeResult` for the future damage system (no damage applied in this phase).
- Timeout/late -> Miss stored. Duplicate/early/late/wrong role/wrong state/rate-limited requests rejected with reasons via RE_PowerGaugeRejected.
- Client never sends power/zone/timestamp; sending fake claims has zero effect.
- Puncher disconnect or Target change during gauge cancels it and reverts safely to WaitingForPuncher. EndMatch cleans everything.
- Target and non-punchers never receive gauge timing, position, or zone. State stays PowerGauge after lock (no guessing/damage transition yet).

## I. Common errors and fixes
- `RE_PowerGaugeOpen not found - gauge display disabled`: Remotes folder missing or server script not run. Ensure MatchService runs (ServerScriptService > Services > MatchService) and RemoteService auto-creates remotes; or create the 4 RemoteEvents manually.
- Gauge never starts: Check you pressed F as PotentialPuncher (puncher must exist first), waited the 3s prep, and state printed `PowerGauge STARTED` in SERVER output.
- Needle not visible: Debug display only for the PUNCHER. Check `Config.PowerGaugeShowDebugDisplay = true` and that you are the Puncher; check PlayerGui for PowerGaugeDebugGui.
- Lock does nothing: E is `Config.PowerGaugeLockKey`; gauge must be open (you got `[PowerGauge] Gauge OPEN`); only the Puncher can lock.
- Zone always Miss: You did not lock in time (`PowerGaugeDuration` 5s total). Increase it or `PowerGaugeSweepDuration` while testing.
- Zone seems off by a bit: Network latency shifts server-side position (expected, server is authoritative). Increase `PowerGaugeSweepDuration` / `Perfect` threshold gap or `PowerGaugeLockLateGrace` if needed.
- `attempt to index nil with 'powerGauge'` type errors: You mixed old/new MatchService copies. Replace the WHOLE MatchService (1314 lines) and restart Studio play.
- `PowerZones` missing: Client PowerGaugeService requires `ReplicatedStorage > Shared > PowerZones` - it must exist (create ModuleScript named PowerZones).
- Second Puncher after disconnect keeps gauge: Should not happen; verify HandlePlayerLeaving prints `Power gauge CANCELLED - Puncher disconnected`.
- State stuck at PowerGauge after lock: EXPECTED in this phase (holds for future damage system). It only leaves via Puncher disconnect/Target change/match end.

## J. Not implemented (future phases - do not test for these)
- Damage application (StartingHealth, Damage table untouched, no RE_DamageApplied)
- Punch animations, hit detection, final animations
- Guessing phase (GuessingDuration unused, no RE_GuessOpen/Request/Result)
- Knockout, elimination flow, scoring, winner reveal
- Official Puncher reveal to Target
- Final GUI (current on-screen gauge is a minimal debug display created in code)
- Monetization, DataStores
