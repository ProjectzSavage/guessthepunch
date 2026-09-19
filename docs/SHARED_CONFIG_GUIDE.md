# Shared Configuration & Game-State Definitions - Phase 1 (Rebuilt)

## Goal
Implement ONLY centralized config and shared definitions. No queue logic, match logic, punching, power, damage, guessing, KO, GUI, monetization, DataStores.

---

## 1. File Paths (GitHub)

```
src/Shared/
├── Config.luau        - Centralized tunable values
├── MatchStates.luau   - Match state enums + transitions + hidden puncher rules
├── Roles.luau         - Player roles
├── PowerZones.luau    - Punch power zones (Miss, Weak, Normal, Strong, Perfect)
├── Results.luau       - Guess results (Correct/Wrong/Timeout) + Match results
├── Types.luau         - Filtered payload types (no secrets)
└── Constants.luau     - Aggregator re-exporting all above + remote names
```

All files are in `src/Shared/` only. No Server or Client files in this phase.

---

## 2. Roblox Studio Destinations

| GitHub Path | Studio Destination | Type |
|-------------|-------------------|------|
| src/Shared/Config.luau | ReplicatedStorage > Shared > Config | ModuleScript |
| src/Shared/MatchStates.luau | ReplicatedStorage > Shared > MatchStates | ModuleScript |
| src/Shared/Roles.luau | ReplicatedStorage > Shared > Roles | ModuleScript |
| src/Shared/PowerZones.luau | ReplicatedStorage > Shared > PowerZones | ModuleScript |
| src/Shared/Results.luau | ReplicatedStorage > Shared > Results | ModuleScript |
| src/Shared/Types.luau | ReplicatedStorage > Shared > Types | ModuleScript |
| src/Shared/Constants.luau | ReplicatedStorage > Shared > Constants | ModuleScript |

All names WITHOUT .luau extension in Studio (just `Config`, `MatchStates`, etc.)

---

## 3. Required Folders

In Studio Explorer, create:

- `ReplicatedStorage` -> Folder `Shared`
- (Optional) `ReplicatedStorage` -> Folder `Remotes` (will be auto-created later by server, not needed for this phase)

No other folders required for this phase.

In GitHub, folder `src/Shared/` already exists.

---

## 4. How Future Systems Will Import These Modules

### From Server (ServerScriptService)

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Config = require(Shared:WaitForChild("Config"))
local MatchStates = require(Shared:WaitForChild("MatchStates"))
local Roles = require(Shared:WaitForChild("Roles"))
local PowerZones = require(Shared:WaitForChild("PowerZones"))
local Results = require(Shared:WaitForChild("Results"))

-- Or single import via aggregator:
local Constants = require(Shared:WaitForChild("Constants"))
local Config = Constants.Config
local MatchStates = Constants.MatchStates

-- Usage:
print(Config.MinimumPlayers) -- 2
print(Config.Damage.Perfect) -- 100
print(MatchStates.States.GUESSING) -- "GUESSING"
if MatchStates.IsPuncherHidden(currentState) then
  -- send filtered payload without puncherUserId
end
```

### From Client (StarterPlayerScripts)

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Config = require(Shared:WaitForChild("Config"))
local PowerZones = require(Shared:WaitForChild("PowerZones"))

-- Client visual only, server authoritative:
local zone = PowerZones.GetZoneFromPosition(0.51) -- client prediction
-- Server will calculate real zone from tick, never trust client
```

### From Shared Modules Themselves

```lua
-- Constants.luau already requires others:
local Config = require(script.Parent:WaitForChild("Config"))
local MatchStates = require(script.Parent:WaitForChild("MatchStates"))
-- etc.
```

**Important:** Shared is visible to client, so NEVER store secrets like puncherUserId, gaugeStartTick, camera CFrames in Config or any Shared module. Those stay server-only in future MatchService.

---

## 5. Centralized Configuration Values (Easy to Adjust)

All in `Config.luau`:

- **Queue capacities:** `QueueCapacities = {Slot2=2, Slot4=4, Slot6=6}`, `QueueCapacityList = {2,4,6}`
- **Minimum players:** `MinimumPlayers = 2`
- **Queue countdowns:** `QueueCountdownDuration = 10`, `QueueCountdownByCapacity = {[2]=10, [4]=10, [6]=15}`
- **Match preparation time:** `MatchPreparationTime = 3`
- **Punch-selection duration:** `PunchSelectionDuration = 10`
- **Power-gauge duration:** `PowerGaugeDuration = 5`, `PowerGaugeCycleDuration = 2.0`
- **Guessing duration:** `GuessingDuration = 15`
- **Starting health:** `StartingHealth = 100`
- **Weak damage:** `Damage.Weak = 10`
- **Normal damage:** `Damage.Normal = 25`
- **Strong damage:** `Damage.Strong = 50`
- **Perfect damage:** `Damage.Perfect = 100` (instant KO)
- **Miss damage:** `Damage.Miss = 0`
- **Knockout duration:** `KnockoutDuration = 3`
- **Lobby return delay:** `LobbyReturnDelay = 5`

To balance, just edit numbers in Config.luau, no other files need changes.

---

## 6. Shared Definitions

