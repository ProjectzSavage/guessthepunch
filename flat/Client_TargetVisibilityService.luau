--!nonstrict
-- TargetVisibilityService.luau
-- Purpose: Client-only visibility presentation for Target role
-- Implements ONLY:
-- - Make Puncher invisible to Target (anti-cheat backup to camera restriction)
-- - Hide players behind Target locally (do not rely on camera restriction alone)
-- - Keep camera behavior normal for other players
-- - Do not reveal hidden Puncher before official reveal
-- - Restore visibility when no longer Target
-- - Handle reset, death, disconnect, match completion safely
-- Server controls Target role and does NOT send Puncher identity to Target
-- Client controls visibility presentation only (LocalTransparencyModifier, local only)
-- Does NOT implement: Punch selection, power, damage, guessing, knockout, scoring, GUI
-- Roblox Studio Destination: StarterPlayer > StarterPlayerScripts > GuessThePuncherClient > Services > TargetVisibilityService (ModuleScript)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TargetVisibilityService = {}

local Config
local isTarget = false
local currentMatchPlayers = {} -- [userId] = Player
local heartbeatConn = nil
local originalTransparencies = {} -- [character] = { [part] = original LocalTransparencyModifier }
local hiddenCharacters = {} -- [character] = true if currently hidden

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
		TargetHideBehindPlayers = true,
		TargetBehindDotThreshold = -0.1,
		TargetVisibilityCheckInterval = 0.15,
		PuncherInvisibleToTarget = true,
	}
end

local function getLocalPlayer(): Player?
	return Players.LocalPlayer
end

local function getHRP(character: Model): BasePart?
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function setCharacterInvisible(character: Model, invisible: boolean)
	if not character then return end
	if invisible and hiddenCharacters[character] then return end
	if not invisible and not hiddenCharacters[character] then return end

	for _, desc in ipairs(character:GetDescendants()) do
		if desc:IsA("BasePart") then
			if invisible then
				-- Save original if not saved
				if not originalTransparencies[character] then
					originalTransparencies[character] = {}
				end
				if originalTransparencies[character][desc] == nil then
					originalTransparencies[character][desc] = desc.LocalTransparencyModifier
				end
				desc.LocalTransparencyModifier = 1 -- invisible only for local client
			else
				-- Restore
				if originalTransparencies[character] and originalTransparencies[character][desc] ~= nil then
					desc.LocalTransparencyModifier = originalTransparencies[character][desc]
				else
					desc.LocalTransparencyModifier = 0
				end
			end
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			if invisible then
				if not originalTransparencies[character] then originalTransparencies[character] = {} end
				if originalTransparencies[character][desc] == nil then
					originalTransparencies[character][desc] = desc.Transparency
				end
				desc.Transparency = 1
			else
				if originalTransparencies[character] and originalTransparencies[character][desc] ~= nil then
					desc.Transparency = originalTransparencies[character][desc]
				else
					desc.Transparency = 0
				end
			end
		elseif desc:IsA("BillboardGui") or desc:IsA("SurfaceGui") then
			-- Hide nameplates, etc.
			if invisible then
				if not originalTransparencies[character] then originalTransparencies[character] = {} end
				if originalTransparencies[character][desc] == nil then
					originalTransparencies[character][desc] = desc.Enabled
				end
				desc.Enabled = false
			else
				if originalTransparencies[character] and originalTransparencies[character][desc] ~= nil then
					desc.Enabled = originalTransparencies[character][desc]
				else
					desc.Enabled = true
				end
			end
		end
	end

	if invisible then
		hiddenCharacters[character] = true
	else
		hiddenCharacters[character] = nil
	end
end

local function restoreAllVisibility()
	for character, _ in pairs(hiddenCharacters) do
		if character and character.Parent then
			setCharacterInvisible(character, false)
		end
	end
	hiddenCharacters = {}
	originalTransparencies = {}
end

local function isBehind(targetHRP: BasePart, otherHRP: BasePart, dotThreshold: number): boolean
	-- Compute vector from target to other, dot with target forward
	local toOther = (otherHRP.Position - targetHRP.Position)
	if toOther.Magnitude < 1 then return false end
	toOther = toOther.Unit
	local forward = targetHRP.CFrame.LookVector
	local dot = forward:Dot(toOther)
	return dot < dotThreshold
end

