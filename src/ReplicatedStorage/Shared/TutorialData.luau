--!strict
-- TutorialData: Murph's tutorial (GAME_DESIGN §11), one objective at a time.
-- QuestService (server) counts progress from game events; QuestUI (client)
-- shows the objective, Murph's line and a beacon. Tuning = editing this.
--
-- Order: claim a plot, chop, pick up, sell the first load at Murph's cart
-- (he chips in $25 on that sale), then buy the Rustbucket (delivered to
-- the plot's pad). After that the old lessons stay: load, mill, plant,
-- the three loads, and the Steel Axe. QuestService then keeps one next
-- goal on the tracker (NextGoal).
--
-- Inserting a step shifts the ones after it: QuestService moves saves
-- made before the insert to the latest step they had reached (by the
-- funnel steps they've reached), so keep step ids stable.
--
-- The v2 core loop (V2_PLAN.md §13, Shared/CoreLoop) has its own steps,
-- StepsV2: the same ids in the same order (saves carry over), with the
-- v2 loop's words and events. ForLoop(loop) picks the list; Steps is the
-- v1 one.

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
	axeGoal: boolean?, -- the tracker also shows cash toward the Steel Axe
	axePrice: number?, -- that axe's price in this loop
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

local function plotStep(): Step
	return {
		id = "plot",
		objective = if saplings then "Claim a free plot and plant a sapling" else "Claim a free plot",
		murph = if saplings
			then "Every lumberjack needs land, and this one's free. The plot district is east of town, past the lot. Claim one, then plant a sapling on it."
			else "Every lumberjack needs land, and this one's free. The plot district is east of town, past the lot. Claim one.",
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
			then string.format(
				"That sale's yours, and a little extra from me. The Rustbucket is $%d at the dealership. Buy it and it shows up on your plot.",
				price
			)
			else "That sale's yours, and a little extra from me. Buy the Rustbucket at the dealership and it shows up on your plot.",
		event = "truckBought",
		count = 1,
		beacon = "dealership",
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
		"See it grow? That tree's yours now. That Rusty Axe won't cut it in the hills, though. Sell another load at the mill and I'll chip in for a Steel Axe."
	),
	logLoad("loads2", 8, "Another load at the mill. You're getting the hang of the haul."),
	logLoad("loads3", 9, "One more load at the mill, and I'll chip in for that axe."),
	{
		id = "steel",
		objective = "Buy the Steel Axe at the Tool Shed",
		murph = "Here's a little somethin' from me. The Tool Shed's just west of the mill. Go get yourself a real axe, kid.",
		event = "axeBought",
		count = 1,
		beacon = "toolShed",
	},
} :: { Step }

-- The v2 loop's steps: the same ids in the same order as Steps. Wood is
-- cut where you swing, dragged with your axe put away, carried loose on
-- the bed and sold by volume. The first sale is the cart; the mill is the
-- trip after the truck. Each step's event is what the v2 services report.
-- Murph's numbers come from the v2 data: hits from FieldGuide.TrunkHits.
TutorialData.StepsV2 = {
	plotStep(),
	{
		id = "fell",
		objective = "Chop down a tree",
		murph = string.format(
			"Swing low on a trunk and keep hittin' the same spot: about %d whacks and she tips. {Click}, or hold, to keep swingin'.",
			FieldGuide.TrunkHits(starterAxe, oak)
		),
		murphBack = "Welcome back! The little oaks are just to your left. Things work different now: cut a tree anywhere, drag the wood, and the mill buys it by the cubic unit. Swing low on a trunk and keep hittin' the same spot till she tips. {Click}, or hold, to keep swingin'.",
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
	truckStep(2),
	{
		id = "load",
		objective = "Drag a log onto your truck's bed",
		murph = "That was the easy one. That's your Rustbucket. She ain't pretty, but she hauls. Drag a log up onto her bed and lay it flat so it rides. Too long for the bed? Cut it to fit.",
		event = "woodLoaded",
		count = 1,
		beacon = "truckBed",
	},
	{
		id = "mill",
		objective = "Sell wood at the sawmill",
		murph = "Hop in and drive to the mill up north. Back her onto the pad that says SELL LOGS HERE and the whole bed sells itself, or push a log onto it by hand. Bigger logs pay more: it's all by the cubic unit, u³. A saw from the Tool Shed turns straight logs into planks, and planks pay more.",
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
			"See it grow? That tree's yours now. That %s of yours takes %d hits a cut on birch, though. Sell another load at the mill and I'll chip in for a %s.",
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
			"Here's a little somethin' from me. Tink's Tool Shed is just west of the mill. A %s cuts an oak trunk in %d hits, not %d. Go get yourself a real axe, kid.",
			steelAxe.displayName,
			FieldGuide.TrunkHits(steelAxe, oak),
			FieldGuide.TrunkHits(starterAxe, oak)
		),
		event = "axeBought",
		count = 1,
		beacon = "toolShed",
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
	"The plot's yours, and that axe will do. Take my old Field Guide: every new wood you fell goes in it. Pine grows in the hills. And kid, some woods only show at night."

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
-- isn't passed). A step with `also` reads "(1/2)" from the two bits.
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
	if step.axeGoal and step.axePrice then
		local shown = if type(cash) == "number" then cash else 0
		text ..= string.format(
			" · %s of %s to Steel Axe",
			FieldGuide.CashText(shown),
			FieldGuide.CashText(step.axePrice)
		)
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
	local old, new = TutorialData.Steps[index], TutorialData.StepsV2[index]
	return old ~= nil and new ~= nil and old.event == new.event
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

-- What Murph says for `step`: his welcome-back line on the refresher, when
-- the step has one.
function TutorialData.MurphLine(step: Step, refresher: boolean): string
	return if refresher and step.murphBack then step.murphBack else step.murph
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
