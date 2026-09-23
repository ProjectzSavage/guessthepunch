--!nonstrict
-- TargetCameraService.luau
-- Purpose: Client-only camera presentation for Target role
-- Implements ONLY:
-- - Force restricted first-person camera when player becomes Target
-- - Prevent zooming out
-- - Prevent freely rotating to inspect players behind them
-- - Keep camera stable
-- - Restore normal camera when no longer Target
-- - Handle reset, death, disconnect, match completion safely
-- Server controls Target role, client controls camera presentation only
-- Does NOT implement: Punch selection, power, damage, guessing, knockout, scoring, GUI
-- Roblox Studio Destination: StarterPlayer > StarterPlayerScripts > GuessThePuncherClient > Services > TargetCameraService (ModuleScript, child of Main.client.luau or sibling)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local TargetCameraService = {}
TargetCameraService.__index = TargetCameraService

local Config
local isTarget = false
local originalSettings = {}
local renderBindName = "TargetCameraClamp"
local initialForward = nil
local initialYaw = nil
local characterAddedConn = nil
local heartbeatConn = nil

-- Helpers

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
		TargetCameraEnabled = true,
		TargetFirstPersonZoom = 0.5,
		TargetMaxYawDegrees = 65,
		TargetMaxPitchDegrees = 30,
		TargetCameraStability = true,
		TargetDisableAutoRotate = true,
		TargetRestoreDelay = 0.2,
	}
end

local function getLocalPlayer(): Player?
	return Players.LocalPlayer
end

local function getHumanoid(): Humanoid?
	local player = getLocalPlayer()
	if not player then return nil end
	local character = player.Character
	if not character then return nil end
	return character:FindFirstChildOfClass("Humanoid")
end

local function getHRP(): BasePart?
	local player = getLocalPlayer()
	if not player then return nil end
	local character = player.Character
	if not character then return nil end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function normalizeAngle(angle: number): number
	-- Normalize to -pi .. pi
	while angle > math.pi do angle -= 2*math.pi end
	while angle < -math.pi do angle += 2*math.pi end
	return angle
end

local function getYawFromLookVector(look: Vector3): number
	return math.atan2(look.X, look.Z)
end

local function getPitchFromLookVector(look: Vector3): number
	-- pitch: positive up
	return math.asin(math.clamp(look.Y, -1, 1))
end

local function saveOriginalSettings()
	local player = getLocalPlayer()
	if not player then return end
	local humanoid = getHumanoid()
	local camera = Workspace.CurrentCamera
	if not camera then return end

	originalSettings.CameraMode = player.CameraMode
	originalSettings.MinZoom = player.CameraMinZoomDistance
	originalSettings.MaxZoom = player.CameraMaxZoomDistance
	originalSettings.CameraType = camera.CameraType
	if humanoid then
		originalSettings.AutoRotate = humanoid.AutoRotate
		originalSettings.CameraOffset = humanoid.CameraOffset
	end
	originalSettings.MouseBehavior = UserInputService.MouseBehavior
end

local function restoreOriginalSettings()
	local player = getLocalPlayer()
	if not player then return end
	local humanoid = getHumanoid()
	local camera = Workspace.CurrentCamera

	-- Unbind render step
	if RunService:FindFirstChild(renderBindName) or pcall(function() RunService:UnbindFromRenderStep(renderBindName) end) then
		pcall(function() RunService:UnbindFromRenderStep(renderBindName) end)
	end

	if originalSettings.CameraMode then
		pcall(function() player.CameraMode = originalSettings.CameraMode end)
	end
	if originalSettings.MinZoom then
		pcall(function() player.CameraMinZoomDistance = originalSettings.MinZoom end)
	end
	if originalSettings.MaxZoom then
		pcall(function() player.CameraMaxZoomDistance = originalSettings.MaxZoom end)
	end
	if camera and originalSettings.CameraType then
		pcall(function() camera.CameraType = originalSettings.CameraType end)
	end
	if humanoid then
		if originalSettings.AutoRotate ~= nil then
			pcall(function() humanoid.AutoRotate = originalSettings.AutoRotate end)
		end
		if originalSettings.CameraOffset then
			pcall(function() humanoid.CameraOffset = originalSettings.CameraOffset end)
		end
	end

	originalSettings = {}
	initialForward = nil
	initialYaw = nil
	isTarget = false
