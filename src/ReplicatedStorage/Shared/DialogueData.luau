--!strict
-- DialogueData: what the shopkeepers say at the counter. Each shop has its
-- own lines. The keys are the cashier's outcomes (CounterLogic.Line).
-- Nothing here is copied from another game.
--
-- Land Office, Odds & Ends, Sparkworks and the Hermit have lines only.
-- Their buildings are not in this batch, so they are not in NPCData and
-- nothing here spawns them. The Land Office, Odds & Ends and Sparkworks
-- sets are DRAFTS (marked below): placeholder writing for shops that do
-- not exist, kept so the tests keep every shop's lines complete. Nobody
-- hears them. Rewrite them when their buildings are built (B16).

local ShopHoursLogic = require(script.Parent.ShopHoursLogic)

local DialogueData = {}

-- Yes / No on a phone. The face is this many pixels on a side, over the
-- 44 px fingertip minimum, and the row sits at the bottom centre.
DialogueData.ButtonPx = 48

export type Vars = {
	name: string?,
	price: string?,
	shop: string?,
	hour: number?,
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
		needsPlot = "Claim a plot before you open that box.",
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
		needsPlot = "You'll want a plot of your own before you open that.",
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
		needsPlot = "You'll need a plot to open this.",
		thanks = "Sold. The box is yours to open.",
		locked = "I don't have that one for sale.",
	},
	-- DRAFT: not spoken yet (no Land Office building); rewrite with the building.
	LandOffice = {
		greet = "Plots are on the board. Tell me which square you want.",
		offer = "This %s is %s. Shall I mark it yours?",
		broke = "The office can't file a short payment.",
		declined = "The square will still be there.",
		missing = "That slip isn't on the counter.",
		alreadyOwned = "That square is already in your name.",
		needsLand = "Pick a free slot before I can file this.",
		thanks = "Filed. The square is yours.",
		locked = "That one isn't for sale from this desk.",
	},
	-- DRAFT: not spoken yet (no Odds & Ends building); rewrite with the building.
	OddsAndEnds = {
		greet = "Odds, ends, and a few things that are both.",
		offer = "This %s for %s. Want it?",
		broke = "The drawer won't close on a short payment.",
		declined = "I'll leave it on the shelf.",
		missing = "That one walked off the counter.",
		alreadyOwned = "You already bought that oddment.",
		needsLand = "You'll want a plot before this one.",
		thanks = "Yours. Don't ask where I found it.",
		locked = "Not for sale. Even I have limits.",
	},
	-- DRAFT: not spoken yet (no Sparkworks building); rewrite with the building.
	Sparkworks = {
		greet = "Mind the sparks. The counter's the safe bit.",
		offer = "Wire this %s for %s?",
		broke = "The coil won't spark on a short payment.",
		declined = "It'll keep. Copper doesn't mind waiting.",
		missing = "That box isn't on the bench.",
		alreadyOwned = "You already wired one of those.",
		needsLand = "A plot first, then the machine.",
		thanks = "Paid. Open it somewhere that isn't my bench.",
		locked = "That circuit isn't on the board.",
	},
	Hermit = {
		greet = "You found the cave. Speak softly.",
		offer = "This %s costs %s. Leave it if you must.",
		broke = "The mountain doesn't take a short coin.",
		declined = "Then leave it. The cave keeps it.",
		missing = "That isn't on the stone.",
		alreadyOwned = "You already carry that.",
		needsLand = "A plot in town, before this.",
		thanks = "Take it. Don't tell the town the way.",
		locked = "Not mine to sell.",
	},
}

-- One %s, filled with the formatted next-open hour.
local SLEEPY: { [string]: string } = {
	ToolShed = "The shed's still open. I don't sleep.",
	HearthAndHome = "Mmf... the hearth opens at %s...",
	Dealership = "Mmf... the lot opens at %s...",
	LandOffice = "Mmf... the office opens at %s...",
	OddsAndEnds = "Mmf... the shop opens at %s...",
	Sparkworks = "Mmf... the bench opens at %s...",
	Hermit = "Mmf... come back at %s...",
}

local IDLES: { [string]: { string } } = {
	ToolShed = {
		"That edge will hold. I've asked it to.",
		"Grindstone's warm. Bring me a dull one.",
		"Starfall isn't on the shelf. It's forged, up on the isles.",
	},
	HearthAndHome = {
		"I swept twice already. The woods keep coming in.",
		"Scarves on the left, lanterns by the door.",
		"The kettle's on. The till can wait a minute.",
	},
	Dealership = {
		"That tyre stack is a system. Don't touch it.",
		"I road-tested the Rustbucket. Once was enough.",
		"Trailers hitch on the back. Your back will thank you.",
	},
}

local function shopLines(shop: string?): { [string]: string }
	return LINES[shop or ""] or LINES.ToolShed
end

function DialogueData.Sleepy(shop: string?, hour: number): string
	local when = ShopHoursLogic.FormatHour(ShopHoursLogic.NextOpen(shop or "", hour))
	local text = SLEEPY[shop or ""] or "Mmf... open at %s..."
	return string.format(text, when)
end

function DialogueData.Idles(shop: string): { string }
	return IDLES[shop] or {}
end

function DialogueData.Line(key: string, vars: Vars?): string
	local shop = if vars then vars.shop else nil
	if key == "sleepy" then
		local hour = if vars and type(vars.hour) == "number" then vars.hour else ShopHoursLogic.FallbackHour
		return DialogueData.Sleepy(shop, hour)
	end
	local name = if vars and vars.name then vars.name else "item"
	local price = if vars and vars.price then vars.price else ""
	local text = shopLines(shop)[key] or LINES.ToolShed[key] or ""
	if string.find(text, "%s", 1, true) then
		return string.format(text, name, price)
	end
	return text
end

function DialogueData.Shops(): { string }
	return { "ToolShed", "HearthAndHome", "Dealership" }
end

export type Card = { choice: boolean, noLabel: string }

-- Yes / Cancel on the no-plot warning. Other choice lines stay Yes / No.
function DialogueData.Card(line: string): Card
	if line == "needsPlot" then
		return { choice = true, noLabel = "Cancel" }
	elseif line == "offer" then
		return { choice = true, noLabel = "No" }
	end
	return { choice = false, noLabel = "Close" }
end

return DialogueData
