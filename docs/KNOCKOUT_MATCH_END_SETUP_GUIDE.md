# Knockout & Elimination + Match Ending & Winner - Setup Guide

Combined guide for TWO phases implemented together (elimination triggers match completion):
- PART 1: Knockout & elimination (health 0 -> KO presentation -> spectator -> next turn or match end)
- PART 2: Match ending & winner handling (1 active player remains -> server-confirmed winner -> result display -> lobby return -> full cleanup)

## A. Goal

### PART 1 - Knockout & elimination (ONLY)
Rules implemented:
- Perfect damage (100) immediately knocks out the Target (at server contact moment)
- ANY damage reducing match health to zero knocks out the Target (e.g. accumulated Weak/Normal/Strong across turns)
- The knocked-out player leaves ACTIVE participation (removed from the active set: cannot Punch, Guess, or become Target)
- The eliminated player becomes a SPECTATOR (role "Spectator") and is moved to a SAFE SPECTATOR AREA: an optional manual `SpectatorArea` BasePart inside the arena, or a server AUTO-CREATED floating glass platform above the arena (Config.SpectatorAutoPlatformHeight = 25, SpectatorPlatformSize = 24)
- If >= 2 active players remain: another LIVING player is chosen as Target (fresh health, teleported to TargetStand), and the next Punch selection begins
- If exactly 1 active player remains: match completion is prepared (see PART 2)
- Cleans timers, roles, inputs, effects, old events (full turn reset + attempt guards)
- Handles disconnects during the knockout sequence (attempt guards + PlayerRemoving flows)
Server sequence: 1) stop gameplay input (turn reset) -> 2) KO presentation (RE_PlayerEliminated to ALL) -> 3) elimination CONFIRMED on server (active set removal + Spectator role) -> 4) spectator teleport after KnockoutDuration (3s) -> 5) active players updated -> 6) next turn or match-end preparation.
KO presentation (client, code-created, no asset IDs): "K.O.!" billboard + impact burst + placeholder sound note; the eliminated player gets "K.O.! YOU ARE ELIMINATED - Spectating" + flash; their restricted Target camera is RESTORED (normal spectator camera).
Not implemented: winner rewards, scoring, final GUI.

### PART 2 - Match ending & winner handling (ONLY)
- The match ends when ONE active player remains (via elimination OR a disconnect leaving one)
- The winner is CONFIRMED ON THE SERVER (roles -> "Winner", RE_RoleAssigned "Winner")
- Timers and gameplay events stop (attempt increments, gauge/sequence/guess cancellation)
- Actions after completion are REJECTED (match removed from Matches after cleanup; Punch/lock/Guess all require active states; `ending` flag blocks double-end and post-end leaving logic)
- Result DISPLAYED to participants (RE_MatchResult to ALL: matchId, "Winner"/"Cancelled", winnerUserId, reason)
- ORIGINAL VICTORY PRESENTATION (code-created placeholders, no asset IDs): winner sees "VICTORY! You win the match!" + confetti burst on their character; everyone else sees "<Name> WINS! - Defeat (thanks for playing)"; cancelled matches show "Match ended: <reason>"
- Players RETURN TO THE LOBBY after Config.LobbyReturnDelay (5s) - camera, visibility, effects restored on RE_MatchEnd; match health/roles reset naturally on the next match; movement was never altered
- ALL match-specific data cleaned (Matches entry removed, PlayersInMatch cleared, ArenasInUse cleared)
- QUEUE SLOTS MADE AVAILABLE AGAIN (QueueService.ReleaseSlot, existing integration)
- WINNER DISCONNECT handled: if the winner leaves during the result display, teleport skips them; if the last active player leaves before end, the match ends Cancelled (no winner)
Not implemented: DataStores, coins, shops, cosmetics, monetization, rewards, scoring.

