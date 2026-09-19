# Claude MCP Setup - Guess the Puncher Queue System

This file is for **Claude** (or any AI with MCP connection to Roblox Studio) to automatically create all folders and scripts needed for the queue system.

You can paste scripts directly - no manual .luau extensions, just names as requested.

---

## What Claude Needs To Do

1. **Create ReplicatedStorage folders:**
   - `ReplicatedStorage/Shared` (Folder)
   - `ReplicatedStorage/Remotes` (Folder) - auto-created by server but create anyway

2. **Create Shared ModuleScripts (9) with code inside:**
   - `Config` - centralized config (capacities 2,4,6, min 2, countdowns, damages, etc.)
   - `QueueStates` - WAITING, COUNTDOWN_FULL, COUNTDOWN_PARTIAL, LOCKED, STARTING, CANCELLED
   - `RemoteNames` - RE_QueueJoinRequest etc.
   - `Constants` - standalone, NO requires (fixes yellow underline error)
   - `MatchStates` - future use
   - `Roles` - future
   - `PowerZones` - future
   - `Results` - future
   - `Types` - future

3. **Create ServerScriptService folders and scripts:**
   - `ServerScriptService/Services` (Folder)
   - `Services/RemoteService` (ModuleScript)
   - `Services/QueueService` (ModuleScript) - full queue logic
   - `ServerScriptService/GuessThePuncherServer` (Script) - main server

4. **Create StarterPlayerScripts:**
   - `StarterPlayer/StarterPlayerScripts/GuessThePuncherClient` (LocalScript) - test client

5. **Create Workspace folders and physical objects:**
   - `Workspace.Lobby` (Folder)
   - `Workspace.Lobby/SpawnLocation` (SpawnLocation)
   - `Workspace.Lobby/MatchSlots` (Folder)
   - `Workspace.Lobby.MatchSlots/Slot2, Slot4, Slot6` (Models) each with:
     - `EntryArea` (Part) 6x1x6 Anchored CanCollide false - physical entry
     - `LeaveButton` (Part) 3x1x3 + ClickDetector
     - `DisplayBoard` (Part) 4x6x0.5 + BillboardGui with OccupancyLabel, StatusLabel, CountdownLabel
     - `PlayerSpawns` (Folder) with Player1..N Parts 3x1x3 Anchored
   - `Workspace.MatchArenas` (Folder)
   - `Workspace.MatchArenas/Arena2, Arena4, Arena6` (Models) at 0,100,0 / 200,100,0 / 400,100,0 each with:
     - `TargetStand` (Part) 4x1x4 + `Chair` (Seat) inside - target sits on chair as requested
     - `PuncherStand` (Part) 4x1x4 6 studs behind TargetStand
     - `PlayerSpawns` (Folder) Player1..N

6. **No spectator stands** as requested.

---

## MASTER SCRIPT - Paste Once (Creates Everything)

**This single script creates all folders and ModuleScripts with actual code inside. Paste into Command Bar or run via MCP.**

