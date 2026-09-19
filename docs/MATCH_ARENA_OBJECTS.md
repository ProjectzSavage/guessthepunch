# Match Arena - Exact Manual Objects Required (Match Setup Phase)

## Overview
For basic match setup system: when queue starts a match, assign queued players to unique match, move to correct arena, prevent joining another queue, select Target server-side, assign PotentialPuncher, place in positions, handle leaving/disconnect/reset/dying, end if <2 remain, keep matches independent.

---

## Required Manual Arena Objects

### Workspace.MatchArenas (Folder)

**Path:** Workspace > MatchArenas (Folder)
- Create: Right-click Workspace -> Insert Object -> Folder -> Name `MatchArenas`
- This is where you put arenas as you said

### Arena2 (Model) - For 2 players - at (0,100,0) far from lobby

- **Name:** `Arena2`
- **PrimaryPart:** Set to TargetStand if possible (for moving whole model)
- **Position:** Move entire model to (0,100,0) - select all parts inside and move, or set model PrimaryPart CFrame
- **Children:**

  1. **TargetStand** (Part)
     - Name: `TargetStand`
     - Size: 4,1,4
     - Anchored: true
     - CanCollide: true
     - Color: Really red (255,0,0)
     - Material: SmoothPlastic
     - Position: (0,100,0)
     - Orientation: 0,0,0 (facing -Z, important for puncher behind logic)
     - Tag: `TargetStand` (CollectionService optional)
     - Inside TargetStand:
       - **Chair** (Seat) - Target will sit on chair as requested
         - Insert Object -> Seat (NOT Part, NOT VehicleSeat)
         - Name: `Chair`
         - Size: 2,1,2
         - Anchored: true (static seat)
         - CanCollide: true
         - Position: (0,101,0) = 1 stud above TargetStand
         - Orientation: 0,0,0 same as TargetStand
         - Properties: Disabled=false

  2. **PuncherStand** (Part)
     - Name: `PuncherStand`
     - Size: 4,1,4
     - Anchored: true
     - CanCollide: true
     - Color: Really blue (0,0,255)
     - Position: 6 studs behind TargetStand = (0,100,6) if TargetStand at (0,100,0) facing -Z
     - Orientation: same as TargetStand (0,0,0)
     - Tag: `PuncherStand`

  3. **PlayerSpawns** (Folder)
     - Name: `PlayerSpawns`
     - Inside:
       - **Player1** (Part): Name Player1, Size 3,1,3, Anchored true, Position (5,100,0), Color White
       - **Player2** (Part): Name Player2, Size 3,1,3, Anchored true, Position (-5,100,0), Color White

### Arena4 (Model) - For 4 players - at (200,100,0)

- Name: `Arena4`
- Position: (200,100,0)
- TargetStand at (200,100,0) with Chair Seat inside at (200,101,0)
- PuncherStand at (200,100,6)
- PlayerSpawns Folder with 4 Parts:
  - Player1 at (205,100,0)
  - Player2 at (195,100,0)
  - Player3 at (200,100,5)
  - Player4 at (200,100,-5)

### Arena6 (Model) - For 6 players - at (400,100,0)

- Name: `Arena6`
- Position: (400,100,0)
- TargetStand at (400,100,0) with Chair
- PuncherStand at (400,100,6)
- PlayerSpawns with 6 Parts Player1..6 arranged in circle radius 5

---

## Why This Hierarchy?

As you requested earlier:

```
Slot/Arena
├── TargetStand
│   └── Chair (Seat) - target sits
├── PuncherStand - 6 studs behind
├── PlayerSpawns
│   ├── Player1
│   └── Player2 (up to 6)
```

- **TargetStand**: Where initial Target is placed, sits on Chair
- **Chair (Seat)**: Seat object inside TargetStand, target will sit via `Seat:Sit(Humanoid)` server-side
- **PuncherStand**: Where puncher will be placed in future punching phase (6 studs behind target, anti-exploit + invisibility)
- **PlayerSpawns**: General spawns for all players before role assigned, and for PotentialPunchers after target selection

No spectator stands as requested earlier.

---

## Properties Summary

| Object | Type | Anchored | CanCollide | Size | Position | Notes |
|--------|------|----------|------------|------|----------|-------|
| MatchArenas | Folder | - | - | - | - | In Workspace |
| Arena2 | Model | - | - | - | 0,100,0 | Far from lobby |
| TargetStand | Part | true | true | 4,1,4 | 0,100,0 | Red, target position |
| Chair | Seat | true | true | 2,1,2 | 0,101,0 | Inside TargetStand, target sits |
| PuncherStand | Part | true | true | 4,1,4 | 0,100,6 | Blue, 6 studs behind TargetStand |
| PlayerSpawns | Folder | - | - | - | - | Inside Arena |
| Player1 | Part | true | true | 3,1,3 | 5,100,0 | General spawn |

All Stands should have Attributes or Tags for future if needed, but not required for this phase.

---

## For Queue Slots (Lobby) - Already Created in Previous Phase

**Workspace.Lobby.MatchSlots.Slot2, Slot4, Slot6** each with:
- EntryArea (Part) 6,1,6 Anchored CanCollide false - physical entry
- LeaveButton (Part) 3,1,3 + ClickDetector
- DisplayBoard (Part) 4,6,0.5 + BillboardGui
- PlayerSpawns Folder Player1..N

These are for queue, not for match arena, but same PlayerSpawns concept.

---

## Verification Checklist

- [ ] Workspace.MatchArenas (Folder) exists
- [ ] Workspace.MatchArenas.Arena2 (Model) at 0,100,0 with TargetStand, TargetStand/Chair (Seat), PuncherStand at 0,100,6, PlayerSpawns/Player1,Player2
- [ ] Workspace.MatchArenas.Arena4 at 200,100,0 with TargetStand+Chair, PuncherStand, PlayerSpawns/Player1..4
- [ ] Workspace.MatchArenas.Arena6 at 400,100,0 with TargetStand+Chair, PuncherStand, PlayerSpawns/Player1..6
- [ ] Chair is Seat object, not Part, named Chair, parented to TargetStand, Anchored true
- [ ] PuncherStand is 6 studs behind TargetStand
- [ ] No SpectatorStands folder anywhere
- [ ] Workspace.Lobby.MatchSlots.Slot2,4,6 exist with EntryArea, DisplayBoard, PlayerSpawns (from previous phase)