end

local function applyFirstPerson()
	local player = getLocalPlayer()
	if not player then return end
	local cfg = getConfig()
	local zoom = cfg.TargetFirstPersonZoom or 0.5

	-- Force restricted first-person, prevent zooming out
	pcall(function()
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		player.CameraMinZoomDistance = zoom
		player.CameraMaxZoomDistance = zoom
	end)

	local camera = Workspace.CurrentCamera
	if camera then
		pcall(function()
			camera.CameraType = Enum.CameraType.Custom
		end)
	end

	local humanoid = getHumanoid()
	if humanoid then
		pcall(function()
			if cfg.TargetDisableAutoRotate then
				humanoid.AutoRotate = false
			end
			humanoid.CameraOffset = Vector3.new(0, 0, 0)
		end)
	end
end

local function clampCamera()
	local player = getLocalPlayer()
	if not player then return end
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local camera = Workspace.CurrentCamera
	if not hrp or not camera then return end

	local cfg = getConfig()
	local maxYawDeg = cfg.TargetMaxYawDegrees or 65
	local maxPitchDeg = cfg.TargetMaxPitchDegrees or 30
	local maxYawRad = math.rad(maxYawDeg)
	local maxPitchRad = math.rad(maxPitchDeg)

	if not initialForward then
		initialForward = hrp.CFrame.LookVector
		initialYaw = getYawFromLookVector(initialForward)
		return
	end

	-- Keep camera stable: enforce first-person zoom
	pcall(function()
		player.CameraMinZoomDistance = cfg.TargetFirstPersonZoom or 0.5
		player.CameraMaxZoomDistance = cfg.TargetFirstPersonZoom or 0.5
		if player.CameraMode ~= Enum.CameraMode.LockFirstPerson then
			player.CameraMode = Enum.CameraMode.LockFirstPerson
		end
	end)

	-- Prevent freely rotating to inspect behind: clamp yaw/pitch
	local camCF = camera.CFrame
	local camLook = camCF.LookVector
	local currentYaw = getYawFromLookVector(camLook)
	local currentPitch = getPitchFromLookVector(camLook)

	local deltaYaw = normalizeAngle(currentYaw - (initialYaw or 0))

	-- Clamp yaw
	if math.abs(deltaYaw) > maxYawRad then
		local clampedYaw = (initialYaw or 0) + math.clamp(deltaYaw, -maxYawRad, maxYawRad)
		-- Preserve pitch, reconstruct look vector
		-- Use clamped yaw + current pitch to build new CFrame
		local clampedPitch = math.clamp(currentPitch, -maxPitchRad, maxPitchRad)
		-- Build CFrame from yaw/pitch: lookVector = (sin(yaw)*cos(pitch), sin(pitch), cos(yaw)*cos(pitch))
		-- Note: Roblox LookVector Z is forward, X is right
		local cosPitch = math.cos(clampedPitch)
		local newLook = Vector3.new(
			math.sin(clampedYaw) * cosPitch,
			math.sin(clampedPitch),
			math.cos(clampedYaw) * cosPitch
		)
		local headPos = camCF.Position
		-- Keep camera at head position, looking clamped direction
		-- Use CFrame.lookAt
		local newCF = CFrame.lookAt(headPos, headPos + newLook)
		camera.CFrame = newCF
	else
		-- Even if yaw within limit, clamp pitch to prevent looking too far up/down
		if math.abs(currentPitch) > maxPitchRad then
			local clampedPitch = math.clamp(currentPitch, -maxPitchRad, maxPitchRad)
			local cosPitch = math.cos(clampedPitch)
			local newLook = Vector3.new(
				math.sin(currentYaw) * cosPitch,
				math.sin(clampedPitch),
				math.cos(currentYaw) * cosPitch
			)
			local headPos = camCF.Position
			camera.CFrame = CFrame.lookAt(headPos, headPos + newLook)
		end
	end

	-- Keep HRP stable forward (prevent character spinning behind)
	if cfg.TargetCameraStability and cfg.TargetDisableAutoRotate then
		-- Keep HRP facing initial forward, but allow slight yaw within limit
		-- We set HRP CFrame to initial yaw clamped? For stability, keep initial yaw
		-- Only if HRP yaw deviates too much, snap back
		local hrpYaw = getYawFromLookVector(hrp.CFrame.LookVector)
		local hrpDelta = normalizeAngle(hrpYaw - (initialYaw or 0))
		if math.abs(hrpDelta) > math.rad(15) then
			-- Snap HRP back to initial forward (keep position, only rotation)
			local pos = hrp.Position
			-- Preserve Y
			local newHRPCF = CFrame.new(pos) * CFrame.Angles(0, (initialYaw or 0), 0)
			-- Lerp for smoothness? For now set directly
			-- Use :PivotTo? Use CFrame
			pcall(function()
				hrp.CFrame = newHRPCF
			end)
		end
	end