```lua
-- MASTER SETUP SCRIPT FOR CLAUDE MCP - Guess the Puncher Queue System
-- Creates all folders and scripts with code, no .luau extensions, just names
-- Run once in Studio Command Bar or via MCP

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterGui = game:GetService("StarterGui")

print("=== STARTING MASTER SETUP ===")

-- ==================== ReplicatedStorage/Shared ====================
local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
if not sharedFolder then
    sharedFolder = Instance.new("Folder")
    sharedFolder.Name = "Shared"
    sharedFolder.Parent = ReplicatedStorage
end

-- Config
local configCode = [=[
--!nonstrict
-- Config.luau - Centralized configuration
local Config = {}
Config.QueueCapacities = {Slot2 = 2, Slot4 = 4, Slot6 = 6}
Config.QueueCapacityList = {2, 4, 6}
Config.MinimumPlayers = 2
Config.QueueFullCountdown = 5
Config.QueuePartialWaitTime = 30
Config.QueuePartialCountdown = 5
Config.QueueCountdownDuration = 10
Config.MatchPreparationTime = 3
Config.PunchSelectionDuration = 10
Config.PowerGaugeDuration = 5
Config.GuessingDuration = 15
Config.KnockoutDuration = 3
Config.LobbyReturnDelay = 5
Config.StartingHealth = 100
Config.Damage = {Miss = 0, Weak = 10, Normal = 25, Strong = 50, Perfect = 100}
Config.WeakDamage = 10
Config.NormalDamage = 25
Config.StrongDamage = 50
Config.PerfectDamage = 100
Config.MissDamage = 0
Config.PerfectIsInstantKO = true
Config.TeleportOffsetY = 3
Config.PuncherOffsetBehindTarget = 6
Config.PuncherInvisibleToTarget = true
Config.TouchDebounce = 1
Config.PunchRequestCooldown = 0.5
Config.DebugPrints = true
return Config
]=]

local function createModule(parent, name, code)
    local existing = parent:FindFirstChild(name)
    if existing then
        if existing:IsA("ModuleScript") then
            existing.Source = code
            print("Updated ModuleScript: "..parent.Name.."/"..name)
            return existing
        else
            existing:Destroy()
        end
    end
    local m = Instance.new("ModuleScript")
    m.Name = name
    m.Source = code
    m.Parent = parent
    print("Created ModuleScript: "..parent.Name.."/"..name)
    return m
end

createModule(sharedFolder, "Config", configCode)

-- QueueStates
local queueStatesCode = [=[
--!nonstrict
-- QueueStates.luau
local QueueStates = {}
QueueStates.States = {
    WAITING = "WAITING",
    COUNTDOWN_FULL = "COUNTDOWN_FULL",
    COUNTDOWN_PARTIAL = "COUNTDOWN_PARTIAL",
    LOCKED = "LOCKED",
    STARTING = "STARTING",
    CANCELLED = "CANCELLED",
}
QueueStates.List = {"WAITING","COUNTDOWN_FULL","COUNTDOWN_PARTIAL","LOCKED","STARTING","CANCELLED"}
function QueueStates.IsCountingDown(state: string): boolean
    return state == QueueStates.States.COUNTDOWN_FULL or state == QueueStates.States.COUNTDOWN_PARTIAL
end
function QueueStates.CanJoin(state: string): boolean
    return state == QueueStates.States.WAITING
end
return QueueStates
]=]
createModule(sharedFolder, "QueueStates", queueStatesCode)

-- RemoteNames
local remoteNamesCode = [=[
--!nonstrict
-- RemoteNames.luau
local RemoteNames = {}
RemoteNames.Queue = {
    JoinRequest = "RE_QueueJoinRequest",
    LeaveRequest = "RE_QueueLeaveRequest",
    StateUpdate = "RE_QueueStateUpdate",
    CountdownUpdate = "RE_QueueCountdownUpdate",
    Locked = "RE_QueueLocked",
    Started = "RE_QueueStarted",
    PlayerLeft = "RE_QueuePlayerLeft",
}
RemoteNames.Match = {
    MatchStart = "RE_MatchStart",
    MatchStateUpdate = "RE_MatchStateUpdate",
    PunchOpportunityOpen = "RE_PunchOpportunityOpen",
    PunchRequest = "RE_PunchRequest",
    PuncherSelected = "RE_PuncherSelected",
    PowerGaugeOpen = "RE_PowerGaugeOpen",
    PowerGaugeStopRequest = "RE_PowerGaugeStopRequest",
    PowerGaugeResult = "RE_PowerGaugeResult",
    DamageApplied = "RE_DamageApplied",
    GuessOpen = "RE_GuessOpen",
    GuessRequest = "RE_GuessRequest",
    GuessResult = "RE_GuessResult",
    TargetEliminated = "RE_TargetEliminated",
    MatchEnd = "RE_MatchEnd",
    CameraMode = "RE_CameraMode",
    AnimationPlay = "RE_AnimationPlay",
}
RemoteNames.All = {}
for _, name in pairs(RemoteNames.Queue) do table.insert(RemoteNames.All, name) end
for _, name in pairs(RemoteNames.Match) do table.insert(RemoteNames.All, name) end
return RemoteNames
]=]
createModule(sharedFolder, "RemoteNames", remoteNamesCode)

-- Constants (standalone, no requires - fixes yellow underline)
local constantsCode = [=[
--!nonstrict
-- Constants.luau - Standalone, NO requires
local Constants = {}
Constants.QueueCapacities = {Slot2 = 2, Slot4 = 4, Slot6 = 6}
Constants.MinimumPlayers = 2
Constants.Remotes = {
    QueueJoinRequest = "RE_QueueJoinRequest",
    QueueLeaveRequest = "RE_QueueLeaveRequest",
    QueueStateUpdate = "RE_QueueStateUpdate",
    QueueCountdownUpdate = "RE_QueueCountdownUpdate",
    QueueLocked = "RE_QueueLocked",
    QueueStarted = "RE_QueueStarted",
    QueuePlayerLeft = "RE_QueuePlayerLeft",
    MatchStart = "RE_MatchStart",
    MatchStateUpdate = "RE_MatchStateUpdate",
    PunchOpportunityOpen = "RE_PunchOpportunityOpen",
    PunchRequest = "RE_PunchRequest",
    PuncherSelected = "RE_PuncherSelected",
    PowerGaugeOpen = "RE_PowerGaugeOpen",
    PowerGaugeStopRequest = "RE_PowerGaugeStopRequest",
    PowerGaugeResult = "RE_PowerGaugeResult",
    DamageApplied = "RE_DamageApplied",
    GuessOpen = "RE_GuessOpen",
    GuessRequest = "RE_GuessRequest",
    GuessResult = "RE_GuessResult",
    TargetEliminated = "RE_TargetEliminated",
    MatchEnd = "RE_MatchEnd",
    CameraMode = "RE_CameraMode",
    AnimationPlay = "RE_AnimationPlay",
}
Constants.AllRemoteNames = {}
for _, name in pairs(Constants.Remotes) do table.insert(Constants.AllRemoteNames, name) end
Constants.Tags = {QueueEntry = "QueueEntry", TargetStand = "TargetStand", PuncherStand = "PuncherStand", PlayerSpawn = "PlayerSpawn", QueueDisplay = "QueueDisplay"}
return Constants
]=]
createModule(sharedFolder, "Constants", constantsCode)

-- Other shared (future use, minimal)
createModule(sharedFolder, "MatchStates", [=[
--!nonstrict
local MatchStates = {}
MatchStates.States = {WAITING_FOR_PLAYERS="WAITING_FOR_PLAYERS",COUNTDOWN="COUNTDOWN",PREPARING="PREPARING",ROUND_START="ROUND_START",PUNCH_SELECTION="PUNCH_SELECTION",PUNCHER_SELECTED="PUNCHER_SELECTED",POWER_GAUGE="POWER_GAUGE",PUNCH_EXECUTING="PUNCH_EXECUTING",GUESSING="GUESSING",GUESS_RESULT="GUESS_RESULT",TARGET_ELIMINATED="TARGET_ELIMINATED",MATCH_ENDING="MATCH_ENDING",LOBBY_RETURN="LOBBY_RETURN"}
return MatchStates
]=])

createModule(sharedFolder, "Roles", [=[
--!nonstrict
local Roles = {}
Roles.Roles = {NONE="NONE",LOBBY="LOBBY",QUEUED="QUEUED",TARGET="TARGET",PUNCHER="PUNCHER",SPECTATOR="SPECTATOR",ELIMINATED="ELIMINATED",WINNER="WINNER"}
return Roles
]=])

createModule(sharedFolder, "PowerZones", [=[
--!nonstrict
local PowerZones = {}
PowerZones.Zones = {MISS="Miss",WEAK="Weak",NORMAL="Normal",STRONG="Strong",PERFECT="Perfect"}
return PowerZones
]=])

createModule(sharedFolder, "Results", [=[
--!nonstrict
local Results = {}
Results.GuessResults = {CORRECT="Correct",WRONG="Wrong",TIMEOUT="Timeout"}
Results.MatchResults = {WINNER="Winner",ELIMINATED="Eliminated",DRAW="Draw",CANCELLED="Cancelled"}
return Results
]=])

createModule(sharedFolder, "Types", [=[
--!nonstrict
return {}
]=])

-- ==================== Remotes ====================
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
    remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "Remotes"
    remotesFolder.Parent = ReplicatedStorage
end
for _, name in ipairs({"RE_QueueJoinRequest","RE_QueueLeaveRequest","RE_QueueStateUpdate","RE_QueueCountdownUpdate","RE_QueueLocked","RE_QueueStarted","RE_QueuePlayerLeft","RE_MatchStart","RE_MatchStateUpdate","RE_PunchOpportunityOpen","RE_PunchRequest","RE_PuncherSelected","RE_PowerGaugeOpen","RE_PowerGaugeStopRequest","RE_PowerGaugeResult","RE_DamageApplied","RE_GuessOpen","RE_GuessRequest","RE_GuessResult","RE_TargetEliminated","RE_MatchEnd","RE_CameraMode","RE_AnimationPlay"}) do
    if not remotesFolder:FindFirstChild(name) then
        local re = Instance.new("RemoteEvent")
        re.Name = name
        re.Parent = remotesFolder
        print("Created Remotes/"..name)
    end
end

-- ==================== Server ====================
local servicesFolder = ServerScriptService:FindFirstChild("Services")
if not servicesFolder then
    servicesFolder = Instance.new("Folder")
    servicesFolder.Name = "Services"
    servicesFolder.Parent = ServerScriptService
end

-- RemoteService
local remoteServiceCode = [=[
--!nonstrict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteService = {}
function RemoteService.EnsureFolder(): Folder
    local folder = ReplicatedStorage:FindFirstChild("Remotes")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "Remotes"
        folder.Parent = ReplicatedStorage
    end
    return folder
end
function RemoteService.EnsureRemote(name: string): RemoteEvent
    local folder = RemoteService.EnsureFolder()
    local existing = folder:FindFirstChild(name)
    if existing and existing:IsA("RemoteEvent") then return existing end
    if existing then existing:Destroy() end
    local re = Instance.new("RemoteEvent")
    re.Name = name
    re.Parent = folder
    return re
end
function RemoteService.EnsureAllRemotes(names: {string})
    for _, name in ipairs(names) do RemoteService.EnsureRemote(name) end
end
function RemoteService.GetRemote(name: string): RemoteEvent?
    local folder = ReplicatedStorage:FindFirstChild("Remotes")
    if not folder then return nil end
    local obj = folder:FindFirstChild(name)
    if obj and obj:IsA("RemoteEvent") then return obj end
    return nil
end
return RemoteService
]=]
createModule(servicesFolder, "RemoteService", remoteServiceCode)

-- QueueService - FULL CODE (truncated for brevity in this master script, will be pasted from GitHub in actual run)
-- For MCP, Claude should paste full QueueService code from src/Server/Services/QueueService.luau
-- Below is placeholder that says to paste full code, but for auto-setup we include full code via separate file
-- To keep this master script short, we will create empty and instruct to paste, but MCP can directly set Source from GitHub

-- For full auto, you need to copy the entire QueueService.luau content here
-- Since it's long, Claude should read src/Server/Services/QueueService.luau from GitHub and set Source

-- We will attempt to create with minimal version that still works for queue
local queueServiceCode = [=[
--!nonstrict
-- QueueService.luau - Full queue logic (see GitHub src/Server/Services/QueueService.luau for full code)
-- This is a minimal version for MCP auto-setup - replace with full code from GitHub for production

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QueueService = {}
QueueService.Slots = {}
QueueService.SlotOrder = {"Slot2","Slot4","Slot6"}
QueueService.PendingMatches = {}

local Config
local QueueStates
local remotes = {}

local function getPlayerFromCharacter(character: Model): Player?
    return Players:GetPlayerFromCharacter(character)
end

local function findSlotContainingPlayer(userId: number): string?
    for slotId, slotData in pairs(QueueService.Slots) do
        if slotData.players[userId] then return slotId end
    end
    return nil
end

local function broadcastStateUpdate(slotId: string)
    local slotData = QueueService.Slots[slotId]
    if not slotData then return end
    local occupancyList = {}
    for userId, _ in pairs(slotData.players) do table.insert(occupancyList, userId) end
    local re = remotes.StateUpdate
    if re then re:FireAllClients(slotId, occupancyList, slotData.maxPlayers, slotData.state, slotData.countdownTimeLeft, slotData.locked, slotData.occupancy) end
    if slotData.displayBoard then
        local billboard = slotData.displayBoard:FindFirstChildOfClass("BillboardGui")
        if billboard then
            local occ = billboard:FindFirstChild("OccupancyLabel")
            if occ and occ:IsA("TextLabel") then occ.Text = slotData.occupancy.."/"..slotData.maxPlayers end
            local status = billboard:FindFirstChild("StatusLabel")
            if status and status:IsA("TextLabel") then status.Text = slotData.state end
        end
    end
end

function QueueService.TryJoinSlot(player: Player, slotId: string): (boolean, string)
    if findSlotContainingPlayer(player.UserId) then return false, "Already in slot" end
    local slotData = QueueService.Slots[slotId]
    if not slotData then return false, "Slot not found" end
    if slotData.locked or slotData.state ~= "WAITING" then return false, "Slot locked" end
    if slotData.occupancy >= slotData.maxPlayers then return false, "Slot full" end
    slotData.players[player.UserId] = player
    slotData.occupancy += 1
    if slotData.occupancy >= 2 and not slotData.waitStartTick then slotData.waitStartTick = tick() end
    -- teleport
    local char = player.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp and slotData.playerSpawnsFolder then
            local spawn = slotData.playerSpawnsFolder:FindFirstChild("Player"..slotData.occupancy)
            if spawn and spawn:IsA("BasePart") then hrp.CFrame = spawn.CFrame + Vector3.new(0,3,0) end
        end
    end
    broadcastStateUpdate(slotId)
    if slotData.occupancy == slotData.maxPlayers then QueueService.StartCountdown(slotId, "FULL") end
    return true, "Joined"
end

function QueueService.LeaveSlot(player: Player): (boolean, string)
    local slotId = findSlotContainingPlayer(player.UserId)
    if not slotId then return false, "Not in slot" end
    local slotData = QueueService.Slots[slotId]
    if slotData.state == "LOCKED" or slotData.state == "STARTING" then return false, "Cannot leave, starting" end
    slotData.players[player.UserId] = nil
    slotData.occupancy = math.max(0, slotData.occupancy-1)
    if slotData.occupancy < 2 and (slotData.state == "COUNTDOWN_FULL" or slotData.state == "COUNTDOWN_PARTIAL") then
        QueueService.CancelCountdown(slotId, "Not enough players")
    end
    if slotData.occupancy < 2 then slotData.waitStartTick = nil end
    local char = player.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.CFrame = CFrame.new(0,5,0) end
    end
    broadcastStateUpdate(slotId)
    return true, "Left"
end

function QueueService.StartCountdown(slotId: string, type: string)
    local slotData = QueueService.Slots[slotId]
    if not slotData then return end
    local duration = (type == "FULL") and Config.QueueFullCountdown or Config.QueuePartialCountdown
    slotData.state = (type == "FULL") and "COUNTDOWN_FULL" or "COUNTDOWN_PARTIAL"
    slotData.countdownActive = true
    slotData.countdownTimeLeft = duration
    slotData.countdownEndTick = tick() + duration
    slotData.locked = true
    broadcastStateUpdate(slotId)
    print("[QueueService] Countdown "..slotId.." "..type.." "..duration)
end

function QueueService.CancelCountdown(slotId: string, reason: string)
    local slotData = QueueService.Slots[slotId]
    if not slotData then return end
    slotData.state = "WAITING"
    slotData.countdownActive = false
    slotData.countdownTimeLeft = 0
    slotData.locked = false
    if slotData.occupancy < 2 then slotData.waitStartTick = nil end
    broadcastStateUpdate(slotId)
    print("[QueueService] Cancelled "..slotId.." "..reason)
end

function QueueService.FinishCountdown(slotId: string)
    local slotData = QueueService.Slots[slotId]
    if not slotData then return end
    if slotData.occupancy < 2 then QueueService.CancelCountdown(slotId, "Not enough") return end
    slotData.state = "LOCKED"
    slotData.locked = true
    broadcastStateUpdate(slotId)
    local playerList = {}
    for uid,_ in pairs(slotData.players) do table.insert(playerList, uid) end
    QueueService.PendingMatches[slotId] = {slotId=slotId, players=playerList, readyTick=tick()}
    slotData.state = "STARTING"
    broadcastStateUpdate(slotId)
    local re = remotes.Started
    if re then re:FireAllClients(slotId, playerList) end
    print("[QueueService] Finished "..slotId.." handoff "..#playerList)
    task.delay(Config.LobbyReturnDelay or 5, function()
        if QueueService.Slots[slotId] and QueueService.Slots[slotId].state == "STARTING" then
            QueueService.ReleaseSlot(slotId)
        end
    end)
end

function QueueService.ReleaseSlot(slotId: string)
    local slotData = QueueService.Slots[slotId]
    if not slotData then return end
    for _, plr in pairs(slotData.players) do
        if plr and plr.Parent and plr.Character then
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.CFrame = CFrame.new(0,5,0) end
        end
    end
    slotData.players = {}
    slotData.occupancy = 0
    slotData.state = "WAITING"
    slotData.countdownActive = false
    slotData.countdownTimeLeft = 0
    slotData.countdownEndTick = nil
    slotData.waitStartTick = nil
    slotData.locked = false
    QueueService.PendingMatches[slotId] = nil
    broadcastStateUpdate(slotId)
    print("[QueueService] Released "..slotId)
end

function QueueService.Init()
    print("[QueueService] Initializing...")
    local Shared = ReplicatedStorage:WaitForChild("Shared", 10)
    Config = require(Shared:WaitForChild("Config"))
    QueueStates = require(Shared:WaitForChild("QueueStates"))
    local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
    if remotesFolder then
        remotes.StateUpdate = remotesFolder:FindFirstChild("RE_QueueStateUpdate")
        remotes.CountdownUpdate = remotesFolder:FindFirstChild("RE_QueueCountdownUpdate")
        remotes.Locked = remotesFolder:FindFirstChild("RE_QueueLocked")
        remotes.Started = remotesFolder:FindFirstChild("RE_QueueStarted")
        remotes.PlayerLeft = remotesFolder:FindFirstChild("RE_QueuePlayerLeft")
        remotes.JoinRequest = remotesFolder:FindFirstChild("RE_QueueJoinRequest")
        remotes.LeaveRequest = remotesFolder:FindFirstChild("RE_QueueLeaveRequest")
    end
    local lobby = Workspace:FindFirstChild("Lobby")
    if not lobby then lobby = Instance.new("Folder") lobby.Name="Lobby" lobby.Parent=Workspace end
    local matchSlots = lobby:FindFirstChild("MatchSlots")
    if not matchSlots then matchSlots = Instance.new("Folder") matchSlots.Name="MatchSlots" matchSlots.Parent=lobby end
    for _, slotId in ipairs(QueueService.SlotOrder) do
        local slotModel = matchSlots:FindFirstChild(slotId)
        local entryPart = slotModel and (slotModel:FindFirstChild("EntryArea") or slotModel:FindFirstChild("TouchBlock"))
        local displayBoard = slotModel and slotModel:FindFirstChild("DisplayBoard")
        local spawnsFolder = slotModel and slotModel:FindFirstChild("PlayerSpawns")
        local maxPlayers = Config.QueueCapacities[slotId] or 2
        QueueService.Slots[slotId] = {
            id=slotId, maxPlayers=maxPlayers, players={}, occupancy=0, state="WAITING",
            countdownActive=false, countdownTimeLeft=0, countdownEndTick=nil, waitStartTick=nil, locked=false,
            entryPart=entryPart, displayBoard=displayBoard, playerSpawnsFolder=spawnsFolder, touchDebounce={}
        }
        if entryPart and entryPart:IsA("BasePart") then
            entryPart.Touched:Connect(function(hit)
                local char = hit.Parent
                if not char then return end
                local plr = game.Players:GetPlayerFromCharacter(char)
                if not plr then return end
                local now = tick()
                local last = QueueService.Slots[slotId].touchDebounce[plr.UserId] or 0
                if now - last < 1 then return end
                QueueService.Slots[slotId].touchDebounce[plr.UserId] = now
                QueueService.TryJoinSlot(plr, slotId)
            end)
        end
    end
    if remotes.JoinRequest then
        remotes.JoinRequest.OnServerEvent:Connect(function(plr, slotId)
            if typeof(slotId) ~= "string" then return end
            QueueService.TryJoinSlot(plr, slotId)
        end)
    end
    if remotes.LeaveRequest then
        remotes.LeaveRequest.OnServerEvent:Connect(function(plr)
            QueueService.LeaveSlot(plr)
        end)
    end
    game.Players.PlayerRemoving:Connect(function(plr) QueueService.LeaveSlot(plr) end)
    task.spawn(function()
        while true do
            task.wait(1)
            local now = tick()
            for slotId, slotData in pairs(QueueService.Slots) do
                if slotData.state == "WAITING" then
                    if slotData.occupancy >= 2 and slotData.occupancy < slotData.maxPlayers then
                        if not slotData.waitStartTick then slotData.waitStartTick = now
                        else
                            if now - slotData.waitStartTick >= (Config.QueuePartialWaitTime or 30) then
                                QueueService.StartCountdown(slotId, "PARTIAL")
                            end
                        end
                    elseif slotData.occupancy < 2 then
                        slotData.waitStartTick = nil
                    end
                elseif slotData.state == "COUNTDOWN_FULL" or slotData.state == "COUNTDOWN_PARTIAL" then
                    if slotData.countdownEndTick then
                        local left = slotData.countdownEndTick - now
                        slotData.countdownTimeLeft = math.max(0, left)
                        if remotes.CountdownUpdate then remotes.CountdownUpdate:FireAllClients(slotId, slotData.countdownTimeLeft) end
                        if left <= 0 then QueueService.FinishCountdown(slotId) end
                        if slotData.occupancy < 2 then QueueService.CancelCountdown(slotId, "Not enough") end
                    end
                end
            end
        end
    end)
    print("[QueueService] Initialized")
end

return QueueService
]=]
createModule(servicesFolder, "QueueService", queueServiceCode)

-- Main.server.luau
local mainServerCode = [=[
--!nonstrict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
print("[GuessThePuncherServer] Starting Queue System...")
local sharedFolder = ReplicatedStorage:WaitForChild("Shared", 10)
if not sharedFolder then error("Missing Shared") end
local function safeRequire(name)
    local mod = sharedFolder:FindFirstChild(name)
    if not mod then warn("Missing Shared/"..name) return nil end
    local ok, res = pcall(require, mod)
    if not ok then warn("Failed require "..name..": "..tostring(res)) return nil end
    return res
end
local Config = safeRequire("Config")
if not Config then error("Config missing") end
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
    remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "Remotes"
    remotesFolder.Parent = ReplicatedStorage
end
local allRemotes = {"RE_QueueJoinRequest","RE_QueueLeaveRequest","RE_QueueStateUpdate","RE_QueueCountdownUpdate","RE_QueueLocked","RE_QueueStarted","RE_QueuePlayerLeft","RE_MatchStart","RE_MatchStateUpdate","RE_PunchOpportunityOpen","RE_PunchRequest","RE_PuncherSelected","RE_PowerGaugeOpen","RE_PowerGaugeStopRequest","RE_PowerGaugeResult","RE_DamageApplied","RE_GuessOpen","RE_GuessRequest","RE_GuessResult","RE_TargetEliminated","RE_MatchEnd","RE_CameraMode","RE_AnimationPlay"}
for _, name in ipairs(allRemotes) do
    if not remotesFolder:FindFirstChild(name) then
        local re = Instance.new("RemoteEvent")
        re.Name = name
        re.Parent = remotesFolder
    end
end
print("[GuessThePuncherServer] Remotes ready")
local servicesFolder = script.Parent:FindFirstChild("Services") or game:GetService("ServerScriptService"):FindFirstChild("Services")
if servicesFolder then
    local qsMod = servicesFolder:FindFirstChild("QueueService")
    if qsMod then
        local ok, qs = pcall(require, qsMod)
        if ok and qs then qs.Init() print("[GuessThePuncherServer] QueueService initialized") end
    end
end
print("[GuessThePuncherServer] Queue System ready")
]=]

local existingServer = ServerScriptService:FindFirstChild("GuessThePuncherServer")
if existingServer then existingServer:Destroy() end
local serverScript = Instance.new("Script")
serverScript.Name = "GuessThePuncherServer"
serverScript.Source = mainServerCode
serverScript.Parent = ServerScriptService
print("Created ServerScriptService/GuessThePuncherServer")

-- ==================== Client ====================
local StarterPlayer = game:GetService("StarterPlayer")
local sps = StarterPlayer:FindFirstChild("StarterPlayerScripts")
if sps then
    local clientCode = [=[
--!nonstrict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
print("[QueueClient] Starting for "..player.Name)
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
if not remotesFolder then return end
local stateUpdate = remotesFolder:WaitForChild("RE_QueueStateUpdate", 10)
if stateUpdate then
    stateUpdate.OnClientEvent:Connect(function(slotId, occupancyList, maxPlayers, state, countdownTimeLeft, locked, occupancyCount)
        print(string.format("[QueueClient] %s: %d/%d state=%s countdown=%.1f locked=%s", slotId, occupancyCount or #occupancyList, maxPlayers, state, countdownTimeLeft or 0, tostring(locked)))
    end)
end
print("[QueueClient] Ready. Use: game.ReplicatedStorage.Remotes.RE_QueueJoinRequest:FireServer('Slot2')")
]=]
    local existingClient = sps:FindFirstChild("GuessThePuncherClient")
    if existingClient then existingClient:Destroy() end
    local client = Instance.new("LocalScript")
    client.Name = "GuessThePuncherClient"
    client.Source = clientCode
    client.Parent = sps
    print("Created StarterPlayerScripts/GuessThePuncherClient")
end

-- ==================== Workspace ====================
local lobby = Workspace:FindFirstChild("Lobby")
if not lobby then
    lobby = Instance.new("Folder")
    lobby.Name = "Lobby"
    lobby.Parent = Workspace
end

if not lobby:FindFirstChild("SpawnLocation") then
    local spawn = Instance.new("SpawnLocation")
    spawn.Name = "SpawnLocation"
    spawn.Size = Vector3.new(6,1,6)
    spawn.Anchored = true
    spawn.Neutral = true
    spawn.Position = Vector3.new(0,3,0)
    spawn.Parent = lobby
end

local matchSlots = lobby:FindFirstChild("MatchSlots")
if not matchSlots then
    matchSlots = Instance.new("Folder")
    matchSlots.Name = "MatchSlots"
    matchSlots.Parent = lobby
end

local arenasFolder = Workspace:FindFirstChild("MatchArenas")
if not arenasFolder then
    arenasFolder = Instance.new("Folder")
    arenasFolder.Name = "MatchArenas"
    arenasFolder.Parent = Workspace
end

local function createQueueSlot(parentFolder, slotName, playerCount, basePos)
    local slotModel = parentFolder:FindFirstChild(slotName)
    if not slotModel then
        slotModel = Instance.new("Model")
        slotModel.Name = slotName
        slotModel.Parent = parentFolder
    end
    slotModel:SetAttribute("SlotId", slotName)
    slotModel:SetAttribute("MaxPlayers", playerCount)
    if not slotModel:FindFirstChild("EntryArea") then
        local part = Instance.new("Part")
        part.Name = "EntryArea"
        part.Size = Vector3.new(6,1,6)
        part.Anchored = true
        part.CanCollide = false
        part.Transparency = 0.3
        part.Color = Color3.fromRGB(0,170,255)
        part.Material = Enum.Material.ForceField
        part.Position = basePos
        part.Parent = slotModel
    end
    if not slotModel:FindFirstChild("LeaveButton") then
        local part = Instance.new("Part")
        part.Name = "LeaveButton"
        part.Size = Vector3.new(3,1,3)
        part.Anchored = true
        part.CanCollide = false
        part.Color = Color3.fromRGB(255,0,0)
        part.Position = basePos + Vector3.new(0,0,5)
        part.Parent = slotModel
        local cd = Instance.new("ClickDetector")
        cd.Parent = part
    end
    if not slotModel:FindFirstChild("DisplayBoard") then
        local part = Instance.new("Part")
        part.Name = "DisplayBoard"
        part.Size = Vector3.new(4,6,0.5)
        part.Anchored = true
        part.Position = basePos + Vector3.new(0,5,0)
        part.Parent = slotModel
        local bg = Instance.new("BillboardGui")
        bg.Name = "BillboardGui"
        bg.Size = UDim2.new(0,200,0,150)
        bg.StudsOffset = Vector3.new(0,3,0)
        bg.AlwaysOnTop = true
        bg.Parent = part
        local occ = Instance.new("TextLabel")
        occ.Name = "OccupancyLabel"
        occ.Size = UDim2.new(1,0,0.3,0)
        occ.Text = "0/"..playerCount
        occ.TextScaled = true
        occ.Parent = bg
        local status = Instance.new("TextLabel")
        status.Name = "StatusLabel"
        status.Size = UDim2.new(1,0,0.3,0)
        status.Position = UDim2.new(0,0,0.3,0)
        status.Text = "WAITING"
        status.TextScaled = true
        status.Parent = bg
        local cdLabel = Instance.new("TextLabel")
        cdLabel.Name = "CountdownLabel"
        cdLabel.Size = UDim2.new(1,0,0.4,0)
        cdLabel.Position = UDim2.new(0,0,0.6,0)
        cdLabel.Text = ""
        cdLabel.TextScaled = true
        cdLabel.Parent = bg
    end
    local spawnsFolder = slotModel:FindFirstChild("PlayerSpawns")
    if not spawnsFolder then
        spawnsFolder = Instance.new("Folder")
        spawnsFolder.Name = "PlayerSpawns"
        spawnsFolder.Parent = slotModel
    end
    for i=1, playerCount do
        if not spawnsFolder:FindFirstChild("Player"..i) then
            local part = Instance.new("Part")
            part.Name = "Player"..i
            part.Size = Vector3.new(3,1,3)
            part.Anchored = true
            part.Position = basePos + Vector3.new(-10 + (i-1)*4, -2.5, -10)
            part.Parent = spawnsFolder
        end
    end
end

local function createArena(parentFolder, arenaName, playerCount, basePos)
    local arenaModel = parentFolder:FindFirstChild(arenaName)
    if not arenaModel then
        arenaModel = Instance.new("Model")
        arenaModel.Name = arenaName
        arenaModel.Parent = parentFolder
    end
    local targetStand = arenaModel:FindFirstChild("TargetStand")
    if not targetStand then
        targetStand = Instance.new("Part")
        targetStand.Name = "TargetStand"
        targetStand.Size = Vector3.new(4,1,4)
        targetStand.Anchored = true
        targetStand.Color = Color3.fromRGB(255,0,0)
        targetStand.Position = basePos
        targetStand.Parent = arenaModel
    end
    if not targetStand:FindFirstChild("Chair") then
        local chair = Instance.new("Seat")
        chair.Name = "Chair"
        chair.Size = Vector3.new(2,1,2)
        chair.Anchored = true
        chair.Position = basePos + Vector3.new(0,1,0)
        chair.Parent = targetStand
    end
    if not arenaModel:FindFirstChild("PuncherStand") then
        local puncherStand = Instance.new("Part")
        puncherStand.Name = "PuncherStand"
        puncherStand.Size = Vector3.new(4,1,4)
        puncherStand.Anchored = true
        puncherStand.Color = Color3.fromRGB(0,0,255)
        puncherStand.Position = basePos + Vector3.new(0,0,6)
        puncherStand.Parent = arenaModel
    end
    local spawnsFolder = arenaModel:FindFirstChild("PlayerSpawns")
    if not spawnsFolder then
        spawnsFolder = Instance.new("Folder")
        spawnsFolder.Name = "PlayerSpawns"
        spawnsFolder.Parent = arenaModel
    end
    for i=1, playerCount do
        if not spawnsFolder:FindFirstChild("Player"..i) then
            local part = Instance.new("Part")
            part.Name = "Player"..i
            part.Size = Vector3.new(3,1,3)
            part.Anchored = true
            local angle = (i-1) * (360/playerCount)
            local rad = math.rad(angle)
            part.Position = basePos + Vector3.new(math.cos(rad)*5, 0, math.sin(rad)*5)
            part.Parent = spawnsFolder
        end
    end
end

createQueueSlot(matchSlots, "Slot2", 2, Vector3.new(0,3,0))
createQueueSlot(matchSlots, "Slot4", 4, Vector3.new(20,3,0))
createQueueSlot(matchSlots, "Slot6", 6, Vector3.new(40,3,0))

createArena(arenasFolder, "Arena2", 2, Vector3.new(0,100,0))
createArena(arenasFolder, "Arena4", 4, Vector3.new(200,100,0))
createArena(arenasFolder, "Arena6", 6, Vector3.new(400,100,0))

print("=== MASTER SETUP DONE ===")
print("Hierarchy: Slot2/EntryArea, LeaveButton, DisplayBoard, PlayerSpawns/Player1,Player2")
print("Arena: TargetStand/Chair(Seat), PuncherStand 6 studs behind, PlayerSpawns")
print("No spectator stands")
```

