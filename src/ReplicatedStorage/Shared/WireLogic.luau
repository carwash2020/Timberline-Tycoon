--!strict
-- WireLogic: the rules for wiring a switch to a lamp or a door on a plot
-- (LogicItems, LogicService). Pure, so the server decides and tests run it.
--
-- A wire joins one switch to one target. Targets are a Spark Lamp or a
-- Door. A switch can feed several targets and a target can have several
-- switches (it follows any switch that is on). Wires are saved as
-- { from = switchUid, to = targetUid } in profile.plot.wires. A switch's
-- position is saved as its uid in profile.plot.switches while it is on
-- (a switch missing from the list is off), so it keeps its place when the
-- plot rebuilds.

local WireLogic = {}

export type Wire = { from: string, to: string }

export type Item = {
	uid: string,
	blueprintId: string,
	x: number,
	z: number,
	y: number?,
	fill: { units: number }?,
}

WireLogic.Reach = 30 -- studs from the player to each end of a wire
WireLogic.Span = 32 -- studs from the switch to its target, along the ground
WireLogic.MaxWires = 40 -- per plot
WireLogic.MaxPerSwitch = 6
WireLogic.FlipCooldown = 0.5 -- seconds between flips of one switch
WireLogic.MaxSwitches = 40 -- uids kept in plot.switches
WireLogic.Port = 1 -- the only port a piece has; the Wire remote carries it

local ROLES: { [string]: string } = {
	SparkSwitch = "switch",
	SparkLamp = "lamp",
	Door = "door",
}

-- "switch", "lamp", "door", or nil for a piece that cannot be wired.
function WireLogic.Role(blueprintId: string): string?
	return ROLES[blueprintId]
end

function WireLogic.IsTarget(role: string?): boolean
	return role == "lamp" or role == "door"
end

local MESSAGES: { [string]: string } = {
	bad = "That can't be wired.",
	missing = "That piece isn't on your plot.",
	from = "Start a wire at a Wall Switch.",
	to = "A switch wires to a Spark Lamp or a Door.",
	unfinished = "Finish building that first.",
	dup = "Those two are already wired.",
	span = "Too far apart. Keep them within 32 studs.",
	reach = "Stand closer to wire that.",
	full = "This plot has all the wires it can hold.",
	limit = "That switch already feeds six things.",
	none = "Nothing to wire within 32 studs. Place a Spark Lamp or a Door nearby.",
	cleared = "Wires cleared.",
	wired = "Wired.",
}

function WireLogic.Message(key: string?): string?
	return MESSAGES[key or ""]
end

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- Wires from a save: only { from, to } pairs of non-empty strings, no
-- repeats, no loops, at most MaxWires. Anything else is dropped.
function WireLogic.Clean(value: any): { Wire }
	local out: { Wire } = {}
	if type(value) ~= "table" then
		return out
	end
	local seen: { [string]: boolean } = {}
	for _, entry in ipairs(value) do
		if type(entry) == "table" then
			local from, to = entry.from, entry.to
			if type(from) == "string" and type(to) == "string" and from ~= "" and to ~= "" and from ~= to then
				local key = from .. ">" .. to
				if not seen[key] then
					seen[key] = true
					table.insert(out, { from = from, to = to })
					if #out >= WireLogic.MaxWires then
						break
					end
				end
			end
		end
	end
	return out
end

-- Saved switch positions: the uids of the switches that are on. Only
-- non-empty strings, no repeats, at most MaxSwitches.
function WireLogic.CleanSwitches(value: any): { string }
	local out: { string } = {}
	if type(value) ~= "table" then
		return out
	end
	local seen: { [string]: boolean } = {}
	for _, uid in ipairs(value) do
		if type(uid) == "string" and uid ~= "" and not seen[uid] then
			seen[uid] = true
			table.insert(out, uid)
			if #out >= WireLogic.MaxSwitches then
				break
			end
		end
	end
	return out
end

-- Is this switch saved as on?
function WireLogic.IsOn(switches: any, uid: string): boolean
	return type(switches) == "table" and table.find(switches, uid) ~= nil
end

-- `switches` with `uid` set on or off. Returns a new list.
function WireLogic.SetOn(switches: any, uid: string, on: boolean): { string }
	local out: { string } = {}
	for _, have in ipairs(WireLogic.CleanSwitches(switches)) do
		if have ~= uid then
			table.insert(out, have)
		end
	end
	if on and #out < WireLogic.MaxSwitches then
		table.insert(out, uid)
	end
	return out
end

-- The saved positions of switches that are still placed.
function WireLogic.LiveSwitches(switches: any, placed: { Item }): { string }
	local out: { string } = {}
	local byUid: { [string]: Item } = {}
	for _, item in ipairs(placed) do
		byUid[item.uid] = item
	end
	for _, uid in ipairs(WireLogic.CleanSwitches(switches)) do
		local item = byUid[uid]
		if item and WireLogic.Role(item.blueprintId) == "switch" then
			table.insert(out, uid)
		end
	end
	return out
