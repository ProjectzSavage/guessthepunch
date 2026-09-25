--!nonstrict
-- MatchService.luau
-- Purpose: Implements queue handoff + Target selection + Puncher selection + server-authoritative Power gauge ONLY
-- Implements:
-- - Assign queued players to unique match
-- - Move them into correct arena
-- - Prevent joining another queue
-- - Select initial Target server-side
-- - Assign PotentialPuncher role to others
-- - Place players in designated positions (TargetStand+Chair, PlayerSpawns)
-- - Puncher selection phase: first valid server-accepted Punch request becomes Puncher
-- - Move Puncher to controlled position behind Target
-- - Prevent Puncher from freely leaving designated position
-- - Give Puncher short preparation period
-- - Power gauge phase: server starts gauge with server-controlled timestamp, needle ping-pongs,
--   Puncher sends LOCK request (matchId ONLY, no power/zone/timestamp), server calculates zone
--   from SERVER clock, accepts only one lock, rejects duplicate/early/late/invalid requests,
--   stores result for damage system, timeout -> Miss, handles disconnect
-- - Punch sequence + Target match health: server-applied damage (Weak 10/Normal 25/Strong 50/
--   Perfect 100 KO mark/Miss 0), duplicate damage prevention, clamp, match health separate
-- - Guessing phase: starts ONLY after a valid punch, Target submits ONE guess (server-validated),
--   countdown, timeout = incorrect, Puncher hidden until official reveal (RE_GuessResult)
-- - Turn system: CorrectGuess -> Puncher becomes next Target; WrongGuess/GuessTimeout ->
--   same Target remains; either way reset turn state and begin another Punch selection
-- - Handle duplicate requests, spam, rate limits, disconnects
-- - End safely if <2 active or Target invalid
-- Does NOT implement: final elimination flow, winner logic, rewards, scoring, monetization, DataStores, final GUI
-- Roblox Studio Destination: ServerScriptService > Services > MatchService (ModuleScript)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MatchService = {}
MatchService.Matches = {} -- [matchId] = matchData
MatchService.PlayersInMatch = {} -- [userId] = matchId
MatchService.ArenasInUse = {} -- [arenaName] = matchId

local Config
local MatchStates
local Roles
local PowerZones
local Results
local RemoteService

local remotes = {}

local startPowerGauge -- forward declaration, defined in POWER GAUGE section below
local schedulePunchSequence -- forward declaration, defined in PUNCH RESULT RESOLUTION below
local startGuessingPhase -- forward declaration, defined in GUESSING & TURN SYSTEM below
local resetTurnForNewAttempt -- forward declaration, defined in GUESSING & TURN SYSTEM below
local startPunchSelectionWindow -- forward declaration, defined in GUESSING & TURN SYSTEM below

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
	for _, child in ipairs(spawnsFolder:GetChildren()) do
		if child:IsA("BasePart") then return child end
	end
	return nil
end

local function teleportPlayerToCFrame(player: Player, cf: CFrame): boolean
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

local function teleportToArenaSpawn(player: Player, arenaModel: Model, index: number): boolean
	local spawnPart = findPlayerSpawn(arenaModel, index)
	if spawnPart then
		return teleportPlayerToCFrame(player, spawnPart.CFrame)
	else
		warn("[MatchService] No spawn found for index " .. index .. " in arena " .. arenaModel.Name)
		return false
	end
end

local function teleportToTargetStand(player: Player, arenaModel: Model): boolean
	local targetStand = arenaModel:FindFirstChild("TargetStand")
	if not targetStand or not targetStand:IsA("BasePart") then
		warn("[MatchService] Missing TargetStand in arena " .. arenaModel.Name)
		return false
	end
	local success = teleportPlayerToCFrame(player, targetStand.CFrame)
	task.wait(0.2)
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local chair = targetStand:FindFirstChild("Chair")
		if chair and chair:IsA("Seat") and humanoid then
			pcall(function()
				chair:Sit(humanoid)
			end)
		end
	end
	return success
end

local function teleportToPuncherStand(player: Player, arenaModel: Model): boolean
	local puncherStand = arenaModel:FindFirstChild("PuncherStand")
	if puncherStand and puncherStand:IsA("BasePart") then
		return teleportPlayerToCFrame(player, puncherStand.CFrame)
	else
		return false
	end
end

local function getPuncherBehindCFrame(arenaModel: Model?, targetPlayer: Player?): CFrame?
	-- Controlled position behind Target: use PuncherStand if exists, else calculate behind TargetStand or Target HRP
	if arenaModel then
		local puncherStand = arenaModel:FindFirstChild("PuncherStand")
		if puncherStand and puncherStand:IsA("BasePart") then
			return puncherStand.CFrame
		end
		local targetStand = arenaModel:FindFirstChild("TargetStand")
		if targetStand and targetStand:IsA("BasePart") then
			local offset = Config.PuncherOffsetBehindTarget or 6
			-- Behind is -LookVector * offset
			return targetStand.CFrame * CFrame.new(0, 0, offset) -- Roblox: Z forward, so +Z is behind if LookVector is -Z? Use CFrame point
			-- More accurate: CFrame behind = TargetStand CFrame - LookVector * offset
			-- We'll compute: targetStand.CFrame.Position - targetStand.CFrame.LookVector * offset, facing target
		end
	end
	if targetPlayer then
		local char = targetPlayer.Character
		if char then
			local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				local offset = Config.PuncherOffsetBehindTarget or 6
				local behindPos = hrp.Position - hrp.CFrame.LookVector * offset
				-- Face towards Target
				return CFrame.lookAt(behindPos, hrp.Position)
			end
		end
	end
	return nil
end

local function teleportPuncherBehindTarget(puncherPlayer: Player, targetPlayer: Player?, arenaModel: Model?): boolean
	local behindCF = getPuncherBehindCFrame(arenaModel, targetPlayer)
	if behindCF then
		return teleportPlayerToCFrame(puncherPlayer, behindCF)
	else
		-- Fallback to PuncherStand or 0,0,0
		if arenaModel then
			return teleportToPuncherStand(puncherPlayer, arenaModel)
		else
			return teleportPlayerToCFrame(puncherPlayer, CFrame.new(0, 100, 0))
		end
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

-- ============================================================================
-- FILTERED PAYLOADS (anti-cheat: Target must not receive hidden Puncher info)
-- ============================================================================

local function buildFilteredPayload(matchData, forPlayerUserId: number)
	local isTargetRecipient = (forPlayerUserId == matchData.targetUserId)
	local isPuncherRecipient = (forPlayerUserId == matchData.puncherUserId)

	local playerList = {}
	for userId, _ in pairs(matchData.players) do
		table.insert(playerList, userId)
	end

	-- Filter roles: hide Puncher identity from Target
	local filteredRoles = {}
	for uid, role in pairs(matchData.roles) do
		if isTargetRecipient then
			if role == "Puncher" then
				filteredRoles[uid] = "PotentialPuncher" -- mask
			else
				filteredRoles[uid] = role
			end
		else
			filteredRoles[uid] = role
		end
	end

	-- Payload must NOT contain puncherUserId for Target before reveal, nor healthTable, nor private camera/position
	local payload: any = {
		matchId = matchData.matchId,
		state = matchData.state,
		targetUserId = matchData.targetUserId,
		players = playerList,
		roles = filteredRoles,
		arenaName = matchData.arenaName,
	}

	-- Only include puncherUserId for non-Target recipients (Target must not receive hidden Puncher info)
	if not isTargetRecipient then
		if matchData.puncherUserId then
			payload.puncherUserId = matchData.puncherUserId
		end
	else
		-- Explicitly NOT including puncherUserId for Target
	end

	-- For Puncher selection phase, we may include preparation time left, but not power/damage
	if matchData.puncherUserId and matchData.puncherPreparationEndTick then
		local timeLeft = math.max(0, matchData.puncherPreparationEndTick - tick())
		if not isTargetRecipient then
			payload.puncherPreparationTimeLeft = timeLeft
		end
	end

	-- POWER GAUGE DATA MUST NEVER APPEAR IN STATE PAYLOADS:
	-- no gauge timing (startServerTime/duration/sweep), no needle position, no zone/power result.
	-- Gauge timing goes ONLY to the Puncher via RE_PowerGaugeOpen,
	-- zone result goes ONLY to the Puncher via RE_PowerGaugeResult.
	-- matchData.powerGaugeResult (stored for future damage system) is server-internal only.

	return payload
end

local function broadcastMatchState(matchData)
	local re = remotes.StateUpdate
	if not re then return end
	for _, player in pairs(matchData.playerInstances) do
		if player and player.Parent then
			local filteredPayload = buildFilteredPayload(matchData, player.UserId)
			re:FireClient(player, filteredPayload)
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
	for _, player in pairs(matchData.playerInstances) do
		if player and player.Parent then
			re:FireClient(player, matchData.matchId, reason)
		end
	end