---

## What Each Module Does (For Claude Reference)

- **Config:** Capacities 2,4,6, Min 2, FullCountdown 5, PartialWait 30, PartialCountdown 5, Prep 3, Punch 10, Gauge 5, Guessing 15, KO 3, LobbyReturn 5, Health 100, Damages Miss 0 Weak 10 Normal 25 Strong 50 Perfect 100
- **QueueStates:** WAITING, COUNTDOWN_FULL, COUNTDOWN_PARTIAL, LOCKED, STARTING, CANCELLED + CanJoin() only if WAITING
- **RemoteNames:** Queue remotes + future match remotes
- **Constants:** Standalone, no requires (fixes yellow underline), remote names, tags
- **QueueService:** Full queue logic - Touched detection, occupancy server-side, prevent multi-join, leave, start when full, start after 30s if >=2, cancel if <2, handle death (keep in queue, teleport back), disconnect (remove), locked prevents new joins, handoff via GetPlayersForMatch() and RE_QueueStarted
- **RemoteService:** Auto-creates RemoteEvents if missing
- **Main.server:** Auto-creates Remotes folder + all remotes, validates workspace, inits QueueService
- **Main.client:** Prints queue updates for testing

---

## How Future Systems Will Import

```lua
local Shared = game.ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local QueueStates = require(Shared.QueueStates)
```

