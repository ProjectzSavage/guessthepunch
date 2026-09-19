# Match Setup System - Implementation Guide

## Goal
Implement only basic match setup for players accepted from queue. Do not implement punching, power, damage, guessing, knockout, final scoring, GUI, monetization, DataStores.

When queue starts a match:
1. Assign queued players to unique match
2. Move them into correct arena
3. Prevent them from joining another queue
4. Select one player as initial Target server-side
5. Assign all others PotentialPuncher role
6. Place players in designated positions
7. Handle leaving, disconnecting, resetting, dying
8. End safely if <2 active players remain
9. Keep separate matches independent when multiple matches run in one server

Use server-controlled states: Preparing, SelectingTarget, WaitingForPuncher, Punching, Guessing, Resolving, Eliminated, Finished

---

## File Paths (GitHub)

```
src/Shared/
├── Config.luau          - Queue capacities 2,4,6, min 2, countdowns, match prep 3s, selecting target 2s, lobby return 5s, damages future
├── QueueStates.luau     - WAITING, COUNTDOWN_FULL, COUNTDOWN_PARTIAL, LOCKED, STARTING
├── MatchStates.luau     - Preparing, SelectingTarget, WaitingForPuncher, Punching, Guessing, Resolving, Eliminated, Finished
├── Roles.luau           - None, Lobby, Queued, Target, PotentialPuncher, Puncher, Spectator, Eliminated, Winner
├── RemoteNames.luau     - Queue remotes + Match remotes: RE_MatchStart, RE_MatchStateUpdate, RE_MatchEnd, RE_RoleAssigned, RE_TargetSelected
├── Constants.luau       - Standalone, no requires (fixes yellow underline), remote names, tags
└── Types.luau           - Future

src/Server/
├── Main.server.luau     - Auto-creates Remotes, validates workspace, inits MatchService then QueueService
└── Services/
    ├── RemoteService.luau  - EnsureFolder, EnsureRemote, EnsureAllRemotes
    ├── QueueService.luau   - Queue logic + handoff to MatchService via CreateMatchFromQueue, checks IsPlayerInMatch to prevent queue join when in match
    └── MatchService.luau   - NEW: Basic match setup system (this phase)

src/Client/
└── Main.client.luau     - Listens to queue + match events for testing
```

## Studio Destinations

| GitHub | Studio Destination | Type |
|--------|-------------------|------|
| Config.luau | ReplicatedStorage/Shared/Config | ModuleScript |
| QueueStates.luau | ReplicatedStorage/Shared/QueueStates | ModuleScript |
| MatchStates.luau | ReplicatedStorage/Shared/MatchStates | ModuleScript |
| Roles.luau | ReplicatedStorage/Shared/Roles | ModuleScript |
| RemoteNames.luau | ReplicatedStorage/Shared/RemoteNames | ModuleScript |
| Constants.luau | ReplicatedStorage/Shared/Constants | ModuleScript |
| Types.luau | ReplicatedStorage/Shared/Types | ModuleScript |
| RemoteService.luau | ServerScriptService/Services/RemoteService | ModuleScript |
| QueueService.luau | ServerScriptService/Services/QueueService | ModuleScript |
| MatchService.luau | ServerScriptService/Services/MatchService | ModuleScript |
| Main.server.luau | ServerScriptService/GuessThePuncherServer | Script |
| Main.client.luau | StarterPlayer/StarterPlayerScripts/GuessThePuncherClient | LocalScript |

All ModuleScript names WITHOUT .luau extension.

## Required Folders

- ReplicatedStorage/Shared
- ReplicatedStorage/Remotes (auto-created)
- ServerScriptService/Services
- Workspace.Lobby
- Workspace.Lobby.MatchSlots
- Workspace.MatchArenas (you said you will put arenas in folder)

## Manual Setup Instructions

See docs/QUEUE_MANUAL_OBJECTS.md for queue slots and docs/MATCH_ARENA_OBJECTS.md for arenas.

Quick:

1. **Lobby Queue Slots** (from previous phase, should already exist):
   - Workspace.Lobby (Folder) + SpawnLocation + MatchSlots (Folder)
   - Slot2, Slot4, Slot6 Models with EntryArea 6x1x6 Anchored CanCollide false, LeaveButton 3x1x3 + ClickDetector, DisplayBoard 4x6x0.5 + BillboardGui, PlayerSpawns Folder Player1..N

2. **Match Arenas** (required for this phase):
   - Workspace.MatchArenas (Folder)
   - Arena2 at 0,100,0: TargetStand 4x1x4 Red at 0,100,0 + Chair Seat inside at 0,101,0, PuncherStand 4x1x4 Blue at 0,100,6 (6 studs behind), PlayerSpawns Folder Player1 at 5,100,0 Player2 at -5,100,0
   - Arena4 at 200,100,0: TargetStand+Chair at 200,100,0 PuncherStand at 200,100,6 PlayerSpawns Player1..4
   - Arena6 at 400,100,0: TargetStand+Chair at 400,100,0 PuncherStand at 400,100,6 PlayerSpawns Player1..6

