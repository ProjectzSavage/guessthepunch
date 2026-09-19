--!nonstrict
-- QueueService.luau
-- Purpose: Implements ONLY lobby and queue-slot system for 2,4,6 players
-- Requirements covered:
-- - Physical entry area detection (EntryArea Touched)
-- - Track occupancy on server
-- - Prevent joining multiple slots
-- - Allow leave before match begins
-- - Start when full
-- - Start after waiting period if >=2 but not full
-- - Cancel if <2 remain
-- - Handle reset, death, disconnect
-- - Prevent new joins once queue starts
-- - Prepare clean handoff to future MatchManager
-- Roblox Studio Destination: ServerScriptService > Services > QueueService (ModuleScript)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QueueService = {}
QueueService.__index = QueueService

-- Will be loaded in Init
local Config
local RemoteService
local QueueStates
local MatchService -- for handoff and preventing queue join when in match

-- Internal slot storage
-- Slots[slotId] = {
--   id = "Slot2",
--   maxPlayers = 2,
--   players = { [userId] = Player },
--   occupancy = 0,
--   state = "WAITING",
--   countdownActive = false,
--   countdownTimeLeft = 0,
--   countdownEndTick = nil,
--   waitStartTick = nil,
--   locked = false,
--   entryPart = Part,
--   displayBoard = Part,
--   playerSpawnsFolder = Folder,
--   touchDebounce = { [userId] = tick() }
-- }
QueueService.Slots = {}
QueueService.SlotOrder = {"Slot2", "Slot4", "Slot6"}

-- For clean handoff to future MatchManager
QueueService.PendingMatches = {} -- [slotId] = {players = {userId}, playerInstances = {Player}, slotId, readyTick}

local remotes = {}

-- ============================================================================
-- HELPERS
-- ============================================================================

local function getPlayerFromCharacter(character: Model): Player?
	if not character then return nil end
	return Players:GetPlayerFromCharacter(character)
end

local function findSlotContainingPlayer(userId: number): string?
	for slotId, slotData in pairs(QueueService.Slots) do
		if slotData.players[userId] then
			return slotId
		end
	end
	return nil
end

local function getSpawnPartForIndex(slotData, index: number): BasePart?
	if not slotData.playerSpawnsFolder then return nil end
	local spawnName = "Player" .. index
	local part = slotData.playerSpawnsFolder:FindFirstChild(spawnName)
	if part and part:IsA("BasePart") then
		return part
	end
	-- Fallback: try to find any spawn
	for _, child in ipairs(slotData.playerSpawnsFolder:GetChildren()) do
		if child:IsA("BasePart") then
			return child
		end
	end
	return nil
end

local function teleportToSpawn(player: Player, slotData, index: number)
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		character:WaitForChild("HumanoidRootPart", 2)
		hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
	end
	local spawnPart = getSpawnPartForIndex(slotData, index)
	if spawnPart then
		local cf = spawnPart.CFrame + Vector3.new(0, Config.TeleportOffsetY or 3, 0)
		hrp.CFrame = cf
	else
		warn("[QueueService] No spawn part found for index " .. index .. " in slot " .. slotData.id)
	end
end

local function teleportToLobby(player: Player)
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	-- Find lobby spawn or use Workspace.Lobby SpawnLocation
	local lobby = Workspace:FindFirstChild("Lobby")
	if lobby then
		local spawnLoc = lobby:FindFirstChildOfClass("SpawnLocation") or lobby:FindFirstChild("SpawnLocation")
		if spawnLoc and spawnLoc:IsA("SpawnLocation") then
			hrp.CFrame = spawnLoc.CFrame + Vector3.new(0, 3, 0)
			return
		end
	end
	-- Fallback: 0,5,0
	hrp.CFrame = CFrame.new(0, 5, 0)
end

