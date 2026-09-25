# Guessing Phase + Turn System - Setup Guide

Combined guide for TWO phases implemented together (the turn system consumes the guess result). ALSO includes the user-provided real animation IDs installed into the punch sequence.

## A. Goal

### PART 1 - Target guessing phase (ONLY)
- Starts ONLY after a valid punch (server-locked gauge -> damage applied -> Target survived). Gauge TIMEOUT = nobody punched -> NO guessing, a new Punch selection begins instead.
- The Target chooses which eligible player was the Puncher. Choices = all active match players EXCLUDING the Target (server builds the list).
- Prevents guessing before the phase starts (server rejects unless state = Guessing and phase active; client UI only exists while the phase is open).
- ONE submitted guess per phase (duplicate submissions rejected, guess not consumed on invalid attempts).
- Countdown (Config.GuessingDuration = 15s), server-driven; Target UI updates every second.
- Timeout = incorrect (GuessTimeout).
- Server validates everything: identity, match, only-Target, phase active, not locked, guess must be a number, not the Target, must be an active eligible player.
- Puncher identity stays HIDDEN until the reveal; RE_GuessResult to ALL clients = OFFICIAL reveal (after submission or timeout).
- Handles players leaving: eligible list refresh (GUI rebuilds), Target left -> new Target + new selection, Puncher left mid-guess -> guess cancelled (no answer), new selection.
- Rejects duplicate and invalid guesses (RE_GuessRejected + InvalidGuess result to Target only).
- Produces for later systems (Shared Results.GuessResults): "CorrectGuess", "WrongGuess", "GuessTimeout", "InvalidGuess".
- NOT implemented: final elimination, winner logic, rewards, scoring, DataStores, role-transfer UI (server does the transfer silently).

