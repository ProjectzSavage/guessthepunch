# Game UI - Setup Guide

## A. Goal
Provide the UI the game needs to be playable end-to-end WITHOUT the command bar:
- **LOBBY QUEUE PANEL** (new, `QueueUIService`): "GUESS THE PUNCHER" panel with one row per slot (Slot2/Slot4/Slot6) showing live occupancy (2/4 style), slot state (Open / Starting in Xs / LOCKED / CANCELLED) and JOIN / LEAVE buttons (server keeps all queue authority - buttons just fire the existing queue remotes; the server validates everything). Visible only in the lobby; hides when a match starts; returns when the match ends.
- **MATCH HUD** (new, `HudService`): role/state chip (top left), TARGET HEALTH BAR (top right, server-driven from `RE_TargetHealthUpdate`, colored green/yellow/red, refills on Reset/new Target), and a center prompt per state+role ("Press [F] to become the Puncher!", "Get ready... X.Xs" (prep countdown), "Press [E] to lock the gauge!", "Pick who punched you!", "KNOCKED OUT!", etc.). Visible only during a match.
- These COMPLEMENT the existing per-system UIs which already exist (power gauge panel, guess choice panel + reveal banners, spectator panel, victory/defeat banners, K.O. effects). No gameplay was changed; UI is client presentation only and every server validation remains authoritative.

## B. Files (exact paths)
### Changed
1. `src/Shared/Config.luau` - new UI section: `UIEnabled = true`, `ShowQueueUI = true`, `ShowMatchHud = true` (set false to disable either panel)
2. `src/Client/Main.client.luau` - loads + wires `QueueUIService` and `HudService` (require via pcall, `UpdateState` in applyPuncherState, `HandleMatchEnd` in restoreAll, `Init` at startup)
### New
3. `src/Client/Services/QueueUIService.luau` - lobby queue panel; listens `RE_QueueStateUpdate` (slotId, occupancyList, maxPlayers, state, countdownTimeLeft, locked, occupancyCount) + `RE_QueueCountdownUpdate` (slotId, timeLeft); fires `RE_QueueJoinRequest:FireServer(slotId)` / `RE_QueueLeaveRequest:FireServer()` from buttons; detects local slot membership from occupancyList to swap JOIN<->LEAVE and highlight the row
4. `src/Client/Services/HudService.luau` - match HUD; listens `RE_TargetHealthUpdate` (health bar) + `RE_PuncherPreparation` (prep countdown, skipped for Target who receives 0); prompt text driven by Main's `UpdateState(matchId, role, state)` using FILTERED server payloads (role chip shows exactly what the server told this client - Target/spectators never see "Puncher" before reveal)
### flat/ sync (Claude MCP)
`flat/Shared_Config.luau`, `flat/Client_Main.client.luau`, `flat/Client_QueueUIService.luau` (NEW), `flat/Client_HudService.luau` (NEW)
### Docs
`docs/UI_SETUP_GUIDE.md` (this file), `docs/CommandBar_UI.txt`

## C. Setup (manual objects)
- NO new RemoteEvents (uses existing queue/health/preparation remotes).
- NO Workspace objects. All UI is CODE-CREATED (ScreenGuis "QueueGui" and "MatchHud" appear in PlayerGui at runtime) - do NOT build GUIs manually.
- Manual work is ONLY: create 2 ModuleScripts and paste code (see D/F).

## D. Hierarchy (Studio explorer after setup)
```
StarterPlayer > StarterPlayerScripts > GuessThePuncherClient (LocalScript) [updated]
    └── Services (Folder)
        ├── TargetCameraService (ModuleScript)    [unchanged]
        ├── TargetVisibilityService (ModuleScript)[unchanged]
        ├── PuncherSelectionService (ModuleScript)[unchanged]
        ├── PowerGaugeService (ModuleScript)      [unchanged]
        ├── PunchSequenceService (ModuleScript)   [unchanged]
        ├── GuessingService (ModuleScript)        [unchanged]
        ├── MatchResultService (ModuleScript)     [unchanged]
        ├── SpectatorService (ModuleScript)       [unchanged]
        ├── QueueUIService (ModuleScript)         [NEW]
        └── HudService (ModuleScript)             [NEW]
ReplicatedStorage > Shared > Config (ModuleScript) [updated]
PlayerGui (runtime, code-created)
├── QueueGui (ScreenGui)  - lobby only: Title, Subtitle, Slot2/Slot4/Slot6 rows (TitleLabel, StatusLabel, JoinButton, LeaveButton)
├── MatchHud (ScreenGui)  - match only: RoleChip, HealthBar (Fill + Label), Prompt
└── ...existing system GUIs (PowerGaugeDebugGui, GuessingDebugGui, SpectatorGui, banners)
```

## E. Properties
- `QueueUIService` and `HudService` ModuleScripts: Name EXACTLY as listed, Parent `GuessThePuncherClient > Services`.
- All GUI instances are created by code with exact names above (runtime only). No asset IDs used anywhere (fonts are Enum.Font.Gotham/GothamBold/GothamBlack, colors are Color3 values).
- Config toggles: `Config.ShowQueueUI`, `Config.ShowMatchHud`, `Config.UIEnabled` (master switch).

