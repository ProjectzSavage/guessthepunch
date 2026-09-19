-- MASTER SCRIPT FOR CLAUDE MCP - Queue + Basic Match Setup
-- Creates all folders and scripts with FULL CODE (no .luau extensions)
-- Paste into Command Bar or run via MCP

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local StarterPlayer = game:GetService("StarterPlayer")

print("=== CLAUDE MCP MATCH SETUP START ===")

local function createModule(parent, name, code)
    local existing = parent:FindFirstChild(name)
    if existing then
        if existing:IsA("ModuleScript") then
            existing.Source = code
            print("Updated: "..parent.Name.."/"..name)
            return existing
        else
            existing:Destroy()
        end
    end
    local m = Instance.new("ModuleScript")
    m.Name = name
    m.Source = code
    m.Parent = parent
    print("Created: "..parent.Name.."/"..name)
    return m
end

local function createScript(parent, name, code, isLocal)
    local existing = parent:FindFirstChild(name)
    if existing then existing:Destroy() end
    local s = isLocal and Instance.new("LocalScript") or Instance.new("Script")
    s.Name = name
    s.Source = code
    s.Parent = parent
    print("Created: "..parent:GetFullName().."/"..name)
    return s
end

-- Shared
local sharedFolder = ReplicatedStorage:FindFirstChild("Shared") or Instance.new("Folder")
sharedFolder.Name = "Shared"
sharedFolder.Parent = ReplicatedStorage

-- Config, QueueStates, MatchStates, Roles, RemoteNames, Constants
-- For brevity, using minimal versions - replace with full from GitHub src/Shared/ for production
createModule(sharedFolder, "Config", [[
--!nonstrict
local Config = {}
Config.QueueCapacities = {Slot2=2,Slot4=4,Slot6=6}
Config.QueueCapacityList = {2,4,6}
Config.MinimumPlayers = 2
Config.QueueFullCountdown = 5
Config.QueuePartialWaitTime = 30
Config.QueuePartialCountdown = 5
Config.QueueCountdownDuration = 10
Config.MatchPreparationTime = 3
Config.SelectingTargetDuration = 2
Config.MatchMinPlayers = 2
Config.ArenaBySlot = {Slot2="Arena2",Slot4="Arena4",Slot6="Arena6"}
Config.ArenaFolderName = "MatchArenas"
Config.LobbyFolderName = "Lobby"
Config.MatchSlotsFolderName = "MatchSlots"
Config.LobbyReturnDelay = 5
Config.PunchSelectionDuration = 10
Config.PowerGaugeDuration = 5
Config.GuessingDuration = 15
Config.KnockoutDuration = 3
Config.StartingHealth = 100
Config.Damage = {Miss=0,Weak=10,Normal=25,Strong=50,Perfect=100}
Config.WeakDamage=10 Config.NormalDamage=25 Config.StrongDamage=50 Config.PerfectDamage=100 Config.MissDamage=0
Config.PerfectIsInstantKO=true
Config.TeleportOffsetY=3
Config.PuncherOffsetBehindTarget=6
Config.PuncherInvisibleToTarget=true
Config.TouchDebounce=1
Config.PunchRequestCooldown=0.5
Config.DebugPrints=true
return Config
]])

createModule(sharedFolder, "QueueStates", [[
--!nonstrict
local QueueStates={}
QueueStates.States={WAITING="WAITING",COUNTDOWN_FULL="COUNTDOWN_FULL",COUNTDOWN_PARTIAL="COUNTDOWN_PARTIAL",LOCKED="LOCKED",STARTING="STARTING",CANCELLED="CANCELLED"}
QueueStates.List={"WAITING","COUNTDOWN_FULL","COUNTDOWN_PARTIAL","LOCKED","STARTING","CANCELLED"}
function QueueStates.IsCountingDown(s) return s=="COUNTDOWN_FULL" or s=="COUNTDOWN_PARTIAL" end
function QueueStates.CanJoin(s) return s=="WAITING" end
return QueueStates
]])

