# Spectator Mode + Security Audit - Setup Guide

Combined guide: PART 1 = spectator mode; PART 2 = complete security audit (all fixes applied, no new gameplay features).

## A. Goal

### PART 1 - Spectator mode (ONLY)
- Eliminated players watch active players WITHOUT affecting the match.
- Prevents spectators from entering the active arena: server-enforced LEASH loop (every `SpectatorEnforceInterval` 0.5s) teleports any eliminated player further than `SpectatorLeashDistance` (18 studs) from the SpectatorArea center back to the area.
- Prevents Punch / Guess / Target / queue actions: spectators are removed from the active set server-side (all action validations fail), blocked from queue via `IsPlayerInMatch` (cleared only at match end), and server broadcasts never grant them actions.
- Controlled spectator camera: code-created follow camera (behind/above the watched player, smooth Lerp), separate `SpectatorService`.
- Switching between eligible active players: Q / E keys + Prev/Next buttons in a code-created "SPECTATOR MODE" panel; watch list = server-sent active userIds (RE_SpectatorUpdate, refreshed when the active set changes); unwatchable players (left/dead) are skipped automatically.
- Puncher identity HIDDEN until official reveal: spectator payloads are masked exactly like the Target's (no `puncherUserId`, Puncher role masked to PotentialPuncher); `RE_PuncherSelected` and `RE_PuncherPreparation` are no longer sent to spectators; `RE_SpectatorUpdate` contains only userIds. The official reveal (`RE_GuessResult`) reaches everyone including spectators.
- Returns spectators to the lobby when the match ends (existing EndMatch teleport includes spectators - they are in playerInstances).
- Restores camera and controls after returning to the lobby (`SpectatorService.HandleMatchEnd` → CameraType Custom + subject back to own Humanoid + GUI destroyed; Main.restoreAll also runs on RE_MatchEnd).
- Handles match ending while spectating (same path; also safe if the spectator respawns - follow camera re-applies, server leash keeps them on the platform).
- Kept SEPARATE from active-player functionality: new dedicated client service; server additions are spectator-only branches; spectators receive a dedicated remote (`RE_SpectatorUpdate`).
- Does NOT implement: rewards, monetization, freecam polish, spectator chat, final GUI.

### PART 2 - Security audit (no new gameplay features)
Audited: queue membership, match membership, target selection, puncher selection, first-click priority, power result, damage, health, guess correctness, role assignment, knockout, winner selection, rewards (none exist), spectator permissions; all RemoteEvents for identity/match/role/state/parameter validation, rate limiting, duplicate protection, timeout handling, disconnect handling, stale-event protection; race conditions, old match IDs, invalid actions, client timestamps/damage/power claims. All found issues FIXED (see H).

## B. Files (exact paths)
### Changed
1. `src/Shared/Config.luau` - `SpectatorLeashDistance = 18`, `SpectatorEnforceInterval = 0.5`, `QueueActionCooldown = 0.5` (audit fix)
2. `src/Shared/RemoteNames.luau` - added `SpectatorUpdate = "RE_SpectatorUpdate"` (Server -> SPECTATOR ONLY, watch list, no puncher info)
3. `src/Server/Services/MatchService.luau` (2163 lines):
   - AUDIT FIX V1: `buildFilteredPayload` now masks Puncher identity from SPECTATORS (eliminated recipients) exactly like the Target (role masked to PotentialPuncher, no puncherUserId, no prep time) - previously spectators received the puncher identity in every state update
   - AUDIT FIX V2: `broadcastPuncherSelected` / `broadcastPuncherPreparation` no longer sent to eliminated players
   - AUDIT FIX V3: `broadcastRoleAssigned` falls back to `Players:GetPlayerByUserId` (eliminated players are removed from matchData.players, so the Spectator role assignment previously NEVER reached the eliminated client -> stuck Target camera)
   - AUDIT FIX V4: `RE_GuessRequest` rate limiting added (0.3s cooldown per player + max 12 requests per guess phase) - previously unlimited spam
   - SPECTATOR: `broadcastSpectatorUpdate` (watch lists to spectators only), `startSpectatorLeashLoop` (server-authoritative arena-exclusion), both wired into `eliminateTarget` + `HandlePlayerLeaving`
   - Init: ensures + registers `RE_SpectatorUpdate`
