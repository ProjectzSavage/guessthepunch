--!nonstrict
-- QueueUIService.luau
-- Purpose: LOBBY QUEUE UI (presentation ONLY - server keeps all queue authority)
-- Implements ONLY:
-- - Code-created queue panel (no asset IDs, no manual GUI objects): title + one row per slot
--   (Slot2/Slot4/Slot6) with live occupancy (2/4 style), slot state and countdown
-- - Join button per row -> RE_QueueJoinRequest:FireServer(slotId); Leave button when joined
--   -> RE_QueueLeaveRequest:FireServer() - the SERVER validates joins/leaves/rate limits
-- - Live status from RE_QueueStateUpdate (slotId, occupancyList, maxPlayers, state,
--   countdownTimeLeft, locked, occupancyCount) and RE_QueueCountdownUpdate (slotId, timeLeft)
-- - Visible in the LOBBY (no match); hides automatically when a match starts, returns on match end
-- - Buttons are display-only triggers: pressing Join while locked/full/in-match simply gets
--   rejected by the server (panel also greys rows from server state)
-- Does NOT implement: match gameplay, monetization, shop UI, final polish, DataStores
-- Roblox Studio Destination: StarterPlayer > StarterPlayerScripts > GuessThePuncherClient > Services > QueueUIService (ModuleScript)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QueueUIService = {}

local player = Players.LocalPlayer
local remotes = {}

local Config = nil
local currentMatchId: string? = nil
local queueGui = nil
local rows = {} -- [slotId] = {frame, titleLabel, statusLabel, joinButton, leaveButton}
local mySlot: string? = nil

local SLOT_IDS = { "Slot2", "Slot4", "Slot6" }

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

local function capacityFor(slotId: string): number
	return (Config and Config.QueueCapacities and Config.QueueCapacities[slotId]) or 2
end

local function stateText(state: string?, countdownTimeLeft: number?, locked: boolean?): (string, Color3)
	if locked then
		return "LOCKED", Color3.fromRGB(255, 170, 80)
	end
	if state == "COUNTDOWN_FULL" or state == "COUNTDOWN_PARTIAL" then
		return string.format("Starting in %.0fs...", countdownTimeLeft or 0), Color3.fromRGB(120, 220, 140)
	end
	if state == "LOCKED" then
		return "LOCKED", Color3.fromRGB(255, 170, 80)
	end
	if state == "STARTING" then
		return "STARTING...", Color3.fromRGB(120, 220, 140)
	end
	if state == "CANCELLED" then
		return "CANCELLED", Color3.fromRGB(255, 120, 120)
	end
	return "Open - waiting for players", Color3.fromRGB(190, 200, 220)
end

local function destroyGui()
	if queueGui then
		queueGui:Destroy()
		queueGui = nil
		rows = {}
	end
end

-- Row refresh from server state
local function updateRow(slotId: string, occupancyList: {number}, maxPlayers: number, state: string?, countdownTimeLeft: number?, locked: boolean?, occupancyCount: number?)
	local row = rows[slotId]
	if not row then return end
	local count = occupancyCount or #occupancyList
	local inSlot = false
	for _, uid in ipairs(occupancyList) do
		if uid == player.UserId then
			inSlot = true
			break
		end
	end
	if inSlot then
		mySlot = slotId
	elseif mySlot == slotId then
		mySlot = nil
	end

	row.titleLabel.Text = string.format("%s  -  %d players", slotId:gsub("Slot", ""), maxPlayers)
	local txt, color = stateText(state, countdownTimeLeft, locked)
	row.statusLabel.Text = string.format("%d/%d  %s", count, maxPlayers, txt)
	row.statusLabel.TextColor3 = color

	-- Buttons: server still validates everything
	local canJoin = (not locked) and state == "WAITING" and count < maxPlayers and mySlot == nil
	row.joinButton.Visible = (not inSlot)
	row.joinButton.AutoButtonColor = canJoin
	row.joinButton.BackgroundColor3 = canJoin and Color3.fromRGB(60, 120, 220) or Color3.fromRGB(90, 90, 90)
	row.leaveButton.Visible = inSlot
	row.frame.BackgroundColor3 = inSlot and Color3.fromRGB(35, 55, 90) or Color3.fromRGB(25, 25, 35)
