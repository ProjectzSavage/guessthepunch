--!nonstrict
-- PowerZones.luau
-- Shared definition of punch power zones (future use)
-- Roblox Studio Destination: ReplicatedStorage > Shared > PowerZones (ModuleScript)

local PowerZones = {}

PowerZones.Zones = {
	MISS = "Miss",
	WEAK = "Weak",
	NORMAL = "Normal",
	STRONG = "Strong",
	PERFECT = "Perfect",
}

PowerZones.List = {"Miss", "Weak", "Normal", "Strong", "Perfect"}

PowerZones.DamageByZone = {
	Miss = 0,
	Weak = 10,
	Normal = 25,
	Strong = 50,
	Perfect = 100,
}

function PowerZones.IsInstantKO(zone: string): boolean
	return zone == PowerZones.Zones.PERFECT
end

return PowerZones