4. `src/Server/Services/QueueService.luau` - AUDIT FIX V5: join/leave rate limiting (`QueueActionCooldown` 0.5s per player; disconnect cleanup bypasses the limit via the Parent==nil check)
5. `src/Server/Main.server.luau` - AUDIT FIX V6: stale auto-created remote list synced with ALL current remotes (was missing RE_PunchRejected, RE_PuncherPreparation, RE_PowerGaugeRejected, RE_PunchSequence, RE_TargetHealthUpdate, RE_GuessRejected, RE_PlayerEliminated, RE_MatchResult, RE_SpectatorUpdate)
6. `src/Client/Main.client.luau` - AUDIT FIX V7: self-elimination handler on `RE_PlayerEliminated` restores Target camera/visibility immediately and sets role Spectator (previously the eliminated Target kept the restricted first-person camera); loads + wires SpectatorService
### New
7. `src/Client/Services/SpectatorService.luau` (327 lines) - separate spectator-only client service: activation on own elimination, follow camera (RenderStep Camera+1), Q/E + button switching, code-created GUI ("SPECTATOR MODE", "Spectating <name> (i/n)", Prev/Next), watch list from RE_SpectatorUpdate, match-end restore, respawn-safe. Sends NOTHING to the server.
### flat/ sync (Claude MCP)
`flat/Shared_Config.luau`, `flat/Shared_RemoteNames.luau`, `flat/Server_MatchService.luau`, `flat/Server_QueueService.luau`, `flat/Server_Main.server.luau`, `flat/Client_Main.client.luau`, `flat/Client_SpectatorService.luau` (NEW)
### Docs
`docs/SPECTATOR_SECURITY_GUIDE.md` (this file), `docs/CommandBar_SpectatorSecurity.txt`

## C. Setup (manual objects)
- REMOTES: auto-created. Manual pre-create (RemoteEvent in ReplicatedStorage.Remotes): `RE_SpectatorUpdate`.
- NEW ModuleScript (manual, required): `SpectatorService` in `GuessThePuncherClient > Services`.
- SpectatorArea: optional (manual Part inside each arena, Anchored true CanCollide true) or auto-created platform.
- No other new objects.

## D. Hierarchy (Studio explorer after setup)
```
ReplicatedStorage > Remotes: RE_SpectatorUpdate (RemoteEvent) [NEW]
ServerScriptService > Services: MatchService [updated], QueueService [updated]
ServerScriptService > GuessThePuncherServer (Script) [updated remote list]
GuessThePuncherClient > Services: SpectatorService (ModuleScript) [NEW]
workspace (runtime): SpectatorArea platforms, spectator leash (server)
PlayerGui (runtime): SpectatorGui (code-created)
```

## E. Properties
- RE_SpectatorUpdate: class RemoteEvent, exact name, Parent `ReplicatedStorage.Remotes`.
- `SpectatorService` ModuleScript: Name exactly `SpectatorService`, Parent `GuessThePuncherClient > Services`.
- Spectator GUI/camera created by code - do NOT build manually.

## F. Copy instructions
1. Config -> `Shared.Config` · 2. RemoteNames -> `Shared.RemoteNames` · 3. MatchService -> `Services.MatchService` (REPLACE WHOLE 2163-line) · 4. QueueService -> `Services.QueueService` (replace whole) · 5. Main.server -> `GuessThePuncherServer` (replace whole) · 6. Main.client -> `GuessThePuncherClient` (replace whole) · 7. NEW `SpectatorService` ModuleScript · or run `docs/CommandBar_SpectatorSecurity.txt`. Claude MCP: flat/ files.

