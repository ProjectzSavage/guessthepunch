--!nonstrict
-- Main.client.luau - Queue + Match Setup + Target Camera/Visibility Client
-- Purpose: Listens to queue and match state, controls Target camera and visibility presentation only
-- Implements ONLY Target camera and visibility system (no punch, power, damage, guessing, knockout, scoring, GUI)
-- Server controls Target role, client controls camera presentation only
-- Roblox Studio Destination: StarterPlayer > StarterPlayerScripts > GuessThePuncherClient (LocalScript)
-- Expected children: Services folder with TargetCameraService and TargetVisibilityService ModuleScripts

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

-- Load Target Camera and Visibility Services (try multiple paths for Studio setup flexibility)
local TargetCameraService = nil
local TargetVisibilityService = nil

local function loadClientServices()
	-- Try: script.Services folder (if Main.client has Services as child)
	local servicesFolder = script:FindFirstChild("Services")
	if not servicesFolder then
		-- Try sibling folder in StarterPlayerScripts
		local starterPlayerScripts = script.Parent
		if starterPlayerScripts then
			servicesFolder = starterPlayerScripts:FindFirstChild("Services")
			if not servicesFolder then
				-- Try GuessThePuncherClient folder
				local gtpFolder = starterPlayerScripts:FindFirstChild("GuessThePuncherClient")
				if gtpFolder then
					servicesFolder = gtpFolder:FindFirstChild("Services")
				end
			end
		end
	end
	if not servicesFolder then
		-- Try ReplicatedStorage Client Services (fallback for flat structure)
		local clientFolder = ReplicatedStorage:FindFirstChild("Client")
		if clientFolder then
			servicesFolder = clientFolder:FindFirstChild("Services")
		end
	end

	if servicesFolder then
		local camMod = servicesFolder:FindFirstChild("TargetCameraService")
		local visMod = servicesFolder:FindFirstChild("TargetVisibilityService")
		if camMod then
			local ok, mod = pcall(require, camMod)
			if ok then TargetCameraService = mod else warn("[Client] Failed to require TargetCameraService: " .. tostring(mod)) end
		end
		if visMod then
			local ok, mod = pcall(require, visMod)
			if ok then TargetVisibilityService = mod else warn("[Client] Failed to require TargetVisibilityService: " .. tostring(mod)) end
		end
	else
		warn("[Client] Services folder not found - Target camera/visibility will be disabled. Create StarterPlayerScripts/GuessThePuncherClient/Services with TargetCameraService and TargetVisibilityService ModuleScripts")
	end
end

loadClientServices()

-- Track current match state for camera/visibility logic
local currentMatchId: string? = nil
local currentRole: string? = nil
local currentMatchPlayers: { [number]: Player } = {} -- [userId] = Player
local currentTargetUserId: number? = nil

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
			-- Player might have left, try FindFirstChild
			for _, p in ipairs(Players:GetPlayers()) do
				if p.UserId == userId then
					currentMatchPlayers[userId] = p
					break
				end
			end
		end
	end
	-- Also include local player if not in list but in match
	if currentMatchId and not currentMatchPlayers[player.UserId] then
		currentMatchPlayers[player.UserId] = player
	end

	if TargetVisibilityService then
		TargetVisibilityService.UpdateMatchPlayers(currentMatchPlayers)
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
		print("[Client] You are now TARGET - restricted first-person camera enforced, behind players hidden locally")
	else
		if currentRole then
			print("[Client] Your role: " .. tostring(currentRole) .. " - normal camera")
		end
	end
end

local function restoreAll()
	print("[Client] Restoring camera and visibility - match ended or role cleared")
	if TargetCameraService then
		TargetCameraService.Restore()
	end
	if TargetVisibilityService then
		TargetVisibilityService.Restore()
	end
	currentMatchId = nil
	currentRole = nil
	currentTargetUserId = nil
	currentMatchPlayers = {}
end

-- Initialize services
if TargetCameraService and TargetCameraService.Init then
	TargetCameraService.Init()
end
if TargetVisibilityService and TargetVisibilityService.Init then
	TargetVisibilityService.Init()
end

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
if not remotesFolder then
	warn("[GuessThePuncherClient] Missing Remotes folder")
	return
end

