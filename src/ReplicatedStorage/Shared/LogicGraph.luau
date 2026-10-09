--!strict
-- LogicGraph: the pure logic network (V2_PLAN.md §10). Ports carry boolean
-- signals. Edges are the plot's wires. One input port ORs every wire that
-- lands on it. A propagation queue stops at 200 evaluations in one Set or
-- Tick, so an oscillating circuit is marked Overloaded instead of hanging.
-- Timers advance on a 0.1 s step.
--
-- Build, then Set each saved latch. The same placed pieces, wires, settings
-- and latches rebuild to the same outputs. A clock starts off, and a delay
-- starts empty, so a fresh load matches a fresh build.

local WireLogic = require(script.Parent.WireLogic)

local LogicGraph = {}

LogicGraph.Cap = 200
LogicGraph.Step = 0.1

export type Wire = WireLogic.Wire
export type Placed = { uid: string, blueprintId: string }
export type Settings = { [string]: { [string]: number } }
export type Report = { changed: { string } }

type Edge = { from: string, fp: number, tp: number }

type Node = {
	uid: string,
	id: string,
	op: string?,
	sink: boolean,
	delay: boolean,
	sustain: boolean,
	clock: boolean,
	latch: boolean,
	pulse: number,
	sense: boolean,
	reads: boolean, -- keeps a level for each input port (sinks, the Wood Detector)
	ins: { number },
	levels: { [number]: boolean },
	setting: number,
	out: boolean,
	level: boolean,
	live: boolean,
	phase: number,
	hold: number,
	pulseLeft: number,
	hist: { boolean },
	histAt: number,
	overloaded: boolean,
	queued: boolean,
	marked: boolean,
}

export type Graph = {
	nodes: { [string]: Node },
	order: { string },
	into: { [string]: { Edge } },
	changed: { string },
	changedN: number,
	report: Report,
	acc: number,
	queue: { string },
	qh: number,
	qt: number,
	evals: number,
}

local function addChanged(graph: Graph, node: Node)
	if node.marked then
		return
	end
	node.marked = true
	graph.changedN += 1
	graph.changed[graph.changedN] = node.uid
end

local function clearChanged(graph: Graph)
	local list = graph.changed
	for i = 1, graph.changedN do
		local uid = list[i]
		local node = if uid then graph.nodes[uid] else nil
		if node then
			node.marked = false
		end
		list[i] = nil
	end
	graph.changedN = 0
end

-- True when any wire into `port` comes from an output that is on.
local function readIn(graph: Graph, uid: string, port: number): boolean
	local edges = graph.into[uid]
	if not edges then
		return false
	end
	for _, edge in ipairs(edges) do
		if edge.tp == port and edge.fp == 1 then
			local src = graph.nodes[edge.from]
			if src and src.out then
				return true
			end
		end
	end
	return false
end

local function enqueue(graph: Graph, uid: string)
	local node = graph.nodes[uid]
	if not node or node.queued then
		return
	end
	node.queued = true
	graph.qt += 1
	graph.queue[graph.qt] = uid
end

local function enqueueConsumers(graph: Graph, uid: string)
	for _, other in ipairs(graph.order) do
		local edges = graph.into[other]
		if edges then
			for _, edge in ipairs(edges) do
				if edge.from == uid then
					enqueue(graph, other)
					break
				end
			end
		end
	end
end

local function setOut(graph: Graph, node: Node, value: boolean)
	if node.out == value then
		return
	end
	node.out = value
	addChanged(graph, node)
	enqueueConsumers(graph, node.uid)
end

local function compute(graph: Graph, node: Node): boolean
	local a = readIn(graph, node.uid, 1)
	local b = readIn(graph, node.uid, 2)
	local op = node.op
	if op == "and" then
		return a and b
	elseif op == "or" then
		return a or b
	elseif op == "xor" then
		return a ~= b
	elseif op == "not" then
		return not a
	end
	return false
end

local function eval(graph: Graph, node: Node)
	if node.op ~= nil then
		setOut(graph, node, compute(graph, node))
	elseif node.delay then
		node.live = readIn(graph, node.uid, 1)
	elseif node.sustain then
		node.live = readIn(graph, node.uid, 1)
		if node.live then
			node.hold = node.setting
			setOut(graph, node, true)
		end
	elseif node.reads then
		local moved = false
		for _, port in ipairs(node.ins) do
			local value = readIn(graph, node.uid, port)
			if node.levels[port] ~= value then
				node.levels[port] = value
				if port ~= 1 then
					moved = true
				end
			end
		end
		local level = node.levels[1] == true
		if level ~= node.level then
			node.level = level
			moved = true
		end
		if moved then
			addChanged(graph, node)
		end
	end
