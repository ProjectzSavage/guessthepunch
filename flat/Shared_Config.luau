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
-- FUTURE: Punch, Power, Guessing, Damage (not implemented yet, but centralized)
-- ============================================================================
Config.PunchSelectionDuration = 10
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
-- TELEPORT & ANTI-EXPLOIT
-- ============================================================================
Config.TeleportOffsetY = 3
Config.PuncherOffsetBehindTarget = 6
Config.PuncherInvisibleToTarget = true
Config.TouchDebounce = 1
Config.PunchRequestCooldown = 0.5
Config.DebugPrints = true

return Config
