--!nonstrict
-- Main.server.luau
-- Entry point for Guess the Puncher - Queue + Basic Match Setup
-- Purpose: Auto-creates RemoteEvents, initializes QueueService and MatchService
-- Roblox Studio Destination: ServerScriptService > GuessThePuncherServer (Script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

print("[GuessThePuncherServer] Starting Queue + Match Setup System...")

-- Ensure Shared folder exists
local sharedFolder = ReplicatedStorage:WaitForChild("Shared", 10)
if not sharedFolder then
	error("[GuessThePuncherServer] CRITICAL: Missing ReplicatedStorage.Shared - create Folder Shared and copy ModuleScripts from src/Shared/")
end

local function safeRequire(moduleName: string)
	local mod = sharedFolder:FindFirstChild(moduleName)
	if not mod then
		warn("[GuessThePuncherServer] Missing Shared/" .. moduleName .. " - copy from GitHub src/Shared/" .. moduleName .. ".luau")
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		warn("[GuessThePuncherServer] Failed to require " .. moduleName .. ": " .. tostring(result))
		return nil
	end
	return result
end

local Config = safeRequire("Config")
local QueueStates = safeRequire("QueueStates")
local MatchStates = safeRequire("MatchStates")

if not Config then
	error("[GuessThePuncherServer] Config missing, cannot start")
end

-- Ensure Remotes folder and auto-create all remotes
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = ReplicatedStorage
	print("[GuessThePuncherServer] Created ReplicatedStorage.Remotes folder")
end

local queueRemoteNames = {
	"RE_QueueJoinRequest",
	"RE_QueueLeaveRequest",
	"RE_QueueStateUpdate",
	"RE_QueueCountdownUpdate",
	"RE_QueueLocked",
	"RE_QueueStarted",
	"RE_QueuePlayerLeft",
}

local matchRemoteNames = {
	"RE_MatchStart",
	"RE_MatchStateUpdate",
	"RE_MatchEnd",
	"RE_RoleAssigned",
	"RE_TargetSelected",
	-- Puncher selection
	"RE_PunchOpportunityOpen",
	"RE_PunchRequest",
	"RE_PunchRejected",
	"RE_PuncherSelected",
	"RE_PuncherPreparation",
	-- Power gauge
	"RE_PowerGaugeOpen",
	"RE_PowerGaugeStopRequest",
	"RE_PowerGaugeRejected",
	"RE_PowerGaugeResult",
	-- Punch sequence + health
	"RE_PunchSequence",
	"RE_TargetHealthUpdate",
	-- Guessing + turns
	"RE_GuessOpen",
	"RE_GuessRequest",
	"RE_GuessRejected",
	"RE_GuessResult",
	-- Knockout/elimination + match end + spectator
	"RE_PlayerEliminated",
	"RE_MatchResult",
	"RE_SpectatorUpdate",
	-- Future (reserved, not used yet)
	"RE_DamageApplied",
	"RE_TargetEliminated",
	"RE_CameraMode",
	"RE_AnimationPlay",
}

local allRemotes = {}
for _, n in ipairs(queueRemoteNames) do table.insert(allRemotes, n) end
for _, n in ipairs(matchRemoteNames) do table.insert(allRemotes, n) end

local created = 0
for _, name in ipairs(allRemotes) do
	if not remotesFolder:FindFirstChild(name) then
		local re = Instance.new("RemoteEvent")
		re.Name = name
		re.Parent = remotesFolder
		created += 1
	end
end

if created > 0 then
	print("[GuessThePuncherServer] Auto-created " .. created .. " RemoteEvents")
else
	print("[GuessThePuncherServer] All remotes exist: " .. #allRemotes)
end

-- Validate Workspace structure
local function validateWorkspace()
	local missing = {}

	if not Workspace:FindFirstChild("Lobby") then
		table.insert(missing, "Workspace.Lobby (Folder)")
	else
		local lobby = Workspace.Lobby
		if not lobby:FindFirstChild("MatchSlots") then
			table.insert(missing, "Workspace.Lobby.MatchSlots (Folder)")
		else
			local slotsFolder = lobby.MatchSlots
			for _, slotId in ipairs({"Slot2", "Slot4", "Slot6"}) do
				local slotModel = slotsFolder:FindFirstChild(slotId)
				if not slotModel then
					table.insert(missing, "Workspace.Lobby.MatchSlots." .. slotId .. " (Model)")
				else
					if not slotModel:FindFirstChild("EntryArea") and not slotModel:FindFirstChild("TouchBlock") then
						table.insert(missing, slotModel:GetFullName() .. ".EntryArea (Part) - physical entry area")
					end
					if not slotModel:FindFirstChild("DisplayBoard") then
						table.insert(missing, slotModel:GetFullName() .. ".DisplayBoard (Part)")
					end
					if not slotModel:FindFirstChild("PlayerSpawns") then
						table.insert(missing, slotModel:GetFullName() .. ".PlayerSpawns (Folder) with Player1..N")
					else
						local spawns = slotModel:FindFirstChild("PlayerSpawns")
						local expected = Config.QueueCapacities[slotId] or 2
						local count = 0
						for _, child in ipairs(spawns:GetChildren()) do
							if child:IsA("BasePart") then count += 1 end
						end
						if count < expected then
							table.insert(missing, slotModel:GetFullName() .. ".PlayerSpawns needs " .. expected .. " parts (found " .. count .. ")")
						end
					end
				end
			end
		end
	end

	if not Workspace:FindFirstChild("MatchArenas") then
		table.insert(missing, "Workspace.MatchArenas (Folder) - you said you will put arenas in a folder, create it with Arena2, Arena4, Arena6")
	else
		local arenas = Workspace.MatchArenas
		for _, arenaName in ipairs({"Arena2", "Arena4", "Arena6"}) do
			local arena = arenas:FindFirstChild(arenaName)
			if not arena then
				table.insert(missing, "Workspace.MatchArenas." .. arenaName .. " (Model)")
			else
				if not arena:FindFirstChild("TargetStand") then
					table.insert(missing, arena:GetFullName() .. ".TargetStand (Part)")
				else
					local targetStand = arena:FindFirstChild("TargetStand")
					if targetStand and not targetStand:FindFirstChild("Chair") then
						table.insert(missing, arena:GetFullName() .. ".TargetStand.Chair (Seat) - target will sit on chair")
					end
				end
				if not arena:FindFirstChild("PuncherStand") then
					table.insert(missing, arena:GetFullName() .. ".PuncherStand (Part) 6 studs behind TargetStand")
				end
				if not arena:FindFirstChild("PlayerSpawns") then
					table.insert(missing, arena:GetFullName() .. ".PlayerSpawns (Folder)")
				else
					local spawns = arena:FindFirstChild("PlayerSpawns")
					local expected = Config.QueueCapacities[arenaName:gsub("Arena", "Slot")] or 2
					local count = 0
					for _, child in ipairs(spawns:GetChildren()) do
						if child:IsA("BasePart") then count += 1 end
					end
					if count < expected then
						table.insert(missing, arena:GetFullName() .. ".PlayerSpawns needs " .. expected .. " parts (found " .. count .. ")")
					end
				end
			end
		end
	end

	if #missing > 0 then
		warn("[GuessThePuncherServer] Missing Workspace objects (" .. #missing .. "):")
		for _, p in ipairs(missing) do
			warn("  - " .. p)
		end
		warn("[GuessThePuncherServer] See docs/QUEUE_MANUAL_OBJECTS.md and docs/MATCH_ARENA_OBJECTS.md for exact setup")
		return false
	else
		print("[GuessThePuncherServer] Workspace structure validated for queue + match setup")
		return true
	end
end

validateWorkspace()

-- Initialize Services - MatchService first, then QueueService (so queue can find match service)
local servicesFolder = script.Parent:FindFirstChild("Services") or ServerScriptService:FindFirstChild("Services")
if not servicesFolder then
	warn("[GuessThePuncherServer] Missing Services folder - create ServerScriptService/Services and copy QueueService and MatchService ModuleScripts")
else
	-- Init MatchService first
	local matchServiceMod = servicesFolder:FindFirstChild("MatchService")
	if matchServiceMod then
		local ok, MatchService = pcall(require, matchServiceMod)
		if ok and MatchService then
			MatchService.Init()
			print("[GuessThePuncherServer] MatchService initialized - States: Preparing, SelectingTarget, WaitingForPuncher, Punching, Guessing, Resolving, Eliminated, Finished")
		else
			warn("[GuessThePuncherServer] Failed to require MatchService: " .. tostring(MatchService))
		end
	else
		warn("[GuessThePuncherServer] Missing MatchService ModuleScript in Services folder - create per docs")
	end

	-- Init QueueService second (needs MatchService for handoff)
	local queueServiceMod = servicesFolder:FindFirstChild("QueueService")
	if queueServiceMod then
		local ok, QueueService = pcall(require, queueServiceMod)
		if ok and QueueService then
			QueueService.Init()
			print("[GuessThePuncherServer] QueueService initialized")
			print(string.format("[GuessThePuncherServer] Config: Capacities 2,4,6 Min=%d FullCountdown=%d PartialWait=%d PartialCountdown=%d", Config.MinimumPlayers, Config.QueueFullCountdown, Config.QueuePartialWaitTime, Config.QueuePartialCountdown))
		else
			warn("[GuessThePuncherServer] Failed to require QueueService: " .. tostring(QueueService))
		end
	else
		warn("[GuessThePuncherServer] Missing QueueService ModuleScript in Services folder")
	end
end

print("[GuessThePuncherServer] Queue + Match Setup System ready")
print("[GuessThePuncherServer] Flow: Queue Full/Partial -> MatchService.CreateMatchFromQueue -> Preparing (teleport to arena) -> SelectingTarget (random Target) -> WaitingForPuncher (setup complete)")
