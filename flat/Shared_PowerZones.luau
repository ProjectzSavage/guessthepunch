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

-- ============================================================================
-- POWER GAUGE MATH (Phase: server-authoritative power gauge)
-- IMPORTANT: Server lock calculation AND client display MUST both use these
-- exact functions so the displayed needle matches the server-calculated zone.
-- ============================================================================

-- Ping-pong needle position in [0,1] for elapsed seconds.
-- Moves continuously 0 -> 1, REVERSES at the ends (1 -> 0 -> 1 ...).
function PowerZones.GetNeedlePosition(elapsed: number, sweepDuration: number): number
	if sweepDuration <= 0 then return 0 end
	if elapsed < 0 then elapsed = 0 end
	local raw = elapsed / sweepDuration
	local cycle = raw % 2
	if cycle <= 1 then
		return cycle -- moving up 0 -> 1
	else
		return 2 - cycle -- reversed, moving down 1 -> 0
	end
end

-- Zone for a needle position. thresholds = Config.PowerGaugeZoneThresholds
-- (pass explicitly so this module stays standalone). Position IS the power level.
function PowerZones.GetZoneForPosition(position: number, thresholds): string
	position = math.clamp(position, 0, 1)
	local t = thresholds or { Normal = 0.40, Strong = 0.70, Perfect = 0.90 }
	if position >= (t.Perfect or 0.90) then
		return PowerZones.Zones.PERFECT
	end
	if position >= (t.Strong or 0.70) then
		return PowerZones.Zones.STRONG
	end
	if position >= (t.Normal or 0.40) then
		return PowerZones.Zones.NORMAL
	end
	return PowerZones.Zones.WEAK
end

return PowerZones
