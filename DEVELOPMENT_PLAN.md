# Guess the Puncher - Complete Development Plan
## Version 0 - Planning Phase (No Code Yet)

This document is the authoritative plan for the game. No Luau files should be created until this is approved.

---

### 1. Repository Structure (Proposed)

Proposed GitHub repo layout that maps 1:1 to Roblox Studio. All files will be Luau (.luau) to allow Rojo-like sync or manual copy.

```
/ (repo root)
├── README.md
├── DEVELOPMENT_PLAN.md (this file)
├── docs/
│   ├── SETUP_GUIDE.md (manual Studio steps per phase)
│   └── REMOTES.md (remote contract)
└── src/
    ├── Server/
    │   ├── Main.server.luau              -> ServerScriptService/GuessThePuncherServer
    │   └── Services/
    │       ├── MatchSlotService.luau     -> ServerScriptService/Services
    │       ├── MatchService.luau
    │       ├── RoleService.luau
    │       ├── PunchService.luau
    │       ├── PowerGaugeService.luau
    │       ├── DamageService.luau
    │       ├── GuessService.luau
    │       ├── EliminationService.luau
    │       ├── TeleportService.luau
    │       └── ValidationService.luau
    ├── Client/
    │   ├── Main.client.luau              -> StarterPlayer/StarterPlayerScripts/GuessThePuncherClient
    │   └── Controllers/
    │       ├── SlotUIController.luau
    │       ├── CameraController.luau
    │       ├── PunchButtonController.luau
    │       ├── PowerGaugeController.luau
    │       ├── GuessUIController.luau
    │       ├── AnimationController.luau
    │       ├── HUDController.luau
    │       └── MatchStateController.luau
    └── Shared/
        ├── Constants.luau                -> ReplicatedStorage/Shared
        ├── Types.luau
        ├── Config.luau
        ├── Animations.luau
        └── Util/
            ├── Signal.luau
            ├── TableUtil.luau
            └── StateMachine.luau
```

**Why this structure:**
- Clear server authority separation.
- Shared holds no mutable state, only definitions.
- Client Controllers never trust their own data; they render server state.
- Server Services own all game logic.

---

### 2. Exact Luau Files Needed (Final Game)

#### Shared (ReplicatedStorage/Shared)
1.  `Constants.luau` - Match states, remote names, slot sizes, damage table, timing values, tags.
2.  `Types.luau` - Type definitions for Match, PlayerData, Slot, PowerTier, Role.
3.  `Config.luau` - Tunables: countdown duration (e.g. 10s), punch window duration, power gauge speed, damage values, perfect threshold, max health, teleport CFrames offsets.
4.  `Animations.luau` - Placeholder animation IDs with validation: `PUNCH_WINDUP`, `PUNCH_RELEASE`, `TARGET_HIT_REACT`, `TARGET_KO`. All default to "" with warn if empty.
5.  `Util/Signal.luau` - Simple signal implementation if needed.
6.  `Util/TableUtil.luau` - Helpers.
7.  `Util/StateMachine.luau` - Generic state machine for Match.

#### Server (ServerScriptService)
7.  `Main.server.luau` - Requires and initializes all Services. Validates existence of Remotes Folder and required Workspace folders. Prints clear errors if missing.
8.  `Services/ValidationService.luau` - Central validation: is player in match, alive, has role, etc. Never trusts client UserId.
9.  `Services/MatchSlotService.luau` - Manages 3 slots (2,4,6). Handles TouchBlock.Touched with debounce, occupancy, leave via button or leaving game, teleport to lobby stands, countdown, fires Slot_StateUpdate.
10. `Services/TeleportService.luau` - Safe teleport: checks HumanoidRootPart exists, sets CFrame, handles character loading, anti-stuck.
11. `Services/MatchService.luau` - Creates match object per slot. Owns state machine, player list (only those in slot), health table, alive table, current Target, current Puncher, punch lock. Cleanup on end.
12. `Services/RoleService.luau` - Picks Target: random living player initially, then on correct guess -> Puncher becomes Target, on elimination -> random living. Server only.
13. `Services/PunchService.luau` - Opens punch window, accepts first valid `Punch_RequestPunch`. Uses server tick to enforce first-come. Ignores Target requests. Sets PuncherSelected.
14. `Services/PowerGaugeService.luau` - Server-authoritative timing: when gauge opens, server records start tick. Client sends RequestStop. Server computes elapsed, maps to PowerTier. Client's claimed power ignored.
15. `Services/DamageService.luau` - Maps PowerTier -> damage. Perfect = instant KO (health = 0). Else subtract. Calls EliminationService if needed.
16. `Services/GuessService.luau` - Opens guess window for Target only. Validates guessedUserId is in match, alive, not self. Compares to server's hidden puncher. Fires result.
17. `Services/EliminationService.luau` - Marks health <=0 as eliminated, handles Target eliminated -> pick new Target, check win (1 alive left).

