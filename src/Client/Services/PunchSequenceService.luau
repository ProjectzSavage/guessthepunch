--!nonstrict
-- PunchSequenceService.luau
-- Purpose: VISUAL punch sequence presentation ONLY (server-selected result drives everything)
-- Implements ONLY:
-- - Punch RAISE animation (Config.PunchAnimRaiseId - USER-PROVIDED: 94641587122659)
-- - HOLDING PUNCH animation (Config.PunchAnimPrepId - USER-PROVIDED: 98380541569272, looped through prep)
-- - PUNCH STRIKE animation (Config.PunchAnimPunchId - USER-PROVIDED: 81965585102785)
-- - Cartoon-style impact effect created entirely in CODE (expanding neon sphere, particle burst,
--   comic "POW!/BAM!/BOOM!/PERFECT!/MISS" billboard, light flash) - no asset IDs needed
-- - Placeholder sound ONLY because no real asset ID has been provided (Config.PunchSoundId = "rbxassetid://0")
-- - Small camera shake effect for the TARGET (magnitude by zone from Config.PunchCameraShakeByZone)
-- - DIFFERENT presentation per zone: Miss / Weak / Normal / Strong / Perfect
-- - Prevents repeated triggering (one sequence per match result, playing guard)
-- - Cleans ALL effects on match end, state revert, or player disconnect
-- The SERVER fires RE_PunchSequence with the SERVER-selected zone. Visuals NEVER determine the game result.
-- This client sends NOTHING (no remotes fired here).
-- Does NOT implement: damage (server does it), guessing, knockout flow, scoring, monetization, final animations, final GUI
-- Roblox Studio Destination: StarterPlayer > StarterPlayerScripts > GuessThePuncherClient > Services > PunchSequenceService (ModuleScript)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local PunchSequenceService = {}

local Config = nil
local player = Players.LocalPlayer

local remotes = {}

-- Presentation per zone (colors/text/effects). SERVER zone decides which row is used.
local ZONE_PRESENTATION = {
	Miss = {
		text = "MISS",
		color = Color3.fromRGB(190, 190, 190),
		impact = false, -- no contact, no impact burst
		particles = 0,
		effectSize = 0,
		soundPitch = 0.7,
		soundVolume = 0.2,
		flash = false,
	},
	Weak = {
		text = "POW!",
		color = Color3.fromRGB(255, 230, 90),
		impact = true,
		particles = 14,
		effectSize = 2.2,
		soundPitch = 1.15,
		soundVolume = 0.4,
		flash = false,
	},
	Normal = {
		text = "BAM!",
		color = Color3.fromRGB(255, 160, 60),
		impact = true,
		particles = 26,
		effectSize = 3.2,
		soundPitch = 1.0,
		soundVolume = 0.55,
		flash = false,
	},
	Strong = {
		text = "BOOM!",
		color = Color3.fromRGB(255, 90, 50),
		impact = true,
		particles = 42,
		effectSize = 4.4,
		soundPitch = 0.85,
		soundVolume = 0.7,
		flash = false,
	},
	Perfect = {
		text = "PERFECT!!",
		color = Color3.fromRGB(255, 215, 0),
		impact = true,
		particles = 70,
		effectSize = 6,
		soundPitch = 0.7,
		soundVolume = 0.9,
		flash = true, -- brief white screen flash for the Target
	},
}

local playing = false
local effectsFolder = nil -- client-local container for all effect instances (easy cleanup)
local shakeBindName = "PunchSequenceCameraShake"

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

-- ============================================================================
-- EFFECT PRIMITIVES (all created in code - no asset IDs)
-- ============================================================================

local function ensureEffectsFolder()
	if effectsFolder and effectsFolder.Parent then return effectsFolder end
	effectsFolder = Instance.new("Folder")
	effectsFolder.Name = "PunchSequenceEffects"
	effectsFolder.Parent = workspace
	return effectsFolder
end

local function destroyEffectsFolder()
	if effectsFolder then
		effectsFolder:Destroy()
		effectsFolder = nil
	end
end

