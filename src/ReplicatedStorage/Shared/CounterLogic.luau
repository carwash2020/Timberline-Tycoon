--!strict
-- CounterLogic: the counter as a queue. Boxes in the pay zone are offered
-- one at a time, never more than CounterMaxItems. Saying no keeps the rest.
-- Pulling the offered box off the counter is the "missing" line, and no
-- money moves.

local GameConfig = require(script.Parent.GameConfig)

local CounterLogic = {}

-- How far past the counter's own top the pay zone reaches, and how far
-- below that top it still counts. A box sitting on the counter has its
-- centre about a stud above the top.
CounterLogic.BelowTop = 0.5
CounterLogic.AboveTop = 6

export type Line = "greet" | "offer" | "broke" | "declined" | "missing" | "alreadyOwned" | "needsLand" | "thanks"

export type Queued = {
	uid: string,
	inZone: boolean,
}

export type LineFacts = {
	greeting: boolean?,
	declined: boolean?,
	boxUid: string?,
	inZone: boolean?,
	cash: number?,
	price: number?,
	owned: boolean?,
	needsLand: boolean?,
	paid: boolean?,
}

-- `cf` and `size` are the counter part. The zone is its footprint, from
-- half a stud under the top to six studs over it.
function CounterLogic.InZone(point: Vector3, cf: CFrame, size: Vector3): boolean
	local p = cf:PointToObjectSpace(point)
	local top = size.Y / 2
	if p.Y < top - CounterLogic.BelowTop or p.Y > top + CounterLogic.AboveTop then
		return false
	end
	if math.abs(p.X) > size.X / 2 or math.abs(p.Z) > size.Z / 2 then
		return false
	end
	return true
end

-- The boxes the cashier will mention, in the order given, capped.
function CounterLogic.Queue(items: { Queued }, maxItems: number?): { string }
	local cap = maxItems or GameConfig.CounterMaxItems
	local out: { string } = {}
	for _, item in ipairs(items) do
		if item.inZone then
			table.insert(out, item.uid)
			if #out >= cap then
				break
			end
		end
	end
	return out
end

function CounterLogic.Offer(queue: { string }): string?
	return queue[1]
end

-- Drop the offered box. Everything behind it stays, in the same order.
function CounterLogic.Decline(queue: { string }): { string }
	local rest: { string } = {}
	for i = 2, #queue do
		table.insert(rest, queue[i])
	end
	return rest
end

-- Which line to say. Missing wins over a short wallet: the box has to be
-- on the counter before anyone talks price.
function CounterLogic.Line(facts: LineFacts): Line
	if facts.greeting then
		return "greet"
	elseif facts.declined then
		return "declined"
	elseif facts.paid then
		return "thanks"
	elseif facts.boxUid == nil or facts.inZone == false then
		return "missing"
	elseif facts.needsLand then
		return "needsLand"
	elseif facts.owned then
		return "alreadyOwned"
	elseif facts.cash ~= nil and facts.price ~= nil and facts.cash < facts.price then
		return "broke"
	end
	return "offer"
end

return CounterLogic
