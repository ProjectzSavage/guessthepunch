# Puncher Selection Phase - Setup Guide

## Goal
Implement ONLY Puncher selection phase. No power gauge, damage, guessing, knockout, scoring, monetization, final GUI.

## Required RemoteEvents (Before Coding)

### New for this phase:
1. **RE_PunchRequest** (RemoteEvent) - Client -> Server
   - Args: matchId: string (optional, server uses PlayersInMatch if not provided)
   - Client MUST send only Punch request, NOT claimed winner, timestamp, damage, power, role
   - Server validates: identity, match identity, active role, state, alive, eligibility, duplicate, rate limits

2. **RE_PunchRejected** (RemoteEvent) - Server -> Client
   - Args: matchId: string, reason: string
   - Reasons: NotEligible, AlreadyHasPuncher, RateLimited, WrongState, Spam, TargetNotEligible, NotInMatch, etc.

3. **RE_PuncherSelected** (RemoteEvent) - Server -> Client, FILTERED
   - Args: matchId: string, puncherUserId: number? (nil for Target to hide identity)
   - For Puncher: receives own UserId
   - For other non-Target PotentialPunchers: receives puncherUserId
   - For Target: receives nil (hidden, does NOT reveal Puncher before official reveal)

4. **RE_PuncherPreparation** (RemoteEvent) - Server -> Client
   - Args: matchId: string, timeLeft: number
   - Preparation countdown after Puncher selected, before future power gauge
   - Filtered: Target gets 0 or hidden

### Existing (must still exist, updated):
- RE_MatchStart, RE_MatchStateUpdate (now filtered to hide puncherUserId from Target), RE_MatchEnd, RE_RoleAssigned, RE_TargetSelected
- RE_Queue* events (unchanged)

### Auto-creation:
- RemoteService.EnsureAllRemotes now includes: RE_PunchRequest, RE_PunchRejected, RE_PuncherSelected, RE_PuncherPreparation

## Manual Arena Objects Required

### Workspace Structure:
```
Workspace
├── Lobby (Folder)
│   ├── SpawnLocation
│   └── MatchSlots (Folder)
│       ├── Slot2 (Model) - MaxPlayers 2
│       │   ├── EntryArea (Part, Anchored true, CanCollide false, Transparency 0.5)
│       │   ├── DisplayBoard (Part, Anchored true)
│       │   └── PlayerSpawns (Folder) with Player1, Player2 (Parts)
│       ├── Slot4, Slot6 similar with 4,6 spawns
└── MatchArenas (Folder)
    ├── Arena2 (Model) - for Slot2
    │   ├── TargetStand (Part, Anchored true, CanCollide false, Size 4,2,4, CFrame defines forward direction)
    │   │   └── Chair (Seat, Anchored false, CanCollide false, child of TargetStand, positioned on top of TargetStand)
    │   ├── PuncherStand (Part, Anchored true, CanCollide false, Size 4,1,4, Transparency 0.5)
    │   │   - Position: behind TargetStand at -LookVector * PuncherOffsetBehindTarget (6 studs)
    │   │   - Example: If TargetStand CFrame is at (0,5,0) facing (0,0,-1), PuncherStand at (0,5,6)
    │   │   - This is controlled position for Puncher, server enforces max distance 4 studs
    │   └── PlayerSpawns (Folder) with Player1..N Parts (for initial spawn before Target selection)
    ├── Arena4, Arena6 similar but larger
```

