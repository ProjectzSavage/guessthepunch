# Queue System Setup Guide

## Goal
Implement only lobby and queue-slot system for 2,4,6 players with all requirements.

---

## What This Phase Does

- Tracks occupancy on server
- Detects EntryArea Touched with debounce
- Prevents joining multiple slots
- Allows leave before match begins (via RemoteEvent or LeaveButton ClickDetector)
- Starts when full (countdown 5s)
- Starts after waiting period if >=2 but not full (wait 30s, then countdown 5s)
- Cancels if <2 remain
- Handles reset, death, disconnect (keeps in queue on death, teleports back on respawn, removes on disconnect)
- Prevents new joins once queue starts (locked during countdown)
- Prepares clean handoff to future MatchManager via GetPlayersForMatch() and ReleaseSlot() and RE_QueueStarted event

## What It Does NOT Do

- No match logic, roles, punching, power gauge, damage, guessing, KO, GUI, rewards

---

## File Paths (GitHub)

```
src/Shared/
├── Config.luau          - Queue capacities 2,4,6, min 2, countdowns, preparation, punch, gauge, guessing, health, damages, KO, lobby return
├── QueueStates.luau     - WAITING, COUNTDOWN_FULL, COUNTDOWN_PARTIAL, LOCKED, STARTING, CANCELLED
├── RemoteNames.luau     - RE_QueueJoinRequest etc.
├── Constants.luau       - Standalone, no requires (fixed yellow underline error)
├── MatchStates.luau     - Future use
├── Roles.luau           - Future
├── PowerZones.luau      - Future
├── Results.luau         - Future
└── Types.luau           - Future

src/Server/
├── Main.server.luau     - Auto-creates Remotes, validates workspace, inits QueueService
└── Services/
    ├── RemoteService.luau  - EnsureRemote, EnsureAllRemotes
    └── QueueService.luau   - Full queue logic
```

## Studio Destinations

| GitHub | Studio | Type |
|--------|--------|------|
| Config.luau | ReplicatedStorage/Shared/Config | ModuleScript |
| QueueStates.luau | ReplicatedStorage/Shared/QueueStates | ModuleScript |
| RemoteNames.luau | ReplicatedStorage/Shared/RemoteNames | ModuleScript |
| Constants.luau | ReplicatedStorage/Shared/Constants | ModuleScript |
| MatchStates.luau | ReplicatedStorage/Shared/MatchStates | ModuleScript |
| Roles.luau | ReplicatedStorage/Shared/Roles | ModuleScript |
| PowerZones.luau | ReplicatedStorage/Shared/PowerZones | ModuleScript |
| Results.luau | ReplicatedStorage/Shared/Results | ModuleScript |
| Types.luau | ReplicatedStorage/Shared/Types | ModuleScript |
| RemoteService.luau | ServerScriptService/Services/RemoteService | ModuleScript |
| QueueService.luau | ServerScriptService/Services/QueueService | ModuleScript |
| Main.server.luau | ServerScriptService/GuessThePuncherServer | Script |

All ModuleScript names WITHOUT .luau extension in Studio.

## Required Folders

- ReplicatedStorage/Shared
- ReplicatedStorage/Remotes (auto-created)
- ServerScriptService/Services
- Workspace.Lobby
- Workspace.Lobby.MatchSlots
- Workspace.MatchArenas (you said you will put arenas in folder)

## Manual Setup Instructions

See docs/QUEUE_MANUAL_OBJECTS.md for exact hierarchy including Chair inside TargetStand.

Quick version:

1. Create Workspace.Lobby (Folder) + SpawnLocation + MatchSlots (Folder)
2. Create Slot2, Slot4, Slot6 Models inside MatchSlots with:
   - EntryArea (Part) 6x1x6 Anchored CanCollide false Transparency 0.3
   - LeaveButton (Part) 3x1x3 Anchored CanCollide false + ClickDetector or ProximityPrompt
   - DisplayBoard (Part) 4x6x0.5 + BillboardGui with OccupancyLabel, StatusLabel, CountdownLabel
   - PlayerSpawns (Folder) with Player1..N Parts 3x1x3 Anchored
3. Create Workspace.MatchArenas (Folder) + Arena2, Arena4, Arena6 Models at far positions (0,100,0), (200,100,0), (400,100,0) each with:
   - TargetStand (Part) 4x1x4 + Chair (Seat) inside TargetStand
   - PuncherStand (Part) 4x1x4 6 studs behind TargetStand
   - PlayerSpawns Folder Player1..N
