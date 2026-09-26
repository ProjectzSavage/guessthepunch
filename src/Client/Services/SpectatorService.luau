--!nonstrict
-- SpectatorService.luau
-- Purpose: SPECTATOR MODE client presentation ONLY (server-enforced, kept separate from active-player services)
-- Implements ONLY:
-- - Activates for the LOCAL player when they are eliminated (RE_PlayerEliminated with own userId)
-- - Controlled spectator camera: follows an active player (default = current Target, else first)
-- - Switching between eligible active players: Q / E keys + on-screen Prev/Next buttons (code-created GUI)
-- - Watch list comes from RE_SpectatorUpdate (Server -> spectator ONLY): active userIds, NO puncher
--   identity, no roles - the server masks Puncher info from spectators until the official reveal
-- - "Spectating <name>" header + "SPECTATOR MODE" panel; identity of the Puncher is never shown here
-- - Handles match ending while spectating: RE_MatchEnd / HandleMatchEnd restores camera + controls
-- - Sends NOTHING to the server (spectator actions are server-side; leash is server-enforced)
-- Does NOT implement: rewards, monetization, freecam polish, spectator chat, final GUI
-- Roblox Studio Destination: StarterPlayer > StarterPlayerScripts > GuessThePuncherClient > Services > SpectatorService (ModuleScript)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SpectatorService = {}

local player = Players.LocalPlayer
local remotes = {}

local spectating = false
local currentMatchId: string? = nil
local activeUserIds: {number} = {} -- eligible active players to watch (from server)
local watchIndex = 1
local renderBound = false
local spectateGui = nil
local headerLabel = nil
local infoLabel = nil

local function resolvePlayer(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

local function isWatchable(userId: number): boolean
	local plr = resolvePlayer(userId)
	if not plr then return false end
	local char = plr.Character
	if not char then return false end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	return hrp ~= nil and hum ~= nil and hum.Health > 0
end

local function watchedUserId(): number?
	for attempt = 1, #activeUserIds + 1 do
		local uid = activeUserIds[watchIndex]
		if uid and isWatchable(uid) then
			return uid
		end
		watchIndex += 1
		if watchIndex > #activeUserIds then
			watchIndex = 1
		end
		if attempt > #activeUserIds then break end
	end
	-- Fallback: any watchable active player
	for i, uid in ipairs(activeUserIds) do
		if isWatchable(uid) then
			watchIndex = i
			return uid
		end
	end
	return nil
end

-- ============================================================================
-- MINIMAL SPECTATOR GUI (code-created; final GUI comes later)
-- ============================================================================

local function destroyGui()
	if spectateGui then
		spectateGui:Destroy()
		spectateGui = nil
		headerLabel = nil
		infoLabel = nil
	end
end

local function buildGui()
	if spectateGui then return end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end
	spectateGui = Instance.new("ScreenGui")
	spectateGui.Name = "SpectatorGui"
	spectateGui.ResetOnSpawn = false
	spectateGui.DisplayOrder = 58
	spectateGui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.fromScale(0.5, 0.98)
	panel.Size = UDim2.fromScale(0.36, 0.13)
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	panel.BackgroundTransparency = 0.25
	panel.BorderSizePixel = 0
	panel.Parent = spectateGui

	headerLabel = Instance.new("TextLabel")
	headerLabel.Name = "Header"
	headerLabel.Size = UDim2.fromScale(1, 0.34)
	headerLabel.BackgroundTransparency = 1
	headerLabel.TextScaled = true
	headerLabel.Font = Enum.Font.GothamBold
	headerLabel.TextColor3 = Color3.fromRGB(150, 200, 255)
	headerLabel.Text = "SPECTATOR MODE"
	headerLabel.Parent = panel

	infoLabel = Instance.new("TextLabel")
	infoLabel.Name = "Info"
	infoLabel.Position = UDim2.fromScale(0, 0.34)
	infoLabel.Size = UDim2.fromScale(1, 0.3)
	infoLabel.BackgroundTransparency = 1
	infoLabel.TextScaled = true
	infoLabel.Font = Enum.Font.Gotham
	infoLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	infoLabel.Text = "Spectating..."
	infoLabel.Parent = panel

	local btnRow = Instance.new("Frame")
	btnRow.Position = UDim2.fromScale(0.05, 0.66)
	btnRow.Size = UDim2.fromScale(0.9, 0.3)
	btnRow.BackgroundTransparency = 1
	btnRow.Parent = panel

	local prevBtn = Instance.new("TextButton")
	prevBtn.Name = "Prev"
	prevBtn.Size = UDim2.fromScale(0.32, 1)
	prevBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 160)
	prevBtn.BorderSizePixel = 0
	prevBtn.TextScaled = true
	prevBtn.Font = Enum.Font.GothamBold
	prevBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	prevBtn.Text = "< Prev (Q)"
	prevBtn.Parent = btnRow
	prevBtn.Activated:Connect(function()
		SpectatorService.Switch(-1)
	end)

	local nextBtn = Instance.new("TextButton")
	nextBtn.Name = "Next"
	nextBtn.Position = UDim2.fromScale(0.68, 0)
	nextBtn.Size = UDim2.fromScale(0.32, 1)
	nextBtn.BackgroundColor3 = Color3.fromRGB(60, 90, 160)
	nextBtn.BorderSizePixel = 0
	nextBtn.TextScaled = true
	nextBtn.Font = Enum.Font.GothamBold
	nextBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	nextBtn.Text = "Next (E) >"
	nextBtn.Parent = btnRow
	nextBtn.Activated:Connect(function()
		SpectatorService.Switch(1)
	end)
