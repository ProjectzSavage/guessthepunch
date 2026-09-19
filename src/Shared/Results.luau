--!nonstrict
-- Results.luau
-- Shared definitions for guess results and match results (future use)
-- Roblox Studio Destination: ReplicatedStorage > Shared > Results (ModuleScript)

local Results = {}

Results.GuessResults = {
	CORRECT = "Correct",
	WRONG = "Wrong",
	TIMEOUT = "Timeout",
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