-- Queue events (unchanged from previous phase)
local stateUpdate = remotesFolder:WaitForChild("RE_QueueStateUpdate", 10)
if stateUpdate then
	stateUpdate.OnClientEvent:Connect(function(slotId, occupancyList, maxPlayers, state, countdownTimeLeft, locked, occupancyCount)
		print(string.format("[Queue] %s: %d/%d state=%s countdown=%.1f locked=%s", slotId, occupancyCount or #occupancyList, maxPlayers, state, countdownTimeLeft or 0, tostring(locked)))
	end)
	print("[QueueClient] Listening to RE_QueueStateUpdate")
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
		print(string.format("[Match] Start matchId=%s arena=%s players=%d (%s)", matchId, arenaName, #players, table.concat(players, ",")))
		currentMatchId = matchId
		-- Build player map
		currentMatchPlayers = {}
		for _, uid in ipairs(players) do
			local plr = Players:GetPlayerByUserId(uid)
			if plr then
				currentMatchPlayers[uid] = plr
			else
				for _, p in ipairs(Players:GetPlayers()) do
					if p.UserId == uid then
						currentMatchPlayers[uid] = p
						break
					end
				end
			end
		end
		if TargetVisibilityService then
			TargetVisibilityService.UpdateMatchPlayers(currentMatchPlayers)
		end
	end)
end

local matchStateUpdate = remotesFolder:FindFirstChild("RE_MatchStateUpdate")
if matchStateUpdate then
	matchStateUpdate.OnClientEvent:Connect(function(payload)
		if payload then
			print(string.format("[Match] StateUpdate matchId=%s state=%s target=%s players=%d", tostring(payload.matchId), tostring(payload.state), tostring(payload.targetUserId), payload.players and #payload.players or 0))
			-- Update current match tracking
			if payload.matchId then
				currentMatchId = payload.matchId
			end
			if payload.targetUserId then
				currentTargetUserId = payload.targetUserId
			end
			updateMatchPlayersFromPayload(payload)

			-- Check our role from filtered payload (server does NOT send Puncher identity to Target)
			if payload.roles then
				local ourRole = payload.roles[player.UserId]
				if ourRole then
					currentRole = ourRole
					print(string.format("[Match] Your role (filtered payload): %s", ourRole))
					-- Security check: ensure Target never receives Puncher role for others (server filtering)
					if ourRole == "Target" then
						for uid, role in pairs(payload.roles) do
							if uid ~= player.UserId and role == "Puncher" then
								warn("[Security] Target received Puncher role for other player! Server filtering failed - should be masked as PotentialPuncher")
							end
						end
						-- Also ensure payload does NOT contain puncherUserId
						if (payload :: any).puncherUserId then
							warn("[Security] Payload contains puncherUserId - should NOT be sent to clients before reveal!")
						end
					end
				end
			end

			applyTargetState()
		end
	end)
end

local matchEnd = remotesFolder:FindFirstChild("RE_MatchEnd")
if matchEnd then
	matchEnd.OnClientEvent:Connect(function(matchId, reason)
		print(string.format("[Match] End matchId=%s reason=%s - returning to lobby, restoring camera", matchId, reason))
		restoreAll()
	end)
end

local roleAssigned = remotesFolder:FindFirstChild("RE_RoleAssigned")
if roleAssigned then
	roleAssigned.OnClientEvent:Connect(function(matchId, role)
		print(string.format("[Match] RoleAssigned matchId=%s role=%s", matchId, role))
		currentMatchId = matchId
		currentRole = role
		if role == "Target" then
			currentTargetUserId = player.UserId
		end
		applyTargetState()
	end)
end

-- Handle reset/death/disconnect/match completion safely
player.CharacterAdded:Connect(function(character)
	print("[Client] CharacterAdded - if Target, camera will re-apply")
	-- Services handle their own CharacterAdded, but we also ensure state re-applied after delay
	task.wait(0.5)
	if isLocalPlayerTarget() then
		applyTargetState()
	end
end)

-- If player leaves match (PlayerRemoving handled server-side, client just restores on MatchEnd)
-- Also handle when local player is removed from match without MatchEnd (edge case)
Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer.UserId == player.UserId then
		restoreAll()
	else
		-- Other player left, update visibility list
		if currentMatchPlayers[leavingPlayer.UserId] then
			currentMatchPlayers[leavingPlayer.UserId] = nil
			if TargetVisibilityService then
				TargetVisibilityService.UpdateMatchPlayers(currentMatchPlayers)
			end
		end
	end
end)

print("[GuessThePuncherClient] Ready - Queue + Match Setup + Target Camera/Visibility")
print("  To join queue: game.ReplicatedStorage.Remotes.RE_QueueJoinRequest:FireServer('Slot2')")
print("  To leave queue: game.ReplicatedStorage.Remotes.RE_QueueLeaveRequest:FireServer()")
print("  Or walk onto EntryArea part")
print("  When you become Target: first-person forced, max yaw " .. tostring(Config and Config.TargetMaxYawDegrees or 65) .. "°, max pitch " .. tostring(Config and Config.TargetMaxPitchDegrees or 30) .. "°, behind players hidden locally")
