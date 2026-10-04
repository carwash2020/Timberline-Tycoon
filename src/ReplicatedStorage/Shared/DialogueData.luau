--!strict
-- DialogueData: what the shopkeepers say at the counter. Each shop has its
-- own lines. The keys are the cashier's outcomes (CounterLogic.Line).
-- Nothing here is copied from another game.

local DialogueData = {}

-- Yes / No on a phone. The face is this many pixels on a side, over the
-- 44 px fingertip minimum, and the row sits at the bottom centre.
DialogueData.ButtonPx = 48

export type Vars = {
	name: string?,
	price: string?,
	shop: string?,
}

local LINES: { [string]: { [string]: string } } = {
	ToolShed = {
		greet = "Set a box on the counter and I'll ring it up.",
		offer = "Buy this %s for %s?",
		broke = "You're a little short for that tool.",
		declined = "No rush. The next box can wait its turn.",
		missing = "Did that box slip off the counter?",
		alreadyOwned = "You already have that one in the shed.",
		needsLand = "Claim a plot before you haul a sawmill home.",
		thanks = "Paid. Open the box when you want the tool.",
		locked = "That one isn't for sale from this counter.",
	},
	HearthAndHome = {
		greet = "If it's sitting on the counter, I can sell it.",
		offer = "Shall I sell you this %s for %s?",
		broke = "The till won't take a short payment.",
		declined = "That's fine. I'll ask about the next one.",
		missing = "I don't see that box on the counter anymore.",
		alreadyOwned = "You already bought one of those.",
		needsLand = "You'll want your own plot before this one.",
		thanks = "It's yours. Open it whenever you like.",
		locked = "I can't sell that from this counter.",
	},
	Dealership = {
		greet = "Trucks are on the board. A box on the counter, I can ring up.",
		offer = "This %s is %s. Do you want it?",
		broke = "That's more than you have on you.",
		declined = "All right. I'll keep the others on the counter.",
		missing = "That box isn't on the counter. Did it fall off?",
		alreadyOwned = "You already own that one.",
		needsLand = "You need a plot of your own for that.",
		thanks = "Sold. The box is yours to open.",
		locked = "I don't have that one for sale.",
	},
}

local function shopLines(shop: string?): { [string]: string }
	return LINES[shop or ""] or LINES.ToolShed
end

function DialogueData.Line(key: string, vars: Vars?): string
	local name = if vars and vars.name then vars.name else "item"
	local price = if vars and vars.price then vars.price else ""
	local shop = if vars then vars.shop else nil
	local text = shopLines(shop)[key] or LINES.ToolShed[key] or ""
	if string.find(text, "%s", 1, true) then
		return string.format(text, name, price)
	end
	return text
end

function DialogueData.Shops(): { string }
	return { "ToolShed", "HearthAndHome", "Dealership" }
end

return DialogueData
