--!nonstrict
-- GuessingService.luau
-- Purpose: Client-side GUESSING phase presentation + Target guess submission ONLY (server-authoritative)
-- Implements ONLY:
-- - RE_GuessOpen (Target ONLY): shows a code-created minimal choice GUI (eligible players EXCLUDING the
--   Target) with a live countdown; server rebroadcasts for countdown updates and eligible shrink
-- - Target submits ONE guess: clicking a button fires RE_GuessRequest(matchId, guessedUserId) - nothing else
-- - Prevents guessing before the phase starts: the GUI exists ONLY while Guessing is active server-side
-- - One submitted guess: buttons lock after submission (duplicate presses rejected by server too)
-- - RE_GuessResult (ALL clients): shows the OFFICIAL reveal banner (CorrectGuess / WrongGuess /
--   GuessTimeout; InvalidGuess is Target-only, no reveal) then cleans up
-- - RE_GuessRejected (Target): shows rejection reason (duplicate / invalid / too early)
-- - Handles players leaving: server refreshes the eligible list; GUI rebuilds on each GuessOpen
-- - Cleans up on match end, state change, or respawn
-- The SERVER validates and evaluates the guess; this client NEVER decides the result and keeps
-- no Puncher information until the official reveal.
-- Does NOT implement: role transfer UI flow (server does it), knockout, scoring, final GUI, monetization
-- Roblox Studio Destination: StarterPlayer > StarterPlayerScripts > GuessThePuncherClient > Services > GuessingService (ModuleScript)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GuessingService = {}

local Config = nil
local Results = nil
local player = Players.LocalPlayer

local remotes = {}

local guessGui = nil -- ScreenGui with choice buttons (Target only)
local statusLabel = nil
local countdownLabel = nil
local currentMatchId: string? = nil
local submitted = false

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

local function playerNameFor(userId: number): string
	local plr = Players:GetPlayerByUserId(userId)
	if plr then
		return plr.Name
	end
	return "Player " .. tostring(userId)
end

-- ============================================================================
-- MINIMAL CHOICE GUI (created in code; final GUI comes in a later phase)
-- ============================================================================

local function destroyGuessGui()
	if guessGui then
		guessGui:Destroy()
		guessGui = nil
		statusLabel = nil
		countdownLabel = nil
	end
end

