--!strict
-- Ores mined from the shaft, and gems cracked from geodes.
-- value:  base sell price in coins
-- tier:   1 common, 2 uncommon, 3 rare, 4 very rare (sets drop weight)

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

-- Gems found inside geodes, one per geode rarity
local Gems: { [string]: { name: string, value: number, rarity: string, color: Color3 } } = {
	agate = { name = "Agate", value = 20, rarity = "Common", color = Color3.fromHex("C97B4A") },
	moonstone = { name = "Moonstone", value = 120, rarity = "Rare", color = Color3.fromHex("BFE9FF") },
	stargarnet = { name = "Star Garnet", value = 600, rarity = "Epic", color = Color3.fromHex("C2185B") },
	heartstone = { name = "Heartstone", value = 3000, rarity = "Legendary", color = Color3.fromHex("FFC233") },
}

local GemByRarity = {
	Common = "agate",
	Rare = "moonstone",
	Epic = "stargarnet",
	Legendary = "heartstone",
}

return {
	Ores = Ores,
	TierWeights = TierWeights,
	Gems = Gems,
	GemByRarity = GemByRarity,
}