3. **ReplicatedStorage:**
   - Shared Folder with 9 ModuleScripts (paste from GitHub src/Shared/)
   - Remotes Folder auto-created by server

4. **ServerScriptService:**
   - Services Folder with RemoteService, QueueService, MatchService ModuleScripts
   - GuessThePuncherServer Script with Main.server.luau code

5. **StarterPlayerScripts:**
   - GuessThePuncherClient LocalScript with Main.client.luau code

## Copy Instructions

### Option 1: Manual

- Create Folder/Shared, create ModuleScript named Config, open GitHub src/Shared/Config.luau, copy all, paste, repeat for all Shared files
- Create Folder Services in ServerScriptService, create ModuleScripts RemoteService, QueueService, MatchService, paste from GitHub
- Create Script GuessThePuncherServer in ServerScriptService, paste Main.server.luau
- Create LocalScript GuessThePuncherClient in StarterPlayerScripts, paste Main.client.luau

### Option 2: Command Bar

Use `docs/CommandBar_FullQueue.txt` for queue slots + arenas physical objects (EntryArea, Chair Seat, etc.)

Use `docs/CommandBar_QueueSystem.txt` for Shared + Services ModuleScripts (no code, just names)

Use `docs/CLAUDE_MASTER_SCRIPT.lua` for full auto with code (for Claude MCP) - creates all folders and scripts with full code, no .luau extensions

Then paste code from GitHub into each ModuleScript if using minimal command bar scripts.

### Updated Command Bar for Match Setup:

See `docs/CommandBar_MatchSetup.txt` - creates MatchService ModuleScript + ensures Match remotes + arenas with Chair

```lua
-- Paste into Command Bar:
local ServerScriptService = game:GetService("ServerScriptService")
local servicesFolder = ServerScriptService:FindFirstChild("Services") or Instance.new("Folder")
servicesFolder.Name = "Services"
servicesFolder.Parent = ServerScriptService
if not servicesFolder:FindFirstChild("MatchService") then
    local m = Instance.new("ModuleScript")
    m.Name = "MatchService"
    m.Parent = servicesFolder
    print("Created Services/MatchService - now paste code from GitHub src/Server/Services/MatchService.luau")
end
-- Ensure match remotes
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotesFolder.Name = "Remotes"
remotesFolder.Parent = ReplicatedStorage
for _, name in ipairs({"RE_MatchStart","RE_MatchStateUpdate","RE_MatchEnd","RE_RoleAssigned","RE_TargetSelected"}) do
    if not remotesFolder:FindFirstChild(name) then
        local re = Instance.new("RemoteEvent")
        re.Name = name
        re.Parent = remotesFolder
        print("Created Remotes/"..name)
    end
end
```

## Multiplayer Testing Instructions

### Test 1: Queue -> Match Handoff (2 players)

1. Start test with 1 server + 2 clients (Test tab > Clients and Servers)
2. Client1 touches Slot2 EntryArea -> joins, teleported to PlayerSpawns/Player1
3. Client2 touches Slot2 EntryArea -> joins, 2/2, COUNTDOWN_FULL 5s starts, locked true
4. After 5s countdown:
   - Expected: Queue finishes, MatchService.CreateMatchFromQueue called
   - Server prints: `[MatchService] Creating match Slot2_XXXXX from queue Slot2 with 2 players, arena Arena2`
   - Server prints: `Match Slot2_XXXXX Target selected: UserId, 1 PotentialPunchers`
   - Both clients teleported to Arena2 at 0,100,0: Target to TargetStand+Chair (sits), other to PlayerSpawns
   - Client prints: `[Match] Start matchId=Slot2_XXXXX arena=Arena2 players=2`
   - Client prints: `[Match] StateUpdate state=Preparing -> SelectingTarget -> WaitingForPuncher`
   - Client prints: `[Match] Your role: Target` or `PotentialPuncher`
5. Check: Players cannot join another queue while in match - Client1 tries to touch Slot4 EntryArea -> should fail "Already in a match"

### Test 2: Independent Matches

1. Start with 1 server + 4 clients
2. Client1+Client2 join Slot2 -> countdown -> match in Arena2
3. Client3+Client4 join Slot4 -> countdown -> match in Arena4 at 200,100,0
4. Expected: Two separate matches running independent:
   - MatchService.Matches contains 2 entries with different matchIds
   - Arena2 has 2 players, Arena4 has 2 players, far apart (0,100,0 vs 200,100,0)
   - Each match has its own Target selected server-side random
   - Server prints for both matches without mixing

### Test 3: Handle Leaving During Match

