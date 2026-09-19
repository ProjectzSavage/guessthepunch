--!nonstrict
-- Config.luau
-- Centralized configuration for Guess the Puncher - Queue & Future Match
-- Purpose: All tunable numbers, easy to adjust. No logic, no secrets.
-- Roblox Studio Destination: ReplicatedStorage > Shared > Config (ModuleScript)

local Config = {}

-- ============================================================================
-- QUEUE CAPACITIES (2, 4, 6) as requested
-- ============================================================================
Config.QueueCapacities = {
	Slot2 = 2,
	Slot4 = 4,
	Slot6 = 6,
}
Config.QueueCapacityList = {2, 4, 6}

-- Minimum players to start countdown / waiting logic
Config.MinimumPlayers = 2

-- ============================================================================
-- QUEUE COUNTDOWNS & TIMINGS (as requested)
-- ============================================================================

-- Countdown when slot is full (start when full)
Config.QueueFullCountdown = 5 -- seconds after full before starting match

-- Countdown when slot has >=2 but not full, after waiting period
Config.QueuePartialWaitTime = 30 -- seconds to wait before starting with >=2 players if not full
Config.QueuePartialCountdown = 5 -- countdown after wait time expires

-- General queue countdown (used for display)
Config.QueueCountdownDuration = 10 -- fallback

-- Match preparation time (after queue finishes, before handoff to MatchManager)
Config.MatchPreparationTime = 3

-- Punch-selection duration (future)
Config.PunchSelectionDuration = 10

-- Power-gauge duration (future)
Config.PowerGaugeDuration = 5

-- Guessing duration (future)
Config.GuessingDuration = 15

-- Knockout duration (future)
Config.KnockoutDuration = 3

-- Lobby return delay (future)
Config.LobbyReturnDelay = 5

-- ============================================================================
-- HEALTH & DAMAGE (future, but centralized as requested)
-- ============================================================================
Config.StartingHealth = 100

Config.Damage = {
	Miss = 0,
	Weak = 10,
	Normal = 25,
	Strong = 50,
	Perfect = 100, -- instant KO
}

-- Individual easy-access aliases as requested
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

-- Debug
Config.DebugPrints = true

return Config