end

local function updateInfoLabel()
	if infoLabel then
		local uid = watchedUserId()
		local nameStr = uid and (function()
			local plr = resolvePlayer(uid)
			return plr and plr.Name or ("Player " .. tostring(uid))
		end)() or "waiting for players"
		infoLabel.Text = string.format("Spectating %s (%d/%d)", nameStr, watchIndex, math.max(1, #activeUserIds))
	end
end

-- ============================================================================
-- CONTROLLED SPECTATOR CAMERA (follow cam; restore on end)
-- ============================================================================

local function stopFollowCamera()
	if renderBound then
		pcall(function()
			RunService:UnbindFromRenderStep("SpectatorFollowCamera")
		end)
		renderBound = false
	end
end

local function startFollowCamera()
	stopFollowCamera()
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	renderBound = true
	RunService:BindToRenderStep("SpectatorFollowCamera", Enum.RenderPriority.Camera.Value + 1, function()
		if not spectating then return end
		local camera2 = workspace.CurrentCamera
		if not camera2 then return end
		local uid = watchedUserId()
		local plr = uid and resolvePlayer(uid) or nil
		local char = plr and plr.Character or nil
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then
			updateInfoLabel()
			return
		end
		-- Controlled follow position: behind and above the watched player
		local targetCF = hrp.CFrame * CFrame.new(0, 7, 11)
		camera2.CFrame = camera2.CFrame:Lerp(targetCF, 0.18)
		updateInfoLabel()
	end)
end

local function restoreCameraAndControls()
	stopFollowCamera()
	local camera = workspace.CurrentCamera
	local character = player.Character
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
	destroyGui()
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function SpectatorService.Switch(direction: number)
	if not spectating then return end
	if #activeUserIds == 0 then return end
	watchIndex = watchIndex + (direction >= 0 and 1 or -1)
	if watchIndex > #activeUserIds then watchIndex = 1 end
	if watchIndex < 1 then watchIndex = #activeUserIds end
	updateInfoLabel()
end

-- Server -> ALL: (matchId, eliminatedUserId, reason). Local player eliminated -> spectate.
local function onPlayerEliminated(matchId: string, eliminatedUserId: number, reason: string)
	if currentMatchId and matchId ~= currentMatchId then return end
	if eliminatedUserId ~= player.UserId then return end
	if spectating then return end
	spectating = true
	print("[Spectator] Spectator mode ACTIVATED (reason: " .. tostring(reason) .. ") - camera follows active players, Q/E or buttons to switch")
	buildGui()
	startFollowCamera()
end

-- Server -> SPECTATOR ONLY: (matchId, activeUserIds)
local function onSpectatorUpdate(matchId: string, newActiveUserIds: {number})
	if currentMatchId and matchId ~= currentMatchId then return end
	if not spectating then return end
	activeUserIds = newActiveUserIds or {}
	if watchIndex > #activeUserIds then watchIndex = 1 end
	updateInfoLabel()
	print("[Spectator] Watch list updated: " .. #activeUserIds .. " active players")
end

function SpectatorService.UpdateState(matchId: string?, role: string?, state: string?)
	if matchId then currentMatchId = matchId end
	if spectating and role and role ~= "Spectator" then
		-- No longer a spectator (safety)
		spectating = false
		activeUserIds = {}
		restoreCameraAndControls()
	end
end

-- Match ending while spectating -> restore camera and controls (lobby teleport comes from server)
function SpectatorService.HandleMatchEnd()
	if spectating then
		print("[Spectator] Match ended while spectating - restoring camera and controls")
	end
	spectating = false
	currentMatchId = nil
	activeUserIds = {}
	watchIndex = 1
	restoreCameraAndControls()
end

function SpectatorService.Init()
	print("[SpectatorService] Initializing...")

	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotesFolder then
		warn("[SpectatorService] Missing Remotes folder")
		return
	end

	remotes.PlayerEliminated = remotesFolder:WaitForChild("RE_PlayerEliminated", 10)
	remotes.SpectatorUpdate = remotesFolder:FindFirstChild("RE_SpectatorUpdate")

	if remotes.PlayerEliminated then
		remotes.PlayerEliminated.OnClientEvent:Connect(function(matchId, eliminatedUserId, reason)
			onPlayerEliminated(matchId, eliminatedUserId, reason)
		end)
	else
		warn("[SpectatorService] RE_PlayerEliminated not found - spectator mode disabled")
	end

	if remotes.SpectatorUpdate then
		remotes.SpectatorUpdate.OnClientEvent:Connect(function(matchId, activeList)
			onSpectatorUpdate(matchId, activeList)
		end)
	end

	-- Keyboard switching (Q/E)
	local UserInputService = game:GetService("UserInputService")
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not spectating then return end
		if input.KeyCode == Enum.KeyCode.Q then
			SpectatorService.Switch(-1)
		elseif input.KeyCode == Enum.KeyCode.E then
			SpectatorService.Switch(1)
		end
	end)

	-- Restore if the local character respawns while spectating (camera re-applies via follow loop)
	player.CharacterAdded:Connect(function()
		if spectating then
			startFollowCamera()
		end
	end)

	print("[SpectatorService] Ready - spectator camera activates on elimination (Q/E to switch)")
end

return SpectatorService
