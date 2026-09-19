--!nonstrict
-- Constants.luau
-- Standalone constants, NO requires to avoid yellow underline errors
-- Purpose: Remote names, tags, queue capacities for easy access
-- Roblox Studio Destination: ReplicatedStorage > Shared > Constants (ModuleScript)
-- NOTE: This file does NOT require other modules to prevent "Module does not return exactly 1 value" errors
-- Import other modules directly if needed: require(Shared.Config), etc.

local Constants = {}

-- Queue capacities
Constants.QueueCapacities = {
	Slot2 = 2,
	Slot4 = 4,
	Slot6 = 6,
}
Constants.MinimumPlayers = 2

-- Remote names - queue system (implemented)
Constants.Remotes = {
	QueueJoinRequest = "RE_QueueJoinRequest",
	QueueLeaveRequest = "RE_QueueLeaveRequest",
	QueueStateUpdate = "RE_QueueStateUpdate",
	QueueCountdownUpdate = "RE_QueueCountdownUpdate",
	QueueLocked = "RE_QueueLocked",
	QueueStarted = "RE_QueueStarted",
	QueuePlayerLeft = "RE_QueuePlayerLeft",

	-- Future match remotes (reserved, auto-created but not used yet)
	MatchStart = "RE_MatchStart",
	MatchStateUpdate = "RE_MatchStateUpdate",
	PunchOpportunityOpen = "RE_PunchOpportunityOpen",
	PunchRequest = "RE_PunchRequest",
	PuncherSelected = "RE_PuncherSelected",
	PowerGaugeOpen = "RE_PowerGaugeOpen",
	PowerGaugeStopRequest = "RE_PowerGaugeStopRequest",
	PowerGaugeResult = "RE_PowerGaugeResult",
	DamageApplied = "RE_DamageApplied",
	GuessOpen = "RE_GuessOpen",
	GuessRequest = "RE_GuessRequest",
	GuessResult = "RE_GuessResult",
	TargetEliminated = "RE_TargetEliminated",
	MatchEnd = "RE_MatchEnd",
	CameraMode = "RE_CameraMode",
	AnimationPlay = "RE_AnimationPlay",
}

Constants.AllRemoteNames = {}
for _, name in pairs(Constants.Remotes) do
	table.insert(Constants.AllRemoteNames, name)
end

-- Tags
Constants.Tags = {
	QueueEntry = "QueueEntry",
	TargetStand = "TargetStand",
	PuncherStand = "PuncherStand",
	PlayerSpawn = "PlayerSpawn",
	QueueDisplay = "QueueDisplay",
}

return Constants
