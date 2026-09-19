# Studio Mapping - Guess the Puncher

## Purpose
Explains where every GitHub file goes in Roblox Studio.

---

### 1. Where future files will be placed (Overview)

```
GitHub repo src/  ->  Roblox Studio Explorer
src/Server/Main.server.luau  -> ServerScriptService
src/Server/Services/*.luau   -> ServerScriptService/Services
src/Shared/*.luau            -> ReplicatedStorage/Shared
src/Shared/Util/*.luau       -> ReplicatedStorage/Shared/Util
src/Client/Main.client.luau  -> StarterPlayer/StarterPlayerScripts
src/Client/Controllers/*.luau -> StarterPlayer/StarterPlayerScripts/Controllers
```

---

### 2. Which files belong in ServerScriptService

Create Folder `Services` inside ServerScriptService.

| GitHub Path | Studio Path | Type |
|-------------|-------------|------|
| src/Server/Main.server.luau | ServerScriptService/GuessThePuncherServer | Script (.server.luau) |
| src/Server/Services/RemoteService.luau | ServerScriptService/Services/RemoteService | ModuleScript |
| src/Server/Services/ValidationService.luau | ServerScriptService/Services/ValidationService | ModuleScript |
| src/Server/Services/MatchSlotService.luau | ServerScriptService/Services/MatchSlotService | ModuleScript |
| src/Server/Services/MatchService.luau | ServerScriptService/Services/MatchService | ModuleScript |
| src/Server/Services/RoleService.luau | ServerScriptService/Services/RoleService | ModuleScript |
| src/Server/Services/PunchService.luau | ServerScriptService/Services/PunchService | ModuleScript |
| src/Server/Services/PowerGaugeService.luau | ServerScriptService/Services/PowerGaugeService | ModuleScript |
| src/Server/Services/DamageService.luau | ServerScriptService/Services/DamageService | ModuleScript |
| src/Server/Services/GuessService.luau | ServerScriptService/Services/GuessService | ModuleScript |
| src/Server/Services/EliminationService.luau | ServerScriptService/Services/EliminationService | ModuleScript |
| src/Server/Services/TeleportService.luau | ServerScriptService/Services/TeleportService | ModuleScript |
| src/Server/Services/SpectatorService.luau | ServerScriptService/Services/SpectatorService | ModuleScript |

All server files are **server-authoritative**. Never trust client.

---

### 3. Which files belong in ReplicatedStorage

Create Folders: `Shared`, `Shared/Util`, `Remotes` (Remotes auto-created by server script, but you can create manually).

| GitHub Path | Studio Path | Type |
|-------------|-------------|------|
| src/Shared/Constants.luau | ReplicatedStorage/Shared/Constants | ModuleScript |
| src/Shared/Config.luau | ReplicatedStorage/Shared/Config | ModuleScript |
| src/Shared/Types.luau | ReplicatedStorage/Shared/Types | ModuleScript |
| src/Shared/Animations.luau | ReplicatedStorage/Shared/Animations | ModuleScript |
| src/Shared/RemoteDefinitions.luau | ReplicatedStorage/Shared/RemoteDefinitions | ModuleScript |
| src/Shared/Util/TableUtil.luau | ReplicatedStorage/Shared/Util/TableUtil | ModuleScript |
| src/Shared/Util/StateMachine.luau | ReplicatedStorage/Shared/Util/StateMachine | ModuleScript |
| src/Shared/Util/Signal.luau | ReplicatedStorage/Shared/Util/Signal | ModuleScript |

Remotes Folder:
- ReplicatedStorage/Remotes contains 20 RemoteEvents (auto-created by Main.server.luau if missing)
- See docs/REMOTES.md for exact names

Shared is visible to both client and server, so never store secrets there (puncherUserId, gaugeStartTick must stay server-only in MatchService).

---

### 4. Which files belong in StarterPlayerScripts

Create Folder `Controllers` inside StarterPlayerScripts.

| GitHub Path | Studio Path | Type |
|-------------|-------------|------|
| src/Client/Main.client.luau | StarterPlayer/StarterPlayerScripts/GuessThePuncherClient | LocalScript (.client.luau) |
| src/Client/Controllers/SlotUIController.luau | StarterPlayer/StarterPlayerScripts/Controllers/SlotUIController | ModuleScript |
| src/Client/Controllers/MatchStateController.luau | .../Controllers/MatchStateController | ModuleScript |
| src/Client/Controllers/CameraController.luau | .../Controllers/CameraController | ModuleScript |
| src/Client/Controllers/PunchButtonController.luau | .../Controllers/PunchButtonController | ModuleScript |
| src/Client/Controllers/PowerGaugeController.luau | .../Controllers/PowerGaugeController | ModuleScript |
| src/Client/Controllers/GuessUIController.luau | .../Controllers/GuessUIController | ModuleScript |
| src/Client/Controllers/HUDController.luau | .../Controllers/HUDController | ModuleScript |
| src/Client/Controllers/AnimationController.luau | .../Controllers/AnimationController | ModuleScript |
| src/Client/Controllers/SpectatorController.luau | .../Controllers/SpectatorController | ModuleScript |
| src/Client/Controllers/InputController.luau | .../Controllers/InputController | ModuleScript |
| src/Client/Controllers/RoleController.luau | .../Controllers/RoleController | ModuleScript |

All client files are **presentation only**, never authoritative.

---

### 5. Which files belong in StarterGui

No Luau files yet in Phase 1 (GUI built manually). Future:

- StarterGui/MainHUD (ScreenGui) will be created manually
  - Contains: CountdownLabel, RoleLabel, HealthBar, PunchButton, PowerGauge Frame, GuessUI Frame, WinnerLabel
  - No scripts inside yet; controllers will reference it via WaitForChild

Phase 1 does NOT create final GUI yet per your instruction.

---

### 6. Summary Table

| Location | Count | Purpose |
|----------|-------|---------|
| ServerScriptService | 1 Script + 11 ModuleScripts | Game management, queue, match, roles, punch, gauge, damage, guess, elimination, teleport, spectator, remote auto-creation |
| ReplicatedStorage/Shared | 5 + 3 Util | Config, constants, types, animations, remote docs, helpers |
| ReplicatedStorage/Remotes | 20 RemoteEvents | Communication (auto-created) |
| StarterPlayerScripts | 1 LocalScript + 11 ModuleScripts | Input, camera, UI presentation |
| StarterGui | 1 ScreenGui (manual) | HUD (future) |

