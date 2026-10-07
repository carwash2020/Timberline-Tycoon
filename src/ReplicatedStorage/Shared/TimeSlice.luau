--!strict
-- TimeSlice: "work for a few milliseconds, then give the frame back". One
-- tested place for the budget-and-yield pattern that the forest planter, the
-- deferred build queue (Shared/LoadQueue) and the client's forest plan all
-- use, so a long job never freezes the server or the client for a whole
-- frame. Call `step()` after each small unit of work: it yields (and starts
-- a new slice) only when the budget is spent, and says whether it did.
--
-- The clock and the wait are injected so the specs can run it without a
-- scheduler; the defaults are os.clock and task.wait.

local TimeSlice = {}

export type Options = {
	budget: number?, -- seconds of work per slice (default 0.012)
	clock: (() -> number)?,
	wait: (() -> ())?,
}

export type Slice = {
	step: () -> boolean, -- yields when the slice is spent; true if it did
	reset: () -> (), -- start a fresh slice now (after a yield of your own)
	yields: () -> number, -- how many times step() has yielded
}

TimeSlice.DefaultBudget = 0.012

function TimeSlice.new(options: Options?): Slice
	local budget = (options and options.budget) or TimeSlice.DefaultBudget
	local clock = (options and options.clock) or os.clock
	local waitFn = (options and options.wait) or function()
		if task then
			task.wait()
		end
	end
	local sliceStart = clock()
	local count = 0
	local slice: Slice = {
		step = function(): boolean
			if clock() - sliceStart >= budget then
				count += 1
				waitFn()
				sliceStart = clock()
				return true
			end
			return false
		end,
		reset = function()
			sliceStart = clock()
		end,
		yields = function(): number
			return count
		end,
	}
	return slice
end

return TimeSlice
