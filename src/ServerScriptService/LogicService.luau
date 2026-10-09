--!strict
-- LogicService: wiring and the Sparkworks sandbox on a plot (V2_PLAN.md).
-- Rules live in Shared/WireLogic and Shared/LogicGraph. Pieces live in
-- Shared/LogicItems.
--   * A Wall Switch has Flip (Interact) and Wire (Open, a short hold).
--     Wire links the nearest free target within WireLogic.Span, then the
--     next, then clears. The Wire remote carries the same intent by uid:
--     (fromUid, port, toUid, port) or ("cut", uid). It is rate limited,
--     needs the build permission, and the player must stand within
--     WireLogic.Reach of each piece.
--   * Wires are saved in profile.plot.wires. Latches that are on are uids
--     in profile.plot.switches. Tunable times are profile.plot.logic[uid].
--     A source model carries a "Wires" attribute (target uids, comma
--     joined, "@port" when the input is not port 1) so the client can
--     draw the lines.
--   * A lamp nobody wired stays lit. A wired lamp, a glow wire, a hatch
--     and a door follow the graph. A wired door opens through PlotDoors.
--   * The graph is rebuilt on load, restore and any wire change, and
--     ticked only while the owner is online and the plot is loaded.
--     Leaving drops the run; the save is what comes back.
--   * Lane W: belts, sawmills and planers are wire targets (RegisterTarget,
--     on Attach; dropped on Sync once sold or rebuilt). Ports are in
--     AutomationLogic.Ports: power and reverse, plus side on a Switch Belt.
--     An unwired port runs as before. The owner's Reverse prompt (every
--     belt) and Flip prompt (Switch Belt) save item.reversed / item.flip.
--     The Wood Detector (a belt) and the Laser Emitter are sensed sources;
--     the Wood Sweeper pushes loose wood off a belt on a rising input.
-- PlotService calls Bind once, Attach for each built piece, and Sync after
-- a piece is sold. V1Boot calls V1Init. GameServer still calls Init(Wire).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AutomationLogic = require(ReplicatedStorage.Shared.AutomationLogic)
local BlueprintModels = require(ReplicatedStorage.Shared.BlueprintModels)
local InputKit = require(ReplicatedStorage.Shared.InputKit)
local LogicGraph = require(ReplicatedStorage.Shared.LogicGraph)
local PermissionLogic = require(ReplicatedStorage.Shared.PermissionLogic)
local PlotData = require(ReplicatedStorage.Shared.PlotData)
local PlotLogic = require(ReplicatedStorage.Shared.PlotLogic)
local TimeSlice = require(ReplicatedStorage.Shared.TimeSlice)
local WireLogic = require(ReplicatedStorage.Shared.WireLogic)
local PlotDoors = require(script.Parent.PlotDoors)
local RateLimiter = require(script.Parent.RateLimiter)

local LogicService = {}

export type Host = { cframe: CFrame, items: Instance }
type Profile = any
export type HostFn = (Player, string) -> (Host?, Profile?, Player?, boolean)
export type Notify = (Player, string) -> ()

export type Context = {
	slot: Host,
	model: Model,
	item: PlotLogic.Placed,
	ownerOf: () -> (Player?, Profile?),
}

type Run = {
	host: Host,
	profile: Profile,
	graph: LogicGraph.Graph?,
	owner: Player?,
	senseAcc: number,
	toldCap: boolean,
	anyOver: boolean,
	wires: { WireLogic.Wire },
	laserTick: number?,
}

local LEVER_BOX = 3
local TIP = 0.7
local ROOT_LIFT = Vector3.new(0, 0.1, 0)
local PLATE_SIZE = Vector3.new(3.6, 5, 3.6)
local OFF_COLOR = Color3.fromRGB(88, 84, 76)
local DIM_WIRE = Color3.fromRGB(90, 78, 60)
local LIT_WIRE = Color3.fromRGB(255, 196, 90)
local HATCH_OPEN = math.rad(-72)

local GLOW_ROLE: { [string]: boolean } = {
	glow = true,
	gate = true,
	invert = true,
	clock = true,
	plate = true,
	button = true,
	delay = true,
	sustain = true,
}

local hostFn: HostFn? = nil
-- Set below once the overlap params helper exists (sense and sweep share it).
local overlapParamsFn: () -> any = function(): any
	return nil
end
local function silent(_player: Player, _text: string) end
local notify: Notify = silent
-- Lane W registers a belt, sawmill or planer. power and reverse are the
-- two boolean inputs a wire can drive later. Registering does not run them.
export type LogicTarget = {
	power: (boolean) -> (),
	reverse: (boolean) -> (),
}

local targets: { [string]: LogicTarget } = {}
-- The plot folder a registered belt or machine sits in (Lane W), so Sync
-- drops only that plot's sold pieces.
local targetHost: { [string]: Instance } = {}
local lastFlip: { [string]: number } = {}
local runs: { [Instance]: Run } = {}
local hexCache: { [string]: Color3 } = {}
local bound = false
local logicBound = false
local started = false

local demoFolder: Folder? = nil
local demoGraph: LogicGraph.Graph? = nil
local demoModels: { [string]: Model } = {}
local demoBeams: { { part: Part, from: string } } = {}
local demoSense = 0

local slice = TimeSlice.new({ budget = 0.002 })
-- True while a Tick is running (it may be suspended inside slice.step()), so
-- the next Heartbeat's Tick skips instead of advancing the graphs twice.
local ticking = false

-- TEST ONLY: swap the slice's clock and wait so a spec can force a yield.
-- nil restores the default 2 ms slice.
function LogicService._setSlice(options: TimeSlice.Options?)
	local clock = options and options.clock
	local waitFn = options and options.wait
	slice = TimeSlice.new({ budget = 0.002, clock = clock, wait = waitFn })
end

function LogicService.Bind(host: HostFn, notifyFn: Notify)
	hostFn = host
	notify = notifyFn
end

function LogicService.Reset()
	table.clear(lastFlip)
	table.clear(targets)
	table.clear(targetHost)
end

local function mayUse(owner: Player, profile: Profile, who: Player, flag: string): boolean
	return who.UserId == owner.UserId or PermissionLogic.Allows(profile.permissions, who.UserId, flag)
end

local function wiresOf(profile: Profile): { WireLogic.Wire }
	local plot = profile.plot
	if type(plot.wires) ~= "table" then
		plot.wires = {}
	end
	return plot.wires
end

local function findItem(profile: Profile, uid: string): PlotLogic.Placed?
	for _, item in ipairs(profile.plot.placed) do
		if item.uid == uid then
			return item
		end
	end
	return nil
end

local function modelOf(host: Host, uid: string): Model?
	local found = host.items:FindFirstChild(uid)
	if found and found:IsA("Model") then
		return found
	end
	return nil
end

local function nameOf(item: PlotLogic.Placed): string
	local bp = PlotLogic.Blueprint(item.blueprintId)
	return if bp then bp.displayName else item.blueprintId
end

local function hex(color: string): Color3
	local cached = hexCache[color]
	if cached then
		return cached
	end
	local made = Color3.fromHex(color)
	hexCache[color] = made
	return made
end

local function formatNum(n: number): string
	local rounded = math.round(n * 10) / 10
	if math.abs(rounded - math.floor(rounded + 1e-6)) < 1e-4 then
		return string.format("%d", rounded)
	end
	return string.format("%.1f", rounded)
