# Target Camera and Visibility System - Setup Guide

## Goal
Implement ONLY Target camera and visibility system. No punch, power, damage, guessing, knockout, scoring, GUI.

## Changed Files

### 1. src/Shared/Config.luau
- Added Target camera tuning:
  - TargetCameraEnabled = true
  - TargetFirstPersonZoom = 0.5
  - TargetMaxYawDegrees = 65 (prevents inspecting behind)
  - TargetMaxPitchDegrees = 30
  - TargetCameraStability = true
  - TargetDisableAutoRotate = true
  - TargetHideBehindPlayers = true (anti-cheat backup)
  - TargetBehindDotThreshold = -0.1
  - TargetVisibilityCheckInterval = 0.15
  - TargetRestoreDelay = 0.2

### 2. src/Server/Services/MatchService.luau
- Fixed ServerScriptService definition (was crashing)
- Updated broadcastMatchState to use filtered payloads per player:
  - buildFilteredPayload(matchData, forPlayerUserId)
  - For Target recipient: masks Puncher role as PotentialPuncher
  - Payload explicitly does NOT contain: puncherUserId, healthTable, hidden role info, private camera/position
  - Separate payloads for Target vs other clients (anti-cheat)
  - Server controls Target role, client only presentation

### 3. src/Client/Services/TargetCameraService.luau (NEW)
- Client-only camera presentation
- Forces LockFirstPerson, Min/Max zoom 0.5, prevents zoom out
- Clamps yaw to ±65° from initial forward, pitch to ±30°
- Keeps camera stable, prevents freely rotating behind
- Saves/restores original CameraMode, Min/Max zoom, CameraType, AutoRotate, CameraOffset
- Binds to RenderStep for clamping
- Handles CharacterAdded (reset/death), MatchEnd, role change, disconnect

### 4. src/Client/Services/TargetVisibilityService.luau (NEW)
- Client-only visibility presentation
- When Target: hides players behind Target locally via LocalTransparencyModifier (anti-cheat backup, not relying only on camera)
- Uses dot product check: if player behind (dot < -0.1), make invisible only for Target client
- Does NOT reveal Puncher identity (server filters Puncher role from Target payload)
- Hides BaseParts, Decals, Textures, BillboardGuis locally
- Restores when no longer Target
- Handles CharacterAdded for other players respawn

### 5. src/Client/Main.client.luau
- Loads TargetCameraService and TargetVisibilityService from multiple possible paths (child Services folder, sibling, etc.)
- Tracks currentMatchId, currentRole, currentTargetUserId, currentMatchPlayers
- On RE_RoleAssigned and RE_MatchStateUpdate: determines if local player is Target, calls SetIsTarget on both services
- On RE_MatchEnd: restores camera and visibility
- On CharacterAdded: re-applies if still Target
- Security checks: warns if Target receives Puncher role or puncherUserId (should never happen)

### 6. flat/ copies for Claude MCP
- flat/Shared_Config.luau (synced)
- flat/Server_MatchService.luau (synced with filtered payloads)
- flat/Client_Main.client.luau (synced)
- flat/Client_TargetCameraService.luau (new)
- flat/Client_TargetVisibilityService.luau (new)

## Exact Studio Destinations

### Server
- ReplicatedStorage > Shared > Config (ModuleScript) <- src/Shared/Config.luau
- ServerScriptService > Services > MatchService (ModuleScript) <- src/Server/Services/MatchService.luau
- ServerScriptService > Services > QueueService (ModuleScript) <- already exists, unchanged but must be 752 lines with MatchService handoff
- ServerScriptService > Services > RemoteService (ModuleScript) <- unchanged
- ServerScriptService > Main (Script) <- src/Server/Main.server.luau (init MatchService first then QueueService)

