--!strict
-- Ores mined from the shaft, and gems cracked from geodes.
-- value:  base sell price in coins
-- tier:   1 common, 2 uncommon, 3 rare, 4 very rare (sets drop weight)

local Strata = require(script.Parent.Strata)
local Economy = require(script.Parent.Economy)

export type Ore = {
	name: string,
	value: number,
	tier: number,
	color: Color3,
	variant: string?, -- MaterialVariant for the block, if one exists
	glow: boolean?, -- Neon highlight on the block
}

local Ores: { [string]: Ore } = {
	-- Clay Beds
	coal = { name = "Coal", value = 1, tier = 1, color = Color3.fromHex("2B2B2B"), variant = "DCC_CoalOre" },
	copper = { name = "Copper", value = 3, tier = 2, color = Color3.fromHex("D9822B"), variant = "DCC_CopperOre" },
	tin = { name = "Tin", value = 6, tier = 3, color = Color3.fromHex("C9D1D9") },
	amber = { name = "Amber", value = 25, tier = 4, color = Color3.fromHex("FFB238"), variant = "DCC_AmberOre", glow = true },

	-- Basalt Shelf
	iron = { name = "Iron", value = 10, tier = 1, color = Color3.fromHex("A35A3C") },
	silver = { name = "Silver", value = 20, tier = 2, color = Color3.fromHex("DDE6F0") },
	gold = { name = "Gold", value = 40, tier = 3, color = Color3.fromHex("FFD166"), glow = true },
	jade = { name = "Jade", value = 150, tier = 4, color = Color3.fromHex("3CCB7F"), glow = true },

	-- Crystal Caverns
	quartz = { name = "Quartz", value = 60, tier = 1, color = Color3.fromHex("F2F2FF") },
	amethyst = { name = "Amethyst", value = 120, tier = 2, color = Color3.fromHex("B266FF"), glow = true },
	sapphire = { name = "Sapphire", value = 250, tier = 3, color = Color3.fromHex("3D7BFF"), glow = true },
	prism = { name = "Prism Crystal", value = 1000, tier = 4, color = Color3.fromHex("FF7AD9"), glow = true },

	-- Magma Vents
	obsidian = { name = "Obsidian", value = 400, tier = 1, color = Color3.fromHex("1A1024") },
	fireopal = { name = "Fire Opal", value = 900, tier = 2, color = Color3.fromHex("FF7A1A"), glow = true },
	emberite = { name = "Emberite", value = 4000, tier = 3, color = Color3.fromHex("FFC23D"), glow = true },
}

-- Drop weight per tier (before luck)
local TierWeights = { 60, 28, 10, 2 }

-- Gems found inside geodes: one collection of 50 that can all be found in any layer.
-- A geode's rarity decides which tier of gems it holds (20 Common, 15 Rare, 10 Epic,
-- 5 Legendary); inside a tier every gem has its own weight, so some are much rarer
-- than others. The odds are the same at every depth.
--
-- A gem's coin value is set when you crack it, by its rarity and the layer the geode
-- came from (GemValue), so deeper geodes pay more whichever gem is inside. 5% of
-- cracks are Flawless and worth more.
export type Gem = { name: string, rarity: string, weight: number, color: Color3, boost: string }

local RARITIES = { "Common", "Rare", "Epic", "Legendary" }