end

local function slotRun(host: Host, profile: Profile, owner: Player?): Run
	local run = runs[host.items]
	if not run then
		run = {
			host = host,
			profile = profile,
			graph = nil,
			owner = owner,
			senseAcc = 0,
			toldCap = false,
			anyOver = false,
			wires = {},
		}
		runs[host.items] = run
	else
		run.host = host
		run.profile = profile
		if owner ~= nil and run.owner == nil then
			run.owner = owner
		end
	end
	return run
end

---------------------------------------------------------------------------
-- What the pieces show
---------------------------------------------------------------------------

local function named(model: Model, slot: string): BasePart?
	local part = model:FindFirstChild(slot)
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

local function restOf(part: BasePart, root: BasePart): CFrame
	local rest = part:GetAttribute("RestOffset")
	if typeof(rest) == "CFrame" then
		return rest
	end
	local made = root.CFrame:ToObjectSpace(part.CFrame)
	part:SetAttribute("RestOffset", made)
	return made
end

local function tip(model: Model, blueprintId: string, on: boolean)
	local moving = named(model, "Moving")
	local base = named(model, "Root")
	if moving and base then
		moving.CFrame = base.CFrame * restOf(moving, base) * CFrame.Angles(0, 0, if on then -TIP else TIP)
		model:SetAttribute("On", on)
		return
	end
	local lever = model:FindFirstChild("Part" .. LEVER_BOX)
	base = named(model, "Root")
	local bp = PlotLogic.Blueprint(blueprintId)
	local box = if bp then bp.boxes[LEVER_BOX] else nil
	if lever and base and box and lever:IsA("BasePart") then
		lever.CFrame = base.CFrame * CFrame.new(box.offset - ROOT_LIFT) * CFrame.Angles(0, 0, if on then -TIP else TIP)
	end
	model:SetAttribute("On", on)
end

local function poseCap(model: Model, down: boolean)
	local moving = named(model, "Moving")
	local base = named(model, "Root")
	if not moving or not base then
		return
	end
	moving.CFrame = base.CFrame * restOf(moving, base) * CFrame.new(0, if down then -0.08 else 0, 0)
end

local function setLamp(model: Model, blueprintId: string, lit: boolean)
	local indicator = named(model, "Indicator")
	if indicator then
		local stored = indicator:GetAttribute("LitColor")
		local color = if typeof(stored) == "Color3" then stored else indicator.Color
		indicator.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
		indicator.Color = if lit then color else OFF_COLOR
		local glow = indicator:FindFirstChildOfClass("PointLight")
		if glow then
			glow.Enabled = lit
		end
		model:SetAttribute("Lit", lit)
		return
	end
	local bp = PlotLogic.Blueprint(blueprintId)
	if bp then
		for i, box in ipairs(bp.boxes) do
			local part = model:FindFirstChild("Part" .. i)
			if part and part:IsA("BasePart") then
				if box.material == "Neon" then
					part.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
					part.Color = if lit then hex(box.color) else OFF_COLOR
				end
				local light = part:FindFirstChildOfClass("PointLight")
				if light then
					light.Enabled = lit
				end
			end
		end
	end
	model:SetAttribute("Lit", lit)
end

local function poseHatch(model: Model, open: boolean)
	local moving = named(model, "Moving")
	local root = named(model, "Root")
	if moving and root then
		local shut = root.CFrame * restOf(moving, root)
		if open then
			local half = moving.Size.Z / 2
			moving.CFrame = shut * CFrame.new(0, 0, half) * CFrame.Angles(HATCH_OPEN, 0, 0) * CFrame.new(0, 0, -half)
		else
			moving.CFrame = shut
		end
		model:SetAttribute("Open", open)
		return
	end
	local leaf = model:FindFirstChild("Part2")
	local base = model:FindFirstChild("Root")
	local bp = PlotLogic.Blueprint("Hatch")
	local box = if bp then bp.boxes[2] else nil
	if leaf and base and box and leaf:IsA("BasePart") and base:IsA("BasePart") then
		leaf:SetAttribute("Leaf", true)
		local shut = base.CFrame * CFrame.new(box.offset - ROOT_LIFT)
		if open then
			local half = leaf.Size.Z / 2
			leaf.CFrame = shut * CFrame.new(0, 0, half) * CFrame.Angles(HATCH_OPEN, 0, 0) * CFrame.new(0, 0, -half)
		else
			leaf.CFrame = shut
		end
	end
	model:SetAttribute("Open", open)
end

local function showOverload(model: Model, on: boolean)
	model:SetAttribute("Overloaded", on)
	local existing = model:FindFirstChild("OverloadGui", true)
	if on and existing == nil then
		local host = model:FindFirstChild("LabelFace") or model:FindFirstChild("Part1")
		if host and host:IsA("BasePart") then
			local gui = Instance.new("SurfaceGui")
			gui.Name = "OverloadGui"
			gui.Face = Enum.NormalId.Front
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 40
			gui.Parent = host
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Text = "Overloaded"
			label.TextColor3 = Color3.fromRGB(255, 90, 48)
			label.TextScaled = true
			label.Font = Enum.Font.GothamBold
			label.Parent = gui
		end
	elseif existing and existing:IsA("SurfaceGui") then
		existing.Enabled = on
	end
end

local function fedBy(wires: { WireLogic.Wire }, uid: string): boolean
	for _, wire in ipairs(wires) do
		if wire.to == uid then
			return true
		end
	end
	return false
end

local function setDoor(
	host: Host,
	profile: Profile,
	who: Player,
	item: PlotLogic.Placed,
	model: Model,
	open: boolean
): string?
	if (model:GetAttribute("Open") == true) == open then
		return nil
	end
	local _, hint = PlotDoors.Toggle(who, model, item, profile.plot.placed, host.cframe, host.items, os.clock(), true)
	return hint
end

---------------------------------------------------------------------------
-- Lane W: belts and machines on wires, the sweeper, detector and laser
---------------------------------------------------------------------------

local function savedSetting(profile: Profile?, uid: string, key: string, default: number): number
	if profile and type(profile.plot.logic) == "table" then
		local bag = profile.plot.logic[uid]
		if type(bag) == "table" and type(bag[key]) == "number" then
			return bag[key]
		end
	end
	return default
end

local SKY_BLUE = Color3.fromHex("#6FB7E8")
local DETECT_ON = Color3.fromHex("#C9A24A")
local DETECT_OFF = Color3.fromHex("#2B2B2E")

-- What the wires say to one belt or machine: power, reverse and (Switch
-- Belt) side. An unwired port gives the old behaviour.
function LogicService._applyMachine(graph: LogicGraph.Graph, item: PlotLogic.Placed, model: Model)
	local ports = AutomationLogic.Ports(item.blueprintId)
	local uid = item.uid
	local function state(port: number?): (boolean, boolean)
		if port == nil then
			return false, false
		end
		return LogicGraph.Wired(graph, uid, port), LogicGraph.Level(graph, uid, port)
	end
	local pw, pl = state(ports.power)
	local rw, rl = state(ports.reverse)
	local powered = AutomationLogic.Powered(pw, pl)
	local wireReverse = rw and rl
	local target = targets[uid]
	if target then
		target.power(powered)
		target.reverse(wireReverse)
	end
	if ports.side then
		local sw, sl = state(ports.side)
		model:SetAttribute("WireSide", if sw and sl then true else nil)
	end
