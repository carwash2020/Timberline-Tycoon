--!strict
-- TutorialData: Murph's tutorial (GAME_DESIGN §11), one objective at a time.
-- QuestService (server) counts progress from game events; QuestUI (client)
-- shows the objective, Murph's line and a beacon. Tuning = editing this.
--
-- v1 order: claim a plot, chop, pick up, sell the first load at the sawmill
-- (Murph chips in $25 on that sale), then buy the Rustbucket. After that
-- the old lessons stay: load, mill, plant, the three loads, and the Steel
-- Axe. QuestService then keeps one next goal on the tracker (NextGoal).
--
-- v2 order: fell, drag, sell at the sawmill, buy a plot at the Land Office
-- (nobody is given one: GameConfig.PlotPrice), the build lessons, then the
-- Rustbucket box, its pad and the truck, and the same lessons after it. tutorialStep is an index, so a save from
-- the plot-first v2 order is remapped by ApplyOrder (old index to the step
-- name, then that name's new index).
--
-- Short v2 list (order 6, 6 October 2026): playtesters found the tutorial
-- far too long, so StepsV2 is the essentials only: fell, drag, sell, plot,
-- one build lesson (place), then truck, pad, spawn. The steps cut from it
-- (build, land, load, mill, loads, loads2, loads3, steel) are RETIRED:
-- their ids stay in the old-order lists below and in RetiredV2, never
-- reused, and ApplyOrder moves a save that was on one forward to the next
-- remaining step (or to the end, which finishes the tutorial). The next
-- axe is one non-blocking line on the tracker afterwards (NextGoal) and
-- in Murph's Farewell, not a lesson.
--
-- Inserting a step shifts the ones after it: QuestService moves saves
-- made before the insert to the latest step they had reached (by the
-- funnel steps they've reached), so keep step ids stable.
--
-- The v2 core loop (V2_PLAN.md §13, Shared/CoreLoop) has its own steps,
-- StepsV2, with the v2 loop's words and events. ForLoop(loop) picks the
-- list; Steps is the v1 one.

local FieldGuide = require(script.Parent.FieldGuide)
local GameConfig = require(script.Parent.GameConfig)
local ItemCatalog = require(script.Parent.ItemCatalog)
local ShopLogic = require(script.Parent.ShopLogic)
local WoodData = require(script.Parent.WoodData)

local TutorialData = {}

-- Game events QuestService listens for (the server reports them). The
-- v2 loop adds wood events; plotClaimed is the open plot. buildOpened,
-- itemPlaced and landOpened are the build lessons after the claim (the
-- client reports the first and last through TutorialSeen). v2 trucks come in
-- a box with their own pad: truckBought is the box bought, padPlaced the pad
-- put down on the plot, truckSpawned the pad's button pressed (the truck
-- rolls out; VehicleService reports the last two).
export type TutorialEvent =
	"treeFelled"
	| "logPickedUp"
	| "logsLoaded"
	| "logsSold"
	| "axeBought"
	| "woodGrabbed"
	| "woodLoaded"
	| "woodSold"
	| "woodSoldCash"
	| "plotClaimed"
	| "truckBought"
	| "padPlaced"
	| "truckSpawned"
	| "buildOpened"
	| "itemPlaced"
	| "landOpened"

-- What the beacon points at (QuestUI finds it in the world). v2 adds
-- "wood" (your nearest loose piece, tag Wood) and "truckBed" (your
-- truck's bed). "sellPad" is the sawmill's sell pad; "plotSign" is plot 1;
-- "landOffice" is the counter that sells the first plot.
export type BeaconTarget =
	"tree"
	| "log"
	| "truck"
	| "sellPad"
	| "toolShed"
	| "wood"
	| "truckBed"
	| "plotSign"
	| "landOffice"
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
	rewardToast: boolean?, -- false: no "Murph chipped in" toast (the next card says it)
	murphBack: string?, -- v2: what Murph says instead to a returning player on the refresher (RefresherLast)
	murphShort: string?, -- said instead while cash is under cashPrice ("sell more first")
	axeGoal: boolean?, -- the tracker also shows cash toward the Steel Axe
	axePrice: number?, -- that axe's price in this loop
	cashItem: string?, -- tracker suffix " · $51 of $75 to Rustbucket"
	cashPrice: number?, -- that purchase's price; with murphShort, the short line while cash is under it
	also: TutorialEvent?, -- a second event; both must happen (progress stores the two bits)
}

local starterAxe = ItemCatalog.AxeLadder()[1]
local steelAxe = ItemCatalog.AxeLadder()[2] -- AlreadyDone's tier 2
local oak = WoodData.Get("oak") :: WoodData.WoodDef
local rustbucket = ItemCatalog.GetTruck("Rustbucket") :: ItemCatalog.TruckDef

-- Murph chips in when the plot is bought, so the plot and then the
-- Rustbucket box are both within reach of what the sawmill pays for the
-- first oaks (tools/economy models it; tests/TutorialGrove.spec checks it).
local PLOT_REWARD = 175

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

-- The first plot is bought, not given (v2: the step right after the first
-- sale). The event is still plotClaimed: the server reports it when the
-- purchase goes through (PlotService). The v1 order keeps its free-plot
-- wording for a rollback, with the same event.
local function plotStep(afterSale: boolean?): Step
	if not afterSale then
		return {
			id = "plot",
			objective = "Claim an open plot",
			murph = "Every lumberjack needs land. Claim an open plot, follow the arrow.",
			event = "plotClaimed",
			count = 1,
			beacon = "plotSign",
		}
	end
	local price = GameConfig.PlotPrice
	return {
		id = "plot",
		objective = "Buy a plot at the Land Office",
		murph = string.format(
			"That sale's yours, and a little extra from me. A plot is $%d at the Land Office in town. Buy one, follow the arrow.",
			price
		),
		murphShort = string.format(
			"Sell more wood at the sawmill first. A plot is $%d at the Land Office in town.",
			price
		),
		event = "plotClaimed",
		count = 1,
		beacon = "landOffice",
		cashItem = "a plot",
		cashPrice = price,
		rewardCash = PLOT_REWARD,
	}
end

local function truckStep(loop: number): Step
	local price = ShopLogic.Price(rustbucket, loop)
	local boxed = loop == 2 -- v2: a box with its own pad; v1: handed over
	return {
		id = "truck",
		objective = if boxed
			then "Buy the Rustbucket box at the dealership"
			else "Buy the Rustbucket at the dealership",
		murph = if boxed
			then string.format(
				"The Rustbucket is $%d at the dealership. It comes in a box with its own pad. Buy it and carry it to your plot.",
				price
			)
			elseif price > 0 then string.format(
				"The Rustbucket is $%d at the dealership. Buy it and it shows up on your plot.",
				price
			)
			else "That sale's yours, and a little extra from me. Buy the Rustbucket at the dealership and it shows up on your plot.",
		murphShort = if price > 0
			then string.format("Sell more wood at the sawmill first. The Rustbucket is $%d at the dealership.", price)
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
		objective = "Sell your first load at the sawmill",
		murph = "Take it up to the sawmill's sell pad up north, and sell this first load.",
		event = "logsSold",
		count = 1,
		beacon = "sellPad",
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
	logLoad(
		"loads",
		8,
		"That Rusty Axe won't cut it in the hills. Sell another load and I'll chip in for a Steel Axe."
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
-- drag, sell at the sawmill, claim a plot, the build lessons (hammer, place
-- one item), then the truck, its pad and spawning it. Each step's event is
-- what the v2 services report.
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
		objective = "Sell your first load at the sawmill",
		murph = "Drag that log up north to the sawmill's sell pad, and set it down on the pad. The mill pays by the cubic unit.",
		event = "woodSold",
		count = 1,
		beacon = "sellPad",
		rewardCash = 25,
		rewardToast = false, -- the plot step's card opens "That sale's yours, and a little extra from me"
	},
	plotStep(true),
	{
		id = "place",
		objective = "Place one blueprint with your hammer",
		murph = "Pick the cheapest piece in your blueprints and set it down. You pay when you place it, and you get half back if you sell it.",
		event = "itemPlaced",
		count = 1,
	},
	truckStep(2),
	{
		id = "pad",
		objective = "Open the box on your plot and place its pad",
		murph = "Carry the box onto your land and open it. The pad's inside: set it down anywhere you like. Your truck comes out of that pad.",
		event = "padPlaced",
		count = 1,
	},
	{
		id = "spawn",
		objective = "Press the pad's button to bring out your truck",
		murph = "Walk up to the pad and press its button. That's how the Rustbucket rolls out, and how you get her back if she's ever stuck.",
		event = "truckSpawned",
		count = 1,
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

-- The joy beat when the tutorial is finished (not skipped): a banner, a
-- chime and client confetti (QuestUI.JoyBeat). The banner's second line is
-- the player's next goal (the NextGoal attribute), so the end of the lessons
-- always shows where to go.
TutorialData.JoyTitle = "LESSONS DONE!"
TutorialData.JoySub = "The forest is yours. Next: %s"
TutorialData.JoySeconds = 3.2
TutorialData.JoyConfetti = 36

function TutorialData.JoyLine(nextGoal: unknown): string
	local goal = if type(nextGoal) == "string" and nextGoal ~= "" then nextGoal else "sell wood and buy a better axe"
	return string.format(TutorialData.JoySub, goal)
end

-- The line Murph says once the last step is done (both loops).
TutorialData.Farewell =
	"That's the lot! Sell wood at the sawmill up north, and grab a better axe at Tink's Tool Shed. Bigger logs and planks pay more."

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

-- The starter cash a player who skips on step `fromIndex` is paid: every
-- step's cash from that step on, the steps they were about to earn it from.
-- (A skip pays it once, in one lump; the finished steps already paid.)
function TutorialData.SkipCash(loop: number?, fromIndex: number): number
	local total = 0
	for i, step in ipairs(TutorialData.ForLoop(loop or 1)) do
		if i >= fromIndex then
			total += step.rewardCash or 0
		end
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

-- A save that came into the v2 loop with the tutorial finished gets a
-- refresher (ProfileSchema.MigrateV2, QuestService): StepsV2 up to and
-- including the first sale, the steps whose mechanics changed. Then it's
-- done again. The first sale is the sawmill's, so the refresher ends there.
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

-- Where the arrow points. The plot and truck steps send a player who can't
-- afford them back to the sawmill's sell pad; once they can, it points at the Land
-- Office or the dealership.
-- Every other step uses its own beacon.
function TutorialData.Beacon(step: Step, cash: number?): BeaconTarget?
	local price = step.cashPrice
	if (step.id == "truck" or step.id == "plot") and type(price) == "number" and price > 0 then
		local have = if type(cash) == "number" and cash == cash then cash else 0
		if have < price then
			return "sellPad"
		end
	end
	return step.beacon
end

-- Order 1 (and 0): plot led. Order 2: fell led, and still had a plant step.
-- Order 3: that step is gone. Order 4: build, place and land follow the plot
-- step. Order 5: the pad and spawn steps follow the truck. Order 6: the
-- short list (RetiredV2 are gone). ApplyOrder turns a saved index into this
-- list.
TutorialData.OrderV2 = 6
-- The plot-first list (order 0 and 1).
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
-- The fell-first list that still included plant (order 2).
TutorialData.OrderV2WithPlant = {
	"fell",
	"pickup",
	"sell",
	"plot",
	"truck",
	"load",
	"mill",
	"plant",
	"loads",
	"loads2",
	"loads3",
	"steel",
}

-- The list as order 3 had it (no build lessons).
TutorialData.OrderV2BeforeBuild = {
	"fell",
	"pickup",
	"sell",
	"plot",
	"truck",
	"load",
	"mill",
	"loads",
	"loads2",
	"loads3",
	"steel",
}

-- The list as order 4 had it (no pad or spawn steps).
TutorialData.OrderV2BeforePad = {
	"fell",
	"pickup",
	"sell",
	"plot",
	"build",
	"place",
	"land",
	"truck",
	"load",
	"mill",
	"loads",
	"loads2",
	"loads3",
	"steel",
}

-- The list as order 5 had it (the long tutorial, before the short one).
TutorialData.OrderV2BeforeShort = {
	"fell",
	"pickup",
	"sell",
	"plot",
	"build",
	"place",
	"land",
	"truck",
	"pad",
	"spawn",
	"load",
	"mill",
	"loads",
	"loads2",
	"loads3",
	"steel",
}

-- Where a retired step's save goes. A step name lands on that step (it
-- must be in StepsV2 or retired itself); END means the tutorial is over.
-- Never reuse a retired id for a new step. "plant" went first; the later
-- cuts follow the order 5 list: build and land were lessons before the
-- truck, so they hand on to the step after them; everything from the
-- truck's load onward (load, mill, the sell-more loads, the axe) comes
-- after spawn, so a save on one has done the essentials: END.
local END = "$end"
local RETIRED_STEP: { [string]: string } = {
	plant = "loads",
	build = "place",
	land = "truck",
	load = END,
	mill = END,
	loads = END,
	loads2 = END,
	loads3 = END,
	steel = END,
}

-- The retired v2 ids, for specs and anyone wondering whether an id is free.
TutorialData.RetiredV2 = {} :: { [string]: boolean }
for id in pairs(RETIRED_STEP) do
	TutorialData.RetiredV2[id] = true
end

-- Resolves a name through RETIRED_STEP to a step index in StepsV2, or one
-- past the end for END. Nil when the name isn't a step at all.
local function indexOfName(name: string): number?
	for _ = 1, 8 do -- a retired step may hand on to another retired one
		local to = RETIRED_STEP[name]
		if to == nil then
			break
		end
		name = to
	end
	if name == END then
		return #TutorialData.StepsV2 + 1
	end
	for i, step in ipairs(TutorialData.StepsV2) do
		if step.id == name then
			return i
		end
	end
	return nil
end

local function remapFrom(list: { string }, oldIndex: number): number
	local name = list[oldIndex]
	if type(name) ~= "string" then
		return oldIndex
	end
	return indexOfName(name) or oldIndex
end

-- A plot-first index to the step's name, then that name's index in StepsV2.
-- An index this list doesn't have is returned as it is. "plant" lands on loads.
function TutorialData.RemapV2Step(oldIndex: number): number
	return remapFrom(TutorialData.OrderV2Previous, oldIndex)
end

-- One profile or slot, once. A save still on the old first step (plot)
-- starts the new order at fell: jumping it to the plot's new index would
-- skip the chop and the first sale. A save already on the fell-first list (order
-- 2) keeps each step by name, and the removed plant step becomes loads.
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
		local order = tonumber(record.tutorialOrder) or 0
		local list: { string }? = nil
		if order == 5 then
			list = TutorialData.OrderV2BeforeShort
		elseif order == 4 then
			list = TutorialData.OrderV2BeforePad
		elseif order == 3 then
			list = TutorialData.OrderV2BeforeBuild
		elseif order >= 2 then
			list = TutorialData.OrderV2WithPlant
		elseif step > 1 then
			list = TutorialData.OrderV2Previous
		end
		if list then
			local name = list[step]
			record.tutorialStep = remapFrom(list, step)
			if type(name) == "string" and RETIRED_STEP[name] ~= nil then
				record.tutorialProgress = 0 -- progress toward a cut step means nothing on the next one
			end
		else
			record.tutorialStep = 1
			record.tutorialProgress = 0
		end
	end
	record.tutorialOrder = TutorialData.OrderV2
end

-- Whether a player who's already past this step (from their save) should
-- have it done on the spot: they bought the Steel Axe, or they already
-- claimed a plot and the step doesn't still need a sapling.
function TutorialData.AlreadyDone(
	step: Step,
	bestAxeTier: number,
	plotClaimed: boolean?,
	ownsTruck: boolean?,
	hasPlaced: boolean?,
	hasPad: boolean?
): boolean
	if step.event == "axeBought" and bestAxeTier >= 2 then
		return true
	end
	if step.event == "plotClaimed" and plotClaimed == true and step.also == nil then
		return true
	end
	if step.event == "truckBought" and ownsTruck == true then
		return true
	end
	if step.event == "padPlaced" and hasPad == true then
		return true
	end
	if step.event == "itemPlaced" and hasPlaced == true then
		return true
	end
	return false
end

return TutorialData
