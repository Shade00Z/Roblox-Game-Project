--!nonstrict
-- The dig front: the few rows of blocks at the bottom of your shaft that you and
-- your crew dig through together. Shared by server and client so both always agree
-- on what every block is, without sending block data over the network.
--
-- Layout (side view, row 1 is the top row you stand on):
--
--     row 1   meter = front.top       <- clearing this whole row = +1 meter
--     row 2   meter = front.top + 1
--     row 3   meter = front.top + 2
--
-- front = { top = <meter of row 1>, rows = { mask1, mask2, mask3 } }
-- Each mask is a number whose bits say which of the WIDTH columns are already mined.

local Shared = script.Parent
local Strata = require(Shared.Config.Strata)
local Economy = require(Shared.Config.Economy)
local OreConfig = require(Shared.Config.Ores)
local Formulas = require(Shared.Formulas)

local DigFront = {}

DigFront.WIDTH = Economy.Dig.Width
DigFront.ROWS = Economy.Dig.Rows

-- Fallback order (middle outward) for crew progress when no critter has a block
DigFront.CREW_ORDER = { 4, 5, 3, 6, 2, 7, 1, 8, 0, 9 }

----------------------------------------------------------------------
-- Bit masks
----------------------------------------------------------------------

function DigFront.IsMined(mask: number, col: number): boolean
	return bit32.btest(mask, bit32.lshift(1, col))
end

function DigFront.SetMined(mask: number, col: number): number
	return bit32.bor(mask, bit32.lshift(1, col))
end

function DigFront.Count(mask: number): number
	local n = 0
	for col = 0, DigFront.WIDTH - 1 do
		if DigFront.IsMined(mask, col) then
			n += 1
		end
	end
	return n
end

function DigFront.Full(mask: number): boolean
	return DigFront.Count(mask) >= DigFront.WIDTH
end

function DigFront.NewFront(top: number)
	local rows = {}
	for i = 1, DigFront.ROWS do
		rows[i] = 0
	end
	return { top = top, rows = rows }
end

----------------------------------------------------------------------
-- What is inside a block
----------------------------------------------------------------------

-- A repeatable random generator for one block. The same seed, meter and column
-- always give the same numbers, on the server and on every client.
local function cellRng(seed: number, meter: number, col: number): Random
	local a = (seed % 2147483647) * 73856093 % 4294967296
	local b = (meter * 19349663) % 4294967296
	local c = ((col + 1) * 83492791) % 4294967296
	return Random.new(bit32.bxor(a, b, c))
end

export type Cell = {
	kind: string, -- "rock" | "ore" | "pocket" | "geode" | "egg"
	oreId: string?, -- for "ore" and "pocket"
	stratum: number,
}

