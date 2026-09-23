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
-- FUTURE: Power, Damage, Guessing, Knockout, Scoring (not implemented yet, but centralized)
-- ============================================================================
Config.PowerGaugeDuration = 5
Config.GuessingDuration = 15
Config.KnockoutDuration = 3

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