-- Comic-style billboard text ("POW!", damage number, etc.)
local function spawnComicBillboard(position: Vector3, text: string, color: Color3, sizeScale: number)
	local folder = ensureEffectsFolder()
	local anchor = Instance.new("Part")
	anchor.Name = "ComicAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.5, 0.5, 0.5)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = folder

	local bb = Instance.new("BillboardGui")
	bb.Name = "ComicText"
	bb.Size = UDim2.fromScale(6 * sizeScale, 3 * sizeScale)
	bb.StudsOffset = Vector3.new(0, 2.5, 0)
	bb.AlwaysOnTop = true
	bb.Parent = anchor

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Text"
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBlack
	lbl.Text = text
	lbl.TextColor3 = color
	lbl.TextStrokeColor3 = Color3.fromRGB(30, 30, 30)
	lbl.TextStrokeTransparency = 0
	lbl.Rotation = math.random(-8, 8) -- cartoon tilt
	lbl.Parent = bb

	-- Pop-in then fade out
	lbl.TextTransparency = 1
	lbl.TextStrokeTransparency = 1
	TweenService:Create(lbl, TweenInfo.new(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextTransparency = 0, TextStrokeTransparency = 0 }):Play()
	task.delay(0.7, function()
		if bb and bb.Parent then
			TweenService:Create(lbl, TweenInfo.new(0.35), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
	Debris:AddItem(anchor, 1.2)
end

-- Cartoon impact: expanding neon sphere + particle burst + light flash
local function spawnImpactEffect(position: Vector3, pres)
	local folder = ensureEffectsFolder()

	local sphere = Instance.new("Part")
	sphere.Name = "ImpactSphere"
	sphere.Shape = Enum.PartType.Ball
	sphere.Material = Enum.Material.Neon
	sphere.Color = pres.color
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.CanTouch = false
	sphere.Transparency = 0.15
	sphere.Size = Vector3.new(1, 1, 1)
	sphere.CFrame = CFrame.new(position)
	sphere.Parent = folder
	TweenService:Create(sphere, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(pres.effectSize, pres.effectSize, pres.effectSize),
		Transparency = 1,
	}):Play()
	Debris:AddItem(sphere, 0.6)

	local ring = Instance.new("Part")
	ring.Name = "ImpactRing"
	ring.Shape = Enum.PartType.Ball
	ring.Material = Enum.Material.ForceField
	ring.Color = pres.color
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Transparency = 0.3
	ring.Size = Vector3.new(1, 1, 1)
	ring.CFrame = CFrame.new(position)
	ring.Parent = folder
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
		Size = Vector3.new(pres.effectSize * 1.6, pres.effectSize * 1.6, pres.effectSize * 1.6),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.7)

	local emitterHost = Instance.new("Part")
	emitterHost.Name = "ParticleHost"
	emitterHost.Anchored = true
	emitterHost.CanCollide = false
	emitterHost.CanQuery = false
	emitterHost.CanTouch = false
	emitterHost.Transparency = 1
	emitterHost.Size = Vector3.new(0.5, 0.5, 0.5)
	emitterHost.CFrame = CFrame.new(position)
	emitterHost.Parent = folder

	local pe = Instance.new("ParticleEmitter")
	pe.Name = "ImpactBurst"
	pe.Color = ColorSequence.new(pres.color, Color3.fromRGB(255, 255, 255))
	pe.LightEmission = 1
	pe.Speed = NumberRange.new(8, 18)
	pe.Lifetime = NumberRange.new(0.25, 0.5)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	pe.Rate = 0
	pe.Parent = emitterHost
	if pres.particles and pres.particles > 0 then
		pe:Emit(pres.particles)
	end
	Debris:AddItem(emitterHost, 1)

	local light = Instance.new("PointLight")
	light.Name = "ImpactFlash"
	light.Color = pres.color
	light.Brightness = 6
	light.Range = pres.effectSize * 3
	light.Parent = emitterHost
	TweenService:Create(light, TweenInfo.new(0.3), { Brightness = 0 }):Play()
end