end

local function buildGui()
	loadShared()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end
	destroyGui()

	queueGui = Instance.new("ScreenGui")
	queueGui.Name = "QueueGui"
	queueGui.ResetOnSpawn = false
	queueGui.DisplayOrder = 40
	queueGui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.55)
	panel.Size = UDim2.fromScale(0.3, 0.34)
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Parent = queueGui

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 0.16)
	title.BackgroundTransparency = 1
	title.TextScaled = true
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = Color3.fromRGB(255, 220, 120)
	title.Text = "GUESS THE PUNCHER"
	title.Parent = panel

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Position = UDim2.fromScale(0, 0.16)
	subtitle.Size = UDim2.fromScale(1, 0.1)
	subtitle.BackgroundTransparency = 1
	subtitle.TextScaled = true
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextColor3 = Color3.fromRGB(190, 200, 220)
	subtitle.Text = "Pick a queue slot"
	subtitle.Parent = panel

	for i, slotId in ipairs(SLOT_IDS) do
		local row = Instance.new("Frame")
		row.Name = slotId
		row.Position = UDim2.fromScale(0.05, 0.28 + (i - 1) * 0.24)
		row.Size = UDim2.fromScale(0.9, 0.2)
		row.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
		row.BorderSizePixel = 0
		row.Parent = panel

		local titleLabel = Instance.new("TextLabel")
		titleLabel.Name = "TitleLabel"
		titleLabel.Position = UDim2.fromScale(0.03, 0.05)
		titleLabel.Size = UDim2.fromScale(0.42, 0.5)
		titleLabel.BackgroundTransparency = 1
		titleLabel.TextScaled = true
		titleLabel.Font = Enum.Font.GothamBold
		titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		titleLabel.Text = slotId
		titleLabel.Parent = row

		local statusLabel = Instance.new("TextLabel")
		statusLabel.Name = "StatusLabel"
		statusLabel.Position = UDim2.fromScale(0.03, 0.52)
		statusLabel.Size = UDim2.fromScale(0.6, 0.42)
		statusLabel.BackgroundTransparency = 1
		statusLabel.TextScaled = true
		statusLabel.Font = Enum.Font.Gotham
		statusLabel.TextColor3 = Color3.fromRGB(190, 200, 220)
		statusLabel.Text = "0/" .. tostring(capacityFor(slotId)) .. "  Open"
		statusLabel.Parent = row

		local joinButton = Instance.new("TextButton")
		joinButton.Name = "JoinButton"
		joinButton.AnchorPoint = Vector2.new(1, 0.5)
		joinButton.Position = UDim2.fromScale(0.97, 0.5)
		joinButton.Size = UDim2.fromScale(0.26, 0.66)
		joinButton.BackgroundColor3 = Color3.fromRGB(60, 120, 220)
		joinButton.BorderSizePixel = 0
		joinButton.TextScaled = true
		joinButton.Font = Enum.Font.GothamBold
		joinButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		joinButton.Text = "JOIN"
		joinButton.Parent = row
		joinButton.Activated:Connect(function()
			local re = remotes.JoinRequest
			if re then
				re:FireServer(slotId)
				print("[QueueUI] Join requested: " .. slotId .. " (server decides)")
			end
		end)

		local leaveButton = Instance.new("TextButton")
		leaveButton.Name = "LeaveButton"
		leaveButton.AnchorPoint = Vector2.new(1, 0.5)
		leaveButton.Position = UDim2.fromScale(0.97, 0.5)
		leaveButton.Size = UDim2.fromScale(0.26, 0.66)
		leaveButton.BackgroundColor3 = Color3.fromRGB(200, 70, 70)
		leaveButton.BorderSizePixel = 0
		leaveButton.TextScaled = true
		leaveButton.Font = Enum.Font.GothamBold
		leaveButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		leaveButton.Text = "LEAVE"
		leaveButton.Visible = false
		leaveButton.Parent = row
		leaveButton.Activated:Connect(function()
			local re = remotes.LeaveRequest
			if re then
				re:FireServer()
				print("[QueueUI] Leave requested (server decides)")
			end
		end)

		rows[slotId] = {
			frame = row,
			titleLabel = titleLabel,
			statusLabel = statusLabel,
			joinButton = joinButton,
			leaveButton = leaveButton,
		}
	end

	print("[QueueUI] Queue panel opened")