- **Match states:** `MatchStates.States` = WAITING_FOR_PLAYERS, COUNTDOWN, PREPARING, ROUND_START, PUNCH_SELECTION, PUNCHER_SELECTED, POWER_GAUGE, PUNCH_EXECUTING, GUESSING, GUESS_RESULT, TARGET_ELIMINATED, MATCH_ENDING, LOBBY_RETURN + `Transitions` table + `IsPuncherHidden()` helper
- **Player roles:** `Roles.Roles` = NONE, LOBBY, QUEUED, TARGET, PUNCHER, SPECTATOR, ELIMINATED, WINNER + `IsAlive()`, `CanPunch()`, `CanGuess()` helpers
- **Punch power zones:** `PowerZones.Zones` = Miss, Weak, Normal, Strong, Perfect + `Thresholds` + `GetZoneFromPosition()` + `IsInstantKO()`
- **Guess results:** `Results.GuessResults` = Correct, Wrong, Timeout
- **Match results:** `Results.MatchResults` = Winner, Eliminated, Draw, Cancelled + `EliminationReasons`

---

## 7. New Slot Hierarchy (No Spectator Stands)

As requested, hierarchy inside Slot (or Arena) is:

```
Slot2 (Model)
├── TargetStand (Part)
├── PuncherStand (Part) - 6 studs behind TargetStand
├── PlayerSpawns (Folder)
│   ├── Player1 (Part or SpawnLocation)
│   └── Player2 (Part)
├── TouchBlock (Part) - for queue join (if this is lobby slot)
└── DisplayBoard (Part) - for occupancy UI
```

For Slot4: PlayerSpawns contains Player1..Player4
For Slot6: Player1..Player6

No SpectatorStands folder. Spectators will use PlayerSpawns as well (all alive players have a spawn, but Target and Puncher use their dedicated stands during round).

If you put arenas in Workspace.MatchArenas folder (as you said you will), use same hierarchy inside each Arena:

```
Workspace.MatchArenas (Folder)
├── Arena2 (Model)
│   ├── TargetStand
│   ├── PuncherStand
│   └── PlayerSpawns (Player1, Player2)
├── Arena4 (Model) Player1..4
└── Arena6 (Model) Player1..6
```

And lobby queue slots in Workspace.Lobby.MatchSlots can be simpler (just TouchBlock + DisplayBoard) OR same hierarchy if you want matches to happen inside lobby slots. Recommended: keep lobby slots separate for queue, arenas for match, both using same internal structure for consistency.

See MANUAL_OBJECTS.md for exact properties.

---

## 8. Copy Instructions

### Manual Copy-Paste

1. In GitHub, open `src/Shared/Config.luau`, select all, copy
2. In Studio, create ModuleScript named `Config` inside `ReplicatedStorage/Shared`, paste
3. Repeat for MatchStates, Roles, PowerZones, Results, Types, Constants

### Using Command Bar (Faster)

See `docs/CommandBar_CreateShared.txt` - copy-paste entire script into Studio Command Bar (View -> Command Bar) and press Enter. It will create all folders and ModuleScripts with correct names (no .luau extensions). Then you manually paste code into each ModuleScript.

---

## 9. Manual Verification Procedure (No Code Needed)

1. Create Shared folder and 7 ModuleScripts via Command Bar script
2. Paste code from GitHub into each
3. In Studio Command Bar, run:

```lua
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MatchStates = require(Shared:WaitForChild("MatchStates"))
local Roles = require(Shared:WaitForChild("Roles"))
local PowerZones = require(Shared:WaitForChild("PowerZones"))
local Results = require(Shared:WaitForChild("Results"))
print("Config capacities:", Config.QueueCapacities.Slot2, Config.QueueCapacities.Slot4, Config.QueueCapacities.Slot6)
print("Min players:", Config.MinimumPlayers)
print("Queue countdown:", Config.QueueCountdownDuration)
print("Prep time:", Config.MatchPreparationTime)
print("Punch selection:", Config.PunchSelectionDuration)
print("Power gauge:", Config.PowerGaugeDuration)
print("Guessing:", Config.GuessingDuration)
print("Health:", Config.StartingHealth)
print("Damages:", Config.Damage.Weak, Config.Damage.Normal, Config.Damage.Strong, Config.Damage.Perfect, Config.Damage.Miss)
print("KO duration:", Config.KnockoutDuration)
print("Lobby return:", Config.LobbyReturnDelay)
print("States:", MatchStates.States.WAITING_FOR_PLAYERS, MatchStates.States.GUESSING, MatchStates.States.MATCH_ENDING)
print("Roles:", Roles.Roles.TARGET, Roles.Roles.PUNCHER, Roles.Roles.SPECTATOR)
print("Power zones:", PowerZones.Zones.MISS, PowerZones.Zones.WEAK, PowerZones.Zones.NORMAL, PowerZones.Zones.STRONG, PowerZones.Zones.PERFECT)
print("Guess results:", Results.GuessResults.CORRECT, Results.GuessResults.WRONG, Results.GuessResults.TIMEOUT)
print("Match results:", Results.MatchResults.WINNER, Results.MatchResults.ELIMINATED)
print("All shared definitions loaded OK")
```

Expected output: all values printed, no errors.

4. Test filtering helper:

```lua
local MatchStates = require(game.ReplicatedStorage.Shared.MatchStates)
print(MatchStates.IsPuncherHidden("GUESSING")) -- should be true
print(MatchStates.IsPuncherHidden("GUESS_RESULT")) -- should be false
print(MatchStates.CanTransition("GUESSING", "GUESS_RESULT")) -- true
print(MatchStates.CanTransition("GUESSING", "PUNCH_SELECTION")) -- false
```

If all prints are correct, Phase 1 is verified.

---

## 10. What Is NOT Implemented

- No queue logic, no touch handling
- No match logic, no state machine execution
- No punching, no power gauge logic
- No damage application, no health
- No guessing logic
- No knockout, no elimination
- No GUI, no camera
- No monetization, DataStores
- No Server or Client scripts (only Shared)

Future systems will import these modules but not modify them.