## B. Files (exact paths)
### Changed
1. `src/Shared/Config.luau` - new KNOCKOUT, ELIMINATION & MATCH END section: `KnockoutDuration = 3` (KO presentation pause), `SpectatorAutoPlatformHeight = 25`, `SpectatorPlatformSize = 24`; `LobbyReturnDelay = 5` (already existed in MATCH SETUP) now drives lobby return
2. `src/Shared/RemoteNames.luau` - added `PlayerEliminated = "RE_PlayerEliminated"` (Server->ALL) and `MatchResult = "RE_MatchResult"` (Server->ALL)
3. `src/Server/Services/MatchService.luau` (2077 lines):
   - matchData fields: `eliminatedUserIds`, `winnerUserId`, `ending`
   - Helpers: `recountActivePlayers` (active = matchData.players map; eliminated are REMOVED from it), `getSpectatorAreaCFrame` (manual SpectatorArea or auto-created floating platform, reused per arena), `teleportToSpectatorArea`, `broadcastPlayerEliminated`, `broadcastMatchResult`
   - `eliminateTarget(matchData, reason)`: full 6-step server sequence above; reason = Results.EliminationReasons.PERFECT_PUNCH or DAMAGE_KO; attempt-guarded continuation
   - `applyPunchDamage`: health 0 -> eliminateTarget (any zone; Perfect = instant); survival -> guessing (unchanged)
   - `HandlePlayerLeaving`: early return when `ending`; spectator bookkeeping; active recount; **1 active remains -> EndMatch(..., lastActiveUserId) = WINNER** (except Preparing/SelectingTarget -> cancelled); 0 -> cancelled; target-left branch unchanged (new living Target)
   - `EndMatch(matchId, reason, winnerUserId?)`: `ending` guard; stops timers/events; CONFIRMS winner server-side (passed-in or last active; passed-in winner who left -> fallback); roles -> "Winner" + RoleAssigned; state Finished; RE_MatchResult; waits LobbyReturnDelay (result presentation); then RE_MatchEnd + lobby teleport + PlayersInMatch/ArenasInUse cleanup + QueueService.ReleaseSlot + Matches removal
   - Init: ensures + registers RE_PlayerEliminated/RE_MatchResult; spectator respawn -> back to spectator area
4. `src/Client/Services/PunchSequenceService.luau` - `onPlayerEliminated`: K.O.! billboard + impact burst + placeholder sound note; local eliminated player: flash + "YOU ARE ELIMINATED - Spectating" banner; cleans up with existing effect system
5. `src/Client/Main.client.luau` - loads + wires MatchResultService (`UpdateState`, `HandleMatchEnd`); ready prints updated
### New
6. `src/Client/Services/MatchResultService.luau` (167 lines) - RE_MatchResult presentation: VICTORY! + code-created confetti for the winner; "<Name> WINS! - Defeat" for others; "Match ended: reason" for cancelled; banner duration = LobbyReturnDelay
### flat/ sync (Claude MCP)
`flat/Shared_Config.luau`, `flat/Shared_RemoteNames.luau`, `flat/Server_MatchService.luau`, `flat/Client_PunchSequenceService.luau`, `flat/Client_MatchResultService.luau` (NEW), `flat/Client_Main.client.luau`
### Docs
`docs/KNOCKOUT_MATCH_END_SETUP_GUIDE.md` (this file), `docs/CommandBar_KnockoutMatchEnd.txt`

## C. Setup (manual objects)
- REMOTES: auto-created by MatchService.Init. Manual pre-create (RemoteEvent in ReplicatedStorage.Remotes): `RE_PlayerEliminated`, `RE_MatchResult`.
- MODULESCRIPT (manual, required): `MatchResultService` in `GuessThePuncherClient > Services` (paste code).
- OPTIONAL manual object per arena: `Workspace > MatchArenas > Arena2/4/6 > SpectatorArea` - Part, **Anchored true, CanCollide true**, Size e.g. (24, 1, 24), place it somewhere safe/visible (e.g. beside/above the arena). If MISSING, the server AUTO-CREATES a floating glass platform above the arena - no action required.
- All previous-phase objects/remotes must still exist.

## D. Hierarchy (Studio explorer after setup)
```
ReplicatedStorage
└── Remotes (Folder)
    ├── RE_PlayerEliminated (RemoteEvent) [NEW: Server -> ALL, KO presentation]
    └── RE_MatchResult (RemoteEvent)      [NEW: Server -> ALL, victory/defeat]
Workspace > MatchArenas > ArenaX
└── SpectatorArea (Part, optional - Anchored, CanCollide; auto-created if missing)
ServerScriptService > Services > MatchService (ModuleScript) [updated 2077 lines]
StarterPlayer > StarterPlayerScripts > GuessThePuncherClient (LocalScript) [updated]
    └── Services (Folder)
        ├── PunchSequenceService (ModuleScript) [updated: KO presentation]
        └── MatchResultService (ModuleScript)   [NEW]
workspace (runtime): auto-created SpectatorArea platform (if no manual one), VictoryConfetti host, effect folders
PlayerGui (runtime): PunchSequenceEliminated banner, MatchResultBanner (code-created)
```