4. Create ReplicatedStorage/Shared Folder
5. Create ServerScriptService/Services Folder
6. Use Command Bar script to create ModuleScripts, then paste code

## Copy Instructions

### Option 1: Manual Paste

- Open GitHub file, copy all
- In Studio, create ModuleScript with exact name (no .luau), paste

### Option 2: Command Bar (Recommended)

See docs/CommandBar_QueueSystem.txt - paste into Command Bar (View > Command Bar) and Enter. It creates all folders and ModuleScripts with correct names (no extensions). Then paste code from GitHub into each.

**Command Bar Script for Queue System:**

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

-- Shared
local sharedFolder = ReplicatedStorage:FindFirstChild("Shared") or Instance.new("Folder")
sharedFolder.Name = "Shared"
sharedFolder.Parent = ReplicatedStorage
for _, name in ipairs({"Config","QueueStates","RemoteNames","Constants","MatchStates","Roles","PowerZones","Results","Types"}) do
    if not sharedFolder:FindFirstChild(name) then
        local m = Instance.new("ModuleScript")
        m.Name = name
        m.Parent = sharedFolder
        print("Created Shared/"..name)
    end
end

-- Remotes (auto-created by server, but create folder)
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotesFolder.Name = "Remotes"
remotesFolder.Parent = ReplicatedStorage

-- Services
local servicesFolder = ServerScriptService:FindFirstChild("Services") or Instance.new("Folder")
servicesFolder.Name = "Services"
servicesFolder.Parent = ServerScriptService
for _, name in ipairs({"RemoteService","QueueService"}) do
    if not servicesFolder:FindFirstChild(name) then
        local m = Instance.new("ModuleScript")
        m.Name = name
        m.Parent = servicesFolder
        print("Created Services/"..name)
    end
end

if not ServerScriptService:FindFirstChild("GuessThePuncherServer") then
    local s = Instance.new("Script")
    s.Name = "GuessThePuncherServer"
    s.Parent = ServerScriptService
    print("Created GuessThePuncherServer")
end

-- Workspace
local lobby = Workspace:FindFirstChild("Lobby") or Instance.new("Folder")
lobby.Name = "Lobby"
lobby.Parent = Workspace

local matchSlots = lobby:FindFirstChild("MatchSlots") or Instance.new("Folder")
matchSlots.Name = "MatchSlots"
matchSlots.Parent = lobby

local arenas = Workspace:FindFirstChild("MatchArenas") or Instance.new("Folder")
arenas.Name = "MatchArenas"
arenas.Parent = Workspace

