--!nonstrict
-- Main.client.luau - Queue + Match Setup + Target Camera/Visibility + Puncher Selection Client
-- Purpose: Listens to queue and match state, controls Target camera/visibility and Puncher request presentation only
-- Implements: Target camera/visibility + Puncher selection phase (first valid server-accepted becomes Puncher)
-- Server controls all roles and validation, client sends only Punch request (no winner/timestamp/damage/power/role)
-- Does NOT implement: power gauge, damage, guessing, knockout, scoring, monetization, final GUI
-- Roblox Studio Destination: StarterPlayer > StarterPlayerScripts > GuessThePuncherClient (LocalScript)
-- Expected children: Services folder with TargetCameraService, TargetVisibilityService, PuncherSelectionService ModuleScripts

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
print("[GuessThePuncherClient] Starting for " .. player.Name)

-- Load Shared Config
local Shared = ReplicatedStorage:WaitForChild("Shared", 10)
local Config = nil
if Shared then
	local ConfigMod = Shared:FindFirstChild("Config")
	if ConfigMod then
		Config = require(ConfigMod)
	end
end

-- Load Client Services
local TargetCameraService = nil
local TargetVisibilityService = nil
local PuncherSelectionService = nil

local function loadClientServices()
	local servicesFolder = script:FindFirstChild("Services")
	if not servicesFolder then
		local starterPlayerScripts = script.Parent
		if starterPlayerScripts then
			servicesFolder = starterPlayerScripts:FindFirstChild("Services")
			if not servicesFolder then
				local gtpFolder = starterPlayerScripts:FindFirstChild("GuessThePuncherClient")
				if gtpFolder then
					servicesFolder = gtpFolder:FindFirstChild("Services")
				end
			end
		end
	end
	if not servicesFolder then
		local clientFolder = ReplicatedStorage:FindFirstChild("Client")
		if clientFolder then
			servicesFolder = clientFolder:FindFirstChild("Services")
		end
	end

	if servicesFolder then
		local camMod = servicesFolder:FindFirstChild("TargetCameraService")
		local visMod = servicesFolder:FindFirstChild("TargetVisibilityService")
		local punchMod = servicesFolder:FindFirstChild("PuncherSelectionService")
		if camMod then
			local ok, mod = pcall(require, camMod)
			if ok then TargetCameraService = mod else warn("[Client] Failed to require TargetCameraService: " .. tostring(mod)) end
		end
		if visMod then
			local ok, mod = pcall(require, visMod)
			if ok then TargetVisibilityService = mod else warn("[Client] Failed to require TargetVisibilityService: " .. tostring(mod)) end
		end
		if punchMod then
			local ok, mod = pcall(require, punchMod)
			if ok then PuncherSelectionService = mod else warn("[Client] Failed to require PuncherSelectionService: " .. tostring(mod)) end
		end
	else
		warn("[Client] Services folder not found - create StarterPlayerScripts/GuessThePuncherClient/Services with TargetCameraService, TargetVisibilityService, PuncherSelectionService")
	end
end

loadClientServices()

-- Track current match state
local currentMatchId: string? = nil
local currentRole: string? = nil
local currentState: string? = nil
local currentMatchPlayers: { [number]: Player } = {}
local currentTargetUserId: number? = nil
local currentPuncherUserId: number? = nil

local function isLocalPlayerTarget(): boolean
	if currentRole == "Target" then return true end
	if currentTargetUserId and currentTargetUserId == player.UserId then return true end
	return false
end

