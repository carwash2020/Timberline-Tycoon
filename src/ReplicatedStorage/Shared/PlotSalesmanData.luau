--!strict
-- PlotSalesmanData: Old Hank, the farmer who runs the Land Office counter.
-- Pure data plus the few rules around it, so the server (PlotService wires
-- his Talk prompt), the roster (NPCData builds his lines from here) and the
-- tests all agree.
--
-- He is an NPC like the others (NPCData.List, id = PlotSalesmanData.Id), but
-- he is not a shopkeeper: NPCData gives him no `shop`, so ShopHoursLogic
-- never closes him and NPCService never lays him down to sleep. He stands at
-- the counter around the clock. IsAvailable says so for the tests.
--
-- WHAT HE SELLS is the Offers list below. Today it has one entry, "Buy a
-- plot". The price is GameConfig.PlotPrice, read when the line is spoken,
-- never copied here. Plot tiers and expansion squares keep their own rules
-- (PlotData, PlotLogic, PlotService.Upgrade / UpgradePlot) and are not
-- moved by this file.
--
-- TO ADD AN OFFER (a tier upgrade, a square, a plot paint job, ...):
--   1. Add an entry to Offers: a unique `id`, the prompt `label`, the
--      `pitch` (one %s, the price as "$N"), a `price()` that reads the real
--      number from GameConfig / PlotData / PlotLogic, and an `available`
--      rule over State (pure; add State fields as needed).
--   2. Add a handler with the same id to PlotService's SALESMAN_OFFERS table.
--      The handler does the real, server-validated work (range, ownership,
--      charge once via EconomyService). The client never names a price.
--   3. Add a spec case in tests/PlotSalesman.spec.luau.
-- Choose() picks the first available offer. When there is more than one
-- offer at once, give him a menu (Dialogue card) in place of "first wins".

local GameConfig = require(script.Parent.GameConfig)

local PlotSalesmanData = {}

PlotSalesmanData.Id = "OldHank" -- NPCData id and model name
PlotSalesmanData.Name = "Old Hank"
PlotSalesmanData.Role = "Plot salesman"

-- What the server knows about the player when they talk to him.
export type State = {
	ownsPlot: boolean, -- already has a homestead
	full: boolean, -- the plot district has no free pad on this server
}

export type Offer = {
	id: string, -- also the key into PlotService's SALESMAN_OFFERS
	label: string, -- the action, as on the counter's prompt
	pitch: string, -- one %s: the price as "$N"
	price: () -> number, -- read live from the game's numbers
	available: (State) -> boolean,
}

PlotSalesmanData.Offers = {
	{
		id = "buyPlot",
		label = "Buy a plot",
		pitch = "A plot of your own is %s, paid once. Pick your pad and it's yours to build on.",
		price = function(): number
			return GameConfig.PlotPrice
		end,
		available = function(state: State): boolean
			return not state.ownsPlot
		end,
	},
} :: { Offer }

-- He is never off shift: any hour of the day.
function PlotSalesmanData.IsAvailable(_hour: number): boolean
	return true
end

function PlotSalesmanData.PriceText(offer: Offer): string
	return string.format("$%d", offer.price())
end

function PlotSalesmanData.Pitch(offer: Offer): string
	return string.format(offer.pitch, PlotSalesmanData.PriceText(offer))
end

-- Lines that do not depend on an offer.
PlotSalesmanData.OwnsLine = "You've got your plot, partner. Come back when there's more land to be had."
PlotSalesmanData.FullLine = "Every pad's spoken for on this server today. Try another one, friend."
PlotSalesmanData.FarLine = "Come on up to the counter, I can't hear you from there."

function PlotSalesmanData.Find(id: string): Offer?
	for _, offer in ipairs(PlotSalesmanData.Offers) do
		if offer.id == id then
			return offer
		end
	end
	return nil
end

-- The offers open to this player, in list order.
function PlotSalesmanData.Available(state: State): { Offer }
	local out: { Offer } = {}
	if state.full then
		return out
	end
	for _, offer in ipairs(PlotSalesmanData.Offers) do
		if offer.available(state) then
			table.insert(out, offer)
		end
	end
	return out
end

export type Choice = { offer: Offer?, line: string }

-- What Hank does when talked to: the offer to open (first available) and
-- the line he says in his voice, with the real price in it.
function PlotSalesmanData.Choose(state: State): Choice
	local open = PlotSalesmanData.Available(state)
	local offer = open[1]
	if offer then
		return { offer = offer, line = "Howdy! " .. PlotSalesmanData.Pitch(offer) }
	end
	if state.ownsPlot then
		return { offer = nil, line = PlotSalesmanData.OwnsLine }
	end
	return { offer = nil, line = PlotSalesmanData.FullLine }
end

-- Greetings for NPCData. Every one names the plot price, so whichever
-- the dialogue box draws, the player hears the real number. Built from the live
-- Offers, so a price change in GameConfig shows up here.
function PlotSalesmanData.Greetings(): { string }
	local price = PlotSalesmanData.PriceText(PlotSalesmanData.Offers[1])
	return {
		string.format("Howdy, partner! Plots are %s. Come on up.", price),
		string.format("Fine day for it. A plot of your own is %s.", price),
		string.format("Land's cheap at %s. Buy a plot, build a place.", price),
	}
end

-- Idle chatter. The first is the one-price pitch in his voice.
function PlotSalesmanData.Lines(): { string }
	local price = PlotSalesmanData.PriceText(PlotSalesmanData.Offers[1])
	return {
		string.format("%s, once, and the pad is yours for good.", price),
		"Started with a patch of dirt myself. Now look at me. Still dirt, but it's mine.",
		"Your plot grows as you do. Start small, add squares, build it up.",
		"Hay's good, weather's fair. Can't ask for much more than that.",
		"Everyone gets a homestead and a view. Pick a pad and settle in.",
	}
end

return PlotSalesmanData