end

local function broadcastRoleAssigned(matchData, userId: number, role: string)
	local re = remotes.RoleAssigned
	if not re then return end
	local player = matchData.players[userId]
	if player and player.Parent then
		re:FireClient(player, matchData.matchId, role)
	end
end

local function broadcastPuncherSelected(matchData, puncherUserId: number)
	local re = remotes.PuncherSelected
	if not re then return end
	-- Filtered: Target does NOT get puncherUserId before official reveal
	for _, player in pairs(matchData.playerInstances) do
		if player and player.Parent then
			if player.UserId == matchData.targetUserId then
				-- For Target: hide who is Puncher, only tell that Puncher was selected (no identity)
				re:FireClient(player, matchData.matchId, nil) -- nil = hidden
			else
				re:FireClient(player, matchData.matchId, puncherUserId)
			end
		end
	end
end

local function broadcastPunchRejected(player: Player, matchId: string, reason: string)
	local re = remotes.PunchRejected
	if not re then return end
	if player and player.Parent then
		re:FireClient(player, matchId, reason)
	end
end

local function broadcastPuncherPreparation(matchData, timeLeft: number)
	local re = remotes.PuncherPreparation
	if not re then return end
	for _, player in pairs(matchData.playerInstances) do
		if player and player.Parent then
			if player.UserId == matchData.targetUserId then
				-- Target does not get preparation info about Puncher? For this phase, we hide? But preparation is for Puncher only
				-- For Target, we can send 0 or not send, to not reveal
				re:FireClient(player, matchData.matchId, 0)
			else
				re:FireClient(player, matchData.matchId, timeLeft)
			end
		end
	end
end

-- ============================================================================
-- PUNCHER SELECTION VALIDATION (server authoritative)
-- ============================================================================

local function isPlayerAlive(player: Player): boolean
	local character = player.Character
	if not character then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end
	return humanoid.Health > 0
end

local function validatePunchRequest(player: Player, matchId: string, matchData): (boolean, string)
	-- Server must validate:
	-- Player identity, Match identity, Active role, Current match state, Alive status, Punch eligibility, Duplicate, Rate limits

	-- Player identity
	if not player or not player.Parent then
		return false, "Invalid player identity"
	end
	if not Players:GetPlayerByUserId(player.UserId) then
		return false, "Player not found"
	end

	-- Match identity
	if not matchId or typeof(matchId) ~= "string" then
		return false, "Invalid match identity"
	end
	if matchData.matchId ~= matchId then
		return false, "Match identity mismatch"
	end
	if MatchService.PlayersInMatch[player.UserId] ~= matchId then
		return false, "Player not in this match"
	end
	if not matchData.players[player.UserId] then
		return false, "Player not active in match"
	end

	-- Current match state: must be WaitingForPuncher
	if matchData.state ~= MatchStates.States.WAITING_FOR_PUNCHER then
		return false, "Wrong state: " .. tostring(matchData.state) .. ", must be WaitingForPuncher"
	end

	-- Active role: must be PotentialPuncher, not Target
	local role = matchData.roles[player.UserId]
	if not role then
		return false, "No active role"
	end
	if role == "Target" then
		return false, "Target not eligible to punch"
	end
	if role == "Puncher" then
		return false, "Already Puncher"
	end
	if role ~= "PotentialPuncher" then
		return false, "Not eligible role: " .. tostring(role)
	end

	-- Alive status
	if not isPlayerAlive(player) then
		return false, "Player not alive"
	end

	-- Punch eligibility: Target must be valid
	if not matchData.targetUserId then
		return false, "No Target, cannot punch"
	end
	if not matchData.players[matchData.targetUserId] then
		return false, "Target invalid"
	end

	-- Duplicate: Puncher already selected
	if matchData.puncherUserId then
		return false, "Puncher already selected: " .. tostring(matchData.puncherUserId)
	end

	-- Rate limits and spam handling
	local now = tick()
	local lastRequest = matchData.punchRequests and matchData.punchRequests[player.UserId] or 0
	local cooldown = Config.PunchRequestCooldown or 0.5
	if now - lastRequest < cooldown then
		return false, "Rate limited, wait " .. string.format("%.1f", cooldown - (now - lastRequest)) .. "s"
	end

	-- Spam detection: count requests in window
	if not matchData.punchRequestCounts then
		matchData.punchRequestCounts = {}
	end
	if not matchData.punchRequestCounts[player.UserId] then
		matchData.punchRequestCounts[player.UserId] = {}
	end
	-- Clean old entries outside window
	local window = Config.PunchSpamWindow or 2
	local threshold = Config.PunchSpamThreshold or 3
	local counts = matchData.punchRequestCounts[player.UserId]
	-- Remove old
	for i = #counts, 1, -1 do
		if now - counts[i] > window then
			table.remove(counts, i)
		end
	end
	if #counts >= threshold then
		return false, "Spam detected, too many requests"
	end

	return true, "Valid"
end

local function selectPuncher(matchData, puncherPlayer: Player): boolean
	if matchData.puncherUserId then
		warn("[MatchService] Puncher already selected for match " .. matchData.matchId)
		return false
	end

	local targetPlayer = matchData.players[matchData.targetUserId]
	if not targetPlayer then
		warn("[MatchService] Cannot select Puncher, Target invalid for match " .. matchData.matchId)
		MatchService.EndMatch(matchData.matchId, "Target invalid during puncher selection")
		return false
	end

	-- Assign Puncher role
	matchData.puncherUserId = puncherPlayer.UserId
	matchData.roles[puncherPlayer.UserId] = "Puncher"
	matchData.puncherSelectedTick = tick()
	matchData.puncherPreparationEndTick = tick() + (Config.PuncherPreparationTime or 3)
	matchData.puncherLocked = true -- Other punch actions become unavailable

	print(string.format("[MatchService] Puncher selected for match %s: %s (%d) behind Target %d", matchData.matchId, puncherPlayer.Name, puncherPlayer.UserId, matchData.targetUserId))

	-- Move Puncher to controlled position behind Target
	local success = teleportPuncherBehindTarget(puncherPlayer, targetPlayer, matchData.arenaModel)
	if not success then
		warn("[MatchService] Failed to teleport Puncher behind Target for match " .. matchData.matchId)
	end
	-- Store controlled position for enforcement
	local char = puncherPlayer.Character
	if char then
		local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			matchData.puncherPosition = hrp.CFrame
		end
	end

	-- Broadcast role assigned to Puncher only (Target does NOT get Puncher identity via RoleAssigned? Actually RoleAssigned only to Puncher)
	broadcastRoleAssigned(matchData, puncherPlayer.UserId, "Puncher")

	-- Broadcast PuncherSelected filtered (Target gets nil)
	broadcastPuncherSelected(matchData, puncherPlayer.UserId)

	-- Change state to Punching (preparation period)
	matchData.state = MatchStates.States.PUNCHING
	broadcastMatchState(matchData)

	-- Start enforcement loop to prevent Puncher freely leaving designated position
	if matchData.puncherEnforceConn then
		matchData.puncherEnforceConn:Disconnect()
	end
	matchData.puncherEnforceConn = game:GetService("RunService").Heartbeat:Connect(function()
		if not MatchService.Matches[matchData.matchId] then
			if matchData.puncherEnforceConn then
				matchData.puncherEnforceConn:Disconnect()
				matchData.puncherEnforceConn = nil
			end
			return
		end
		-- Only enforce during preparation
		if not matchData.puncherUserId then return end
		if tick() > (matchData.puncherPreparationEndTick or 0) then
			-- Preparation over, stop enforcing? For this phase, keep enforcing until future power gauge
			-- For now, keep enforcing during Punching state as well to prevent leaving
		end
		local puncher = matchData.players[matchData.puncherUserId]
		if not puncher or not puncher.Parent then return end
		local pChar = puncher.Character
		if not pChar then return end
		local pHRP = pChar:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not pHRP or not matchData.puncherPosition then return end
		local maxDist = Config.PuncherMaxDistanceFromPosition or 4
		local dist = (pHRP.Position - matchData.puncherPosition.Position).Magnitude
		if dist > maxDist then
			-- Teleport back to controlled position
			pHRP.CFrame = matchData.puncherPosition + Vector3.new(0, Config.TeleportOffsetY or 3, 0)
		end
	end)

	-- Start preparation countdown broadcast
	task.spawn(function()
		while MatchService.Matches[matchData.matchId] and matchData.puncherUserId do
			local now = tick()
			local endTick = matchData.puncherPreparationEndTick or now
			local timeLeft = math.max(0, endTick - now)
			broadcastPuncherPreparation(matchData, timeLeft)
			if timeLeft <= 0 then
				print(string.format("[MatchService] Puncher preparation over for match %s, Puncher %d - starting power gauge", matchData.matchId, matchData.puncherUserId))
				-- POWER GAUGE PHASE: start server-authoritative gauge after preparation
				if MatchService.Matches[matchData.matchId]
					and matchData.puncherUserId
					and matchData.state == MatchStates.States.PUNCHING then
					startPowerGauge(matchData)
				end
				break
			end
			task.wait(0.5)
		end
	end)

	return true
