--!strict
-- PickerSequence: which join screen is on top. A first join can ask for two
-- at once: the Lower / Higher quality choice and (for a save that owns a
-- plot) the plot picker. They used to open together, the quality screen
-- (layer 90) over the plot picker (80): the plot picker's buttons sat
-- under the quality screen's backdrop and both held a movement lock at
-- once. Now they take turns: each asks (Request), only the first in
-- Order is shown, and when it is done (Done) the next one opens. Pure.
--
-- Order: "quality", then "slot" (which save to play), then "plot" (which pad
-- to put that save's base on). Anything else never shows (Request refuses).

local PickerSequence = {}

PickerSequence.Order = { "quality", "slot", "plot" }

export type Sequence = {
	Request: (id: string) -> boolean,
	Done: (id: string) -> (),
	Active: () -> string?,
	IsActive: (id: string) -> boolean,
	Waiting: (id: string) -> boolean,
	OnChange: (fn: (active: string?) -> ()) -> (),
}

function PickerSequence.new(): Sequence
	local wanted: { [string]: boolean } = {}
	local listeners: { (active: string?) -> () } = {}
	local last: string? = nil
	local seq = {} :: Sequence

	local function active(): string?
		for _, id in ipairs(PickerSequence.Order) do
			if wanted[id] then
				return id
			end
		end
		return nil
	end

	local function changed()
		local now = active()
		if now == last then
			return
		end
		last = now
		for _, fn in ipairs(listeners) do
			pcall(fn, now)
		end
	end

	function seq.Request(id: string): boolean
		if not table.find(PickerSequence.Order, id) then
			return false
		end
		wanted[id] = true
		changed()
		return active() == id
	end

	function seq.Done(id: string)
		if wanted[id] then
			wanted[id] = nil
			changed()
		end
	end

	function seq.Active(): string?
		return active()
	end

	function seq.IsActive(id: string): boolean
		return active() == id
	end

	function seq.Waiting(id: string): boolean
		return wanted[id] == true and active() ~= id
	end

	function seq.OnChange(fn: (active: string?) -> ())
		table.insert(listeners, fn)
	end

	return seq
end

local shared: Sequence? = nil

-- The one the client's screens share.
function PickerSequence.Shared(): Sequence
	if shared == nil then
		shared = PickerSequence.new()
	end
	return shared :: Sequence
end

return PickerSequence