createModule(sharedFolder, "MatchStates", [[
--!nonstrict
local MatchStates={}
MatchStates.States={
    PREPARING="Preparing",
    SELECTING_TARGET="SelectingTarget",
    WAITING_FOR_PUNCHER="WaitingForPuncher",
    PUNCHING="Punching",
    GUESSING="Guessing",
    RESOLVING="Resolving",
    ELIMINATED="Eliminated",
    FINISHED="Finished",
}
MatchStates.List={"Preparing","SelectingTarget","WaitingForPuncher","Punching","Guessing","Resolving","Eliminated","Finished"}
MatchStates.Transitions={
    Preparing={"SelectingTarget","Finished"},
    SelectingTarget={"WaitingForPuncher","Finished"},
    WaitingForPuncher={"Punching","Finished"},
    Punching={"Guessing","Eliminated","Finished"},
    Guessing={"Resolving","Finished"},
    Resolving={"SelectingTarget","Eliminated","Finished"},
    Eliminated={"SelectingTarget","Finished"},
    Finished={},
}
function MatchStates.CanTransition(f,t)
    local a=MatchStates.Transitions[f]
    if not a then return false end
    for _,s in ipairs(a) do if s==t then return true end end
    return false
end
return MatchStates
]])

createModule(sharedFolder, "Roles", [[
--!nonstrict
local Roles={}
Roles.Roles={NONE="None",LOBBY="Lobby",QUEUED="Queued",TARGET="Target",POTENTIAL_PUNCHER="PotentialPuncher",PUNCHER="Puncher",SPECTATOR="Spectator",ELIMINATED="Eliminated",WINNER="Winner"}
return Roles
]])

createModule(sharedFolder, "RemoteNames", [[
--!nonstrict
local RemoteNames={}
RemoteNames.Queue={JoinRequest="RE_QueueJoinRequest",LeaveRequest="RE_QueueLeaveRequest",StateUpdate="RE_QueueStateUpdate",CountdownUpdate="RE_QueueCountdownUpdate",Locked="RE_QueueLocked",Started="RE_QueueStarted",PlayerLeft="RE_QueuePlayerLeft"}
RemoteNames.Match={MatchStart="RE_MatchStart",MatchStateUpdate="RE_MatchStateUpdate",MatchEnd="RE_MatchEnd",RoleAssigned="RE_RoleAssigned",TargetSelected="RE_TargetSelected"}
RemoteNames.All={}
for _,n in pairs(RemoteNames.Queue) do table.insert(RemoteNames.All,n) end
for _,n in pairs(RemoteNames.Match) do table.insert(RemoteNames.All,n) end
return RemoteNames
]])

createModule(sharedFolder, "Constants", [[
--!nonstrict
local Constants={}
Constants.QueueCapacities={Slot2=2,Slot4=4,Slot6=6}
Constants.MinimumPlayers=2
Constants.Remotes={
    QueueJoinRequest="RE_QueueJoinRequest",QueueLeaveRequest="RE_QueueLeaveRequest",QueueStateUpdate="RE_QueueStateUpdate",QueueCountdownUpdate="RE_QueueCountdownUpdate",QueueLocked="RE_QueueLocked",QueueStarted="RE_QueueStarted",QueuePlayerLeft="RE_QueuePlayerLeft",
    MatchStart="RE_MatchStart",MatchStateUpdate="RE_MatchStateUpdate",MatchEnd="RE_MatchEnd",RoleAssigned="RE_RoleAssigned",TargetSelected="RE_TargetSelected",
}
Constants.AllRemoteNames={}
for _,n in pairs(Constants.Remotes) do table.insert(Constants.AllRemoteNames,n) end
return Constants
]])

createModule(sharedFolder, "Types", "--!nonstrict\nreturn {}\n")

-- Remotes
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotesFolder.Name="Remotes"
remotesFolder.Parent=ReplicatedStorage
for _,name in ipairs({"RE_QueueJoinRequest","RE_QueueLeaveRequest","RE_QueueStateUpdate","RE_QueueCountdownUpdate","RE_QueueLocked","RE_QueueStarted","RE_QueuePlayerLeft","RE_MatchStart","RE_MatchStateUpdate","RE_MatchEnd","RE_RoleAssigned","RE_TargetSelected"}) do
    if not remotesFolder:FindFirstChild(name) then
        local re=Instance.new("RemoteEvent")
        re.Name=name
        re.Parent=remotesFolder
    end
end

-- Services
local servicesFolder = ServerScriptService:FindFirstChild("Services") or Instance.new("Folder")
servicesFolder.Name="Services"
servicesFolder.Parent=ServerScriptService

