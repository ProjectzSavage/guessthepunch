--!nonstrict
-- MatchService.luau
-- Purpose: Basic match setup system for players accepted from queue
-- Implements ONLY:
-- - Assign queued players to unique match
-- - Move them into correct arena
-- - Prevent joining another queue
-- - Select initial Target server-side
-- - Assign PotentialPuncher role to others
-- - Place players in designated positions (TargetStand+Chair, PlayerSpawns)
-- - Handle leaving, disconnecting, resetting, dying
-- - End safely if <2 active players remain
-- - Keep separate matches independent
-- Uses server-controlled states: Preparing, SelectingTarget, WaitingForPuncher, Punching, Guessing, Resolving, Eliminated, Finished
-- Does NOT implement: punching, power, damage, guessing, knockout, final scoring, GUI, monetization, DataStores
-- Roblox Studio Destination: ServerScriptService > Services > MatchService (ModuleScript)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchService = {}
MatchService.Matches = {} -- [matchId] = matchData
MatchService.PlayersInMatch = {} -- [userId] = matchId (prevents joining another queue)
MatchService.ArenasInUse = {} -- [arenaName] = matchId (for physical independence check)

local Config
local MatchStates
local Roles
local RemoteService

local remotes = {}

-- ============================================================================
-- HELPERS
-- ============================================================================

local function generateMatchId(slotId: string): string
	return slotId .. "_" .. tostring(math.random(100000, 999999)) .. "_" .. tostring(tick()):gsub("%.", "")
end

local function getArenaModel(arenaName: string): Model?
	local arenasFolder = Workspace:FindFirstChild("MatchArenas")
	if not arenasFolder then return nil end
	return arenasFolder:FindFirstChild(arenaName) :: Model?
end

local function findPlayerSpawn(arenaModel: Model, index: number): BasePart?
	local spawnsFolder = arenaModel:FindFirstChild("PlayerSpawns")
	if not spawnsFolder then return nil end
	local part = spawnsFolder:FindFirstChild("Player" .. index)
	if part and part:IsA("BasePart") then return part end
	-- fallback any
	for _, child in ipairs(spawnsFolder:GetChildren()) do
		if child:IsA("BasePart") then return child end
	end
	return nil
end

local function teleportPlayerToCFrame(player: Player, cf: CFrame)
	local character = player.Character
	if not character then return false end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		character:WaitForChild("HumanoidRootPart", 2)
		hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false end
	end
	hrp.CFrame = cf + Vector3.new(0, Config.TeleportOffsetY or 3, 0)
	return true
end

local function teleportToArenaSpawn(player: Player, arenaModel: Model, index: number)
	local spawnPart = findPlayerSpawn(arenaModel, index)
	if spawnPart then
		return teleportPlayerToCFrame(player, spawnPart.CFrame)
	else
		warn("[MatchService] No spawn found for index " .. index .. " in arena " .. arenaModel.Name)
		return false
	end
end

local function teleportToTargetStand(player: Player, arenaModel: Model)
	local targetStand = arenaModel:FindFirstChild("TargetStand")
	if not targetStand or not targetStand:IsA("BasePart") then
		warn("[MatchService] Missing TargetStand in arena " .. arenaModel.Name)
		return false
	end
	local success = teleportPlayerToCFrame(player, targetStand.CFrame)
	-- Try to sit on Chair Seat if exists
	task.wait(0.2)
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local chair = targetStand:FindFirstChild("Chair")
		if chair and chair:IsA("Seat") and humanoid then
			-- Seat:Sit is deprecated, use humanoid.Sit = true and seat's occupant?
			-- For R15, setting humanoid.Sit and moving to seat CFrame works, or use chair:Sit(humanoid)
			pcall(function()
				chair:Sit(humanoid)
			end)
		end
	end
	return success
end