## F. Copy instructions
1. `src/Shared/Config.luau` -> `ReplicatedStorage > Shared > Config`
2. NEW ModuleScript `QueueUIService` in `GuessThePuncherClient > Services`, paste `src/Client/Services/QueueUIService.luau`
3. NEW ModuleScript `HudService` in `GuessThePuncherClient > Services`, paste `src/Client/Services/HudService.luau`
4. `src/Client/Main.client.luau` -> `GuessThePuncherClient` (LocalScript, REPLACE WHOLE)
5. Claude MCP: flat/ files (flat/Client_QueueUIService.luau -> QueueUIService etc.)
6. Or run `docs/CommandBar_UI.txt` first (creates the 2 ModuleScripts)

## G. Tests (multiplayer: Test > Clients and Servers, 2-4 players)
1. **Lobby panel**: Join the game -> "GUESS THE PUNCHER" panel with 3 rows shows "0/2 Open", "0/4 Open", "0/6 Open".
2. **Join via button**: Click JOIN on Slot2 -> server adds you -> row updates "1/2 Open", your row highlights blue, button swaps to red LEAVE; second client joins -> "2/2", state becomes "Starting in 5s..." (countdown live).
3. **Leave before start**: Click LEAVE -> removed, row shows 1/2 again (or countdown cancels if <2 remain - server logic).
4. **Locked row**: Once the countdown runs, JOIN presses are ignored/rejected by the server; rows show LOCKED/STARTING while handing off.
5. **Panel hides in match**: When the match starts (Preparing), QueueGui disappears and MatchHud appears: role chip "Queued | Preparing", prompt "Match starting...", health bar at 100/100 default.
6. **Role chip**: Target selected -> your chip shows "Target | WaitingForPuncher" (orange) and prompt "Waiting for a Puncher..."; a PotentialPuncher sees "PotentialPuncher | WaitingForPuncher" + "Press [F] to become the Puncher!". As TARGET you must NOT see "Puncher" anywhere in the chip after selection - only masked roles (server-filtered payloads).
7. **Prep countdown**: Someone presses F -> Puncher's prompt "Get ready... 3.0 -> 0.0" (from RE_PuncherPreparation); others see "The Puncher is preparing...".
8. **Gauge prompt**: State PowerGauge -> Puncher sees "Press [E] to lock the gauge!" plus the gauge panel; others see "The Puncher is charging the punch...".
9. **Health bar**: Lock Weak -> bar drops to 90/100 (yellow at <=60, red at <=30); new Target/round -> bar refills ("last: -0 Reset"). Perfect -> 0/100 red + "KNOCKED OUT!" prompt.
10. **Guess prompt**: State Guessing -> Target sees "Pick who punched you!" + choice panel; others see "The Target is guessing...".
11. **Spectator**: Get eliminated -> chip "Spectator | <state>", no center prompt (SpectatorService panel shows instead), health bar still tracks the Target.
12. **Match end**: Result banner shows -> 5s later everyone in the lobby -> MatchHud disappears, QueueGui returns; join a new slot and play again end-to-end.
13. **Toggles**: Set `Config.ShowQueueUI = false` -> no lobby panel (walk-on EntryArea still works). `ShowMatchHud = false` -> no HUD.

## H. Expected results
- The game is fully playable from UI alone: join/leave queue with buttons, every phase prompts the right player (F punch prompt, E lock prompt, guess panel, spectator panel, result banners), Target health always visible and server-accurate, panel swap lobby<->match automatic.
- No client authority added: buttons only fire existing validated remotes; every display value comes from server payloads (filtered - the Target never sees Puncher identity in the HUD).
- No asset IDs used; all UI is code-created and safe to re-create on respawn (ResetOnSpawn=false, services rebuild).

## I. Common errors and fixes
- No lobby panel: `[QueueUIService] Ready` missing in Output -> ModuleScript not installed/named wrong; check `Config.ShowQueueUI` and `Config.UIEnabled`.
- Buttons do nothing: check server Output for `[QueueService] JoinRequest ...` - if absent, remotes missing (re-run updated Main.server/MatchService) or you were rejected (already in match / locked / full) - the server prints the reason.
- Rows never update: RE_QueueStateUpdate not firing -> QueueService outdated; re-copy it.
- No HUD in match: `[HudService] Ready` missing or `ShowMatchHud = false`; HUD appears only after the first state update in a match (MatchStart/StateUpdate).
- Health bar stuck at 100: RE_TargetHealthUpdate missing -> update MatchService; bar defaults per match until the first hit.
- Wrong prompt for my role: role comes from FILTERED payloads; if the Target sees "Puncher" role in the chip, an OLD MatchService is running (masking regression) - replace the whole 2163-line file.
- Panels overlap: HUD prompt sits at y=0.68 below the gauge panel (0.82) and guess panel (0.25) by design; adjust positions inside the services if your screen layout needs it.
- GUIs duplicate after respawn: services destroy/rebuild via ResetOnSpawn=false + HandleMatchEnd; re-copy both services if you see stacking.

## J. Not implemented (future - do not test)
- Custom imagery/logos/animations for UI (placeholder code-created UI only, no asset IDs provided)
- Damage numbers floating UI, kill feed, minimap, spectator list UI, rematch button, shop/coins (no monetization ever requested)
- Mobile/console button layouts (keyboard prompts [F]/[E] shown; touch users can still use the guess/spectator BUTTONS, and queue buttons work on touch)
