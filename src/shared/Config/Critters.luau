--!strict
-- Crew critters. Stats:
--   dig:  meters per minute this critter adds to the crew
--   luck: adds to rare ore and geode chances (0.1 = +10%)
--   heat: lets it work at full speed in hot strata

export type Species = {
	name: string,
	rarity: string,
	dig: number,
	luck: number,
	heat: number,
	color: Color3,
	accent: Color3,
}

local Critters: { [string]: Species } = {
	pebblemole = { name = "Pebble Mole", rarity = "Common", dig = 1.0, luck = 0, heat = 0, color = Color3.fromHex("9A9A9A"), accent = Color3.fromHex("FFC233") },
	rustbeetle = { name = "Rust Beetle", rarity = "Common", dig = 1.2, luck = 0, heat = 0, color = Color3.fromHex("C8642D"), accent = Color3.fromHex("5A2E14") },
	clayarmadillo = { name = "Clay Armadillo", rarity = "Uncommon", dig = 1.6, luck = 0, heat = 2, color = Color3.fromHex("C97B4A"), accent = Color3.fromHex("8E4F2C") },
	lanternworm = { name = "Lantern Worm", rarity = "Uncommon", dig = 0.8, luck = 0.1, heat = 0, color = Color3.fromHex("E8D7A9"), accent = Color3.fromHex("FFD166") },
	quartzsnail = { name = "Quartz Snail", rarity = "Rare", dig = 1.0, luck = 0.2, heat = 0, color = Color3.fromHex("B8E6FF"), accent = Color3.fromHex("FFFFFF") },
	basaltbadger = { name = "Basalt Badger", rarity = "Rare", dig = 3.0, luck = 0, heat = 1, color = Color3.fromHex("3A4250"), accent = Color3.fromHex("DDE6F0") },
	embersalamander = { name = "Ember Salamander", rarity = "Epic", dig = 2.5, luck = 0, heat = 5, color = Color3.fromHex("FF7A1A"), accent = Color3.fromHex("1C1414") },
	geodegolem = { name = "Geode Golem Pup", rarity = "Legendary", dig = 5.0, luck = 0.3, heat = 5, color = Color3.fromHex("8D99AE"), accent = Color3.fromHex("B266FF") },
}

local RarityColors = {
	Common = Color3.fromHex("B0B0B0"),
	Uncommon = Color3.fromHex("5CD65C"),
	Rare = Color3.fromHex("4DA6FF"),
	Epic = Color3.fromHex("B266FF"),
	Legendary = Color3.fromHex("FFC233"),
}

return {
	Species = Critters,
	RarityColors = RarityColors,
}
