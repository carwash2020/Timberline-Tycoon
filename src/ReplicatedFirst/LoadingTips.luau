--!strict
-- LoadingTips: the loading card's rotating lines. ReplicatedFirst cannot
-- require ReplicatedStorage (this runs before it replicates), so the list
-- lives here, next to the loading screen. Edit Lines; keep each one short
-- enough for a phone (MaxLength).

local LoadingTips = {}

LoadingTips.MaxLength = 70

-- Early path, in plain words. No prices and no Robux. A shuffle shows each
-- line once before any line repeats.
LoadingTips.Lines = {
	"Planks sell for more than logs.",
	"Rook at the main sawmill hands out 3 daily jobs.",
	"Bombs clear cave rubble to deeper, richer ore.",
	"Wear the Insulated Coat before heading into the snow.",
	"Back your truck up to the furnace to sell a whole load.",
	"Hover over an ore rock to see what's inside.",
	"Swing low on a tree and keep chopping until it falls.",
	"Put the axe away, then drag a log onto your truck.",
	"Odd bark can hide figured wood. The mill pays more.",
	"Old Hank at the Land Office sells homestead plots.",
	"A blueprint teaches a building. The hammer places it.",
	"The Field Guide lists every wood you have found.",
	"Heat Boots let you walk the volcano safely.",
	"A lantern lights the Gloam Hollow while you chop.",
}

export type Rng = (number) -> number

export type Cycle = {
	order: { number },
	generation: number,
	rng: Rng,
}

local function roll(rng: Rng, n: number): number
	local raw = rng(n)
	if type(raw) ~= "number" then
		return 1
	end
	local picked = math.floor(raw)
	if picked < 1 then
		return 1
	end
	if picked > n then
		return n
	end
	return picked
end

-- Fisher-Yates. `rng(n)` should return an integer from 1 to n; a wild roll
-- is clamped so a bad generator cannot skip a line or repeat inside a cycle.
function LoadingTips.Shuffle(rng: Rng?): { number }
	local n = #LoadingTips.Lines
	local order: { number } = table.create(n)
	for i = 1, n do
		order[i] = i
	end
	local rollOf = rng or math.random
	for i = n, 2, -1 do
		local j = roll(rollOf, i)
		order[i], order[j] = order[j], order[i]
	end
	return order
end

function LoadingTips.Begin(rng: Rng?): Cycle
	local rollOf = rng or math.random
	return {
		order = LoadingTips.Shuffle(rollOf),
		generation = 0,
		rng = rollOf,
	}
end

-- The line for `slot` (0, 1, 2, ...). A new shuffle starts every time the
-- list has been shown all the way through, so nothing repeats inside a cycle.
function LoadingTips.LineAt(cycle: Cycle, slot: number): string
	local n = #LoadingTips.Lines
	local safe = if slot == slot then math.max(0, math.floor(slot)) else 0
	local generation = math.floor(safe / n)
	if cycle.generation ~= generation then
		cycle.order = LoadingTips.Shuffle(cycle.rng)
		cycle.generation = generation
	end
	local index = cycle.order[safe % n + 1]
	return LoadingTips.Lines[index]
end

return LoadingTips
