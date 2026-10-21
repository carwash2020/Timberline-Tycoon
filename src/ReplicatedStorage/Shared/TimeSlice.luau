--!strict
-- TimeSlice: "work for a few milliseconds, then give the frame back". One
-- tested place for the budget-and-yield pattern that the forest planter, the
-- deferred build queue (Shared/LoadQueue) and the client's forest plan all
-- use, so a long job never freezes the server or the client for a whole
-- frame. Call `step()` after each small unit of work: it yields (and starts
-- a new slice) only when the budget is spent, and says whether it did.
--
-- A slice can also take a shared FrameBudget (`frame`): it then yields when
-- that frame's budget is spent by ANY job, not only when its own is, so the
-- forest, the terrain and the deferred queue do not stack their slices.
--
-- The clock and the wait are injected so the specs can run it without a
-- scheduler; the defaults are os.clock and task.wait.

local FrameBudget = require(script.Parent.FrameBudget)

local TimeSlice = {}

export type FrameBudgetLike = FrameBudget.Budget

export type Options = {
	budget: number?, -- seconds of work per slice (default 0.012; none of its own when `frame` is given)
	frame: FrameBudgetLike?, -- a budget shared with other jobs (Shared/FrameBudget)
	clock: (() -> number)?,
	wait: (() -> ())?,
}

export type Slice = {
	step: () -> boolean, -- yields when the slice is spent; true if it did
	reset: () -> (), -- start a fresh slice now (after a yield of your own)
	setBudget: (seconds: number) -> (), -- change the slice's own budget (the next step uses it)
	yields: () -> number, -- how many times step() has yielded
	longest: () -> number, -- the longest stretch of work between two yields, seconds
	finish: () -> (), -- counts the stretch since the last yield (call when the job ends)
}

TimeSlice.DefaultBudget = 0.012

function TimeSlice.new(options: Options?): Slice
	local frame = options and options.frame
	local budget = (options and options.budget) or (if frame then math.huge else TimeSlice.DefaultBudget)
	local clock = (options and options.clock) or os.clock
	local waitFn = (options and options.wait) or function()
		if task then
			task.wait()
		end
	end
	local sliceStart = clock()
	local count = 0
	local longest = 0
	if frame then
		frame.Begin()
	end
	local slice: Slice = {
		step = function(): boolean
			local spent = clock() - sliceStart
			if spent >= budget or (frame ~= nil and frame.Over()) then
				count += 1
				if spent > longest then
					longest = spent
				end
				waitFn()
				sliceStart = clock()
				if frame then
					frame.Begin()
				end
				return true
			end
			return false
		end,
		setBudget = function(seconds: number)
			budget = seconds
		end,
		reset = function()
			sliceStart = clock()
			if frame then
				frame.Begin()
			end
		end,
		yields = function(): number
			return count
		end,
		longest = function(): number
			return longest
		end,
		finish = function()
			local spent = clock() - sliceStart
			if spent > longest then
				longest = spent
			end
		end,
	}
	return slice
end

return TimeSlice