---

## Verification After Claude Runs Master Script

In Command Bar:

```lua
local Shared = game.ReplicatedStorage.Shared
print(require(Shared.Config).QueueCapacities.Slot2) -- 2
print(require(Shared.QueueStates).States.WAITING) -- WAITING
print(game.ReplicatedStorage.Remotes:FindFirstChild("RE_QueueJoinRequest") ~= nil) -- true
print(workspace.Lobby.MatchSlots.Slot2:FindFirstChild("EntryArea") ~= nil) -- true
print(workspace.MatchArenas.Arena2.TargetStand:FindFirstChild("Chair") ~= nil) -- true, Seat
```

Expected: all true, no errors, no yellow underlines.

---

## Notes for Claude

- Do NOT add .luau extensions to names in Studio, just `Config`, `QueueStates`, etc.
- All ModuleScripts must `return Table` at end (exactly 1 value) to avoid "Module does not return exactly 1 value" error
- Use `--!nonstrict` at top to avoid strict type errors with WaitForChild
- Constants.luau must NOT require other modules - keep standalone
- Chair must be Seat object, not Part, named Chair, parented to TargetStand
- PuncherStand must be 6 studs behind TargetStand
- No SpectatorStands folder
- EntryArea CanCollide false, Anchored true
- PlayerSpawns folder contains Player1..N Parts

---

## Full Code Files (If Claude Wants to Paste Individually)

Full code for each file is in GitHub `src/Shared/` and `src/Server/` - copy from there and set ModuleScript.Source

For QueueService full code (not minimal), copy from `src/Server/Services/QueueService.luau` (719 lines) - the master script above includes minimal version, but for production use full version from GitHub.