-- PLACEHOLDER SOUND - played ONLY because no real asset ID has been provided.
-- Config.PunchSoundId = "rbxassetid://0" is a deliberately marked placeholder; it will not
-- produce audio until a real asset ID is supplied. Pitch/volume already vary by zone so the
-- presentation difference is visible in Output (PlaybackSpeed) even before a real sound exists.
local function playPlaceholderSound(position: Vector3, pres)
	local id = Config and Config.PunchSoundId or "rbxassetid://0"
	local folder = ensureEffectsFolder()
	local host = Instance.new("Part")
	host.Name = "SoundHost"
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.Transparency = 1
	host.Size = Vector3.new(0.5, 0.5, 0.5)
	host.CFrame = CFrame.new(position)
	host.Parent = folder

	local s = Instance.new("Sound")
	s.Name = "PunchSound_PLACEHOLDER"
	s.SoundId = id -- PLACEHOLDER (see Config comment)
	s.PlaybackSpeed = pres.soundPitch
	s.Volume = pres.soundVolume
	s.Parent = host
	if id == "rbxassetid://0" then
		print("[PunchSequence] Sound placeholder (no real asset ID provided): would play pitch=" .. tostring(pres.soundPitch) .. " volume=" .. tostring(pres.soundVolume))
	end
	pcall(function()
		s:Play()
	end)
	Debris:AddItem(host, 2)
end

-- ANIMATIONS - USER-PROVIDED real asset IDs from Config (punch raise / holding punch / punch strike).
-- Loaded in pcall with a warn on failure (a bad/unpublished ID will not break the sequence);
-- the code-created impact/billboard effects always play regardless.
local function playAnimation(character: Model?, animId: string, label: string, looped: boolean?)
	if not character then return end
	if not animId or animId == "rbxassetid://0" then
		print("[PunchSequence] Animation " .. label .. " skipped (placeholder id, no real asset provided)")
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local anim = Instance.new("Animation")
	anim.Name = "PunchSequence_" .. label
	anim.AnimationId = animId -- USER-PROVIDED asset ID (see Config)
	local track
	local ok, err = pcall(function()
		track = animator:LoadAnimation(anim)
	end)
	if not ok or not track then
		warn("[PunchSequence] Failed to load " .. label .. " animation " .. animId .. ": " .. tostring(err))
		return
	end
	track.Looped = looped == true
	pcall(function()
		track:Play()
	end)
end

-- ============================================================================
-- TARGET CAMERA SHAKE (small, presentation only; binds AFTER camera so it stacks
-- safely with the Target first-person camera from TargetCameraService)
-- ============================================================================

local function stopCameraShake()
	pcall(function()
		RunService:UnbindFromRenderStep(shakeBindName)
	end)
end

local function playCameraShake(intensity: number, duration: number)
	if intensity <= 0 then return end
	stopCameraShake()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local elapsed = 0
	RunService:BindToRenderStep(shakeBindName, Enum.RenderPriority.Camera.Value + 2, function(dt)
		elapsed += dt
		if elapsed >= duration or not workspace.CurrentCamera then
			stopCameraShake()
			return
		end
		local decay = 1 - (elapsed / duration)
		local mag = intensity * decay
		local offset = Vector3.new(
			(math.random() - 0.5) * mag,
			(math.random() - 0.5) * mag,
			(math.random() - 0.5) * mag
		)
		workspace.CurrentCamera.CFrame = workspace.CurrentCamera.CFrame * CFrame.new(offset)
	end)
end

-- Brief white screen flash (Perfect only) + KO marker text
local function playScreenFlash(duration: number)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "PunchSequenceFlash"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60
	gui.IgnoreGuiInset = true
	gui.Parent = playerGui
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = gui
	TweenService:Create(frame, TweenInfo.new(0.06), { BackgroundTransparency = 0.25 }):Play()
	task.delay(0.08, function()
		if gui.Parent then
			TweenService:Create(frame, TweenInfo.new(duration), { BackgroundTransparency = 1 }):Play()
		end
	end)
	Debris:AddItem(gui, duration + 0.5)
end