local function buildChoiceGui(matchId: string, eligibleUserIds: {number}, timeLeft: number)
	loadShared()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end

	local wasOpen = (guessGui ~= nil)
	destroyGuessGui()

	guessGui = Instance.new("ScreenGui")
	guessGui.Name = "GuessingDebugGui"
	guessGui.ResetOnSpawn = false
	guessGui.DisplayOrder = 55
	guessGui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.25)
	panel.Size = UDim2.fromScale(0.42, 0.06 + 0.085 * math.max(1, #eligibleUserIds))
	panel.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	panel.BackgroundTransparency = 0.15
	panel.BorderSizePixel = 0
	panel.Parent = guessGui

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 0.18)
	title.BackgroundTransparency = 1
	title.TextScaled = true
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = "WHO PUNCHED YOU? Pick one:"
	title.Parent = panel

	countdownLabel = Instance.new("TextLabel")
	countdownLabel.Name = "Countdown"
	countdownLabel.Position = UDim2.fromScale(0, 0.18)
	countdownLabel.Size = UDim2.fromScale(1, 0.16)
	countdownLabel.BackgroundTransparency = 1
	countdownLabel.TextScaled = true
	countdownLabel.Font = Enum.Font.GothamBlack
	countdownLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
	countdownLabel.Text = string.format("Time left: %.0fs", timeLeft)
	countdownLabel.Parent = panel

	statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Position = UDim2.fromScale(0, 0.34)
	statusLabel.Size = UDim2.fromScale(1, 0.14)
	statusLabel.BackgroundTransparency = 1
	statusLabel.TextScaled = true
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	statusLabel.Text = "One guess only - choose carefully"
	statusLabel.Parent = panel

	-- One button per eligible player (Target excluded by the server list)
	for i, userId in ipairs(eligibleUserIds) do
		local btn = Instance.new("TextButton")
		btn.Name = "Guess_" .. tostring(userId)
		btn.Position = UDim2.fromScale(0.05, 0.5 + (i - 1) * (0.45 / math.max(1, #eligibleUserIds)))
		btn.Size = UDim2.fromScale(0.9, 0.4 / math.max(1, #eligibleUserIds))
		btn.BackgroundColor3 = Color3.fromRGB(60, 90, 180)
		btn.BorderSizePixel = 0
		btn.TextScaled = true
		btn.Font = Enum.Font.GothamBold
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.Text = playerNameFor(userId)
		btn.Parent = panel
		btn.Activated:Connect(function()
			if submitted then
				print("[Guessing] Guess already submitted - duplicate prevented")
				return
			end
			local re = remotes.GuessRequest
			if not re then
				warn("[Guessing] RE_GuessRequest not found")
				return
			end
			submitted = true
			-- Send ONLY (matchId, guessedUserId). The server validates and decides the result.
			re:FireServer(matchId, userId)
			print("[Guessing] Guess submitted: " .. playerNameFor(userId) .. " (server decides)")
			if statusLabel then
				statusLabel.Text = "Guess submitted: " .. playerNameFor(userId)
			end
			-- Lock all buttons visually
			for _, child in ipairs(panel:GetChildren()) do
				if child:IsA("TextButton") then
					child.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
					child.Active = false
				end
			end
		end)
	end

	if not wasOpen then
		print("[Guessing] Choice GUI opened: " .. #eligibleUserIds .. " eligible players, " .. string.format("%.0fs", timeLeft))
	end
end

-- ============================================================================
-- REVEAL BANNER (all clients, official reveal)
-- ============================================================================

local function showRevealBanner(result: string, guessedUserId: number?, puncherUserId: number?)
	loadShared()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end

	local text: string
	local color = Color3.fromRGB(255, 255, 255)
	if result == (Results and Results.GuessResults.CORRECT or "CorrectGuess") then
		text = "CORRECT GUESS! " .. (guessedUserId and playerNameFor(guessedUserId) or "?") .. " was the Puncher!"
		color = Color3.fromRGB(120, 255, 140)
	elseif result == (Results and Results.GuessResults.WRONG or "WrongGuess") then
		text = "WRONG GUESS! The Puncher was " .. (puncherUserId and playerNameFor(puncherUserId) or "unknown")
		color = Color3.fromRGB(255, 110, 110)
	elseif result == (Results and Results.GuessResults.TIMEOUT or "GuessTimeout") then
		text = "TIME'S UP! The Puncher was " .. (puncherUserId and playerNameFor(puncherUserId) or "unknown")
		color = Color3.fromRGB(255, 190, 90)
	else
		-- InvalidGuess: Target-only diagnostic, no reveal
		text = "Guess invalid"
		color = Color3.fromRGB(190, 190, 190)
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "GuessRevealBanner"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 62
	gui.Parent = playerGui
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 0.1)
	lbl.Position = UDim2.fromScale(0, 0.55)
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
	TweenService:Create(lbl, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
	task.delay(3.0, function()
		if gui.Parent then
			gui:Destroy()
		end
	end)
	print("[Guessing] REVEAL: " .. text)
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

-- Server -> TARGET ONLY: (matchId, eligibleUserIds, timeLeft). No puncher info included.
local function onGuessOpen(matchId: string, eligibleUserIds: {number}, timeLeft: number)
	if currentMatchId and matchId ~= currentMatchId then return end
	submitted = false -- new phase/refresh allows submission again (server also validates)
	buildChoiceGui(matchId, eligibleUserIds, timeLeft)
end

-- Server -> ALL clients (official reveal): (matchId, result, guessedUserId, puncherUserId [, reason])
local function onGuessResult(matchId: string, result: string, guessedUserId: number?, puncherUserId: number?, reason: string?)
	if currentMatchId and matchId ~= currentMatchId then return end
	if result == (Results and Results.GuessResults.INVALID or "InvalidGuess") then
		-- InvalidGuess is Target-only diagnostic (no reveal); the guess is NOT consumed - keep the choice UI
		print("[Guessing] Invalid guess (not consumed): " .. tostring(reason))
		if statusLabel then
			statusLabel.Text = "Rejected: " .. tostring(reason)
		end
		submitted = false
		return
	end
	destroyGuessGui() -- resolved (Correct/Wrong/Timeout): Target's choice GUI goes away
	showRevealBanner(result, guessedUserId, puncherUserId)
end

-- Server -> Target: (matchId, reason)
local function onGuessRejected(matchId: string, reason: string)
	print("[Guessing] Guess REJECTED: " .. tostring(reason))
	-- Rejections like "Duplicate: guess already submitted" keep the lock;
	-- "Guessed player is not eligible" etc. do NOT consume the guess (server keeps phase open)
end

function GuessingService.HandleMatchEnd()
	currentMatchId = nil
	submitted = false
	destroyGuessGui()
	print("[Guessing] Guess UI cleaned: match ended")
end

function GuessingService.UpdateState(matchId: string?, role: string?, state: string?)
	if matchId then currentMatchId = matchId end
	-- Phase over (e.g. Puncher disconnected -> WaitingForPuncher): clean the choice UI
	if guessGui and state and state ~= "Guessing" then
		submitted = false
		destroyGuessGui()
		print("[Guessing] Guess UI cleaned: state changed to " .. tostring(state))
	end
end

function GuessingService.Init()
	loadShared()
	print("[GuessingService] Initializing...")

	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotesFolder then
		warn("[GuessingService] Missing Remotes folder")
		return
	end

	remotes.GuessOpen = remotesFolder:WaitForChild("RE_GuessOpen", 10)
	remotes.GuessRequest = remotesFolder:FindFirstChild("RE_GuessRequest")
	remotes.GuessRejected = remotesFolder:FindFirstChild("RE_GuessRejected")
	remotes.GuessResult = remotesFolder:FindFirstChild("RE_GuessResult")

	if not remotes.GuessOpen then
		warn("[GuessingService] RE_GuessOpen not found - guessing UI disabled")
		return
	end

	remotes.GuessOpen.OnClientEvent:Connect(function(matchId, eligibleUserIds, timeLeft)
		onGuessOpen(matchId, eligibleUserIds, timeLeft)
	end)

	if remotes.GuessResult then
		remotes.GuessResult.OnClientEvent:Connect(function(matchId, result, guessedUserId, puncherUserId)
			onGuessResult(matchId, result, guessedUserId, puncherUserId)
		end)
	end

	if remotes.GuessRejected then
		remotes.GuessRejected.OnClientEvent:Connect(function(matchId, reason)
			onGuessRejected(matchId, reason)
		end)
	end

	player.CharacterAdded:Connect(function()
		if guessGui then
			destroyGuessGui()
		end
		submitted = false
	end)

	print("[GuessingService] Ready - Target picks one eligible player when the guess phase opens")
end

return GuessingService