end

local function setDetectorLamp(model: Model, on: boolean)
	local lamp = model:FindFirstChild("Lamp")
	if lamp and lamp:IsA("BasePart") then
		lamp.Color = if on then DETECT_ON else DETECT_OFF
	end
	model:SetAttribute("Detecting", on)
end

-- The arm (Part3) and head (Part4) swing about the post top (local
-- (0, 1.82, 0)) from upright to across the belt on local +X.
local SWEEP_PIVOT = CFrame.new(0, 1.82 - 0.1, 0) -- relative to Root (y 0.1)
local function poseSweeper(model: Model, down: boolean)
	local root = named(model, "Root")
	if not root then
		return
	end
	for _, name in ipairs({ "Part3", "Part4" }) do
		local p = named(model, name)
		if p then
			local rest = restOf(p, root)
			if down then
				p.CFrame = root.CFrame * SWEEP_PIVOT * CFrame.Angles(0, 0, -math.pi / 2) * SWEEP_PIVOT:Inverse() * rest
			else
				p.CFrame = root.CFrame * rest
			end
		end
	end
	model:SetAttribute("Swept", down)
end

local function woodModelOf(part: Instance): Model?
	local node: Instance? = part
	for _ = 1, 4 do
		if node == nil then
			return nil
		end
		if node:IsA("Model") and type(node:GetAttribute("WoodId")) == "string" then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function bodyOf(model: Model): BasePart?
	local primary = model.PrimaryPart
	if primary then
		return primary
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function boxQuery(cf: CFrame, size: Vector3): { Instance }
	local ok, parts = pcall(function()
		return workspace:GetPartBoundsInBox(cf, size, overlapParamsFn())
	end)
	if ok and type(parts) == "table" then
		return parts
	end
	return {}
end

-- Wood models in a box, each once.
local function woodIn(cf: CFrame, size: Vector3): { Model }
	local out: { Model } = {}
	local seen: { [Instance]: boolean } = {}
	for _, part in ipairs(boxQuery(cf, size)) do
		if typeof(part) == "Instance" then
			local wood = woodModelOf(part)
			if wood and not seen[wood] then
				seen[wood] = true
				table.insert(out, wood)
			end
		end
	end
	return out
end

local function landsOnPlot(run: Run, worldPos: Vector3): boolean
	local localPos = run.host.cframe:PointToObjectSpace(worldPos)
	local tier = PlotData.Tier(run.profile.plot.tier) or PlotData.Tiers[1]
	local rect = { x = localPos.X, z = localPos.Z, w = 0, d = 0 }
	local squares = run.profile.plot.squares
	if type(squares) == "table" and #squares > 0 then
		return PlotLogic.OnLand(rect, tier.size, squares)
	end
	return PlotLogic.InBounds(rect, tier.size)
end

-- One sweep: loose wood on the belt beside the sweeper (its local +X) is
-- pushed further that way. QA W5: never held wood, never players or
-- vehicles (only Wood models are looked at), at most SweepMax pieces, and
-- never off the owner's plot.
function LogicService._sweep(run: Run, model: Model): number
	local root = named(model, "Root")
	if not root then
		return 0
	end
	local now = os.clock()
	local last = model:GetAttribute("LastSweep")
	if type(last) == "number" and now - last < AutomationLogic.SweepCooldown then
		return 0
	end
	model:SetAttribute("LastSweep", now)
	local zone = root.CFrame * CFrame.new(3.75, 2.4, 0)
	local dir = root.CFrame.RightVector
	local ownerId = if run.owner then run.owner.UserId else 0
	local candidates: { AutomationLogic.SweepCandidate } = {}
	for _, wood in ipairs(woodIn(zone, Vector3.new(6.5, 4.6, 5.5))) do
		local body = bodyOf(wood)
		local held = wood:GetAttribute("HeldBy")
		local owner = wood:GetAttribute("Owner")
		table.insert(candidates, {
			key = wood,
			held = (type(held) == "number" and held ~= 0) or (body ~= nil and body.Anchored),
			wood = body ~= nil,
			ownerId = if type(owner) == "number" then owner else 0,
			landsOnPlot = body ~= nil and landsOnPlot(run, body.Position + dir * AutomationLogic.SweepLand),
		})
	end
	local picked = AutomationLogic.SweepPick(candidates, ownerId)
	for _, wood in ipairs(picked) do
		local body = bodyOf(wood :: Model)
		if body then
			body.AssemblyLinearVelocity = dir * AutomationLogic.SweepSpeed + Vector3.new(0, 4, 0)
		end
	end
	return #picked
end

local function sweeperInput(run: Run, item: PlotLogic.Placed, model: Model, on: boolean)
	local was = model:GetAttribute("Swept") == true
	if on == was then
		return
	end
	poseSweeper(model, on)
	if on then
		LogicService._sweep(run, model)
	end
	local _ = item
end

-- The Wood Detector sees wood over its deck that matches its filter.
local function detectorSees(run: Run, item: PlotLogic.Placed, model: Model): boolean
	local eye = named(model, "Eye")
	if not eye then
		return false
	end
	local filter = savedSetting(run.profile, item.uid, "filter", 0)
	for _, wood in ipairs(woodIn(eye.CFrame, eye.Size)) do
		if AutomationLogic.FilterMatches(filter, wood:GetAttribute("WoodId")) then
			return true
		end
	end
	return false
end

local function woodFolder(): Instance?
	local map = workspace:FindFirstChild("TimberlineMap")
	local found = if map then map:FindFirstChild("Wood") else nil
	return found or workspace:FindFirstChild("Wood")
end

local function portOf(model: Model, z: number): (Vector3?, Vector3?)
	local root = named(model, "Root")
	if not root then
		return nil, nil
	end
	local cf = root.CFrame * CFrame.new(0, AutomationLogic.BeamPortY - 0.1, z)
	-- Local +Z is the emitter's lens side (the model's back, LookVector is -Z).
	return cf.Position, -root.CFrame.LookVector
end

-- The receiver an emitter's beam reaches, and how far.
local function partnerOf(run: Run, emitter: Model): (Model?, number?)
	local ePort, eDir = portOf(emitter, AutomationLogic.BeamPortZ)
	if not ePort or not eDir then
		return nil, nil
	end
	local best: Model? = nil
	local bestD = math.huge
	for _, other in ipairs(run.profile.plot.placed) do
		if other.blueprintId == "LaserReceiver" then
			local model = modelOf(run.host, other.uid)
			if model then
				local rPort, rDir = portOf(model, AutomationLogic.ReceiverPortZ)
				if rPort and rDir then
					-- The receiver's dish is its local -Z: it faces -rDir.
					local d = AutomationLogic.LaserReach(ePort, eDir, rPort, -rDir)
					if d and d < bestD then
						best = model
						bestD = d
					end
				end
			end
		end
	end
	if best then
		return best, bestD
	end
	return nil, nil
end

local function drawBeam(emitter: Model, from: Vector3?, to: Vector3?)
	local beam = emitter:FindFirstChild("Beam")
	if from == nil or to == nil then
		if beam then
			beam:Destroy()
		end
		return
	end
	local part: Part
	if beam and beam:IsA("Part") then
		part = beam
	else
		part = Instance.new("Part")
		part.Name = "Beam"
		part.Shape = Enum.PartType.Cylinder
		part.Material = Enum.Material.Neon
		part.Color = SKY_BLUE
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 0.15
		part.Parent = emitter
	end
	local length = (to - from).Magnitude
	part.Size = Vector3.new(length, 0.08, 0.08)
	part.CFrame = CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.pi / 2, 0)