## E. Properties
- New RemoteEvents: class RemoteEvent, exact names, Parent `ReplicatedStorage.Remotes`. No other properties.
- Optional SpectatorArea Part: Anchored true, CanCollide true (players stand on it), any Size/position; Name exactly `SpectatorArea`, parented INSIDE the arena Model.
- `MatchResultService` ModuleScript: Name exactly `MatchResultService`, Parent `GuessThePuncherClient > Services`.
- Auto-created spectator platform (runtime): Anchored true, CanCollide true, Transparency 0.4, Glass, size from Config. Banners/confetti created by code - do NOT build manually.

## F. Copy instructions
1. `src/Shared/Config.luau` -> `ReplicatedStorage > Shared > Config`
2. `src/Shared/RemoteNames.luau` -> `ReplicatedStorage > Shared > RemoteNames`
3. `src/Server/Services/MatchService.luau` -> `ServerScriptService > Services > MatchService` (REPLACE WHOLE 2077-line script)
4. `src/Client/Services/PunchSequenceService.luau` -> `GuessThePuncherClient > Services > PunchSequenceService` (replace whole)
5. NEW ModuleScript `MatchResultService` in `GuessThePuncherClient > Services`, paste `src/Client/Services/MatchResultService.luau`
6. `src/Client/Main.client.luau` -> `GuessThePuncherClient` (LocalScript)
7. Claude MCP: flat/ files (flat/Client_MatchResultService.luau -> MatchResultService etc.)
8. Or run `docs/CommandBar_KnockoutMatchEnd.txt` first

## G. Tests (Test > Clients and Servers; use 2, 4, and 6 players via Slot2/Slot4/Slot6; keep tuning: PowerGaugeDuration 10 / SweepDuration 2)
### PART 1 - Knockout & elimination
1. **Perfect = instant KO (2-player match)**: Lock Perfect -> server `takes 100 (Perfect) -> health 0/100` then `KNOCKOUT: Target X eliminated ... PerfectPunch`. All clients: "K.O.!" billboard + burst at the Target. The eliminated player: flash + "YOU ARE ELIMINATED - Spectating", camera returns to NORMAL (no first-person lock). After 3s (KnockoutDuration): eliminated player teleported to the floating glass platform (or your manual SpectatorArea).
2. **Any damage to zero**: Set `Config.StartingHealth = 30` (test) -> lock Strong (50) -> health 0 -> KO (DamageKO). Restore 100 after.
3. **Eliminated cannot act**: As the eliminated/spectator: press F (punch request) -> server `Not eligible role: Spectator`; fire `RE_GuessRequest:FireServer(matchId, id)` -> `Only the Target can guess`; cannot become Target (state payload roles show Spectator).
4. **>=2 active remain -> another living Target (3+ players)**: In Slot4, Target KO'd -> after 3s one of the remaining living players is Target (`New Target after KO: X ... N active`), seated on the TargetStand with `health=100/100 (last: -0 Reset)`, state WaitingForPuncher, F works for the puncher candidates. The eliminated player stays on the platform and is NOT in the eligible guess list.
5. **Disconnect during KO sequence**: Eliminated player leaves during the 3s KO pause -> no errors; match continues (or ends correctly if <2 active remain). Another player leaving right after a KO leaving 1 active -> match end (PART 2).
6. **Cleanup**: On KO: gauge/guess/timers of the old turn are gone (`Turn state reset ... attempt N`); no leftover effects (workspace effect folders cleaned); attempt guards prevent stale loops.
### PART 2 - Match ending & winner (test 2-, 4-, 6-player matches)
7. **2-player**: KO the opponent -> only 1 active remains -> server `Ending match ... Last player standing winner=X` + `WINNER CONFIRMED ... X` -> winner sees "VICTORY! You win the match!" + confetti; the eliminated player sees "<Name> WINS! - Defeat". After 5s (LobbyReturnDelay): everyone teleported to Lobby, camera/effects restored, `[Match] End` printed.
8. **4- and 6-player full run**: Play out turns (punch -> guess -> transfer) eliminating players one by one (Perfect locks) -> each KO: new living Target, next turn -> final 1 active -> winner confirmed -> presentation -> lobby. Verify state payloads never leaked puncherUserId to Targets during the whole match.
9. **Winner via disconnect**: 2+ active, all but one disconnect (stop one client) -> remaining player confirmed winner (server `Last player standing - Disconnected`), result + lobby flow as above. If the LAST player disconnects -> "No active players remain" -> Cancelled (no winner).
10. **Winner disconnects during result display**: Winner leaves right after VICTORY banner -> no errors; others still returned to lobby; match cleaned.
11. **Slots available again / new match after cleanup**: After the match, all players join Slot2 again -> queue fills -> NEW match starts normally (fresh health, roles, timers). Verify `Match cleaned up: <id>` printed and RE_QueueStateUpdate shows the slot open during the previous match-end.
12. **No actions after completion**: After result display, fire `RE_PunchRequest:FireServer(matchId)`, `RE_PowerGaugeStopRequest:FireServer(matchId)`, `RE_GuessRequest:FireServer(matchId, id)` -> all rejected (Match not found / wrong state). No damage/gauge restart possible.
13. **Cancelled match display**: Let the Punch selection expire with 2 players idle -> "Match ended: No Puncher selected in time" for everyone, lobby return, slot released.

