--!nonstrict
-- MatchStates.luau
-- Shared definition of match states for Guess the Puncher - Match Setup Phase
-- Purpose: Centralizes match state names for server-controlled states
-- Roblox Studio Destination: ReplicatedStorage > Shared > MatchStates (ModuleScript)

local MatchStates = {}

-- Requested states for match setup system:
-- Preparing, SelectingTarget, WaitingForPuncher, Punching, PowerGauge, KnockedOut, Guessing, Resolving, Eliminated, Finished
MatchStates.States = {
	PREPARING = "Preparing", -- Assigning players to unique match, moving to arena
	SELECTING_TARGET = "SelectingTarget", -- Server-side logic selecting initial Target
	WAITING_FOR_PUNCHER = "WaitingForPuncher", -- Waiting for puncher selection
	PUNCHING = "Punching", -- Puncher selected, preparation period
	POWER_GAUGE = "PowerGauge", -- Server-authoritative power gauge running (puncher locks gauge)
	KNOCKED_OUT = "KnockedOut", -- Target health reached 0: marked knocked out + PAUSED (full elimination flow is FUTURE)
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
	"PowerGauge",
	"KnockedOut",
	"Guessing",
	"Resolving",
	"Eliminated",
	"Finished",
}

-- Valid transitions (KnockedOut is a PAUSE marker: full elimination/role-transfer flow is FUTURE;
-- this phase only leaves KnockedOut via Finished (match end) or new Target selection)
MatchStates.Transitions = {
	Preparing = {"SelectingTarget", "Finished"}, -- can finish early if <2 players
	SelectingTarget = {"WaitingForPuncher", "Finished"},
	WaitingForPuncher = {"Punching", "Finished"},
	Punching = {"PowerGauge", "WaitingForPuncher", "Guessing", "Eliminated", "Finished"}, -- WaitingForPuncher revert if Puncher disconnects during prep
	PowerGauge = {"KnockedOut", "WaitingForPuncher", "Guessing", "Eliminated", "Finished"}, -- KnockedOut when Target health hits 0; WaitingForPuncher revert if Puncher disconnects
	KnockedOut = {"SelectingTarget", "WaitingForPuncher", "Finished"}, -- FUTURE: full elimination flow; now only match end / new Target
	Guessing = {"WaitingForPuncher", "Resolving", "Finished"}, -- turn system: after reveal -> next punch selection (Resolving is FUTURE)
	Resolving = {"SelectingTarget", "Eliminated", "Finished"},
	Eliminated = {"SelectingTarget", "Finished"},
	Finished = {}, -- terminal, will be cleaned up and returned to lobby
}

function MatchStates.CanTransition(from: string, to: string): boolean
	local allowed = MatchStates.Transitions[from]
	if not allowed then return false end
	for _, state in ipairs(allowed) do
		if state == to then return true end
	end
	return false
end

-- States where puncher identity must be hidden from Target (punch moment itself is the official reveal;
-- RE_PunchSequence may carry puncherUserId, but STATE payloads still never do)
MatchStates.HiddenPuncherStates = {
	"WaitingForPuncher",
	"Punching",
	"PowerGauge",
	"KnockedOut",
	"Guessing",
}

function MatchStates.IsPuncherHidden(state: string): boolean
	for _, s in ipairs(MatchStates.HiddenPuncherStates) do
		if s == state then return true end
	end
	return false
end

return MatchStates
