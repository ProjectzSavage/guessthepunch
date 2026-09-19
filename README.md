# Guess the Puncher - Queue System Phase

This phase implements ONLY lobby and queue-slot system for 2,4,6 players. No matches, roles, punching, power, damage, guessing, GUI, rewards.

Fixed previous error: `Constants.luau` now standalone with NO requires to avoid "Module does not return exactly 1 value" yellow underline.

## File Paths (GitHub)

```
src/Shared/
├── Config.luau          - Queue capacities 2,4,6, min 2, countdowns, prep, punch, gauge, guessing, health, damages, KO, lobby return
├── QueueStates.luau     - WAITING, COUNTDOWN_FULL, COUNTDOWN_PARTIAL, LOCKED, STARTING, CANCELLED
├── RemoteNames.luau     - RE_QueueJoinRequest etc.
├── Constants.luau       - Standalone, no requires (fixes error), remote names, tags
├── MatchStates.luau     - Future use
├── Roles.luau           - Future
├── PowerZones.luau      - Future
├── Results.luau         - Future
└── Types.luau           - Future

src/Server/
├── Main.server.luau     - Auto-creates Remotes, validates workspace, inits QueueService
└── Services/
    ├── RemoteService.luau  - EnsureRemote, EnsureAllRemotes
    └── QueueService.luau   - Full queue logic: entry detection, occupancy, prevent multi-join, leave, start when full, start after wait if >=2, cancel if <2, handle reset/death/disconnect, prevent new joins when locked, handoff to MatchManager

src/Client/
└── Main.client.luau     - Test client that prints queue state updates
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
| Main.client.luau | StarterPlayer/StarterPlayerScripts/GuessThePuncherClient | LocalScript |

All names WITHOUT .luau in Studio.

## Required Folders

- ReplicatedStorage/Shared
- ReplicatedStorage/Remotes (auto-created)
- ServerScriptService/Services
- Workspace.Lobby
- Workspace.Lobby.MatchSlots
- Workspace.MatchArenas (you said you will put arenas in folder)

## Slot Hierarchy (Updated - No Spectator Stands, With Chair)

As requested:

```
Slot2 (Model) in Lobby.MatchSlots
├── EntryArea (Part) 6x1x6 Anchored CanCollide false - physical entry
├── LeaveButton (Part) 3x1x3 Anchored CanCollide false + ClickDetector
├── DisplayBoard (Part) 4x6x0.5 + BillboardGui (OccupancyLabel, StatusLabel, CountdownLabel)
├── PlayerSpawns (Folder)
│   ├── Player1 (Part) 3x1x3 Anchored
│   └── Player2 (Part)

Arena2 (Model) in MatchArenas at (0,100,0)
├── TargetStand (Part) 4x1x4 Anchored Red
│   └── Chair (Seat) - target will sit on chair
├── PuncherStand (Part) 4x1x4 Anchored Blue, 6 studs behind TargetStand
└── PlayerSpawns (Folder)
    ├── Player1 (Part)
    └── Player2 (Part)
```

Slot4: Player1..4, Slot6: Player1..6, same for Arena4, Arena6.

No SpectatorStands.

## Command Bar Scripts (No .luau extensions, just names)

- `docs/CommandBar_QueueSystem.txt` - Minimal: creates Shared + Remotes + Services + GuessThePuncherServer ModuleScripts/Scripts with correct names
- `docs/CommandBar_FullQueue.txt` - Full: creates Shared, Remotes, Services, GuessThePuncherServer, plus Workspace.Lobby.MatchSlots.Slot2,4,6 with EntryArea, LeaveButton, DisplayBoard, PlayerSpawns, and Workspace.MatchArenas.Arena2,4,6 with TargetStand+Chair(Seat), PuncherStand, PlayerSpawns

Paste into Studio Command Bar (View > Command Bar) and Enter, then paste code from GitHub into each ModuleScript.

## Verification

In Command Bar after setup:

```lua
local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
print(Config.QueueCapacities.Slot2, Config.MinimumPlayers, Config.Damage.Perfect) -- 2 2 100
local QueueStates = require(Shared.QueueStates)
print(QueueStates.States.WAITING, QueueStates.CanJoin("WAITING")) -- WAITING true
```

Expected: prints without yellow underline errors.

## Queue System Features

- EntryArea Touched with debounce 1s
- Server tracks occupancy
- Prevents joining multiple slots
- Allows leave before LOCKED/STARTING via RE_QueueLeaveRequest or LeaveButton
- Starts when full (5s countdown)
- Starts after 30s wait if >=2 but not full (5s countdown)
- Cancels if <2 remain
- Handles reset/death (keeps in queue, teleports back), disconnect (removes)
- Prevents new joins once countdown starts (locked)
- Handoff to future MatchManager via GetPlayersForMatch() and RE_QueueStarted

See docs/QUEUE_MANUAL_OBJECTS.md and docs/QUEUE_SETUP_GUIDE.md for full instructions.
