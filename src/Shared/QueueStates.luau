--!nonstrict
-- QueueStates.luau
-- Shared definition of queue slot states
-- Purpose: Centralizes queue state names, no logic
-- Roblox Studio Destination: ReplicatedStorage > Shared > QueueStates (ModuleScript)

local QueueStates = {}

QueueStates.States = {
	WAITING = "WAITING", -- waiting for players, < full, < min or counting wait time
	COUNTDOWN_FULL = "COUNTDOWN_FULL", -- slot full, counting down to start
	COUNTDOWN_PARTIAL = "COUNTDOWN_PARTIAL", -- >=2 players but not full, after wait time, counting down
	LOCKED = "LOCKED", -- countdown finished, locked, no new joins, preparing handoff
	STARTING = "STARTING", -- handing off to MatchManager
	CANCELLED = "CANCELLED", -- cancelled because <2 players remain
}

QueueStates.List = {
	"WAITING",
	"COUNTDOWN_FULL",
	"COUNTDOWN_PARTIAL",
	"LOCKED",
	"STARTING",
	"CANCELLED",
}

function QueueStates.IsCountingDown(state: string): boolean
	return state == QueueStates.States.COUNTDOWN_FULL or state == QueueStates.States.COUNTDOWN_PARTIAL
end

function QueueStates.CanJoin(state: string): boolean
	-- Prevent new joins once queue starts (as requested)
	return state == QueueStates.States.WAITING
end

return QueueStates