print("Done! Now paste code from GitHub src/Shared/ and src/Server/ into ModuleScripts")
```

Full hierarchy with EntryArea, Chair, PlayerSpawns is in docs/CommandBar_FullQueue.txt

## Multiplayer Testing Instructions

### Test 1: Single Player Join

1. Play with 1 client (F5)
2. Walk character onto Slot2 EntryArea
3. Expected: Output "[QueueService] Touched Slot2 by PlayerName -> true (Joined Slot2)", Billboard shows "1/2 WAITING", character teleported to PlayerSpawns/Player1
4. Check ReplicatedStorage.Remotes.RE_QueueStateUpdate fired (client prints if you have test listener)

### Test 2: Prevent Multiple Slots

1. Test with 1 server + 2 clients (Test tab > Clients and Servers > 2 clients > Start)
2. Client1 touches Slot2 EntryArea -> joins
3. Client1 touches Slot4 EntryArea -> should fail "Already in slot Slot2, leave first"
4. Expected: Client1 remains in Slot2, Slot4 occupancy 0

### Test 3: Leave Before Match

1. Client1 in Slot2
2. Client1 touches LeaveButton (ClickDetector) OR fires RemoteEvent RE_QueueLeaveRequest via Command Bar: `game.ReplicatedStorage.Remotes.RE_QueueLeaveRequest:FireServer()`
3. Expected: Leaves slot, teleported back to lobby SpawnLocation, Billboard 0/2

### Test 4: Start When Full (2 players)

1. 2 clients, both touch Slot2 EntryArea
2. Expected: Slot2 occupancy 2/2, state changes to COUNTDOWN_FULL, countdown 5 seconds, locked=true, no new joins allowed
3. After 5s: state LOCKED then STARTING, RE_QueueStarted fires with 2 players, after LobbyReturnDelay (5s) slot resets to 0/2 WAITING

### Test 5: Start After Waiting Period If >=2 But Not Full

1. 2 clients join Slot6 (capacity 6, only 2 players)
2. Wait 30 seconds (QueuePartialWaitTime)
3. Expected: After 30s, starts COUNTDOWN_PARTIAL 5s, then STARTING
4. During waiting, Billboard shows "Waiting Xs for more"

### Test 6: Cancel If <2 Remain

1. 2 clients join Slot2, countdown starts (full)
2. One client leaves before countdown finishes
3. Expected: Countdown cancelled, state back to WAITING, locked false, Billboard shows WAITING, remaining player still in slot

### Test 7: Handle Reset, Death, Disconnect

- **Death:** Kill character (Reset button or `Humanoid.Health=0`), character respawns after 5s, should be teleported back to PlayerSpawns/PlayerX, still in queue
- **Reset:** Press Reset button in game, same as death
- **Disconnect:** Stop one client, PlayerRemoving should remove from slot, occupancy decreases, if <2 cancel countdown

### Test 8: Prevent New Joins Once Queue Starts

1. 2 clients join Slot2, countdown starts, locked true
2. Third client tries to join Slot2
3. Expected: Rejected "Slot locked, countdown active, cannot join"

### Test 9: Clean Handoff to Future MatchManager

1. After countdown finishes, check Server Output: "[QueueService] Queue finished for Slot2, 2 players ready for MatchManager handoff"
2. Check that QueueService.PendingMatches[Slot2] contains players
3. Call from Command Bar (Server): `require(game.ServerScriptService.Services.QueueService).GetPlayersForMatch("Slot2")` should return {userId1, userId2}
4. Call `ReleaseSlot("Slot2")` should reset slot

## Expected Results

- EntryArea Touched works with debounce 1s
- Occupancy tracked server-side, never trusts client
- BillboardGui updates occupancy and status
- State machine: WAITING -> COUNTDOWN_FULL/PARTIAL -> LOCKED -> STARTING -> WAITING (after reset)
- No player can be in multiple slots
- Leave works before LOCKED
- Full slot starts in 5s, partial with >=2 starts after 30s wait + 5s countdown
- Cancel when <2
- Death keeps in queue, disconnect removes
- Locked prevents new joins
- RE_QueueStarted fires with player list for future MatchManager

## Common Errors and Fixes

- **"Missing Workspace.Lobby.MatchSlots.Slot2.EntryArea"**: Create Part named EntryArea inside Slot2 Model, Anchored true, CanCollide false
- **"Module does not return exactly 1 value" yellow underline**: Fixed in this version - Constants.luau now standalone with no requires. Ensure all ModuleScripts return exactly one table at end. If you created ModuleScripts via old Command Bar script that had empty source, paste code from GitHub.
- **Touched not firing**: EntryArea CanCollide false but must have Anchored true, and character must touch with HumanoidRootPart or foot. Ensure EntryArea size 6,1,6 and positioned at ground level (Y=3). Also check debounce - wait 1s between touches.
- **Player not teleported to PlayerSpawns**: Check PlayerSpawns folder exists and contains Parts named Player1, Player2 etc., Anchored true. Check Config.TeleportOffsetY.
- **Countdown not starting**: Check Config.MinimumPlayers=2, ensure occupancy >=2. Check that waitStartTick is set. Look at server output for "[QueueService] Countdown started"
- **LeaveButton not working**: Ensure LeaveButton has ClickDetector or ProximityPrompt, and you have script to fire RE_QueueLeaveRequest on click, OR just use Command Bar to fire leave request for testing. QueueService also handles leave via RemoteEvent, not via button Touched.
- **Remotes not found**: Server auto-creates Remotes folder and 7 queue remotes. If client says missing, wait a second after server starts, or check ReplicatedStorage.Remotes exists.
- **Player stuck in multiple slots**: Should not happen - TryJoin checks existing slot. If it does, call LeaveSlot first or restart server.
- **Chair not working**: Chair must be Seat object, not Part. Insert Seat, name Chair, parent to TargetStand, Anchored true, Position slightly above TargetStand. Future: use Seat:Sit(Humanoid) to sit target.

## What Is NOT Implemented

- No match logic, roles, punching, power gauge, damage, guessing, KO, GUI, rewards
- Only queue system

Future MatchManager will use QueueService.GetPlayersForMatch() and ReleaseSlot()