## G. Tests
### Spectator mode
1. **Normal knockout -> spectate**: Slot2, lock Strong repeatedly across turns (or StartingHealth 30) until KO -> eliminated player: normal camera, SpectatorGui panel "SPECTATOR MODE / Spectating <name> (1/1)", follow camera behind the remaining active player. Walk toward the arena -> server teleports you back (`Spectator ... teleported back to SpectatorArea (leash...)` in server output).
2. **Perfect knockout -> spectate**: Perfect lock -> same flow after the K.O. presentation.
3. **Switching camera targets (3 players)**: In Slot4 after one KO: Q / E keys and Prev/Next buttons cycle between the 2 active players; panel shows "Spectating <name> (1/2) -> (2/2)". A watched player dying/leaving is skipped automatically.
4. **Invalid spectator actions**: As spectator: press F -> client blocks (role not PotentialPuncher) + server rejects; fire `RE_PunchRequest:FireServer(matchId)` -> rejected; fire `RE_PowerGaugeStopRequest:FireServer(matchId)` -> `Not the Puncher`; fire `RE_GuessRequest:FireServer(matchId, id)` -> `Only the Target can guess`; fire `RE_QueueJoinRequest:FireServer("Slot2")` -> `Already in a match, cannot join queue`; spectator never becomes Target (roles show Spectator).
5. **Puncher hidden from spectator**: While spectating during a new turn: state payload print shows roles masked (no "Puncher" visible to you) and no puncherUserId; you learn the Puncher ONLY at the official reveal (RE_GuessResult) or the punch moment (RE_PunchSequence).
6. **Match ending while spectating**: Final KO (you are already spectating) -> VICTORY/defeat banner -> after 5s you are teleported to the Lobby, camera + controls restored (CameraType Custom, subject = your Humanoid), SpectatorGui gone, normal movement.
7. **Spectator respawn**: Reset character while spectating -> respawned onto the SpectatorArea platform (server), follow camera re-applies.
### Security audit exploit-resistance tests
8. **First-click priority**: Two potential punchers fire `RE_PunchRequest:FireServer(matchId)` in the same instant (both via command bar loops) -> exactly one becomes Puncher (server sequential), other gets `Puncher already selected`.
9. **Power claims**: Fire `RE_PowerGaugeStopRequest:FireServer(matchId, "Perfect", 1, 99999)` repeatedly -> zone always server-calculated (matches the real needle), claims ignored; >5 requests -> `Too many lock requests`.
10. **Damage/health**: No remote accepts damage/health values (grep-verified; only client->server args are matchId + ids). Firing all remotes with garbage values never changes health; health changes only after server locks.
11. **Guess correctness**: Non-Target fire -> rejected; Target guessing correctly works; guesses are evaluated ONLY server-side (`guessedUserId == matchData.puncherUserId`); 13 rapid guess fires -> `Rate limited`/`Too many guess requests`.
12. **Old match IDs**: Save a matchId, let the match end, fire all three request remotes with the OLD matchId -> `Match not found` / `Not in a match` (Matches map cleaned).
13. **Stale loops**: End a turn rapidly (KO immediately after lock) -> no double damage, no stale guessing countdown firing into the new turn (`Turn state reset ... attempt N` increments; old loops exit).
14. **Winner**: Cannot self-assign: no remote accepts "winner"; winner derived server-side from the last active player; disconnecting all but one still yields a server-confirmed winner.
15. **Client timestamps/damage/power claims**: Client sends no timestamps anywhere (`tick()`/`GetServerTimeNow()` only server-side); sending extra args to every remote has zero effect.