end

local function markRest(graph: Graph)
	while graph.qh <= graph.qt do
		local uid = graph.queue[graph.qh]
		graph.queue[graph.qh] = nil
		graph.qh += 1
		local waiting = if uid then graph.nodes[uid] else nil
		if waiting then
			waiting.queued = false
			waiting.overloaded = true
			addChanged(graph, waiting)
		end
	end
end

-- Drain the queue. Seeds already queued (a Build pass, or the consumers of
-- a Set / timer step) are the only nodes evaluated.
local function propagate(graph: Graph)
	graph.evals = 0
	if graph.qh > graph.qt then
		graph.qh = 1
		graph.qt = 0
	end
	while graph.qh <= graph.qt do
		if graph.evals >= LogicGraph.Cap then
			-- The remainder is not the whole loop: mark every piece, so a
			-- ring still shows Overloaded on the nodes already evaluated.
			markRest(graph)
			for _, id in ipairs(graph.order) do
				local waiting = graph.nodes[id]
				if waiting then
					waiting.overloaded = true
					addChanged(graph, waiting)
				end
			end
			return
		end
		local uid = graph.queue[graph.qh]
		graph.queue[graph.qh] = nil
		graph.qh += 1
		graph.evals += 1
		local node = if uid then graph.nodes[uid] else nil
		if node then
			node.queued = false
			eval(graph, node)
		end
	end
	for _, uid in ipairs(graph.order) do
		local node = graph.nodes[uid]
		if node then
			node.overloaded = false
		end
	end
	graph.qh = 1
	graph.qt = 0
end

local function historyLen(setting: number): number
	local n = math.floor(setting / LogicGraph.Step + 0.5)
	if n < 1 then
		n = 1
	end
	-- One fewer slot than the step count, so the sample written on the
	-- change comes out on the Nth step (a 0.5 s delay is five 0.1 s steps).
	return n - 1
end

local function makeNode(item: Placed, settings: Settings): Node?
	local spec = WireLogic.Spec(item.blueprintId)
	if not spec then
		return nil
	end
	local setting = spec.default or 0
	local saved = settings[item.uid]
	if spec.setting and saved and type(saved[spec.setting]) == "number" then
		local clamped = WireLogic.ClampSetting(item.blueprintId, spec.setting, saved[spec.setting])
		if clamped then
			setting = clamped
		end
	end
	local hist: { boolean } = {}
	if spec.delay then
		for i = 1, historyLen(setting) do
			hist[i] = false
		end
	end
	return {
		uid = item.uid,
		id = item.blueprintId,
		op = spec.op,
		sink = spec.sink == true,
		delay = spec.delay == true,
		sustain = spec.sustain == true,
		clock = spec.clock == true,
		latch = spec.latch == true,
		pulse = spec.pulse or 0,
		sense = spec.sense == true,
		reads = spec.sink == true or spec.reads == true,
		ins = spec.ins,
		levels = {},
		setting = setting,
		out = false,
		level = false,
		live = false,
		phase = 0,
		hold = 0,
		pulseLeft = 0,
		hist = hist,
		histAt = 1,
		overloaded = false,
		queued = false,
		marked = false,
	}
end

local function seed(graph: Graph)
	for _, uid in ipairs(graph.order) do
		local node = graph.nodes[uid]
		if node and (node.op ~= nil or node.sink or node.reads or node.delay or node.sustain) then
			enqueue(graph, uid)
		end
	end
end

