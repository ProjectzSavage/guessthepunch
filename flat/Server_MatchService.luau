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
--   stores result for future damage system, timeout -> Miss, handles disconnect
-- - Handle duplicate requests, spam, rate limits, disconnects
-- - End safely if <2 active or Target invalid
-- Does NOT implement: damage application, guessing, knockout, scoring, monetization, final animations, final GUI
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
local RemoteService

local remotes = {}

local startPowerGauge -- forward declaration, defined in POWER GAUGE section below

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
		powerGaugeResult = nil, -- stored for future damage system: {zone, position, lockedTick, serverTime, timedOut, puncherUserId} - SERVER-INTERNAL, never broadcast before damage
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

		matchData.state = MatchStates.States.WAITING_FOR_PUNCHER
		matchData.punchSelectionEndTick = tick() + (Config.PunchSelectionDuration or 15)
		broadcastMatchState(matchData)
		print("[MatchService] Match " .. matchId .. " now WaitingForPuncher - waiting for first valid Punch request")

		-- Start punch selection timeout loop
		task.spawn(function()
			while MatchService.Matches[matchId] and matchData.state == MatchStates.States.WAITING_FOR_PUNCHER do
				task.wait(1)
				if not MatchService.Matches[matchId] then return end
				if matchData.puncherUserId then
					-- Puncher already selected, break
					break
				end
				local now = tick()
				if matchData.punchSelectionEndTick and now >= matchData.punchSelectionEndTick then
					if not matchData.puncherUserId then
						print("[MatchService] Punch selection timeout for match " .. matchId .. " - no Puncher selected")
						-- For this phase, end match if no Puncher, or could select random. Ending safely.
						MatchService.EndMatch(matchId, "No Puncher selected in time")
						break
					end
				end
				-- End safely if Target invalid
				if not matchData.targetUserId or not matchData.players[matchData.targetUserId] then
					print("[MatchService] Target invalid during WaitingForPuncher for match " .. matchId)
					MatchService.EndMatch(matchId, "Target invalid during puncher selection")
					break
				end
			end
		end)
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
		matchData.puncherUserId = nil
		matchData.puncherSelectedTick = nil
		matchData.puncherPreparationEndTick = nil
		matchData.puncherPosition = nil
		matchData.puncherLocked = false
		-- For remaining players, if in WaitingForPuncher, Punching (prep) or PowerGauge,
		-- go back to WaitingForPuncher to allow new selection
		if matchData.state == MatchStates.States.PUNCHING
			or matchData.state == MatchStates.States.POWER_GAUGE
			or matchData.state == MatchStates.States.WAITING_FOR_PUNCHER then
			matchData.state = MatchStates.States.WAITING_FOR_PUNCHER
			matchData.punchSelectionEndTick = tick() + (Config.PunchSelectionDuration or 15)
			broadcastMatchState(matchData)
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
				-- Reset to WaitingForPuncher
				matchData.state = MatchStates.States.WAITING_FOR_PUNCHER
				matchData.punchSelectionEndTick = tick() + (Config.PunchSelectionDuration or 15)
				broadcastMatchState(matchData)
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

	print("[MatchService] Initialized - Puncher selection + server-authoritative power gauge ready")
	print("[MatchService] States: Preparing, SelectingTarget, WaitingForPuncher, Punching (prep), PowerGauge (holds after lock), Guessing (future), Resolving (future), Eliminated, Finished")
end

return MatchService