## H. Security audit results (required output)
### 1. Vulnerabilities found
- V1 (HIGH): Spectators/eliminated players received `puncherUserId` and the unmasked "Puncher" role in every `RE_MatchStateUpdate` - leaked the hidden Puncher identity to spectators before the official reveal.
- V2 (MEDIUM): `RE_PuncherSelected` / `RE_PuncherPreparation` were still delivered to eliminated players (identity leak channel).
- V3 (HIGH): `broadcastRoleAssigned` looked up players only in `matchData.players`, but eliminated players are removed from that map -> the "Spectator" role assignment never reached the eliminated client, leaving the restricted Target first-person camera stuck ON for the eliminated player.
- V4 (MEDIUM): `RE_GuessRequest` had no rate limiting - unlimited rejection spam (each firing RE_GuessRejected + InvalidGuess results).
- V5 (LOW): `RE_QueueJoinRequest` / `RE_QueueLeaveRequest` had no rate limiting (request spam).
- V6 (LOW): `Main.server.luau` auto-created an outdated remote list (missing 9 newer remotes) - functionality was covered by MatchService.Init but the stale list could mask missing-remote mistakes.
- V7 (MEDIUM, client presentation): Main.client never reacted to own elimination -> the eliminated Target kept the restricted camera until the next state broadcast (now restored immediately; SpectatorService also takes over).
- Verified SECURE (no issue): first-click priority, power calculation, damage/health, guess correctness, winner selection, knockout, role assignment, target/puncher selection, match membership, client timestamps/damage/power claims, duplicate protection, stale-event guards, old-match-ID rejection, disconnect handling, no RemoteFunctions exist (nothing client-invokable), no rewards/monetization systems exist.
### 2. Fixes applied
- V1: `buildFilteredPayload` masks Puncher identity for spectator recipients (role -> PotentialPuncher, no puncherUserId/prep time).
- V2: PuncherSelected/PuncherPreparation broadcasts skip eliminated players.
- V3: `broadcastRoleAssigned` falls back to `Players:GetPlayerByUserId`.
- V4: Guess requests rate-limited (0.3s cooldown + max 12/phase, tracked server-side in matchData).
- V5: Queue join/leave cooldown 0.5s per player (`Config.QueueActionCooldown`; disconnect cleanup bypasses it).
- V6: Main.server remote list synced to all current remotes.
- V7: Main.client self-elimination handler restores camera/visibility + sets Spectator role; SpectatorService wired.
### 3. How first Punch priority is determined
Entirely server-side arrival order. Roblox runs `OnServerEvent` callbacks sequentially on the server thread; the FIRST request that passes ALL validations (identity, match membership, active role = PotentialPuncher, state = WaitingForPuncher, alive, Target valid, no puncher yet, cooldown 0.5s, spam window) sets `matchData.puncherUserId` inside `selectPuncher`. Every later request hits the duplicate check (`puncherUserId` already set) and is rejected with `RE_PunchRejected`. No client timestamp or claim influences order.
### 4. How power is calculated
The Puncher's lock request carries ONLY matchId (extra args ignored). The server computes `elapsed = clamp(GetServerTimeNow() - gauge.startServerTime, 0, duration + grace)` from its OWN timestamps, converts to a ping-pong needle position via the shared `PowerZones.GetNeedlePosition` (0->1 reversing at ends, `PowerGaugeSweepDuration` per pass), and maps position to a zone via `PowerZones.GetZoneForPosition` and `Config.PowerGaugeZoneThresholds`. Early/late locks (outside `startServerTime-0.1 .. endServerTime+0.15`) are rejected; timeout -> Miss. Damage = `Config.Damage[zone]` server-side; clients can never send power/zone/timestamp values.
### 5. How guesses are validated
`MatchService.TrySubmitGuess` checks: engine-provided Player identity, match membership (`PlayersInMatch` + active set), state = Guessing AND `guessPhaseActive`, sender == current Target, not locked (one guess; duplicates rejected), request rate limit (0.3s + max 12/phase), `guessedUserId` must be a number, not the Target themself, and an ACTIVE match player. The accepted guess is evaluated server-side (`guessedUserId == puncherUserId` -> CorrectGuess else WrongGuess); invalid attempts get RE_GuessRejected + InvalidGuess WITHOUT consuming the one guess. Puncher identity is never sent before resolution.
### 6. How old events are rejected
- Old match IDs: handlers resolve `MatchService.Matches[matchId]`; after EndMatch cleanup the entry is nil -> "Match not found"; membership check (`PlayersInMatch`) also fails.
- Stale async loops: `matchData.turnAttempt` and `matchData.guessAttempt` increment on every reset/end; every loop (punch-selection timeout, guess countdown, reveal transition, KO continuation) captures its attempt and exits when it changes.
- Stale requests between turns: every request validates the CURRENT state (WaitingForPuncher / PowerGauge / Guessing) - a punch request during Guessing, a lock during WaitingForPuncher, or a guess during PowerGauge is rejected by state.
- Consumed one-shots: `damageApplied`, `sequenceFired`, `guessLocked`, `gauge.locked` are one-way flags reset only by the turn reset, so replays of the same logical event cannot double-apply.
### 7. Manual exploit-resistance tests
See tests 8-15 above (first-click race, power claims, damage/health injection, guess validation, old match IDs, stale events, winner self-assignment, client timestamps).

## I. Common errors and fixes
- Spectator camera does not activate: `SpectatorService` ModuleScript missing or not wired in Main.client; check `[SpectatorService] Ready` in client Output.
- Camera stuck on spectated player after match: re-copy SpectatorService + Main.client (HandleMatchEnd wiring); `[Spectator] Match ended while spectating` should print.
- Spectator wanders into the arena: increase enforcement via `SpectatorEnforceInterval` lower / `SpectatorLeashDistance` lower; verify updated MatchService is running (`Spectator ... teleported back` logs).
- Q/E does nothing: you are not eliminated (spectator input only active while spectating); gameProcessed events (chat) are ignored by design.
- Watch list shows 0 players: active players left/dead; list refreshes on `RE_SpectatorUpdate` when the active set changes.
- `RE_SpectatorUpdate not found`: re-copy MatchService (auto-creates) or create the RemoteEvent manually.
- Queue join always "Rate limited": spam protection; wait 0.5s between join/leave requests (Config.QueueActionCooldown).
- Eliminated Target camera issue persists: ensure you replaced BOTH MatchService (V3 fix) and Main.client (V7 fix).

## J. Not implemented (future - do not test)
- Rewards/progression/monetization (still none), freecam/spectator polish (zoom, bird view), spectator chat, spectator counters/UI polish, DataStores, scoring.
