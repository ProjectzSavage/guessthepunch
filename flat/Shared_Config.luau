--!nonstrict
-- Config.luau - Centralized configuration for Queue + Match Setup
-- Purpose: All tunable numbers, easy to adjust. No logic.
-- Roblox Studio Destination: ReplicatedStorage > Shared > Config (ModuleScript)

local Config = {}

-- ============================================================================
-- QUEUE CAPACITIES (2, 4, 6)
-- ============================================================================
Config.QueueCapacities = {
	Slot2 = 2,
	Slot4 = 4,
	Slot6 = 6,
}
Config.QueueCapacityList = {2, 4, 6}
Config.MinimumPlayers = 2 -- minimum to start queue

-- ============================================================================
-- QUEUE COUNTDOWNS & TIMINGS
-- ============================================================================
Config.QueueFullCountdown = 5 -- when slot full, countdown before match
Config.QueuePartialWaitTime = 30 -- wait before starting with >=2 but not full
Config.QueuePartialCountdown = 5
Config.QueueCountdownDuration = 10 -- fallback

-- ============================================================================
-- MATCH SETUP (implemented in this phase)
-- ============================================================================
Config.MatchPreparationTime = 3 -- time in Preparing state (teleporting to arena)
Config.MatchMinPlayers = 2 -- end match safely if fewer than 2 active players remain
Config.SelectingTargetDuration = 2 -- time in SelectingTarget state
Config.ArenaFolderName = "MatchArenas"
Config.LobbyFolderName = "Lobby"
Config.MatchSlotsFolderName = "MatchSlots"
Config.LobbyReturnDelay = 5 -- delay before returning to lobby after Finished

-- Arena mapping: Slot2 -> Arena2, Slot4 -> Arena4, Slot6 -> Arena6
Config.ArenaBySlot = {
	Slot2 = "Arena2",
	Slot4 = "Arena4",
	Slot6 = "Arena6",
}

-- ============================================================================
-- PUNCHER SELECTION (Phase: Puncher selection only)
-- ============================================================================
Config.PunchSelectionDuration = 15 -- max time to wait for someone to request punch in WaitingForPuncher
Config.PuncherPreparationTime = 3 -- short preparation period after Puncher selected, before future power gauge
Config.PuncherMaxDistanceFromPosition = 4 -- max distance Puncher can move from controlled behind position during preparation
Config.PuncherEnforceInterval = 0.2 -- how often server enforces Puncher position
Config.PunchRequestCooldown = 0.5 -- rate limit per player for punch requests (anti-spam)
Config.PunchSpamThreshold = 3 -- max requests within window before temp block
Config.PunchSpamWindow = 2 -- seconds window for spam detection

-- ============================================================================
-- POWER GAUGE (Phase: server-authoritative Puncher power gauge ONLY - no damage)
-- ============================================================================
Config.PowerGaugeEnabled = true
Config.PowerGaugeDuration = 5 -- total server-controlled lock window in seconds (server clock)
Config.PowerGaugeSweepDuration = 1.25 -- seconds for ONE pass 0 -> 1 (needle reverses at ends, ping-pong)
-- Needle position (0..1) IS the power level. Zone = position band (lower bounds, easy to adjust):
Config.PowerGaugeZoneThresholds = {
	Weak = 0, -- everything below Normal
	Normal = 0.40,
	Strong = 0.70,
	Perfect = 0.90,
	-- Miss is NOT on the track: it is the timeout / too-late zone only
}
Config.PowerGaugeLockLateGrace = 0.15 -- seconds after window end that a lock still counts (network latency tolerance)
Config.PowerGaugeLockCooldown = 0.25 -- min seconds between lock requests (anti-spam, server-side)
Config.PowerGaugeMaxLockRequests = 5 -- max lock requests per gauge before further requests rejected (anti-spam)
Config.PowerGaugeShowDebugDisplay = true -- client builds a minimal on-screen gauge for testing (final GUI comes later)
Config.PowerGaugeLockKey = Enum.KeyCode.E -- client lock input for testing (no final GUI yet)

