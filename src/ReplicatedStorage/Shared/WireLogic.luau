--!strict
-- WireLogic: the rules for wiring a plot (LogicItems, LogicService).
-- Pure, so the server decides and tests run it.
--
-- A wire joins one output port to one input port. Several wires may land
-- on the same input; that input is on when any of them is (OR). Saved
-- wires stay { from, to } and grow fromPort / toPort only when the port
-- is not 1, so an old save still loads. A latch that is on is its uid in
-- profile.plot.switches. Tunable times live in profile.plot.logic.

local AutomationLogic = require(script.Parent.AutomationLogic)

local WireLogic = {}

export type Wire = { from: string, to: string, fromPort: number?, toPort: number? }

export type Item = {
	uid: string,
	blueprintId: string,
	x: number,
	z: number,
	y: number?,
	fill: { units: number }?,
}

export type Spec = {
	role: string,
	outs: { number },
	ins: { number },
	latch: boolean?,
	pulse: number?,
	sense: boolean?,
	clock: boolean?,
	delay: boolean?,
	sustain: boolean?,
	op: string?,
	sink: boolean?,
	reads: boolean?, -- a source that also reads its input ports (Wood Detector)
	setting: string?,
	min: number?,
	max: number?,
	step: number?,
	default: number?,
}

WireLogic.Reach = 30 -- studs from the player to each end of a wire
WireLogic.Span = 32 -- studs from an output to its input, along the ground
WireLogic.MaxWires = 160 -- per plot (PROPOSAL)
WireLogic.MaxItems = 80 -- logic pieces per plot (PROPOSAL); a Door is not one
WireLogic.MaxPerSwitch = 6
WireLogic.FlipCooldown = 0.5 -- seconds between flips of one latch
WireLogic.MaxSwitches = 80 -- latch uids kept in plot.switches
WireLogic.Port = 1 -- the first port; the Wire remote carries port numbers

local SPECS: { [string]: Spec } = {
	SparkSwitch = { role = "switch", outs = { 1 }, ins = {}, latch = true },
	Lever = { role = "lever", outs = { 1 }, ins = {}, latch = true },
	Button = { role = "button", outs = { 1 }, ins = {}, pulse = 1 },
	PressurePlate = { role = "plate", outs = { 1 }, ins = {}, sense = true },
	GateAnd = { role = "gate", outs = { 1 }, ins = { 1, 2 }, op = "and" },
	GateOr = { role = "gate", outs = { 1 }, ins = { 1, 2 }, op = "or" },
	GateXor = { role = "gate", outs = { 1 }, ins = { 1, 2 }, op = "xor" },
	GateNot = { role = "invert", outs = { 1 }, ins = { 1 }, op = "not" },
	Delay = {
		role = "delay",
		outs = { 1 },
		ins = { 1 },
		delay = true,
		setting = "delay",
		min = 0.1,
		max = 10,
		step = 0.1,
		default = 1,
	},
	Sustain = {
		role = "sustain",
		outs = { 1 },
		ins = { 1 },
		sustain = true,
		setting = "hold",
		min = 0.1,
		max = 10,
		step = 0.1,
		default = 1,
	},
	Clock = {
		role = "clock",
		outs = { 1 },
		ins = {},
		clock = true,
		setting = "period",
		min = 0.5,
		max = 30,
		step = 0.5,
		default = 2,
	},
	SparkLamp = { role = "lamp", outs = {}, ins = { 1 }, sink = true },
	GlowWire = { role = "glow", outs = {}, ins = { 1 }, sink = true },
	Hatch = { role = "hatch", outs = {}, ins = { 1 }, sink = true },
	Door = { role = "door", outs = {}, ins = { 1 }, sink = true },
	-- Lane W (Sparkworks stock). The sweeper pushes wood when its input
	-- turns on; the laser emitter is on while wood breaks its beam; the
	-- receiver only completes the pair.
	WoodSweeper = { role = "sweeper", outs = {}, ins = { 1 }, sink = true },
	LaserEmitter = { role = "laser", outs = { 1 }, ins = {}, sense = true },
	LaserReceiver = { role = "receiver", outs = {}, ins = {} },
}

-- Belts, sawmills and planers are wire targets too (Lane W), but not
-- logic pieces: they never count toward MaxItems. Their ports come from
-- AutomationLogic.Ports. The Wood Detector is a belt that is also a source.
local machineSpecs: { [string]: Spec } = {}
local notMachine: { [string]: boolean } = {}

