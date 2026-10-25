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

-- How much a critter's stars multiply its Dig, Luck and Heat (0 stars = 1x)
function Formulas.StarMultiplier(stars: number?): number
	return Economy.Merge.StatPerStar ^ math.clamp(stars or 0, 0, Economy.Merge.MaxStars)
end

-- A crew member can be a species id ("pebblemole") or { species = id, stars = n }
local function memberInfo(member)
	if type(member) == "string" then
		return Critters.Species[member], 1
	end
	return Critters.Species[member.species], Formulas.StarMultiplier(member.stars)
end

-- One critter's stats with its stars applied
function Formulas.CritterStats(species: string, stars: number?): { dig: number, luck: number, heat: number }
	local sp = Critters.Species[species]
	local m = Formulas.StarMultiplier(stars)
	return { dig = sp.dig * m, luck = sp.luck * m, heat = sp.heat * m }
end

-- Coins for selling a critter
function Formulas.CritterSellValue(species: string, stars: number?): number
	local sp = Critters.Species[species]
	return (Economy.CritterSellValue[sp.rarity] or 0) * 2 ^ (stars or 0)
end

-- Sum of crew luck (0.1 = +10%)
function Formulas.CrewLuck(members: { any }): number
	local luck = 0
	for _, member in ipairs(members) do
		local sp, mult = memberInfo(member)
		if sp then
			luck += sp.luck * mult
		end
	end
	return luck
end

-- Dig rate in meters per minute for this crew in a stratum.
-- Includes the bit multiplier, stratum hardness, Core Shard bonus, and the slowdown
-- for rock that's too tough for your bit (when bitTier is given).
-- boosts (optional): totals from the gem stand, see Formulas.GemBoosts
function Formulas.DigRate(members: { any }, stratumIndex: number, bitMult: number, coreShards: number, bitTier: number?, boosts: any?): number
	local stratum = Strata[stratumIndex]
	local extraHeat = boosts and boosts.heat or 0
	local crewDig = 0
	for _, member in ipairs(members) do
		local sp, mult = memberInfo(member)
		if sp then
			crewDig += sp.dig * mult * Formulas.HeatFactor(sp.heat * mult + extraHeat, stratum.heat)
		end
	end
	local tough = bitTier and Formulas.ToughRockFactor(bitTier, stratumIndex) or 1
	local gemDig = 1 + (boosts and boosts.dig or 0)
	local rebirthDig = 1 + (boosts and boosts.rebirth or 0)
	return crewDig * bitMult * stratum.hardness * (1 + 0.1 * coreShards) * tough * gemDig * rebirthDig
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

----------------------------------------------------------------------
-- Gem stand boosts
----------------------------------------------------------------------

Formulas.BoostNames = {
	dig = "Dig speed",
	heat = "Heat",
	luck = "Luck",
	ore = "Ore value",
	geode = "Geode finds",
}

-- One gem's boost: (kind, amount). Percent kinds are fractions (0.04 = +4%);
-- heat is a flat amount added to every crew critter's Heat.
function Formulas.GemBoost(gemId: string, flawless: boolean?): (string?, number)
	local gem = OreConfig.Gems[gemId]
	if not gem then
		return nil, 0
	end
	local base = Economy.GemBoostBase[gem.rarity]
	local amount = (gem.boost == "heat" and base.heat or base.pct) * (10 / gem.weight) ^ Economy.GemRarityBonusPower
	if flawless then
		amount *= Economy.FlawlessBoostMult
	end
	if gem.boost == "heat" then
		amount = math.floor(amount * 10 + 0.5) / 10 -- tenths of Heat
	else
		amount = math.floor(amount * 200 + 0.5) / 200 -- half-percent steps
	end
	return gem.boost, amount
end

-- Totals for a set of equipped gems: { dig, heat, luck, ore, geode }
function Formulas.GemBoosts(equipped: { string }?, flawless: { [string]: boolean }?)
	local totals = { dig = 0, heat = 0, luck = 0, ore = 0, geode = 0 }
	for _, id in ipairs(equipped or {}) do
		local kind, amount = Formulas.GemBoost(id, flawless and flawless[id])
		if kind then
			totals[kind] += amount
		end
	end
	return totals
end

-- "+4% Dig speed", "+1.5 Heat"
function Formulas.FormatBoost(kind: string, amount: number, short: boolean?): string
	local name = Formulas.BoostNames[kind] or kind
	if short then
		name = ({ dig = "Dig", heat = "Heat", luck = "Luck", ore = "Ore", geode = "Geodes" })[kind] or name
	end
	if kind == "heat" then
		return string.format("+%s %s", (amount == math.floor(amount)) and tostring(math.floor(amount)) or string.format("%.1f", amount), name)
	end
	local pct = amount * 100
	return string.format(pct == math.floor(pct) and "+%d%% %s" or "+%.1f%% %s", pct == math.floor(pct) and math.floor(pct) or pct, name)
end

----------------------------------------------------------------------
-- Rebirths
----------------------------------------------------------------------

-- Depth you need to reach to rebirth, having rebirthed `rebirths` times already
function Formulas.RebirthDepth(rebirths: number): number
	return Economy.Rebirth.BaseDepth + Economy.Rebirth.DepthPerRebirth * (rebirths or 0)
end

-- Extra crew dig speed from rebirths (0.25 = +25%)
function Formulas.RebirthDig(rebirths: number): number
	return Economy.Rebirth.DigPerRebirth * (rebirths or 0)
end

-- How much more things cost after this many rebirths
function Formulas.PriceMult(rebirths: number): number
	return Economy.Rebirth.PriceGrowth ^ (rebirths or 0)
end

-- A shop price after rebirths, rounded to three significant figures (1,125,000 -> 1,130,000)
function Formulas.Price(base: number, rebirths: number): number
	local v = base * Formulas.PriceMult(rebirths)
	if v < 1000 then
		return math.floor(v + 0.5)
	end
	local step = 10 ^ (math.floor(math.log10(v)) - 2)
	return math.floor(v / step + 0.5) * step
end

local function unlocked(rebirths: number, key: string): number
	local extra = 0
	for at, unlock in pairs(Economy.Rebirth.Unlocks) do
		if (rebirths or 0) >= at and unlock[key] then
			extra += unlock[key]
		end
	end
	return extra
end

function Formulas.CrewSlots(rebirths: number): number
	return Economy.CrewSlots + unlocked(rebirths, "crewSlots")
end

function Formulas.RackSlots(rebirths: number): number
	return Economy.RackSlots + unlocked(rebirths, "rackSlots")
end

function Formulas.GemSlots(rebirths: number): number
	return Economy.GemSlots + unlocked(rebirths, "gemSlots")
end

-- The most slots of each kind anyone can have (for building UI once)
function Formulas.MaxSlots(): (number, number, number)
	return Formulas.CrewSlots(math.huge), Formulas.RackSlots(math.huge), Formulas.GemSlots(math.huge)
end

return Formulas