local function playKnockedOutBanner()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "PunchSequenceKO"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 61
	gui.Parent = playerGui
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 0.12)
	lbl.Position = UDim2.fromScale(0, 0.4)
	lbl.BackgroundTransparency = 1
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBlack
	lbl.Text = "TARGET DOWN!"
	lbl.TextColor3 = Color3.fromRGB(255, 70, 70)
	lbl.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
	lbl.TextStrokeTransparency = 0
	lbl.Rotation = -4
	lbl.Parent = gui
	Debris:AddItem(gui, 2.5)
end

-- ============================================================================
-- SEQUENCE FLOW
-- ============================================================================

local function cleanupEffects(reason: string)
	stopCameraShake()
	destroyEffectsFolder()
	playing = false
	print("[PunchSequence] Effects cleaned: " .. reason)
end

function PunchSequenceService.HandleMatchEnd()
	cleanupEffects("match ended")
end

function PunchSequenceService.UpdateState(matchId: string?, role: string?, state: string?)
	-- If state leaves the punch flow (e.g. Puncher disconnected -> WaitingForPuncher), clean effects
	if playing and state and state ~= "PowerGauge" and state ~= "KnockedOut" then
		cleanupEffects("state changed to " .. tostring(state))
	end
end

-- Server fires: (matchId, zone, puncherUserId, targetUserId, timedOut) at the PUNCH MOMENT.
local function onPunchSequence(matchId: string, zone: string, puncherUserId: number?, targetUserId: number?, timedOut: boolean)
	loadShared()
	if not Config or not Config.PunchSequenceEnabled then return end

	-- Prevent repeated triggering (one sequence at a time; duplicate events for same match ignored)
	if playing then
		print("[PunchSequence] Sequence already playing - duplicate prevented")
		return
	end
	playing = true

	local pres = ZONE_PRESENTATION[zone] or ZONE_PRESENTATION.Normal
	local timedOut = timedOut == true
	print(string.format("[PunchSequence] Server zone=%s timedOut=%s -> presentation: %s", tostring(zone), tostring(timedOut), pres.text))

	local puncher = puncherUserId and Players:GetPlayerByUserId(puncherUserId) or nil
	local target = targetUserId and Players:GetPlayerByUserId(targetUserId) or nil
	local puncherChar = puncher and puncher.Character or nil
	local targetChar = target and target.Character or nil
	local targetHRP = targetChar and targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	local puncherHRP = puncherChar and puncherChar:FindFirstChild("HumanoidRootPart") :: BasePart?

	-- Impact position: slightly toward the puncher from the Target (between them)
	local impactPos
	if targetHRP and puncherHRP then
		impactPos = targetHRP.Position + (puncherHRP.Position - targetHRP.Position).Unit * 1.5
	elseif targetHRP then
		impactPos = targetHRP.Position
	elseif puncherHRP then
		impactPos = puncherHRP.Position
	else
		impactPos = Vector3.new(0, 10, 0)
	end

	local prepTime = (Config and Config.PunchSequencePrepTime) or 0.6
	local contactTime = (Config and Config.PunchSequenceContactTime) or 0.35

	if timedOut then
		-- Timed-out Miss: puncher never punched - NO animations, just grey MISS text near the puncher
		print("[PunchSequence] Timed-out Miss presentation - no punch animations, no impact, no shake")
		spawnComicBillboard(puncherHRP and puncherHRP.Position or impactPos, pres.text, pres.color, 1)
		task.delay(1.0, function()
			if playing then
				cleanupEffects("miss finished")
			end
		end)
		return
	end

	-- 1) PREPARATION animations on the puncher (USER-PROVIDED IDs):
	--    punch raise (windup) immediately, then holding punch (looped hold through the prep window)
	playAnimation(puncherChar, (Config and Config.PunchAnimRaiseId) or "rbxassetid://0", "Raise", false)
	task.delay(0.15, function()
		if not playing then return end
		playAnimation(puncherChar, (Config and Config.PunchAnimPrepId) or "rbxassetid://0", "Hold", true)
	end)
	if pres.impact then
		spawnComicBillboard(puncherHRP and puncherHRP.Position or impactPos, "...", Color3.fromRGB(255, 255, 255), 0.6)
	end

	-- 2) PUNCH strike animation (at prep end, aligned with the server damage window:
	--    the server fires immediately and applies damage at prep+contact - same clock math here)
	task.delay(prepTime, function()
		if not playing then return end
		playAnimation(puncherChar, (Config and Config.PunchAnimPunchId) or "rbxassetid://0", "Punch", false)

		-- 3) IMPACT (after contact delay): cartoon effect + sound + Target camera shake
		task.delay(contactTime, function()
			if not playing then return end
			if pres.impact then
				spawnImpactEffect(impactPos, pres)
				spawnComicBillboard(impactPos, pres.text, pres.color, 1 + (pres.effectSize / 8))
				playPlaceholderSound(impactPos, pres)
			else
				-- Miss presentation: grey "MISS" text only, no impact, no shake, no flash
				local missPos = puncherHRP and puncherHRP.Position or impactPos
				spawnComicBillboard(missPos, pres.text, pres.color, 1)
				print("[PunchSequence] Miss presentation - no impact effect (no contact)")
			end

			-- Small camera effect for the TARGET only (magnitude by zone)
			if targetUserId and player.UserId == targetUserId then
				local shakeTable = (Config and Config.PunchCameraShakeByZone) or {}
				local intensity = shakeTable[zone] or 0.3
				playCameraShake(intensity, 0.35 + intensity * 0.3)
				print("[PunchSequence] Target camera shake: intensity=" .. tostring(intensity))
				if pres.flash then
					playScreenFlash(0.3)
				end
			end

			-- KO marker if health reached 0 (server marks KnockedOut; presentation banner)
			if zone == "Perfect" and (Config and Config.PerfectIsInstantKO ~= false) then
				task.delay(0.4, function()
					if playing then
						playKnockedOutBanner()
					end
				end)
			end

			-- Effects are short-lived (Debris) - release the playing guard shortly after
			task.delay(1.2, function()
				if playing then
					cleanupEffects("sequence finished")
				end
			end)
		end)
	end)

	-- Safety: hard cleanup if something went wrong (never leave effects behind)
	task.delay((prepTime + contactTime + 6), function()
		if playing then
			cleanupEffects("safety timeout")
		end
	end)
