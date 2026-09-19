# Setup Guide - Phase 1

## Goal of Phase 1
Create clean repository structure without gameplay logic. Auto-create RemoteEvents. Validate Studio setup.

---

## What Phase 1 Does

- Creates folder structure in GitHub (already done)
- Provides placeholder ModuleScripts for all future systems (no logic yet)
- Server Main.server.luau auto-creates ReplicatedStorage.Remotes and 20 RemoteEvents if missing (as requested)
- Validates existence of Workspace.Lobby, MatchSlots, MatchArenas
- Client Main.client.luau validates remotes and listens to SlotStateUpdate for connection test

## What Phase 1 Does NOT Do

- No gameplay logic (no slot joining, no match start, no punch, no gauge, no damage, no guess)
- No final GUI (only placeholder docs)
- No monetization, DataStores, shops, cosmetics
- No animation playing yet

---

## Exact Steps to Setup in Studio for Phase 1

### Step 1: Create Folders in ReplicatedStorage

1. Open Explorer
2. Right-click ReplicatedStorage -> Insert Object -> Folder -> Name `Shared`
3. Right-click Shared -> Insert Object -> Folder -> Name `Util`
4. Right-click ReplicatedStorage -> Insert Object -> Folder -> Name `Remotes` (or let server auto-create)

### Step 2: Copy Shared ModuleScripts

For each file in `src/Shared/`:

- src/Shared/Constants.luau -> ReplicatedStorage/Shared/Constants (ModuleScript)
- src/Shared/Config.luau -> ReplicatedStorage/Shared/Config (ModuleScript)
- src/Shared/Types.luau -> ReplicatedStorage/Shared/Types (ModuleScript)
- src/Shared/Animations.luau -> ReplicatedStorage/Shared/Animations (ModuleScript)
- src/Shared/RemoteDefinitions.luau -> ReplicatedStorage/Shared/RemoteDefinitions (ModuleScript)
- src/Shared/Util/TableUtil.luau -> ReplicatedStorage/Shared/Util/TableUtil (ModuleScript)
- src/Shared/Util/StateMachine.luau -> ReplicatedStorage/Shared/Util/StateMachine (ModuleScript)
- src/Shared/Util/Signal.luau -> ReplicatedStorage/Shared/Util/Signal (ModuleScript)

How: Create ModuleScript, rename, paste content from GitHub.

### Step 3: Create ServerScriptService Structure

1. Right-click ServerScriptService -> Insert Object -> Folder -> Name `Services`
2. For each file in `src/Server/Services/`, create ModuleScript inside Services folder:
   - RemoteService
   - ValidationService
   - MatchSlotService
   - MatchService
   - RoleService
   - PunchService
   - PowerGaugeService
   - DamageService
   - GuessService
   - EliminationService
   - TeleportService
   - SpectatorService
3. Right-click ServerScriptService -> Insert Object -> Script -> Name `GuessThePuncherServer`
4. Paste content from `src/Server/Main.server.luau`

### Step 4: Create StarterPlayerScripts Structure

1. Right-click StarterPlayer -> StarterPlayerScripts -> Insert Object -> Folder -> Name `Controllers`
2. Right-click StarterPlayerScripts -> Insert Object -> LocalScript -> Name `GuessThePuncherClient`
3. Paste content from `src/Client/Main.client.luau`
4. For each file in `src/Client/Controllers/`, create ModuleScript inside Controllers:
   - SlotUIController
   - MatchStateController
   - CameraController
   - PunchButtonController
   - PowerGaugeController
   - GuessUIController
   - HUDController
   - AnimationController
   - SpectatorController
   - InputController
   - RoleController

### Step 5: Create Workspace Objects (Manual)

See docs/MANUAL_OBJECTS.md for detailed steps. For Phase 1 minimal test, you can create empty folders:

- Workspace -> Folder `Lobby`
  - Lobby -> Folder `MatchSlots`
    - MatchSlots -> Model `Slot2`
    - MatchSlots -> Model `Slot4`
    - MatchSlots -> Model `Slot6`
- Workspace -> Folder `MatchArenas`
  - MatchArenas -> Model `Arena2`
  - MatchArenas -> Model `Arena4`
  - MatchArenas -> Model `Arena6`

For each Slot Model, add TouchBlock Part and DisplayBoard Part and PlayerStands Folder (even empty for Phase 1).

For each Arena Model, add TargetStand Part, PuncherStand Part (6 studs behind), SpectatorStands Folder.

Full details in MANUAL_OBJECTS.md.

### Step 6: Test

1. Click Play (F5) in Studio with 1 client
2. Open Output window (View -> Output)
3. Expected:
   - Server: "[GuessThePuncherServer] Created ReplicatedStorage.Remotes folder" or "All remotes validated: 20 found"
   - Server: "Auto-created X RemoteEvents" if first time
   - Server: "Workspace structure validated" or list of missing objects (if you didn't create all)
   - Server: "Phase 1 scaffold ready. Config: MIN_PLAYERS=2 COUNTDOWN=10 PERFECT_KO=true"
   - Client: "All remotes validated: 20 found"
   - Client: "Phase 1 scaffold ready"

If you see errors about missing modules, check you copied all Shared files.

---

## RemoteEvents Auto-Creation

As you requested, Main.server.luau now does:

```lua
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")...
for _, remoteName in ipairs(Constants.AllRemoteNames) do
  if not remotesFolder:FindFirstChild(remoteName) then
    Instance.new("RemoteEvent").Name = remoteName
  end
end
```

So you don't need to create them manually. But you can verify in Explorer after Play that 20 RemoteEvents exist.

---

## Filtered Payloads (Important for future)

From now on, MatchStateUpdate must NOT contain:

- puncherUserId before reveal (during PUNCH_OPPORTUNITY, PUNCHER_SELECTED, POWER_GAUGE, PUNCH_EXECUTING, GUESSING)
- Any hidden role information
- Any data identifying who clicked first
- Private camera or position information

Server will send:
- For Target client: {matchId, state, targetUserId, alivePlayers, healthTable}
- For others: {matchId, state, targetUserId, alivePlayers, healthTable, puncherUserId?} (puncher allowed for spectators, but still filtered for Target)

Puncher invisibility to Target (approved) will be handled client-side: when Target receives PuncherSelected with nil puncher, it will make puncher character invisible (Transparency 1).

---

## Next Phase

Phase 2 will implement MatchSlotService (lobby queue, touch detection, countdown >=2 players).

Wait for your confirmation before proceeding.