end

function MatchService.TryBecomePuncher(player: Player, matchId: string): (boolean, string)
	local matchData = MatchService.Matches[matchId]
	if not matchData then
		return false, "Match not found"
	end

	-- Initialize punch request tracking if not exists
	if not matchData.punchRequests then matchData.punchRequests = {} end
	if not matchData.punchRequestCounts then matchData.punchRequestCounts = {} end
	if not matchData.punchRequestCounts[player.UserId] then matchData.punchRequestCounts[player.UserId] = {} end

	-- Validate
	local ok, reason = validatePunchRequest(player, matchId, matchData)
	if not ok then
		-- Record request for spam tracking even if failed? Only if not rate limited to avoid spam bypass
		if reason ~= "Rate limited" and reason:find("Spam") == nil then
			table.insert(matchData.punchRequestCounts[player.UserId], tick())
		end
		matchData.punchRequests[player.UserId] = tick()
		print(string.format("[MatchService] Punch request rejected for %s in match %s: %s", player.Name, matchId, reason))
		broadcastPunchRejected(player, matchId, reason)
		return false, reason
	end

	-- First valid server-accepted request becomes Puncher, all later rejected
	if matchData.puncherUserId then
		local msg = "Puncher already selected"
		broadcastPunchRejected(player, matchId, msg)
		return false, msg
	end

	-- Record request time
	matchData.punchRequests[player.UserId] = tick()
	table.insert(matchData.punchRequestCounts[player.UserId], tick())

	-- Select Puncher
	local success = selectPuncher(matchData, player)
	if success then
		return true, "Puncher selected"
	else
		return false, "Failed to select Puncher"
	end
end

-- ============================================================================
-- POWER GAUGE (server-authoritative; stores result for future damage system)
-- Client may display the gauge but must NOT send the final power value.
-- Client sends ONLY the lock request (matchId). Server calculates zone from SERVER clock.
-- ============================================================================

local function cancelPowerGauge(matchData, reason: string)
	if matchData.powerGauge and not matchData.powerGauge.resolved then
		matchData.powerGauge.resolved = true
		matchData.powerGauge.cancelled = true
		print(string.format("[MatchService] Power gauge CANCELLED for match %s: %s", matchData.matchId, reason))
	end
	matchData.powerGauge = nil
end

local function firePowerGaugeOpen(matchData, gauge)
	local re = remotes.PowerGaugeOpen
	if not re then return end
	local puncher = matchData.players[matchData.puncherUserId]
	if puncher and puncher.Parent then
		-- Server-controlled timestamp. Fired to the PUNCHER ONLY:
		-- Target and other players never receive gauge timing (anti-cheat filtering).
		re:FireClient(puncher, matchData.matchId, gauge.startServerTime, gauge.endServerTime - gauge.startServerTime, gauge.sweepDuration)
	end
end

local function broadcastPowerGaugeResult(matchData, zone: string, position: number, timedOut: boolean)
	local re = remotes.PowerGaugeResult
	if not re then return end
	local puncher = matchData.players[matchData.puncherUserId]
	if puncher and puncher.Parent then
		-- Result goes to the PUNCHER ONLY. Target and others get nothing
		-- (power/zone info stays server-internal until future damage phase).
		re:FireClient(puncher, matchData.matchId, zone, position, timedOut)
	end
end

-- Starts the gauge using a server-controlled timestamp (workspace:GetServerTimeNow)
startPowerGauge = function(matchData)
	if not MatchService.Matches[matchData.matchId] then return end
	if not matchData.puncherUserId then return end
	local puncher = matchData.players[matchData.puncherUserId]
	if not puncher or not puncher.Parent then return end
	if matchData.state ~= MatchStates.States.PUNCHING then return end

	local nowServer = workspace:GetServerTimeNow()
	local duration = Config.PowerGaugeDuration or 5
	local sweep = Config.PowerGaugeSweepDuration or 1.25
	local gauge = {
		startServerTime = nowServer, -- SERVER-controlled timestamp
		endServerTime = nowServer + duration,
		sweepDuration = sweep,
		locked = false, -- accept only ONE lock
		resolved = false,
		cancelled = false,
		lockRequestCount = 0,
		lastLockRequestTick = 0,
	}
	matchData.powerGauge = gauge
	matchData.state = MatchStates.States.POWER_GAUGE
	broadcastMatchState(matchData) -- filtered payload contains NO gauge data
	firePowerGaugeOpen(matchData, gauge)
	print(string.format("[MatchService] Power gauge STARTED for match %s, puncher %s (%d), window %.2fs, sweep %.2fs, startServerTime=%.3f",
		matchData.matchId, puncher.Name, puncher.UserId, duration, sweep, nowServer))

	-- Server timeout loop: no valid lock by endServerTime + grace -> Miss (stored for damage system)
	task.spawn(function()
		local grace = Config.PowerGaugeLockLateGrace or 0.15
		while MatchService.Matches[matchData.matchId] and not gauge.resolved and not gauge.cancelled do
			if workspace:GetServerTimeNow() >= gauge.endServerTime + grace then
				gauge.resolved = true
				if not gauge.locked then
					-- TIMEOUT -> Miss
					matchData.powerGaugeResult = {
						zone = PowerZones.Zones.MISS,
						position = 0,
						lockedTick = tick(),
						timedOut = true,
					}
					broadcastPowerGaugeResult(matchData, PowerZones.Zones.MISS, 0, true)
					-- Miss PRESENTATION (whiff/no-contact) - still one sequence, 0 damage
					schedulePunchSequence(matchData, PowerZones.Zones.MISS, true)
					print(string.format("[MatchService] Power gauge TIMEOUT for match %s -> Miss (stored for damage system)", matchData.matchId))
				else
					print(string.format("[MatchService] Power gauge resolved by lock for match %s", matchData.matchId))
				end
				break
			end
			task.wait(0.05)
		end
	end)
end

-- Validates a lock request. Server must reject duplicate, early, late and invalid requests.
local function validateGaugeLockRequest(player: Player, matchId: string, matchData): (boolean, string)
	-- 1. Player identity
	if not player or not player.Parent then
		return false, "Invalid player identity"
	end
	if not Players:GetPlayerByUserId(player.UserId) then
		return false, "Player not found"
	end

	-- 2. Match identity
	if type(matchId) ~= "string" then
		return false, "Invalid match identity"
	end
	if matchData.matchId ~= matchId then
		return false, "Match identity mismatch"
	end
	if MatchService.PlayersInMatch[player.UserId] ~= matchId then
		return false, "Player not in this match"
	end
	if not matchData.players[player.UserId] then
		return false, "Player not active in match"
	end

	-- 3. Active role: must be THE Puncher
	if matchData.puncherUserId ~= player.UserId then
		return false, "Not the Puncher"
	end
	if matchData.roles[player.UserId] ~= "Puncher" then
		return false, "Not the Puncher"
	end

	-- 4. Current match state
	if matchData.state ~= MatchStates.States.POWER_GAUGE then
		return false, "Wrong state: " .. tostring(matchData.state) .. ", must be PowerGauge"
	end

	-- 5. Gauge exists and is active
	local gauge = matchData.powerGauge
	if not gauge then
		return false, "No active gauge"
	end
	if gauge.cancelled then
		return false, "Gauge cancelled"
	end
	if gauge.resolved then
		return false, "Gauge already resolved"
	end

	-- 6. Duplicate: accept only ONE lock request
	if gauge.locked then
		return false, "Gauge already locked"
	end

	-- 7. Rate limits (anti-spam)
	local nowTick = tick()
	if nowTick - (gauge.lastLockRequestTick or 0) < (Config.PowerGaugeLockCooldown or 0.25) then
		return false, "Rate limited"
	end
	gauge.lastLockRequestTick = nowTick
	gauge.lockRequestCount = (gauge.lockRequestCount or 0) + 1
	if gauge.lockRequestCount > (Config.PowerGaugeMaxLockRequests or 5) then
		return false, "Too many lock requests"
	end

	-- 8. Alive status
	if not isPlayerAlive(player) then
		return false, "Player not alive"
	end

	-- 9. Timing (SERVER clock is authoritative; client timestamp is never trusted)
	local nowServer = workspace:GetServerTimeNow()
	local grace = Config.PowerGaugeLockLateGrace or 0.15
	if nowServer < gauge.startServerTime - 0.1 then
		return false, "Too early"
	end
	if nowServer > gauge.endServerTime + grace then
		return false, "Too late"
	end

	return true, "Valid"
end