### Client
- StarterPlayer > StarterPlayerScripts > GuessThePuncherClient (LocalScript) <- src/Client/Main.client.luau
- StarterPlayer > StarterPlayerScripts > GuessThePuncherClient > Services (Folder)
  - TargetCameraService (ModuleScript) <- src/Client/Services/TargetCameraService.luau
  - TargetVisibilityService (ModuleScript) <- src/Client/Services/TargetVisibilityService.luau
- Alternative if you use flat structure: StarterPlayerScripts > Services folder with same modules, Main.client will find it

### Remotes (auto-created by RemoteService, but manual if needed)
- ReplicatedStorage > Remotes (Folder)
  - RE_QueueJoinRequest (RemoteEvent)
  - RE_QueueLeaveRequest (RemoteEvent)
  - RE_QueueStateUpdate (RemoteEvent)
  - RE_QueueCountdownUpdate (RemoteEvent)
  - RE_QueueLocked (RemoteEvent)
  - RE_QueueStarted (RemoteEvent)
  - RE_QueuePlayerLeft (RemoteEvent)
  - RE_MatchStart (RemoteEvent)
  - RE_MatchStateUpdate (RemoteEvent) - FILTERED PAYLOADS, no puncherUserId
  - RE_MatchEnd (RemoteEvent)
  - RE_RoleAssigned (RemoteEvent)
  - RE_TargetSelected (RemoteEvent)

## Manual Setup

### 1. Ensure Lobby and Arenas exist (from previous phases)
- Workspace > Lobby (Folder)
  - SpawnLocation
  - MatchSlots (Folder) with Slot2, Slot4, Slot6 (Models)
    - Each Slot: EntryArea (Part), DisplayBoard (Part with BillboardGui), PlayerSpawns (Folder with Player1..N Parts)
- Workspace > MatchArenas (Folder) with Arena2, Arena4, Arena6 (Models)
  - Each Arena: TargetStand (Part) with Chair (Seat) child, PuncherStand (Part), PlayerSpawns (Folder with Player1..N Parts)

### 2. Create Client Services Folder
In Studio:
1. Go to StarterPlayer > StarterPlayerScripts
2. Find GuessThePuncherClient (LocalScript) - if not exists, create LocalScript named GuessThePuncherClient and paste Main.client.luau code
3. Inside GuessThePuncherClient, create Folder named Services
4. Inside Services, create ModuleScript named TargetCameraService, paste src/Client/Services/TargetCameraService.luau code
5. Inside Services, create ModuleScript named TargetVisibilityService, paste src/Client/Services/TargetVisibilityService.luau code
6. Properties: All ModuleScripts have no special properties needed

### 3. Verify Shared Config
- ReplicatedStorage > Shared > Config ModuleScript must have Target camera values (copy from src/Shared/Config.luau)
- If using old Config, add the Target camera section manually

### 4. Verify MatchService filtered payloads
- ServerScriptService > Services > MatchService must have buildFilteredPayload function and filtered broadcast
- Check line 21 has ServerScriptService = game:GetService("ServerScriptService")
- Check broadcastMatchState loops per player and calls buildFilteredPayload

## Copy Instructions

### Option A: Manual Copy (recommended, no .luau extensions)
1. Open src/Shared/Config.luau in GitHub, copy all, paste into ReplicatedStorage.Shared.Config in Studio
2. Open src/Server/Services/MatchService.luau, copy, paste into ServerScriptService.Services.MatchService
3. Open src/Client/Services/TargetCameraService.luau, copy, paste into StarterPlayerScripts.GuessThePuncherClient.Services.TargetCameraService
4. Open src/Client/Services/TargetVisibilityService.luau, copy, paste into StarterPlayerScripts.GuessThePuncherClient.Services.TargetVisibilityService
5. Open src/Client/Main.client.luau, copy, paste into StarterPlayerScripts.GuessThePuncherClient (LocalScript)