function DigFront.CellAt(seed: number, meter: number, col: number): Cell
	local si = Formulas.StratumIndexAt(meter)
	local rng = cellRng(seed, meter, col)
	local roll = rng:NextNumber()
	local dig = Economy.Dig

	if roll < dig.EggChance then
		return { kind = "egg", stratum = si }
	end
	roll -= dig.EggChance
	if roll < dig.GeodeChance then
		return { kind = "geode", stratum = si }
	end
	roll -= dig.GeodeChance
	if roll < dig.PocketChance then
		local ores = Strata[si].ores
		return { kind = "pocket", oreId = ores[math.min(3, #ores)], stratum = si }
	end
	roll -= dig.PocketChance
	if roll < dig.OreChance then
		return { kind = "ore", oreId = Formulas.RollOre(Formulas.OreWeights(si, 0), rng), stratum = si }
	end
	return { kind = "rock", stratum = si }
end

-- Swings needed to break a block at this meter with this pickaxe level.
-- Rock too tough for your drill bit takes extra swings (Economy.ToughRockHits).
function DigFront.HitsNeeded(meter: number, pickaxeLevel: number, bitLevel: number?): number
	local si = Formulas.StratumIndexAt(meter)
	local pick = Economy.Pickaxes[pickaxeLevel] or Economy.Pickaxes[1]
	local hits = math.ceil(Strata[si].blockHp / pick.power)
	if bitLevel then
		local bit = Economy.Bits[bitLevel] or Economy.Bits[1]
		hits *= Economy.ToughRockHits ^ Formulas.TiersShort(bit.tier, si)
	end
	return math.max(1, hits)
end

----------------------------------------------------------------------
-- Rules
----------------------------------------------------------------------

-- A block can be dug if it's in the top row, or touches an already-dug block
-- above it or beside it.
function DigFront.Exposed(front, row: number, col: number): boolean
	if row == 1 then
		return true
	end
	local rows = front.rows
	if DigFront.IsMined(rows[row - 1], col) then
		return true
	end
	if col > 0 and DigFront.IsMined(rows[row], col - 1) then
		return true
	end
	if col < DigFront.WIDTH - 1 and DigFront.IsMined(rows[row], col + 1) then
		return true
	end
	return false
end

-- Where a block sits in the world, given the shaft room's origin
-- (matches the room built in Workspace.Map.ShaftRoom: 4-stud blocks, 10 wide).
function DigFront.CellPosition(origin: Vector3, row: number, col: number): Vector3
	return origin + Vector3.new(-18 + col * 4, 2 + (DigFront.ROWS - row) * 4, 4)
end

----------------------------------------------------------------------
-- Crew critters: each one works its own block
----------------------------------------------------------------------
-- front.crew = { targets = { cell, ... }, turn = n }
--   targets[k] is the block critter k (k-th in the crew list) is digging, as a cell
--   number: cell = (row - 1) * WIDTH + col, so 0..9 is the top row and 10..19 the
--   second row. -1 means it has nothing to dig right now.
--   * Critters work the top row first. No two critters ever share a block.
--   * When a critter's block breaks, only that critter moves, to the closest free
--     block beside it.
--   * A critter with no free top-row block drops into an already-dug hole and digs the
--     block under it in the second row. When the top row clears and everything slides
--     up, that critter rides up with its block and keeps digging.
--   The server saves this, so every device sees the same thing.

function DigFront.EncodeCell(row: number, col: number): number
	return (row - 1) * DigFront.WIDTH + col
end

function DigFront.DecodeCell(cell: number): (number, number)
	return cell // DigFront.WIDTH + 1, cell % DigFront.WIDTH
end

-- Where critter k of n starts, spread evenly across the row
local function homeColumn(k: number, n: number): number
	return math.clamp(math.floor((k - 0.5) * DigFront.WIDTH / n), 0, DigFront.WIDTH - 1)
end

local function claimedByOther(targets, cell: number, k: number): boolean
	for i, t in ipairs(targets) do
		if i ~= k and t == cell then
			return true
		end
	end
	return false
end

-- Can the crew dig this block? Top-row blocks always; second-row blocks only from
-- inside a hole (the block above is already dug).
local function crewCanDig(front, row: number, col: number): boolean
	if row == 1 then
		return not DigFront.IsMined(front.rows[1], col)
	elseif row == 2 then
		return DigFront.IsMined(front.rows[1], col) and not DigFront.IsMined(front.rows[2], col)
	end
	return false
end

-- The closest free block to column `from` in one row, or -1
local function nearestInRow(front, targets, row: number, from: number, k: number): number
	for d = 0, DigFront.WIDTH - 1 do
		for _, col in ipairs({ from - d, from + d }) do
			if col >= 0 and col < DigFront.WIDTH and crewCanDig(front, row, col) then
				local cell = DigFront.EncodeCell(row, col)
				if not claimedByOther(targets, cell, k) then
					return cell
				end
			end
		end
	end
	return -1
end

-- Top row first; if nothing is free there, the second row
local function pickBlock(front, targets, from: number, k: number): number
	local cell = nearestInRow(front, targets, 1, from, k)
	if cell < 0 then
		cell = nearestInRow(front, targets, 2, from, k)
	end
	return cell
end

-- Make sure there's one target per critter and every target is a free block the
-- crew can dig. Critters whose block is still fine keep it; only the others move.
function DigFront.FixCrewTargets(front, crewCount: number)
	front.crew = front.crew or { targets = {}, turn = 0 }
	local targets = front.crew.targets
	while #targets > crewCount do
		table.remove(targets)
	end
	for k = 1, crewCount do
		local cur = targets[k]
		local bad = cur == nil or cur < 0 or cur >= 2 * DigFront.WIDTH
		if not bad then
			local row, col = DigFront.DecodeCell(cur)
			bad = not crewCanDig(front, row, col)
		end
		if not bad then
			-- an earlier critter already holds this block
			for i = 1, k - 1 do
				if targets[i] == cur then
					bad = true
					break
				end
			end
		end
		if bad then
			local from = homeColumn(k, crewCount)
			if cur ~= nil and cur >= 0 then
				from = cur % DigFront.WIDTH
			end
			targets[k] = -1
			targets[k] = pickBlock(front, targets, from, k)
		end
	end
end

-- Each critter's current block as a cell number (-1 = nothing to dig), for placing them
function DigFront.CrewTargets(front): { number }
	return front.crew and front.crew.targets or {}
end

----------------------------------------------------------------------
-- Keeping depth and the front in step (server only)
----------------------------------------------------------------------

local function shift(front)
	table.remove(front.rows, 1)
	table.insert(front.rows, 0)
	front.top += 1
	-- critters ride up with their blocks: a second-row block is now in the top row.
	-- A critter that was on the cleared top row keeps its column as a starting point.
	if front.crew then
		for k, cell in ipairs(front.crew.targets) do
			if cell >= DigFront.WIDTH then
				front.crew.targets[k] = cell - DigFront.WIDTH
			end
		end
	end
end

-- Call after depth changes (crew digging) or after a block is mined.
--   * If the crew dug past the top row, rows scroll up.
--   * The crew's progress inside the top row shows up as mined blocks: critters take
--     turns, each breaking the block it's working, then stepping to the next one.
--     A critter digging the second row while it waits gets a head start on the next
--     row (those blocks count once the row slides up).
--   * Blocks you mined count toward depth (each block = 1/WIDTH of a meter).
--   * A fully cleared top row breaks through to the next meter.
-- Returns how many rows broke through.
function DigFront.Sync(data, maxDepth: number, crewCount: number?): number
	local n = crewCount or 0
	local front = data.front
	local whole = math.floor(data.depth + 1e-9)

	-- the crew dug past the visible rows (e.g. while offline)
	if whole - front.top >= DigFront.ROWS then
		local fresh = DigFront.NewFront(whole)
		front.top, front.rows = fresh.top, fresh.rows
		front.crew = { targets = {}, turn = 0 }
	end
	while front.top < whole do
		shift(front)
	end
	DigFront.FixCrewTargets(front, n)

	-- crew progress inside the top row
	local wanted = math.floor((data.depth - front.top) * DigFront.WIDTH + 1e-6)
	local count = DigFront.Count(front.rows[1])
	for _ = 1, DigFront.WIDTH * 3 do
		if count >= wanted then
			break
		end
		local cell = -1
		if n > 0 then
			-- critters take turns; the one whose turn it is breaks its own block
			for _ = 1, n do
				local k = (front.crew.turn % n) + 1
				front.crew.turn += 1
				cell = front.crew.targets[k]
				if cell >= 0 then
					break
				end
			end
		end
		if cell < 0 then
			-- no critter has a block (e.g. the crew was rested mid-row): fill from the middle
			for _, c in ipairs(DigFront.CREW_ORDER) do
				if not DigFront.IsMined(front.rows[1], c) then
					cell = c
					break
				end
			end
		end
		if cell < 0 then
			break
		end
		local row, col = DigFront.DecodeCell(cell)
		front.rows[row] = DigFront.SetMined(front.rows[row], col)
		if row == 1 then
			count += 1
		end
		DigFront.FixCrewTargets(front, n) -- only the critter that broke it moves on
	end

	-- player-mined blocks count toward depth, and full rows break through
	local broke = 0
	while true do
		data.depth = math.min(math.max(data.depth, front.top + DigFront.Count(front.rows[1]) / DigFront.WIDTH), maxDepth)
		if DigFront.Full(front.rows[1]) and front.top + 1 <= maxDepth then
			shift(front)
			broke += 1
		else
			break
		end
	end
	DigFront.FixCrewTargets(front, n)
	return broke
end

return DigFront
