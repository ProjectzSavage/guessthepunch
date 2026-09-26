--!nonstrict
-- RemoteNames.luau
-- Central list of RemoteEvent names for queue system + future match
-- Purpose: No requires, standalone, returns exactly 1 value
-- Roblox Studio Destination: ReplicatedStorage > Shared > RemoteNames (ModuleScript)

local RemoteNames = {}

-- Queue system remotes (implemented in this phase)
RemoteNames.Queue = {
	JoinRequest = "RE_QueueJoinRequest", -- Client -> Server (slotId)
	LeaveRequest = "RE_QueueLeaveRequest", -- Client -> Server ()
	StateUpdate = "RE_QueueStateUpdate", -- Server -> All (slotId, occupancy, max, state, countdown, locked)
	CountdownUpdate = "RE_QueueCountdownUpdate", -- Server -> Slot players (slotId, timeLeft)
	Locked = "RE_QueueLocked", -- Server -> All (slotId, locked)
	Started = "RE_QueueStarted", -- Server -> Slot players (slotId, players) - handoff to MatchManager
	PlayerLeft = "RE_QueuePlayerLeft", -- Server -> All (slotId, userId)
}

-- Future match remotes (Puncher selection phase + future)
RemoteNames.Match = {
	MatchStart = "RE_MatchStart",
	MatchStateUpdate = "RE_MatchStateUpdate",
	MatchEnd = "RE_MatchEnd",
	RoleAssigned = "RE_RoleAssigned",
	TargetSelected = "RE_TargetSelected",
	-- Puncher selection phase (implemented in this phase)
	PunchOpportunityOpen = "RE_PunchOpportunityOpen",
	PunchRequest = "RE_PunchRequest", -- Client -> Server, only punch request, no winner/timestamp/damage/power/role
	PunchRejected = "RE_PunchRejected", -- Server -> Client, reason for rejection
	PuncherSelected = "RE_PuncherSelected", -- Server -> Client, filtered (Target does NOT get puncherUserId before reveal)
	PuncherPreparation = "RE_PuncherPreparation", -- Server -> Client, preparation countdown
	-- Power gauge phase (implemented in this phase)
	PowerGaugeOpen = "RE_PowerGaugeOpen", -- Server -> PUNCHER ONLY (matchId, startServerTime, duration, sweepDuration); startServerTime is server-controlled
	PowerGaugeStopRequest = "RE_PowerGaugeStopRequest", -- Client -> Server LOCK request: matchId ONLY. No power value, no zone claim, no timestamp
	PowerGaugeRejected = "RE_PowerGaugeRejected", -- Server -> Client (matchId, reason) e.g. Already locked / Too early / Too late / Not the Puncher / Rate limited
	PowerGaugeResult = "RE_PowerGaugeResult", -- Server -> PUNCHER ONLY (matchId, zone, position, timedOut); zone computed by SERVER
	-- Punch sequence + Target health (implemented in this phase)
	PunchSequence = "RE_PunchSequence", -- Server -> ALL match clients at the punch moment (matchId, zone, puncherUserId, targetUserId, timedOut); punch moment = official reveal; SERVER zone determines presentation, visuals never determine result
	TargetHealthUpdate = "RE_TargetHealthUpdate", -- Server -> ALL match clients (matchId, targetUserId, health, maxHealth, lastDamage, lastZone); match health is SERVER-INTERNAL and separate from Roblox Humanoid health
	-- Guessing + turn system (implemented in this phase)
	GuessOpen = "RE_GuessOpen", -- Server -> TARGET ONLY (matchId, eligibleUserIds, timeLeft); contains NO puncher info; rebroadcast for countdown/eligibility updates
	GuessRequest = "RE_GuessRequest", -- Client -> Server: Target ONLY sends (matchId, guessedUserId); server validates, one guess allowed
	GuessRejected = "RE_GuessRejected", -- Server -> Target (matchId, reason) e.g. duplicate / invalid / too early / not Target
	GuessResult = "RE_GuessResult", -- Server -> ALL match clients (matchId, result, guessedUserId, puncherUserId) = OFFICIAL PUNCHER REVEAL after submission or timeout; results: CorrectGuess / WrongGuess / GuessTimeout / InvalidGuess
	-- Knockout/elimination + match end (implemented in this phase)
	PlayerEliminated = "RE_PlayerEliminated", -- Server -> ALL match clients (matchId, eliminatedUserId, reason); KO presentation + the eliminated player switches to spectator
	MatchResult = "RE_MatchResult", -- Server -> ALL match clients (matchId, matchResult, winnerUserId, reason); matchResult: Winner / Cancelled; victory/defeat presentation
	SpectatorUpdate = "RE_SpectatorUpdate", -- Server -> SPECTATOR ONLY (matchId, activeUserIds); watch list for the spectator camera; contains NO puncher identity or roles
	-- Future: damage application to character, scoring (not implemented yet)
	DamageApplied = "RE_DamageApplied",
	TargetEliminated = "RE_TargetEliminated",
	CameraMode = "RE_CameraMode",
	AnimationPlay = "RE_AnimationPlay",
}

-- Combined list for auto-creation
RemoteNames.All = {}
for _, name in pairs(RemoteNames.Queue) do
	table.insert(RemoteNames.All, name)
end
for _, name in pairs(RemoteNames.Match) do
	table.insert(RemoteNames.All, name)
end

return RemoteNames
