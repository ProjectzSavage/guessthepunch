--!nonstrict
-- MatchResultService.luau
-- Purpose: MATCH RESULT presentation ONLY (server confirms the winner)
-- Implements ONLY:
-- - RE_MatchResult (Server -> ALL): (matchId, matchResult, winnerUserId, reason)
--   matchResult "Winner" (Results.MatchResults.WINNER) -> winner sees "VICTORY!" + confetti on their
--   character (code-created placeholder presentation, no asset IDs); everyone else sees
--   "WINNER: <name>" + "DEFEAT / thanks for playing" participation result
--   matchResult "Cancelled" -> neutral "Match ended" message for everyone
-- - Display duration covers the server's Config.LobbyReturnDelay before the lobby teleport
-- - Cleans up on match end / respawn (banners are Debris-managed)
-- Does NOT implement: winner rewards, coins, shops, cosmetics, monetization, DataStores, scoring, final GUI
-- Roblox Studio Destination: StarterPlayer > StarterPlayerScripts > GuessThePuncherClient > Services > MatchResultService (ModuleScript)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local MatchResultService = {}

local Config = nil
local Results = nil
local player = Players.LocalPlayer

local remotes = {}
local currentMatchId: string? = nil

local function loadShared()
	if Config and Results then return end
	local Shared = ReplicatedStorage:FindFirstChild("Shared")
	if Shared then
		local configMod = Shared:FindFirstChild("Config")
		if configMod then
			local ok, result = pcall(require, configMod)
			if ok then Config = result end
		end
		local resultsMod = Shared:FindFirstChild("Results")
		if resultsMod then
			local ok, result = pcall(require, resultsMod)
			if ok then Results = result end
		end
	end
end

local function playerNameFor(userId: number?): string
	if not userId then return "Unknown" end
	local plr = Players:GetPlayerByUserId(userId)
	if plr then
		return plr.Name
	end
	return "Player " .. tostring(userId)
end

-- PLACEHOLDER VICTORY PRESENTATION - confetti burst created entirely in code (no asset IDs).
local function spawnConfetti(character: Model?)
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end
	local host = Instance.new("Part")
	host.Name = "VictoryConfetti"
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.Transparency = 1
	host.Size = Vector3.new(0.5, 0.5, 0.5)
	host.CFrame = hrp.CFrame + Vector3.new(0, 4, 0)
	host.Parent = workspace

	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Confetti_PLACEHOLDER"
	pe.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 215, 0)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 120, 160)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 200, 255)),
	})
	pe.LightEmission = 0.8
	pe.Speed = NumberRange.new(6, 14)
	pe.Lifetime = NumberRange.new(0.8, 1.6)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 0.08),
	})
	pe.Rate = 0
	pe.Parent = host
	pe:Emit(120)
	Debris:AddItem(host, 3)
end

local function showResultBanner(text: string, color: Color3, duration: number)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "MatchResultBanner"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 64
	gui.Parent = playerGui
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 0.12)
	lbl.Position = UDim2.fromScale(0, 0.2)
	lbl.BackgroundTransparency = 1
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBlack
	lbl.Text = text
	lbl.TextColor3 = color
	lbl.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
	lbl.TextStrokeTransparency = 0
	lbl.Rotation = -2
	lbl.Parent = gui
	lbl.TextTransparency = 1
	TweenService:Create(lbl, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
	Debris:AddItem(gui, duration)
	print("[MatchResult] " .. text)
end

-- Server -> ALL: (matchId, matchResult, winnerUserId, reason)
local function onMatchResult(matchId: string, matchResult: string, winnerUserId: number?, reason: string)
	loadShared()
	if currentMatchId and matchId ~= currentMatchId then return end

	local winnerResult = (Results and Results.MatchResults.WINNER) or "Winner"
	local duration = (Config and Config.LobbyReturnDelay) or 5

	if matchResult == winnerResult and winnerUserId then
		local winnerName = playerNameFor(winnerUserId)
		if winnerUserId == player.UserId then
			showResultBanner("VICTORY! You win the match!", Color3.fromRGB(255, 215, 0), duration)
			spawnConfetti(player.Character)
		else
			showResultBanner(winnerName .. " WINS! - Defeat (thanks for playing)", Color3.fromRGB(220, 120, 120), duration)
			local winner = Players:GetPlayerByUserId(winnerUserId)
			if winner then
				spawnConfetti(winner.Character)
			end
		end
	else
		showResultBanner("Match ended: " .. tostring(reason), Color3.fromRGB(200, 200, 200), duration)
	end
end

function MatchResultService.HandleMatchEnd()
	currentMatchId = nil
end

function MatchResultService.UpdateState(matchId: string?)
	if matchId then currentMatchId = matchId end
end

function MatchResultService.Init()
	loadShared()
	print("[MatchResultService] Initializing...")

	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotesFolder then
		warn("[MatchResultService] Missing Remotes folder")
		return
	end

	remotes.MatchResult = remotesFolder:WaitForChild("RE_MatchResult", 10)
	if not remotes.MatchResult then
		warn("[MatchResultService] RE_MatchResult not found - result presentation disabled")
		return
	end

	remotes.MatchResult.OnClientEvent:Connect(function(matchId, matchResult, winnerUserId, reason)
		onMatchResult(matchId, matchResult, winnerUserId, reason)
	end)

	player.CharacterAdded:Connect(function()
		-- Respawn during result display: re-show confetti if we won (banner is Debris-managed)
	end)

	print("[MatchResultService] Ready - victory/defeat presentation (placeholders, no rewards)")
end

return MatchResultService
