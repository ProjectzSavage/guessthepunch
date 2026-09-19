--!nonstrict
-- MatchStates.luau
-- Shared definition of match states (future use, kept for reference)
-- Purpose: No logic, only constants. Returns exactly 1 value.
-- Roblox Studio Destination: ReplicatedStorage > Shared > MatchStates (ModuleScript)

local MatchStates = {}

MatchStates.States = {
	WAITING_FOR_PLAYERS = "WAITING_FOR_PLAYERS",
	COUNTDOWN = "COUNTDOWN",
	PREPARING = "PREPARING",
	ROUND_START = "ROUND_START",
	PUNCH_SELECTION = "PUNCH_SELECTION",
	PUNCHER_SELECTED = "PUNCHER_SELECTED",
	POWER_GAUGE = "POWER_GAUGE",
	PUNCH_EXECUTING = "PUNCH_EXECUTING",
	GUESSING = "GUESSING",
	GUESS_RESULT = "GUESS_RESULT",
	TARGET_ELIMINATED = "TARGET_ELIMINATED",
	MATCH_ENDING = "MATCH_ENDING",
	LOBBY_RETURN = "LOBBY_RETURN",
}

MatchStates.List = {}
for _, v in pairs(MatchStates.States) do
	table.insert(MatchStates.List, v)
end

-- States where puncher identity must be hidden from Target
MatchStates.HiddenPuncherStates = {
	"ROUND_START",
	"PUNCH_SELECTION",
	"PUNCHER_SELECTED",
	"POWER_GAUGE",
	"PUNCH_EXECUTING",
	"GUESSING",
}

function MatchStates.IsPuncherHidden(state: string): boolean
	for _, s in ipairs(MatchStates.HiddenPuncherStates) do
		if s == state then
			return true
		end
	end
	return false
end

return MatchStates