end

-- QA W7: only wood breaks the beam. Placed walls and players do not.
function LogicService._laserBroken(run: Run, emitter: Model): boolean
	local receiver, dist = partnerOf(run, emitter)
	local ePort, eDir = portOf(emitter, AutomationLogic.BeamPortZ)
	if not receiver or not dist or not ePort or not eDir then
		drawBeam(emitter, nil, nil)
		return false
	end
	local endPoint = ePort + eDir * dist
	drawBeam(emitter, ePort, endPoint)
	local folder = woodFolder()
	if folder == nil then
		return false
	end
	local ok, hit = pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { folder }
		return workspace:Raycast(ePort, eDir * dist, params)
	end)
	return ok and hit ~= nil
end

-- Drop the targets of this plot's pieces that are gone (sold, or a stale
-- registration). PlotService calls Sync after a sale.
local function dropGoneTargets(host: Host, profile: Profile)
	local live: { [string]: boolean } = {}
	for _, item in ipairs(profile.plot.placed) do
		live[item.uid] = true
	end
	for uid, folder in pairs(targetHost) do
		if folder == host.items and not live[uid] then
			targets[uid] = nil
			targetHost[uid] = nil
		end
	end
end

local function applyItem(run: Run, item: PlotLogic.Placed, who: Player?): string?
	local graph = run.graph
	if not graph then
		return nil
	end
	local model = modelOf(run.host, item.uid)
	if not model then
		return nil
	end
	local id = item.blueprintId
	local role = WireLogic.Role(id)
	local on = LogicGraph.On(graph, item.uid)
	local hint: string? = nil
	if role == "lamp" then
		setLamp(model, id, WireLogic.LampLit(fedBy(run.wires, item.uid), on))
	elseif role == "door" then
		if fedBy(run.wires, item.uid) and who then
			hint = setDoor(run.host, run.profile, who, item, model, on)
		end
	elseif role == "hatch" then
		poseHatch(model, on)
	elseif role == "belt" or role == "machine" or role == "detector" then
		LogicService._applyMachine(graph, item, model)
		if role == "detector" then
			setDetectorLamp(model, on)
		end
	elseif role == "sweeper" then
		sweeperInput(run, item, model, on)
	elseif role ~= nil and GLOW_ROLE[role] then
		setLamp(model, id, on)
		if role == "button" or role == "plate" then
			poseCap(model, on)
		end
		if role == "button" then
			model:SetAttribute("On", on)
		end
	end
	local overloaded = LogicGraph.Overloaded(graph, item.uid)
	if overloaded or model:GetAttribute("Overloaded") == true then
		showOverload(model, overloaded)
		if overloaded then
			run.anyOver = true
		end
	end
	return hint
end

local function applyReport(run: Run, who: Player?)
	local graph = run.graph
	if not graph then
		return
	end
	local list = graph.changed
	local hint: string? = nil
	for i = 1, graph.changedN do
		local uid = list[i]
		local item = if uid then findItem(run.profile, uid) else nil
		if item then
			hint = applyItem(run, item, who) or hint
		end
	end
	if hint and who then
		notify(who, hint)
	end
end

local function applyAll(run: Run, who: Player?)
	local hint: string? = nil
	for _, item in ipairs(run.profile.plot.placed) do
		if WireLogic.Role(item.blueprintId) ~= nil then
			hint = applyItem(run, item, who) or hint
		end
	end
	if hint and who then
		notify(who, hint)
	end
end

local function writeWires(run: Run)
	local byFrom: { [string]: { string } } = {}
	for _, wire in ipairs(run.wires) do
		local list = byFrom[wire.from]
		if not list then
			list = {}
			byFrom[wire.from] = list
		end
		local name = wire.to
		local port = wire.toPort
		if port ~= nil and port ~= 1 then
			name ..= "@" .. tostring(port)
		end
		table.insert(list, name)
	end
	for _, item in ipairs(run.profile.plot.placed) do
		if WireLogic.IsSource(WireLogic.Role(item.blueprintId)) then
			local model = modelOf(run.host, item.uid)
			if model then
				local list = byFrom[item.uid]
				model:SetAttribute("Wires", if list then table.concat(list, ",") else "")
			end
		end
	end
end

local function settingsOf(profile: Profile): LogicGraph.Settings
	local logic = profile.plot.logic
	if type(logic) ~= "table" then
		return {}
	end
	return logic
end

-- Recomputes the graph, the wire labels, and every output.
function LogicService.Refresh(host: Host, profile: Profile, who: Player?)
	local placed: { PlotLogic.Placed } = profile.plot.placed
	local live = WireLogic.Live(profile.plot.wires, placed :: any)
	local graph = LogicGraph.Build(placed :: any, live, settingsOf(profile))
	local run = slotRun(host, profile, nil)
	run.graph = graph
	run.wires = live
	run.senseAcc = 0
	for _, item in ipairs(placed) do
		if WireLogic.Latches(item.blueprintId) then
			local model = modelOf(host, item.uid)
			local on = WireLogic.IsOn(profile.plot.switches, item.uid)
			if model then
				on = on or model:GetAttribute("On") == true
				tip(model, item.blueprintId, on)
			end
			if on then
				LogicGraph.Set(graph, item.uid, 1, true)
			end
		end
	end
	writeWires(run)
	applyAll(run, who)
	if WireLogic.LogicCount(placed :: any) > WireLogic.MaxItems and not run.toldCap and who then
		run.toldCap = true
		notify(who, WireLogic.Message("items") or "")
	end
end

function LogicService.Restore(host: Host, profile: Profile, who: Player?)
	LogicService.Refresh(host, profile, who)
end

function LogicService.Sync(host: Host, profile: Profile, who: Player?)
	dropGoneTargets(host, profile)
	if type(profile.plot.wires) == "table" then
		profile.plot.wires = WireLogic.Live(profile.plot.wires, profile.plot.placed)
	end
	if type(profile.plot.switches) == "table" then
		profile.plot.switches = WireLogic.LiveSwitches(profile.plot.switches, profile.plot.placed)
	end
	if type(profile.plot.wires) == "table" then
		LogicService.Refresh(host, profile, who)
	end
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

local function addWire(
	profile: Profile,
	fromUid: string,
	toUid: string,
	fromPort: number?,
	toPort: number?
): (boolean, string?)
	local placed = profile.plot.placed
	profile.plot.wires = WireLogic.Live(wiresOf(profile), placed)
	local ok, why = WireLogic.Check(profile.plot.wires, placed, fromUid, toUid, fromPort, toPort)
	if not ok then
		return false, why
	end
	local wire: WireLogic.Wire = { from = fromUid, to = toUid }
	if fromPort ~= nil and fromPort ~= 1 then
		wire.fromPort = fromPort
	end
	if toPort ~= nil and toPort ~= 1 then
		wire.toPort = toPort
	end
	table.insert(profile.plot.wires, wire)
	return true, nil
end

local function cutWires(profile: Profile, uid: string): number
	local rest, cut = WireLogic.Without(wiresOf(profile), uid)
	profile.plot.wires = rest
	return cut
end

