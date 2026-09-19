# Manual Objects - Updated (No Spectator Stands, New Slot Hierarchy)

As requested, hierarchy inside Slot is:

```
Slot
├── TargetStand
├── PuncherStand
├── PlayerSpawns
│   ├── Player1
│   └── Player2
├── TouchBlock (for lobby queue slots)
└── DisplayBoard (for lobby queue slots)
```

No SpectatorStands folder.

---

## Workspace.Lobby.MatchSlots (Queue Slots)

**Path:** Workspace > Lobby (Folder) > MatchSlots (Folder)

### Slot2
- **Model** Name: `Slot2`, Attribute `SlotId` = "Slot2"
  - **TouchBlock** (Part): Size 6,1,6, Anchored true, CanCollide false, Transparency 0.2, Position in lobby e.g. (0,3,0)
  - **DisplayBoard** (Part): Size 4,6,0.5, Anchored true, Position above TouchBlock
    - Insert BillboardGui with TextLabels OccupancyLabel "0/2" and CountdownLabel
  - **TargetStand** (Part): Size 4,1,4, Anchored true, Color Red, Position e.g. (-10,0.5,20) - this is where Target stands during match if you use lobby slots as arena, or leave for arena version
  - **PuncherStand** (Part): Size 4,1,4, Anchored true, Color Blue, Position 6 studs behind TargetStand e.g. (-10,0.5,26)
  - **PlayerSpawns** (Folder)
    - **Player1** (Part): Size 3,1,3, Anchored true, Position (-12,0.5,10)
    - **Player2** (Part): Size 3,1,3, Anchored true, Position (-8,0.5,10)

### Slot4
- Model `Slot4`, SlotId="Slot4"
  - TouchBlock at (20,3,0)
  - DisplayBoard
  - TargetStand, PuncherStand (6 studs behind)
  - PlayerSpawns: Player1, Player2, Player3, Player4 (4 parts)

### Slot6
- Model `Slot6`, SlotId="Slot6"
  - TouchBlock at (40,3,0)
  - DisplayBoard
  - TargetStand, PuncherStand
  - PlayerSpawns: Player1..Player6

---

## Workspace.MatchArenas (Match Arenas) - As you said you will put arenas in a folder

**Path:** Workspace > MatchArenas (Folder)

You said you will put arenas in a folder - create Folder `MatchArenas` in Workspace.

Inside, create 3 Models with SAME hierarchy (no TouchBlock/DisplayBoard needed, only match stands):

### Arena2 (Model) at (0,100,0) far from lobby
- **TargetStand** (Part): Size 4,1,4, Anchored true, Position (0,100,0), Orientation 0,0,0 (facing -Z)
- **PuncherStand** (Part): Size 4,1,4, Anchored true, Position (0,100,6) = 6 studs behind TargetStand, Same Orientation
- **PlayerSpawns** (Folder)
  - Player1 at (5,100,0) Size 3,1,3 Anchored
  - Player2 at (-5,100,0)

### Arena4 (Model) at (200,100,0)
- TargetStand at (200,100,0)
- PuncherStand at (200,100,6)
- PlayerSpawns: Player1..4 around

### Arena6 (Model) at (400,100,0)
- TargetStand at (400,100,0)
- PuncherStand at (400,100,6)
- PlayerSpawns: Player1..6

**Why 6 studs behind?** Puncher moves behind Target to punch, Target in first-person cannot see behind, plus we make puncher invisible to Target client for anti-exploit.

---

## Properties Summary

| Object | Anchored | CanCollide | Size | Notes |
|--------|----------|------------|------|-------|
| TouchBlock | true | false | 6,1,6 | Queue join trigger |
| DisplayBoard | true | true | 4,6,0.5 | Holds BillboardGui |
| TargetStand | true | true | 4,1,4 | Red, target position |
| PuncherStand | true | true | 4,1,4 | Blue, 6 studs behind TargetStand |
| PlayerSpawns/PlayerX | true | true | 3,1,3 | General spawns for all players before role assigned |

All Stands should have Attribute or Tag for future CollectionService if needed, but not required for Phase 1.

---

## ReplicatedStorage

- **Shared** (Folder) - contains ModuleScripts Config, MatchStates, Roles, PowerZones, Results, Types, Constants
- **Remotes** (Folder) - auto-created later, not needed for Phase 1 shared config only

---

## ServerScriptService & StarterPlayer

No objects needed for this phase (only Shared). For future, you'll create Services and Controllers folders.

---

## StarterGui

No GUI needed for this phase.

---

## Verification

After creating, in Explorer you should see:

```
Workspace.Lobby.MatchSlots.Slot2.TargetStand
Workspace.Lobby.MatchSlots.Slot2.PuncherStand
Workspace.Lobby.MatchSlots.Slot2.PlayerSpawns.Player1
Workspace.Lobby.MatchSlots.Slot2.PlayerSpawns.Player2
Workspace.MatchArenas.Arena2.TargetStand
Workspace.MatchArenas.Arena2.PuncherStand
Workspace.MatchArenas.Arena2.PlayerSpawns.Player1
...
```

No SpectatorStands anywhere.