local function machineSpec(blueprintId: string): Spec?
	local cached = machineSpecs[blueprintId]
	if cached then
		return cached
	end
	if notMachine[blueprintId] then
		return nil
	end
	local ins = AutomationLogic.InPorts(blueprintId)
	local spec: Spec? = nil
	if #ins > 0 then
		local _, def = AutomationLogic.Get(blueprintId)
		if def and def.shape == "detector" then
			spec = { role = "detector", outs = { 1 }, ins = ins, sense = true, reads = true }
		elseif def then
			spec = { role = "belt", outs = {}, ins = ins, sink = true }
		else
			spec = { role = "machine", outs = {}, ins = ins, sink = true }
		end
	end
	if spec then
		machineSpecs[blueprintId] = spec
	else
		notMachine[blueprintId] = true
	end
	return spec
end

local SOURCE_ROLE: { [string]: boolean } = {
	switch = true,
	button = true,
	lever = true,
	plate = true,
	gate = true,
	invert = true,
	delay = true,
	sustain = true,
	clock = true,
	laser = true,
	detector = true,
}

local TARGET_ROLE: { [string]: boolean } = {
	lamp = true,
	door = true,
	gate = true,
	invert = true,
	delay = true,
	sustain = true,
	glow = true,
	hatch = true,
	belt = true,
	machine = true,
	sweeper = true,
	detector = true,
}

function WireLogic.Spec(blueprintId: string): Spec?
	return SPECS[blueprintId] or machineSpec(blueprintId)
end

-- "switch", "lamp", "door", and the sandbox roles, or nil.
function WireLogic.Role(blueprintId: string): string?
	local spec = WireLogic.Spec(blueprintId)
	return if spec then spec.role else nil
end

-- A belt, sawmill or planer (Lane W): a wire target that is not a logic piece.
function WireLogic.IsMachine(blueprintId: string): boolean
	return SPECS[blueprintId] == nil and machineSpec(blueprintId) ~= nil
end

function WireLogic.IsSource(role: string?): boolean
	return role ~= nil and SOURCE_ROLE[role] == true
end

function WireLogic.IsTarget(role: string?): boolean
	return role ~= nil and TARGET_ROLE[role] == true
end

function WireLogic.IsLogicItem(blueprintId: string): boolean
	return SPECS[blueprintId] ~= nil and blueprintId ~= "Door"
end

function WireLogic.Latches(blueprintId: string): boolean
	local spec = SPECS[blueprintId]
	return spec ~= nil and spec.latch == true
end

function WireLogic.LogicCount(placed: { Item }): number
	local n = 0
	for _, item in ipairs(placed) do
		if WireLogic.IsLogicItem(item.blueprintId) then
			n += 1
		end
	end
	return n
end

-- False when this blueprint would be one logic piece too many.
function WireLogic.CanPlace(placed: { Item }, blueprintId: string): boolean
	if not WireLogic.IsLogicItem(blueprintId) then
		return true
	end
	return WireLogic.LogicCount(placed) < WireLogic.MaxItems
end

local function listed(ports: { number }, port: number): boolean
	return table.find(ports, port) ~= nil
end

function WireLogic.HasOut(blueprintId: string, port: number): boolean
	local spec = WireLogic.Spec(blueprintId)
	return spec ~= nil and listed(spec.outs, port)
end

function WireLogic.HasIn(blueprintId: string, port: number): boolean
	local spec = WireLogic.Spec(blueprintId)
	return spec ~= nil and listed(spec.ins, port)
end

-- The saved number for a tunable piece, or nil when the key is not its setting
-- or the number is outside the range. In-range values snap to the step.
function WireLogic.ClampSetting(blueprintId: string, key: string, value: number): number?
	local spec = SPECS[blueprintId]
	if not spec or spec.setting ~= key or spec.min == nil or spec.max == nil or spec.step == nil then
		return nil
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	if value < spec.min - 1e-6 or value > spec.max + 1e-6 then
		return nil
	end
	local n = math.floor(value / spec.step + 0.5 + 1e-9)
	local snapped = math.round(n * spec.step * 10) / 10
	if snapped < spec.min or snapped > spec.max then
		return nil
	end
	return snapped
end

function WireLogic.DefaultSetting(blueprintId: string): (string?, number?)
	local spec = SPECS[blueprintId]
	if not spec or spec.setting == nil or spec.default == nil then
		return nil, nil
	end
	return spec.setting, spec.default
end