#### Client (StarterPlayerScripts)
18. `Main.client.luau` - Initializes controllers.
19. `Controllers/SlotUIController.luau` - Listens to Slot_StateUpdate, updates BillboardGuis on slots.
20. `Controllers/MatchStateController.luau` - Listens to Match_Start, Match_StateUpdate, Match_End, updates local match state.
21. `Controllers/CameraController.luau` - Handles Target first-person lock (FOV 70, Humanoid CameraMode LockFirstPerson, hides other players? Or server tells). Also spectator behind target. Must be client only.
22. `Controllers/PunchButtonController.luau` - Shows Punch button when PunchOpportunityOpened and local player is not Target and alive.
23. `Controllers/PowerGaugeController.luau` - Shows timing bar moving left-right. Local visual only. On stop button, fires RequestStop. No damage calc.
24. `Controllers/GuessUIController.luau` - Shows list of alive players (excluding self) when Guess_Open. Sends Guess_Request.
25. `Controllers/AnimationController.luau` - Listens to Animation_Play, loads Animator, plays placeholder animations. Validates Animator exists.
26. `Controllers/HUDController.luau` - Health, countdown, role label (You are Target / You are Spectator / You are Puncher), winner.

Total: ~26 files.

---

### 3. Exact Roblox Studio Destination for Each File

