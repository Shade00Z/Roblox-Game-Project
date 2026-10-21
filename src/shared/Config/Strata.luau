--!strict
-- Every stratum of the shaft, top to bottom.
-- Depth is in meters. One block = 1 meter for display purposes.
-- hardness: multiplier on dig speed (1 = normal, 0.1 = ten times slower)
-- heat:     critters with less Heat than this dig slower here
-- bitTier:  the drill bit tier this stratum is built for; with a weaker bit you can still
--           dig here, just slower (see Economy.ToughRock*)
-- blockHp:  how tough each block is to mine by hand (see Economy.Pickaxes)

export type Stratum = {
	id: string,
	name: string,
	top: number,
	bottom: number,
	hardness: number,
	heat: number,
	bitTier: number,
	blockHp: number,
	rockColor: Color3,
	rockVariant: string?, -- MaterialVariant name in MaterialService
	ores: { string }, -- ore ids, most common first
}

local Strata: { Stratum } = {
	{
		id = "clay",
		name = "Clay Beds",
		top = 0,
		bottom = 100,
		hardness = 1.0,
		heat = 0,
		bitTier = 1,
		blockHp = 2,
		rockColor = Color3.fromHex("C97B4A"),
		rockVariant = "DCC_Clay",
		ores = { "coal", "copper", "tin", "amber" },
	},
	{
		id = "basalt",
		name = "Basalt Shelf",
		top = 100,
		bottom = 400,
		hardness = 0.6,
		heat = 0,
		bitTier = 2,
		blockHp = 6,
		rockColor = Color3.fromHex("3A4250"),
		rockVariant = "DCC_Basalt",
		ores = { "iron", "silver", "gold", "jade" },
	},
	{
		id = "crystal",
		name = "Crystal Caverns",
		top = 400,
		bottom = 1000,
		hardness = 0.35,
		heat = 0,
		bitTier = 3,
		blockHp = 15,
		rockColor = Color3.fromHex("2E2546"),
		rockVariant = "DCC_CrystalRock",
		ores = { "quartz", "amethyst", "sapphire", "prism" },
	},
	{
		id = "magma",
		name = "Magma Vents",
		top = 1000,
		bottom = 2500,
		hardness = 0.2,
		heat = 3,
		bitTier = 4,
		blockHp = 40,
		rockColor = Color3.fromHex("1C1414"),
		rockVariant = "DCC_MagmaRock",
		ores = { "obsidian", "fireopal", "emberite" },
	},
	{
		id = "core",
		name = "The Core",
		top = 2500,
		bottom = math.huge,
		hardness = 0.1,
		heat = 5,
		bitTier = 5,
		blockHp = 100,
		rockColor = Color3.fromHex("FFF4D6"),
		rockVariant = nil,
		ores = { "obsidian", "fireopal", "emberite" }, -- placeholder until Phase 3
	},
}

return Strata