1. 2 clients in Slot2 -> match starts in Arena2, Target selected
2. Client2 (PotentialPuncher) leaves game (Stop client or PlayerRemoving)
3. Expected: Server prints `[MatchService] Player UserId leaving match Slot2_XXXXX reason=Disconnected`, activePlayers becomes 1, since <2, match ends: `[MatchService] Ending match ... reason=Not enough players`, both (remaining) teleported back to lobby, match cleaned up, queue slot released

### Test 4: Handle Target Leaving

1. 3 clients join Slot4 -> match in Arena4, Target selected (e.g., Client1 is Target)
2. Client1 (Target) leaves
3. Expected: Server prints Target left, selects new target from remaining, reassigns roles, teleports new target to TargetStand+Chair

### Test 5: Handle Reset/Death

1. 2 clients in match Arena2, Target sitting on Chair
2. Client1 (Target) presses Reset button or dies
3. Expected: Character respawns after 5s, kept in match, teleported back to TargetStand+Chair, still Target role
4. Check: Match does not end, activePlayers still 2

### Test 6: Prevent Queue Join When In Match

1. Client1 in match Arena2
2. Client1 tries to join Slot4 via EntryArea or RemoteEvent RE_QueueJoinRequest
3. Expected: Rejected "Already in a match, cannot join queue"

### Test 7: End Safely If <2 Remain

1. 2 clients in match
2. One disconnects
3. Expected: Match ends safely, state Finished, RE_MatchEnd fires, players teleported to lobby, arena released, queue slot released, no errors

## Expected Results

- Queue finishes -> MatchService creates unique matchId e.g., Slot2_123456_123456789
- Players assigned to unique match (MatchService.Matches[matchId] contains players)
- Moved into correct arena: Slot2->Arena2 at 0,100,0, Slot4->Arena4 at 200,100,0, Slot6->Arena6 at 400,100,0
- Cannot join another queue while in match (checked via MatchService.IsPlayerInMatch)
- Initial Target selected server-side random (math.random, never trusts client)
- Others assigned PotentialPuncher role
- Placed in designated positions: Target to TargetStand+Chair Seat (sits), others to PlayerSpawns
- Leaving/disconnecting removes from match, if <2 ends match safely with Finished state, teleports back to lobby
- Reset/death keeps in match, teleports back after respawn
- Separate matches independent: Matches table has separate entries, ArenasInUse tracks, no shared state, multiple matches can run in one server at different arenas
- States: Preparing (teleporting) -> SelectingTarget (2s) -> WaitingForPuncher (setup complete, ready for future punching) -> Finished (when <2 or ended)

## Common Errors and Fixes

- **"Missing arena model: Arena2"**: Create Workspace.MatchArenas.Arena2 Model with TargetStand, TargetStand/Chair Seat, PuncherStand, PlayerSpawns per MATCH_ARENA_OBJECTS.md
- **"Missing TargetStand.Chair (Seat)"**: Inside TargetStand Part, insert Seat object (not Part), Name Chair, Size 2,1,2 Anchored true at 1 stud above TargetStand. Target will sit via Seat:Sit(Humanoid)
- **"Arena already in use" warning**: If you start two Slot2 matches, both try to use Arena2. For true physical independence, create more arenas (Arena2_2) or wait for first match to finish. Logical independence is kept (separate matchIds), but physical sharing will cause players to see each other. Fix: create additional arenas or ensure only one match per arena type at a time.
- **Player not teleported to arena**: Check PlayerSpawns folder exists with Parts named Player1, Player2 etc., Anchored true. Check Config.TeleportOffsetY.
- **Target not sitting on Chair**: Chair must be Seat object, Anchored true, CanCollide true. Server uses chair:Sit(humanoid) in pcall. If fails, character still at TargetStand CFrame, which is okay. Check that Humanoid exists.
- **Player can still join queue while in match**: Ensure MatchService.IsPlayerInMatch check added to QueueService.TryJoinSlot - updated in this phase. If still can join, ensure MatchService initialized before QueueService (Main.server does MatchService first).
- **Match not ending when <2 remain**: Check Config.MatchMinPlayers=2, and HandlePlayerLeaving checks activePlayers < min then EndMatch. Check server output for "Ending match".
- **Matches not independent**: Check MatchService.Matches table has separate entries. Each match has its own matchId, arenaName, players, state. No global shared state except PlayersInMatch and ArenasInUse which are maps.
- **Remotes not found**: Server auto-creates RE_MatchStart, RE_MatchStateUpdate, RE_MatchEnd, RE_RoleAssigned, RE_TargetSelected. If client says missing, wait 1s after server start.
- **Yellow underline "Module does not return exactly 1 value"**: Fixed - Constants standalone no requires. Ensure all ModuleScripts return exactly one table.

## What Is NOT Implemented

- No punching, power gauge, damage, guessing, knockout, final scoring, GUI, monetization, DataStores
- Match stops at WaitingForPuncher state - future systems will handle Punching, Guessing, Resolving, Eliminated

Future MatchManager handoff is ready: QueueService calls MatchService.CreateMatchFromQueue, MatchService handles setup, future punching system will start from WaitingForPuncher.