end

function TargetCameraService.SetIsTarget(newIsTarget: boolean)
	local cfg = getConfig()
	if not cfg.TargetCameraEnabled then
		return
	end

	if newIsTarget == isTarget then
		return
	end

	isTarget = newIsTarget

	if isTarget then
		print("[TargetCamera] Becoming Target - forcing restricted first-person")
		saveOriginalSettings()

		-- Store initial forward from HRP if available, else wait for character
		local hrp = getHRP()
		if hrp then
			initialForward = hrp.CFrame.LookVector
			initialYaw = getYawFromLookVector(initialForward)
		end

		applyFirstPerson()

		-- Bind render step to clamp rotation and keep stable
		pcall(function() RunService:UnbindFromRenderStep(renderBindName) end)
		RunService:BindToRenderStep(renderBindName, Enum.RenderPriority.Camera.Value + 1, clampCamera)

		-- Also heartbeat to enforce zoom (backup)
		if heartbeatConn then heartbeatConn:Disconnect() end
		heartbeatConn = RunService.Heartbeat:Connect(function()
			if isTarget then
				applyFirstPerson()
			end
		end)
	else
		print("[TargetCamera] No longer Target - restoring normal camera")
		if heartbeatConn then
			heartbeatConn:Disconnect()
			heartbeatConn = nil
		end
		restoreOriginalSettings()
	end
end

function TargetCameraService.IsTarget(): boolean
	return isTarget
end

function TargetCameraService.Restore()
	-- Safe restore for reset, death, disconnect, match completion
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
	pcall(function() RunService:UnbindFromRenderStep(renderBindName) end)
	restoreOriginalSettings()
end

function TargetCameraService.HandleCharacterAdded(character: Model)
	-- Handle reset, death: re-apply if still Target after respawn
	if not isTarget then return end
	local cfg = getConfig()
	task.wait(cfg.TargetRestoreDelay or 0.2)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Wait for HRP
		character:WaitForChild("HumanoidRootPart", 2)
		-- Re-save initial forward from new HRP
		local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			initialForward = hrp.CFrame.LookVector
			initialYaw = getYawFromLookVector(initialForward)
		end
		applyFirstPerson()
		-- Re-bind if needed
		pcall(function() RunService:UnbindFromRenderStep(renderBindName) end)
		RunService:BindToRenderStep(renderBindName, Enum.RenderPriority.Camera.Value + 1, clampCamera)
	end
end

function TargetCameraService.Init()
	print("[TargetCameraService] Initializing...")
	local player = getLocalPlayer()
	if not player then
		warn("[TargetCameraService] No LocalPlayer")
		return
	end

	-- Handle reset/death
	if characterAddedConn then characterAddedConn:Disconnect() end
	characterAddedConn = player.CharacterAdded:Connect(function(character)
		TargetCameraService.HandleCharacterAdded(character)
	end)

	-- If character already exists and we are Target (edge case on respawn), handle
	if player.Character then
		-- No-op until role set
	end

	print("[TargetCameraService] Initialized - waiting for Target role")
end

return TargetCameraService