local function broadcastPowerGaugeRejected(player: Player, matchId: string, reason: string)
	local re = remotes.PowerGaugeRejected
	if not re then return end
	if player and player.Parent then
		re:FireClient(player, matchId, reason)
	end
end

-- ============================================================================
-- PUNCH RESULT RESOLUTION (server-authoritative)
-- The SERVER-selected power result (matchData.powerGaugeResult.zone) determines
-- the presentation AND the damage. Visual effects NEVER determine the game result.
-- MATCH HEALTH is stored server-side, separate from Roblox Humanoid health
-- (Humanoid.Health is NEVER modified in this phase).
-- ============================================================================

-- Fired at the PUNCH MOMENT (= official reveal) to ALL match clients:
-- (matchId, zone, puncherUserId, targetUserId, timedOut). Presentation choice is the
-- client's job; the zone it must present comes from the SERVER.
local function broadcastPunchSequence(matchData, zone: string, timedOut: boolean)
	local re = remotes.PunchSequence
	if not re then return end
	for _, player in pairs(matchData.playerInstances) do
		if player and player.Parent then
			re:FireClient(player, matchData.matchId, zone, matchData.puncherUserId, matchData.targetUserId, timedOut)
		end
	end
end

-- (matchId, targetUserId, health, maxHealth, lastDamage, lastZone) to ALL match clients.
local function broadcastTargetHealth(matchData, lastDamage: number, lastZone: string)
	local re = remotes.TargetHealthUpdate
	if not re then return end
	local maxHealth = Config.StartingHealth or 100
	for _, player in pairs(matchData.playerInstances) do
		if player and player.Parent then
			re:FireClient(player, matchData.matchId, matchData.targetUserId, matchData.targetHealth or maxHealth, maxHealth, lastDamage, lastZone)
		end
	end
end

-- Applies damage ONLY after a valid punch result (locked gauge -> stored zone).
-- Never accepts client-provided damage. Prevents duplicate damage via damageApplied flag.
-- Clamps health at zero. Detects zero health -> mark Target knocked out + PAUSE
-- (full elimination flow is FUTURE - deliberately not implemented here).
local function applyPunchDamage(matchData)
	if not MatchService.Matches[matchData.matchId] then return end
	if matchData.damageApplied then
		print("[MatchService] Duplicate damage prevented for match " .. matchData.matchId)
		return
	end
	local result = matchData.powerGaugeResult
	if not result then
		print("[MatchService] No valid punch result, damage skipped for match " .. matchData.matchId)
		return
	end
	local targetPlayer = matchData.players[matchData.targetUserId]
	if not targetPlayer then
		print("[MatchService] Target gone, damage skipped for match " .. matchData.matchId)
		return
	end

	local zone = result.zone
	local damage = (Config.Damage and Config.Damage[zone]) or 0
	matchData.damageApplied = true

	-- MATCH health (separate from Humanoid health). Clamp at zero.
	matchData.targetHealth = math.max(0, (matchData.targetHealth or Config.StartingHealth or 100) - damage)
	print(string.format("[MatchService] DAMAGE match %s: Target %d takes %d (%s) -> health %d/%d (Humanoid health untouched)",
		matchData.matchId, matchData.targetUserId, damage, zone, matchData.targetHealth, Config.StartingHealth or 100))
	broadcastTargetHealth(matchData, damage, zone)

	-- Detect zero health -> mark knocked out + pause
	if matchData.targetHealth <= 0 then
		matchData.targetKnockedOut = true
		if MatchStates.CanTransition(matchData.state, MatchStates.States.KNOCKED_OUT) then
			matchData.state = MatchStates.States.KNOCKED_OUT
		end
		broadcastMatchState(matchData)
		print(string.format("[MatchService] TARGET KNOCKED OUT in match %s (health 0) - PAUSED, marked only. Full elimination flow is FUTURE (not implemented).", matchData.matchId))
	else
		-- Target survived a valid punch -> GUESSING phase starts (server-authoritative)
		startGuessingPhase(matchData)
	end
end

-- Schedules the visual punch sequence timing SERVER-side (prep -> punch -> contact).
-- One sequence per punch result (sequenceFired guard prevents repeated triggering).
-- The sequence event is fired IMMEDIATELY so clients can play raise/hold during the server
-- prep window and the impact visual lands exactly at the server damage moment.
-- If the match ends or puncher/target disconnects mid-schedule, sequenceCancelled stops it
-- and clients clean their effects.
schedulePunchSequence = function(matchData, zone: string, timedOut: boolean)
	if not Config.PunchSequenceEnabled then return end
	if not MatchService.Matches[matchData.matchId] then return end
	if matchData.sequenceFired then
		print("[MatchService] Punch sequence already fired for match " .. matchData.matchId .. " - repeat prevented")
		return
	end
	matchData.sequenceFired = true

	task.spawn(function()
		local prepTime = Config.PunchSequencePrepTime or 0.6
		local contactTime = Config.PunchSequenceContactTime or 0.35

		-- Fire at the PUNCH MOMENT start (clients play raise/hold now, strike at prep, impact at prep+contact)
		broadcastPunchSequence(matchData, zone, timedOut)
		print(string.format("[MatchService] Punch sequence FIRED for match %s: zone=%s timedOut=%s (prep %.2fs, contact %.2fs)",
			matchData.matchId, zone, tostring(timedOut), prepTime, contactTime))

		task.wait(prepTime + contactTime)
		if not MatchService.Matches[matchData.matchId] or matchData.sequenceCancelled then
			print("[MatchService] Punch sequence cancelled before contact for match " .. matchData.matchId)
			return
		end
		-- Damage ONLY after a valid (locked) punch result. Gauge timeout = nobody punched:
		-- Miss presentation, 0 damage, and NO guessing phase (guessing starts only after a valid punch).
		if timedOut or zone == PowerZones.Zones.MISS then
			print("[MatchService] Gauge-timeout Miss for match " .. matchData.matchId .. " - 0 damage, no contact, NO guessing (no valid punch)")
			matchData.damageApplied = true -- consume the result: no further damage possible
			broadcastTargetHealth(matchData, 0, PowerZones.Zones.MISS)
			-- Begin another Punch selection phase (same Target remains, everyone may request again)
			task.spawn(function()
				task.wait(Config.GuessResultMissPause or 1.0)
				if not MatchService.Matches[matchData.matchId] then return end
				if matchData.state ~= MatchStates.States.POWER_GAUGE then return end -- leaving/state change already handled
				resetTurnForNewAttempt(matchData)
				startPunchSelectionWindow(matchData)
			end)
		else
			applyPunchDamage(matchData) -- applies damage; on survival starts the guessing phase
		end
	end)
end

-- ============================================================================
-- GUESSING & TURN SYSTEM (server-authoritative)
-- Guessing starts ONLY after a valid punch (locked gauge -> damage applied, Target survived).
-- Target submits ONE guess via RE_GuessRequest (matchId, guessedUserId). Server validates:
-- correct phase/state, only Target, eligible non-Target choice, one guess, no stale events.
-- Results (Results.GuessResults): CorrectGuess / WrongGuess / GuessTimeout / InvalidGuess.
-- Puncher identity stays HIDDEN until reveal; RE_GuessResult (to ALL) = OFFICIAL reveal
-- after submission or timeout. Then the turn system runs:
--   CorrectGuess -> Puncher becomes the next Target
--   WrongGuess / GuessTimeout (treated as incorrect) -> same Target remains
--   Either way: reset Puncher/power/guessing/timer state, begin another Punch selection.
-- No final elimination, winner logic, rewards, or DataStores (FUTURE).
-- ============================================================================

local function broadcastGuessRejected(player: Player, matchId: string, reason: string)
	local re = remotes.GuessRejected
	if not re then return end
	if player and player.Parent then
		re:FireClient(player, matchId, reason)
	end
end

-- Fire InvalidGuess result to the Target ONLY (no reveal; for later systems/logging)
local function fireInvalidGuessResult(matchData, reason: string)
	local re = remotes.GuessResult
	if not re then return end
	local target = matchData.players[matchData.targetUserId]
	if target and target.Parent then
		re:FireClient(target, matchData.matchId, Results.GuessResults.INVALID, nil, nil, reason)
	end
end

-- Sent to the TARGET ONLY: eligible choices (all active players EXCEPT the Target) + countdown.
-- Contains NO puncher information. Rebroadcast for countdown updates and eligible shrink.
local function broadcastGuessOpen(matchData)
	local re = remotes.GuessOpen
	if not re then return end
	local target = matchData.players[matchData.targetUserId]
	if not target or not target.Parent then return end
	local eligible = {}
	for userId, _ in pairs(matchData.players) do
		if userId ~= matchData.targetUserId then
			table.insert(eligible, userId)
		end
	end
	local timeLeft = math.max(0, (matchData.guessEndTick or tick()) - tick())
	re:FireClient(target, matchData.matchId, eligible, timeLeft)
end

