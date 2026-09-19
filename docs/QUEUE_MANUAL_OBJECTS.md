# Queue System - Exact Manual Roblox Objects Required

## Overview
Implement only lobby and queue-slot system for 2,4,6 players. No match logic yet.

As requested, slot hierarchy includes TargetStand, PuncherStand, PlayerSpawns, and Chair where target will sit.

We keep arena as you said you will put arenas in a folder.

---

## 1. Workspace.Lobby

**Path:** Workspace > Lobby (Folder)
- Create: Right-click Workspace -> Insert Object -> Folder -> Name `Lobby`
- Properties: No special properties

### 1a. Workspace.Lobby.SpawnLocation

- Inside Lobby, insert SpawnLocation
- Name: `SpawnLocation`
- Properties:
  - Anchored: true (default)
  - CanCollide: true
  - Size: 6,1,6 or default
  - Position: (0,3,0) or wherever you want lobby spawn
  - Neutral: true
  - AllowTeamChangeOnTouch: false

### 1b. Workspace.Lobby.MatchSlots

- Inside Lobby, Folder named `MatchSlots`

---

## 2. Queue Slots (Lobby) - 2,4,6 Players

Inside `Workspace.Lobby.MatchSlots`, create 3 Models:

### Slot2 (Model) - 2 players queue

- **Name:** `Slot2`
- **Attributes:**
  - String Attribute `SlotId` = "Slot2"
  - Number Attribute `MaxPlayers` = 2 (optional, Config overrides)
- **Children:**

  1. **EntryArea** (Part) - Physical entry area to detect joining
     - Name: `EntryArea` (also accepts old name `TouchBlock` for backward compat)
     - Size: 6,1,6
     - Anchored: true
     - CanCollide: false
     - Transparency: 0.3
     - Color: Bright blue (optional)
     - Material: ForceField or Neon
     - Position: e.g., (0,3,0) in lobby
     - Tag: `QueueEntry` (CollectionService Tag, optional)

  2. **LeaveButton** (Part) - Allows leaving before match begins
     - Name: `LeaveButton`
     - Size: 3,1,3
     - Anchored: true
     - CanCollide: false
     - Color: Bright red
     - Position: near EntryArea, e.g., (0,3,5)
     - Insert: ClickDetector or ProximityPrompt
       - If ProximityPrompt: ActionText="Leave Queue", ObjectText="Queue", HoldDuration=0, MaxActivationDistance=10
     - This is optional - players can also leave via RemoteEvent from future GUI

  3. **DisplayBoard** (Part) - Shows occupancy
     - Name: `DisplayBoard`
     - Size: 4,6,0.5
     - Anchored: true
     - Position: above EntryArea, e.g., (0,8,0)
     - Insert BillboardGui:
       - Name: `BillboardGui`
       - Size: {0,200},{0,150}
       - StudsOffset: 0,3,0
       - AlwaysOnTop: true
       - Inside BillboardGui:
         - TextLabel `OccupancyLabel`: Text="0/2", Size {1,0},{0.3,0}, Position {0,0},{0,0}, TextScaled true
         - TextLabel `StatusLabel`: Text="WAITING", Size {1,0},{0.3,0}, Position {0,0},{0.3,0}, TextScaled true
         - TextLabel `CountdownLabel`: Text="", Size {1,0},{0.4,0}, Position {0,0},{0.6,0}, TextScaled true

  4. **PlayerSpawns** (Folder)
     - Name: `PlayerSpawns`
     - Inside:
       - **Player1** (Part): Name Player1, Size 3,1,3, Anchored true, Position (-10,0.5,-10)
       - **Player2** (Part): Name Player2, Size 3,1,3, Anchored true, Position (-6,0.5,-10)

### Slot4 (Model) - 4 players queue

- Name: `Slot4`, Attribute SlotId="Slot4", MaxPlayers=4
- EntryArea at (20,3,0) Size 6,1,6 Anchored true CanCollide false
- LeaveButton at (20,3,5)
- DisplayBoard at (20,8,0) with BillboardGui
- PlayerSpawns Folder with 4 Parts:
  - Player1 (-10,0.5,10) etc, or arrange in circle
  - Player2, Player3, Player4

### Slot6 (Model) - 6 players queue

- Name: `Slot6`, SlotId="Slot6", MaxPlayers=6
- EntryArea at (40,3,0)
- LeaveButton at (40,3,5)
- DisplayBoard at (40,8,0)
- PlayerSpawns with 6 Parts Player1..Player6

---

## 3. Workspace.MatchArenas (You said you will put arenas in a folder)

**Path:** Workspace > MatchArenas (Folder)
- Create Folder `MatchArenas` in Workspace
- This folder holds actual match arenas where future matches will happen
- For queue phase, we only validate existence, but you should create as per hierarchy below

### Arena2 (Model) at (0,100,0) - far from lobby to avoid interference