### Properties for PuncherStand (critical for this phase):
- Name: PuncherStand (exact)
- Parent: Arena Model (Arena2, Arena4, Arena6)
- Class: Part
- Anchored: true
- CanCollide: false (so Puncher doesn't get stuck)
- Transparency: 0.5 (visible for testing, can be 1 for production)
- Size: Vector3.new(4,1,4)
- CFrame: Behind TargetStand
  - Calculate: TargetStand.CFrame * CFrame.new(0,0,6) -- 6 studs behind
  - Orientation: Same as TargetStand or facing Target (CFrame.lookAt(PuncherStandPos, TargetStandPos))
- Attribute: None required, but ensure not named differently

### Why PuncherStand matters:
- Server uses getPuncherBehindCFrame() which first tries PuncherStand.CFrame, else calculates behind TargetStand or behind Target HRP
- Puncher is teleported to this controlled position behind Target
- Server enforces Puncher cannot freely leave: if distance > PuncherMaxDistanceFromPosition (4 studs), teleport back
- Gives short preparation period (PuncherPreparationTime = 3s) before future power gauge

## Changed Files (After Coding)

### 1. src/Shared/Config.luau
- Added Puncher selection tuning:
  - PunchSelectionDuration = 15 (max wait for punch request in WaitingForPuncher)
  - PuncherPreparationTime = 3 (short prep after selection)
  - PuncherMaxDistanceFromPosition = 4
  - PuncherEnforceInterval = 0.2
  - PunchRequestCooldown = 0.5 (rate limit)
  - PunchSpamThreshold = 3, PunchSpamWindow = 2

### 2. src/Shared/RemoteNames.luau
- Added to Match: RoleAssigned, TargetSelected, PunchRequest, PunchRejected, PuncherSelected, PuncherPreparation
- All list auto-created

### 3. src/Server/Services/MatchService.luau (1027 lines)
- Added fields to matchData: puncherUserId, puncherSelectedTick, puncherPreparationEndTick, puncherPosition, puncherLocked, puncherEnforceConn, punchRequests, punchRequestCounts, punchSelectionEndTick
- New helpers: getPuncherBehindCFrame(), teleportPuncherBehindTarget()
- New filtered payload: buildFilteredPayload now hides puncherUserId from Target, includes puncherPreparationTimeLeft for non-Target
- New broadcasts: broadcastPuncherSelected (filtered nil for Target), broadcastPunchRejected, broadcastPuncherPreparation
- New validation: validatePunchRequest() checks:
  - Player identity (exists, Parent, GetPlayerByUserId)
  - Match identity (matchId string, matches PlayersInMatch, player in matchData.players)
  - Active role (must be PotentialPuncher, not Target, not already Puncher)
  - Current state (must be WaitingForPuncher)
  - Alive status (Character, Humanoid.Health >0)
  - Punch eligibility (Target valid, exists)
  - Duplicate (puncherUserId already exists)
  - Rate limits (cooldown 0.5s, spam threshold 3 in 2s window)
- New core: selectPuncher() assigns Puncher role, teleports behind Target, stores puncherPosition, sets state to Punching, starts enforce loop (Heartbeat checks distance >4, teleports back), starts preparation countdown broadcast
- TryBecomePuncher(): entry point for RE_PunchRequest, records request tick, validates, selects first valid, rejects later
- StartPunchSelectionPhase: sets punchSelectionEndTick = tick()+15, loop checks timeout -> EndMatch if no Puncher, checks Target invalid -> EndMatch
- HandlePlayerLeaving: if Puncher leaves, clear puncherUserId, disconnect enforce, revert to WaitingForPuncher, allow new selection. If Target leaves, select new Target, clear Puncher, revert to WaitingForPuncher.
- Init: ensures new remotes, listens to RE_PunchRequest OnServerEvent, client sends only matchId (no winner/timestamp/damage/power/role)

### 4. src/Client/Services/PuncherSelectionService.luau NEW
- Client-only Punch request presentation
- canRequestPunch() checks: in match, role PotentialPuncher, state WaitingForPuncher, not already selected, cooldown
- RequestPunch() fires RE_PunchRequest with matchId only (no winner/timestamp/damage/power/role)
- UpdateState() tracks matchId/role/state/puncherSelected, disables further requests when selected
- Handles PuncherSelected (filtered nil for Target), PunchRejected, Preparation countdown
- Input: Press F to request Punch for testing (UserInputService)
- Handles MatchEnd reset

### 5. src/Client/Main.client.luau (updated)
- Loads PuncherSelectionService alongside TargetCamera and Visibility
- Tracks currentPuncherUserId, currentState
- On MatchStateUpdate: updates puncherUserId (filtered), calls PuncherSelectionService.UpdateState
- On PuncherSelected event: logs, updates state
- On CharacterAdded: re-applies

### 6. flat/ copies
- All synced for Claude MCP

## Exact Studio Destinations

- ReplicatedStorage > Shared > Config (ModuleScript) <- Config.luau
- ReplicatedStorage > Shared > RemoteNames (ModuleScript) <- RemoteNames.luau
- ServerScriptService > Services > MatchService (ModuleScript) <- MatchService.luau (1027 lines, must have ServerScriptService defined)
- ServerScriptService > Services > QueueService (ModuleScript) <- unchanged 752 lines
- StarterPlayer > StarterPlayerScripts > GuessThePuncherClient (LocalScript) <- Main.client.luau
- StarterPlayer > StarterPlayerScripts > GuessThePuncherClient > Services (Folder)
  - TargetCameraService (ModuleScript)
  - TargetVisibilityService (ModuleScript)
  - PuncherSelectionService (ModuleScript) NEW

## Setup Instructions

1. Ensure Lobby and Arenas exist per previous phases, plus PuncherStand behind TargetStand in each Arena
2. Update Config, RemoteNames, MatchService from GitHub
3. Create PuncherSelectionService ModuleScript in GuessThePuncherClient.Services
4. Update Main.client.luau
5. Verify RemoteService auto-creates new remotes, or manually create in ReplicatedStorage.Remotes: RE_PunchRequest, RE_PunchRejected, RE_PuncherSelected, RE_PuncherPreparation

## Copy Instructions

- Manual: Copy src files to Studio destinations (no .luau extension in Studio)
- Flat: Use flat/ folder for Claude MCP - flat/Shared_Config.luau, flat/Shared_RemoteNames.luau, flat/Server_MatchService.luau, flat/Client_Main.client.luau, flat/Client_PuncherSelectionService.luau etc.
- CommandBar: Use docs/CommandBar_PuncherSelection.txt (to be created) which creates Services folder and ModuleScripts

## Multiplayer Tests

### Test 1: Every non-target may request Punch, Target not eligible
- Start 3 clients, join same Slot, wait for Target selection
- As Target, press F - should print "Target not eligible"
- As PotentialPuncher, press F - should send request

### Test 2: First valid becomes Puncher, later rejected
- 2 PotentialPunchers press F almost simultaneously
- Server Output: first gets "Puncher selected", second gets "Puncher already selected" + RE_PunchRejected
- Client Output: first sees "You are now Puncher!", second sees "Punch rejected: Puncher already selected"
- Check RE_MatchStateUpdate: Puncher role assigned, state becomes Punching

### Test 3: Move Puncher behind Target, prevent leaving
- After selection, Puncher should teleport to PuncherStand (behind Target)
- Try to walk away >4 studs - server should teleport back (enforce loop)
- Check Puncher CFrame stays near PuncherStand

### Test 4: Preparation period
- After selection, server broadcasts RE_PuncherPreparation countdown 3,2,1,0
- During prep, Puncher cannot leave, other punch actions unavailable (press F again -> "Already Puncher" or "Puncher already selected")

### Test 5: Duplicate requests and spam
- As PotentialPuncher, spam F quickly (<0.5s) - should get "Rate limited"
- Spam 3+ times within 2s - should get "Spam detected"
- After Puncher selected, all further requests rejected

### Test 6: Puncher disconnecting
- After Puncher selected, have Puncher leave game (PlayerRemoving)
- Server should clear puncherUserId, disconnect enforce, revert state to WaitingForPuncher, allow new selection
- Remaining players can press F again to become new Puncher

### Test 7: Target invalid
- During WaitingForPuncher or Punching, have Target leave
- Server should select new Target from remaining, clear Puncher, revert to WaitingForPuncher
- If only 1 player left, EndMatch

### Test 8: Server validation
- Try firing RE_PunchRequest with fake matchId - should get "Match identity mismatch" or "Not in match"
- Try firing as Target - should get "Target not eligible"
- Try firing when state is Preparing/SelectingTarget - should get "Wrong state"
- Try firing when dead (Humanoid.Health 0) - should get "Player not alive"
- Client never sends winner/timestamp/damage/power/role - check server only uses matchId, validates everything

### Test 9: Target does NOT receive Puncher identity (anti-cheat)
- As Target, check Output for PuncherSelected event: should receive nil (hidden)
- Check RE_MatchStateUpdate payload: should NOT contain puncherUserId field, roles for others should be PotentialPuncher not Puncher
- No warning "[Security] Target received Puncher role" or "contains puncherUserId"

## Expected Results

- WaitingForPuncher state allows PotentialPunchers to request via F or RE_PunchRequest:FireServer(matchId)
- First valid request becomes Puncher, teleported behind Target to PuncherStand, preparation 3s
- Later requests rejected with reason
- Puncher cannot leave >4 studs, enforced by server
- Spam/duplicate handled, rate limit 0.5s
- Puncher disconnect -> back to WaitingForPuncher
- Target invalid -> new Target or EndMatch
- Target never sees who is Puncher (filtered payloads, nil in PuncherSelected)
- Other players see Puncher identity (except Target)
- Server validates all, client only sends Punch request

## Common Errors and Fixes

- RE_PunchRequest not found: Ensure RemoteService creates it, or manually create RemoteEvent in ReplicatedStorage.Remotes
- Can request as Target: Check validatePunchRequest role check, ensure role is PotentialPuncher
- Multiple Punchers selected: Check puncherUserId check before selection, ensure first wins, later rejected. Race condition? Server processes OnServerEvent sequentially, first wins.
- Puncher not moved behind: Check PuncherStand exists, or getPuncherBehindCFrame calculates correctly. Check teleportPuncherBehindTarget success, check arenaModel exists.
- Puncher can freely leave: Check enforce loop running (Heartbeat), check puncherPosition stored, max distance 4, check puncherEnforceConn not disconnected early
- Spam not handled: Check punchRequestCounts tracking, window 2s, threshold 3, cooldown 0.5s
- Puncher disconnect not handled: Check HandlePlayerLeaving clears puncherUserId and reverts state
- Target sees Puncher: Check buildFilteredPayload hides puncherUserId for Target, broadcastPuncherSelected sends nil to Target, check client security warnings
- Client sends extra data: Ensure RE_PunchRequest:FireServer only sends matchId, not winner/timestamp/damage/power/role. Server ignores extra args anyway, only uses matchId and Player.
- Wrong state error: Ensure match is in WaitingForPuncher before requesting, wait for Target selection to finish
- No Puncher selected timeout: After 15s, match ends with "No Puncher selected" - expected, increase PunchSelectionDuration if need longer testing

## Not Implemented (Future)

- Power gauge, damage calculation, guessing phase, knockout, scoring, final GUI, monetization
- Punch animations, hit detection, damage application
- Official Puncher reveal to Target (future Guess phase)
- Final winner determination