### PART 2 - Turn system connection (ONLY)
- CorrectGuess: the Puncher becomes the NEXT TARGET (old Target -> PotentialPuncher, new Target teleported to TargetStand+Chair, old Target to a spawn, fresh match health for the new Target).
- WrongGuess: the same Target remains active (health NOT reset - damage persists within the same Target's turn cycle).
- GuessTimeout: treated as incorrect (same Target remains).
- After an incorrect result (and after correct-guess transfer): another Punch selection phase begins (WaitingForPuncher + fresh PunchSelectionDuration timer).
- Reset between attempts: Puncher (role/position/lock/enforce conn), power (gauge + stored result), guessing (phase/lock/guessed/deadline), damage/sequence flags, timers - via resetTurnForNewAttempt() + startPunchSelectionWindow().
- Stale-event prevention: matchData.turnAttempt and matchData.guessAttempt increment on every reset; ALL async loops (punch-selection timeout, guess countdown, turn transition) are attempt-guarded and discard themselves when the counter changes. Cleared fields also make stale remote requests fail validation naturally.
- Players leaving during transitions: every transition re-checks match existence, state, and attempt before acting; HandlePlayerLeaving covers Target/Puncher/other leaves in every phase.
- Server-authoritative throughout: clients never decide roles, results, or timing.
- NOT implemented: final elimination, winner logic, rewards, DataStores.

### Animations installed (user-provided real IDs)
- `PunchAnimRaiseId = "rbxassetid://94641587122659"` (punch raise/windup)
- `PunchAnimPrepId = "rbxassetid://98380541569272"` (holding punch, looped through the prep window)
- `PunchAnimPunchId = "rbxassetid://81965585102785"` (punch strike at impact)
- `PunchSoundId` remains the clearly-marked PLACEHOLDER "rbxassetid://0" (user has NOT provided a sound ID).
- Server timing improved: RE_PunchSequence now fires IMMEDIATELY at lock so raise/hold play during the server prep window and the strike/impact visual lands exactly at the server damage moment.

## B. Files (exact paths)
### Changed
1. `src/Shared/Config.luau` - real animation IDs (above, clearly marked USER-PROVIDED); new GUESSING & TURN SYSTEM section: `GuessingEnabled = true`, `GuessingDuration = 15`, `GuessRevealPause = 1.5`, `GuessResultMissPause = 1.0`; `KnockoutDuration` remains FUTURE
2. `src/Shared/Results.luau` - `GuessResults = { CORRECT = "CorrectGuess", WRONG = "WrongGuess", TIMEOUT = "GuessTimeout", INVALID = "InvalidGuess" }` (exact values as specified)
3. `src/Shared/MatchStates.luau` - `Guessing -> { WaitingForPuncher, Resolving, Finished }` (turn loop; Resolving still FUTURE)
4. `src/Shared/RemoteNames.luau` - guessing remotes now implemented: `RE_GuessOpen` (Server->TARGET ONLY), `RE_GuessRequest` (Client->Server: matchId, guessedUserId), `RE_GuessRejected` (NEW, Server->Target reason), `RE_GuessResult` (Server->ALL = official reveal)
5. `src/Server/Services/MatchService.luau` (1823 lines) - GUESSING & TURN SYSTEM section:
   - matchData fields: `turnAttempt`, `guessPhaseActive`, `guessLocked`, `guessedUserId`, `guessEndTick`, `guessAttempt`
   - `startGuessingPhase`: guards (valid punch only, Target alive, puncher exists), state Guessing, deadline, attempt-guarded countdown loop (1s rebroadcasts), timeout -> resolveGuess(GuessTimeout)
   - `MatchService.TrySubmitGuess` (RE_GuessRequest): full validation; correct -> CorrectGuess else WrongGuess (server evaluates); rejects: not Target, phase inactive (pre-guessing), duplicate, non-number, self-guess, ineligible player - each with RE_GuessRejected + InvalidGuess result to Target (NOT consumed)
   - `resolveGuess`: official reveal to ALL (matchId, result, guessedUserId, puncherUserId), then attempt-guarded transition after GuessRevealPause: CorrectGuess -> Puncher becomes Target (roles broadcast, teleports, fresh health + Reset broadcast); Wrong/Timeout -> same Target; then startPunchSelectionWindow
   - `resetTurnForNewAttempt`: increments turnAttempt + guessAttempt (stale-event prevention), full puncher/gauge/damage/sequence/guessing reset
   - `startPunchSelectionWindow`: state WaitingForPuncher + fresh timer + attempt-guarded timeout loop (replaces the old inline loop; now reusable every turn)
   - Wiring: `applyPunchDamage` (Target survived) -> startGuessingPhase; gauge timeout Miss -> NO guessing, resetTurn + new selection after GuessResultMissPause; `HandlePlayerLeaving`: Puncher leaves during Guessing -> cancel guess + reset + new selection; Target leaves -> guess cancelled + new Target + fresh health + new selection; other leaves -> eligible list refreshed to Target
   - `EndMatch`: guess phase cleanup + attempt increments
6. `src/Client/Services/PunchSequenceService.luau` - real animations: `playAnimation` (USER-PROVIDED IDs, pcall + warn), sequence plays Raise -> Hold (looped) -> Punch (strike) aligned to server damage moment; header updated (sound still PLACEHOLDER)
7. `src/Client/Main.client.luau` - loads + wires GuessingService (`UpdateState`, `HandleMatchEnd`)
### New
8. `src/Client/Services/GuessingService.luau` (325 lines) - Target choice GUI (code-created: panel + countdown + one button per eligible player), submits `RE_GuessRequest:FireServer(matchId, userId)` ONCE, locks buttons, shows reveal banner to ALL clients, shows rejection reasons, cleans up on match end/state change/respawn
### flat/ sync (Claude MCP)
`flat/Shared_Config.luau`, `flat/Shared_Results.luau`, `flat/Shared_MatchStates.luau`, `flat/Shared_RemoteNames.luau`, `flat/Server_MatchService.luau`, `flat/Client_Main.client.luau`, `flat/Client_PunchSequenceService.luau`, `flat/Client_GuessingService.luau` (NEW)
### Docs
`docs/GUESSING_TURN_SETUP_GUIDE.md` (this file), `docs/CommandBar_GuessingTurn.txt`

## C. Setup (manual objects)
- NO new Workspace objects.
- 4 guess RemoteEvents AUTO-CREATED by `MatchService.Init`. To pre-create manually in `ReplicatedStorage > Remotes` (RemoteEvent each): `RE_GuessOpen`, `RE_GuessRequest`, `RE_GuessRejected`, `RE_GuessResult`.
- New ModuleScript needed manually (see D): `GuessingService`.
- All previous-phase objects/remotes must still exist. Test tuning still recommended: `PowerGaugeDuration = 10`, `PowerGaugeSweepDuration = 2`, `PunchSelectionDuration = 20`.

## D. Hierarchy (Studio explorer after setup)
```
ReplicatedStorage
├── Shared
│   ├── Config (ModuleScript)      [updated: real anim IDs + guessing settings]
│   ├── Results (ModuleScript)     [updated: CorrectGuess/WrongGuess/GuessTimeout/InvalidGuess]
│   ├── MatchStates (ModuleScript) [updated]
│   └── RemoteNames (ModuleScript) [updated]
└── Remotes (Folder)
    ├── RE_GuessOpen (RemoteEvent)      [Server -> TARGET ONLY]
    ├── RE_GuessRequest (RemoteEvent)   [Client -> Server: Target only]
    ├── RE_GuessRejected (RemoteEvent)  [Server -> Target]
    └── RE_GuessResult (RemoteEvent)    [Server -> ALL: official reveal]
ServerScriptService > Services > MatchService (ModuleScript) [updated 1823 lines]
StarterPlayer > StarterPlayerScripts > GuessThePuncherClient (LocalScript) [updated]
    └── Services (Folder)
        ├── PunchSequenceService (ModuleScript) [updated: real animations]
        └── GuessingService (ModuleScript)      [NEW]
PlayerGui (runtime, client-created)
└── GuessingDebugGui (ScreenGui: panel, countdown, buttons) / GuessRevealBanner
```

## E. Properties
- New RemoteEvents: class RemoteEvent, exact names, Parent `ReplicatedStorage.Remotes`. No other properties.
- `GuessingService` ModuleScript: Name exactly `GuessingService`, Parent `GuessThePuncherClient > Services`.
- The choice GUI/banner are created by CODE at runtime - do NOT build them manually.
- Animation IDs are already in Config (user-provided). If an animation fails to load, Output shows `[PunchSequence] Failed to load ... animation` - verify the IDs are published under the SAME owner as the game.

## F. Copy instructions
1. `src/Shared/Config.luau` -> `ReplicatedStorage > Shared > Config`
2. `src/Shared/Results.luau` -> `ReplicatedStorage > Shared > Results`
3. `src/Shared/MatchStates.luau` -> `ReplicatedStorage > Shared > MatchStates`
4. `src/Shared/RemoteNames.luau` -> `ReplicatedStorage > Shared > RemoteNames`
5. `src/Server/Services/MatchService.luau` -> `ServerScriptService > Services > MatchService` (REPLACE WHOLE 1823-line script)
6. `src/Client/Services/PunchSequenceService.luau` -> `GuessThePuncherClient > Services > PuncherSequenceService` (replace whole)
7. NEW ModuleScript `GuessingService` in `GuessThePuncherClient > Services`, paste `src/Client/Services/GuessingService.luau`
8. `src/Client/Main.client.luau` -> `GuessThePuncherClient` (LocalScript)
9. Claude MCP: flat/ files (flat/Client_GuessingService.luau -> GuessingService etc.)
10. Or run `docs/CommandBar_GuessingTurn.txt` first

## G. Tests (2-3 clients; use the tuning above)
### PART 1 - Guessing phase
1. **Starts only after a valid punch**: Play, all join Slot2, F as PotentialPuncher, lock with E. After damage: server `GUESSING started ... Target X has 15s`; ONLY the Target gets the choice panel (Who punched you? + buttons + countdown); other clients see nothing. Puncher identity still hidden (state payload has no puncherUserId).
2. **Gauge timeout = NO guessing**: Let the gauge expire -> grey MISS, `NO guessing (no valid punch)` in server output -> new Punch selection window starts (F works again).
3. **Eligible choices / Target excluded**: The panel lists every match player EXCEPT the Target (2-player match = 1 button; 3-player = 2 buttons).
4. **Guessing before phase rejected**: During WaitingForPuncher/Punching/PowerGauge fire `RE_GuessRequest:FireServer(matchId, someUserId)` as Target -> `Guess REJECTED: Guessing phase not active`, no effect.
5. **Only Target can guess**: Non-target fires RE_GuessRequest during Guessing -> `REJECTED: Only the Target can guess`.
6. **One guess / duplicates rejected**: Target clicks a button -> buttons lock, `Guess submitted`. Fire RE_GuessRequest again (same or different userId) -> `REJECTED: Duplicate: guess already submitted`; phase resolves exactly once.
7. **Invalid guesses rejected (not consumed)**: Target fires `RE_GuessRequest:FireServer(matchId, ownUserId)` (careful: this IS a valid-shaped but ineligible guess) -> rejected `You cannot guess yourself`; fires `RE_GuessRequest:FireServer(matchId, 999999)` -> rejected `Guessed player is not eligible`; the panel STAYS open and Target can still guess (InvalidGuess result logged, phase continues).
8. **Countdown + timeout = incorrect**: Target does not click -> panel countdown 15..0 -> server `GUESS RESOLVED ... result=GuessTimeout` -> ALL clients see "TIME'S UP! The Puncher was X" banner (official reveal).
### PART 2 - Turn system
9. **Correct guess (asked test)**: Note who the Puncher is (server output). Target clicks the Puncher's button -> `result=CorrectGuess` -> reveal "CORRECT GUESS!" -> after 1.5s: old Puncher teleported to TargetStand (seated), old Target moved to a spawn, roles broadcast (Puncher is now Target), `Correct guess: Puncher X is the NEW TARGET (fresh health)`, `[Health] health=100/100 (last: -0 Reset)`, state WaitingForPuncher, everyone can press F again.
10. **Wrong guess / multiple wrong guesses**: Target clicks a non-puncher -> `result=WrongGuess` -> reveal "WRONG GUESS! The Puncher was X" -> same Target stays on the stand (NOT reset to full health - damage persists), new Punch selection starts. Repeat several rounds: puncher is re-selected each time among PotentialPunchers, turn state resets each time (`Turn state reset ... attempt N` increments).
11. **Timeout turn**: Nobody guesses -> same as wrong: same Target remains, new selection. Verify health was NOT reset (e.g. after an earlier Weak, health stays 90).
12. **Player leaving between turns**: During WaitingForPuncher after a turn, the Puncher-candidate or Target leaves -> existing safe handling (new Target / match end if <2) with no stale flow. During Guessing: (a) a choice leaves -> Target's panel rebuilds without them; (b) the PUNCHER leaves -> `guess phase loses its answer`, no reveal, new Punch selection; (c) the TARGET leaves -> new Target selected, fresh health, new selection.
13. **Stale button/remote requests (asked test)**: Submit a guess, then BEFORE the 1.5s reveal pause ends fire `RE_GuessRequest:FireServer(matchId, userId)` again -> `Duplicate` rejected; after the turn resets, click a STALE button from the old panel or fire RE_GuessRequest with the old match data -> rejected (`Guessing phase not active`); press F during Guessing -> `Wrong state` rejected. Old panels: server refreshes/rebuilds close them; stale countdown loop is attempt-guarded (`Turn state reset ... attempt N` proves old loops died).
14. **Animations (real IDs)**: Watch the puncher during the sequence: raise -> hold (looped) -> strike at impact moment, aligned with the damage (`DAMAGE` line appears as the strike lands). If Output shows `Failed to load ... animation`, the asset is not published/accessible - see Common fixes.
15. **KO pause unaffected**: Lock Perfect -> health 0 -> `TARGET KNOCKED OUT ... PAUSED` -> NO guessing (Target cannot guess while knocked out) - state stays KnockedOut (future elimination flow).

## H. Expected results
- Guessing starts ONLY after a valid punch that leaves the Target alive; choices = all active players minus Target; one server-validated guess; 15s countdown; timeout = incorrect.
- Puncher hidden through Punching/PowerGauge/Guessing state payloads; identity revealed ONLY by RE_GuessResult at resolution (submission or timeout).
- Results produced: CorrectGuess / WrongGuess / GuessTimeout / InvalidGuess (exact strings in Results.GuessResults).
- Turn rules enforced server-side: Correct -> Puncher becomes Target (fresh health); Wrong/Timeout -> same Target (health persists); both -> full state reset (puncher/power/guessing/timers) and a NEW Punch selection phase.
- Stale events cannot affect the new attempt (attempt counters + cleared fields + state validation).
- Leaves handled in every phase; EndMatch cleans everything. No elimination/winner/scoring/DataStores.

## I. Common errors and fixes
- No choice panel appears: You are not the Target (only the Target gets RE_GuessOpen), the punch was a gauge-timeout Miss (no guessing by design), or the Target was KO'd (paused). Check server output for `GUESSING started`.
- `Results.GuessResults` nil / errors on Results: `ReplicatedStorage > Shared > Results` ModuleScript missing - create it and paste flat/Shared_Results.luau.
- Animations don't play: Output `Failed to load ... animation <id>` -> the animation must be published by the SAME user/group that owns the place (Roblox rule), and the ID must be an Animation asset. Verify in the Animations editor. The cartoon impact still plays regardless.
- Animations play at the wrong time: Ensure you copied BOTH MatchService (fire-immediately timing) and PunchSequenceService (Raise/Hold/Punch alignment).
- Guess always rejected "phase not active": You are firing outside Guessing - start the phase first (valid punch + surviving Target).
- Turn didn't switch after CorrectGuess: Check server for `Correct guess: Puncher X is the NEW TARGET`; if missing, the reveal-pause guard tripped (a player left during the 1.5s pause or state changed) - that's the leaving-handling working; next turn proceeds normally.
- Target kept damaged health after wrong guess: EXPECTED - only a NEW Target gets fresh health (spec: reset Puncher/power/guessing/timers between attempts, health not listed).
- Old panel buttons still clickable after a turn: Panels rebuild on every GuessOpen; a stale panel that never received a refresh means GuessingService is outdated - re-copy it (325 lines) and Main.client.
- `startPunchSelectionWindow` errors / double countdowns: You mixed old/new MatchService - REPLACE the whole 1823-line file and restart Play.
- Match ends with "No Puncher selected in time" right after a turn: PunchSelectionDuration (15s) expired - raise it while testing.

## J. Not implemented (future phases - do not test for these)
- Final elimination flow after KnockedOut (KO still just marks + pauses)
- Winner logic, scoring, rewards, round win counting, match completion by score
- DataStores / persistent stats
- Guess history UI, spectator reveal, post-reveal ceremony
- Any guessing GUI polish (current panel is a minimal code-created debug GUI)