local function rootPosition(player: Player): Vector3?
	local char = player.Character
	if not char then
		return nil
	end
	local part = char:FindFirstChild("HumanoidRootPart") :: any
	if part == nil then
		return nil
	end
	return part.Position
end

local function near(player: Player, host: Host, item: PlotLogic.Placed): boolean
	local pos = rootPosition(player)
	if not pos then
		return false
	end
	local local3 = host.cframe:PointToObjectSpace(pos)
	return WireLogic.InReach(local3.X, local3.Y, local3.Z, item :: any)
end

function LogicService.Link(
	player: Player,
	fromUid: string,
	toUid: string,
	fromPort: number?,
	toPort: number?
): (boolean, string?)
	local get = hostFn
	if not get then
		return false, "bad"
	end
	local host, profile = get(player, "build")
	if not host or not profile then
		return false, "missing"
	end
	local from, to = findItem(profile, fromUid), findItem(profile, toUid)
	if not from or not to then
		return false, "missing"
	end
	if not (near(player, host, from) and near(player, host, to)) then
		return false, "reach"
	end
	local ok, why = addWire(profile, fromUid, toUid, fromPort, toPort)
	if ok then
		LogicService.Refresh(host, profile, player)
	end
	return ok, why
end

function LogicService.Cut(player: Player, uid: string): (boolean, string?)
	local get = hostFn
	if not get then
		return false, "bad"
	end
	local host, profile = get(player, "build")
	if not host or not profile then
		return false, "missing"
	end
	local item = findItem(profile, uid)
	if not item or WireLogic.Role(item.blueprintId) == nil then
		return false, "missing"
	end
	if not near(player, host, item) then
		return false, "reach"
	end
	local cut = cutWires(profile, uid)
	LogicService.Refresh(host, profile, player)
	return cut > 0, if cut > 0 then nil else "none"
end

local function portOk(value: unknown): number?
	if type(value) ~= "number" or value ~= math.floor(value) or value < 1 or value > 8 then
		return nil
	end
	return value
end

function LogicService.OnWire(player: Player, a: unknown, b: unknown, c: unknown, d: unknown)
	if not RateLimiter.Allow(player, "Wire") then
		return
	end
	local ok: boolean, why: string?
	if a == "cut" and type(b) == "string" and c == nil then
		ok, why = LogicService.Cut(player, b)
	elseif type(a) == "string" and type(c) == "string" and a ~= "cut" then
		local fp, tp = portOk(b), portOk(d)
		if not fp or not tp then
			return
		end
		local get = hostFn
		local host: Host? = nil
		local profile: Profile? = nil
		if get then
			host, profile = get(player, "build")
		end
		if host and profile then
			local from, dest = findItem(profile, a), findItem(profile, c)
			if
				from
				and dest
				and not (WireLogic.HasOut(from.blueprintId, fp) and WireLogic.HasIn(dest.blueprintId, tp))
			then
				return
			end
		end
		ok, why = LogicService.Link(player, a, c, fp, tp)
		if ok then
			notify(player, WireLogic.Message("wired") or "")
			return
		end
	else
		return
	end
	local text = WireLogic.Message(if ok then "cleared" else why)
	if text then
		notify(player, text)
	end
end

---------------------------------------------------------------------------
-- Pieces on the plot
---------------------------------------------------------------------------

local function drive(ctx: Context, who: Player, on: boolean)
	local run = runs[ctx.slot.items]
	if run and run.graph and run.profile == (select(2, ctx.ownerOf())) then
		LogicGraph.Set(run.graph, ctx.item.uid, 1, on)
		applyReport(run, who)
		return
	end
	local _, profile = ctx.ownerOf()
	if profile then
		LogicService.Refresh(ctx.slot, profile, who)
	end
	return nil
end

function LogicService.Flip(ctx: Context, who: Player)
	local owner, profile = ctx.ownerOf()
	if not owner or not profile then
		return
	end
	if not mayUse(owner, profile, who, "interact") then
		notify(who, "The owner hasn't let you use that.")
		return
	end
	local now = os.clock()
	local last = lastFlip[ctx.item.uid]
	if last and now - last < WireLogic.FlipCooldown then
		return
	end
	lastFlip[ctx.item.uid] = now
	local on = ctx.model:GetAttribute("On") ~= true
	tip(ctx.model, ctx.item.blueprintId, on)
	profile.plot.switches = WireLogic.SetOn(profile.plot.switches, ctx.item.uid, on)
	drive(ctx, who, on)
end

-- A button press. The graph holds the output for its pulse, then lets go.
function LogicService.Press(ctx: Context, who: Player)
	local owner, profile = ctx.ownerOf()
	if not owner or not profile then
		return
	end
	if not mayUse(owner, profile, who, "interact") then
		notify(who, "The owner hasn't let you use that.")
		return
	end
	local now = os.clock()
	local last = lastFlip[ctx.item.uid]
	if last and now - last < WireLogic.FlipCooldown then
		return
	end
	lastFlip[ctx.item.uid] = now
	ctx.model:SetAttribute("On", true)
	if runs[ctx.slot.items] == nil or runs[ctx.slot.items].graph == nil then
		LogicService.Refresh(ctx.slot, profile, who)
	end
	local run = runs[ctx.slot.items]
	if run and run.graph then
		LogicGraph.Set(run.graph, ctx.item.uid, 1, true)
		applyReport(run, who)
	end
end

function LogicService.WireNearest(ctx: Context, who: Player)
	local owner, profile = ctx.ownerOf()
	if not owner or not profile then
		return
	end
	if not mayUse(owner, profile, who, "build") then
		notify(who, "The owner hasn't let you build here.")
		return
	end
	local uid = ctx.item.uid
	profile.plot.wires = WireLogic.Live(wiresOf(profile), profile.plot.placed)
	local list = WireLogic.Candidates(profile.plot.wires, profile.plot.placed, uid)
	local target = list[1]
	if target then
		local ok, why = addWire(profile, uid, target, nil, nil)
		if ok then
			local other = findItem(profile, target)
			notify(who, string.format("Wired to the %s.", if other then nameOf(other) else "piece"))
			LogicService.Refresh(ctx.slot, profile, who)
		else
			notify(who, WireLogic.Message(why) or "")
		end
		return
	end
	if cutWires(profile, uid) > 0 then
		notify(who, WireLogic.Message("cleared") or "")
		LogicService.Refresh(ctx.slot, profile, who)
	else
		notify(who, WireLogic.Message("none") or "")
	end
end

function LogicService.OnLogicSet(player: Player, uid: unknown, key: unknown, value: unknown)
	if not RateLimiter.Allow(player, "LogicSet") then
		return
	end
	if type(uid) ~= "string" or type(key) ~= "string" or type(value) ~= "number" then
		return
	end
	local get = hostFn
	if not get then
		return
	end
	local host, profile, owner, denied = get(player, "interact")
	if denied or not host or not profile or not owner then
		return
	end
	if not mayUse(owner, profile, player, "interact") then
		notify(player, "The owner hasn't let you use that.")
		return
	end
	local item = findItem(profile, uid)
	if not item then
		return
	end
	if not near(player, host, item) then
		notify(player, WireLogic.Message("reach") or "")
		return
	end
	local clamped = WireLogic.ClampSetting(item.blueprintId, key, value)
	if clamped == nil then
		return
	end
	if type(profile.plot.logic) ~= "table" then
		profile.plot.logic = {}
	end
	local bag = profile.plot.logic[uid]
	if type(bag) ~= "table" then
		bag = {}
		profile.plot.logic[uid] = bag
	end
	bag[key] = clamped
	LogicService.Refresh(host, profile, player)
	local model = modelOf(host, uid)
	if model then
		local prompt = model:FindFirstChild("SetPrompt", true)
		if prompt then
			prompt:SetAttribute("LogicValue", clamped)
		end
	end
	notify(player, string.format("%s set to %s s.", nameOf(item), formatNum(clamped)))