-- RemoteService
createModule(servicesFolder, "RemoteService", [[
--!nonstrict
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RemoteService={}
function RemoteService.EnsureFolder()
    local f=ReplicatedStorage:FindFirstChild("Remotes")
    if not f then f=Instance.new("Folder") f.Name="Remotes" f.Parent=ReplicatedStorage end
    return f
end
function RemoteService.EnsureRemote(name)
    local folder=RemoteService.EnsureFolder()
    local existing=folder:FindFirstChild(name)
    if existing and existing:IsA("RemoteEvent") then return existing end
    if existing then existing:Destroy() end
    local re=Instance.new("RemoteEvent") re.Name=name re.Parent=folder return re
end
function RemoteService.EnsureAllRemotes(names)
    for _,n in ipairs(names) do RemoteService.EnsureRemote(n) end
end
return RemoteService
]])

-- NOTE: For full QueueService and MatchService code, copy from GitHub:
-- src/Server/Services/QueueService.luau (719 lines)
-- src/Server/Services/MatchService.luau (569 lines)
-- Below are minimal working versions for quick test - replace with full for production

createModule(servicesFolder, "QueueService", [[
--!nonstrict
-- Minimal QueueService - replace with full from GitHub for production
local Players=game:GetService("Players")
local Workspace=game:GetService("Workspace")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local QueueService={}
QueueService.Slots={}
QueueService.SlotOrder={"Slot2","Slot4","Slot6"}
QueueService.PendingMatches={}
local Config
local QueueStates
local MatchService
local remotes={}
local function findSlotContainingPlayer(uid)
    for sid,sd in pairs(QueueService.Slots) do if sd.players[uid] then return sid end end
    return nil
end
local function broadcast(sid)
    local sd=QueueService.Slots[sid]
    if not sd then return end
    local list={}
    for uid,_ in pairs(sd.players) do table.insert(list,uid) end
    if remotes.StateUpdate then remotes.StateUpdate:FireAllClients(sid,list,sd.maxPlayers,sd.state,sd.countdownTimeLeft,sd.locked,sd.occupancy) end
end
function QueueService.TryJoinSlot(plr,sid)
    if MatchService and MatchService.IsPlayerInMatch(plr.UserId) then return false,"In match" end
    if findSlotContainingPlayer(plr.UserId) then return false,"Already in slot" end
    local sd=QueueService.Slots[sid]
    if not sd then return false,"No slot" end
    if sd.locked or sd.state~="WAITING" then return false,"Locked" end
    if sd.occupancy>=sd.maxPlayers then return false,"Full" end
    sd.players[plr.UserId]=plr
    sd.occupancy+=1
    if sd.occupancy>=2 and not sd.waitStartTick then sd.waitStartTick=tick() end
    broadcast(sid)
    if sd.occupancy==sd.maxPlayers then QueueService.StartCountdown(sid,"FULL") end
    return true,"Joined"
end
function QueueService.LeaveSlot(plr)
    local sid=findSlotContainingPlayer(plr.UserId)
    if not sid then return false,"Not in slot" end
    local sd=QueueService.Slots[sid]
    if sd.state=="LOCKED" or sd.state=="STARTING" then return false,"Starting" end
    sd.players[plr.UserId]=nil
    sd.occupancy=math.max(0,sd.occupancy-1)
    if sd.occupancy<2 then sd.waitStartTick=nil end
    broadcast(sid)
    return true,"Left"
end
function QueueService.StartCountdown(sid,typ)
    local sd=QueueService.Slots[sid]
    if not sd then return end
    local dur=(typ=="FULL") and Config.QueueFullCountdown or Config.QueuePartialCountdown
    sd.state=(typ=="FULL") and "COUNTDOWN_FULL" or "COUNTDOWN_PARTIAL"
    sd.countdownActive=true
    sd.countdownTimeLeft=dur
    sd.countdownEndTick=tick()+dur
    sd.locked=true
    broadcast(sid)
end
function QueueService.CancelCountdown(sid,reason)
    local sd=QueueService.Slots[sid]
    if not sd then return end
    sd.state="WAITING"
    sd.countdownActive=false
    sd.locked=false
    if sd.occupancy<2 then sd.waitStartTick=nil end
    broadcast(sid)
end
function QueueService.FinishCountdown(sid)
    local sd=QueueService.Slots[sid]
    if not sd then return end
    if sd.occupancy<2 then QueueService.CancelCountdown(sid,"Not enough") return end
    sd.state="LOCKED"
    sd.locked=true
    broadcast(sid)
    local list={}
    local inst={}
    for uid,plr in pairs(sd.players) do table.insert(list,uid) table.insert(inst,plr) end
    QueueService.PendingMatches[sid]={slotId=sid,players=list,playerInstances=inst}
    sd.state="STARTING"
    broadcast(sid)
    if remotes.Started then remotes.Started:FireAllClients(sid,list) end
    if MatchService and MatchService.CreateMatchFromQueue then
        local mid=MatchService.CreateMatchFromQueue(sid,list,inst)
        if mid then
            sd.players={}
            sd.occupancy=0
            sd.waitStartTick=nil
            QueueService.PendingMatches[sid]=nil
            return
        end
    end
    task.delay(5,function()
        if QueueService.Slots[sid] and QueueService.Slots[sid].state=="STARTING" then
            QueueService.ReleaseSlot(sid)
        end
    end)
end
function QueueService.ReleaseSlot(sid)
    local sd=QueueService.Slots[sid]
    if not sd then return end
    sd.players={}
    sd.occupancy=0
    sd.state="WAITING"
    sd.locked=false
    sd.waitStartTick=nil
    QueueService.PendingMatches[sid]=nil
    broadcast(sid)
end
function QueueService.Init()
    local Shared=ReplicatedStorage:WaitForChild("Shared",10)
    Config=require(Shared:WaitForChild("Config"))
    QueueStates=require(Shared:WaitForChild("QueueStates"))
    local rf=ReplicatedStorage:WaitForChild("Remotes",10)
    if rf then
        remotes.StateUpdate=rf:FindFirstChild("RE_QueueStateUpdate")
        remotes.Started=rf:FindFirstChild("RE_QueueStarted")
        remotes.JoinRequest=rf:FindFirstChild("RE_QueueJoinRequest")
        remotes.LeaveRequest=rf:FindFirstChild("RE_QueueLeaveRequest")
    end
    local ServicesFolder=script.Parent
    local msMod=ServicesFolder:FindFirstChild("MatchService")
    if msMod then
        local ok,ms=pcall(require,msMod)
        if ok then MatchService=ms end
    end
    local lobby=Workspace:FindFirstChild("Lobby")
    if not lobby then lobby=Instance.new("Folder") lobby.Name="Lobby" lobby.Parent=Workspace end
    local matchSlots=lobby:FindFirstChild("MatchSlots")
    if not matchSlots then matchSlots=Instance.new("Folder") matchSlots.Name="MatchSlots" matchSlots.Parent=lobby end
    for _,sid in ipairs(QueueService.SlotOrder) do
        local sm=matchSlots:FindFirstChild(sid)
        local entry=sm and (sm:FindFirstChild("EntryArea") or sm:FindFirstChild("TouchBlock"))
        local board=sm and sm:FindFirstChild("DisplayBoard")
        local spawns=sm and sm:FindFirstChild("PlayerSpawns")
        QueueService.Slots[sid]={id=sid,maxPlayers=Config.QueueCapacities[sid] or 2,players={},occupancy=0,state="WAITING",locked=false,entryPart=entry,displayBoard=board,playerSpawnsFolder=spawns,touchDebounce={},waitStartTick=nil,countdownEndTick=nil,countdownTimeLeft=0}
        if entry and entry:IsA("BasePart") then
            entry.Touched:Connect(function(hit)
                local char=hit.Parent
                if not char then return end
                local plr=Players:GetPlayerFromCharacter(char)
                if not plr then return end
                local now=tick()
                local last=QueueService.Slots[sid].touchDebounce[plr.UserId] or 0
                if now-last<1 then return end
                QueueService.Slots[sid].touchDebounce[plr.UserId]=now
                QueueService.TryJoinSlot(plr,sid)
            end)
        end
    end
    if remotes.JoinRequest then
        remotes.JoinRequest.OnServerEvent:Connect(function(plr,sid) QueueService.TryJoinSlot(plr,sid) end)
    end
    if remotes.LeaveRequest then
        remotes.LeaveRequest.OnServerEvent:Connect(function(plr) QueueService.LeaveSlot(plr) end)
    end
    Players.PlayerRemoving:Connect(function(plr) QueueService.LeaveSlot(plr) end)
    task.spawn(function()
        while true do
            task.wait(1)
            local now=tick()
            for sid,sd in pairs(QueueService.Slots) do
                if sd.state=="WAITING" then
                    if sd.occupancy>=2 and sd.occupancy<sd.maxPlayers then
                        if not sd.waitStartTick then sd.waitStartTick=now
                        elseif now-sd.waitStartTick>=(Config.QueuePartialWaitTime or 30) then
                            QueueService.StartCountdown(sid,"PARTIAL")
                        end
                    end
                elseif sd.state=="COUNTDOWN_FULL" or sd.state=="COUNTDOWN_PARTIAL" then
                    if sd.countdownEndTick then
                        local left=sd.countdownEndTick-now
                        sd.countdownTimeLeft=math.max(0,left)
                        if left<=0 then QueueService.FinishCountdown(sid) end
                        if sd.occupancy<2 then QueueService.CancelCountdown(sid,"Not enough") end
                    end
                end
            end
        end
    end)
    print("[QueueService] Initialized")
end
return QueueService
]])