### Option B: Flat folder for Claude MCP
If Claude MCP cannot access subfolders, use flat/ folder:
- flat/Shared_Config.luau -> ReplicatedStorage.Shared.Config
- flat/Server_MatchService.luau -> ServerScriptService.Services.MatchService
- flat/Client_Main.client.luau -> StarterPlayerScripts.GuessThePuncherClient
- flat/Client_TargetCameraService.luau -> ...Services.TargetCameraService
- flat/Client_TargetVisibilityService.luau -> ...Services.TargetVisibilityService

### Option C: CommandBar Script
Use docs/CommandBar_TargetCamera.txt (to be created) which auto-creates all folders and scripts without .luau extensions.

## Camera Testing Steps

### Prerequisites
- Have 2-3 test clients in Studio: Test > Clients and Servers > Start with 2-3 players
- Ensure Lobby and MatchArenas exist per manual setup
- Ensure QueueService and MatchService are running (check Output for "[QueueService] Initialized" and "[MatchService] Initialized")

### Test 1: Target gets restricted first-person
1. Start server with 2 clients
2. Both players walk onto same Slot EntryArea (e.g., Slot2)
3. Wait for countdown (5 sec when full) -> should teleport to Arena2
4. Observe Output: "[MatchService] Target selected: X"
5. For Target player: camera should snap to LockFirstPerson, zoom locked to 0.5, cannot scroll out
6. Try mouse wheel - should NOT zoom out
7. Try looking around - yaw should be limited to ~65° left/right from initial forward, pitch limited to ~30° up/down
8. Try to look behind (180°) - should clamp and prevent

### Test 2: Prevent freely rotating to inspect behind
1. As Target, try to spin mouse quickly to look behind
2. Camera should clamp and snap back forward
3. Character HRP should stay facing initial forward (AutoRotate false), not spin behind
4. Other player (PotentialPuncher) moves behind Target - Target should NOT be able to rotate to see them due to clamp

### Test 3: Camera stable
1. As Target, stand still, move mouse slightly - camera should be stable, not jitter
2. Walk forward slightly (if allowed) - camera should stay first-person stable

### Test 4: Prevent receiving hidden Puncher information
1. As Target, check Output for "[Match] Your role (filtered payload): Target"
2. Check that payload does NOT contain puncherUserId - no warning "[Security] Payload contains puncherUserId"
3. Check that roles for other players are all "PotentialPuncher", never "Puncher" - no warning "[Security] Target received Puncher role"
4. In Server Output, verify broadcast uses filtered payloads

### Test 5: Restore normal camera when no longer Target
1. As Target, leave match by disconnecting or when match ends due to <2 players
2. Camera should restore to normal (CameraMode from before, zoom restored, AutoRotate true)
3. Try zooming out - should work now
4. Try rotating 360° - should work

### Test 6: Handle reset, death, disconnect, match completion
1. As Target, reset character (Humanoid health 0)
2. After respawn, camera should re-apply restricted first-person after ~0.2 sec delay
3. As PotentialPuncher, reset - should stay normal camera, respawn in arena
4. Disconnect Target player - match should end safely, other players return to lobby with normal camera
5. End match (all leave) - all cameras restored

### Test 7: Other players keep normal camera
1. As PotentialPuncher, verify camera is normal (can zoom, rotate 360°)
2. Move behind Target - you should be visible normally to other PotentialPunchers, but hidden from Target's perspective (behind check)
3. For Target, other players in front should be visible, behind should be invisible locally (LocalTransparencyModifier = 1)

### Test 8: Anti-cheat backup (visibility)
1. As Target, have other player stand behind you (within 10 studs, behind dot < -0.1)
2. That player should become invisible only on Target's client (check Explorer > other character parts LocalTransparencyModifier = 1 on Target client, but 0 on their own client)
3. Move to front of Target - should become visible again on Target client
4. This ensures even if Target bypasses camera clamp (exploit), they still cannot see Puncher behind

## Expected Results