end

local function find(placed: { Item }, uid: string): Item?
	for _, item in ipairs(placed) do
		if item.uid == uid then
			return item
		end
	end
	return nil
end

-- The wires whose two ends are both placed, the first a switch and the
-- second a target.
function WireLogic.Live(wires: { Wire }?, placed: { Item }): { Wire }
	local out: { Wire } = {}
	if type(wires) ~= "table" then
		return out
	end
	local byUid: { [string]: Item } = {}
	for _, item in ipairs(placed) do
		byUid[item.uid] = item
	end
	for _, wire in ipairs(wires) do
		local a, b = byUid[wire.from], byUid[wire.to]
		if
			a
			and b
			and WireLogic.Role(a.blueprintId) == "switch"
			and WireLogic.IsTarget(WireLogic.Role(b.blueprintId))
		then
			table.insert(out, wire)
		end
	end
	return out
end

-- Ground distance between two placed pieces, in studs.
function WireLogic.Distance(a: Item, b: Item): number
	local dx, dz = a.x - b.x, a.z - b.z
	return math.sqrt(dx * dx + dz * dz)
end

-- True when a player standing at plot-local (px, py, pz) is near `item`.
function WireLogic.InReach(px: number, py: number, pz: number, item: Item): boolean
	if not (finite(px) and finite(py) and finite(pz)) then
		return false
	end
	local dx, dy, dz = px - item.x, py - (item.y or 0), pz - item.z
	return dx * dx + dy * dy + dz * dz <= WireLogic.Reach * WireLogic.Reach
end

-- (true, nil) when `fromUid` may be wired to `toUid`, else (false, reason).
function WireLogic.Check(wires: { Wire }, placed: { Item }, fromUid: string, toUid: string): (boolean, string?)
	if fromUid == toUid then
		return false, "bad"
	end
	local a, b = find(placed, fromUid), find(placed, toUid)
	if not a or not b then
		return false, "missing"
	end
	if WireLogic.Role(a.blueprintId) ~= "switch" then
		return false, "from"
	end
	if not WireLogic.IsTarget(WireLogic.Role(b.blueprintId)) then
		return false, "to"
	end
	if a.fill ~= nil or b.fill ~= nil then
		return false, "unfinished"
	end
	if WireLogic.Distance(a, b) > WireLogic.Span then
		return false, "span"
	end
	local live = WireLogic.Live(wires, placed)
	local feeds = 0
	for _, wire in ipairs(live) do
		if wire.from == fromUid and wire.to == toUid then
			return false, "dup"
		end
		if wire.from == fromUid then
			feeds += 1
		end
	end
	if #live >= WireLogic.MaxWires then
		return false, "full"
	end
	if feeds >= WireLogic.MaxPerSwitch then
		return false, "limit"
	end
	return true, nil
end

-- Targets in reach of a switch that it does not feed yet, nearest first
-- (ties by uid, so the order never wobbles).
function WireLogic.Candidates(wires: { Wire }, placed: { Item }, switchUid: string): { string }
	local sw = find(placed, switchUid)
	local out: { { uid: string, d: number } } = {}
	if not sw or WireLogic.Role(sw.blueprintId) ~= "switch" then
		return {}
	end
	for _, item in ipairs(placed) do
		if item.uid ~= switchUid and WireLogic.IsTarget(WireLogic.Role(item.blueprintId)) then
			if WireLogic.Check(wires, placed, switchUid, item.uid) then
				table.insert(out, { uid = item.uid, d = WireLogic.Distance(sw, item) })
			end
		end
	end
	table.sort(out, function(p, q)
		if p.d ~= q.d then
			return p.d < q.d
		end
		return p.uid < q.uid
	end)
	local uids: { string } = {}
	for _, entry in ipairs(out) do
		table.insert(uids, entry.uid)
	end
	return uids
end

-- `wires` without any wire that touches `uid`.
function WireLogic.Without(wires: { Wire }, uid: string): ({ Wire }, number)
	local out: { Wire } = {}
	local cut = 0
	for _, wire in ipairs(wires) do
		if wire.from == uid or wire.to == uid then
			cut += 1
		else
			table.insert(out, wire)
		end
	end
	return out, cut
end

-- Is a lamp or door fed by any live wire, and is any of its switches on?
-- `on` maps a switch uid to true. Returns (fed, powered).
function WireLogic.Power(wires: { Wire }, uid: string, on: { [string]: boolean }): (boolean, boolean)
	local fed, powered = false, false
	for _, wire in ipairs(wires) do
		if wire.to == uid then
			fed = true
			if on[wire.from] == true then
				powered = true
			end
		end
	end
	return fed, powered
end

-- What a lamp shows. A lamp nobody wired stays lit.
function WireLogic.LampLit(fed: boolean, powered: boolean): boolean
	return if fed then powered else true
end

return WireLogic
