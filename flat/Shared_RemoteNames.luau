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

-- Future match remotes (not implemented yet, but reserved)
RemoteNames.Match = {
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

-- Combined list for auto-creation
RemoteNames.All = {}
for _, name in pairs(RemoteNames.Queue) do
	table.insert(RemoteNames.All, name)
end
for _, name in pairs(RemoteNames.Match) do
	table.insert(RemoteNames.All, name)
end

return RemoteNames
