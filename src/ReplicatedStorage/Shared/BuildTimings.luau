--!strict
-- BuildTimings: what each step of the world build cost, in order, and
-- whether it gates play. Pure (seconds are passed in), so a spec can feed it
-- a fake build and MapBuilder just records each top-level step.
--
-- The target (Connor, 12 October 2026, after a Studio load of 300 s): a
-- player can play within PlayBudgetSeconds of joining. The steps that run
-- before the world gate opens (terrain, the town, the shops, ...) are
-- "gating"; the deferred build and the mesh loads are not and are never
-- counted here.

local BuildTimings = {}

BuildTimings.PlayBudgetSeconds = 15
-- One gating step that alone takes this long is named in the report.
BuildTimings.StepWarnSeconds = 3

export type Step = { name: string, seconds: number, gating: boolean }

export type Timings = {
	Record: (name: string, seconds: number, gating: boolean?) -> (),
	Steps: () -> { Step },
	GatingSeconds: () -> number,
	OverBudget: (budget: number?) -> boolean,
	Slowest: () -> Step?,
	Lines: (budget: number?) -> { string },
}

function BuildTimings.new(): Timings
	local steps: { Step } = {}
	local timings = {} :: Timings

	timings.Record = function(name: string, seconds: number, gating: boolean?)
		if type(seconds) ~= "number" or seconds ~= seconds or seconds < 0 then
			seconds = 0
		end
		table.insert(steps, { name = name, seconds = seconds, gating = gating ~= false })
	end

	timings.Steps = function(): { Step }
		return steps
	end

	timings.GatingSeconds = function(): number
		local total = 0
		for _, step in ipairs(steps) do
			if step.gating then
				total += step.seconds
			end
		end
		return total
	end

	timings.OverBudget = function(budget: number?): boolean
		return timings.GatingSeconds() > (budget or BuildTimings.PlayBudgetSeconds)
	end

	timings.Slowest = function(): Step?
		local slowest: Step? = nil
		for _, step in ipairs(steps) do
			if step.gating and (slowest == nil or step.seconds > slowest.seconds) then
				slowest = step
			end
		end
		return slowest
	end

	-- One line per gating step, then the total against the budget.
	timings.Lines = function(budget: number?): { string }
		local limit = budget or BuildTimings.PlayBudgetSeconds
		local lines: { string } = {}
		for _, step in ipairs(steps) do
			if step.gating then
				local flag = if step.seconds >= BuildTimings.StepWarnSeconds then "  <-- slow" else ""
				table.insert(lines, string.format("  %-34s %6.2fs%s", step.name, step.seconds, flag))
			end
		end
		local total = timings.GatingSeconds()
		table.insert(
			lines,
			string.format(
				"gating build %.1fs of %.0fs budget: %s",
				total,
				limit,
				if total > limit then "OVER BUDGET (something is waiting on an asset or doing too much)" else "ok"
			)
		)
		return lines
	end

	return timings
end

return BuildTimings