## H. Expected results
- Health 0 (Perfect instant or accumulated) -> 6-step server sequence: input stop -> K.O. presentation -> server-confirmed elimination -> spectator area teleport (3s) -> active update -> new living Target + next turn, or match end at 1 active.
- Eliminated players: Spectator role, on the safe platform, camera normal, cannot Punch/Guess/become Target, not in guess choices, respawn back on the platform.
- Match end at 1 active: server-confirmed Winner, timers stopped, post-completion actions rejected, VICTORY/defeat/cancelled presentation (placeholder confetti, no asset IDs), lobby return after 5s, camera/visibility/effects reset, match data cleaned, queue slot released.
- Winner disconnect safe (skipped teleport, others still finish); last-player disconnect -> Cancelled.
- No DataStores/coins/shops/cosmetics/monetization/rewards anywhere.

## I. Common errors and fixes
- Eliminated player falls through the map: No SpectatorArea and auto-platform failed -> check Output for `Auto-created SpectatorArea platform`; raise `SpectatorAutoPlatformHeight`. Or create the manual SpectatorArea Part (Anchored true, CanCollide true).
- Eliminated player still has first-person camera: Re-copy PunchSequenceService + Main.client; RoleAssigned "Spectator" must reach the client (check Output `[Match] RoleAssigned ... role=Spectator`).
- No match end at 1 player: Check server output for `Ending match ... winner=`; if missing, an old MatchService is running - REPLACE the whole 2077-line file.
- Double result banners: `ending` guard prevents double EndMatch; if seen, mixed old/new MatchService - replace whole file, restart Play.
- Players stuck in arena after result: LobbySpawnLocation missing -> teleport falls back to (0,5,0); ensure `Workspace > Lobby > SpawnLocation` exists (Anchored true).
- Queue slot stays locked: QueueService.ReleaseSlot missing/renamed -> verify `ServerScriptService > Services > QueueService` has ReleaseSlot and the slot id matches.
- K.O. effects remain: Re-copy PunchSequenceService (cleanup wiring) and Main.client; confirm `[PunchSequence] Effects cleaned` prints on match end.
- Spectator respawned into the arena: Server Init spectator respawn branch missing - you have an old MatchService; replace whole file.
- Confetti/banners missing: MatchResultService not installed or RE_MatchResult not created - check `[MatchResultService] Ready` in client Output.
- `ending` field nil errors: Old matchData from a previous script version - restart Play after replacing MatchService.

## J. Not implemented (future - do not test for these)
- Winner rewards, coins, shops, cosmetics, monetization, DataStores
- Scoring systems, match statistics, leaderboards
- Spectator camera features (freecam UI, follow-cam modes) - spectators just have normal camera on the platform
- Post-elimination ragdoll/death animations (KO presentation is code-created effects)
- Multiple simultaneous matches beyond the existing slot system, rematches UI, final game GUI polish