- When becoming Target: Output "[TargetCamera] Becoming Target - forcing restricted first-person" and "[TargetVisibility] Becoming Target - enabling behind-player hiding"
- CameraMode = LockFirstPerson, Min/Max zoom = 0.5, cannot zoom out
- Yaw clamped to ±65°, pitch to ±30°, cannot inspect behind
- Camera stable, HRP stays forward
- Behind players invisible to Target only (LocalTransparencyModifier = 1)
- No hidden Puncher info in payload for Target
- Other players: normal camera, normal visibility (except they hide when behind Target from Target's perspective)
- On match end / role change / death / reset: camera restores, visibility restores
- Server controls Target role (random selection), client only presentation

## Common Errors and Fixes

### Error: "Services folder not found - Target camera/visibility will be disabled"
- Fix: Create StarterPlayerScripts > GuessThePuncherClient > Services folder with two ModuleScripts inside. Or create StarterPlayerScripts > Services folder. Main.client tries multiple paths.

### Error: "TargetCameraService not found" or "Failed to require"
- Fix: Ensure ModuleScript names exactly "TargetCameraService" and "TargetVisibilityService" (no .luau extension in Studio). Check they are ModuleScripts, not Scripts.

### Error: Camera not forcing first-person
- Fix: Check Config.TargetCameraEnabled = true. Check Player.CameraMode is being set - may be overridden by other scripts. Ensure no other LocalScript sets CameraMode after ours. Our service re-applies on Heartbeat as backup.

### Error: Can still zoom out
- Fix: Ensure Player.CameraMinZoomDistance and MaxZoomDistance both set to 0.5. Some Studio settings (StarterPlayer.CameraMinZoomDistance) may override. Set StarterPlayer.CameraMinZoomDistance = 0.5, Max = 0.5 as fallback, but our script forces per player.

### Error: Can still rotate 360° behind
- Fix: Check RunService:BindToRenderStep is working - look for errors in Output. Ensure initialYaw is set (HRP exists). Try increasing RenderPriority or check if another camera script unbinds ours. Our service re-binds on CharacterAdded.

### Error: Camera jitter / flicker
- Fix: May be conflict with Humanoid.AutoRotate. Ensure TargetDisableAutoRotate = true and HRP CFrame snapping not too aggressive. Try increasing TargetMaxYawDegrees to 75 for less clamping, or reduce heartbeat enforcement.

### Error: Other players not invisible behind Target
- Fix: Check TargetHideBehindPlayers = true, TargetBehindDotThreshold = -0.1. Ensure TargetVisibilityService is running (Output "[TargetVisibilityService] Initialized"). Check other players' characters have HumanoidRootPart. LocalTransparencyModifier only works locally - check on Target client, not server.

### Error: Target sees Puncher role or puncherUserId
- Fix: Server filtering failed. Ensure MatchService has buildFilteredPayload and uses it per player. Check payload.roles for Target should never contain "Puncher". Check payload does not contain puncherUserId field. Update MatchService from GitHub.

### Error: Camera not restoring after match end
- Fix: Ensure RE_MatchEnd is fired and Main.client listens. Check Output "[Client] Restoring camera and visibility". If not, manually call TargetCameraService.Restore() in CommandBar for testing. Ensure originalSettings saved before.

### Error: After death, camera stays broken
- Fix: Ensure CharacterAdded connection works. TargetCameraService.HandleCharacterAdded waits 0.2 sec then re-applies. Check humanoid exists. If still broken, check Output for errors.

### Error: "Cannot require module" for Config
- Fix: Ensure ReplicatedStorage.Shared.Config exists and returns a table. Check for syntax errors in Config.luau.

### Error: MatchService crash "ServerScriptService nil"
- Fix: Old version. Update MatchService from GitHub - line 21 must have local ServerScriptService = game:GetService("ServerScriptService").

## Not Implemented (Future)
- Punch selection, power gauge, damage, guessing, knockout, scoring, final GUI, monetization, DataStores
- Puncher movement behind Target (only visibility infrastructure now)
- Official Puncher reveal logic
- Punch animations
