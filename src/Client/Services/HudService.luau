--!nonstrict
-- HudService.luau
-- Purpose: IN-MATCH HUD (presentation ONLY - server keeps all authority)
-- Implements ONLY:
-- - Role/State chip (top left) from filtered server payloads (via Main UpdateState)
-- - TARGET HEALTH BAR (top right) from RE_TargetHealthUpdate (matchId, targetUserId, health,
--   maxHealth, lastDamage, lastZone); fill ratio server-driven; "Reset" zone refills the bar
-- - Center prompt by state + LOCAL role:
--     WaitingForPuncher + PotentialPuncher -> "Press [F] to become the Puncher!"
--     WaitingForPuncher + Target           -> "Waiting for a Puncher..."
--     Punching + Puncher (prep countdown from RE_PuncherPreparation) -> "Get ready... 2.0s"
--     Punching + others                    -> "The Puncher is preparing..."
--     PowerGauge + Puncher                 -> "Press [E] to lock the gauge!"
--     PowerGauge + others                  -> "The Puncher is charging the punch..."
--     Guessing + Target                    -> "Pick who punched you!"
--     Guessing + others                    -> "The Target is guessing..."
--     KnockedOut                           -> "KNOCKED OUT!"
--     Spectator                            -> no prompt (SpectatorService has its own panel)
-- - Visible ONLY during a match; hidden automatically on match end / in lobby
-- The system GUIs (power gauge, guess panel, spectator panel, result banners, K.O. effects)
-- are handled by their own services; this HUD complements them.
-- Does NOT implement: gameplay, monetization, final polish, DataStores
-- Roblox Studio Destination: StarterPlayer > StarterPlayerScripts > GuessThePuncherClient > Services > HudService (ModuleScript)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudService = {}

local player = Players.LocalPlayer
local remotes = {}

local Config = nil
local currentMatchId: string? = nil
local currentRole: string? = nil
local currentState: string? = nil
local currentTargetUserId: number? = nil
local prepEndTime: number? = nil -- local render clock for prep countdown

local hudGui = nil
local roleChip = nil
local promptLabel = nil
local healthFrame = nil
local healthFill = nil
local healthLabel = nil

local function loadShared()
	if Config then return end
	local Shared = ReplicatedStorage:FindFirstChild("Shared")
	if Shared then
		local configMod = Shared:FindFirstChild("Config")
		if configMod then
			local ok, result = pcall(require, configMod)
			if ok then Config = result end
		end
	end
end

local function healthColor(ratio: number): Color3
	if ratio > 0.6 then
		return Color3.fromRGB(90, 220, 110)
	elseif ratio > 0.3 then
		return Color3.fromRGB(240, 200, 80)
	end
	return Color3.fromRGB(240, 80, 80)
end

local function destroyGui()
	if hudGui then
		hudGui:Destroy()
		hudGui = nil
		roleChip = nil
		promptLabel = nil
		healthFrame = nil
		healthFill = nil
		healthLabel = nil
	end
end

local function buildGui()
	loadShared()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end
	destroyGui()

	hudGui = Instance.new("ScreenGui")
	hudGui.Name = "MatchHud"
	hudGui.ResetOnSpawn = false
	hudGui.DisplayOrder = 45
	hudGui.Parent = playerGui

	-- Role/State chip (top left)
	roleChip = Instance.new("TextLabel")
	roleChip.Name = "RoleChip"
	roleChip.AnchorPoint = Vector2.new(0, 0)
	roleChip.Position = UDim2.fromScale(0.012, 0.02)
	roleChip.Size = UDim2.fromScale(0.2, 0.045)
	roleChip.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	roleChip.BackgroundTransparency = 0.25
	roleChip.BorderSizePixel = 0
	roleChip.TextScaled = true
	roleChip.Font = Enum.Font.GothamBold
	roleChip.TextColor3 = Color3.fromRGB(255, 255, 255)
	roleChip.Text = ""
	roleChip.Parent = hudGui

	-- Target health bar (top right)
	healthFrame = Instance.new("Frame")
	healthFrame.Name = "HealthBar"
	healthFrame.AnchorPoint = Vector2.new(1, 0)
	healthFrame.Position = UDim2.fromScale(0.988, 0.02)
	healthFrame.Size = UDim2.fromScale(0.24, 0.045)
	healthFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	healthFrame.BackgroundTransparency = 0.2
	healthFrame.BorderSizePixel = 0
	healthFrame.Parent = hudGui

	healthFill = Instance.new("Frame")
	healthFill.Name = "Fill"
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BackgroundColor3 = Color3.fromRGB(90, 220, 110)
	healthFill.BorderSizePixel = 0
	healthFill.Parent = healthFrame

	healthLabel = Instance.new("TextLabel")
	healthLabel.Name = "Label"
	healthLabel.Size = UDim2.fromScale(1, 1)
	healthLabel.BackgroundTransparency = 1
	healthLabel.TextScaled = true
	healthLabel.Font = Enum.Font.GothamBold
	healthLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	healthLabel.Text = "Target: 100/100"
	healthLabel.Parent = healthFrame

	-- Center prompt (below middle so it never covers the gauge panel)
	promptLabel = Instance.new("TextLabel")
	promptLabel.Name = "Prompt"
	promptLabel.AnchorPoint = Vector2.new(0.5, 0)
	promptLabel.Position = UDim2.fromScale(0.5, 0.68)
	promptLabel.Size = UDim2.fromScale(0.5, 0.05)
	promptLabel.BackgroundTransparency = 1
	promptLabel.TextScaled = true
	promptLabel.Font = Enum.Font.GothamBold
	promptLabel.TextColor3 = Color3.fromRGB(255, 235, 150)
	promptLabel.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
	promptLabel.TextStrokeTransparency = 0.2
	promptLabel.Text = ""
	promptLabel.Parent = hudGui

	print("[Hud] Match HUD opened")
