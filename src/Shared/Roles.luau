--!nonstrict
-- Roles.luau
-- Shared definition of player roles (future use)
-- Roblox Studio Destination: ReplicatedStorage > Shared > Roles (ModuleScript)

local Roles = {}

Roles.Roles = {
	NONE = "NONE",
	LOBBY = "LOBBY",
	QUEUED = "QUEUED",
	TARGET = "TARGET",
	PUNCHER = "PUNCHER",
	SPECTATOR = "SPECTATOR",
	ELIMINATED = "ELIMINATED",
	WINNER = "WINNER",
}

Roles.List = {}
for _, v in pairs(Roles.Roles) do
	table.insert(Roles.List, v)
end

function Roles.IsAlive(role: string): boolean
	return role == Roles.Roles.QUEUED or role == Roles.Roles.TARGET or role == Roles.Roles.PUNCHER or role == Roles.Roles.SPECTATOR
end

return Roles
