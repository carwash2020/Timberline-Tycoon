--!strict
-- SparkworksStock: the list the Sparkworks counter sells (Lane F stocks
-- the shop from this). Prices come from LogicItems, so a piece has one
-- price. Order is the shelf order: inputs, gates, timers, then outputs.
-- A Door is not sold here; the kit door is already wireable.

local LogicItems = require(script.Parent.LogicItems)

local SparkworksStock = {}

export type Row = {
	id: string,
	displayName: string,
	price: number,
	blurb: string,
}

local ORDER: { { id: string, blurb: string } } = {
	{ id = "Button", blurb = "On for one second when you press it." },
	{ id = "Lever", blurb = "Stays on or off until you flip it again." },
	{ id = "PressurePlate", blurb = "On while a player or a piece of wood rests on it." },
	{ id = "SparkSwitch", blurb = "A wall switch. Wire it to a lamp, a door or a gate." },
	{ id = "GateAnd", blurb = "On only when both inputs are on." },
	{ id = "GateOr", blurb = "On when either input is on." },
	{ id = "GateXor", blurb = "On when the inputs disagree." },
	{ id = "GateNot", blurb = "On when its input is off." },
	{ id = "Delay", blurb = "Passes a signal through after the time you set." },
	{ id = "Sustain", blurb = "Stays on for the time you set after the signal drops." },
	{ id = "Clock", blurb = "Blinks on and off over the period you set." },
	{ id = "SparkLamp", blurb = "Lit until you wire it, then it follows the wire." },
	{ id = "GlowWire", blurb = "A wire that lights while its input is on." },
	{ id = "Hatch", blurb = "A floor door that opens while it is on." },
}

local byId: { [string]: any } = {}
for _, bp in ipairs(LogicItems) do
	byId[bp.id] = bp
end

local list: { Row } = {}
for _, entry in ipairs(ORDER) do
	local bp = byId[entry.id]
	assert(bp, "[SparkworksStock] missing logic piece " .. entry.id)
	table.insert(list, {
		id = bp.id,
		displayName = bp.displayName,
		price = bp.priceCash,
		blurb = entry.blurb,
	})
end

function SparkworksStock.List(): { Row }
	return list
end

function SparkworksStock.Get(id: string): Row?
	for _, row in ipairs(list) do
		if row.id == id then
			return row
		end
	end
	return nil
end

function SparkworksStock.Price(id: string): number?
	local row = SparkworksStock.Get(id)
	return if row then row.price else nil
end

return SparkworksStock