end

local function promptForState(): string
	if currentRole == "Spectator" then
		return "" -- SpectatorService panel handles spectator text
	end
	if currentState == "WaitingForPuncher" then
		if currentRole == "PotentialPuncher" then
			return "Press [F] to become the Puncher!"
		elseif currentRole == "Target" then
			return "Waiting for a Puncher..."
		end
		return "Choosing a Puncher..."
	elseif currentState == "Punching" then
		if currentRole == "Puncher" then
			return "Get ready..."
		end
		return "The Puncher is preparing..."
	elseif currentState == "PowerGauge" then
		if currentRole == "Puncher" then
			return "Press [E] to lock the gauge!"
		end
		return "The Puncher is charging the punch..."
	elseif currentState == "Guessing" then
		if currentRole == "Target" then
			return "Pick who punched you!"
		end
		return "The Target is guessing..."
	elseif currentState == "KnockedOut" then
		return "KNOCKED OUT!"
	elseif currentState == "Preparing" or currentState == "SelectingTarget" then
		return "Match starting..."
	elseif currentState == "Finished" then
		return "Match over!"
	end
	return ""
end

local function refresh()
	if not hudGui then return end
	if roleChip then
		local roleText = currentRole or "-"
		roleChip.Text = string.format("%s  |  %s", roleText, currentState or "-")
		if roleText == "Target" then
			roleChip.TextColor3 = Color3.fromRGB(255, 170, 120)
		elseif roleText == "Puncher" then
			roleChip.TextColor3 = Color3.fromRGB(140, 220, 255)
		elseif roleText == "Spectator" then
			roleChip.TextColor3 = Color3.fromRGB(180, 180, 200)
		else
			roleChip.TextColor3 = Color3.fromRGB(255, 255, 255)
		end
	end
	if promptLabel then
		promptLabel.Text = promptForState()
	end
end

-- Health bar updates come ONLY from the server (RE_TargetHealthUpdate)
local function onTargetHealth(matchId: string, targetUserId: number, health: number, maxHealth: number, lastDamage: number, lastZone: string)
	if currentMatchId and matchId ~= currentMatchId then return end
	currentTargetUserId = targetUserId
	if not hudGui or not healthFill or not healthLabel then return end
	local h = math.max(0, health or 0)
	local m = math.max(1, maxHealth or 100)
	local ratio = math.clamp(h / m, 0, 1)
	healthFill.Size = UDim2.fromScale(ratio, 1)
	healthFill.BackgroundColor3 = healthColor(ratio)
	healthLabel.Text = string.format("Target: %d/%d", h, m)
	if lastZone == "Reset" then
		print("[Hud] Target health RESET (new Target / new round)")
	end
end

-- Prep countdown display (RE_PuncherPreparation: Target receives 0, spectators nothing)
local function onPreparation(matchId: string, timeLeft: number)
	if currentMatchId and matchId ~= currentMatchId then return end
	if currentState ~= "Punching" then return end
	if currentRole == "Target" then return end -- server sends 0 to the Target
	if promptLabel and currentRole == "Puncher" then
		promptLabel.Text = string.format("Get ready... %.1fs", math.max(0, timeLeft or 0))
	end
end

local function setHudVisible(visible: boolean)
	loadShared()
	if not (Config and Config.UIEnabled and Config.ShowMatchHud) then
		visible = false
	end
	if visible then
		if not hudGui then
			buildGui()
			refresh()
		end
	elseif hudGui then
		destroyGui()
	end
end

function HudService.UpdateState(matchId: string?, role: string?, state: string?)
	local wasNil = (currentMatchId == nil)
	if matchId ~= nil then currentMatchId = matchId end
	if role ~= nil then currentRole = role end
	if state ~= nil then currentState = state end
	-- HUD shows ONLY during a match
	setHudVisible(currentMatchId ~= nil)
	if wasNil and currentMatchId ~= nil then
		-- fresh match: default the health bar until the first server update arrives
		onTargetHealth(currentMatchId or "", currentTargetUserId or 0, (Config and Config.StartingHealth) or 100, (Config and Config.StartingHealth) or 100, 0, "Reset")
	end
	refresh()
end

function HudService.HandleMatchEnd()
	currentMatchId = nil
	currentRole = nil
	currentState = nil
	currentTargetUserId = nil
	prepEndTime = nil
	setHudVisible(false)
end

function HudService.Init()
	loadShared()
	print("[HudService] Initializing...")

	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotesFolder then
		warn("[HudService] Missing Remotes folder")
		return
	end

	remotes.TargetHealthUpdate = remotesFolder:FindFirstChild("RE_TargetHealthUpdate")
	remotes.PuncherPreparation = remotesFolder:FindFirstChild("RE_PuncherPreparation")

	if remotes.TargetHealthUpdate then
		remotes.TargetHealthUpdate.OnClientEvent:Connect(function(matchId, targetUserId, health, maxHealth, lastDamage, lastZone)
			onTargetHealth(matchId, targetUserId, health, maxHealth, lastDamage, lastZone)
		end)
	else
		warn("[HudService] RE_TargetHealthUpdate not found - health bar disabled")
	end

	if remotes.PuncherPreparation then
		remotes.PuncherPreparation.OnClientEvent:Connect(function(matchId, timeLeft)
			onPreparation(matchId, timeLeft)
		end)
	end

	print("[HudService] Ready - role/state chip, Target health bar, state prompts")
end

return HudService