-- rarity, id, name, color, weight (higher = more common within its tier), stand boost
local GEM_LIST: { { any } } = {
	-- Common geodes
	{ "Common", "agate", "Agate", "C97B4A", 10, "ore" },
	{ "Common", "redjasper", "Red Jasper", "B5482F", 10, "ore" },
	{ "Common", "onyx", "Onyx", "4A4A56", 10, "geode" },
	{ "Common", "rosequartz", "Rose Quartz", "F7B6CF", 10, "luck" },
	{ "Common", "cinderstone", "Cinderstone", "8A4A32", 10, "heat" },
	{ "Common", "carnelian", "Carnelian", "E07A3F", 8, "heat" },
	{ "Common", "bandedagate", "Banded Agate", "D9A066", 8, "ore" },
	{ "Common", "bandedonyx", "Banded Onyx", "6E6A78", 8, "geode" },
	{ "Common", "citrine", "Citrine", "F2C14E", 8, "luck" },
	{ "Common", "ironheart", "Ironheart", "8D8D99", 6, "dig" },
	{ "Common", "cherryquartz", "Cherry Quartz", "E05A7A", 6, "luck" },
	{ "Common", "glowingcinder", "Glowing Cinder", "D9622B", 6, "heat" },
	{ "Common", "sardonyx", "Sardonyx", "A0522D", 6, "geode" },
	{ "Common", "meteoriron", "Meteor Iron", "6B6F7A", 4, "dig" },
	{ "Common", "snowflakeobsidian", "Snowflake Obsidian", "2E2E36", 4, "geode" },
	{ "Common", "emberagate", "Ember Agate", "C2412D", 4, "heat" },
	{ "Common", "starrosequartz", "Star Rose Quartz", "FFD1E3", 3, "luck" },
	{ "Common", "lavapearl", "Lava Pearl", "FF7A45", 3, "ore" },
	{ "Common", "starforgediron", "Starforged Iron", "B8C0CC", 2, "dig" },
	{ "Common", "starmetal", "Starmetal", "D6DEEA", 2, "dig" },
	-- Rare geodes
	{ "Rare", "moonstone", "Moonstone", "BFE9FF", 10, "luck" },
	{ "Rare", "labradorite", "Labradorite", "5FA8D3", 10, "geode" },
	{ "Rare", "amethystheart", "Amethyst Heart", "9B5DE5", 10, "ore" },
	{ "Rare", "firegarnet", "Fire Garnet", "E5383B", 10, "ore" },
	{ "Rare", "fireagate", "Fire Agate", "E8572A", 8, "heat" },
	{ "Rare", "spectrolite", "Spectrolite", "3FC1A5", 8, "geode" },
	{ "Rare", "voidglass", "Voidglass", "3B2A6B", 8, "dig" },
	{ "Rare", "bluemoonstone", "Blue Moonstone", "8CC8F0", 6, "luck" },
	{ "Rare", "chevronamethyst", "Chevron Amethyst", "B98AF0", 6, "geode" },
	{ "Rare", "moltengarnet", "Molten Garnet", "FF5A36", 6, "heat" },
	{ "Rare", "nebulaglass", "Nebula Glass", "6B4FC4", 4, "dig" },
	{ "Rare", "auroralabradorite", "Aurora Labradorite", "7FE0C8", 4, "luck" },
	{ "Rare", "royalamethyst", "Royal Amethyst", "6A2FB5", 3, "ore" },
	{ "Rare", "infernogarnet", "Inferno Garnet", "B3122E", 3, "heat" },
	{ "Rare", "abyssalglass", "Abyssal Glass", "1E2A55", 2, "dig" },
	-- Epic geodes
	{ "Epic", "stargarnet", "Star Garnet", "C2185B", 10, "ore" },
	{ "Epic", "blackopal", "Black Opal", "4B2A7B", 10, "geode" },
	{ "Epic", "starsapphire", "Star Sapphire", "3D7BFF", 9, "luck" },
	{ "Epic", "sunstone", "Sunstone", "FF9F1C", 9, "heat" },
	{ "Epic", "crowngarnet", "Crown Garnet", "9E1748", 8, "ore" },
	{ "Epic", "corestar", "Corestar", "FFD166", 8, "dig" },
	{ "Epic", "galaxyopal", "Galaxy Opal", "2B3A8C", 7, "geode" },
	{ "Epic", "padparadscha", "Padparadscha", "FF8F70", 7, "luck" },
	{ "Epic", "solarflare", "Solar Flare", "FFC23D", 6, "heat" },
	{ "Epic", "supernova", "Supernova", "FF6FB0", 5, "dig" },
	-- Legendary geodes
	{ "Legendary", "heartstone", "Heartstone", "FFC233", 10, "ore" },
	{ "Legendary", "stormglass", "Stormglass", "8FD3FF", 9, "geode" },
	{ "Legendary", "prismheart", "Prismheart", "FF7AD9", 8, "luck" },
	{ "Legendary", "phoenixopal", "Phoenix Opal", "FF5E3A", 7, "heat" },
	{ "Legendary", "worldheart", "Heart of the World", "FF3D7F", 6, "dig" },
}