-- For MatchService, instruct Claude to paste full code from GitHub
-- Creating placeholder - Claude should replace with full code from src/Server/Services/MatchService.luau
createModule(servicesFolder, "MatchService", [[
--!nonstrict
-- MatchService.luau - Placeholder - Replace with full code from GitHub src/Server/Services/MatchService.luau (569 lines)
-- For MCP, Claude should read the GitHub file and set Source to full code

local MatchService={}
MatchService.Matches={}
MatchService.PlayersInMatch={}
MatchService.ArenasInUse={}

function MatchService.IsPlayerInMatch(uid) return MatchService.PlayersInMatch[uid] ~= nil end

function MatchService.CreateMatchFromQueue(slotId, userIds, instances)
    print("[MatchService] CreateMatchFromQueue called for "..slotId.." with "..#userIds.." players - placeholder, paste full code from GitHub")
    -- Minimal: just mark players as in match and teleport to arena if exists
    local Workspace=game:GetService("Workspace")
    local arenas=Workspace:FindFirstChild("MatchArenas")
    local arenaName = (slotId=="Slot2" and "Arena2") or (slotId=="Slot4" and "Arena4") or "Arena6"
    local arena = arenas and arenas:FindFirstChild(arenaName)
    local matchId = slotId.."_"..math.random(100000,999999)
    MatchService.Matches[matchId]={matchId=matchId, slotId=slotId, arenaName=arenaName, players={}, targetUserId=userIds[math.random(1,#userIds)]}
    for _,uid in ipairs(userIds) do MatchService.PlayersInMatch[uid]=matchId end
    if arena then
        local targetStand=arena:FindFirstChild("TargetStand")
        for _,plr in ipairs(instances) do
            if plr and plr.Character then
                local hrp=plr.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    if plr.UserId==MatchService.Matches[matchId].targetUserId and targetStand then
                        hrp.CFrame=targetStand.CFrame + Vector3.new(0,3,0)
                        local chair=targetStand:FindFirstChild("Chair")
                        local hum=plr.Character:FindFirstChildOfClass("Humanoid")
                        if chair and chair:IsA("Seat") and hum then pcall(function() chair:Sit(hum) end) end
                    else
                        local spawns=arena:FindFirstChild("PlayerSpawns")
                        local spawn=spawns and spawns:FindFirstChild("Player1")
                        if spawn then hrp.CFrame=spawn.CFrame + Vector3.new(0,3,0) end
                    end
                end
            end
        end
    end
    return matchId
end

function MatchService.Init()
    print("[MatchService] Initialized (placeholder) - replace with full code from GitHub src/Server/Services/MatchService.luau for full features: Preparing, SelectingTarget, WaitingForPuncher, handle leave/disconnect/reset/dying, end if <2, independent matches")
end

return MatchService
]])

-- Main server
createScript(ServerScriptService, "GuessThePuncherServer", [[
--!nonstrict
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Workspace=game:GetService("Workspace")
print("[GuessThePuncherServer] Starting Queue + Match Setup...")
local sharedFolder=ReplicatedStorage:WaitForChild("Shared",10)
if not sharedFolder then error("Missing Shared") end
local function safeRequire(n)
    local m=sharedFolder:FindFirstChild(n)
    if not m then warn("Missing "..n) return nil end
    local ok,r=pcall(require,m)
    if not ok then warn("Fail "..n) return nil end
    return r
end
local Config=safeRequire("Config")
local remotesFolder=ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotesFolder.Name="Remotes"
remotesFolder.Parent=ReplicatedStorage
local allRemotes={"RE_QueueJoinRequest","RE_QueueLeaveRequest","RE_QueueStateUpdate","RE_QueueCountdownUpdate","RE_QueueLocked","RE_QueueStarted","RE_QueuePlayerLeft","RE_MatchStart","RE_MatchStateUpdate","RE_MatchEnd","RE_RoleAssigned","RE_TargetSelected"}
for _,name in ipairs(allRemotes) do
    if not remotesFolder:FindFirstChild(name) then
        local re=Instance.new("RemoteEvent")
        re.Name=name
        re.Parent=remotesFolder
    end
end
local servicesFolder=script.Parent:FindFirstChild("Services") or game:GetService("ServerScriptService"):FindFirstChild("Services")
if servicesFolder then
    local msMod=servicesFolder:FindFirstChild("MatchService")
    if msMod then local ok,ms=pcall(require,msMod) if ok and ms then ms.Init() end end
    local qsMod=servicesFolder:FindFirstChild("QueueService")
    if qsMod then local ok,qs=pcall(require,qsMod) if ok and qs then qs.Init() end end
end
print("[GuessThePuncherServer] Ready - Queue -> Match Setup")
]], false)

-- Client
local sps = StarterPlayer:FindFirstChild("StarterPlayerScripts")
if sps then
    createScript(sps, "GuessThePuncherClient", [[
--!nonstrict
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local player=Players.LocalPlayer
print("[Client] Starting for "..player.Name)
local remotesFolder=ReplicatedStorage:WaitForChild("Remotes",10)
if not remotesFolder then return end
local qState=remotesFolder:WaitForChild("RE_QueueStateUpdate",10)
if qState then
    qState.OnClientEvent:Connect(function(slotId, occList, maxP, state, cd, locked, occCount)
        print(string.format("[Queue] %s %d/%d %s",slotId,occCount or #occList,maxP,state))
    end)
end
local mStart=remotesFolder:FindFirstChild("RE_MatchStart")
if mStart then
    mStart.OnClientEvent:Connect(function(matchId, arenaName, players)
        print(string.format("[Match] Start %s arena %s players %d",matchId,arenaName,#players))
    end)
end
local mState=remotesFolder:FindFirstChild("RE_MatchStateUpdate")
if mState then
    mState.OnClientEvent:Connect(function(payload)
        if payload then print(string.format("[Match] State %s target %s",payload.state or "?", tostring(payload.targetUserId))) end
    end)
end
print("[Client] Ready")
]], true)
end

-- Workspace
local lobby=Workspace:FindFirstChild("Lobby") or Instance.new("Folder")
lobby.Name="Lobby"
lobby.Parent=Workspace
if not lobby:FindFirstChild("SpawnLocation") then
    local sp=Instance.new("SpawnLocation")
    sp.Name="SpawnLocation"
    sp.Size=Vector3.new(6,1,6)
    sp.Anchored=true
    sp.Neutral=true
    sp.Position=Vector3.new(0,3,0)
    sp.Parent=lobby
end
local matchSlots=lobby:FindFirstChild("MatchSlots") or Instance.new("Folder")
matchSlots.Name="MatchSlots"
matchSlots.Parent=lobby
local arenasFolder=Workspace:FindFirstChild("MatchArenas") or Instance.new("Folder")
arenasFolder.Name="MatchArenas"
arenasFolder.Parent=Workspace

local function createQueueSlot(parent, name, count, pos)
    local model=parent:FindFirstChild(name)
    if not model then model=Instance.new("Model") model.Name=name model.Parent=parent end
    model:SetAttribute("SlotId",name)
    model:SetAttribute("MaxPlayers",count)
    if not model:FindFirstChild("EntryArea") then
        local p=Instance.new("Part") p.Name="EntryArea" p.Size=Vector3.new(6,1,6) p.Anchored=true p.CanCollide=false p.Transparency=0.3 p.Color=Color3.fromRGB(0,170,255) p.Material=Enum.Material.ForceField p.Position=pos p.Parent=model
    end
    if not model:FindFirstChild("LeaveButton") then
        local p=Instance.new("Part") p.Name="LeaveButton" p.Size=Vector3.new(3,1,3) p.Anchored=true p.CanCollide=false p.Color=Color3.fromRGB(255,0,0) p.Position=pos+Vector3.new(0,0,5) p.Parent=model local cd=Instance.new("ClickDetector") cd.Parent=p
    end
    if not model:FindFirstChild("DisplayBoard") then
        local p=Instance.new("Part") p.Name="DisplayBoard" p.Size=Vector3.new(4,6,0.5) p.Anchored=true p.Position=pos+Vector3.new(0,5,0) p.Parent=model
        local bg=Instance.new("BillboardGui") bg.Name="BillboardGui" bg.Size=UDim2.new(0,200,0,150) bg.StudsOffset=Vector3.new(0,3,0) bg.AlwaysOnTop=true bg.Parent=p
        local occ=Instance.new("TextLabel") occ.Name="OccupancyLabel" occ.Size=UDim2.new(1,0,0.3,0) occ.Text="0/"..count occ.TextScaled=true occ.Parent=bg
        local status=Instance.new("TextLabel") status.Name="StatusLabel" status.Size=UDim2.new(1,0,0.3,0) status.Position=UDim2.new(0,0,0.3,0) status.Text="WAITING" status.TextScaled=true status.Parent=bg
        local cdL=Instance.new("TextLabel") cdL.Name="CountdownLabel" cdL.Size=UDim2.new(1,0,0.4,0) cdL.Position=UDim2.new(0,0,0.6,0) cdL.Text="" cdL.TextScaled=true cdL.Parent=bg
    end
    local spawns=model:FindFirstChild("PlayerSpawns") or Instance.new("Folder")
    spawns.Name="PlayerSpawns"
    spawns.Parent=model
    for i=1,count do
        if not spawns:FindFirstChild("Player"..i) then
            local p=Instance.new("Part") p.Name="Player"..i p.Size=Vector3.new(3,1,3) p.Anchored=true p.Position=pos+Vector3.new(-10+(i-1)*4,-2.5,-10) p.Parent=spawns
        end
    end
end

local function createArena(parent, name, count, pos)
    local model=parent:FindFirstChild(name)
    if not model then model=Instance.new("Model") model.Name=name model.Parent=parent end
    local ts=model:FindFirstChild("TargetStand")
    if not ts then ts=Instance.new("Part") ts.Name="TargetStand" ts.Size=Vector3.new(4,1,4) ts.Anchored=true ts.Color=Color3.fromRGB(255,0,0) ts.Position=pos ts.Parent=model end
    if not ts:FindFirstChild("Chair") then
        local chair=Instance.new("Seat") chair.Name="Chair" chair.Size=Vector3.new(2,1,2) chair.Anchored=true chair.Position=pos+Vector3.new(0,1,0) chair.Parent=ts
    end
    if not model:FindFirstChild("PuncherStand") then
        local ps=Instance.new("Part") ps.Name="PuncherStand" ps.Size=Vector3.new(4,1,4) ps.Anchored=true ps.Color=Color3.fromRGB(0,0,255) ps.Position=pos+Vector3.new(0,0,6) ps.Parent=model
    end
    local spawns=model:FindFirstChild("PlayerSpawns") or Instance.new("Folder")
    spawns.Name="PlayerSpawns"
    spawns.Parent=model
    for i=1,count do
        if not spawns:FindFirstChild("Player"..i) then
            local p=Instance.new("Part") p.Name="Player"..i p.Size=Vector3.new(3,1,3) p.Anchored=true
            local angle=(i-1)*(360/count) local rad=math.rad(angle)
            p.Position=pos+Vector3.new(math.cos(rad)*5,0,math.sin(rad)*5)
            p.Parent=spawns
        end
    end
end

createQueueSlot(matchSlots,"Slot2",2,Vector3.new(0,3,0))
createQueueSlot(matchSlots,"Slot4",4,Vector3.new(20,3,0))
createQueueSlot(matchSlots,"Slot6",6,Vector3.new(40,3,0))

createArena(arenasFolder,"Arena2",2,Vector3.new(0,100,0))
createArena(arenasFolder,"Arena4",4,Vector3.new(200,100,0))
createArena(arenasFolder,"Arena6",6,Vector3.new(400,100,0))

print("=== MASTER SETUP DONE - Queue + Match Setup ===")
print("For full MatchService code (569 lines), copy from GitHub src/Server/Services/MatchService.luau and paste into Services/MatchService ModuleScript")