end

local function prompt(parent: Instance, name: string, action: string, object: string, input: string, hold: number)
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold
	p.MaxActivationDistance = InputKit.OpenRange
	InputKit.PromptDefaults(p, input)
	p.Parent = parent
	return p
end

local function onTriggered(p: ProximityPrompt, handler: (Player) -> ())
	local ok, signal = pcall(function()
		return p.Triggered
	end)
	if ok and signal then
		signal:Connect(handler)
	end
end

---------------------------------------------------------------------------
-- Lane W: the owner's belt prompts and target registration
---------------------------------------------------------------------------

local function ownerCheck(ctx: Context, who: Player, budget: string): (Player?, Profile?)
	local owner, profile = ctx.ownerOf()
	if owner == nil or profile == nil then
		return nil, nil
	end
	-- QA W8: owner only, rate limited, standing near the piece.
	if who.UserId ~= owner.UserId then
		notify(who, AutomationLogic.OwnerOnlyLine)
		return nil, nil
	end
	if not RateLimiter.Allow(who, budget) then
		return nil, nil
	end
	if not near(who, ctx.slot, ctx.item) then
		notify(who, WireLogic.Message("reach") or "")
		return nil, nil
	end
	return owner, profile
end

local function reverseText(reversed: boolean): string
	return if reversed then "Run forward" else "Reverse"
end

-- The owner's Reverse prompt: saved on the piece (item.reversed).
function LogicService.Reverse(ctx: Context, who: Player): boolean
	if not AutomationLogic.CanReverse(ctx.item.blueprintId) then
		return false
	end
	local owner = ownerCheck(ctx, who, "BeltReverse")
	if not owner then
		return false
	end
	local item = ctx.item :: any
	local reversed = item.reversed ~= true
	item.reversed = if reversed then true else nil
	ctx.model:SetAttribute("Reversed", reversed)
	local p = ctx.model:FindFirstChild("ReversePrompt", true)
	if p and p:IsA("ProximityPrompt") then
		p.ActionText = reverseText(reversed)
	end
	notify(who, if reversed then AutomationLogic.ReverseLine else AutomationLogic.ForwardLine)
	return true
end

-- The owner's Flip prompt on a Switch Belt: mirrors the diverter (item.flip).
function LogicService.FlipBelt(ctx: Context, who: Player): boolean
	if not AutomationLogic.CanFlip(ctx.item.blueprintId) then
		return false
	end
	local owner = ownerCheck(ctx, who, "BeltFlip")
	if not owner then
		return false
	end
	local item = ctx.item :: any
	local flip = item.flip ~= true
	item.flip = if flip then true else nil
	ctx.model:SetAttribute("Flip", flip)
	notify(who, AutomationLogic.FlipLine)
	return true
end

local function filterObject(filter: number): string
	return "Wood Detector: " .. AutomationLogic.FilterName(filter)
end

-- The owner steps a Wood Detector's filter: any wood, then each wood in
-- WoodData order. Saved in profile.plot.logic[uid].filter.
function LogicService.StepFilter(ctx: Context, who: Player): number?
	local _, profile = ownerCheck(ctx, who, "DetectorFilter")
	if not profile then
		return nil
	end
	if type(profile.plot.logic) ~= "table" then
		profile.plot.logic = {}
	end
	local bag = profile.plot.logic[ctx.item.uid]
	if type(bag) ~= "table" then
		bag = {}
		profile.plot.logic[ctx.item.uid] = bag
	end
	local nextFilter = AutomationLogic.NextFilter(bag.filter)
	bag.filter = if nextFilter == 0 then nil else nextFilter
	if next(bag) == nil then
		profile.plot.logic[ctx.item.uid] = nil
	end
	ctx.model:SetAttribute("Filter", nextFilter)
	local p = ctx.model:FindFirstChild("FilterPrompt", true)
	if p and p:IsA("ProximityPrompt") then
		p.ObjectText = filterObject(nextFilter)
	end
	notify(who, "Watching for: " .. AutomationLogic.FilterName(nextFilter))
	return nextFilter
end

local function targetFor(model: Model): LogicTarget
	return {
		power = function(on: boolean)
			-- Only an unpowered piece carries the attribute, so an unwired
			-- plot looks exactly as it did before Lane W.
			model:SetAttribute("PowerIn", if on then nil else false)
		end,
		reverse = function(on: boolean)
			model:SetAttribute("WireReverse", if on then true else nil)
		end,
	}
end

function LogicService._attachMachine(ctx: Context)
	local id = ctx.item.blueprintId
	local item = ctx.item :: any
	local model = ctx.model
	local uid = ctx.item.uid
	LogicService.RegisterTarget(uid, targetFor(model))
	targetHost[uid] = ctx.slot.items
	if AutomationLogic.CanReverse(id) then
		model:SetAttribute("Reversed", if item.reversed == true then true else nil)
	end
	if AutomationLogic.CanFlip(id) then
		model:SetAttribute("Flip", if item.flip == true then true else nil)
	end
	if model:FindFirstChild("ReversePrompt", true) then
		return -- a rebuilt model keeps its prompts
	end
	local host: Instance = model.PrimaryPart or model
	local object = nameOf(ctx.item)
	if AutomationLogic.CanReverse(id) then
		local p = prompt(host, "ReversePrompt", reverseText(item.reversed == true), object, "Interact", 0)
		onTriggered(p, function(who: Player)
			LogicService.Reverse(ctx, who)
		end)
	end
	if AutomationLogic.CanFlip(id) then
		local p = prompt(host, "BeltFlipPrompt", "Flip", object, "Open", 0)
		onTriggered(p, function(who: Player)
			LogicService.FlipBelt(ctx, who)
		end)
	end
	local _, def = AutomationLogic.Get(id)
	if def and def.shape == "detector" then
		local _, profile = ctx.ownerOf()
		local filter = AutomationLogic.CleanFilter(savedSetting(profile, uid, "filter", 0))
		model:SetAttribute("Filter", filter)
		local p = prompt(host, "FilterPrompt", "Filter", filterObject(filter), "Open", 0)
		onTriggered(p, function(who: Player)
			LogicService.StepFilter(ctx, who)
		end)
	end
end