-- Starts the guessing phase. Called ONLY from applyPunchDamage (valid punch, Target survived).
startGuessingPhase = function(matchData)
	if not Config.GuessingEnabled then return end
	if not MatchService.Matches[matchData.matchId] then return end
	if not matchData.targetUserId or not matchData.players[matchData.targetUserId] then return end
	if matchData.targetKnockedOut or (matchData.targetHealth or 0) <= 0 then return end
	if not matchData.puncherUserId then
		-- No puncher (edge): skip guessing, start a new punch selection with same Target
		resetTurnForNewAttempt(matchData)
		startPunchSelectionWindow(matchData)
		return
	end
	-- Official Puncher reveal happens ONLY after submission/timeout; state payload stays filtered
	matchData.guessPhaseActive = true
	matchData.guessLocked = false
	matchData.guessedUserId = nil
	matchData.guessEndTick = tick() + (Config.GuessingDuration or 15)
	matchData.guessAttempt = (matchData.guessAttempt or 0) + 1 -- stale-loop guard
	if MatchStates.CanTransition(matchData.state, MatchStates.States.GUESSING) then
		matchData.state = MatchStates.States.GUESSING
	end
	broadcastMatchState(matchData) -- filtered: still NO puncherUserId for Target
	broadcastGuessOpen(matchData)
	print(string.format("[MatchService] GUESSING started for match %s: Target %d has %.0fs to guess (one guess, timeout = incorrect)",
		matchData.matchId, matchData.targetUserId, Config.GuessingDuration or 15))

	-- Countdown + timeout loop (attempt-guarded so stale loops never fire into a new attempt)
	local myAttempt = matchData.guessAttempt
	task.spawn(function()
		while MatchService.Matches[matchData.matchId]
			and matchData.state == MatchStates.States.GUESSING
			and matchData.guessAttempt == myAttempt
			and matchData.guessPhaseActive do
			task.wait(1)
			if not MatchService.Matches[matchData.matchId] then return end
			if matchData.guessAttempt ~= myAttempt then return end -- stale
			if not matchData.guessPhaseActive then return end -- resolved by submission
			if matchData.state ~= MatchStates.States.GUESSING then return end
			if matchData.guessLocked then return end
			-- Update countdown + eligible list on the Target's UI (handles players leaving)
			broadcastGuessOpen(matchData)
			if tick() >= (matchData.guessEndTick or 0) then
				-- TIMEOUT -> treated as incorrect, reveal Puncher
				resolveGuess(matchData, Results.GuessResults.TIMEOUT, nil, myAttempt)
				return
			end
		end
	end)
end

-- Reset Puncher, power, guessing, damage/sequence and timer state between attempts.
-- Increments turnAttempt so STALE async loops/events from the old attempt cannot affect the new one.
resetTurnForNewAttempt = function(matchData)
	-- Prevent stale events from affecting the new attempt
	matchData.turnAttempt = (matchData.turnAttempt or 0) + 1

	-- Puncher reset
	if matchData.puncherEnforceConn then
		matchData.puncherEnforceConn:Disconnect()
		matchData.puncherEnforceConn = nil
	end
	local oldPuncherUserId = matchData.puncherUserId
	if oldPuncherUserId and matchData.players[oldPuncherUserId] then
		matchData.roles[oldPuncherUserId] = "PotentialPuncher"
		broadcastRoleAssigned(matchData, oldPuncherUserId, "PotentialPuncher")
	end
	matchData.puncherUserId = nil
	matchData.puncherSelectedTick = nil
	matchData.puncherPreparationEndTick = nil
	matchData.puncherPosition = nil
	matchData.puncherLocked = false
	matchData.punchRequests = {}
	matchData.punchRequestCounts = {}

	-- Power gauge + stored result reset
	cancelPowerGauge(matchData, "turn reset")
	matchData.powerGaugeResult = nil

	-- Damage/sequence re-arm for the new attempt
	matchData.damageApplied = false
	matchData.sequenceFired = false
	matchData.sequenceCancelled = false

	-- Guessing reset
	matchData.guessPhaseActive = false
	matchData.guessLocked = false
	matchData.guessedUserId = nil
	matchData.guessEndTick = nil
	matchData.guessAttempt = (matchData.guessAttempt or 0) + 1 -- stale guess loops die

	print("[MatchService] Turn state reset for match " .. matchData.matchId .. " (attempt " .. tostring(matchData.turnAttempt) .. ")")
end

-- (Re)starts a Punch selection window: WaitingForPuncher + fresh timer + attempt-guarded timeout loop.
startPunchSelectionWindow = function(matchData)
	if not MatchService.Matches[matchData.matchId] then return end
	matchData.state = MatchStates.States.WAITING_FOR_PUNCHER
	matchData.punchSelectionEndTick = tick() + (Config.PunchSelectionDuration or 15)
	matchData.turnAttempt = (matchData.turnAttempt or 0) + 1
	local myAttempt = matchData.turnAttempt
	broadcastMatchState(matchData)
	print("[MatchService] Match " .. matchData.matchId .. " now WaitingForPuncher - waiting for first valid Punch request (attempt " .. tostring(myAttempt) .. ")")

	-- Punch selection timeout loop (attempt-guarded)
	task.spawn(function()
		while MatchService.Matches[matchData.matchId]
			and matchData.state == MatchStates.States.WAITING_FOR_PUNCHER
			and matchData.turnAttempt == myAttempt do
			task.wait(1)
			if not MatchService.Matches[matchData.matchId] then return end
			if matchData.turnAttempt ~= myAttempt then return end -- stale
			if matchData.puncherUserId then
				break -- Puncher already selected
			end
			local now = tick()
			if matchData.punchSelectionEndTick and now >= matchData.punchSelectionEndTick then
				if not matchData.puncherUserId then
					print("[MatchService] Punch selection timeout for match " .. matchData.matchId .. " - no Puncher selected")
					MatchService.EndMatch(matchData.matchId, "No Puncher selected in time")
					break
				end
			end
			-- End safely if Target invalid
			if not matchData.targetUserId or not matchData.players[matchData.targetUserId] then
				print("[MatchService] Target invalid during WaitingForPuncher for match " .. matchData.matchId)
				MatchService.EndMatch(matchData.matchId, "Target invalid during puncher selection")
				break
			end
		end
	end)
end

-- Resolves the guess: OFFICIAL REVEAL to ALL, then the TURN SYSTEM transition.
local function resolveGuess(matchData, result: string, guessedUserId: number?, attemptId: number?)
	if not MatchService.Matches[matchData.matchId] then return end
	if matchData.state ~= MatchStates.States.GUESSING then return end
	if attemptId and matchData.guessAttempt ~= attemptId then return end -- stale attempt
	if not matchData.guessPhaseActive then return end -- already resolved/cancelled
	matchData.guessPhaseActive = false

	local puncherUserId = matchData.puncherUserId

	-- OFFICIAL PUNCHER REVEAL to ALL match clients (submission or timeout)
	local re = remotes.GuessResult
	if re then
		for _, player in pairs(matchData.playerInstances) do
			if player and player.Parent then
				re:FireClient(player, matchData.matchId, result, guessedUserId, puncherUserId)
			end
		end
	end
	print(string.format("[MatchService] GUESS RESOLVED for match %s: result=%s guessed=%s puncher=%s (revealed to all)",
		matchData.matchId, result, tostring(guessedUserId), tostring(puncherUserId)))

	-- TURN SYSTEM transition after a brief reveal pause (server-authoritative, attempt-guarded)
	local myTurn = matchData.turnAttempt
	task.spawn(function()
		task.wait(Config.GuessRevealPause or 1.5)
		if not MatchService.Matches[matchData.matchId] then return end
		if matchData.turnAttempt ~= myTurn then return end -- stale (players leaving / match end already handled it)
		if matchData.state ~= MatchStates.States.GUESSING then return end -- leaving logic already advanced state

		if result == Results.GuessResults.CORRECT and puncherUserId and matchData.players[puncherUserId] then
			-- CORRECT GUESS: the Puncher becomes the next Target
			local newTargetUserId = puncherUserId
			local oldTargetUserId = matchData.targetUserId
			resetTurnForNewAttempt(matchData)
			matchData.targetUserId = newTargetUserId
			for userId, _ in pairs(matchData.players) do
				if userId == newTargetUserId then
					matchData.roles[userId] = "Target"
				else
					matchData.roles[userId] = "PotentialPuncher"
				end
				broadcastRoleAssigned(matchData, userId, matchData.roles[userId])
			end
			-- Teleport: new Target -> TargetStand (chair), old Target -> a player spawn
			local newTargetPlayer = matchData.players[newTargetUserId]
			if newTargetPlayer and matchData.arenaModel then
				teleportToTargetStand(newTargetPlayer, matchData.arenaModel)
			end
			local oldTargetPlayer = matchData.players[oldTargetUserId]
			if oldTargetPlayer and matchData.arenaModel then
				local idx = 1
				for i, p in ipairs(matchData.playerInstances) do
					if p.UserId == oldTargetUserId then idx = i break end
				end
				teleportToArenaSpawn(oldTargetPlayer, matchData.arenaModel, idx)
			end
			-- NEW Target -> fresh match health
			matchData.targetHealth = Config.StartingHealth or 100
			matchData.targetKnockedOut = false
			broadcastTargetHealth(matchData, 0, "Reset")
			print(string.format("[MatchService] Correct guess: Puncher %d is the NEW TARGET for match %s (fresh health)", newTargetUserId, matchData.matchId))
		else
			-- WRONG GUESS or TIMEOUT (treated as incorrect): the same Target remains active
			resetTurnForNewAttempt(matchData)
			print(string.format("[MatchService] %s: same Target %d remains for match %s", result, matchData.targetUserId, matchData.matchId))
		end

		-- Either way: begin another Punch selection phase
		if MatchService.Matches[matchData.matchId] then
			startPunchSelectionWindow(matchData)
		end
	end)