end

function PunchSequenceService.Init()
	loadShared()
	print("[PunchSequenceService] Initializing...")

	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotesFolder then
		warn("[PunchSequenceService] Missing Remotes folder")
		return
	end

	remotes.PunchSequence = remotesFolder:WaitForChild("RE_PunchSequence", 10)
	remotes.TargetHealthUpdate = remotesFolder:FindFirstChild("RE_TargetHealthUpdate")

	if remotes.PunchSequence then
		remotes.PunchSequence.OnClientEvent:Connect(function(matchId, zone, puncherUserId, targetUserId, timedOut)
			onPunchSequence(matchId, zone, puncherUserId, targetUserId, timedOut)
		end)
		print("[PunchSequenceService] Listening to RE_PunchSequence")
	else
		warn("[PunchSequenceService] RE_PunchSequence not found - punch sequence disabled")
	end

	if remotes.TargetHealthUpdate then
		remotes.TargetHealthUpdate.OnClientEvent:Connect(function(matchId, targetUserId, health, maxHealth, lastDamage, lastZone)
			print(string.format("[Health] match=%s Target=%d health=%d/%d (last: -%d %s)", tostring(matchId), targetUserId or -1, health or 0, maxHealth or 100, lastDamage or 0, tostring(lastZone)))
			if health ~= nil and health <= 0 and lastZone ~= "Reset" then
				print("[Health] Target at 0 - server marks KnockedOut (paused)")
			end
		end)
	end

	-- Clean effects if the LOCAL player disconnects/respawns mid-sequence
	player.CharacterAdded:Connect(function()
		if playing then
			cleanupEffects("local character respawn")
		end
	end)

	print("[PunchSequenceService] Ready - presentation only, server zone decides everything")
end

return PunchSequenceService
