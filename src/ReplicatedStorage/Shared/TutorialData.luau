--!strict
-- TutorialData: Murph's tutorial (GAME_DESIGN §11), one objective at a time.
-- QuestService (server) counts progress from game events; QuestUI (client)
-- shows the objective, Murph's line and a beacon. Tuning = editing this.
--
-- Beats 5–7 of §11 (plot, first blueprint, Field Guide) join when plots
-- and the compendium exist. The last step here hands over to the Steel
-- Axe goal instead. Right after the first sale Murph teaches the Living
-- Forest's habit (GAME_DESIGN §16): plant a Heartseed in a stump.
--
-- Inserting a step shifts the ones after it: QuestService moves saves
-- made before the insert to the step they were really on (by the funnel
-- steps they've reached), so keep step ids stable.
--
-- The v2 core loop (V2_PLAN.md §13, Shared/CoreLoop) has its own steps,
-- StepsV2: the same ids in the same order (saves carry over), with the
-- v2 loop's words and events. ForLoop(loop) picks the list; Steps is the
-- v1 one, unchanged.

local FieldGuide = require(script.Parent.FieldGuide)
local ItemCatalog = require(script.Parent.ItemCatalog)
local WoodData = require(script.Parent.WoodData)

local TutorialData = {}

-- Game events QuestService listens for (the server reports them). The
-- last four are new with the v2 loop (EventsV2 lists the seven it uses).
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

-- What the beacon points at (QuestUI finds it in the world; "stump" is a
-- stump you hold a Heartseed for, which ForestUI also marks). v2 adds
-- "wood" (your nearest loose piece, tag Wood) and "truckBed" (your
-- truck's bed).
export type BeaconTarget = "tree" | "log" | "truck" | "sellPad" | "stump" | "toolShed" | "wood" | "truckBed"

export type Step = {
	id: string,
	objective: string, -- the tracker line; "%d" is replaced by the goal count
	murph: string, -- what Murph says when the step starts ({click} / {Click}: the device's word, HintLogic.Expand)
	event: TutorialEvent,
	count: number, -- how many of `event` (logs, for the log events)
	beacon: BeaconTarget?,
	beaconWood: string?, -- v2: the wood the "tree" beacon looks for first (a WoodData id)
	unit: "cash"?, -- v2: `count` is dollars, so the tracker reads "($23/$60)"
	rewardCash: number?, -- paid when the step is done
	murphBack: string?, -- v2: what Murph says instead to a returning player on the refresher (RefresherLast)
}

TutorialData.Steps = {
	{
		id = "fell",
		objective = "Chop down a tree",
		murph = "Mornin'! I'm Murph. See the woods south of town, past the parking lot? Find an oak and give it a whack. {Click}, or hold, to keep swingin'.",
		event = "treeFelled",
		count = 1,
		beacon = "tree",
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
		id = "load",
		objective = "Load logs into your truck",
		murph = "That's your Rustbucket. She ain't pretty, but she hauls. Load 'em up at the tailgate.",
		event = "logsLoaded",
		count = 1,
		beacon = "truck",
	},
	{
		id = "sell",
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
	{
		id = "loads",
		objective = "Sell %d more logs",
		murph = "See it grow? That tree's yours now. That Rusty Axe won't cut it in the hills, though. Sell a few more loads and I'll chip in for a Steel Axe.",
		event = "logsSold",
		count = 18,
		rewardCash = 25,
	},
	{
		id = "steel",
		objective = "Buy the Steel Axe at the Tool Shed",
		murph = "Here's a little somethin' from me. The Tool Shed's just west of the mill. Go get yourself a real axe, kid.",
		event = "axeBought",
		count = 1,
		beacon = "toolShed",
	},
} :: { Step }

-- The v2 loop's steps (V2_PLAN.md §13): the same ids in the same order as
-- Steps. Wood is cut where you swing, dragged with your axe put away,
-- carried loose on the bed and sold by volume on the pad. Each step's
-- event is what the v2 services report (QuestService.Event):
--   treeFelled    a tree you felled (the first cut through its trunk)
--   woodGrabbed   a piece you started dragging
--   woodLoaded    a piece of yours came to rest on your truck's bed
--   woodSold      pieces of yours sold on the pad (amount = pieces)
--   seedPlanted   a Heartseed planted in a stump
--   woodSoldCash  the same sale's cash (amount = whole dollars credited)
--   axeBought     an axe bought at the Tool Shed
-- Murph's numbers come from the v2 data: hits from FieldGuide.TrunkHits
-- (the starter axe and the next one on the ladder, on oak and birch).
local starterAxe = ItemCatalog.AxeLadder()[1]
local steelAxe = ItemCatalog.AxeLadder()[2] -- AlreadyDone's tier 2
local oak = WoodData.Get("oak") :: WoodData.WoodDef
local birch = WoodData.Get("birch") :: WoodData.WoodDef

TutorialData.StepsV2 = {
	{
		id = "fell",
		objective = "Chop down a tree",
		murph = string.format(
			"Mornin'! I'm Murph. Follow the arrow to the oaks south of town, past the parking lot. Swing low on a trunk and keep hittin' the same spot: about %d whacks and she tips. {Click}, or hold, to keep swingin'.",
			FieldGuide.TrunkHits(starterAxe, oak)
		),
		-- (no hit count: a returning player's axe is likely better than the Rusty Axe)
		murphBack = "Welcome back! Things work different now: cut a tree anywhere, drag the wood, and the mill buys it by the cubic unit. Swing low on a trunk and keep hittin' the same spot till she tips. {Click}, or hold, to keep swingin'.",
		event = "treeFelled",
		count = 1,
		beacon = "tree",
		beaconWood = "oak",
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
		id = "load",
		objective = "Drag a log onto your truck's bed",
		murph = "That's your Rustbucket. She ain't pretty, but she hauls. Drag a log up onto her bed and lay it flat so it rides. Too long for the bed? Cut it to fit.",
		event = "woodLoaded",
		count = 1,
		beacon = "truckBed",
	},
	{
		id = "sell",
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
	{
		id = "loads",
		objective = "Sell $%d more wood",
		murph = string.format(
			"See it grow? That tree's yours now. That %s of yours takes %d hits a cut on birch, though. Sell a bigger load and I'll chip in for a %s.",
			starterAxe.displayName,
			FieldGuide.TrunkHits(starterAxe, birch),
			steelAxe.displayName
		),
		event = "woodSoldCash",
		count = 120, -- StartingCash + this + the reward reaches the Steel Axe's v2 price
		unit = "cash",
		rewardCash = 25,
	},
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

-- The events the v2 steps listen for.
TutorialData.EventsV2 = {
	"treeFelled",
	"woodGrabbed",
	"woodLoaded",
	"woodSold",
	"seedPlanted",
	"woodSoldCash",
	"axeBought",
} :: { TutorialEvent }

-- The steps for `loop` (CoreLoop.Active()): StepsV2 under the v2 loop,
-- else Steps.
function TutorialData.ForLoop(loop: number): { Step }
	return if loop == 2 then TutorialData.StepsV2 else TutorialData.Steps
end

-- The line Murph says once the last step is done (both loops).
TutorialData.Farewell =
	"Now that's an axe! Take my old Field Guide: every new wood you fell goes in it. Pine grows in the hills. And kid, some woods only show at night."

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

-- The tracker line for a step, with progress: "Sell 18 more logs (4/18)",
-- or for a step counted in dollars "Sell $60 more wood ($23/$60)".
function TutorialData.ObjectiveText(step: Step, progress: number): string
	local text = string.gsub(step.objective, "%%d", tostring(step.count))
	if step.count > 1 then
		local done = math.min(progress, step.count)
		if step.unit == "cash" then
			text ..= string.format(" (%s/%s)", FieldGuide.CashText(done), FieldGuide.CashText(step.count))
		else
			text ..= string.format(" (%d/%d)", done, step.count)
		end
	end
	return text
end

-- Whether a save on step `index` keeps its tutorialProgress when it moves
-- from the v1 loop to v2 (ProfileSchema.MigrateV2): only where the step
-- counts the same event in both (felling, planting, buying). Where the
-- event changed (logs picked up, loaded or sold), the old count means
-- something else, so it starts again.
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
-- done again.
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
-- have it done on the spot, e.g. they bought the Steel Axe before the
-- tutorial asked.
function TutorialData.AlreadyDone(step: Step, bestAxeTier: number): boolean
	return step.event == "axeBought" and bestAxeTier >= 2
end

return TutorialData