end

-- Entry point for RE_GuessRequest. Only the Target, only during Guessing, one guess, eligible choice.
function MatchService.TrySubmitGuess(player: Player, matchId: any, guessedUserId: any): (boolean, string)
	local matchData = nil
	if type(matchId) == "string" then
		matchData = MatchService.Matches[matchId]
	end
	if not matchData then
		local knownMatchId = MatchService.PlayersInMatch[player.UserId]
		if knownMatchId then
			matchData = MatchService.Matches[knownMatchId]
		end
	end
	if not matchData then
		broadcastGuessRejected(player, type(matchId) == "string" and matchId or "", "Match not found")
		return false, "Match not found"
	end

	-- Validate (server-authoritative; prevents guessing before the phase starts)
	if not player or not player.Parent or not Players:GetPlayerByUserId(player.UserId) then
		return false, "Invalid player identity"
	end
	if MatchService.PlayersInMatch[player.UserId] ~= matchData.matchId or not matchData.players[player.UserId] then
		broadcastGuessRejected(player, matchData.matchId, "Player not in this match")
		return false, "Player not in this match"
	end
	if matchData.state ~= MatchStates.States.GUESSING or not matchData.guessPhaseActive then
		broadcastGuessRejected(player, matchData.matchId, "Guessing phase not active")
		fireInvalidGuessResult(matchData, "Too early / phase not active")
		return false, "Guessing phase not active"
	end
	if player.UserId ~= matchData.targetUserId then
		broadcastGuessRejected(player, matchData.matchId, "Only the Target can guess")
		return false, "Only the Target can guess"
	end
	if matchData.guessLocked then
		-- Reject duplicate guesses (the one submitted guess was already used)
		broadcastGuessRejected(player, matchData.matchId, "Duplicate: guess already submitted")
		fireInvalidGuessResult(matchData, "Duplicate guess")
		return false, "Duplicate guess"
	end
	if type(guessedUserId) ~= "number" then
		broadcastGuessRejected(player, matchData.matchId, "Invalid guess (must be a player)")
		fireInvalidGuessResult(matchData, "Invalid guess format")
		return false, "Invalid guess"
	end
	if guessedUserId == matchData.targetUserId then
		-- Target is excluded from choices
		broadcastGuessRejected(player, matchData.matchId, "You cannot guess yourself")
		fireInvalidGuessResult(matchData, "Guessed the Target")
		return false, "Invalid guess"
	end
	if not matchData.players[guessedUserId] then
		-- Guessed player not eligible (not an active match player)
		broadcastGuessRejected(player, matchData.matchId, "Guessed player is not eligible")
		fireInvalidGuessResult(matchData, "Ineligible player")
		return false, "Invalid guess"
	end

	-- ACCEPT the one submitted guess and evaluate on the SERVER
	matchData.guessLocked = true
	matchData.guessedUserId = guessedUserId
	local result
	if guessedUserId == matchData.puncherUserId then
		result = Results.GuessResults.CORRECT
	else
		result = Results.GuessResults.WRONG
	end
	print(string.format("[MatchService] Guess ACCEPTED for match %s: Target %d guessed %d -> %s",
		matchData.matchId, player.UserId, guessedUserId, result))
	resolveGuess(matchData, result, guessedUserId, matchData.guessAttempt)
	return true, result
end

-- Entry point for RE_PowerGaugeStopRequest. Client may send extra args (power/zone claims)
-- - they are IGNORED. Server computes needle position and zone from the SERVER clock,
-- so a client can NEVER claim Perfect (or any zone).
function MatchService.TryLockPowerGauge(player: Player, matchId: any, ...): (boolean, string)
	-- ... = any client-sent extra args are deliberately ignored (never trusted)
	local matchData = nil
	if type(matchId) == "string" then
		matchData = MatchService.Matches[matchId]
	end
	if not matchData then
		local knownMatchId = MatchService.PlayersInMatch[player.UserId]
		if knownMatchId then
			matchData = MatchService.Matches[knownMatchId]
		end
	end
	if not matchData then
		broadcastPowerGaugeRejected(player, type(matchId) == "string" and matchId or "", "Match not found")
		return false, "Match not found"
	end

	local ok, reason = validateGaugeLockRequest(player, matchData.matchId, matchData)
	if not ok then
		print(string.format("[MatchService] Gauge lock REJECTED for %s in match %s: %s", player.Name, matchData.matchId, reason))
		broadcastPowerGaugeRejected(player, matchData.matchId, reason)
		return false, reason
	end

	-- ACCEPT: one and only one lock. Calculate zone from SERVER clock.
	local gauge = matchData.powerGauge
	gauge.locked = true
	gauge.resolved = true
	gauge.lockedTick = tick()

	local nowServer = workspace:GetServerTimeNow()
	local maxElapsed = (gauge.endServerTime - gauge.startServerTime) + (Config.PowerGaugeLockLateGrace or 0.15)
	local elapsed = math.clamp(nowServer - gauge.startServerTime, 0, maxElapsed)
	local position = PowerZones.GetNeedlePosition(elapsed, gauge.sweepDuration)
	local zone = PowerZones.GetZoneForPosition(position, Config.PowerGaugeZoneThresholds)

	-- Store the result for the future damage system (server-internal, never broadcast to Target)
	matchData.powerGaugeResult = {
		zone = zone,
		position = position,
		lockedTick = tick(),
		serverTime = nowServer,
		timedOut = false,
		puncherUserId = player.UserId,
	}

	broadcastPowerGaugeResult(matchData, zone, position, false)
	broadcastMatchState(matchData) -- state stays PowerGauge; payload contains NO gauge/zone data
	print(string.format("[MatchService] Gauge LOCKED for match %s by %s (%d): zone=%s position=%.3f (server-calculated)",
		matchData.matchId, player.Name, player.UserId, zone, position))

	-- PUNCH SEQUENCE + DAMAGE: the SERVER-selected zone drives the presentation and,
	-- at contact time, the server-applied damage. Client visuals never determine the result.
	schedulePunchSequence(matchData, zone, false)
	return true, zone
end

