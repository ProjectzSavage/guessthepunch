--!nonstrict
-- PowerGaugeService.luau
-- Purpose: Client-side power gauge DISPLAY and LOCK input ONLY (server-authoritative)
-- Implements ONLY:
-- - Receives gauge start from server (RE_PowerGaugeOpen, Puncher only) with server-controlled timestamp
-- - Displays moving needle using the SAME shared math as the server (PowerZones.GetNeedlePosition)
--   and the server timestamp via workspace:GetServerTimeNow() (synchronized clock)
-- - Sends LOCK request (RE_PowerGaugeStopRequest) with matchId ONLY
--   NO power value, NO zone claim, NO timestamp, NO role - the server calculates the zone
-- - Shows lock result zone returned by the server (RE_PowerGaugeResult, Puncher only)
-- - Shows rejection reasons (RE_PowerGaugeRejected)
-- Does NOT implement: damage, guessing, knockout, scoring, final animations, final GUI
-- (the on-screen gauge below is a minimal debug display, created in code - final GUI comes later)
-- Roblox Studio Destination: StarterPlayer > StarterPlayerScripts > GuessThePuncherClient > Services > PowerGaugeService (ModuleScript)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local PowerGaugeService = {}

local Config = nil
local PowerZones = nil
local player = Players.LocalPlayer

local remotes = {}

-- Gauge state (only set when server opens the gauge for us = we are the Puncher)
local gauge = nil -- {matchId, startServerTime, duration, sweepDuration, locked, resultZone, resultPosition, timedOut}
local renderConn = nil
local inputConn = nil
local currentMatchId: string? = nil
local cleanupTask = nil

-- Debug display instances (minimal, created in code)
local debugGui = nil
local needleFrame = nil
local statusLabel = nil
local zoneLabel = nil

local function loadShared()
	if Config and PowerZones then return end
	local Shared = ReplicatedStorage:FindFirstChild("Shared")
	if Shared then
		local configMod = Shared:FindFirstChild("Config")
		if configMod then
			local ok, result = pcall(require, configMod)
			if ok then Config = result end
		end
		local powerZonesMod = Shared:FindFirstChild("PowerZones")
		if powerZonesMod then
			local ok, result = pcall(require, powerZonesMod)
			if ok then PowerZones = result end
		end
	end
	if not PowerZones then
		-- Fallback math identical to PowerZones (should not normally happen)
		PowerZones = {
			GetNeedlePosition = function(elapsed, sweepDuration)
				if sweepDuration <= 0 then return 0 end
				if elapsed < 0 then elapsed = 0 end
				local raw = elapsed / sweepDuration
				local cycle = raw % 2
				if cycle <= 1 then return cycle else return 2 - cycle end
			end,
			Zones = { MISS = "Miss", WEAK = "Weak", NORMAL = "Normal", STRONG = "Strong", PERFECT = "Perfect" },
		}
	end
end

-- ============================================================================
-- MINIMAL DEBUG DISPLAY (created in code; final GUI comes in a later phase)
-- ============================================================================

local function destroyDebugDisplay()
	if debugGui then
		debugGui:Destroy()
		debugGui = nil
		needleFrame = nil
		statusLabel = nil
		zoneLabel = nil
	end
end

