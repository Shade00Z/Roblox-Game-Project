--!strict
-- Pure math shared by server and client. No state, no side effects.

local Shared = script.Parent
local Strata = require(Shared.Config.Strata)
local Critters = require(Shared.Config.Critters)
local OreConfig = require(Shared.Config.Ores)
local Economy = require(Shared.Config.Economy)

local Formulas = {}

-- Index into Strata for a given depth (meters)
function Formulas.StratumIndexAt(depth: number): number
	for i, s in ipairs(Strata) do
		if depth < s.bottom then
			return i
		end
	end
	return #Strata
end

-- The deepest point a drill bit tier digs at full speed (deeper is allowed, just slower)
function Formulas.FullSpeedDepth(tier: number): number
	local s = Strata[math.clamp(tier, 1, #Strata)]
	return s.bottom
end

-- How many drill-bit tiers short you are for a stratum (0 = your bit is good enough)
function Formulas.TiersShort(bitTier: number, stratumIndex: number): number
	return math.max(0, Strata[stratumIndex].bitTier - bitTier)
end

-- Crew speed multiplier for rock that's too tough for your bit (1 = full speed)
function Formulas.ToughRockFactor(bitTier: number, stratumIndex: number): number
	return 1 / (Economy.ToughRockSlowdown ^ Formulas.TiersShort(bitTier, stratumIndex))
end

-- How well one critter works in a stratum (0.2 .. 1)
function Formulas.HeatFactor(critterHeat: number, stratumHeat: number): number
	if stratumHeat <= 0 then
		return 1
	end
	return math.clamp(critterHeat / stratumHeat, Economy.HeatFloor, 1)
end

-- Sum of crew luck (0.1 = +10%)
function Formulas.CrewLuck(speciesIds: { string }): number
	local luck = 0
	for _, id in ipairs(speciesIds) do
		local sp = Critters.Species[id]
		if sp then
			luck += sp.luck
		end
	end
	return luck
end

-- Dig rate in meters per minute for this crew in a stratum.
-- Includes the bit multiplier, stratum hardness, Core Shard bonus, and the slowdown
-- for rock that's too tough for your bit (when bitTier is given).
function Formulas.DigRate(speciesIds: { string }, stratumIndex: number, bitMult: number, coreShards: number, bitTier: number?): number
	local stratum = Strata[stratumIndex]
	local crewDig = 0
	for _, id in ipairs(speciesIds) do
		local sp = Critters.Species[id]
		if sp then
			crewDig += sp.dig * Formulas.HeatFactor(sp.heat, stratum.heat)
		end
	end
	local tough = bitTier and Formulas.ToughRockFactor(bitTier, stratumIndex) or 1
	return crewDig * bitMult * stratum.hardness * (1 + 0.1 * coreShards) * tough
end

-- Ore drop weights for a stratum, with luck boosting the rarer tiers
function Formulas.OreWeights(stratumIndex: number, luck: number): { { id: string, weight: number } }
	local list = {}
	for _, oreId in ipairs(Strata[stratumIndex].ores) do
		local ore = OreConfig.Ores[oreId]
		local w = OreConfig.TierWeights[ore.tier] or 1
		if ore.tier >= 3 then
			w *= (1 + luck)
		end
		table.insert(list, { id = oreId, weight = w })
	end
	return list
end

-- Pick one ore id from a weight list
function Formulas.RollOre(weights: { { id: string, weight: number } }, rng: Random): string
	local total = 0
	for _, e in ipairs(weights) do
		total += e.weight
	end
	local r = rng:NextNumber() * total
	for _, e in ipairs(weights) do
		r -= e.weight
		if r <= 0 then
			return e.id
		end
	end
	return weights[#weights].id
end

-- Split `units` ore across the weight list. Expected values, with random rounding,
-- so a long offline period is one cheap calculation instead of thousands of rolls.
function Formulas.DistributeOre(weights: { { id: string, weight: number } }, units: number, rng: Random): { [string]: number }
	local total = 0
	for _, e in ipairs(weights) do
		total += e.weight
	end
	local out = {}
	for _, e in ipairs(weights) do
		local exact = units * e.weight / total
		local n = math.floor(exact)
		if rng:NextNumber() < exact - n then
			n += 1
		end
		if n > 0 then
			out[e.id] = n
		end
	end
	return out
end

-- Pick a geode rarity name
function Formulas.RollGeodeRarity(rng: Random, luck: number): string
	local total = 0
	local weights = {}
	for i, r in ipairs(Economy.GeodeRarities) do
		local w = r.weight
		if i >= 2 then
			w *= (1 + luck)
		end
		weights[i] = w
		total += w
	end
	local roll = rng:NextNumber() * total
	for i, r in ipairs(Economy.GeodeRarities) do
		roll -= weights[i]
		if roll <= 0 then
			return r.name
		end
	end
	return Economy.GeodeRarities[1].name
end

function Formulas.GeodeMatureSeconds(rarity: string): number
	for _, r in ipairs(Economy.GeodeRarities) do
		if r.name == rarity then
			return r.matureSeconds
		end
	end
	return 3600
end

-- Total sell value of a cart table { [oreId] = count }
function Formulas.CartValue(cart: { [string]: number }): number
	local v = 0
	for id, n in pairs(cart) do
		local ore = OreConfig.Ores[id]
		if ore then
			v += ore.value * n
		end
	end
	return v
end

function Formulas.GemsValue(gems: { [string]: number }): number
	local v = 0
	for id, n in pairs(gems) do
		local gem = OreConfig.Gems[id]
		if gem then
			v += gem.value * n
		end
	end
	return v
end

-- "2h 13m", "45m", "30s"
function Formulas.FormatDuration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	elseif m > 0 then
		return string.format("%dm %02ds", m, s)
	end
	return string.format("%ds", s)
end

-- 1234567 -> "1,234,567"
function Formulas.FormatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

return Formulas
