--!strict
-- Fossil eggs sold at the Hatchery.
--
-- price:        coins
-- hatchSeconds: real time in an incubator before it can hatch (keeps going offline)
-- stock:        { min, max } of this egg each player can buy per restock
-- chance:       how often this egg is in stock at all on a given restock (1 = always)
-- odds:         { species, weight } — shown to players as percentages

export type Egg = {
	id: string,
	name: string,
	price: number,
	hatchSeconds: number,
	color: Color3,
	stock: { number },
	chance: number,
	odds: { { any } },
}

local Eggs = {}

Eggs.RestockSeconds = 30 * 60 -- every server restocks at the same moment
Eggs.IncubatorSlots = 3

Eggs.List = {
	{
		id = "dirt",
		name = "Dirt Egg",
		price = 200,
		hatchSeconds = 5 * 60,
		color = Color3.fromHex("A0673A"),
		stock = { 3, 6 },
		chance = 1,
		odds = { { "pebblemole", 45 }, { "rustbeetle", 35 }, { "clayarmadillo", 12 }, { "lanternworm", 8 } },
	},
	{
		id = "amber",
		name = "Amber Egg",
		price = 1500,
		hatchSeconds = 20 * 60,
		color = Color3.fromHex("FFB238"),
		stock = { 1, 4 },
		chance = 1,
		odds = { { "rustbeetle", 25 }, { "clayarmadillo", 30 }, { "lanternworm", 25 }, { "quartzsnail", 12 }, { "basaltbadger", 8 } },
	},
	{
		id = "crystal",
		name = "Crystal Egg",
		price = 9000,
		hatchSeconds = 60 * 60,
		color = Color3.fromHex("B266FF"),
		stock = { 1, 2 },
		chance = 0.75,
		odds = { { "clayarmadillo", 15 }, { "lanternworm", 15 }, { "quartzsnail", 30 }, { "basaltbadger", 30 }, { "embersalamander", 10 } },
	},
	{
		id = "magma",
		name = "Magma Egg",
		price = 60000,
		hatchSeconds = 3 * 60 * 60,
		color = Color3.fromHex("FF7A1A"),
		stock = { 1, 1 },
		chance = 0.4,
		odds = { { "basaltbadger", 30 }, { "quartzsnail", 15 }, { "embersalamander", 45 }, { "geodegolem", 10 } },
	},
} :: { Egg }

function Eggs.Get(id: string): Egg?
	for _, egg in ipairs(Eggs.List) do
		if egg.id == id then
			return egg
		end
	end
	return nil
end

-- Which restock window a time falls in
function Eggs.RestockIndex(now: number): number
	return now // Eggs.RestockSeconds
end

-- The stock for one restock window. Every server and every client computes the
-- same numbers from the window index, so no cross-server messaging is needed.
function Eggs.StockFor(index: number): { [string]: number }
	local rng = Random.new(index * 7919 + 104729)
	local stock = {}
	for _, egg in ipairs(Eggs.List) do
		local inStock = rng:NextNumber() < egg.chance
		local amount = rng:NextInteger(egg.stock[1], egg.stock[2])
		stock[egg.id] = inStock and amount or 0
	end
	return stock
end

-- Odds as percentages, for showing on the egg card
function Eggs.Percentages(egg: Egg): { { species: string, percent: number } }
	local total = 0
	for _, o in ipairs(egg.odds) do
		total += o[2]
	end
	local list = {}
	for _, o in ipairs(egg.odds) do
		table.insert(list, { species = o[1], percent = o[2] / total * 100 })
	end
	return list
end

return Eggs
