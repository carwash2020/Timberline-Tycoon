--!strict
-- ForemanData: Rook Calloway, the Sawmill Foreman, who pays the day's jobs.
-- Pure rules and lines shared by DailyService (the server pays), DailyUI and
-- NPCController (the box and the panel say what is owed) and the specs.
--
-- A finished daily goal is not paid the moment it finishes: it waits,
-- `done` and not `paid`, until the player hands it in to Rook. Finishing
-- all of the day's goals earns the streak bonus, owed the same way
-- (`daily.bonusOwed`). Anything still owed when the day resets is paid
-- then, so a missed visit never loses money (DailyService). The reset is
-- at UTC midnight, so "new jobs in" counts down rather than saying
-- "tomorrow" (6 PM in Mountain Time).

local DailyData = require(script.Parent.DailyData)

local ForemanData = {}

ForemanData.Id = "Foreman"
ForemanData.Name = "Rook Calloway"
ForemanData.Role = "Sawmill Foreman"

-- Cash the foreman holds for the player: every finished goal not yet paid,
-- plus the all-done bonus (and any remainder a full wallet left owed).
-- Returns (total, finished goals waiting).
function ForemanData.Owed(goals: { DailyData.Goal }, bonusOwed: number?): (number, number)
	local total, waiting = 0, 0
	for _, goal in ipairs(goals) do
		if goal.done and goal.paid == false then
			total += goal.reward
			waiting += 1
		end
	end
	local extra = bonusOwed or 0
	if extra > 0 then
		total += extra
	end
	return total, waiting
end

-- "5h 12m" or "12m" until `resetAt` (UTC midnight).
function ForemanData.Countdown(resetAt: number, now: number): string
	local seconds = math.max(0, resetAt - now)
	local hours = seconds // 3600
	local minutes = (seconds % 3600) // 60
	if hours > 0 then
		return string.format("%dh %02dm", hours, minutes)
	end
	return string.format("%dm", math.max(1, minutes))
end

export type State = {
	tutorial: boolean, -- Murph's lessons are still running
	goals: { DailyData.Goal },
	bonusOwed: number,
	streak: number,
	countdown: string, -- ForemanData.Countdown
}

local function cash(n: number): string
	local out = tostring(math.floor(n))
	while true do
		local nextText, hits = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
		out = nextText
		if hits == 0 then
			break
		end
	end
	return "$" .. out
end

-- What Rook says when you talk to him: two short sentences, so the box
-- stays at two lines on a phone.
function ForemanData.Lines(state: State): { string }
	if state.tutorial then
		return { "Finish with Murph first.", "Then come to me for three jobs a day." }
	end
	local total, waiting = ForemanData.Owed(state.goals, state.bonusOwed)
	local open, finished = 0, 0
	for _, goal in ipairs(state.goals) do
		if goal.done then
			finished += 1
		else
			open += 1
		end
	end
	if total > 0 then
		local streak = if open == 0 and state.streak > 1 then string.format(" %d days running!", state.streak) else ""
		return {
			string.format("%s for you.%s", cash(total), streak),
			if waiting > 0
				then string.format("%d job%s to hand in.", waiting, if waiting == 1 then "" else "s")
				else "Wallet's full. Come back after a sale.",
		}
	end
	if #state.goals > 0 and open == 0 then
		return { "All paid. Good work.", "New jobs in " .. state.countdown .. "." }
	end
	if finished > 0 then
		return { "Paid so far. Keep at it.", string.format("%d job%s left today.", open, if open == 1 then "" else "s") }
	end
	return { "Three jobs today.", "Finish one and come back for your pay." }
end

return ForemanData