local function updateMatchPlayersFromPayload(payload)
	if not payload or not payload.players then return end
	currentMatchPlayers = {}
	for _, userId in ipairs(payload.players) do
		local plr = Players:GetPlayerByUserId(userId)
		if plr then
			currentMatchPlayers[userId] = plr
		else
			for _, p in ipairs(Players:GetPlayers()) do
				if p.UserId == userId then
					currentMatchPlayers[userId] = p
					break
				end
			end
		end
	end
	if currentMatchId and not currentMatchPlayers[player.UserId] then
		currentMatchPlayers[player.UserId] = player
	end
	if TargetVisibilityService then
		TargetVisibilityService.UpdateMatchPlayers(currentMatchPlayers)
	end
	if PuncherSelectionService and payload.puncherUserId then
		-- Update puncher tracking for client (filtered, Target won't get it)
		currentPuncherUserId = payload.puncherUserId
	end
end

local function applyTargetState()
	local isTarget = isLocalPlayerTarget()
	if TargetCameraService then
		TargetCameraService.SetIsTarget(isTarget)
	end
	if TargetVisibilityService then
		TargetVisibilityService.SetIsTarget(isTarget, currentMatchPlayers)
	end
	if isTarget then
		print("[Client] You are now TARGET - restricted first-person, behind players hidden")
	else
		if currentRole then
			print("[Client] Your role: " .. tostring(currentRole) .. " - normal camera")
		end
	end
end

local function applyPuncherState()
	if PuncherSelectionService then
		PuncherSelectionService.UpdateState(currentMatchId, currentRole, currentState, currentPuncherUserId ~= nil)
	end
end

local function restoreAll()
	print("[Client] Restoring camera, visibility, puncher state - match ended")
	if TargetCameraService then TargetCameraService.Restore() end
	if TargetVisibilityService then TargetVisibilityService.Restore() end
	if PuncherSelectionService then PuncherSelectionService.HandleMatchEnd() end
	currentMatchId = nil
	currentRole = nil
	currentState = nil
	currentTargetUserId = nil
	currentPuncherUserId = nil
	currentMatchPlayers = {}
end

-- Initialize services
if TargetCameraService and TargetCameraService.Init then TargetCameraService.Init() end
if TargetVisibilityService and TargetVisibilityService.Init then TargetVisibilityService.Init() end
if PuncherSelectionService and PuncherSelectionService.Init then PuncherSelectionService.Init() end

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
if not remotesFolder then
	warn("[GuessThePuncherClient] Missing Remotes folder")
	return
end

-- Queue events
local stateUpdate = remotesFolder:WaitForChild("RE_QueueStateUpdate", 10)
if stateUpdate then
	stateUpdate.OnClientEvent:Connect(function(slotId, occupancyList, maxPlayers, state, countdownTimeLeft, locked, occupancyCount)
		print(string.format("[Queue] %s: %d/%d state=%s countdown=%.1f locked=%s", slotId, occupancyCount or #occupancyList, maxPlayers, state, countdownTimeLeft or 0, tostring(locked)))
	end)
end

local queueStarted = remotesFolder:FindFirstChild("RE_QueueStarted")
if queueStarted then
	queueStarted.OnClientEvent:Connect(function(slotId, players)
		print(string.format("[Queue] Started %s with %d players - handing off to MatchService", slotId, #players))
	end)
end

-- Match events
local matchStart = remotesFolder:FindFirstChild("RE_MatchStart")
if matchStart then
	matchStart.OnClientEvent:Connect(function(matchId, arenaName, players)
		print(string.format("[Match] Start matchId=%s arena=%s players=%d", matchId, arenaName, #players))
		currentMatchId = matchId
		currentMatchPlayers = {}
		for _, uid in ipairs(players) do
			local plr = Players:GetPlayerByUserId(uid)
			if plr then currentMatchPlayers[uid] = plr end
		end
		if TargetVisibilityService then TargetVisibilityService.UpdateMatchPlayers(currentMatchPlayers) end
		if PuncherSelectionService then PuncherSelectionService.UpdateState(matchId, nil, nil, false) end
	end)
end

local matchStateUpdate = remotesFolder:FindFirstChild("RE_MatchStateUpdate")
if matchStateUpdate then
	matchStateUpdate.OnClientEvent:Connect(function(payload)
		if payload then
			print(string.format("[Match] StateUpdate matchId=%s state=%s target=%s puncher=%s players=%d", tostring(payload.matchId), tostring(payload.state), tostring(payload.targetUserId), tostring((payload :: any).puncherUserId), payload.players and #payload.players or 0))
			if payload.matchId then currentMatchId = payload.matchId end
			if payload.state then currentState = payload.state end
			if payload.targetUserId then currentTargetUserId = payload.targetUserId end
			if (payload :: any).puncherUserId then currentPuncherUserId = (payload :: any).puncherUserId end
			updateMatchPlayersFromPayload(payload)

			if payload.roles then
				local ourRole = payload.roles[player.UserId]
				if ourRole then
					currentRole = ourRole
					print(string.format("[Match] Your role (filtered): %s", ourRole))
					if ourRole == "Target" then
						for uid, role in pairs(payload.roles) do
							if uid ~= player.UserId and role == "Puncher" then
								warn("[Security] Target received Puncher role! Filtering failed")
							end
						end
						if (payload :: any).puncherUserId then
							warn("[Security] Target payload contains puncherUserId before reveal! Should be hidden")
						end
					end
				end
			end

			applyTargetState()
			applyPuncherState()
		end
	end)
end

local matchEnd = remotesFolder:FindFirstChild("RE_MatchEnd")
if matchEnd then
	matchEnd.OnClientEvent:Connect(function(matchId, reason)
		print(string.format("[Match] End matchId=%s reason=%s", matchId, reason))
		restoreAll()
	end)
end

local roleAssigned = remotesFolder:FindFirstChild("RE_RoleAssigned")
if roleAssigned then
	roleAssigned.OnClientEvent:Connect(function(matchId, role)
		print(string.format("[Match] RoleAssigned matchId=%s role=%s", matchId, role))
		currentMatchId = matchId
		currentRole = role
		if role == "Target" then currentTargetUserId = player.UserId end
		if role == "Puncher" then currentPuncherUserId = player.UserId end
		applyTargetState()
		applyPuncherState()
	end)
end

-- Puncher specific remotes handled inside PuncherSelectionService, but also log here for debug
local puncherSelected = remotesFolder:FindFirstChild("RE_PuncherSelected")
if puncherSelected then
	puncherSelected.OnClientEvent:Connect(function(matchId, puncherUserId)
		print(string.format("[Match] PuncherSelected event matchId=%s puncher=%s (nil=hidden from Target)", matchId, tostring(puncherUserId)))
		if puncherUserId then currentPuncherUserId = puncherUserId end
		applyPuncherState()
	end)
end

player.CharacterAdded:Connect(function(character)
	print("[Client] CharacterAdded - re-applying states if needed")
	task.wait(0.5)
	if isLocalPlayerTarget() then applyTargetState() end
	applyPuncherState()
end)

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer.UserId == player.UserId then
		restoreAll()
	else
		if currentMatchPlayers[leavingPlayer.UserId] then
			currentMatchPlayers[leavingPlayer.UserId] = nil
			if TargetVisibilityService then TargetVisibilityService.UpdateMatchPlayers(currentMatchPlayers) end
		end
	end
end)

print("[GuessThePuncherClient] Ready - Queue + Match + Target Camera/Visibility + Puncher Selection")
print("  Join queue: RE_QueueJoinRequest:FireServer('Slot2') or walk onto EntryArea")
print("  When PotentialPuncher in WaitingForPuncher: Press F to request Punch (or RE_PunchRequest:FireServer(matchId))")
print("  First valid server-accepted becomes Puncher, moved behind Target, preparation " .. tostring(Config and Config.PuncherPreparationTime or 3) .. "s")
