--!nonstrict
-- PuncherSelectionService.luau
-- Purpose: Client-only Punch request presentation for Puncher selection phase
-- Implements ONLY:
-- - Every non-target active player may request Punch via RE_PunchRequest
-- - Client sends only Punch request, not claimed winner/timestamp/damage/power/role
-- - Handles first valid server-accepted becomes Puncher, others rejected
-- - Other Punch actions become unavailable after selection
-- - Handles duplicate requests and spam (client-side cooldown)
-- - Handles Puncher disconnect, Target invalid (via MatchEnd)
-- Server validates: identity, match, role, state, alive, eligibility, duplicate, rate limits
-- Does NOT implement: power gauge, damage, guessing, knockout, scoring, monetization, final GUI
-- Roblox Studio Destination: StarterPlayer > StarterPlayerScripts > GuessThePuncherClient > Services > PuncherSelectionService (ModuleScript)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local PuncherSelectionService = {}

local Config
local currentMatchId: string? = nil
local currentRole: string? = nil
local currentState: string? = nil
local isPuncherSelected = false
local lastRequestTick = 0
local punchRequestConn = nil

local remotes = {}

local function getConfig()
	if Config then return Config end
	local Shared = ReplicatedStorage:FindFirstChild("Shared")
	if Shared then
		local ConfigMod = Shared:FindFirstChild("Config")
		if ConfigMod then
			Config = require(ConfigMod)
			return Config
		end
	end
	return {
		PunchRequestCooldown = 0.5,
	}
end

local function getLocalPlayer(): Player?
	return Players.LocalPlayer
end

local function canRequestPunch(): (boolean, string)
	if not currentMatchId then
		return false, "Not in match"
	end
	if not currentRole then
		return false, "No role"
	end
	if currentRole == "Target" then
		return false, "Target not eligible"
	end
	if currentRole == "Puncher" then
		return false, "Already Puncher"
	end
	if currentRole ~= "PotentialPuncher" then
		return false, "Not eligible role: " .. tostring(currentRole)
	end
	if currentState ~= "WaitingForPuncher" then
		return false, "Wrong state: " .. tostring(currentState)
	end
	if isPuncherSelected then
		return false, "Puncher already selected"
	end
	local now = tick()
	local cooldown = getConfig().PunchRequestCooldown or 0.5
	if now - lastRequestTick < cooldown then
		return false, "Rate limited"
	end
	return true, "Can request"
end

function PuncherSelectionService.RequestPunch()
	local ok, reason = canRequestPunch()
	if not ok then
		print("[PuncherSelection] Cannot request punch: " .. reason)
		return false
	end

	local re = remotes.PunchRequest
	if not re then
		warn("[PuncherSelection] RE_PunchRequest not found")
		return false
	end

	-- Client must send only Punch request, not claimed winner/timestamp/damage/power/role
	-- Send only matchId (server validates everything)
	if currentMatchId then
		re:FireServer(currentMatchId)
		lastRequestTick = tick()
		print("[PuncherSelection] Punch request sent for match " .. currentMatchId)
		return true
	else
		re:FireServer()
		lastRequestTick = tick()
		print("[PuncherSelection] Punch request sent (no matchId)")
		return true
	end
end

function PuncherSelectionService.UpdateState(matchId: string?, role: string?, state: string?, puncherSelected: boolean?)
	if matchId then currentMatchId = matchId end
	if role then currentRole = role end
	if state then currentState = state end
	if puncherSelected ~= nil then isPuncherSelected = puncherSelected end

	-- If Puncher already selected, other Punch actions become unavailable
	if isPuncherSelected then
		-- Disable further requests (client-side)
		-- Could disable GUI button, etc.
	end
end

function PuncherSelectionService.HandlePuncherSelected(matchId: string, puncherUserId: number?)
	-- Server fires filtered: Target gets nil, others get puncherUserId
	if matchId ~= currentMatchId then return end
	isPuncherSelected = true
	if puncherUserId then
		if puncherUserId == getLocalPlayer().UserId then
			print("[PuncherSelection] You are now Puncher! Moved behind Target, preparation period started")
			currentRole = "Puncher"
		else
			print("[PuncherSelection] Puncher selected: " .. tostring(puncherUserId) .. " - other punch actions unavailable")
		end
	else
		-- Target receives nil (hidden)
		print("[PuncherSelection] Puncher selected (hidden from Target) - other punch actions unavailable")
	end
end

function PuncherSelectionService.HandlePunchRejected(matchId: string, reason: string)
	if currentMatchId and matchId ~= currentMatchId and matchId ~= "" then return end
	print("[PuncherSelection] Punch rejected: " .. reason)
	-- Could show UI feedback
end

function PuncherSelectionService.HandleMatchEnd()
	currentMatchId = nil
	currentRole = nil
	currentState = nil
	isPuncherSelected = false
	lastRequestTick = 0
	print("[PuncherSelection] Match ended, reset")
end

function PuncherSelectionService.Init()
	print("[PuncherSelectionService] Initializing...")

	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotesFolder then
		warn("[PuncherSelectionService] Missing Remotes folder")
		return
	end

	remotes.PunchRequest = remotesFolder:WaitForChild("RE_PunchRequest", 10)
	remotes.PunchRejected = remotesFolder:FindFirstChild("RE_PunchRejected")
	remotes.PuncherSelected = remotesFolder:FindFirstChild("RE_PuncherSelected")
	remotes.PuncherPreparation = remotesFolder:FindFirstChild("RE_PuncherPreparation")
	remotes.StateUpdate = remotesFolder:FindFirstChild("RE_MatchStateUpdate")
	remotes.RoleAssigned = remotesFolder:FindFirstChild("RE_RoleAssigned")
	remotes.MatchEnd = remotesFolder:FindFirstChild("RE_MatchEnd")

	if remotes.PunchRejected then
		remotes.PunchRejected.OnClientEvent:Connect(function(matchId, reason)
			PuncherSelectionService.HandlePunchRejected(matchId, reason)
		end)
	end

	if remotes.PuncherSelected then
		remotes.PuncherSelected.OnClientEvent:Connect(function(matchId, puncherUserId)
			PuncherSelectionService.HandlePuncherSelected(matchId, puncherUserId)
		end)
	end

	if remotes.PuncherPreparation then
		remotes.PuncherPreparation.OnClientEvent:Connect(function(matchId, timeLeft)
			if matchId == currentMatchId then
				print(string.format("[PuncherSelection] Preparation time left: %.1f", timeLeft))
			end
		end)
	end

	-- Bind input for testing: Press F to request punch (only when PotentialPuncher in WaitingForPuncher)
	-- This is for testing without GUI, client sends only Punch request
	if UserInputService then
		UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then return end
			if input.KeyCode == Enum.KeyCode.F then
				PuncherSelectionService.RequestPunch()
			end
		end)
		print("[PuncherSelectionService] Press F to request Punch (when PotentialPuncher in WaitingForPuncher)")
	end

	print("[PuncherSelectionService] Initialized - waiting for WaitingForPuncher state")
end

return PuncherSelectionService