local function teleportToPuncherStand(player: Player, arenaModel: Model)
	local puncherStand = arenaModel:FindFirstChild("PuncherStand")
	if puncherStand and puncherStand:IsA("BasePart") then
		return teleportPlayerToCFrame(player, puncherStand.CFrame)
	else
		-- fallback to player spawn
		return false
	end
end

local function teleportToLobby(player: Player)
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local lobby = Workspace:FindFirstChild("Lobby")
	if lobby then
		local spawnLoc = lobby:FindFirstChildOfClass("SpawnLocation")
		if spawnLoc and spawnLoc:IsA("SpawnLocation") then
			hrp.CFrame = spawnLoc.CFrame + Vector3.new(0, 3, 0)
			return
		end
	end
	hrp.CFrame = CFrame.new(0, 5, 0)
end

local function broadcastMatchState(matchData)
	local re = remotes.StateUpdate
	if not re then return end
	-- Filtered payload for now: matchId, state, targetUserId, players, roles
	-- No puncher identity yet (not needed for setup phase)
	local payload = {
		matchId = matchData.matchId,
		state = matchData.state,
		targetUserId = matchData.targetUserId,
		players = {},
		roles = matchData.roles,
		arenaName = matchData.arenaName,
	}

	for userId, _ in pairs(matchData.players) do
		table.insert(payload.players, userId)
	end

	-- Fire to all players in match
	for _, player in pairs(matchData.playerInstances) do
		if player and player.Parent then
			re:FireClient(player, payload)
		end
	end
end

local function broadcastMatchStart(matchData)
	local re = remotes.MatchStart
	if not re then return end
	local playerList = {}
	for userId, _ in pairs(matchData.players) do
		table.insert(playerList, userId)
	end
	for _, player in pairs(matchData.playerInstances) do
		if player and player.Parent then
			re:FireClient(player, matchData.matchId, matchData.arenaName, playerList)
		end
	end
end

local function broadcastMatchEnd(matchData, reason: string)
	local re = remotes.MatchEnd
	if not re then return end
	local playerList = {}
	for userId, _ in pairs(matchData.players) do
		table.insert(playerList, userId)
	end
	for _, player in pairs(matchData.playerInstances) do
		if player and player.Parent then
			re:FireClient(player, matchData.matchId, reason)
		end
	end
	-- Also fire to all for cleanup? For now only to match players
end

local function broadcastRoleAssigned(matchData, userId: number, role: string)
	local re = remotes.RoleAssigned or ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("RE_RoleAssigned")
	if not re then
		-- Try generic role update via state update
		return
	end
	local player = matchData.players[userId]
	if player and player.Parent then
		re:FireClient(player, matchData.matchId, role)
	end
end

-- ============================================================================
-- CORE LOGIC
-- ============================================================================

function MatchService.IsPlayerInMatch(userId: number): boolean
	return MatchService.PlayersInMatch[userId] ~= nil
end

function MatchService.GetMatchIdForPlayer(userId: number): string?
	return MatchService.PlayersInMatch[userId]
end

function MatchService.GetMatchData(matchId: string)
	return MatchService.Matches[matchId]
end