local function buildDebugDisplay()
	if not (Config and Config.PowerGaugeShowDebugDisplay) then return end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end
	destroyDebugDisplay()

	debugGui = Instance.new("ScreenGui")
	debugGui.Name = "PowerGaugeDebugGui"
	debugGui.ResetOnSpawn = false
	debugGui.DisplayOrder = 50
	debugGui.Parent = playerGui

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Position = UDim2.fromScale(0.5, 0.82)
	track.Size = UDim2.fromScale(0.45, 0.055)
	track.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	track.BorderSizePixel = 0
	track.Parent = debugGui

	-- Zone bands from shared config thresholds (presentation only)
	local thresholds = (Config and Config.PowerGaugeZoneThresholds) or { Normal = 0.40, Strong = 0.70, Perfect = 0.90 }
	local function band(fromPos: number, toPos: number, color: Color3, name: string)
		local f = Instance.new("Frame")
		f.Name = name
		f.AnchorPoint = Vector2.new(0, 0)
		f.Position = UDim2.fromScale(fromPos, 0)
		f.Size = UDim2.fromScale(math.clamp(toPos - fromPos, 0, 1), 1)
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 0.35
		f.BorderSizePixel = 0
		f.Parent = track
	end
	band(thresholds.Normal or 0.40, thresholds.Strong or 0.70, Color3.fromRGB(70, 130, 220), "BandNormal")
	band(thresholds.Strong or 0.70, thresholds.Perfect or 0.90, Color3.fromRGB(240, 150, 40), "BandStrong")
	band(thresholds.Perfect or 0.90, 1, Color3.fromRGB(230, 60, 60), "BandPerfect")

	needleFrame = Instance.new("Frame")
	needleFrame.Name = "Needle"
	needleFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	needleFrame.Position = UDim2.fromScale(0, 0.5)
	needleFrame.Size = UDim2.fromScale(0.012, 1.5)
	needleFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	needleFrame.BorderSizePixel = 0
	needleFrame.ZIndex = 3
	needleFrame.Parent = track

	statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.AnchorPoint = Vector2.new(0.5, 1)
	statusLabel.Position = UDim2.fromScale(0.5, -0.15)
	statusLabel.Size = UDim2.fromScale(1, 1.2)
	statusLabel.BackgroundTransparency = 1
	statusLabel.TextScaled = true
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	statusLabel.Text = "Gauge starting..."
	statusLabel.Parent = track

	zoneLabel = Instance.new("TextLabel")
	zoneLabel.Name = "ZoneResult"
	zoneLabel.AnchorPoint = Vector2.new(0.5, 0)
	zoneLabel.Position = UDim2.fromScale(0.5, 1.1)
	zoneLabel.Size = UDim2.fromScale(1, 1.4)
	zoneLabel.BackgroundTransparency = 1
	zoneLabel.TextScaled = true
	zoneLabel.Font = Enum.Font.GothamBlack
	zoneLabel.TextColor3 = Color3.fromRGB(255, 235, 120)
	zoneLabel.Text = ""
	zoneLabel.Parent = track
end

-- ============================================================================
-- GAUGE FLOW
-- ============================================================================

local function stopRenderLoop()
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
end

local function cleanupGauge(reason: string)
	stopRenderLoop()
	if cleanupTask then
		pcall(task.cancel, cleanupTask) -- may already be finished
		cleanupTask = nil
	end
	gauge = nil
	destroyDebugDisplay()
	print("[PowerGauge] Gauge display cleaned up: " .. reason)
end

-- Server opened the gauge (we are the Puncher). Args: matchId, startServerTime, duration, sweepDuration
local function onGaugeOpen(matchId: string, startServerTime: number, duration: number, sweepDuration: number)
	loadShared()
	if currentMatchId and matchId ~= currentMatchId then
		return -- not our match
	end
	if gauge then
		cleanupGauge("new gauge opened") -- replace stale display
	end

	gauge = {
		matchId = matchId,
		startServerTime = startServerTime, -- SERVER-controlled timestamp (never client-generated)
		duration = duration,
		sweepDuration = sweepDuration,
		locked = false,
		resultZone = nil,
		resultPosition = nil,
		timedOut = nil,
	}

	print(string.format("[PowerGauge] Gauge OPEN matchId=%s duration=%.2fs sweep=%.2fs - press %s to LOCK (sends matchId only)",
		matchId, duration, sweepDuration, Config and Config.PowerGaugeLockKey and Config.PowerGaugeLockKey.Name or "E"))

	buildDebugDisplay()
	if statusLabel then
		statusLabel.Text = "Press " .. (Config and Config.PowerGaugeLockKey and Config.PowerGaugeLockKey.Name or "E") .. " to lock!"
	end

	-- Display loop: needle position from SERVER timestamp + shared math (identical to server calc)
	stopRenderLoop()
	renderConn = RunService.RenderStepped:Connect(function()
		if not gauge then stopRenderLoop() return end
		local nowServer = workspace:GetServerTimeNow()
		local pos
		if gauge.locked and gauge.resultPosition then
			pos = gauge.resultPosition -- freeze at locked position
		else
			local elapsed = nowServer - gauge.startServerTime
			pos = PowerZones.GetNeedlePosition(elapsed, gauge.sweepDuration)
		end
		if needleFrame then
			needleFrame.Position = UDim2.fromScale(pos, 0.5)
		end
	end)
end

