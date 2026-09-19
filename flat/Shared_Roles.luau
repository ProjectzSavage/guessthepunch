--!nonstrict
-- Roles.luau
-- Shared definition of player roles for Guess the Puncher - Match Setup Phase
-- Purpose: Centralizes role names, no logic
-- Roblox Studio Destination: ReplicatedStorage > Shared > Roles (ModuleScript)

local Roles = {}

Roles.Roles = {
	NONE = "None", -- not in any slot/match
	LOBBY = "Lobby", -- in lobby
	QUEUED = "Queued", -- in queue slot
	TARGET = "Target", -- initial Target selected server-side
	POTENTIAL_PUNCHER = "PotentialPuncher", -- all others after target selection (as requested)
	PUNCHER = "Puncher", -- future: selected puncher
	SPECTATOR = "Spectator", -- future: spectator
	ELIMINATED = "Eliminated", -- eliminated
	WINNER = "Winner", -- winner
}

-- For backward compatibility
Roles.Roles.PotentialPuncher = Roles.Roles.POTENTIAL_PUNCHER

Roles.List = {}
for _, v in pairs(Roles.Roles) do
	table.insert(Roles.List, v)
end

function Roles.IsAlive(role: string): boolean
	return role == Roles.Roles.QUEUED or role == Roles.Roles.TARGET or role == Roles.Roles.POTENTIAL_PUNCHER or role == Roles.Roles.PUNCHER or role == Roles.Roles.SPECTATOR
end

function Roles.IsInMatch(role: string): boolean
	return role == Roles.Roles.TARGET or role == Roles.Roles.POTENTIAL_PUNCHER or role == Roles.Roles.PUNCHER or role == Roles.Roles.SPECTATOR
end

return Roles