-- ============================================================================
-- GUESSING & TURN SYSTEM (Phase: Target guessing + turn connection ONLY)
-- ============================================================================
Config.GuessingEnabled = true
Config.GuessingDuration = 15 -- seconds the Target has to submit ONE guess (countdown; timeout = incorrect)
Config.GuessRevealPause = 1.5 -- seconds pause after reveal before the next punch selection starts
Config.GuessResultMissPause = 1.0 -- seconds pause after gauge-timeout Miss before a new punch selection starts

-- ============================================================================
-- KNOCKOUT, ELIMINATION & MATCH END (Phase: knockout/elimination + match end/winner ONLY)
-- ============================================================================
Config.KnockoutDuration = 3 -- seconds of knockout presentation before spectator teleport / next turn
Config.SpectatorAutoPlatformHeight = 25 -- Y offset above arena when auto-creating a spectator platform
Config.SpectatorPlatformSize = 24 -- studs; auto-created spectator platform size
-- Optional manual object per arena (Workspace.MatchArenas.ArenaX.SpectatorArea, BasePart,
-- Anchored true, CanCollide true): if present it is used; otherwise the server AUTO-CREATES
-- a floating platform above the arena.
-- Config.LobbyReturnDelay (MATCH SETUP section above) controls the lobby return after match end.

Config.StartingHealth = 100
Config.Damage = {
	Miss = 0,
	Weak = 10,
	Normal = 25,
	Strong = 50,
	Perfect = 100,
}
Config.WeakDamage = 10
Config.NormalDamage = 25
Config.StrongDamage = 50
Config.PerfectDamage = 100
Config.MissDamage = 0
Config.PerfectIsInstantKO = true

-- ============================================================================
-- PUNCH SEQUENCE PRESENTATION (Phase: visual punch sequence ONLY - visuals never determine game result)
-- ============================================================================
Config.PunchSequenceEnabled = true
Config.PunchSequencePrepTime = 0.6 -- seconds: puncher preparation placeholder before punch (server-scheduled)
Config.PunchSequenceContactTime = 0.35 -- seconds: punch start -> impact; SERVER applies damage at contact (server clock)
-- ANIMATION ASSETS (USER-PROVIDED real IDs - no longer placeholders):
Config.PunchAnimRaiseId = "rbxassetid://94641587122659" -- USER-PROVIDED: punch raise (windup)
Config.PunchAnimPrepId = "rbxassetid://98380541569272" -- USER-PROVIDED: holding punch (hold/aim)
Config.PunchAnimPunchId = "rbxassetid://81965585102785" -- USER-PROVIDED: punch strike
-- Sound remains a clearly-marked PLACEHOLDER - the user has NOT provided a sound asset ID yet.
Config.PunchSoundId = "rbxassetid://0" -- PLACEHOLDER impact sound (replace ONLY when user provides a real ID)
-- Camera shake intensity for the TARGET by zone (0 = none). Presentation only.
Config.PunchCameraShakeByZone = {
	Miss = 0,
	Weak = 0.15,
	Normal = 0.3,
	Strong = 0.55,
	Perfect = 0.9,
}

-- ============================================================================
-- TARGET CAMERA & VISIBILITY (Phase: Target camera and visibility system only)
-- ============================================================================
Config.TargetCameraEnabled = true
Config.TargetFirstPersonZoom = 0.5 -- force first-person zoom distance
Config.TargetMaxYawDegrees = 65 -- max left/right rotation from initial forward (prevents inspecting behind)
Config.TargetMaxPitchDegrees = 30 -- max up/down pitch
Config.TargetCameraStability = true -- keep camera stable forward
Config.TargetDisableAutoRotate = true -- prevent character spinning to look behind
Config.TargetHideBehindPlayers = true -- anti-cheat: hide players behind Target locally
Config.TargetBehindDotThreshold = -0.1 -- dot product < this means behind ( -1 = directly behind)
Config.TargetVisibilityCheckInterval = 0.15 -- seconds between visibility updates
Config.TargetRestoreDelay = 0.2 -- delay after respawn before re-applying camera

-- ============================================================================
-- TELEPORT & ANTI-EXPLOIT
-- ============================================================================
Config.TeleportOffsetY = 3
Config.PuncherOffsetBehindTarget = 6
Config.PuncherInvisibleToTarget = true -- server controls, client presentation only
Config.TouchDebounce = 1
Config.PunchRequestCooldown = 0.5
Config.DebugPrints = true

return Config