end

-- Visibility control: queue panel only in the lobby (Config can disable)
local function setGuiVisible(visible: boolean)
	loadShared()
	if not (Config and Config.UIEnabled and Config.ShowQueueUI) then
		visible = false
	end
	if visible then
		if not queueGui then
			buildGui()
		end
	elseif queueGui then
		destroyGui()
	end
end

-- ============================================================================
-- SERVER EVENTS
-- ============================================================================

local function onStateUpdate(slotId: string, occupancyList, maxPlayers: number, state: string?, countdownTimeLeft: number?, locked: boolean?, occupancyCount: number?)
	if not queueGui then return end
	updateRow(slotId, occupancyList or {}, maxPlayers or capacityFor(slotId), state, countdownTimeLeft, locked, occupancyCount)
end

function QueueUIService.UpdateState(matchId: string?, role: string?, state: string?)
	currentMatchId = matchId
	-- Queue panel shows ONLY in the lobby (no match)
	setGuiVisible(currentMatchId == nil)
end

function QueueUIService.HandleMatchEnd()
	currentMatchId = nil
	mySlot = nil
	-- Return to lobby: show the queue panel again
	setGuiVisible(true)
end

function QueueUIService.Init()
	loadShared()
	print("[QueueUIService] Initializing...")

	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotesFolder then
		warn("[QueueUIService] Missing Remotes folder")
		return
	end

	remotes.JoinRequest = remotesFolder:WaitForChild("RE_QueueJoinRequest", 10)
	remotes.LeaveRequest = remotesFolder:FindFirstChild("RE_QueueLeaveRequest")
	remotes.StateUpdate = remotesFolder:FindFirstChild("RE_QueueStateUpdate")
	remotes.CountdownUpdate = remotesFolder:FindFirstChild("RE_QueueCountdownUpdate")
	remotes.Started = remotesFolder:FindFirstChild("RE_QueueStarted")

	if remotes.StateUpdate then
		remotes.StateUpdate.OnClientEvent:Connect(function(slotId, occupancyList, maxPlayers, state, countdownTimeLeft, locked, occupancyCount)
			onStateUpdate(slotId, occupancyList, maxPlayers, state, countdownTimeLeft, locked, occupancyCount)
		end)
	else
		warn("[QueueUIService] RE_QueueStateUpdate not found - queue panel will be static")
	end

	if remotes.CountdownUpdate then
		remotes.CountdownUpdate.OnClientEvent:Connect(function(slotId, timeLeft)
			if rows[slotId] then
				rows[slotId].statusLabel.Text = string.format("Starting in %.0fs...", timeLeft or 0)
				rows[slotId].statusLabel.TextColor3 = Color3.fromRGB(120, 220, 140)
			end
		end)
	end

	if remotes.Started then
		remotes.Started.OnClientEvent:Connect(function(slotId, players)
			print(string.format("[QueueUI] %s started with %d players - match starting", tostring(slotId), players and #players or 0))
		end)
	end

	-- Open the panel in the lobby at start (hidden again as soon as a match starts)
	setGuiVisible(true)
	print("[QueueUIService] Ready - lobby queue panel active (Join/Leave buttons)")
end

return QueueUIService
