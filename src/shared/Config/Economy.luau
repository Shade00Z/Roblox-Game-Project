--!strict
-- Every tunable number for pacing and prices lives here.
-- Change these freely while playtesting; gameplay code reads them at runtime.

local Economy = {}

-- Digging
Economy.OrePerMeter = 1 -- ore units produced per meter dug
Economy.CartFullDigFactor = 0.1 -- when the cart is full, depth still creeps at this fraction
Economy.HeatFloor = 0.35 -- a critter with no Heat still digs at this fraction in hot strata
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
Economy.FirstCrackCritter = "rustbeetle" -- the first geode ever cracked always holds this critter

-- A geode's gem is worth this many of the average ore from the layer it was found in
Economy.GeodeOreWorth = { Common = 8, Rare = 30, Epic = 120, Legendary = 500 }

-- 5% of cracks are Flawless: worth this many times more and marked in the Gem Book
Economy.FlawlessChance = 0.05
Economy.FlawlessMult = 3

-- Gem Book rewards (Core Shards, given once): finishing a tier (all Common gems,
-- all Rare gems...), and finishing all 50
Economy.GemSetShards = 1
Economy.GemBookCompleteShards = 3

-- Gem stand: equip up to GemSlots gems you have found; each gives one boost.
--   dig:   crew dig speed (%)        heat:  Heat added to every crew critter
--   luck:  added to crew Luck (%)    ore:   ore sells for more (%)
--   geode: crew finds more geodes (%)
-- Size: the tier's base, a little more for gems that are rarer inside their tier
-- (x (10 / weight) ^ GemRarityBonusPower), and x FlawlessBoostMult once you have
-- found a Flawless one of that gem.
Economy.GemSlots = 3
Economy.GemBoostBase = {
	Common = { pct = 0.04, heat = 0.4 },
	Rare = { pct = 0.08, heat = 0.8 },
	Epic = { pct = 0.15, heat = 1.5 },
	Legendary = { pct = 0.25, heat = 2.5 },
}
Economy.GemRarityBonusPower = 0.25
Economy.FlawlessBoostMult = 1.5

-- Bonus loot rolled on every crack, by geode rarity:
--   critter: chance a critter from that layer's egg pool was sleeping inside
--   shard:   chance of a Core Shard (+10% dig speed forever)
--   pouch:   chance of a pouch of that layer's ore, sold on the spot; pouchOre = min, max
Economy.GeodeExtras = {
	Common = { critter = 0.05, shard = 0, pouch = 0.25, pouchOre = { 4, 8 } },
	Rare = { critter = 0.12, shard = 0, pouch = 0.4, pouchOre = { 10, 20 } },
	Epic = { critter = 0.25, shard = 0.25, pouch = 0.6, pouchOre = { 30, 50 } },
	Legendary = { critter = 0.5, shard = 1, pouch = 1, pouchOre = { 100, 150 } },
}

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

-- Merging: two of the same critter at the same star level make one a star higher
Economy.Merge = {
	MaxStars = 5,
	StatPerStar = 1.35, -- Dig, Luck and Heat are multiplied by this for every star
}

-- Selling a critter (bench only): base value by rarity, doubled for every star
-- (so a merged critter is worth exactly what its copies were)
Economy.CritterSellValue = {
	Common = 50,
	Uncommon = 150,
	Rare = 600,
	Epic = 2500,
	Legendary = 12000,
}

-- Tough rock: for each bit tier you're short of a stratum's bitTier...
Economy.ToughRockSlowdown = 4 -- ...your crew digs this many times slower
Economy.ToughRockHits = 2 -- ...and blocks take this many times more pickaxe hits

-- Rebirth: once you're deep enough, start over from the surface for a permanent boost.
-- Resets depth, coins, the cart, the geode rack and your bit / cart / pickaxe; keeps
-- critters, eggs, the Gem Book, your gem stand and Core Shards.
Economy.Rebirth = {
	BaseDepth = 2500, -- depth needed for the first rebirth (the Core)
	DepthPerRebirth = 250, -- each rebirth after that needs this much more
	DigPerRebirth = 0.25, -- +25% crew dig speed for every rebirth (adds up)
	PriceGrowth = 1.5, -- bits, carts, pickaxes and eggs cost this much more per rebirth (compounds)
	GemValueGrowth = 1.2, -- gems from geodes sell for this much more per rebirth (compounds)
	-- extra slots unlocked at a rebirth count, kept for good
	Unlocks = {
		[1] = { crewSlots = 1, text = "A 4th crew slot" },
		[2] = { rackSlots = 1, text = "A 5th geode rack slot" },
		[3] = { gemSlots = 1, text = "A 4th gem stand slot" },
	},
}

-- Interaction ranges (studs) checked on the server
Economy.ShopRange = 40

-- Away screen only shows if you were gone at least this long
Economy.AwaySummaryMinSeconds = 60

return Economy