| Repo File | Roblox Studio Destination | Type |
|-----------|---------------------------|------|
| Server/Main.server.luau | ServerScriptService > GuessThePuncherServer | Script (server) |
| Server/Services/* | ServerScriptService > Services (Folder) > ModuleScript per file | ModuleScript |
| Shared/*.luau | ReplicatedStorage > Shared (Folder) > ModuleScript | ModuleScript |
| Shared/Util/*.luau | ReplicatedStorage > Shared > Util (Folder) > ModuleScript | ModuleScript |
| Client/Main.client.luau | StarterPlayer > StarterPlayerScripts > GuessThePuncherClient | LocalScript |
| Client/Controllers/* | StarterPlayer > StarterPlayerScripts > Controllers (Folder) > ModuleScript | ModuleScript |

**Important:** `Main.server.luau` and `Main.client.luau` must be Script/LocalScript with .server/.client suffix. All others are ModuleScripts.

---

### 4. Manual Roblox Objects Required

**Workspace:**
- `Lobby` (Folder) in Workspace
  - `SpawnLocation` (SpawnLocation) inside Lobby, default Roblox spawn.
  - `MatchSlots` (Folder) inside Lobby
    - `Slot2` (Model)
      - `TouchBlock` (Part) - Name exact: TouchBlock, Size 6x1x6, Anchored true, CanCollide false, Material ForceField maybe, Position in lobby
      - `DisplayBoard` (Part) - Anchored true, Size 4x6x0.5, for SurfaceGui/BillboardGui
      - `PlayerStands` (Folder)
        - `Stand1` (Part) - Anchored true, Size 3x1x3, Transparency 0.5
        - `Stand2` (Part) - same
    - `Slot4` (Model) - same but 4 stands
      - `TouchBlock`
      - `DisplayBoard`
      - `PlayerStands` (Stand1..Stand4)
    - `Slot6` (Model) - 6 stands
      - `TouchBlock`
      - `DisplayBoard`
      - `PlayerStands` (Stand1..Stand6)
- `MatchArenas` (Folder) in Workspace
  - `ArenaTemplate` (Model) - will be cloned or referenced. Contains:
    - `TargetStand` (Part) - Anchored true, Size 4x1x4, CFrame defines where Target stands, facing direction matters.
    - `PuncherStand` (Part) - Anchored true, Size 4x1x4, positioned 6 studs behind TargetStand (e.g. Target at 0,0,0 facing -Z, Puncher at 0,0,6 facing same direction as Target). This is critical for punch behind.
    - `SpectatorStands` (Folder) - contains Stand1..Stand5 parts in circle around.
    - `SpawnCFrame` (Part, invisible) - general spawn for match start before role assigned.
  - `Arena2` (Model) - instance for 2-player matches, copy of template positioned far away (e.g. at 0,100,0)
  - `Arena4` (Model) - positioned at 200,100,0
  - `Arena6` (Model) - positioned at 400,100,0
  - (Alternative: single arena reused; but 3 arenas allow concurrent matches for 2,4,6)

**ReplicatedStorage:**
- `Shared` (Folder) - created manually, will hold ModuleScripts copied from repo
  - `Util` (Folder) inside Shared
- `Remotes` (Folder) - contains all RemoteEvents
- `Controllers` is NOT in ReplicatedStorage, it's in StarterPlayerScripts.

**ServerScriptService:**
- `Services` (Folder) - holds service ModuleScripts
- `GuessThePuncherServer` (Script) - Main.server.luau

**StarterPlayer > StarterPlayerScripts:**
- `Controllers` (Folder)
- `GuessThePuncherClient` (LocalScript) - Main.client.luau

**StarterGui:**
- `SlotUI` (ScreenGui) - maybe per slot? Better one global:
  - `MainHUD` (ScreenGui) - Name: MainHUD, ResetOnSpawn false
    - `CountdownLabel` (TextLabel)
    - `RoleLabel` (TextLabel)
    - `HealthBar` (Frame with inner Fill)
    - `PunchButton` (TextButton) - Initially Visible false
    - `PowerGauge` (Frame) - Contains MovingIndicator, PerfectZone, StopButton
      - `Background` (Frame)
      - `PerfectZone` (Frame) - centered, Color Green
      - `Indicator` (Frame) - moving
      - `StopButton` (TextButton)
    - `GuessUI` (Frame) - Contains ScrollingFrame with player buttons
      - `Title` (TextLabel) "Who punched you?"
      - `PlayerList` (ScrollingFrame)
        - Template `PlayerButton` (TextButton)
- `BillboardGuis` - Attached to DisplayBoard parts in slots to show occupancy "2/6" etc. Create manually as BillboardGui inside DisplayBoard.

**Lighting / Other:** No special requirements.

**Tags (CollectionService):**
- Tag `SlotTouchBlock` on each TouchBlock Part for server to find.
- Tag `SlotStand` on each stand Part.
- Tag `TargetStand` on TargetStand.
- Tag `PuncherStand` on PuncherStand.

---

### 5. RemoteEvents and RemoteFunctions Required

All in `ReplicatedStorage/Remotes` (Folder). Exact names:

**RemoteEvents (Client <-> Server):**

1.  `RE_SlotJoinRequest` - Client -> Server - Params: (slotId: string "Slot2"|"Slot4"|"Slot6") - Request to join slot via UI or touch (touch will also fire server-side directly, but client can also request via proximity). Server validates.
2.  `RE_SlotLeaveRequest` - Client -> Server - Params: none, uses player - Leave current slot.
3.  `RE_SlotStateUpdate` - Server -> All Clients - Params: (slotId, occupancy: {userId,...}, maxPlayers, countdownActive: bool, countdownTimeLeft: number) - Updates lobby displays.
4.  `RE_MatchCountdownUpdate` - Server -> Clients in Slot - Params: (slotId, timeLeft) - For countdown UI.
5.  `RE_MatchStart` - Server -> Clients in Match - Params: (matchId, arenaName, players: {userId}, config)
6.  `RE_MatchStateUpdate` - Server -> Clients in Match - Params: (matchId, state: string, targetUserId: number?, alivePlayers: {userId}, healthTable: {[userId]=health}) - **IMPORTANT: Never includes puncherUserId when state is GUESSING for Target client; filtered version sent to Target.**
7.  `RE_PunchOpportunityOpen` - Server -> Clients in Match (except Target) - Params: (matchId, windowDuration) - Shows Punch button.
8.  `RE_PunchRequest` - Client -> Server - Params: (matchId) - Client claims "I want to punch". Server decides first valid.
9.  `RE_PuncherSelected` - Server -> Clients in Match - Params: (matchId, puncherUserId, targetUserId) - **Filtered: Target client receives puncherUserId = nil / hidden. Spectators and Puncher see real puncher.**
10. `RE_PowerGaugeOpen` - Server -> Puncher Client Only - Params: (matchId) - Open gauge.
11. `RE_PowerGaugeStopRequest` - Client -> Server - Params: (matchId) - Puncher pressed stop. Server calculates power based on server tick.
12. `RE_PowerGaugeResult` - Server -> Clients in Match - Params: (matchId, puncherUserId, powerTier: "Weak"|"Medium"|"Strong"|"Perfect", damage: number)
13. `RE_DamageApplied` - Server -> Clients in Match - Params: (matchId, targetUserId, newHealth, isKO: bool)
14. `RE_GuessOpen` - Server -> Target Client Only - Params: (matchId, guessablePlayers: {userId}) - Open guess UI.
15. `RE_GuessRequest` - Client -> Server - Params: (matchId, guessedUserId: number) - Target guesses.
16. `RE_GuessResult` - Server -> Clients in Match - Params: (matchId, correct: bool, guessedUserId, actualPuncherUserId, nextTargetUserId?) - After guess, reveal puncher to all.
17. `RE_TargetEliminated` - Server -> Clients in Match - Params: (matchId, eliminatedUserId)
18. `RE_MatchEnd` - Server -> Clients in Match - Params: (matchId, winnerUserId)
19. `RE_CameraMode` - Server -> Individual Client - Params: (mode: "Lobby"|"FirstPersonTarget"|"BehindTarget"|"Spectator")
20. `RE_AnimationPlay` - Server -> Clients in Match - Params: (userId, animType: "PunchWindup"|"PunchRelease"|"HitReact"|"KO", powerTier?)

**RemoteFunctions:** None for MVP. Avoid RF to prevent client yielding exploits. If needed later, add `RF_GetSlotStates` for initial sync, but we can use RE initial fire on PlayerAdded.

**Total RE count:** 20. Can be reduced by merging some, but explicit names improve security review. Final implementation may consolidate to ~12-15 while keeping filtered logic.

Alternative consolidated set (if you prefer fewer):
- Keep SlotJoin/Leave/State (3)
- MatchLifecycle (Start, StateUpdate, End) (3)
- PunchFlow (Opportunity, Request, Selected, PowerOpen, PowerStop, PowerResult) (6)
- GuessFlow (Open, Request, Result) (3)
- Damage/Elimination (2)
- Camera/Animation (2)
Total 19, similar.

**Security rule for each RE:** Server must validate `player` argument is legitimate, check match membership, alive, role, state, debounce, and never trust client-provided damage/power/UserId.

---

### 6. Server-Authoritative Systems

All authoritative logic runs on Server. Client is dumb renderer.

- **Slot Authority:** Server owns slot occupancy tables. TouchBlock.Touched handler checks debounce per player, checks if player already in a slot, checks slot full, then adds. Teleport handled by TeleportService with server CFrame.
- **Countdown Authority:** Server starts countdown when slot has >=2 players? Spec says "enough players". Define: 2 for Slot2 needs 2, Slot4 needs 2? Or needs full? Suggest: Slot2 needs 2, Slot4 needs 3 min, Slot6 needs 4 min, OR require full. We'll make configurable: `Config.MIN_PLAYERS_TO_START = {Slot2=2, Slot4=2, Slot6=2}` but countdown cancels if drops below min. Or require full for simplicity: countdown when full. Need decision. Propose: countdown when slot has at least 2 and has been full OR player count >=2 and 30s passed? For MVP, countdown when full (2/2,4/4,6/6). This prevents partial start confusion. Can tune later.
- **Match Creation:** Server clones arena or uses prebuilt, creates matchId (e.g. "Slot2_12345"), stores in MatchService.Matches[matchId] = {players, health, alive, state, target, puncher, etc}
- **Role Assignment:** Random living player. Uses server Random.
- **Punch Competition:** Server opens window, sets `punchLock = false`, `punchWindowEnd = tick() + Config.PUNCH_WINDOW`. First `RE_PunchRequest` that passes validation (alive, not target, in match, state==PUNCH_OPPORTUNITY, not locked) gets lock. All other requests ignored until next round. Prevent spam with per-player cooldown 0.5s.
- **Power Gauge Authority:** Server records `gaugeStartTick = tick()` when sending PowerGaugeOpen. When client sends StopRequest, server computes `elapsed = tick() - gaugeStartTick`, maps elapsed to tier using same curve as client visual (so client visual must match server curve). Client never sends power value. Server also enforces max gauge time (e.g. 5s) -> auto Weak if no stop.
- **Damage Authority:** Server maps tier to damage: Weak=10, Medium=25, Strong=50, Perfect=100 (instant KO). Configurable. Server subtracts from target health, never trusts client damage.
- **Guess Authority:** Only target can guess, only in GUESSING state, guessed player must be alive and in match and not self. Server compares guessedUserId to stored puncherUserId. Correct -> puncher becomes next target. Wrong -> same target stays, new punch round.
- **Elimination & Win:** Health <=0 -> eliminated, alive list updated. If target eliminated, pick new target from alive. If alive count ==1 -> winner, match ends, cleanup, teleport back to lobby.
- **Teleport Authority:** Server moves characters, not client. Validates HumanoidRootPart exists.
- **Leave Handling:** If player leaves game mid-match, remove from slot/match, handle if they were target/puncher, reassign or end match if <2 left.

---

### 7. Client-Only Presentation Systems

- **SlotUIController:** Shows occupancy via BillboardGui TextLabel update from RE_SlotStateUpdate. Shows countdown.
- **CameraController:** When target, forces FirstPerson: sets `player.CameraMode = LockFirstPerson`, `CameraMaxZoomDistance=0.5`, `CameraMinZoomDistance=0.5`, FieldOfView maybe 70, and maybe hides other characters behind? For MVP, just lock first person. For puncher/spectator, sets third-person behind target: `CameraMode Classic`, CFrame look at target? Could use `workspace.CurrentCamera.CFrame = CFrame behind target`. But simple: just set CameraMode and let player see arena. Advanced: script camera to face target.
- **PunchButtonController:** Visible only when RE_PunchOpportunityOpen received and local player is not target and alive. On click, fires RE_PunchRequest. Debounce 0.5s, disables button after press.
- **PowerGaugeController:** When RE_PowerGaugeOpen received (only puncher), show gauge Frame. Indicator moves via Tween or RenderStepped loop (sin wave or linear ping-pong). On StopButton click, fire RE_PowerGaugeStopRequest, hide gauge. Local animation only.
- **AnimationController:** Listens RE_AnimationPlay. For each userId, finds character, finds Animator in Humanoid, loads Animation with ID from Shared/Animations module. If ID empty, warn and skip. Plays animation. Types: Windup (puncher before gauge), Release (after gauge), HitReact (target when hit), KO (target eliminated).
- **GuessUIController:** When RE_GuessOpen received, show Frame with buttons for each guessable player (display names). On button click, fire RE_GuessRequest with guessedUserId. Hide after guess.
- **HUDController:** Shows role, health bar (from RE_MatchStateUpdate / DamageApplied), winner announcement.
- **MatchStateController:** Keeps local copy of match state for UI logic, but never authoritative.

All client controllers must handle missing objects gracefully with `warn("[Controller] Missing X")` and not error.

---

### 8. Match States (State Machine)

```
WAITING_FOR_PLAYERS  -- slot not full, waiting
COUNTDOWN            -- slot full or min met, counting down (10s)
INITIALIZING         -- teleport players to arena, assign health, pick initial target
ROUND_START          -- new round, announce target, short delay (2s)
PUNCH_OPPORTUNITY    -- open punch window for non-targets (10s window)
PUNCHER_SELECTED     -- puncher chosen, teleport behind target, play windup anim
POWER_GAUGE          -- puncher timing game (max 5s)
PUNCH_EXECUTING      -- apply damage, play punch + hit anim, show power result (2s)
GUESSING             -- target must guess (15s window, if timeout -> auto wrong)
GUESS_RESULT         -- show if correct/wrong, reveal puncher (3s)
  -> if correct: go to ROUND_START with new target = puncher
  -> if wrong and target still alive: go to PUNCH_OPPORTUNITY (same target)
  -> if wrong and target KO: go to TARGET_ELIMINATED
TARGET_ELIMINATED    -- target out, announce, check win condition (2s)
  -> if 1 alive left: go to MATCH_ENDING
  -> else: pick new target, go to ROUND_START
MATCH_ENDING         -- announce winner, play victory anim (5s)
CLEANUP              -- teleport all back to lobby, clear match data, reset slot
```

State transitions always server-driven. Client receives state updates.

**Per-state server actions:**
- WAITING: nothing
- COUNTDOWN: tick countdown, broadcast
- INITIALIZING: set health = max (100), alive = all, pick random target, teleport, set camera modes, delay then ROUND_START
- ROUND_START: clear puncher, broadcast target, short delay then PUNCH_OPPORTUNITY
- PUNCH_OPPORTUNITY: broadcast opportunity, start window timer, wait for PunchService to select puncher or timeout (if no one punches in 10s, pick random non-target as puncher? Or reopen? Propose: auto-pick random)
- PUNCHER_SELECTED: teleport puncher, play windup anim, delay 1s then POWER_GAUGE
- POWER_GAUGE: open gauge for puncher, start timer, wait for stop request or timeout
- PUNCH_EXECUTING: calc damage, apply, play anims, broadcast result, delay then check if target KO? If KO -> TARGET_ELIMINATED else GUESSING
- GUESSING: open guess for target, start timer
- GUESS_RESULT: broadcast result, handle role swap logic
- etc.

---

### 9. Data That Must Remain Hidden From Clients

**Critical hidden:**
- `actualPuncherUserId` during PUNCH_OPPORTUNITY, PUNCHER_SELECTED, POWER_GAUGE, PUNCH_EXECUTING, GUESSING - must be hidden from Target client. Only after GUESS_RESULT is it revealed to all. Implementation: Server sends two versions of RE_PuncherSelected and RE_MatchStateUpdate: one filtered for Target (puncher = nil), one full for others. Or server never sends puncher to Target until reveal.
- `power calculation` - client never decides damage. Server computes from tick.
- `future target selection` - server random, not predictable.
- `other matches' private data` - each match isolated.

**Partially hidden:**
- Health of other players? Might be shown in HUD but server authoritative. Could show all healths to all match players for party feel, but target health is main. Propose show all.
- Exact timing of power gauge perfect window - client visual approximates but server's mapping is authoritative; client cannot know exact thresholds to exploit? But thresholds can be shared for visual sync; still server enforces.

**Never trust client:**
- Damage, power tier, score, timing, role, winner, UserId in guess, punch request timestamp.

**Where stored:**
- Server only: `MatchService.Matches` table contains puncherUserId, gaugeStartTick, healthTable, etc. Never replicated to clients except filtered events.
- Client only: local UI state, camera state.

---

### 10. Development Order (Phases)

**Phase 0 - Plan (CURRENT):** This document. Approval needed.

**Phase 1 - Repo Structure & Remotes & Constants:**
- Create folder structure in repo.
- Create Shared/Constants, Types, Config, Animations with placeholder values.
- Create Remotes folder creation script documentation.
- Create Main.server.luau and Main.client.luau scaffolding that validates objects.
- Manual Studio setup: create ReplicatedStorage/Remotes Folder and 20 RemoteEvents with exact names.
- Test: Server prints "Remotes validated", client prints "Connected".

**Phase 2 - Match Slot System:**
- Implement MatchSlotService: touch detection, occupancy, BillboardGui updates, leave request, countdown, cancellation if player leaves.
- Implement SlotUIController: occupancy display.
- Implement TeleportService: teleport to stands.
- Manual: Build Lobby with 3 slots (2,4,6) as per spec, with TouchBlocks and Stands, Tags, Attributes (SlotId).
- Test: 2 players touch Slot2 block, see 1/2 -> 2/2, countdown starts, both teleported to stands.

**Phase 3 - Match Lifecycle & State Machine:**
- Implement MatchService with state machine, MatchState module.
- Implement basic arena teleport (use ArenaTemplate).
- Manual: Build MatchArenas Folder with 3 arenas, TargetStand, PuncherStand.
- Test: After countdown, players teleported to arena, match state goes INITIALIZING -> ROUND_START.

**Phase 4 - Role Assignment & Camera:**
- Implement RoleService: random target pick.
- Implement CameraController: target first-person lock, spectator third-person.
- Implement RE_CameraMode, RE_MatchStateUpdate with targetUserId.
- Test: One player becomes target, camera locked first-person, others see third-person.

**Phase 5 - Punch Competition:**
- Implement PunchService: punch window, first valid request wins.
- Implement PunchButtonController: shows button for non-targets.
- Implement RE_PunchOpportunityOpen, RE_PunchRequest, RE_PuncherSelected (filtered).
- Test: Non-targets see Punch button, first clicker becomes puncher, target does NOT see who puncher is.

**Phase 6 - Puncher Movement & Animations:**
- Implement teleport puncher behind target using TeleportService + offset.
- Implement AnimationController with placeholder IDs, RE_AnimationPlay.
- Implement windup animation during movement.
- Manual: Add Animator objects, ensure Humanoid exists.
- Test: Puncher teleports behind target, windup anim plays (or warns if ID missing).

**Phase 7 - Power Gauge (Server-Authoritative Timing):**
- Implement PowerGaugeService: server tick timing, tier mapping.
- Implement PowerGaugeController: UI with moving indicator, perfect zone.
- Implement RE_PowerGaugeOpen, StopRequest, Result.
- Define power tiers: Weak (0-30%), Medium (30-70%), Strong (70-90%), Perfect (90-100% sweet spot centered? Or precise timing). Propose ping-pong bar: indicator moves left-right over 2 seconds loop, perfect zone in middle 10% width.
- Test: Puncher sees gauge, presses stop, server calculates tier, broadcasts result, damage not yet applied? Actually damage next phase.

**Phase 8 - Damage & KO:**
- Implement DamageService: tier->damage, health tracking, KO detection.
- Implement HUDController: health bar.
- Implement RE_DamageApplied, hit react and KO animations.
- Test: Power result applies damage, target health reduces, Perfect instantly KO.

**Phase 9 - Guess System:**
- Implement GuessService: guess window, validation, correctness, role swap.
- Implement GuessUIController: list of players to guess.
- Implement RE_GuessOpen, GuessRequest, GuessResult.
- Test: Target sees guess UI after punch, picks player, if correct -> puncher becomes new target, if wrong -> same target another punch round.

**Phase 10 - Elimination & Win:**
- Implement EliminationService: eliminate, pick new target from alive, win check.
- Implement MatchEnd cleanup: teleport back to lobby, reset slots, announce winner.
- Test: Full match from start to winner with 2,4,6 players.

**Phase 11 - Polish & Anti-Exploit:**
- Debounces, leave handling, edge cases (player dies, character respawns mid-match), animation ID placeholders documentation, sound placeholders, final HUD polish.
- Security review: ensure no client-trusted values.
- Performance: limit RemoteEvent spam.

---

### 11. Testing Order

Each phase has its own test procedure using Roblox Studio's built-in multiplayer test.

**General Test Setup:**
- File > Settings > Enable "Show Hidden Objects in Explorer" maybe.
- Use Test tab > Clients and Servers > 2-6 clients (e.g., 3 clients for Slot2, 6 for Slot6).
- Always start with 1 server + N clients.

**Phase 1 Test:**
- Start server + 1 client.
- Check Output: Server prints "[GuessThePuncher] Remotes validated: 20 found" or errors listing missing remotes.
- Client prints "[Client] Connected, waiting for slot updates".
- Expected: No errors.

**Phase 2 Test:**
- Server + 2 clients.
- Client1 touches Slot2 TouchBlock.
- Check: Billboard shows 1/2, Output shows player joined.
- Client2 touches same.
- Check: 2/2, countdown starts (10s), both teleported to Stand1, Stand2.
- One client leaves slot via button or leaves game: countdown cancels, occupancy updates.
- Expected: Occupancy syncs to all clients.

**Phase 3 Test:**
- Server + 2 clients, both in Slot2, countdown finishes.
- Check: Both teleported to Arena2 SpawnCFrame or TargetStand/SpectatorStands.
- Check: MatchState prints INITIALIZING, ROUND_START.
- Expected: Players in arena, not in lobby.

**Phase 4 Test:**
- Server + 3 clients in Slot4 (need at least 2).
- After match start, check: One random target, his camera locked first-person (zoom 0.5, can't go third-person), RoleLabel shows "You are TARGET".
- Others: RoleLabel "Spectator - Press Punch!".
- Expected: Target cannot see behind.

**Phase 5 Test:**
- Server + 3 clients, match in PUNCH_OPPORTUNITY.
- Non-targets see Punch button.
- Target does NOT see button.
- Two non-targets click simultaneously: only first server-accepted becomes puncher (check Output: "[PunchService] Puncher selected: X").
- Target's client Output should NOT contain puncherUserId (check filtering).
- Expected: PuncherSelected event filtered correctly.

**Phase 6 Test:**
- After puncher selected, check: Puncher teleported to PuncherStand behind target (6 studs behind, facing target back).
- Check: AnimationPlay events fire, if animation IDs empty, warn appears but no error.
- Expected: Puncher behind target.

**Phase 7 Test:**
- Puncher client sees PowerGauge UI appear.
- Gauge indicator moves.
- Puncher clicks Stop.
- Check: Server calculates tier based on server tick, broadcasts result, all clients see same tier.
- If puncher doesn't click in 5s, auto Weak.
- Expected: Power result consistent.

**Phase 8 Test:**
- After power result, target health reduces.
- Check: Health bar updates.
- Perfect hit: target health 0, KO anim, goes to TARGET_ELIMINATED.
- Non-perfect: health reduces but target still alive, goes to GUESSING.
- Expected: Damage authoritative.

**Phase 9 Test:**
- Target sees GuessUI with list of alive players (excluding self).
- Target picks correct puncher: Output shows correct=true, next target = puncher.
- Target picks wrong: correct=false, same target stays.
- Try exploit: non-target tries to fire GuessRequest -> server rejects with warn.
- Expected: Role swap works, exploit blocked.

**Phase 10 Test:**
- Full match with 4 players, simulate until 1 winner.
- Check: When target KO, new target random from alive.
- When 1 alive left, MatchEnd fires, winner announced, all teleported back to lobby, slots reset.
- Test player leaving mid-match: match continues if >=2, ends if <2.
- Expected: Winner declared, cleanup works.

**Phase 11 Test:**
- 6 clients, stress test.
- Spam Punch button -> only first valid counts, no crash.
- Spam Power Stop -> only first counts.
- Spam Guess -> only target's first valid guess counts.
- Check Output for no errors, only warns for missing animation IDs.
- Expected: No exploits, stable.

---

### 12. Possible Risks and Assumptions

**Risks:**
1.  **TouchBlock Exploit:** Exploiters can fire Touched repeatedly. Mitigation: server debounce per player (1s), check distance, check character.
2.  **Punch Spam:** Client spams RE_PunchRequest. Mitigation: per-player cooldown 0.5s, punchLock, state check.
3.  **Power Gauge Cheat:** Client could try to send fake power tier. Mitigation: server ignores client power, calculates from tick.
4.  **Guess Cheat:** Client could try to guess as non-target or guess self or guess eliminated player. Mitigation: ValidationService checks all.
5.  **Camera Bypass:** Target could try to go third-person via exploit to see puncher. Mitigation: Server keeps puncher hidden via filtered events, but camera exploit still possible - we can't fully prevent, but we can make puncher invisible to target? Idea: make puncher character invisible or far until after guess? Alternative: make all non-target characters invisible to target during punch? For MVP, accept risk, but note as future: use server to set puncher transparency to 1 for target client only via client controller.
6.  **Teleport Fail:** Character may be dead or HumanoidRootPart missing. Mitigation: TeleportService checks and waits for character, uses :WaitForChild.
7.  **Multiple Concurrent Matches:** Slots 2,4,6 can run simultaneously. Need matchId isolation. Risk of cross-match event leakage. Mitigation: All events include matchId, server checks player's current matchId.
8.  **Player Leaving:** Player leaves mid-countdown or mid-match. Mitigation: PlayerRemoving handler cleans up slot and match, reassigns target if needed.
9.  **Animation IDs Missing:** If you don't provide animation IDs, animations won't play. Mitigation: Animations module returns "" placeholders and warns, game still functions.
10. **Filtering Puncher Identity:** Hard to ensure target never sees puncher. Must send filtered events. Risk of accidentally leaking via MatchStateUpdate. Mitigation: explicit function `getFilteredStateForPlayer(player)` that nils puncher if player is target and state is guessing.
11. **Lobby vs Arena Separation:** Players in match should not be hit by lobby touch blocks. Mitigation: Teleport far away (e.g. 500 studs up), or disable touch handling for players in match.
12. **Performance:** Many BillboardGuis updating every second during countdown. Mitigation: update only on change.
13. **Roblox First-Person Lock:** Forcing first-person can be bypassed. Accept for MVP.
14. **No Asset IDs:** We will use placeholders "" for animations/sounds. You must provide real rbxassetid:// numbers later in Shared/Animations.luau.

**Assumptions:**
- Lobby spawn is default Roblox SpawnLocation, no custom logic needed.
- Match slots 2,4,6 are in Workspace/Lobby/MatchSlots as Models with TouchBlock and Stands. You will create them manually.
- Arenas are prebuilt in Workspace/MatchArenas, not dynamically cloned for MVP (simpler).
- Players have standard R15 or R6 rigs; animations work for both if you provide both IDs or use R15 only.
- Game uses default Humanoid health for display only; actual game health stored in server table (e.g. 100) to avoid conflict with Roblox health.
- Perfect hit instant KO is intended to be rare (10% zone), so game not too short.
- Guess UI shows DisplayNames, but server uses UserId.
- Winner gets no data persistence for MVP (no DataStore).
- No monetization or badges for MVP.
- You will manually create all required Folders, Parts, RemoteEvents with exact names before testing each phase.
- All code will include validation errors like `warn("[MatchSlotService] Missing object: Workspace.Lobby.MatchSlots")` and early return if missing, so you know what to create.
- Server authority never trusts client; all client values validated.
- Client never directly sets health, role, winner.

**Animation Specifics (as requested):**
- During power gauge: Puncher plays `PUNCH_WINDUP` loop (e.g. arm pulled back).
- When puncher releases (after gauge stop): `PUNCH_RELEASE` (punch forward).
- When target gets slapped/hit: `TARGET_HIT_REACT` (head snap, stumble).
- When target KO: `TARGET_KO` (fall).
- All IDs in Shared/Animations.luau as `rbxassetid://0` placeholders with comment `-- TODO: Replace with real asset ID`.
- AnimationController will handle loading and playing, with checks for Animator.

**Future Phases Not In MVP:**
- DataStore for wins.
- Emotes, skins, boxing gloves.
- Spectator camera orbit.
- Sound effects.
- Mobile UI scaling.
- Anti-cheat beyond validation.
- Multiple arenas with voting.

---

### Approval Required

Before proceeding to Phase 1 (repo structure + remotes), please confirm:
1. Slot sizes 2,4,6 correct? Countdown when full or when >=2?
2. Arena setup: 3 separate arenas far apart, or 1 shared arena?
3. Perfect hit = instant KO - keep?
4. Do you want puncher invisible to target during punch (to prevent camera exploit) or visible but identity hidden via UI only?
5. Any asset IDs already available for animations?

Once approved, I will create the initial repository structure and Phase 1 files with detailed setup instructions.