-- Lock input: sends ONLY the matchId. No power, no zone claim, no timestamp.
local function onLockKeyPressed()
	if not gauge then return end
	if gauge.locked then
		print("[PowerGauge] Already locked - ignoring input")
		return
	end
	local re = remotes.PowerGaugeStopRequest
	if not re then
		warn("[PowerGauge] RE_PowerGaugeStopRequest remote not found")
		return
	end
	-- CLIENT SENDS ONLY THE LOCK REQUEST (matchId). Server calculates the zone.
	re:FireServer(gauge.matchId)
	print("[PowerGauge] Lock request sent (matchId only, server decides zone)")
	if statusLabel then
		statusLabel.Text = "Lock requested..."
	end
end

-- Server rejected our lock request: matchId, reason
local function onGaugeRejected(matchId: string, reason: string)
	if gauge and matchId ~= gauge.matchId then return end
	print("[PowerGauge] Lock REJECTED: " .. tostring(reason))
	if statusLabel and gauge and not gauge.locked then
		statusLabel.Text = "Rejected: " .. tostring(reason)
	end
end

-- Server-calculated result: matchId, zone, position, timedOut (Puncher only)
local function onGaugeResult(matchId: string, zone: string, position: number, timedOut: boolean)
	if gauge and matchId ~= gauge.matchId then return end
	if not gauge then
		-- Got a result without display (edge) - just log it
		print("[PowerGauge] Result (no display): zone=" .. tostring(zone))
		return
	end
	gauge.locked = true
	gauge.resultZone = zone
	gauge.resultPosition = position
	gauge.timedOut = timedOut

	local source = timedOut and "TIMEOUT (Miss)" or "server-calculated"
	print(string.format("[PowerGauge] RESULT: zone=%s position=%.3f (%s)", tostring(zone), position or 0, source))
	if zoneLabel then
		zoneLabel.Text = timedOut and ("TIMEOUT - " .. tostring(zone)) or tostring(zone)
	end
	if statusLabel then
		statusLabel.Text = timedOut and "Too slow!" or "Locked!"
	end

	-- Freeze needle at the server position (render loop handles), cleanup shortly after
	stopRenderLoop()
	if needleFrame and position then
		needleFrame.Position = UDim2.fromScale(position, 0.5)
	end
	cleanupTask = task.delay(2.5, function()
		cleanupGauge("result shown")
	end)
end

-- Called by Main on every filtered state update
function PowerGaugeService.UpdateState(matchId: string?, role: string?, state: string?)
	if matchId then currentMatchId = matchId end
	-- If we somehow still show a gauge but state left PowerGauge (disconnect revert etc.), clean up
	if gauge and state and state ~= "PowerGauge" and not gauge.locked then
		cleanupGauge("state changed to " .. tostring(state))
	end
end

function PowerGaugeService.HandleMatchEnd()
	currentMatchId = nil
	if gauge then
		cleanupGauge("match ended")
	end
end

function PowerGaugeService.Init()
	loadShared()
	print("[PowerGaugeService] Initializing...")

	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotesFolder then
		warn("[PowerGaugeService] Missing Remotes folder")
		return
	end

	remotes.PowerGaugeOpen = remotesFolder:WaitForChild("RE_PowerGaugeOpen", 10)
	remotes.PowerGaugeStopRequest = remotesFolder:FindFirstChild("RE_PowerGaugeStopRequest")
	remotes.PowerGaugeRejected = remotesFolder:FindFirstChild("RE_PowerGaugeRejected")
	remotes.PowerGaugeResult = remotesFolder:FindFirstChild("RE_PowerGaugeResult")

	if not remotes.PowerGaugeOpen then
		warn("[PowerGaugeService] RE_PowerGaugeOpen not found - gauge display disabled")
		return
	end

	remotes.PowerGaugeOpen.OnClientEvent:Connect(function(matchId, startServerTime, duration, sweepDuration)
		onGaugeOpen(matchId, startServerTime, duration, sweepDuration)
	end)

	if remotes.PowerGaugeRejected then
		remotes.PowerGaugeRejected.OnClientEvent:Connect(function(matchId, reason)
			onGaugeRejected(matchId, reason)
		end)
	end

	if remotes.PowerGaugeResult then
		remotes.PowerGaugeResult.OnClientEvent:Connect(function(matchId, zone, position, timedOut)
			onGaugeResult(matchId, zone, position, timedOut)
		end)
	end

	-- Lock input for testing (final GUI comes later)
	local lockKey = (Config and Config.PowerGaugeLockKey) or Enum.KeyCode.E
	if inputConn then inputConn:Disconnect() end
	inputConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == lockKey then
			onLockKeyPressed()
		end
	end)

	print("[PowerGaugeService] Ready - press " .. lockKey.Name .. " to lock gauge when it is your punch")
end

return PowerGaugeService