function LogicService.Attach(ctx: Context)
	local id = ctx.item.blueprintId
	local role = WireLogic.Role(id)
	local owner, profile = ctx.ownerOf()
	if owner and profile then
		local run = slotRun(ctx.slot, profile, owner)
		if WireLogic.LogicCount(profile.plot.placed :: any) > WireLogic.MaxItems and not run.toldCap then
			run.toldCap = true
			notify(owner, WireLogic.Message("items") or "")
		end
	end
	if WireLogic.IsMachine(id) then
		LogicService._attachMachine(ctx)
	end
	if role == "switch" or role == "lever" then
		tip(ctx.model, id, profile ~= nil and WireLogic.IsOn(profile.plot.switches, ctx.item.uid))
		local host: Instance = ctx.model:FindFirstChild("Moving")
			or ctx.model:FindFirstChild("Part" .. LEVER_BOX)
			or ctx.model
		local object = nameOf(ctx.item)
		local flipPrompt = prompt(host, "FlipPrompt", "Flip", object, "Interact", 0)
		onTriggered(flipPrompt, function(who: Player)
			LogicService.Flip(ctx, who)
		end)
		if role == "switch" then
			local wirePrompt = prompt(host, "WirePrompt", "Wire", object, "Open", 0.4)
			onTriggered(wirePrompt, function(who: Player)
				LogicService.WireNearest(ctx, who)
			end)
		end
	elseif role == "button" then
		local host: Instance = ctx.model:FindFirstChild("Moving") or ctx.model:FindFirstChild("Part3") or ctx.model
		local pressPrompt = prompt(host, "PressPrompt", "Press", nameOf(ctx.item), "Interact", 0)
		onTriggered(pressPrompt, function(who: Player)
			LogicService.Press(ctx, who)
		end)
	elseif role == "lamp" then
		local lit = true
		if profile then
			local wires = WireLogic.Live(profile.plot.wires, profile.plot.placed)
			local on: { [string]: boolean } = {}
			for _, uid in ipairs(WireLogic.CleanSwitches(profile.plot.switches)) do
				on[uid] = true
			end
			local fed, powered = WireLogic.Power(wires, ctx.item.uid, on)
			lit = WireLogic.LampLit(fed, powered)
		end
		setLamp(ctx.model, id, lit)
	elseif role == "hatch" then
		local leaf = ctx.model:FindFirstChild("Part2")
		if leaf then
			leaf:SetAttribute("Leaf", true)
		end
	end
	local key, default = WireLogic.DefaultSetting(id)
	local spec = WireLogic.Spec(id)
	if key and default and spec and spec.min and spec.max and spec.step then
		local hostPart: Instance = ctx.model:FindFirstChild("LabelFace")
			or ctx.model:FindFirstChild("Part1")
			or ctx.model
		local setPrompt = prompt(hostPart, "SetPrompt", "Set", nameOf(ctx.item), "Interact", 0)
		setPrompt:SetAttribute("Uid", ctx.item.uid)
		setPrompt:SetAttribute("LogicKey", key)
		setPrompt:SetAttribute("LogicMin", spec.min)
		setPrompt:SetAttribute("LogicMax", spec.max)
		setPrompt:SetAttribute("LogicStep", spec.step)
		setPrompt:SetAttribute("LogicValue", savedSetting(profile, ctx.item.uid, key, default))
	end
end

---------------------------------------------------------------------------
-- Tick, leave, and the showroom demo
---------------------------------------------------------------------------

local plateParams: any = nil
local plateParamsReady = false

local function overlapParams(): any
	if not plateParamsReady then
		plateParamsReady = true
		pcall(function()
			plateParams = OverlapParams.new()
		end)
	end
	return plateParams
end

overlapParamsFn = overlapParams

local function occupied(model: Model): boolean
	local root = model:FindFirstChild("Root")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local ok, parts = pcall(function()
		return workspace:GetPartBoundsInBox(root.CFrame, PLATE_SIZE, overlapParams())
	end)
	if not ok or type(parts) ~= "table" then
		return false
	end
	for _, part in ipairs(parts) do
		if typeof(part) == "Instance" then
			local modelParent = part.Parent
			if modelParent and modelParent:FindFirstChildOfClass("Humanoid") then
				return true
			end
			local upper = if modelParent then modelParent.Parent else nil
			if upper and upper:FindFirstChildOfClass("Humanoid") then
				return true
			end
			local tagged = false
			pcall(function()
				local service = game:GetService("CollectionService")
				tagged = service:HasTag(part, "Wood") or (modelParent ~= nil and service:HasTag(modelParent, "Wood"))
			end)
			if tagged then
				return true
			end
		end
	end
	return false
end

local function sense(run: Run, dt: number)
	local graph = run.graph
	if not graph then
		return
	end
	run.senseAcc += dt
	if run.senseAcc < LogicGraph.Step then
		return
	end
	run.senseAcc = 0
	local tick = (run.laserTick or 0) + 1
	run.laserTick = tick
	-- Lasers raycast at AutomationLogic.LaserHz, every other 0.1 s step.
	local laserStep = tick % math.max(1, math.floor(10 / AutomationLogic.LaserHz + 0.5)) == 0
	local lasers = 0
	for _, item in ipairs(run.profile.plot.placed) do
		local spec = WireLogic.Spec(item.blueprintId)
		if spec and spec.sense and graph.nodes[item.uid] ~= nil then
			local model = modelOf(run.host, item.uid)
			if model then
				local on: boolean
				if spec.role == "detector" then
					on = detectorSees(run, item, model)
				elseif spec.role == "laser" then
					lasers += 1
					if lasers > AutomationLogic.MaxLaserPairs then
						drawBeam(model, nil, nil)
						on = false
					elseif laserStep then
						on = LogicService._laserBroken(run, model)
					else
						on = LogicGraph.On(graph, item.uid)
					end
				else
					on = occupied(model)
				end
				if LogicGraph.On(graph, item.uid) ~= on then
					LogicGraph.Set(graph, item.uid, 1, on)
					applyReport(run, run.owner)
				end
			end
		end
	end
end

local function clearOverload(run: Run)
	local graph = run.graph
	if not graph or not run.anyOver or graph.evals >= LogicGraph.Cap then
		return
	end
	for _, uid in ipairs(graph.order) do
		local model = modelOf(run.host, uid)
		if model and model:GetAttribute("Overloaded") == true then
			showOverload(model, false)
		end
	end
	run.anyOver = false
end

local function online(run: Run): boolean
	local owner = run.owner
	if owner == nil or owner.Parent == nil then
		return false
	end
	if run.host.items.Parent == nil or run.graph == nil then
		return false
	end
	return true
end

local function paintDemo(model: Model?, id: string, lit: boolean)
	if model and model:GetAttribute("Lit") ~= lit then
		setLamp(model, id, lit)
	end
end

local function applyDemo()
	local graph = demoGraph
	if not graph then
		return
	end
	paintDemo(demoModels.gate, "GateAnd", LogicGraph.On(graph, "gate"))
	paintDemo(demoModels.clock, "Clock", LogicGraph.On(graph, "clock"))
	local lamp = demoModels.lamp
	if lamp then
		local lit = WireLogic.LampLit(true, LogicGraph.On(graph, "lamp"))
		if lamp:GetAttribute("Lit") ~= lit then
			setLamp(lamp, "SparkLamp", lit)
		end
	end
	local plate = demoModels.plate
	if plate then
		paintDemo(plate, "PressurePlate", LogicGraph.On(graph, "plate"))
	end
	local hatch = demoModels.hatch
	if hatch then
		local open = LogicGraph.On(graph, "hatch")
		if (hatch:GetAttribute("Open") == true) ~= open then
			poseHatch(hatch, open)
		end
	end
	for _, beam in ipairs(demoBeams) do
		local on = LogicGraph.On(graph, beam.from)
		beam.part.Color = if on then LIT_WIRE else DIM_WIRE
	end
end

