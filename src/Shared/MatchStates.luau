--!nonstrict
-- MatchStates.luau
-- Shared definition of match states for Guess the Puncher - Match Setup Phase
-- Purpose: Centralizes match state names for server-controlled states
-- Roblox Studio Destination: ReplicatedStorage > Shared > MatchStates (ModuleScript)

local MatchStates = {}

-- Requested states for match setup system:
-- Preparing, SelectingTarget, WaitingForPuncher, Punching, Guessing, Resolving, Eliminated, Finished
MatchStates.States = {
	PREPARING = "Preparing", -- Assigning players to unique match, moving to arena
	SELECTING_TARGET = "SelectingTarget", -- Server-side logic selecting initial Target
	WAITING_FOR_PUNCHER = "WaitingForPuncher", -- Waiting for puncher selection (future)
	PUNCHING = "Punching", -- Future: punching phase
	GUESSING = "Guessing", -- Future: guessing phase
	RESOLVING = "Resolving", -- Future: resolving guess result
	ELIMINATED = "Eliminated", -- Player eliminated
	FINISHED = "Finished", -- Match ended safely

	-- Legacy aliases for backward compatibility
	WAITING_FOR_PLAYERS = "WaitingForPlayers",
	COUNTDOWN = "Countdown",
	ROUND_START = "RoundStart",
	PUNCH_SELECTION = "PunchSelection",
	PUNCHER_SELECTED = "PuncherSelected",
	POWER_GAUGE = "PowerGauge",
	PUNCH_EXECUTING = "PunchExecuting",
	GUESS_RESULT = "GuessResult",
	TARGET_ELIMINATED = "TargetEliminated",
	MATCH_ENDING = "MatchEnding",
	LOBBY_RETURN = "LobbyReturn",
}

-- Ordered list for debugging
MatchStates.List = {
	"Preparing",
	"SelectingTarget",
	"WaitingForPuncher",
	"Punching",
	"Guessing",
	"Resolving",
	"Eliminated",
	"Finished",
}

-- Valid transitions for match setup phase
MatchStates.Transitions = {
	Preparing = {"SelectingTarget", "Finished"}, -- can finish early if <2 players
	SelectingTarget = {"WaitingForPuncher", "Finished"},
	WaitingForPuncher = {"Punching", "Finished"}, -- future: will go to Punching
	Punching = {"Guessing", "Eliminated", "Finished"},
	Guessing = {"Resolving", "Finished"},
	Resolving = {"SelectingTarget", "Eliminated", "Finished"},
	Eliminated = {"SelectingTarget", "Finished"},
	Finished = {}, -- terminal, will be cleaned up and return to lobby
}

function MatchStates.CanTransition(from: string, to: string): boolean
	local allowed = MatchStates.Transitions[from]
	if not allowed then return false end
	for _, state in ipairs(allowed) do
		if state == to then return true end
	end
	return false
end

-- States where puncher identity must be hidden from Target (future)
MatchStates.HiddenPuncherStates = {
	"WaitingForPuncher",
	"Punching",
	"Guessing",
}

function MatchStates.IsPuncherHidden(state: string): boolean
	for _, s in ipairs(MatchStates.HiddenPuncherStates) do
		if s == state then return true end
	end
	return false
end

return MatchStates
