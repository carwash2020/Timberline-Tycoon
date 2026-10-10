--!strict
-- HandInLogic: which loose wood a hand-in may take (Gus's Charter, the
-- weekly forge order, tempering and relics). Pure. A piece counts when it
-- is the player's own (Owner), not welded into a truck bed, not held by
-- someone else, within reach of the hand-in spot, and of the right kind: planks
-- for wood by volume, any figured log or plank for a relic.

local HandInLogic = {}

HandInLogic.Reach = 22 -- studs from the hand-in spot to the piece's middle

export type Candidate = {
	uid: string,
	woodId: string,
	kind: string, -- "log" | "plank"
	volume: number, -- u³
	figure: string?,
	owner: number,
	welded: boolean,
	held: boolean,
	distance: number,
}

local EPS = 1e-6

function HandInLogic.Counts(c: Candidate, userId: number): boolean
	return c.owner == userId
		and c.owner ~= 0
		and not c.welded
		and not c.held
		and c.distance <= HandInLogic.Reach
		and c.volume == c.volume
		and c.volume > 0
end

-- u³ of planks by wood id that `userId` has laid in reach.
function HandInLogic.Planks(list: { Candidate }, userId: number): { [string]: number }
	local out: { [string]: number } = {}
	for _, c in ipairs(list) do
		if c.kind == "plank" and HandInLogic.Counts(c, userId) then
			out[c.woodId] = (out[c.woodId] or 0) + c.volume
		end
	end
	return out
end

-- How many figured pieces (log or plank) of `woodId` are in reach.
function HandInLogic.Figured(list: { Candidate }, userId: number, woodId: string): number
	local n = 0
	for _, c in ipairs(list) do
		if c.woodId == woodId and c.figure ~= nil and HandInLogic.Counts(c, userId) then
			n += 1
		end
	end
	return n
end

-- The planks of `woodId` to use up for `u3`: smallest first, until the
-- total reaches it. The last piece may go over (a piece is never cut).
function HandInLogic.PickPlanks(list: { Candidate }, userId: number, woodId: string, u3: number): { string }
	local pool: { Candidate } = {}
	for _, c in ipairs(list) do
		if c.kind == "plank" and c.woodId == woodId and HandInLogic.Counts(c, userId) then
			table.insert(pool, c)
		end
	end
	table.sort(pool, function(a: Candidate, b: Candidate): boolean
		if a.volume ~= b.volume then
			return a.volume < b.volume
		end
		return a.uid < b.uid
	end)
	local out: { string } = {}
	local total = 0
	for _, c in ipairs(pool) do
		if total >= u3 - EPS then
			break
		end
		table.insert(out, c.uid)
		total += c.volume
	end
	return out
end

-- The one figured piece of `woodId` a relic uses: the smallest.
function HandInLogic.PickFigured(list: { Candidate }, userId: number, woodId: string): string?
	local best: Candidate? = nil
	for _, c in ipairs(list) do
		if c.woodId == woodId and c.figure ~= nil and HandInLogic.Counts(c, userId) then
			if best == nil or c.volume < best.volume or (c.volume == best.volume and c.uid < best.uid) then
				best = c
			end
		end
	end
	return if best then best.uid else nil
end

return HandInLogic