local function tickDemo(dt: number)
	local graph = demoGraph
	if not graph then
		return
	end
	demoSense += dt
	if demoSense >= LogicGraph.Step then
		demoSense = 0
		local plate = demoModels.plate
		if plate then
			local on = occupied(plate)
			if LogicGraph.On(graph, "plate") ~= on then
				LogicGraph.Set(graph, "plate", 1, on)
			end
		end
	end
	LogicGraph.Tick(graph, dt)
	applyDemo()
end

function LogicService.Tick(dt: number)
	if type(dt) ~= "number" or dt ~= dt or dt <= 0 or dt > 5 then
		return
	end
	if ticking then
		return
	end
	ticking = true
	slice.reset()
	for _, run in pairs(runs) do
		if online(run) then
			-- One failing plot must never stop the others ticking.
			local ok, err = pcall(function()
				sense(run, dt)
				local graph = run.graph
				if graph then
					LogicGraph.Tick(graph, dt)
					applyReport(run, run.owner)
					clearOverload(run)
				end
			end)
			if not ok then
				warn("[LogicService] " .. tostring(err))
			end
		end
		slice.step()
	end
	local demoOk, demoErr = pcall(function()
		tickDemo(dt)
	end)
	if not demoOk then
		warn("[LogicService] " .. tostring(demoErr))
	end
	slice.step()
	ticking = false
end

function LogicService.Stop(player: Player)
	for items, run in pairs(runs) do
		if run.owner == player then
			runs[items] = nil
		end
	end
end

local function beamBetween(parent: Instance, name: string, a: Vector3, b: Vector3, from: string)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Material = Enum.Material.Neon
	part.Color = DIM_WIRE
	local length = (b - a).Magnitude
	part.Size = Vector3.new(0.12, 0.12, math.max(length, 0.1))
	part.CFrame = CFrame.lookAt((a + b) / 2, b)
	part.Parent = parent
	table.insert(demoBeams, { part = part, from = from })
end

local function tie(model: Model, role: string): Vector3
	local height = 1.2
	if role == "lever" then
		height = 2.4
	elseif role == "lamp" then
		height = 4
	elseif role == "plate" or role == "hatch" then
		height = 0.4
	end
	local pivot = model:GetPivot()
	return pivot.Position + Vector3.new(0, height, 0)
end

local function findBoard(given: BasePart?): BasePart?
	if given and given:IsA("BasePart") then
		return given
	end
	local ok, found = pcall(function()
		return (workspace :: any):FindFirstChild("DemoBoard", true)
	end)
	if ok and typeof(found) == "Instance" and found:IsA("BasePart") then
		return found
	end
	return nil
end

-- A live board in front of a DemoBoard part: lever into both AND inputs,
-- a clock into a lamp, a plate into a hatch. Nobody owns it and nothing
-- is saved. Missing board: do nothing.
function LogicService.BuildDemo(board: BasePart?)
	if demoFolder then
		return
	end
	local found = findBoard(board)
	if not found then
		return
	end
	if found:FindFirstChild("SparkworksDemo") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "SparkworksDemo"
	folder.Parent = found
	demoFolder = folder
	local origin = found.CFrame * CFrame.new(0, -found.Size.Y / 2, -(found.Size.Z / 2 + 3))
	local function put(uid: string, id: string, x: number, z: number): Model
		local bp = PlotData.Blueprint(id)
		if bp == nil then
			error("missing blueprint " .. id)
		end
		local model = BlueprintModels.Build(bp, false)
		model.Name = uid
		BlueprintModels.Place(model, origin, x, z, 0, 0)
		model.Parent = folder
		demoModels[uid] = model
		return model
	end
	local lever = put("lever", "Lever", -8, 0)
	local gate = put("gate", "GateAnd", -3, 0)
	local clock = put("clock", "Clock", 3, 0)
	local lamp = put("lamp", "SparkLamp", 8, 0)
	local plate = put("plate", "PressurePlate", -8, 6)
	local hatch = put("hatch", "Hatch", -2, 6)
	local placed = {
		{ uid = "lever", blueprintId = "Lever" },
		{ uid = "gate", blueprintId = "GateAnd" },
		{ uid = "clock", blueprintId = "Clock" },
		{ uid = "lamp", blueprintId = "SparkLamp" },
		{ uid = "plate", blueprintId = "PressurePlate" },
		{ uid = "hatch", blueprintId = "Hatch" },
	}
	local wires: { WireLogic.Wire } = {
		{ from = "lever", to = "gate" },
		{ from = "lever", to = "gate", toPort = 2 },
		{ from = "clock", to = "lamp" },
		{ from = "plate", to = "hatch" },
	}
	demoGraph = LogicGraph.Build(placed, wires, {})
	setLamp(lamp, "SparkLamp", false)
	beamBetween(folder, "WireAnd", tie(lever, "lever"), tie(gate, "gate"), "lever")
	beamBetween(folder, "WireLamp", tie(clock, "clock"), tie(lamp, "lamp"), "clock")
	beamBetween(folder, "WireHatch", tie(plate, "plate"), tie(hatch, "hatch"), "plate")
	local flipHost: Instance = lever:FindFirstChild("Moving") or lever:FindFirstChild("Part3") or lever
	local flipPrompt = prompt(flipHost, "FlipPrompt", "Flip", "Lever", "Interact", 0)
	onTriggered(flipPrompt, function(_who: Player)
		local on = lever:GetAttribute("On") ~= true
		tip(lever, "Lever", on)
		local graph = demoGraph
		if graph then
			LogicGraph.Set(graph, "lever", 1, on)
			applyDemo()
		end
	end)
	applyDemo()
end

local function startRuntime()
	if started then
		return
	end
	started = true
	pcall(function()
		game:GetService("Players").PlayerRemoving:Connect(function(player)
			LogicService.Stop(player)
		end)
	end)
	pcall(function()
		game:GetService("RunService").Heartbeat:Connect(function(dt)
			LogicService.Tick(dt)
		end)
	end)
	LogicService.BuildDemo(nil)
	pcall(function()
		task.delay(8, function()
			LogicService.BuildDemo(nil)
		end)
	end)
end

function LogicService.Init(remoteEvent: RemoteEvent?)
	if remoteEvent ~= nil and not bound then
		bound = true
		remoteEvent.OnServerEvent:Connect(LogicService.OnWire)
	end
	if remoteEvent ~= nil then
		startRuntime()
	end
end

function LogicService.RegisterTarget(uid: string, target: LogicTarget): boolean
	if type(uid) ~= "string" or uid == "" then
		return false
	end
	if type(target) ~= "table" or type(target.power) ~= "function" or type(target.reverse) ~= "function" then
		return false
	end
	targets[uid] = target
	return true
end

function LogicService.UnregisterTarget(uid: string)
	if type(uid) == "string" then
		targets[uid] = nil
	end
end

function LogicService.Target(uid: string): LogicTarget?
	if type(uid) ~= "string" then
		return nil
	end
	return targets[uid]
end

function LogicService.V1Init(ctx: { remotes: { LogicSet: RemoteEvent? }?, notify: Notify? }?)
	if ctx and ctx.notify and notify == silent then
		notify = ctx.notify
	end
	local remote = if ctx and ctx.remotes then ctx.remotes.LogicSet else nil
	if remote and not logicBound then
		logicBound = true
		remote.OnServerEvent:Connect(function(player: Player, uid: unknown, key: unknown, value: unknown)
			LogicService.OnLogicSet(player, uid, key, value)
		end)
	end
	startRuntime()
end

return LogicService
