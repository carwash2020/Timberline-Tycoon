--!strict
-- TutorialData: Murph's tutorial (GAME_DESIGN §11), one objective at a time.
-- QuestService (server) counts progress from game events; QuestUI (client)
-- shows the objective, Murph's line and a beacon. Tuning = editing this.
--
-- Beats 5–7 of §11 (plot, first blueprint, Field Guide) join when plots
-- and the compendium exist. The last step here hands over to the Steel
-- Axe goal instead.

local TutorialData = {}

-- Game events QuestService listens for (the server reports them).
export type TutorialEvent = "treeFelled" | "logPickedUp" | "logsLoaded" | "logsSold" | "axeBought"

-- What the beacon points at (QuestUI finds it in the world).
export type BeaconTarget = "tree" | "log" | "truck" | "sellPad" | "toolShed"

export type Step = {
	id: string,
	objective: string, -- the tracker line; "%d" is replaced by the goal count
	murph: string, -- what Murph says when the step starts
	event: TutorialEvent,
	count: number, -- how many of `event` (logs, for the log events)
	beacon: BeaconTarget?,
	rewardCash: number?, -- paid when the step is done
}

TutorialData.Steps = {
	{
		id = "fell",
		objective = "Chop down a tree",
		murph = "Mornin'! I'm Murph. See that oak? Give it a whack. Click, or hold, to keep swingin'.",
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
		id = "loads",
		objective = "Sell %d more logs",
		murph = "Cha-ching! That Rusty Axe won't cut it in the hills, though. Sell a few more loads and I'll chip in for a Steel Axe.",
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

-- The line Murph says once the last step is done.
TutorialData.Farewell =
	"Now that's an axe! Pine grows in the hills, and every new wood pays better. Come find me if you get stuck."

-- Total cash the tutorial pays out (the economy model counts it toward the
-- first purchase).
function TutorialData.TotalReward(): number
	local total = 0
	for _, step in ipairs(TutorialData.Steps) do
		total += step.rewardCash or 0
	end
	return total
end

-- The tracker line for a step, with progress: "Sell 18 more logs (4/18)".
function TutorialData.ObjectiveText(step: Step, progress: number): string
	local text = string.gsub(step.objective, "%%d", tostring(step.count))
	if step.count > 1 then
		text ..= string.format(" (%d/%d)", math.min(progress, step.count), step.count)
	end
	return text
end

-- Whether a player who's already past this step (from their save) should
-- have it done on the spot, e.g. they bought the Steel Axe before the
-- tutorial asked.
function TutorialData.AlreadyDone(step: Step, bestAxeTier: number): boolean
	return step.event == "axeBought" and bestAxeTier >= 2
end

return TutorialData