-- ============================================================================
-- CORE MATCH LOGIC (queue handoff + target + puncher selection)
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

	local arenaName = Config.ArenaBySlot[slotId] or ("Arena" .. tostring(Config.QueueCapacities[slotId] or 2))
	local arenaModel = getArenaModel(arenaName)
	if not arenaModel then
		warn("[MatchService] Missing arena model: " .. arenaName .. " in Workspace.MatchArenas")
	end

	if MatchService.ArenasInUse[arenaName] then
		local existingMatchId = MatchService.ArenasInUse[arenaName]
		local existingMatch = MatchService.Matches[existingMatchId]
		if existingMatch and existingMatch.state ~= "Finished" then
			warn("[MatchService] Arena " .. arenaName .. " already in use by match " .. existingMatchId .. " - allowing shared for now")
		end
	end

	local matchId = generateMatchId(slotId)
	print(string.format("[MatchService] Creating match %s from queue %s with %d players, arena %s", matchId, slotId, #playerUserIds, arenaName))

	local matchData = {
		matchId = matchId,
		slotId = slotId,
		arenaName = arenaName,
		arenaModel = arenaModel,
		players = {},
		playerInstances = {},
		roles = {},
		targetUserId = nil,
		puncherUserId = nil,
		puncherSelectedTick = nil,
		puncherPreparationEndTick = nil,
		puncherPosition = nil,
		puncherLocked = false,
		puncherEnforceConn = nil,
		punchRequests = {}, -- [userId] = last tick
		punchRequestCounts = {}, -- [userId] = {ticks}
		state = MatchStates.States.PREPARING,
		createdTick = tick(),
		activePlayers = #playerUserIds,
		punchSelectionEndTick = nil,
		powerGauge = nil, -- active gauge: {startServerTime, endServerTime, sweepDuration, locked, resolved, cancelled, lockRequestCount, lastLockRequestTick}
		powerGaugeResult = nil, -- stored for damage system: {zone, position, lockedTick, serverTime, timedOut, puncherUserId} - SERVER-INTERNAL, never broadcast before damage
		-- TARGET MATCH HEALTH (separate from Roblox Humanoid health - Humanoid.Health is NEVER modified)
		targetHealth = Config.StartingHealth or 100, -- reset for every new match (fresh matchData)
		targetKnockedOut = false, -- marked when health reaches 0; full elimination flow is FUTURE
		damageApplied = false, -- prevents duplicate damage per punch result
		sequenceFired = false, -- prevents repeated punch sequence triggering
		sequenceCancelled = false, -- set on match end / disconnect mid-sequence
		-- GUESSING & TURN SYSTEM
		turnAttempt = 0, -- increments each turn reset; stale async loops/events are discarded when it changes
		guessPhaseActive = false, -- guessing phase currently running (only after a valid punch)
		guessLocked = false, -- the ONE submitted guess (duplicate guesses rejected)
		guessedUserId = nil, -- the submitted guess (server-evaluated)
		guessEndTick = nil, -- countdown deadline (timeout = incorrect)
		guessAttempt = 0, -- increments per guess phase; stale guess loops die when it changes
	}

	for i, userId in ipairs(playerUserIds) do
		local player = playerInstances[i] or Players:GetPlayerByUserId(userId)
		if player then
			matchData.players[userId] = player
			table.insert(matchData.playerInstances, player)
			MatchService.PlayersInMatch[userId] = matchId
			matchData.roles[userId] = "Queued"
		else
			warn("[MatchService] Player instance not found for userId " .. userId)
		end
	end

	MatchService.ArenasInUse[arenaName] = matchId
	MatchService.Matches[matchId] = matchData

	broadcastMatchStart(matchData)
	broadcastMatchState(matchData)

	task.spawn(function()
		task.wait(0.5)
		for idx, player in ipairs(matchData.playerInstances) do
			if player and player.Parent then
				if arenaModel then
					teleportToArenaSpawn(player, arenaModel, idx)
				else
					teleportPlayerToCFrame(player, CFrame.new(0, 100, 0))
				end
			end
		end

		task.wait(Config.MatchPreparationTime or 3)
		if not MatchService.Matches[matchId] then return end
		if matchData.activePlayers < Config.MatchMinPlayers then
			MatchService.EndMatch(matchId, "Not enough players after preparation")
			return
		end

		matchData.state = MatchStates.States.SELECTING_TARGET
		broadcastMatchState(matchData)
		print("[MatchService] Match " .. matchId .. " SelectingTarget")

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

		local randomIndex = math.random(1, #aliveUserIds)
		local targetUserId = aliveUserIds[randomIndex]
		matchData.targetUserId = targetUserId

		for userId, _ in pairs(matchData.players) do
			if userId == targetUserId then
				matchData.roles[userId] = "Target"
			else
				matchData.roles[userId] = "PotentialPuncher"
			end
			broadcastRoleAssigned(matchData, userId, matchData.roles[userId])
		end

		print(string.format("[MatchService] Match %s Target selected: %d, %d PotentialPunchers", matchId, targetUserId, #aliveUserIds - 1))

		if arenaModel then
			for _, player in ipairs(matchData.playerInstances) do
				if player and player.Parent then
					if player.UserId == targetUserId then
						teleportToTargetStand(player, arenaModel)
					else
						local idx = 1
						for i, p in ipairs(matchData.playerInstances) do
							if p.UserId == player.UserId then idx = i break end
						end
						teleportToArenaSpawn(player, arenaModel, idx)
					end
				end
			end
		end

		-- Start punch selection window (shared with the turn system: fresh timer + attempt-guarded loop)
		startPunchSelectionWindow(matchData)
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

	-- Cleanup puncher enforce connection
	if matchData.puncherEnforceConn then
		matchData.puncherEnforceConn:Disconnect()
		matchData.puncherEnforceConn = nil
	end

	-- Cleanup active power gauge (timeout loop exits via Matches[matchId] check + resolved flag)
	cancelPowerGauge(matchData, "Match ended: " .. reason)

	-- Cleanup pending punch sequence + damage (clients also clean their visual effects on MatchEnd)
	matchData.sequenceCancelled = true

	-- Cleanup guessing phase (countdown loop exits via Matches[matchId] + attempt guards)
	matchData.guessPhaseActive = false
	matchData.guessAttempt = (matchData.guessAttempt or 0) + 1
	matchData.turnAttempt = (matchData.turnAttempt or 0) + 1

	matchData.state = MatchStates.States.FINISHED
	broadcastMatchState(matchData)
	broadcastMatchEnd(matchData, reason)

	for _, player in pairs(matchData.playerInstances) do
		if player and player.Parent then
			teleportToLobby(player)
			MatchService.PlayersInMatch[player.UserId] = nil
		end
	end

	if MatchService.ArenasInUse[matchData.arenaName] == matchId then
		MatchService.ArenasInUse[matchData.arenaName] = nil
	end

	local queueServiceMod = ServerScriptService:FindFirstChild("Services") and ServerScriptService.Services:FindFirstChild("QueueService")
	if queueServiceMod then
		local ok, QueueService = pcall(require, queueServiceMod)
		if ok and QueueService and QueueService.ReleaseSlot then
			QueueService.ReleaseSlot(matchData.slotId)
		end
	end

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

	-- Handle Puncher disconnecting
	if matchData.puncherUserId == userId then
		print("[MatchService] Puncher disconnected from match " .. matchId)
		if matchData.puncherEnforceConn then
			matchData.puncherEnforceConn:Disconnect()
			matchData.puncherEnforceConn = nil
		end
		-- POWER GAUGE: cancel active gauge and discard stored result (no puncher, no damage)
		cancelPowerGauge(matchData, "Puncher disconnected")
		matchData.powerGaugeResult = nil
		-- PUNCH SEQUENCE: cancel pending sequence/damage if puncher leaves mid-animation
		matchData.sequenceCancelled = true
		matchData.puncherUserId = nil
		matchData.puncherSelectedTick = nil
		matchData.puncherPreparationEndTick = nil
		matchData.puncherPosition = nil
		matchData.puncherLocked = false
		-- GUESSING: puncher gone -> the guess phase loses its answer; cancel it (no reveal)
		matchData.guessPhaseActive = false
		matchData.guessAttempt = (matchData.guessAttempt or 0) + 1 -- kill stale guess countdown loop
		-- For remaining players, if in WaitingForPuncher, Punching (prep), PowerGauge or Guessing,
		-- go back to WaitingForPuncher to allow a new punch selection
		if matchData.state == MatchStates.States.PUNCHING
			or matchData.state == MatchStates.States.POWER_GAUGE
			or matchData.state == MatchStates.States.GUESSING
			or matchData.state == MatchStates.States.WAITING_FOR_PUNCHER then
			resetTurnForNewAttempt(matchData) -- full turn reset + stale-event guard
			startPunchSelectionWindow(matchData)
			print("[MatchService] Puncher left, returning to WaitingForPuncher for match " .. matchId)
		end
	end

	matchData.players[userId] = nil
	for i, plr in ipairs(matchData.playerInstances) do
		if plr.UserId == userId then
			table.remove(matchData.playerInstances, i)
			break
		end
	end
	matchData.roles[userId] = nil
	MatchService.PlayersInMatch[userId] = nil
	if matchData.punchRequests then matchData.punchRequests[userId] = nil end
	if matchData.punchRequestCounts then matchData.punchRequestCounts[userId] = nil end

	matchData.activePlayers = 0
	for _ in pairs(matchData.players) do
		matchData.activePlayers += 1
	end

	broadcastMatchState(matchData)

	-- GUESSING: a choice left -> refresh the Target's eligible list/countdown UI
	if matchData.state == MatchStates.States.GUESSING and matchData.guessPhaseActive and not matchData.guessLocked then
		broadcastGuessOpen(matchData)
	end

	if matchData.activePlayers < (Config.MatchMinPlayers or 2) then
		MatchService.EndMatch(matchId, "Not enough players - " .. reason)
	else
		if matchData.targetUserId == userId then
			print("[MatchService] Target left, selecting new target for match " .. matchId)
			local remaining = {}
			for uid, _ in pairs(matchData.players) do
				table.insert(remaining, uid)
			end
			if #remaining >= 1 then
				local newTarget = remaining[math.random(1, #remaining)]
				matchData.targetUserId = newTarget
				-- If there was a Puncher, clear Puncher because Target changed
				if matchData.puncherUserId then
					if matchData.puncherEnforceConn then
						matchData.puncherEnforceConn:Disconnect()
						matchData.puncherEnforceConn = nil
					end
					-- POWER GAUGE: cancel active gauge and discard result (Target changed)
					cancelPowerGauge(matchData, "Target left, Puncher cleared")
					matchData.powerGaugeResult = nil
					local oldPuncherId = matchData.puncherUserId
					matchData.puncherUserId = nil
					matchData.puncherPosition = nil
					matchData.puncherLocked = false
					if matchData.players[oldPuncherId] then
						matchData.roles[oldPuncherId] = "PotentialPuncher"
						broadcastRoleAssigned(matchData, oldPuncherId, "PotentialPuncher")
					end
				end
				for uid, _ in pairs(matchData.players) do
					if uid == newTarget then
						matchData.roles[uid] = "Target"
					else
						if matchData.roles[uid] ~= "Puncher" then
							matchData.roles[uid] = "PotentialPuncher"
						end
					end
					broadcastRoleAssigned(matchData, uid, matchData.roles[uid])
				end
				local newTargetPlayer = matchData.players[newTarget]
				if newTargetPlayer and matchData.arenaModel then
					teleportToTargetStand(newTargetPlayer, matchData.arenaModel)
				end
				-- NEW TARGET: reset match health for the new Target, clear knockout/damage/sequence state
				matchData.sequenceCancelled = true -- cancel any pending punch sequence from the old round
				matchData.targetHealth = Config.StartingHealth or 100
				matchData.targetKnockedOut = false
				matchData.damageApplied = false
				matchData.sequenceFired = false
				matchData.powerGaugeResult = nil
				-- GUESSING: Target left mid-guess -> cancel guess phase, guard stale loops
				matchData.guessPhaseActive = false
				matchData.guessAttempt = (matchData.guessAttempt or 0) + 1
				matchData.turnAttempt = (matchData.turnAttempt or 0) + 1
				broadcastTargetHealth(matchData, 0, "Reset")
				-- Reset to WaitingForPuncher (fresh attempt-guarded selection window)
				startPunchSelectionWindow(matchData)
			end
		end
	end
end

function MatchService.Init()
	print("[MatchService] Initializing with Puncher selection phase...")

	local Shared = ReplicatedStorage:WaitForChild("Shared", 10)
	if not Shared then
		error("[MatchService] Missing ReplicatedStorage.Shared")
	end

	Config = require(Shared:WaitForChild("Config"))
	MatchStates = require(Shared:WaitForChild("MatchStates"))
	Roles = require(Shared:WaitForChild("Roles"))
	PowerZones = require(Shared:WaitForChild("PowerZones"))
	Results = require(Shared:WaitForChild("Results"))

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
			"RE_PunchRequest",
			"RE_PunchRejected",
			"RE_PuncherSelected",
			"RE_PuncherPreparation",
			"RE_PowerGaugeOpen",
			"RE_PowerGaugeStopRequest",
			"RE_PowerGaugeRejected",
			"RE_PowerGaugeResult",
			"RE_PunchSequence",
			"RE_TargetHealthUpdate",
			"RE_GuessOpen",
			"RE_GuessRequest",
			"RE_GuessRejected",
			"RE_GuessResult",
		})
	end

	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if remotesFolder then
		remotes.MatchStart = remotesFolder:FindFirstChild("RE_MatchStart")
		remotes.StateUpdate = remotesFolder:FindFirstChild("RE_MatchStateUpdate")
		remotes.MatchEnd = remotesFolder:FindFirstChild("RE_MatchEnd")
		remotes.RoleAssigned = remotesFolder:FindFirstChild("RE_RoleAssigned")
		remotes.TargetSelected = remotesFolder:FindFirstChild("RE_TargetSelected")
		remotes.PunchRequest = remotesFolder:FindFirstChild("RE_PunchRequest")
		remotes.PunchRejected = remotesFolder:FindFirstChild("RE_PunchRejected")
		remotes.PuncherSelected = remotesFolder:FindFirstChild("RE_PuncherSelected")
		remotes.PuncherPreparation = remotesFolder:FindFirstChild("RE_PuncherPreparation")
		remotes.PowerGaugeOpen = remotesFolder:FindFirstChild("RE_PowerGaugeOpen")
		remotes.PowerGaugeStopRequest = remotesFolder:FindFirstChild("RE_PowerGaugeStopRequest")
		remotes.PowerGaugeRejected = remotesFolder:FindFirstChild("RE_PowerGaugeRejected")
		remotes.PowerGaugeResult = remotesFolder:FindFirstChild("RE_PowerGaugeResult")
		remotes.PunchSequence = remotesFolder:FindFirstChild("RE_PunchSequence")
		remotes.TargetHealthUpdate = remotesFolder:FindFirstChild("RE_TargetHealthUpdate")
		remotes.GuessOpen = remotesFolder:FindFirstChild("RE_GuessOpen")
		remotes.GuessRequest = remotesFolder:FindFirstChild("RE_GuessRequest")
		remotes.GuessRejected = remotesFolder:FindFirstChild("RE_GuessRejected")
		remotes.GuessResult = remotesFolder:FindFirstChild("RE_GuessResult")
	end

	-- Handle PunchRequest from clients: client must send only Punch request, not winner/timestamp/damage/power/role
	if remotes.PunchRequest then
		remotes.PunchRequest.OnServerEvent:Connect(function(player: Player, matchId: any)
			-- Validate matchId type (client may send matchId or nothing)
			local requestedMatchId: string? = nil
			if typeof(matchId) == "string" then
				requestedMatchId = matchId
			else
				-- If client sends no matchId, use server's PlayersInMatch
				requestedMatchId = MatchService.PlayersInMatch[player.UserId]
			end
			if not requestedMatchId then
				broadcastPunchRejected(player, "", "Not in a match")
				return
			end
			-- Server validates everything, client only sends request
			MatchService.TryBecomePuncher(player, requestedMatchId)
		end)
		print("[MatchService] Listening to RE_PunchRequest")
	end

	-- Handle PowerGaugeStopRequest (gauge LOCK request): client must send ONLY matchId.
	-- Any extra args (power value, zone claim, timestamp) are IGNORED - the server
	-- calculates the zone from the SERVER clock, so a client can never claim Perfect.
	if remotes.PowerGaugeStopRequest then
		remotes.PowerGaugeStopRequest.OnServerEvent:Connect(function(player: Player, matchId: any, ...)
			MatchService.TryLockPowerGauge(player, matchId, ...) -- extra args ignored inside
		end)
		print("[MatchService] Listening to RE_PowerGaugeStopRequest (gauge lock)")
	end

	-- Handle GuessRequest: only the TARGET may submit, ONLY during Guessing, ONE guess allowed.
	-- Server validates everything and evaluates the guess (client never decides the result).
	if remotes.GuessRequest then
		remotes.GuessRequest.OnServerEvent:Connect(function(player: Player, matchId: any, guessedUserId: any)
			MatchService.TrySubmitGuess(player, matchId, guessedUserId)
		end)
		print("[MatchService] Listening to RE_GuessRequest (Target guess submission)")
	end

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
					if player.UserId == matchData.targetUserId then
						teleportToTargetStand(player, matchData.arenaModel)
					elseif player.UserId == matchData.puncherUserId then
						-- Puncher respawn: teleport back behind Target
						local targetPlayer = matchData.players[matchData.targetUserId]
						teleportPuncherBehindTarget(player, targetPlayer, matchData.arenaModel)
						-- Re-store position
						local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
						if hrp then
							matchData.puncherPosition = hrp.CFrame
						end
					else
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

	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function(character)
			task.wait(1)
			local matchId = MatchService.PlayersInMatch[player.UserId]
			if matchId then
				local matchData = MatchService.Matches[matchId]
				if matchData and matchData.arenaModel then
					if player.UserId == matchData.targetUserId then
						teleportToTargetStand(player, matchData.arenaModel)
					elseif player.UserId == matchData.puncherUserId then
						local targetPlayer = matchData.players[matchData.targetUserId]
						teleportPuncherBehindTarget(player, targetPlayer, matchData.arenaModel)
						local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
						if hrp then
							matchData.puncherPosition = hrp.CFrame
						end
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

	print("[MatchService] Initialized - Puncher selection + power gauge + punch sequence + health + guessing/turn system ready")
	print("[MatchService] States: Preparing, SelectingTarget, WaitingForPuncher, Punching (prep), PowerGauge, Guessing (one guess, reveal on resolve), KnockedOut (paused, marked), Eliminated, Finished")
	print("[MatchService] Turn rules: CorrectGuess -> Puncher becomes next Target | WrongGuess/GuessTimeout -> same Target, new Punch selection")
	print("[MatchService] Damage: Miss 0 / Weak " .. tostring(Config.Damage and Config.Damage.Weak) .. " / Normal " .. tostring(Config.Damage and Config.Damage.Normal) .. " / Strong " .. tostring(Config.Damage and Config.Damage.Strong) .. " / Perfect " .. tostring(Config.Damage and Config.Damage.Perfect) .. " (instant KO)")
end

return MatchService
