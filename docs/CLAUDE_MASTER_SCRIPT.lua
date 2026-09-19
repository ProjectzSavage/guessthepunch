-- MASTER SCRIPT FOR CLAUDE MCP - Guess the Puncher Queue System
-- This script creates ALL folders and scripts with FULL CODE (no .luau extensions)
-- Paste into Command Bar or run via MCP - it does everything in one go
-- Hierarchy: Slot with TargetStand, PuncherStand, PlayerSpawns, EntryArea, DisplayBoard, Chair Seat - No spectator stands

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local StarterPlayer = game:GetService("StarterPlayer")

print("=== CLAUDE MCP MASTER SETUP START ===")

-- Helper to create ModuleScript with code
local function createModule(parent, name, code)
    local existing = parent:FindFirstChild(name)
    if existing then
        if existing:IsA("ModuleScript") then
            existing.Source = code
            print("Updated: "..parent:GetFullName().."/"..name)
            return existing
        else
            existing:Destroy()
        end
    end
    local m = Instance.new("ModuleScript")
    m.Name = name
    m.Source = code
    m.Parent = parent
    print("Created: "..parent:GetFullName().."/"..name)
    return m
end

local function createScript(parent, name, code, isLocal)
    local existing = parent:FindFirstChild(name)
    if existing then existing:Destroy() end
    local s
    if isLocal then
        s = Instance.new("LocalScript")
    else
        s = Instance.new("Script")
    end
    s.Name = name
    s.Source = code
    s.Parent = parent
    print("Created: "..parent:GetFullName().."/"..name.." ("..(isLocal and "LocalScript" or "Script")..")")
    return s
end

-- ==================== Shared ====================
local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
if not sharedFolder then
    sharedFolder = Instance.new("Folder")
    sharedFolder.Name = "Shared"
    sharedFolder.Parent = ReplicatedStorage
end

-- Config (from src/Shared/Config.luau)
createModule(sharedFolder, "Config", [=[
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
]=])

-- QueueStates
createModule(sharedFolder, "QueueStates", [=[
--!nonstrict
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
]=])

-- RemoteNames
createModule(sharedFolder, "RemoteNames", [=[
--!nonstrict
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
]=])

-- Constants (standalone, no requires - fixes yellow underline)
createModule(sharedFolder, "Constants", [=[
--!nonstrict
-- Constants.luau - Standalone, NO requires to fix "Module does not return exactly 1 value"
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
]=])

-- Other shared minimal
createModule(sharedFolder, "MatchStates", "--!nonstrict\nlocal MatchStates = {}\nMatchStates.States = {WAITING_FOR_PLAYERS='WAITING_FOR_PLAYERS',COUNTDOWN='COUNTDOWN',PREPARING='PREPARING',ROUND_START='ROUND_START',PUNCH_SELECTION='PUNCH_SELECTION',PUNCHER_SELECTED='PUNCHER_SELECTED',POWER_GAUGE='POWER_GAUGE',PUNCH_EXECUTING='PUNCH_EXECUTING',GUESSING='GUESSING',GUESS_RESULT='GUESS_RESULT',TARGET_ELIMINATED='TARGET_ELIMINATED',MATCH_ENDING='MATCH_ENDING',LOBBY_RETURN='LOBBY_RETURN'}\nreturn MatchStates\n")
createModule(sharedFolder, "Roles", "--!nonstrict\nlocal Roles = {}\nRoles.Roles = {NONE='NONE',LOBBY='LOBBY',QUEUED='QUEUED',TARGET='TARGET',PUNCHER='PUNCHER',SPECTATOR='SPECTATOR',ELIMINATED='ELIMINATED',WINNER='WINNER'}\nreturn Roles\n")
createModule(sharedFolder, "PowerZones", "--!nonstrict\nlocal PowerZones = {}\nPowerZones.Zones = {MISS='Miss',WEAK='Weak',NORMAL='Normal',STRONG='Strong',PERFECT='Perfect'}\nreturn PowerZones\n")
createModule(sharedFolder, "Results", "--!nonstrict\nlocal Results = {}\nResults.GuessResults = {CORRECT='Correct',WRONG='Wrong',TIMEOUT='Timeout'}\nResults.MatchResults = {WINNER='Winner',ELIMINATED='Eliminated',DRAW='Draw',CANCELLED='Cancelled'}\nreturn Results\n")
createModule(sharedFolder, "Types", "--!nonstrict\nreturn {}\n")

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
    end
end

-- ==================== Server ====================
local servicesFolder = ServerScriptService:FindFirstChild("Services")
if not servicesFolder then
    servicesFolder = Instance.new("Folder")
    servicesFolder.Name = "Services"
    servicesFolder.Parent = ServerScriptService
end

createModule(servicesFolder, "RemoteService", [=[
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
]=])

-- QueueService FULL CODE - from GitHub src/Server/Services/QueueService.luau
-- NOTE: This is the full 719-line version - paste actual file content here
-- For brevity in this master script template, we include minimal working version
-- Claude should replace this with full code from GitHub if needed, but minimal version below works for queue

createModule(servicesFolder, "QueueService", [=[
--!nonstrict
-- QueueService.luau - Full queue logic (minimal working version for MCP)
-- For full 719-line version, copy from GitHub src/Server/Services/QueueService.luau

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

function QueueService.GetPlayersForMatch(slotId: string): {number}?
    local pending = QueueService.PendingMatches[slotId]
    if pending then return pending.players end
    local slotData = QueueService.Slots[slotId]
    if slotData and slotData.state == "STARTING" then
        local list = {}
        for uid,_ in pairs(slotData.players) do table.insert(list, uid) end
        return list
    end
    return nil
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
]=])

-- Main.server.luau
createScript(ServerScriptService, "GuessThePuncherServer", [=[
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
]=], false)

-- ==================== Client ====================
local sps = StarterPlayer:FindFirstChild("StarterPlayerScripts")
if sps then
    createScript(sps, "GuessThePuncherClient", [=[
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
]=], true)
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

print("=== CLAUDE MCP MASTER SETUP DONE ===")
print("No spectator stands, with Chair Seat in TargetStand")
print("Queue system ready - test by walking onto EntryArea")