local function broadcastStateUpdate(slotId: string)
	local slotData = QueueService.Slots[slotId]
	if not slotData then return end

	local occupancyList = {}
	for userId, _ in pairs(slotData.players) do
		table.insert(occupancyList, userId)
	end

	local payload = {
		slotId = slotId,
		occupancy = occupancyList,
		maxPlayers = slotData.maxPlayers,
		state = slotData.state,
		countdownActive = slotData.countdownActive,
		countdownTimeLeft = slotData.countdownTimeLeft,
		locked = slotData.locked,
		occupancyCount = slotData.occupancy,
	}

	-- Fire to all clients
	local re = remotes.StateUpdate
	if re then
		re:FireAllClients(slotId, occupancyList, slotData.maxPlayers, slotData.state, slotData.countdownTimeLeft, slotData.locked, slotData.occupancy)
	end

	-- Update BillboardGui if exists
	if slotData.displayBoard then
		local billboard = slotData.displayBoard:FindFirstChildOfClass("BillboardGui") or slotData.displayBoard:FindFirstChild("BillboardGui")
		if billboard then
			local occLabel = billboard:FindFirstChild("OccupancyLabel")
			if occLabel and occLabel:IsA("TextLabel") then
				occLabel.Text = slotData.occupancy .. "/" .. slotData.maxPlayers
			end
			local statusLabel = billboard:FindFirstChild("StatusLabel")
			if statusLabel and statusLabel:IsA("TextLabel") then
				statusLabel.Text = slotData.state
			end
			local cdLabel = billboard:FindFirstChild("CountdownLabel")
			if cdLabel and cdLabel:IsA("TextLabel") then
				if slotData.countdownActive then
					cdLabel.Text = string.format("Starting in %d", math.ceil(slotData.countdownTimeLeft))
				else
					if slotData.occupancy >= 2 and slotData.waitStartTick then
						local waited = tick() - slotData.waitStartTick
						local remaining = (Config.QueuePartialWaitTime or 30) - waited
						if remaining > 0 and slotData.occupancy < slotData.maxPlayers then
							cdLabel.Text = string.format("Waiting %ds for more", math.ceil(remaining))
						else
							cdLabel.Text = ""
						end
					else
						cdLabel.Text = ""
					end
				end
			end
		end
	end

	if Config.DebugPrints then
		print(string.format("[QueueService] StateUpdate %s: %d/%d state=%s countdown=%.1f locked=%s", slotId, slotData.occupancy, slotData.maxPlayers, slotData.state, slotData.countdownTimeLeft, tostring(slotData.locked)))
	end
end

local function broadcastCountdown(slotId: string, timeLeft: number)
	local re = remotes.CountdownUpdate
	if re then
		-- Fire to all for now, future: only to slot players
		re:FireAllClients(slotId, timeLeft)
	end
end

local function broadcastLocked(slotId: string, locked: boolean)
	local re = remotes.Locked
	if re then
		re:FireAllClients(slotId, locked)
	end
end

local function broadcastStarted(slotId: string, players: {number})
	local re = remotes.Started
	if re then
		re:FireAllClients(slotId, players)
	end
end

local function broadcastPlayerLeft(slotId: string, userId: number)
	local re = remotes.PlayerLeft
	if re then
		re:FireAllClients(slotId, userId)
	end
end

-- ============================================================================
-- CORE LOGIC
-- ============================================================================

function QueueService.TryJoinSlot(player: Player, slotId: string): (boolean, string)
	if not player or not player.Parent then
		return false, "Invalid player"
	end

	-- Prevent joining if already in a match (requirement 3)
	if MatchService and MatchService.IsPlayerInMatch(player.UserId) then
		return false, "Already in a match, cannot join queue"
	end

	-- Prevent joining multiple slots
	local existingSlot = findSlotContainingPlayer(player.UserId)
	if existingSlot then
		if existingSlot == slotId then
			return false, "Already in this slot"
		else
			return false, "Already in slot " .. existingSlot .. ", leave first"
		end
	end

	local slotData = QueueService.Slots[slotId]
	if not slotData then
		return false, "Slot not found: " .. tostring(slotId)
	end

	-- Prevent new joins once queue starts (as requested)
	if not QueueStates.CanJoin(slotData.state) then
		return false, "Slot locked, countdown active, cannot join"
	end

	if slotData.locked then
		return false, "Slot locked"
	end

	if slotData.occupancy >= slotData.maxPlayers then
		return false, "Slot full"
	end

	-- Add player
	slotData.players[player.UserId] = player
	slotData.occupancy = slotData.occupancy + 1

	-- Set wait start tick if first time reaching >=2
	if slotData.occupancy >= Config.MinimumPlayers and not slotData.waitStartTick then
		slotData.waitStartTick = tick()
	end

	-- Teleport to assigned spawn
	teleportToSpawn(player, slotData, slotData.occupancy)

	broadcastStateUpdate(slotId)

	-- Check if should start countdown immediately when full
	if slotData.occupancy == slotData.maxPlayers then
		QueueService.StartCountdown(slotId, "FULL")
	end

	return true, "Joined " .. slotId