-- average coin value of one ore from a layer, weighted by how often each ore drops
local function averageOre(stratumIndex: number): number
	local total, weight = 0, 0
	for _, oreId in ipairs(Strata[stratumIndex].ores) do
		local ore = Ores[oreId]
		local w = TierWeights[ore.tier] or 1
		total += ore.value * w
		weight += w
	end
	return weight > 0 and total / weight or 0
end

-- round to two significant figures so prices read cleanly (7,280 -> 7,300)
local function tidy(v: number): number
	if v < 100 then
		return math.max(1, math.floor(v + 0.5))
	end
	local step = 10 ^ (math.floor(math.log10(v)) - 1)
	return math.floor(v / step + 0.5) * step
end

local LAYERS = #Strata
local Gems: { [string]: Gem } = {}
local GemOrder: { string } = {} -- every id, in book order (by tier, most common first)
local byRarity: { [string]: { string } } = {}
local tierWeight: { [string]: number } = {}
for _, row in ipairs(GEM_LIST) do
	local rarity, id, name, hex, weight, boost = row[1], row[2], row[3], row[4], row[5], row[6]
	Gems[id] = { name = name, rarity = rarity, weight = weight, color = Color3.fromHex(hex), boost = boost }
	table.insert(GemOrder, id)
	byRarity[rarity] = byRarity[rarity] or {}
	table.insert(byRarity[rarity], id)
	tierWeight[rarity] = (tierWeight[rarity] or 0) + weight
end

local function clampLayer(layer: number): number
	return math.clamp(math.floor(layer), 1, LAYERS)
end

-- Chance of a gem when you crack a geode of its rarity (the same in every layer)
local function GemChance(id: string): number
	local gem = Gems[id]
	return gem.weight / tierWeight[gem.rarity]
end

-- Roll which gem is inside a geode of this rarity
local function RollGem(rarity: string, rng: Random): string
	local ids = byRarity[rarity] or byRarity.Common
	local roll = rng:NextNumber() * tierWeight[rarity]
	for _, id in ipairs(ids) do
		roll -= Gems[id].weight
		if roll < 0 then
			return id
		end
	end
	return ids[#ids]
end

-- Coins a gem of this rarity is worth when cracked from this layer. Priced so the
-- average crack (including the odd Flawless one) is worth GeodeOreWorth ores.
local averageMult = 1 + Economy.FlawlessChance * (Economy.FlawlessMult - 1)
-- Rebirths raise it a little too (Economy.Rebirth.GemValueGrowth per rebirth).
local function GemValue(rarity: string, layer: number, flawless: boolean?, rebirths: number?): number
	local base = averageOre(clampLayer(layer)) * (Economy.GeodeOreWorth[rarity] or 0) / averageMult
	base *= Economy.Rebirth.GemValueGrowth ^ (rebirths or 0)
	return tidy(base * (flawless and Economy.FlawlessMult or 1))
end

-- The gems of one tier, most common first
local function TierGems(rarity: string): { string }
	return byRarity[rarity] or {}
end

return {
	Ores = Ores,
	TierWeights = TierWeights,
	Gems = Gems,
	GemOrder = GemOrder,
	GemRarities = RARITIES,
	GemChance = GemChance,
	RollGem = RollGem,
	GemValue = GemValue,
	TierGems = TierGems,
	LayerCount = LAYERS,
	AverageOre = averageOre,
}