local function updateVisibility()
	if not isTarget then
		restoreAllVisibility()
		return
	end

	local localPlayer = getLocalPlayer()
	if not localPlayer then return end
	local localChar = localPlayer.Character
	if not localChar then return end
	local localHRP = getHRP(localChar)
	if not localHRP then return end

	local cfg = getConfig()
	local dotThreshold = cfg.TargetBehindDotThreshold or -0.1
	local hideBehind = cfg.TargetHideBehindPlayers
	if hideBehind == nil then hideBehind = true end

	for userId, player in pairs(currentMatchPlayers) do
		if player.UserId == localPlayer.UserId then continue end
		local char = player.Character
		if not char then continue end
		local otherHRP = getHRP(char)
		if not otherHRP then continue end

		-- Anti-cheat: Do not rely on camera restriction alone
		-- For Target, hide players behind Target locally
		-- Future: If role is Puncher, hide always (but server does NOT send Puncher identity to Target, so we hide behind as proxy)
		-- Since server filters Puncher role from Target payload, we cannot know who is Puncher, so we hide all behind players
		-- This prevents Target from seeing Puncher sneaking behind, without revealing who is Puncher

		local shouldHide = false
		if hideBehind then
			shouldHide = isBehind(localHRP, otherHRP, dotThreshold)
		end

		-- If we ever receive Puncher role (should NOT happen for Target due to server filtering), hide always
		-- This is backup: if for some reason Target client knows who is Puncher, hide them
		-- But server must NOT send Puncher identity to Target, so this branch should not trigger for Target
		-- It's here for future non-Target visibility logic

		setCharacterInvisible(char, shouldHide)
	end
end

function TargetVisibilityService.SetIsTarget(newIsTarget: boolean, matchPlayers: { [number]: Player }?)
	if newIsTarget == isTarget and matchPlayers == nil then return end

	-- Update match players list if provided
	if matchPlayers then
		currentMatchPlayers = matchPlayers
	end

	if newIsTarget == isTarget then
		-- Just update visibility
		return
	end

	isTarget = newIsTarget

	if isTarget then
		print("[TargetVisibility] Becoming Target - enabling behind-player hiding (anti-cheat backup)")
		-- Start periodic check
		if heartbeatConn then heartbeatConn:Disconnect() end
		local lastCheck = 0
		heartbeatConn = RunService.Heartbeat:Connect(function(dt)
			lastCheck += dt
			local interval = getConfig().TargetVisibilityCheckInterval or 0.15
			if lastCheck >= interval then
				lastCheck = 0
				updateVisibility()
			end
		end)
	else
		print("[TargetVisibility] No longer Target - restoring visibility")
		if heartbeatConn then
			heartbeatConn:Disconnect()
			heartbeatConn = nil
		end
		restoreAllVisibility()
	end
end

function TargetVisibilityService.UpdateMatchPlayers(players: { [number]: Player } | {Player})
	-- Accept either map [userId]=Player or array of Players
	local map = {}
	if #players > 0 then
		-- Array
		for _, plr in ipairs(players :: any) do
			if typeof(plr) == "Instance" and plr:IsA("Player") then
				map[plr.UserId] = plr
			end
		end
	else
		-- Map
		map = players :: any
	end
	currentMatchPlayers = map
	if isTarget then
		updateVisibility()
	end
end

function TargetVisibilityService.Restore()
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
	restoreAllVisibility()
	isTarget = false
	currentMatchPlayers = {}
end

function TargetVisibilityService.HandleCharacterAdded(player: Player, character: Model)
	-- When other players respawn, re-apply visibility if we are Target
	if not isTarget then return end
	if player.UserId == getLocalPlayer().UserId then
		-- Local player respawn handled by camera service, but visibility also needs reset
		task.wait(0.3)
		updateVisibility()
	else
		-- Other player respawned, need to hide if behind
		task.wait(0.3)
		updateVisibility()
	end
end

function TargetVisibilityService.Init()
	print("[TargetVisibilityService] Initializing...")
	local localPlayer = getLocalPlayer()
	if not localPlayer then return end

	-- Listen to other players character added
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(char)
			TargetVisibilityService.HandleCharacterAdded(player, char)
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= localPlayer then
			player.CharacterAdded:Connect(function(char)
				TargetVisibilityService.HandleCharacterAdded(player, char)
			end)
		end
	end

	-- Local character added also triggers visibility update
	localPlayer.CharacterAdded:Connect(function(char)
		TargetVisibilityService.HandleCharacterAdded(localPlayer, char)
	end)

	print("[TargetVisibilityService] Initialized - waiting for Target role")
end

return TargetVisibilityService
