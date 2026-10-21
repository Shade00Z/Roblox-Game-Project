--!strict
-- Every tunable number for pacing and prices lives here.
-- Change these freely while playtesting; gameplay code reads them at runtime.

local Economy = {}

-- Digging
Economy.OrePerMeter = 1 -- ore units produced per meter dug
Economy.CartFullDigFactor = 0.1 -- when the cart is full, depth still creeps at this fraction
Economy.HeatFloor = 0.2 -- a critter with no Heat still digs at this fraction in hot strata
Economy.CrewSlots = 3

-- Vein taps (active play)
Economy.VeinOre = 2 -- ore units per tap
Economy.VeinCooldown = 6 -- seconds before a tapped vein glows again
Economy.BoostMultiplier = 2 -- dig speed multiplier after a tap
Economy.BoostSeconds = 8 -- how long the burst lasts
Economy.MaxTapsPerSecond = 4 -- anything faster is ignored

-- Drill bits: tier decides how deep your crew digs at full speed (see Strata.bitTier).
-- There is no depth limit: rock that's too tough for your bit is just slower to dig.
Economy.Bits = {
	{ id = "copper", name = "Copper Bit", tier = 1, mult = 1.0, cost = 0 },
	{ id = "iron", name = "Iron Bit", tier = 2, mult = 1.5, cost = 250 },
	{ id = "diamond", name = "Diamond Bit", tier = 3, mult = 2.25, cost = 5000 },
	{ id = "obsidian", name = "Obsidian Bit", tier = 4, mult = 3.4, cost = 60000 },
	{ id = "corebreaker", name = "Corebreaker", tier = 5, mult = 5.0, cost = 750000 },
}

-- Ore cart: capacity is the offline cap (base cart fills in about 2 hours with one Pebble Mole)
Economy.Carts = {
	{ capacity = 120, cost = 0 },
	{ capacity = 240, cost = 100 },
	{ capacity = 480, cost = 600 },
	{ capacity = 960, cost = 3000 },
	{ capacity = 1920, cost = 15000 },
	{ capacity = 3840, cost = 75000 },
}

-- Geodes
Economy.RackSlots = 4
Economy.GeodeChancePerMeter = 0.04 -- about one geode every 25 meters
Economy.GeodeRarities = {
	{ name = "Common", weight = 70, matureSeconds = 3600 },
	{ name = "Rare", weight = 22, matureSeconds = 4 * 3600 },
	{ name = "Epic", weight = 7, matureSeconds = 12 * 3600 },
	{ name = "Legendary", weight = 1, matureSeconds = 24 * 3600 },
}
Economy.CrackCritterChance = 0.15 -- chance a geode also holds a critter
Economy.CrackCritterPool = { "pebblemole", "rustbeetle" } -- Phase 1 pool; eggs replace this in Phase 2
Economy.FirstCrackCritter = "rustbeetle" -- the first geode ever cracked always holds this critter

-- Digging yourself: your pickaxe vs. block hardness (Strata.blockHp)
-- hits per block = ceil(blockHp / power); swing = seconds between hits
Economy.Pickaxes = {
	{ name = "Rusty Pick", power = 1, swing = 0.3, cost = 0 },
	{ name = "Iron Pick", power = 2, swing = 0.26, cost = 150 },
	{ name = "Steel Pick", power = 4, swing = 0.22, cost = 2000 },
	{ name = "Diamond Pick", power = 8, swing = 0.18, cost = 25000 },
	{ name = "Obsidian Pick", power = 15, swing = 0.15, cost = 300000 },
}

Economy.Dig = {
	Width = 10, -- blocks per row (one row = one meter)
	Rows = 3, -- rows of the dig front you can see and dig into
	Reach = 18, -- studs from your character to a block you can hit

	-- what a block holds, rolled once per block from your mine's seed
	OreChance = 0.2, -- 1 ore of the stratum
	PocketChance = 0.015, -- a burst of the stratum's rare ore
	GeodeChance = 0.008, -- a buried geode straight onto your rack
	EggChance = 0.005, -- a fossil egg that hatches a critter

	PocketOre = { 5, 8 }, -- min, max ore from a pocket
	BuriedGeodeLuck = 0.5, -- buried geodes roll rarer than crew finds

	-- which critters hatch from fossil eggs, by stratum index
	EggPools = {
		{ { "pebblemole", 40 }, { "rustbeetle", 35 }, { "clayarmadillo", 15 }, { "lanternworm", 10 } },
		{ { "rustbeetle", 25 }, { "clayarmadillo", 30 }, { "lanternworm", 20 }, { "quartzsnail", 15 }, { "basaltbadger", 10 } },
		{ { "lanternworm", 20 }, { "quartzsnail", 35 }, { "basaltbadger", 30 }, { "embersalamander", 12 }, { "geodegolem", 3 } },
		{ { "basaltbadger", 35 }, { "embersalamander", 50 }, { "geodegolem", 15 } },
		{ { "embersalamander", 60 }, { "geodegolem", 40 } },
	},
}

-- Tough rock: for each bit tier you're short of a stratum's bitTier...
Economy.ToughRockSlowdown = 4 -- ...your crew digs this many times slower
Economy.ToughRockHits = 2 -- ...and blocks take this many times more pickaxe hits

-- Interaction ranges (studs) checked on the server
Economy.ShopRange = 40

-- Away screen only shows if you were gone at least this long
Economy.AwaySummaryMinSeconds = 60

return Economy