end

function QueueService.LeaveSlot(player: Player): (boolean, string)
	if not player then
		return false, "Invalid player"
	end

	local slotId = findSlotContainingPlayer(player.UserId)
	if not slotId then
		return false, "Not in any slot"
	end

	local slotData = QueueService.Slots[slotId]
	if not slotData then
		return false, "Slot data missing"
	end

	-- Allow leave before match begins, but not after locked/starting
	if slotData.state == QueueStates.States.LOCKED or slotData.state == QueueStates.States.STARTING then
		return false, "Cannot leave, match is starting"
	end

	-- Remove
	slotData.players[player.UserId] = nil
	slotData.occupancy = math.max(0, slotData.occupancy - 1)

	-- If occupancy drops below minimum, cancel countdown
	if slotData.occupancy < Config.MinimumPlayers then
		if QueueStates.IsCountingDown(slotData.state) then
			QueueService.CancelCountdown(slotId, "Not enough players")
		end
		slotData.waitStartTick = nil
	end

	teleportToLobby(player)
	broadcastStateUpdate(slotId)
	broadcastPlayerLeft(slotId, player.UserId)

	return true, "Left " .. slotId
end

function QueueService.StartCountdown(slotId: string, type: string)
	local slotData = QueueService.Slots[slotId]
	if not slotData then return end

	if slotData.locked then return end
	if slotData.occupancy < Config.MinimumPlayers then return end

	local duration = Config.QueueFullCountdown
	if type == "PARTIAL" then
		duration = Config.QueuePartialCountdown
	end

	slotData.state = (type == "FULL") and QueueStates.States.COUNTDOWN_FULL or QueueStates.States.COUNTDOWN_PARTIAL
	slotData.countdownActive = true
	slotData.countdownTimeLeft = duration
	slotData.countdownEndTick = tick() + duration
	slotData.locked = true -- prevent new joins once queue starts

	broadcastStateUpdate(slotId)
	broadcastLocked(slotId, true)
	broadcastCountdown(slotId, duration)

	print(string.format("[QueueService] Countdown started for %s type=%s duration=%d occupancy=%d", slotId, type, duration, slotData.occupancy))
end

function QueueService.CancelCountdown(slotId: string, reason: string)
	local slotData = QueueService.Slots[slotId]
	if not slotData then return end

	slotData.state = QueueStates.States.WAITING
	slotData.countdownActive = false
	slotData.countdownTimeLeft = 0
	slotData.countdownEndTick = nil
	slotData.locked = false
	-- Keep waitStartTick? Reset if occupancy < min
	if slotData.occupancy < Config.MinimumPlayers then
		slotData.waitStartTick = nil
	end

	broadcastStateUpdate(slotId)
	broadcastLocked(slotId, false)
	broadcastCountdown(slotId, 0)

	print(string.format("[QueueService] Countdown cancelled for %s reason=%s", slotId, reason))
end