- Name: `Arena2`
- Position: Move model to (0,100,0) - select model, set PrimaryPart or move all parts
- Children:
  - **TargetStand** (Part)
    - Name: `TargetStand`
    - Size: 4,1,4
    - Anchored: true
    - CanCollide: true
    - Color: Really red
    - Position: (0,100,0)
    - Orientation: 0,0,0 (facing -Z)
    - Tag: `TargetStand`
    - Inside TargetStand:
      - **Chair** (Seat) - Target will sit on chair as requested
        - Insert Object -> Seat (not Part, Seat object)
        - Name: `Chair`
        - Size: 2,1,2
        - Anchored: true (for static seat, set true)
        - CanCollide: true
        - Position: slightly above TargetStand, e.g., (0,101,0) or 0,1,0 relative
        - Properties: Disabled=false, Sit auto?
  - **PuncherStand** (Part)
    - Name: `PuncherStand`
    - Size: 4,1,4
    - Anchored: true
    - Color: Really blue
    - Position: 6 studs behind TargetStand = (0,100,6) if TargetStand at (0,100,0) facing -Z
    - Orientation: same as TargetStand
    - Tag: `PuncherStand`
  - **PlayerSpawns** (Folder)
    - Name: `PlayerSpawns`
    - Player1 (Part) Size 3,1,3 Anchored true at (5,100,0)
    - Player2 (Part) Size 3,1,3 Anchored true at (-5,100,0)

### Arena4 (Model) at (200,100,0)

- Name: `Arena4`
- TargetStand at (200,100,0) with Chair Seat inside
- PuncherStand at (200,100,6)
- PlayerSpawns: Player1..4

### Arena6 (Model) at (400,100,0)

- Name: `Arena6`
- TargetStand at (400,100,0) with Chair
- PuncherStand at (400,100,6)
- PlayerSpawns: Player1..6

**Chair details:**
- Use `Seat` object, not `VehicleSeat`
- Seat properties: Anchored=true for static, CanCollide=true
- Position: On top of TargetStand, so character sits facing forward
- For R15, Seat will automatically sit character
- Future: When target is selected, teleport target to TargetStand and sit them on Chair via `Seat:Sit(Humanoid)`

---

## 4. ReplicatedStorage

### ReplicatedStorage.Shared (Folder)
- Create Folder `Shared`
- Inside, you will copy ModuleScripts from GitHub src/Shared/
- Required for this phase:
  - Config
  - QueueStates
  - RemoteNames
  - Constants
  - MatchStates (optional future)
  - Roles, PowerZones, Results, Types (optional future)

### ReplicatedStorage.Remotes (Folder)
- Auto-created by server Main.server.luau if missing (as requested)
- Contains 7 queue remotes + future remotes
- Exact names:
  - RE_QueueJoinRequest
  - RE_QueueLeaveRequest
  - RE_QueueStateUpdate
  - RE_QueueCountdownUpdate
  - RE_QueueLocked
  - RE_QueueStarted
  - RE_QueuePlayerLeft
  - Plus future: RE_MatchStart, RE_MatchStateUpdate, etc.

---

## 5. ServerScriptService

### ServerScriptService.Services (Folder)
- Create Folder `Services`
- Inside, ModuleScripts:
  - RemoteService
  - QueueService

### ServerScriptService.GuessThePuncherServer (Script)
- Create Script (not ModuleScript) named `GuessThePuncherServer`
- Paste from src/Server/Main.server.luau

---

## 6. StarterPlayer

### StarterPlayerScripts (no client logic needed for queue phase, but for testing)
- For this phase, no client files required, but you can create placeholder LocalScript for testing prints

---

## 7. Summary Checklist

- [ ] Workspace.Lobby (Folder)
- [ ] Workspace.Lobby.SpawnLocation (SpawnLocation)
- [ ] Workspace.Lobby.MatchSlots (Folder)
- [ ] Workspace.Lobby.MatchSlots.Slot2 (Model) with EntryArea, LeaveButton, DisplayBoard+BillboardGui, PlayerSpawns/Player1,Player2
- [ ] Workspace.Lobby.MatchSlots.Slot4 with EntryArea, DisplayBoard, PlayerSpawns/Player1..4
- [ ] Workspace.Lobby.MatchSlots.Slot6 with EntryArea, DisplayBoard, PlayerSpawns/Player1..6
- [ ] Workspace.MatchArenas (Folder)
- [ ] Workspace.MatchArenas.Arena2 with TargetStand+Chair(Seat), PuncherStand (6 studs behind), PlayerSpawns/Player1,Player2
- [ ] Workspace.MatchArenas.Arena4 with TargetStand+Chair, PuncherStand, PlayerSpawns/Player1..4
- [ ] Workspace.MatchArenas.Arena6 with TargetStand+Chair, PuncherStand, PlayerSpawns/Player1..6
- [ ] ReplicatedStorage.Shared (Folder) with 7 ModuleScripts
- [ ] ReplicatedStorage.Remotes (Folder) auto-created
- [ ] ServerScriptService.Services (Folder) with RemoteService, QueueService
- [ ] ServerScriptService.GuessThePuncherServer (Script)

No spectator stands anywhere as requested.

