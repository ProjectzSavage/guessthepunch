--!nonstrict
-- Results.luau
-- Shared definitions for guess results and match results
-- Roblox Studio Destination: ReplicatedStorage > Shared > Results (ModuleScript)

local Results = {}

-- Guess phase results (produced for later systems - exact values as specified):
Results.GuessResults = {
	CORRECT = "CorrectGuess", -- Target guessed the Puncher correctly
	WRONG = "WrongGuess", -- Target guessed a non-Puncher
	TIMEOUT = "GuessTimeout", -- Target did not submit in time (treated as incorrect)
	INVALID = "InvalidGuess", -- Rejected/invalid guess attempt (not consumed, for logging/later systems)
}

Results.MatchResults = {
	WINNER = "Winner",
	ELIMINATED = "Eliminated",
	DRAW = "Draw",
	CANCELLED = "Cancelled",
}

Results.EliminationReasons = {
	PERFECT_PUNCH = "PerfectPunch",
	DAMAGE_KO = "DamageKO",
	LEFT_GAME = "LeftGame",
}

return Results