function MatchService.CreateMatchFromQueue(slotId: string, playerUserIds: {number}, playerInstances: {Player}): string?
	if not playerUserIds or #playerUserIds < 2 then
		warn("[MatchService] Cannot create match, not enough players: " .. tostring(#playerUserIds))
		return nil
	end

	-- Check arena availability for physical independence
	local arenaName = Config.ArenaBySlot[slotId] or ("Arena" .. tostring(Config.QueueCapacities[slotId] or 2))
	local arenaModel = getArenaModel(arenaName)
	if not arenaModel then
		warn("[MatchService] Missing arena model: " .. arenaName .. " in Workspace.MatchArenas - create per docs")
		-- Still create match but without arena model (will teleport to 0,0,0 fallback)
	end

	-- For independent matches, check if arena already in use
	if MatchService.ArenasInUse[arenaName] then
		local existingMatchId = MatchService.ArenasInUse[arenaName]
		local existingMatch = MatchService.Matches[existingMatchId]
		if existingMatch and existingMatch.state ~= "Finished" then
			warn("[MatchService] Arena " .. arenaName .. " already in use by match " .. existingMatchId .. " - for true physical independence, create more arenas or wait. Allowing shared arena for now (logical independence kept).")
			-- For this phase, allow shared arena but log warning
			-- If you want strict physical independence, uncomment return nil below:
			-- return nil
		end
	end

	local matchId = generateMatchId(slotId)
	print(string.format("[MatchService] Creating match %s from queue %s with %d players, arena %s", matchId, slotId, #playerUserIds, arenaName))

	-- Build match data
	local matchData = {
		matchId = matchId,
		slotId = slotId,
		arenaName = arenaName,
		arenaModel = arenaModel,
		players = {}, -- [userId] = Player
		playerInstances = {}, -- array of Players
		roles = {}, -- [userId] = role
		targetUserId = nil,
		state = MatchStates.States.PREPARING,
		createdTick = tick(),
		activePlayers = #playerUserIds,
	}

	-- Assign players to unique match (requirement 1) and prevent joining another queue (requirement 3)
	for i, userId in ipairs(playerUserIds) do
		local player = playerInstances[i] or Players:GetPlayerByUserId(userId)
		if player then
			matchData.players[userId] = player
			table.insert(matchData.playerInstances, player)
			MatchService.PlayersInMatch[userId] = matchId
			matchData.roles[userId] = "Queued" -- temporary until target selection
		else
			warn("[MatchService] Player instance not found for userId " .. userId .. " - may have disconnected")
		end
	end

	-- Track arena in use
	MatchService.ArenasInUse[arenaName] = matchId
	MatchService.Matches[matchId] = matchData

	-- Move them into correct arena (requirement 2)
	broadcastMatchStart(matchData)
	broadcastMatchState(matchData)

	-- Teleport all to arena spawns first (Preparing)
	task.spawn(function()
		task.wait(0.5) -- small delay for replication
		for idx, player in ipairs(matchData.playerInstances) do
			if player and player.Parent then
				if arenaModel then
					teleportToArenaSpawn(player, arenaModel, idx)
				else
					teleportPlayerToCFrame(player, CFrame.new(0, 100, 0))
				end
			end
		end

		-- After preparation time, go to SelectingTarget
		task.wait(Config.MatchPreparationTime or 3)
		if not MatchService.Matches[matchId] then return end -- match ended early
		if matchData.activePlayers < Config.MatchMinPlayers then
			MatchService.EndMatch(matchId, "Not enough players after preparation")
			return
		end

		matchData.state = MatchStates.States.SELECTING_TARGET
		broadcastMatchState(matchData)
		print("[MatchService] Match " .. matchId .. " SelectingTarget")

		-- Select one player as initial Target using server-side logic (requirement 4)
		task.wait(Config.SelectingTargetDuration or 2)
		if not MatchService.Matches[matchId] then return end

		local aliveUserIds = {}
		for userId, _ in pairs(matchData.players) do
			table.insert(aliveUserIds, userId)
		end

		if #aliveUserIds < 2 then
			MatchService.EndMatch(matchId, "Not enough players for target selection")
			return
		end

		-- Server-side random selection (never trusts client)
		local randomIndex = math.random(1, #aliveUserIds)
		local targetUserId = aliveUserIds[randomIndex]
		matchData.targetUserId = targetUserId

		-- Assign roles: Target and PotentialPuncher (requirement 5)
		for userId, _ in pairs(matchData.players) do
			if userId == targetUserId then
				matchData.roles[userId] = "Target"
			else
				matchData.roles[userId] = "PotentialPuncher"
			end
			broadcastRoleAssigned(matchData, userId, matchData.roles[userId])
		end

		print(string.format("[MatchService] Match %s Target selected: %d, %d PotentialPunchers", matchId, targetUserId, #aliveUserIds - 1))

		-- Place players in designated positions (requirement 6)
		-- Target to TargetStand+Chair, others to PlayerSpawns
		if arenaModel then
			for _, player in ipairs(matchData.playerInstances) do
				if player and player.Parent then
					if player.UserId == targetUserId then
						teleportToTargetStand(player, arenaModel)
					else
						-- Find index for this player
						local idx = 1
						for i, p in ipairs(matchData.playerInstances) do
							if p.UserId == player.UserId then
								idx = i
								break
							end
						end
						-- If target was at index 1, shift others? For simplicity, use same index
						teleportToArenaSpawn(player, arenaModel, idx)
					end
				end
			end
		end

		matchData.state = MatchStates.States.WAITING_FOR_PUNCHER
		broadcastMatchState(matchData)
		print("[MatchService] Match " .. matchId .. " now WaitingForPuncher - setup complete, handoff ready for future punching system")

		-- For this phase, we stop here at WaitingForPuncher
		-- Future systems will handle Punching, Guessing, etc.
	end)

	return matchId
end

function MatchService.EndMatch(matchId: string, reason: string)
	local matchData = MatchService.Matches[matchId]
	if not matchData then
		warn("[MatchService] EndMatch called for unknown matchId: " .. tostring(matchId))
		return
	end

	print(string.format("[MatchService] Ending match %s reason=%s", matchId, reason))

	matchData.state = MatchStates.States.FINISHED
	broadcastMatchState(matchData)
	broadcastMatchEnd(matchData, reason)

	-- Teleport players back to lobby and cleanup
	for _, player in pairs(matchData.playerInstances) do
		if player and player.Parent then
			teleportToLobby(player)
			MatchService.PlayersInMatch[player.UserId] = nil
		end
	end

	-- Release arena
	if MatchService.ArenasInUse[matchData.arenaName] == matchId then
		MatchService.ArenasInUse[matchData.arenaName] = nil
	end

	-- Release queue slot via QueueService if available
	local queueServiceMod = ServerScriptService:FindFirstChild("Services") and ServerScriptService.Services:FindFirstChild("QueueService")
	if queueServiceMod then
		local ok, QueueService = pcall(require, queueServiceMod)
		if ok and QueueService and QueueService.ReleaseSlot then
			-- Only release if slot is still in STARTING state (queue finished)
			QueueService.ReleaseSlot(matchData.slotId)
		end
	end

	-- Clear match data after delay
	task.delay(1, function()
		MatchService.Matches[matchId] = nil
		print("[MatchService] Match cleaned up: " .. matchId)
	end)
end

function MatchService.HandlePlayerLeaving(userId: number, reason: string)
	local matchId = MatchService.PlayersInMatch[userId]
	if not matchId then return end

	local matchData = MatchService.Matches[matchId]
	if not matchData then
		MatchService.PlayersInMatch[userId] = nil
		return
	end

	print(string.format("[MatchService] Player %d leaving match %s reason=%s", userId, matchId, reason))

	-- Remove from match
	matchData.players[userId] = nil
	-- Remove from playerInstances array
	for i, plr in ipairs(matchData.playerInstances) do
		if plr.UserId == userId then
			table.remove(matchData.playerInstances, i)
			break
		end
	end
	matchData.roles[userId] = nil
	MatchService.PlayersInMatch[userId] = nil

	matchData.activePlayers = 0
	for _ in pairs(matchData.players) do
		matchData.activePlayers += 1
	end

	broadcastMatchState(matchData)

	-- End match safely if fewer than 2 active players remain (requirement 8)
	if matchData.activePlayers < (Config.MatchMinPlayers or 2) then
		MatchService.EndMatch(matchId, "Not enough players - " .. reason)
	else
		-- If target left, select new target
		if matchData.targetUserId == userId then
			print("[MatchService] Target left, selecting new target for match " .. matchId)
			-- Pick new random target from remaining
			local remaining = {}
			for uid, _ in pairs(matchData.players) do
				table.insert(remaining, uid)
			end
			if #remaining >= 1 then
				local newTarget = remaining[math.random(1, #remaining)]
				matchData.targetUserId = newTarget
				-- Reassign roles
				for uid, _ in pairs(matchData.players) do
					if uid == newTarget then
						matchData.roles[uid] = "Target"
					else
						matchData.roles[uid] = "PotentialPuncher"
					end
				end
				-- Teleport new target to TargetStand
				local newTargetPlayer = matchData.players[newTarget]
				if newTargetPlayer and matchData.arenaModel then
					teleportToTargetStand(newTargetPlayer, matchData.arenaModel)
				end
				broadcastMatchState(matchData)
			end
		end
	end
end

function MatchService.Init()
	print("[MatchService] Initializing...")

	local Shared = ReplicatedStorage:WaitForChild("Shared", 10)
	if not Shared then
		error("[MatchService] Missing ReplicatedStorage.Shared")
	end

	Config = require(Shared:WaitForChild("Config"))
	MatchStates = require(Shared:WaitForChild("MatchStates"))
	Roles = require(Shared:WaitForChild("Roles"))

	local ServicesFolder = script.Parent
	local RemoteServiceMod = ServicesFolder:FindFirstChild("RemoteService")
	if RemoteServiceMod then
		RemoteService = require(RemoteServiceMod)
		RemoteService.EnsureAllRemotes({
			"RE_MatchStart",
			"RE_MatchStateUpdate",
			"RE_MatchEnd",
			"RE_RoleAssigned",
			"RE_TargetSelected",
		})
	end

	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if remotesFolder then
		remotes.MatchStart = remotesFolder:FindFirstChild("RE_MatchStart")
		remotes.StateUpdate = remotesFolder:FindFirstChild("RE_MatchStateUpdate")
		remotes.MatchEnd = remotesFolder:FindFirstChild("RE_MatchEnd")
		remotes.RoleAssigned = remotesFolder:FindFirstChild("RE_RoleAssigned")
		remotes.TargetSelected = remotesFolder:FindFirstChild("RE_TargetSelected")
	end

	-- Handle player disconnect, reset, death (requirement 7)
	Players.PlayerRemoving:Connect(function(player)
		MatchService.HandlePlayerLeaving(player.UserId, "Disconnected")
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			task.wait(1)
			local matchId = MatchService.PlayersInMatch[player.UserId]
			if matchId then
				local matchData = MatchService.Matches[matchId]
				if matchData and matchData.arenaModel then
					-- Keep in match, teleport back to designated position
					if player.UserId == matchData.targetUserId then
						teleportToTargetStand(player, matchData.arenaModel)
					else
						-- Find index
						local idx = 1
						for i, p in ipairs(matchData.playerInstances) do
							if p.UserId == player.UserId then idx = i break end
						end
						teleportToArenaSpawn(player, matchData.arenaModel, idx)
					end
					print("[MatchService] Player " .. player.Name .. " respawned, kept in match " .. matchId)
				end
			end
		end)
	end)

	-- Handle death (Humanoid.Died) - keep in match but teleport back after respawn handled by CharacterAdded
	-- For existing players
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function(character)
			task.wait(1)
			local matchId = MatchService.PlayersInMatch[player.UserId]
			if matchId then
				local matchData = MatchService.Matches[matchId]
				if matchData and matchData.arenaModel then
					if player.UserId == matchData.targetUserId then
						teleportToTargetStand(player, matchData.arenaModel)
					else
						local idx = 1
						for i, p in ipairs(matchData.playerInstances) do
							if p.UserId == player.UserId then idx = i break end
						end
						teleportToArenaSpawn(player, matchData.arenaModel, idx)
					end
				end
			end
		end)
	end

	print("[MatchService] Initialized - ready for queue handoff")
	print("[MatchService] States: Preparing, SelectingTarget, WaitingForPuncher, Punching, Guessing, Resolving, Eliminated, Finished")
end

return MatchService