local MESSAGES: { [string]: string } = {
	bad = "That can't be wired.",
	missing = "That piece isn't on your plot.",
	from = "Start a wire at an output.",
	to = "A wire ends at an input.",
	unfinished = "Finish building that first.",
	dup = "Those two are already wired.",
	span = "Too far apart. Keep them within 32 studs.",
	reach = "Stand closer to wire that.",
	full = "This plot holds 160 wires.",
	limit = "That output already feeds six things.",
	items = "This plot holds 80 logic pieces.",
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

local function cleanPort(value: any): number?
	if type(value) ~= "number" or value ~= math.floor(value) or value < 1 or value > 8 then
		return nil
	end
	if value == 1 then
		return nil
	end
	return value
end

-- Wires from a save: only { from, to } pairs of non-empty strings, no
-- repeats, no loops, at most MaxWires. A port other than 1 is kept.
-- Anything else is dropped.
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
				local fp = cleanPort(entry.fromPort)
				local tp = cleanPort(entry.toPort)
				local key = from .. ":" .. tostring(fp or 1) .. ">" .. to .. ":" .. tostring(tp or 1)
				if not seen[key] then
					seen[key] = true
					local wire: Wire = { from = from, to = to }
					if fp then
						wire.fromPort = fp
					end
					if tp then
						wire.toPort = tp
					end
					table.insert(out, wire)
					if #out >= WireLogic.MaxWires then
						break
					end
				end
			end
		end
	end
	return out
end

-- Saved latch positions: the uids that are on. Only non-empty strings,
-- no repeats, at most MaxSwitches.
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

function WireLogic.IsOn(switches: any, uid: string): boolean
	return type(switches) == "table" and table.find(switches, uid) ~= nil
end

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

function WireLogic.LiveSwitches(switches: any, placed: { Item }): { string }
	local out: { string } = {}
	local byUid: { [string]: Item } = {}
	for _, item in ipairs(placed) do
		byUid[item.uid] = item
	end
	for _, uid in ipairs(WireLogic.CleanSwitches(switches)) do
		local item = byUid[uid]
		if item and WireLogic.Latches(item.blueprintId) then
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

local function portFrom(wire: Wire): number
	return wire.fromPort or 1
end

local function portTo(wire: Wire): number
	return wire.toPort or 1
end

-- The wires whose two ends are both placed, the first an output and the
-- second an input, on ports those pieces actually have.
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
			and WireLogic.HasOut(a.blueprintId, portFrom(wire))
			and WireLogic.HasIn(b.blueprintId, portTo(wire))
		then
			table.insert(out, wire)
		end
	end
	return out
end

function WireLogic.Distance(a: Item, b: Item): number
	local dx, dz = a.x - b.x, a.z - b.z
	return math.sqrt(dx * dx + dz * dz)
end

function WireLogic.InReach(px: number, py: number, pz: number, item: Item): boolean
	if not (finite(px) and finite(py) and finite(pz)) then
		return false
	end
	local dx, dy, dz = px - item.x, py - (item.y or 0), pz - item.z
	return dx * dx + dy * dy + dz * dz <= WireLogic.Reach * WireLogic.Reach
end

-- (true, nil) when `fromUid` port `fromPort` may be wired to `toUid` port
-- `toPort`, else (false, reason). Ports default to 1.
function WireLogic.Check(
	wires: { Wire },
	placed: { Item },
	fromUid: string,
	toUid: string,
	fromPort: number?,
	toPort: number?
): (boolean, string?)
	local fp = fromPort or 1
	local tp = toPort or 1
	-- A piece does not wire to itself. A loop is two pieces feeding each other.
	if fromUid == toUid then
		return false, "bad"
	end
	local a, b = find(placed, fromUid), find(placed, toUid)
	if not a or not b then
		return false, "missing"
	end
	if not WireLogic.HasOut(a.blueprintId, fp) then
		return false, "from"
	end
	if not WireLogic.HasIn(b.blueprintId, tp) then
		return false, "to"
	end
	if a.fill ~= nil or b.fill ~= nil then
		return false, "unfinished"
	end
	if WireLogic.LogicCount(placed) > WireLogic.MaxItems then
		return false, "items"
	end
	if fromUid ~= toUid and WireLogic.Distance(a, b) > WireLogic.Span then
		return false, "span"
	end
	local live = WireLogic.Live(wires, placed)
	local feeds = 0
	for _, wire in ipairs(live) do
		if wire.from == fromUid and wire.to == toUid and portFrom(wire) == fp and portTo(wire) == tp then
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

-- Inputs in reach of an output that this port does not feed yet, nearest
-- first (ties by uid, so the order never wobbles).
function WireLogic.Candidates(wires: { Wire }, placed: { Item }, sourceUid: string): { string }
	local src = find(placed, sourceUid)
	local out: { { uid: string, d: number } } = {}
	if not src or not WireLogic.IsSource(WireLogic.Role(src.blueprintId)) then
		return {}
	end
	for _, item in ipairs(placed) do
		if WireLogic.IsTarget(WireLogic.Role(item.blueprintId)) then
			if WireLogic.Check(wires, placed, sourceUid, item.uid) then
				table.insert(out, { uid = item.uid, d = WireLogic.Distance(src, item) })
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

-- Is a piece fed by any live wire, and is any of those outputs on?
-- `on` maps a source uid to true. Returns (fed, powered). Port-blind: any
-- wire into the piece counts, which matches a one-port lamp or door.
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