function QueueService.FinishCountdown(slotId: string)
	local slotData = QueueService.Slots[slotId]
	if not slotData then return end

	-- Double-check still enough players
	if slotData.occupancy < Config.MinimumPlayers then
		QueueService.CancelCountdown(slotId, "Not enough players at finish")
		return
	end

	slotData.state = QueueStates.States.LOCKED
	slotData.countdownActive = false
	slotData.countdownTimeLeft = 0
	slotData.locked = true

	broadcastStateUpdate(slotId)
	broadcastLocked(slotId, true)

	-- Prepare handoff to MatchService (basic match setup system)
	local playerList = {}
	local playerInstances = {}
	for userId, plr in pairs(slotData.players) do
		table.insert(playerList, userId)
		table.insert(playerInstances, plr)
	end

	QueueService.PendingMatches[slotId] = {
		slotId = slotId,
		players = playerList,
		playerInstances = playerInstances,
		readyTick = tick(),
	}

	slotData.state = QueueStates.States.STARTING
	broadcastStateUpdate(slotId)
	broadcastStarted(slotId, playerList)

	print(string.format("[QueueService] Queue finished for %s, %d players ready for MatchService handoff", slotId, #playerList))

	-- Try to create match via MatchService (if available)
	if MatchService and MatchService.CreateMatchFromQueue then
		local matchId = MatchService.CreateMatchFromQueue(slotId, playerList, playerInstances)
		if matchId then
			print("[QueueService] Match created: " .. matchId .. " from queue " .. slotId)
			-- Clear queue slot after handoff (players now in match, not in queue)
			-- Keep slot locked until match ends, but clear players from queue tracking
			-- Queue players are now tracked in MatchService.PlayersInMatch
			slotData.players = {}
			slotData.occupancy = 0
			slotData.waitStartTick = nil
			-- Keep locked true until MatchService releases
			QueueService.PendingMatches[slotId] = nil
			return
		else
			warn("[QueueService] Failed to create match for " .. slotId .. ", releasing slot")
			QueueService.ReleaseSlot(slotId)
		end
	else
		-- Fallback for this phase if MatchService not present: reset after delay
		warn("[QueueService] MatchService not available, using fallback reset")
		task.delay(Config.LobbyReturnDelay or 5, function()
			local current = QueueService.Slots[slotId]
			if current and current.state == QueueStates.States.STARTING then
				QueueService.ReleaseSlot(slotId)
			end
		end)
	end
end

-- Called by future MatchManager to get players and claim slot
function QueueService.GetPlayersForMatch(slotId: string): {number}?
	local pending = QueueService.PendingMatches[slotId]
	if pending then
		return pending.players
	end
	local slotData = QueueService.Slots[slotId]
	if slotData and slotData.state == QueueStates.States.STARTING then
		local list = {}
		for uid, _ in pairs(slotData.players) do
			table.insert(list, uid)
		end
		return list
	end
	return nil
end

-- Called by future MatchManager when match ends or to reset
function QueueService.ReleaseSlot(slotId: string)
	local slotData = QueueService.Slots[slotId]
	if not slotData then return end

	-- Teleport all players back to lobby (if still in game)
	for _, player in pairs(slotData.players) do
		if player and player.Parent then
			teleportToLobby(player)
		end
	end

	slotData.players = {}
	slotData.occupancy = 0
	slotData.state = QueueStates.States.WAITING
	slotData.countdownActive = false
	slotData.countdownTimeLeft = 0
	slotData.countdownEndTick = nil
	slotData.waitStartTick = nil
	slotData.locked = false

	QueueService.PendingMatches[slotId] = nil

	broadcastStateUpdate(slotId)
	broadcastLocked(slotId, false)

	print("[QueueService] Slot released and reset: " .. slotId)
end

-- ============================================================================
-- INIT & LOOP
-- ============================================================================

function QueueService.Init()
	print("[QueueService] Initializing...")

	-- Load shared modules
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Shared = ReplicatedStorage:WaitForChild("Shared", 10)
	if not Shared then
		error("[QueueService] Missing ReplicatedStorage.Shared folder")
	end

	Config = require(Shared:WaitForChild("Config"))
	QueueStates = require(Shared:WaitForChild("QueueStates"))

	local ServicesFolder = script.Parent
	local RemoteServiceModule = ServicesFolder:FindFirstChild("RemoteService")
	if RemoteServiceModule then
		RemoteService = require(RemoteServiceModule)
		RemoteService.EnsureAllRemotes({
			"RE_QueueJoinRequest",
			"RE_QueueLeaveRequest",
			"RE_QueueStateUpdate",
			"RE_QueueCountdownUpdate",
			"RE_QueueLocked",
			"RE_QueueStarted",
			"RE_QueuePlayerLeft",
		})
	end

	local MatchServiceModule = ServicesFolder:FindFirstChild("MatchService")
	if MatchServiceModule then
		local ok, ms = pcall(require, MatchServiceModule)
		if ok and ms then
			MatchService = ms
			print("[QueueService] Found MatchService for handoff")
		end
	end

	-- Get remotes
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

	-- Find lobby slots
	local lobby = Workspace:FindFirstChild("Lobby")
	if not lobby then
		warn("[QueueService] Missing Workspace.Lobby folder - creating placeholder for validation")
		lobby = Instance.new("Folder")
		lobby.Name = "Lobby"
		lobby.Parent = Workspace
	end

	local matchSlotsFolder = lobby:FindFirstChild("MatchSlots")
	if not matchSlotsFolder then
		warn("[QueueService] Missing Workspace.Lobby.MatchSlots folder")
		matchSlotsFolder = Instance.new("Folder")
		matchSlotsFolder.Name = "MatchSlots"
		matchSlotsFolder.Parent = lobby
	end

	-- Initialize each slot
	for _, slotId in ipairs(QueueService.SlotOrder) do
		local slotModel = matchSlotsFolder:FindFirstChild(slotId)
		if not slotModel then
			warn("[QueueService] Missing slot model: " .. slotId .. " in Lobby.MatchSlots - create it per docs/MANUAL_OBJECTS.md")
			-- Create placeholder data anyway
			QueueService.Slots[slotId] = {
				id = slotId,
				maxPlayers = Config.QueueCapacities[slotId] or 2,
				players = {},
				occupancy = 0,
				state = QueueStates.States.WAITING,
				countdownActive = false,
				countdownTimeLeft = 0,
				countdownEndTick = nil,
				waitStartTick = nil,
				locked = false,
				entryPart = nil,
				displayBoard = nil,
				playerSpawnsFolder = nil,
				touchDebounce = {},
			}
		else
			local entryPart = slotModel:FindFirstChild("EntryArea") or slotModel:FindFirstChild("TouchBlock")
			local displayBoard = slotModel:FindFirstChild("DisplayBoard")
			local playerSpawnsFolder = slotModel:FindFirstChild("PlayerSpawns")

			local maxPlayers = Config.QueueCapacities[slotId] or 2
			if slotModel:GetAttribute("MaxPlayers") then
				maxPlayers = slotModel:GetAttribute("MaxPlayers")
			end

			QueueService.Slots[slotId] = {
				id = slotId,
				maxPlayers = maxPlayers,
				players = {},
				occupancy = 0,
				state = QueueStates.States.WAITING,
				countdownActive = false,
				countdownTimeLeft = 0,
				countdownEndTick = nil,
				waitStartTick = nil,
				locked = false,
				entryPart = entryPart,
				displayBoard = displayBoard,
				playerSpawnsFolder = playerSpawnsFolder,
				touchDebounce = {},
			}

			-- Setup Touched for EntryArea
			if entryPart and entryPart:IsA("BasePart") then
				entryPart.Touched:Connect(function(hit)
					local character = hit.Parent
					if not character then return end
					local player = getPlayerFromCharacter(character)
					if not player then return end

					-- Debounce per player
					local now = tick()
					local last = QueueService.Slots[slotId].touchDebounce[player.UserId] or 0
					if now - last < (Config.TouchDebounce or 1) then
						return
					end
					QueueService.Slots[slotId].touchDebounce[player.UserId] = now

					-- Try join
					local ok, msg = QueueService.TryJoinSlot(player, slotId)
					if Config.DebugPrints then
						print(string.format("[QueueService] Touched %s by %s -> %s (%s)", slotId, player.Name, tostring(ok), msg))
					end
				end)
				print("[QueueService] Connected Touched for " .. slotId .. " EntryArea")
			else
				warn("[QueueService] Missing EntryArea part in " .. slotId .. " - create Part named EntryArea")
			end
		end
	end

	-- RemoteEvent handlers
	if remotes.JoinRequest then
		remotes.JoinRequest.OnServerEvent:Connect(function(player: Player, slotId: string)
			if typeof(slotId) ~= "string" then return end
			-- Validate slotId is one of allowed
			if slotId ~= "Slot2" and slotId ~= "Slot4" and slotId ~= "Slot6" then
				warn("[QueueService] Invalid slotId from client: " .. tostring(slotId))
				return
			end
			local ok, msg = QueueService.TryJoinSlot(player, slotId)
			if Config.DebugPrints then
				print(string.format("[QueueService] JoinRequest %s -> %s : %s (%s)", player.Name, slotId, tostring(ok), msg))
			end
		end)
	end

	if remotes.LeaveRequest then
		remotes.LeaveRequest.OnServerEvent:Connect(function(player: Player)
			local ok, msg = QueueService.LeaveSlot(player)
			if Config.DebugPrints then
				print(string.format("[QueueService] LeaveRequest %s -> %s (%s)", player.Name, tostring(ok), msg))
			end
		end)
	end

	-- Handle disconnect
	Players.PlayerRemoving:Connect(function(player)
		QueueService.LeaveSlot(player)
	end)

	-- Handle reset / death: keep in queue but teleport back on respawn
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			-- Wait a bit for Humanoid
			task.wait(1)
			local slotId = findSlotContainingPlayer(player.UserId)
			if slotId then
				local slotData = QueueService.Slots[slotId]
				if slotData then
					-- Find index of player in slot
					local index = 1
					for uid, _ in pairs(slotData.players) do
						if uid == player.UserId then
							break
						end
						index += 1
					end
					teleportToSpawn(player, slotData, index)
				end
			end
		end)
	end)

	-- Also handle existing players (for Studio test)
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function(character)
			task.wait(1)
			local slotId = findSlotContainingPlayer(player.UserId)
			if slotId then
				local slotData = QueueService.Slots[slotId]
				if slotData then
					local index = 1
					for uid, _ in pairs(slotData.players) do
						if uid == player.UserId then break end
						index += 1
					end
					teleportToSpawn(player, slotData, index)
				end
			end
		end)
	end

	-- Main loop for countdowns and waiting period
	task.spawn(function()
		while true do
			task.wait(1)
			local now = tick()
			for slotId, slotData in pairs(QueueService.Slots) do
				if slotData.state == QueueStates.States.WAITING then
					-- Check if should start partial countdown after waiting period
					if slotData.occupancy >= Config.MinimumPlayers and slotData.occupancy < slotData.maxPlayers then
						if not slotData.waitStartTick then
							slotData.waitStartTick = now
						else
							local waited = now - slotData.waitStartTick
							if waited >= (Config.QueuePartialWaitTime or 30) then
								QueueService.StartCountdown(slotId, "PARTIAL")
							else
								-- Update display with waiting time
								broadcastStateUpdate(slotId)
							end
						end
					elseif slotData.occupancy < Config.MinimumPlayers then
						slotData.waitStartTick = nil
					end
				elseif QueueStates.IsCountingDown(slotData.state) then
					if slotData.countdownEndTick then
						local timeLeft = slotData.countdownEndTick - now
						slotData.countdownTimeLeft = math.max(0, timeLeft)
						broadcastCountdown(slotId, slotData.countdownTimeLeft)
						broadcastStateUpdate(slotId)

						if timeLeft <= 0 then
							QueueService.FinishCountdown(slotId)
						end

						-- Cancel if <2 remain during countdown
						if slotData.occupancy < Config.MinimumPlayers then
							QueueService.CancelCountdown(slotId, "Not enough players during countdown")
						end
					end
				end
			end
		end
	end)

	print("[QueueService] Initialized with slots: " .. table.concat(QueueService.SlotOrder, ", "))
	for slotId, data in pairs(QueueService.Slots) do
		broadcastStateUpdate(slotId)
	end
end

return QueueService
