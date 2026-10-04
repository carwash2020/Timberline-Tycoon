--!strict
-- TutorialData: Murph's tutorial (GAME_DESIGN §11), one objective at a time.
-- QuestService (server) counts progress from game events; QuestUI (client)
-- shows the objective, Murph's line and a beacon. Tuning = editing this.
--
-- v1 order: claim a plot, chop, pick up, sell the first load at Murph's
-- cart (he chips in $25 on that sale), then buy the Rustbucket. After that
-- the old lessons stay: load, mill, plant, the three loads, and the Steel
-- Axe. QuestService then keeps one next goal on the tracker (NextGoal).
--
-- v2 order: fell, drag, sell at the cart, claim a plot, then the truck,
-- and the same lessons after it. tutorialStep is an index, so a save from
-- the plot-first v2 order is remapped by ApplyOrder (old index to the step
-- name, then that name's new index).
--
-- Inserting a step shifts the ones after it: QuestService moves saves
-- made before the insert to the latest step they had reached (by the
-- funnel steps they've reached), so keep step ids stable.
--
-- The v2 core loop (V2_PLAN.md §13, Shared/CoreLoop) has its own steps,
-- StepsV2, with the v2 loop's words and events. ForLoop(loop) picks the
-- list; Steps is the v1 one.

local FieldGuide = require(script.Parent.FieldGuide)
local ItemCatalog = require(script.Parent.ItemCatalog)
local PlotData = require(script.Parent.PlotData)
local ShopLogic = require(script.Parent.ShopLogic)
local WoodData = require(script.Parent.WoodData)

local TutorialData = {}

-- Game events QuestService listens for (the server reports them). The
-- v2 loop adds wood events; plotClaimed is the free plot.
export type TutorialEvent =
	"treeFelled"
	| "logPickedUp"
	| "logsLoaded"
	| "logsSold"
	| "seedPlanted"
	| "axeBought"
	| "woodGrabbed"
	| "woodLoaded"
	| "woodSold"
	| "woodSoldCash"
	| "plotClaimed"
	| "truckBought"

-- What the beacon points at (QuestUI finds it in the world; "stump" is a
-- stump you hold a Heartseed for, which ForestUI also marks). v2 adds
-- "wood" (your nearest loose piece, tag Wood) and "truckBed" (your
-- truck's bed). "murphCart" is the tutorial cart; "plotSign" is plot 1.
export type BeaconTarget =
	"tree"
	| "log"
	| "truck"
	| "sellPad"
	| "stump"
	| "toolShed"
	| "wood"
	| "truckBed"
	| "murphCart"
	| "plotSign"
	| "dealership"

export type Step = {
	id: string,
	objective: string, -- the tracker line; "%d" is replaced by the goal count
	murph: string, -- what Murph says when the step starts ({click} / {Click}: the device's word, HintLogic.Expand)
	event: TutorialEvent,
	count: number, -- how many of `event` (logs, for the log events)
	beacon: BeaconTarget?,
	beaconWood: string?, -- v2: the wood the "tree" beacon looks for first (a WoodData id)
	grove: boolean?, -- the tree beacon prefers a TutorialGrove oak
	unit: "cash"?, -- v2: `count` is dollars, so the tracker reads "($23/$40)"
	rewardCash: number?, -- paid when the step is done
	murphBack: string?, -- v2: what Murph says instead to a returning player on the refresher (RefresherLast)
	murphShort: string?, -- said instead while cash is under cashPrice ("sell more first")
	axeGoal: boolean?, -- the tracker also shows cash toward the Steel Axe
	axePrice: number?, -- that axe's price in this loop
	cashItem: string?, -- tracker suffix " · $51 of $75 to Rustbucket"
	cashPrice: number?, -- that purchase's price; with murphShort, the short line while cash is under it
	also: TutorialEvent?, -- a second event; both must happen (progress stores the two bits)
}

-- A blueprint named SaplingPlot is the planting half of the plot step.
function TutorialData.SaplingsExist(): boolean
	for _, bp in ipairs(PlotData.Blueprints) do
		if bp.id == "SaplingPlot" then
			return true
		end
	end
	return false
end

local starterAxe = ItemCatalog.AxeLadder()[1]
local steelAxe = ItemCatalog.AxeLadder()[2] -- AlreadyDone's tier 2
local oak = WoodData.Get("oak") :: WoodData.WoodDef
local birch = WoodData.Get("birch") :: WoodData.WoodDef
local rustbucket = ItemCatalog.GetTruck("Rustbucket") :: ItemCatalog.TruckDef
local saplings = TutorialData.SaplingsExist()

local function logLoad(id: string, reward: number, murph: string): Step
	return {
		id = id,
		objective = "Sell %d more logs",
		murph = murph,
		event = "logsSold",
		count = 6,
		rewardCash = reward,
		axeGoal = true,
		axePrice = ShopLogic.Price(steelAxe, 1),
	}
end

local function cashLoad(id: string, reward: number, murph: string): Step
	return {
		id = id,
		objective = "Sell $%d more wood",
		murph = murph,
		event = "woodSoldCash",
		count = 40,
		unit = "cash",
		rewardCash = reward,
		axeGoal = true,
		axePrice = ShopLogic.Price(steelAxe, 2),
	}
end

local function plotStep(afterSale: boolean?): Step
	-- v1 claims the plot before any sale, so the thank-you stays off that
	-- line. v2 says it here, the step right after the cart sale.
	local claim = if saplings
		then "Every lumberjack needs land, and this one's free. Claim one, follow the arrow, then plant a sapling on it."
		else "Every lumberjack needs land, and this one's free. Claim one, follow the arrow."
	local thanks = "That sale's yours, and a little extra from me. "
	-- The sapling sentence plus the thank-you is too long for one bubble,
	-- so that variant drops the "needs land" clause.
	local after = if saplings
		then thanks .. "Claim one, follow the arrow, then plant a sapling on it."
		else thanks .. claim
	return {
		id = "plot",
		objective = if saplings then "Claim a free plot and plant a sapling" else "Claim a free plot",
		murph = if afterSale then after else claim,
		event = "plotClaimed",
		count = 1,
		beacon = "plotSign",
		also = if saplings then "seedPlanted" :: TutorialEvent else nil,
	}
end

local function truckStep(loop: number): Step
	local price = ShopLogic.Price(rustbucket, loop)
	return {
		id = "truck",
		objective = "Buy the Rustbucket at the dealership",
		murph = if price > 0
			then string.format("The Rustbucket is $%d at the dealership. Buy it and it shows up on your plot.", price)
			else "That sale's yours, and a little extra from me. Buy the Rustbucket at the dealership and it shows up on your plot.",
		murphShort = if price > 0
			then string.format("Sell more wood at my cart first. The Rustbucket is $%d at the dealership.", price)
			else nil,
		event = "truckBought",
		count = 1,
		beacon = "dealership",
		cashItem = if price > 0 then rustbucket.displayName else nil,
		cashPrice = if price > 0 then price else nil,
	}
end

TutorialData.Steps = {
	plotStep(),
	{
		id = "fell",
		objective = "Chop down a tree",
		-- The hello and the grove are Murph's first-wave tip (NPCData). This
		-- line is only how to swing, so a new player doesn't hear it twice.
		murph = "Give one a whack. {Click}, or hold, to keep swingin'.",
		event = "treeFelled",
		count = 1,
		beacon = "tree",
		grove = true,
	},
	{
		id = "pickup",
		objective = "Pick up a log",
		murph = "Timber! Now grab those logs. You can carry two at a time.",
		event = "logPickedUp",
		count = 1,
		beacon = "log",
	},
	{
		id = "sell",
		objective = "Sell your first load at Murph's cart",
		murph = "My cart's right here. Stand by it and sell this first load. Same price as the mill.",
		event = "logsSold",
		count = 1,
		beacon = "murphCart",
		rewardCash = 25,
	},
	truckStep(1),
	{
		id = "load",
		objective = "Load logs into your truck",
		murph = "That's your Rustbucket. She ain't pretty, but she hauls. Load 'em up at the tailgate.",
		event = "logsLoaded",
		count = 1,
		beacon = "truck",
	},
	{
		id = "mill",
		objective = "Sell logs at the sawmill",
		murph = "Hop in and drive to the sawmill up north. Park close, stand on the pad and sell 'em.",
		event = "logsSold",
		count = 1,
		beacon = "sellPad",
	},
	{
		id = "plant",
		objective = "Fell a tree, then plant its Heartseed in the stump",
		murph = "Cut one, plant one, kid. Plant that seed in the stump and the forest'll thank you.",
		event = "seedPlanted",
		count = 1,
		beacon = "stump",
	},
	logLoad(
		"loads",
		8,
		"See it grow? That tree's yours. That Rusty Axe won't cut it in the hills. Sell another load and I'll chip in for a Steel Axe."
	),
	logLoad("loads2", 8, "Another load at the mill. You're getting the hang of the haul."),
	logLoad("loads3", 9, "One more load at the mill, and I'll chip in for that axe."),
	{
		id = "steel",
		objective = "Buy the Steel Axe at the Tool Shed",
		murph = "Here's a little somethin' from me. The Tool Shed's just west of the mill. Go get yourself a real axe, kid.",
		murphShort = string.format(
			"Sell more wood first. Then get the %s at the Tool Shed, just west of the mill.",
			steelAxe.displayName
		),
		event = "axeBought",
		count = 1,
		beacon = "toolShed",
		cashItem = steelAxe.displayName,
		cashPrice = ShopLogic.Price(steelAxe, 1),
	},
} :: { Step }

-- The v2 loop's steps. Wood is cut where you swing, dragged with the axe
-- put away, carried loose on the bed and sold by volume. Order: fell,
-- drag, sell at the cart, claim a plot, then the truck. The mill is the
-- trip after the truck. Each step's event is what the v2 services report.
-- Murph's numbers come from the v2 data: hits from FieldGuide.TrunkHits.
-- Saves from the plot-first order are remapped by ApplyOrder.
TutorialData.StepsV2 = {
	{
		id = "fell",
		objective = "Chop down a tree",
		murph = string.format(
			"Swing low on a trunk and keep hittin' the same spot: about %d whacks and she tips. {Click}, or hold, to keep swingin'.",
			FieldGuide.TrunkHits(starterAxe, oak)
		),
		murphBack = "Welcome back! Cut anywhere and drag the wood. The mill buys by the cubic unit. {Click}, or hold, to keep swingin'.",
		event = "treeFelled",
		count = 1,
		beacon = "tree",
		beaconWood = "oak",
		grove = true,
	},
	{
		id = "pickup",
		objective = "Drag a log",
		murph = "Timber! Put your axe away ({unequip}). Then {grab} on a log to drag it. Big ones are heavy: chop 'em shorter first.",
		event = "woodGrabbed",
		count = 1,
		beacon = "wood",
	},
	{
		id = "sell",
		objective = "Sell your first load at Murph's cart",
		murph = "Don't drive off yet. My cart's right beside you. Drag the log onto it and I'll buy this first load, same price the mill pays.",
		event = "woodSold",
		count = 1,
		beacon = "murphCart",
		rewardCash = 25,
	},
	plotStep(true),
	truckStep(2),
	{
		id = "load",
		objective = "Drag a log onto your truck's bed",
		murph = "That's your Rustbucket. She ain't pretty, but she hauls. Drag a log onto the bed and lay it flat. Too long? Cut it to fit.",
		event = "woodLoaded",
		count = 1,
		beacon = "truckBed",
	},
	{
		id = "mill",
		objective = "Sell wood at the sawmill",
		murph = "Drive to the mill up north and back onto the SELL LOGS HERE pad. The whole bed sells itself.",
		event = "woodSold",
		count = 1,
		beacon = "sellPad",
	},
	{
		id = "plant",
		objective = "Fell a tree, then plant its Heartseed in the stump",
		murph = "Cut one, plant one, kid. Plant that seed in the stump and the forest'll thank you.",
		event = "seedPlanted",
		count = 1,
		beacon = "stump",
	},
	cashLoad(
		"loads",
		8,
		string.format(
			"See it grow? That tree's yours. That %s takes %d hits a cut on birch. Sell another load and I'll chip in for a %s.",
			starterAxe.displayName,
			FieldGuide.TrunkHits(starterAxe, birch),
			steelAxe.displayName
		)
	),
	cashLoad("loads2", 8, "Another load at the mill. Haul it up north and sell it on the pad."),
	cashLoad("loads3", 9, "One more load at the mill. Then that axe is yours to buy."),
	{
		id = "steel",
		objective = "Buy the Steel Axe at the Tool Shed",
		murph = string.format(
			"Here's a little from me. Tink's Tool Shed is just west of the mill. A %s cuts an oak in %d hits, not %d. Go get a real axe, kid.",
			steelAxe.displayName,
			FieldGuide.TrunkHits(steelAxe, oak),
			FieldGuide.TrunkHits(starterAxe, oak)
		),
		murphShort = string.format(
			"Sell more wood first. Then get the %s at Tink's Tool Shed, just west of the mill.",
			steelAxe.displayName
		),
		event = "axeBought",
		count = 1,
		beacon = "toolShed",
		cashItem = steelAxe.displayName,
		cashPrice = ShopLogic.Price(steelAxe, 2),
	},
} :: { Step }

-- The events the v2 steps listen for, in step order (woodSold and
-- woodSoldCash each come up more than once).
local eventsV2: { TutorialEvent } = {}
for _, step in ipairs(TutorialData.StepsV2) do
	table.insert(eventsV2, step.event)
end
TutorialData.EventsV2 = eventsV2

-- The steps for `loop` (CoreLoop.Active()): StepsV2 under the v2 loop,
-- else Steps.
function TutorialData.ForLoop(loop: number): { Step }
	return if loop == 2 then TutorialData.StepsV2 else TutorialData.Steps
end

-- The line Murph says once the last step is done (both loops).
TutorialData.Farewell =
	"The plot's yours. Take the Field Guide. Bigger logs pay more by the u³, and a saw's planks pay more. Some woods only show at night."

-- What Murph says when a returning player's refresher is done.
TutorialData.FarewellBack =
	"That's the new way of it! Same woods, same mill: bigger logs pay more now, so cut 'em to fit your bed. Go get 'em."

-- Total cash the tutorial pays out (the economy model counts it toward the
-- first purchase): the v1 steps', or `loop`'s.
function TutorialData.TotalReward(loop: number?): number
	local total = 0
	for _, step in ipairs(TutorialData.ForLoop(loop or 1)) do
		total += step.rewardCash or 0
	end
	return total
end

-- How far a two-event step is: bit 0 is the main event, bit 1 is `also`.
local function bothBits(progress: number): number
	local bits = math.floor(progress)
	local n = 0
	if bit32.band(bits, 1) ~= 0 then
		n += 1
	end
	if bit32.band(bits, 2) ~= 0 then
		n += 1
	end
	return n
end

-- The tracker line for a step, with progress: "Sell 6 more logs (4/6)",
-- or for a step counted in dollars "Sell $40 more wood ($23/$40)". A step
-- with axeGoal adds " · $20 of $160 to Steel Axe" from `cash` (0 when it
-- isn't passed). A step with cashItem adds the same line toward that buy
-- (" · $51 of $75 to Rustbucket"). A step with `also` reads "(1/2)" from
-- the two bits.
function TutorialData.ObjectiveText(step: Step, progress: number, cash: number?): string
	local text = string.gsub(step.objective, "%%d", tostring(step.count))
	if step.also then
		text ..= string.format(" (%d/2)", bothBits(progress))
	elseif step.count > 1 then
		local done = math.min(progress, step.count)
		if step.unit == "cash" then
			text ..= string.format(" (%s/%s)", FieldGuide.CashText(done), FieldGuide.CashText(step.count))
		else
			text ..= string.format(" (%d/%d)", done, step.count)
		end
	end
	local item = step.cashItem
	local itemPrice = step.cashPrice
	if (item == nil or itemPrice == nil) and step.axeGoal and step.axePrice then
		item = "Steel Axe"
		itemPrice = step.axePrice
	end
	if item and itemPrice and itemPrice > 0 then
		local shown = if type(cash) == "number" then cash else 0
		text ..= string.format(" · %s of %s to %s", FieldGuide.CashText(shown), FieldGuide.CashText(itemPrice), item)
	end
	return text
end

-- Applies one event to a step's progress. Returns the new progress and
-- whether the step is done. A step with `also` stores two bits (1 = the
-- main event, 2 = the other) and finishes when both are set. Any other
-- step only counts its own event.
function TutorialData.Apply(step: Step, progress: number, event: TutorialEvent, amount: number): (number, boolean)
	if step.also then
		local bits = math.floor(progress)
		if event == step.event then
			bits = bit32.bor(bits, 1)
		elseif event == step.also then
			bits = bit32.bor(bits, 2)
		end
		return bits, bit32.band(bits, 3) == 3
	end
	if event ~= step.event then
		return progress, false
	end
	local nextProgress = progress + amount
	return nextProgress, nextProgress >= step.count
end

-- Whether a save on step `index` keeps its tutorialProgress when it moves
-- from the v1 loop to v2 (ProfileSchema.MigrateV2): only where the step
-- counts the same event in both (felling, planting, buying, claiming).
-- Where the event changed (logs picked up, loaded or sold), the old count
-- means something else, so it starts again.
function TutorialData.KeepsProgressV2(index: number): boolean
	local old = TutorialData.Steps[index]
	if not old then
		return false
	end
	for _, new in ipairs(TutorialData.StepsV2) do
		if new.id == old.id then
			return old.event == new.event
		end
	end
	return false
end

-- The Heartseed beat's place in the steps (found by id, so it follows the
-- step wherever it sits).
local function indexOf(id: string): number
	for i, step in ipairs(TutorialData.Steps) do
		if step.id == id then
			return i
		end
	end
	error("[TutorialData] no step " .. id)
end
TutorialData.PlantStep = indexOf("plant")

-- A save that came into the v2 loop with the tutorial finished gets a
-- refresher (ProfileSchema.MigrateV2, QuestService): StepsV2 up to and
-- including the first sale, the steps whose mechanics changed. Then it's
-- done again. The first sale is the cart, so the refresher ends there.
local function indexOfV2(id: string): number
	for i, step in ipairs(TutorialData.StepsV2) do
		if step.id == id then
			return i
		end
	end
	error("[TutorialData] no v2 step " .. id)
end
TutorialData.RefresherLast = indexOfV2("sell")

-- What Murph says for `step`: the short "sell more first" line while `cash`
-- is under the step's price, his welcome-back line on the refresher, or
-- the usual line.
function TutorialData.MurphLine(step: Step, refresher: boolean, cash: number?): string
	local price = step.cashPrice
	if not refresher and step.murphShort and type(price) == "number" and price > 0 then
		local have = if type(cash) == "number" and cash == cash then cash else 0
		if have < price then
			return step.murphShort
		end
	end
	return if refresher and step.murphBack then step.murphBack else step.murph
end

-- Where the arrow points. The truck step sends a player who can't afford
-- it back to Murph's cart; once they can, it points at the dealership.
-- Every other step uses its own beacon.
function TutorialData.Beacon(step: Step, cash: number?): BeaconTarget?
	local price = step.cashPrice
	if step.id == "truck" and type(price) == "number" and price > 0 then
		local have = if type(cash) == "number" and cash == cash then cash else 0
		if have < price then
			return "murphCart"
		end
	end
	return step.beacon
end

-- The v2 order before this list (plot led). A saved tutorialStep from that
-- order is a position here. ApplyOrder turns it into the new position.
TutorialData.OrderV2 = 2
TutorialData.OrderV2Previous = {
	"plot",
	"fell",
	"pickup",
	"sell",
	"truck",
	"load",
	"mill",
	"plant",
	"loads",
	"loads2",
	"loads3",
	"steel",
}

-- Old v2 index to the step's name, then that name's index in StepsV2.
-- An index this list doesn't have is returned as it is.
function TutorialData.RemapV2Step(oldIndex: number): number
	local name = TutorialData.OrderV2Previous[oldIndex]
	if type(name) ~= "string" then
		return oldIndex
	end
	for i, step in ipairs(TutorialData.StepsV2) do
		if step.id == name then
			return i
		end
	end
	return oldIndex
end

-- One profile or slot, once. A save still on the old first step (plot)
-- starts the new order at fell: jumping it to the plot's new index would
-- skip the chop and the cart. Any later index keeps that step by name.
-- A finished tutorial only gets the version stamp. Never touches the plot.
function TutorialData.ApplyOrder(record: any)
	if type(record) ~= "table" then
		return
	end
	if record.tutorialOrder == TutorialData.OrderV2 then
		return
	end
	if record.tutorialDone ~= true then
		local raw = tonumber(record.tutorialStep)
		local step = if type(raw) ~= "number" or raw ~= raw then 1 else math.floor(raw)
		if step > 1 then
			record.tutorialStep = TutorialData.RemapV2Step(step)
		else
			record.tutorialStep = 1
			record.tutorialProgress = 0
		end
	end
	record.tutorialOrder = TutorialData.OrderV2
end

-- How long a stump felled on the way to the plant step waits before its
-- tree grows back on its own (TreeService.HoldRegrow): long enough to haul
-- and sell a load and come back to plant in it.
TutorialData.StumpHoldSeconds = 240

-- Whether a player on tutorial step `step` (the TutorialStep attribute: 0
-- once it's finished or skipped) may plant a Heartseed. Before the plant
-- step they keep their seed: Murph shows them where.
function TutorialData.CanPlant(step: number): boolean
	return step <= 0 or step >= TutorialData.PlantStep
end

-- Seconds a tree felled by a player on step `step` keeps its stump (0 =
-- the usual regrowth): anyone still on the way to the plant step, so the
-- stump is there when Murph asks for it.
function TutorialData.StumpHold(step: number): number
	return if step > 0 and step <= TutorialData.PlantStep then TutorialData.StumpHoldSeconds else 0
end

-- Whether a player who's already past this step (from their save) should
-- have it done on the spot: they bought the Steel Axe, or they already
-- claimed a plot and the step doesn't still need a sapling.
function TutorialData.AlreadyDone(step: Step, bestAxeTier: number, plotClaimed: boolean?, ownsTruck: boolean?): boolean
	if step.event == "axeBought" and bestAxeTier >= 2 then
		return true
	end
	if step.event == "plotClaimed" and plotClaimed == true and step.also == nil then
		return true
	end
	if step.event == "truckBought" and ownsTruck == true then
		return true
	end
	return false
end

return TutorialData