function LogicGraph.Build(placed: { Placed }, wires: { Wire }?, settings: Settings?): Graph
	local changed: { string } = {}
	local graph: Graph = {
		nodes = {},
		order = {},
		into = {},
		changed = changed,
		changedN = 0,
		report = { changed = changed },
		acc = 0,
		queue = {},
		qh = 1,
		qt = 0,
		evals = 0,
	}
	local bag = settings or {}
	local count = 0
	-- A belt, sawmill or planer is a node only when a wire touches it, so an
	-- unwired line costs the graph nothing (Lane W).
	local touched: { [string]: boolean } = {}
	if type(wires) == "table" then
		for _, wire in ipairs(wires) do
			touched[wire.from] = true
			touched[wire.to] = true
		end
	end
	for _, item in ipairs(placed) do
		if WireLogic.IsLogicItem(item.blueprintId) and count >= WireLogic.MaxItems then
			continue
		end
		if not touched[item.uid] and WireLogic.IsMachine(item.blueprintId) then
			continue
		end
		local node = makeNode(item, bag)
		if node then
			if WireLogic.IsLogicItem(item.blueprintId) then
				count += 1
			end
			graph.nodes[item.uid] = node
			table.insert(graph.order, item.uid)
			graph.into[item.uid] = {}
		end
	end
	table.sort(graph.order)
	if type(wires) == "table" then
		for _, wire in ipairs(wires) do
			local src = graph.nodes[wire.from]
			local dstNode = graph.nodes[wire.to]
			local dst = if dstNode then graph.into[wire.to] else nil
			local fp = wire.fromPort or 1
			local tp = wire.toPort or 1
			if src and dst and dstNode and WireLogic.HasOut(src.id, fp) and WireLogic.HasIn(dstNode.id, tp) then
				table.insert(dst, { from = wire.from, fp = fp, tp = tp })
			end
		end
	end
	seed(graph)
	propagate(graph)
	clearChanged(graph)
	return graph
end

-- Drive an output (a latch, a button press, a plate). `port` is "1" or 1.
function LogicGraph.Set(graph: Graph, uid: string, port: string | number, value: boolean): Report
	clearChanged(graph)
	local node = graph.nodes[uid]
	local p = if type(port) == "number" then port else tonumber(port)
	if not node or p ~= 1 or node.sink or node.op ~= nil or node.delay or node.sustain or node.clock then
		return graph.report
	end
	if node.pulse > 0 then
		if value then
			node.pulseLeft = node.pulse
			setOut(graph, node, true)
		end
	else
		setOut(graph, node, value)
	end
	propagate(graph)
	return graph.report
end

local function stepOne(graph: Graph, node: Node)
	if node.pulse > 0 and node.pulseLeft > 0 then
		node.pulseLeft -= LogicGraph.Step
		if node.pulseLeft <= 1e-6 then
			node.pulseLeft = 0
			setOut(graph, node, false)
		end
	elseif node.clock then
		node.phase += LogicGraph.Step
		if node.phase >= node.setting - 1e-6 then
			node.phase -= node.setting
			if node.phase < 0 then
				node.phase = 0
			end
		end
		setOut(graph, node, node.phase >= node.setting * 0.5 - 1e-6)
	elseif node.delay then
		local len = #node.hist
		if len < 1 then
			setOut(graph, node, node.live)
			return
		end
		local old = node.hist[node.histAt]
		node.hist[node.histAt] = node.live
		node.histAt += 1
		if node.histAt > len then
			node.histAt = 1
		end
		setOut(graph, node, old)
	elseif node.sustain and not node.live and node.hold > 0 then
		node.hold -= LogicGraph.Step
		if node.hold <= 1e-6 then
			node.hold = 0
		end
		setOut(graph, node, node.hold > 0)
	end
end

function LogicGraph.Tick(graph: Graph, dt: number): Report
	clearChanged(graph)
	if type(dt) ~= "number" or dt ~= dt or dt <= 0 or dt > 5 then
		return graph.report
	end
	graph.acc += dt
	local steps = 0
	while graph.acc >= LogicGraph.Step - 1e-9 and steps < 50 do
		graph.acc -= LogicGraph.Step
		if graph.acc < 0 then
			graph.acc = 0
		end
		steps += 1
		for _, uid in ipairs(graph.order) do
			local node = graph.nodes[uid]
			if node then
				stepOne(graph, node)
			end
		end
	end
	if steps > 0 then
		propagate(graph)
	end
	return graph.report
end

function LogicGraph.On(graph: Graph, uid: string): boolean
	local node = graph.nodes[uid]
	if not node then
		return false
	end
	if node.sink then
		return node.level
	end
	return node.out
end

-- The level on one input port of a piece that reads its inputs (false when
-- the piece is not in the graph).
function LogicGraph.Level(graph: Graph, uid: string, port: number): boolean
	local node = graph.nodes[uid]
	return node ~= nil and node.levels[port] == true
end

-- Whether any wire lands on this input port.
function LogicGraph.Wired(graph: Graph, uid: string, port: number): boolean
	local edges = graph.into[uid]
	if not edges then
		return false
	end
	for _, edge in ipairs(edges) do
		if edge.tp == port then
			return true
		end
	end
	return false
end

function LogicGraph.Overloaded(graph: Graph, uid: string): boolean
	local node = graph.nodes[uid]
	return node ~= nil and node.overloaded
end

function LogicGraph.Evals(graph: Graph): number
	return graph.evals
end

return LogicGraph
