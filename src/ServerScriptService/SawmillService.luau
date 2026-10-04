--!strict
-- SawmillService: loose logs and planks go in a placed sawmill and come
-- out as planks (V2_PLAN.md §7). The server decides everything. A client
-- only asks to nudge the cut (SawmillSet: owner, in range, one step).
--
-- Every GameConfig.SellPollSec each mill's Intake is one box query over
-- the Wood folder. A piece that has rested there for Settle seconds, that
-- SawmillLogic will take, and whose WoodWatch verdict is good, is anchored,
-- snapped onto the conveyor (length along the belt, centred so it misses
-- the walls) and slid to the outfeed over 1-3 s. The belt's own
-- AssemblyLinearVelocity matches GameConfig.ConveyorSpeed, aimed out the
-- front. The log is marked selling while that happens, so it can't be
-- grabbed, sold or milled twice. Then it is destroyed and its volume comes
-- back as planks (the log's wood, owner, figure and boost), one at a time,
-- on the ground just past the Output attachment, shoved along the outfeed.
--
-- A plank fed back in is cut again to the panel's current X by Y. The
-- volume, wood, owner, figure and boost carry, and the result is still
-- planks. The sizes used here are the parts at intake time. A piece
-- WoodWatch has not cleared, or one that teleported or is still flying,
-- is left alone. A piece that won't fit raises the BLOCKAGE board.
--
-- Planks are ordinary loose wood after that: drag them, load them, and the
-- sell pad pays the plank price.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local MachineArt = require(ReplicatedStorage.Shared.Art.MachineArt)
local SawmillLogic = require(ReplicatedStorage.Shared.SawmillLogic)
local VehicleLogic = require(ReplicatedStorage.Shared.VehicleLogic)
local GrabService = require(script.Parent.GrabService)
local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)
local WoodService = require(script.Parent.WoodService)

local SawmillService = {}

SawmillService.Settle = 0.3 -- seconds a log rests in the intake before the blade takes it
SawmillService.PlankGap = 0.2 -- seconds between planks coming out
SawmillService.ReachPad = 12 -- studs past the mill's edge that still count as at the panel

type Piece = WoodService.Piece

type Job = {
	mill: Model,
	piece: Piece,
	from: CFrame,
	to: CFrame,
	start: number,
	duration: number,
	planks: { SawmillLogic.Plank },
	woodId: string,
	ownerId: number,
	figure: string?,
	boost: number,
	lux: boolean,
	lastHolderId: number?,
	consumed: boolean,
	next: number,
	nextAt: number,
}

type Context = {
	notify: (Player, string) -> (),
	now: () -> number,
	partsIn: (BasePart) -> { BasePart },
	pieceOf: (BasePart) -> Piece?,
	mills: () -> { Model },
	release: (Model, string) -> (),
	remove: (Piece) -> (),
	spawn: (WoodService.PlankInfo) -> Piece?,
	moved: (Model) -> (),
}

local ctx: Context? = nil
local jobs: { [Model]: Job } = {}
local firstSeen: { [Model]: number } = {}
local running = false

local function defaultPartsIn(intake: BasePart): { BasePart }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { WoodService.Folder() }
	return workspace:GetPartBoundsInBox(intake.CFrame, intake.Size, params)
end

local function defaultMills(): { Model }
	local out: { Model } = {}
	for _, inst in ipairs(CollectionService:GetTagged("Sawmill")) do
		if inst:IsA("Model") and inst.Parent then
			table.insert(out, inst)
		end
	end
	return out
end

local function viewOf(piece: Piece): SawmillLogic.PieceView
	local sections: { SawmillLogic.Section } = {}
	for id, part in pairs(piece.parts) do
		local node = piece.nodes[id]
		table.insert(sections, {
			length = part.Size.Y,
			sx = part.Size.X,
			sz = part.Size.Z,
			dir = part.CFrame.UpVector,
			children = if node then #node.children else 0,
			root = node == nil or node.parent == nil,
		})
	end
	return { kind = piece.kind, sections = sections }
end

local function speedOf(piece: Piece): number
	-- A part that has never been given a velocity (a spec double) is at rest.
	-- Reading the property before anyone writes it errors outside Roblox.
	local ok, vel = pcall(function()
		return piece.root.AssemblyLinearVelocity
	end)
	if not ok or typeof(vel) ~= "Vector3" then
		return 0
	end
	return vel.Magnitude
end

-- WoodWatch's last accepted place against where the part is now. A
-- teleport that the watch hasn't judged yet still fails this. Pieces with
-- no watch record (a spec double) are not treated as a jump.
local function jumped(piece: Piece, now: number): boolean
	local record = piece :: any
	local last = record.lastGood
	local at = record.lastGoodAt
	if typeof(last) ~= "CFrame" or type(at) ~= "number" then
		return false
	end
	local verdict = VehicleLogic.JudgeMove(last.Position, piece.root.CFrame.Position, now - at, GameConfig.WoodMaxSpeed)
	return verdict == "tooFar"
end

local function settingsOf(model: Model, mill: ItemCatalog.SawmillDef): SawmillLogic.Settings
	local x = model:GetAttribute("CutX")
	local y = model:GetAttribute("CutY")
	return SawmillLogic.ClampSettings(
		mill,
		if type(x) == "number" then x else 1,
		if type(y) == "number" then y else 0.6
	)
end

local function outputCf(model: Model): CFrame
	local att = model:FindFirstChild("Output", true)
	if att and att:IsA("Attachment") then
		local parent = att.Parent
		if parent and parent:IsA("BasePart") then
			return parent.CFrame * att.CFrame
		end
	end
	return model:GetPivot() * CFrame.new(0, 2, 8)
end

local function unit(v: Vector3): Vector3
	if v.Magnitude < 1e-6 then
		return Vector3.zAxis
	end
	return v.Unit
end

local function beltPart(mill: Model): BasePart?
	local belt = mill:FindFirstChild("Conveyor", true)
	if belt and belt:IsA("BasePart") and belt.CanCollide then
		return belt
	end
	return nil
end

local function lengthOf(piece: Piece): number
	local n = 0
	for _, part in pairs(piece.parts) do
		n += part.Size.Y
	end
	return math.max(n, 0.2)
end

local function radiusOf(piece: Piece): number
	local r = 0.2
	for _, part in pairs(piece.parts) do
		r = math.max(r, math.min(part.Size.X, part.Size.Z) / 2)
	end
	return r
end

-- Y axis (a section's length) lies along `dir`.
local function along(pos: Vector3, dir: Vector3): CFrame
	local yAxis = unit(dir)
	local xAxis = yAxis:Cross(Vector3.yAxis)
	if xAxis.Magnitude < 0.2 then
		xAxis = yAxis:Cross(Vector3.xAxis)
	end
	xAxis = xAxis.Unit
	return CFrame.fromMatrix(pos, xAxis, yAxis, xAxis:Cross(yAxis))
end

-- Both poses sit on the belt centreline, so the slide never walks the log
-- into a side wall. The centre travels nearly the whole belt; a log longer
-- than the mill hangs out the ends (those guards don't collide with wood).
local function beltEnds(belt: BasePart, piece: Piece): (CFrame, CFrame)
	local look = unit(belt.CFrame.LookVector)
	local half = belt.Size.Z / 2
	local nose = math.min(lengthOf(piece) / 2, half * 0.35)
	local lift = belt.CFrame.UpVector * (belt.Size.Y / 2 + radiusOf(piece))
	-- CFrame, not .Position: art is placed with CFrame, and a part's
	-- Position stays unset until something writes it.
	local at = belt.CFrame.Position
	local entry = at - look * (half - nose) + lift
	local exit = at + look * (half - nose) + lift
	return along(entry, look), along(exit, look)
end

-- Length (the part's Y) points out of the mill. Planks sit on the ground
-- just past the outfeed, four high, so a burst doesn't spawn inside the
-- housing or inside itself.
local function plankCf(out: CFrame, plank: SawmillLogic.Plank, index: number): CFrame
	local look = unit(out.LookVector)
	local up = if math.abs(look:Dot(Vector3.yAxis)) > 0.99 then Vector3.zAxis else Vector3.yAxis
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = Vector3.xAxis
	end
	right = right.Unit
	local layer = (index - 1) % 4
	local row = math.floor((index - 1) / 4)
	local pos = out.Position + look * (plank.sy / 2 + 0.6) + right * (row * (plank.sx + 0.3))
	pos = Vector3.new(pos.X, 0.05 + plank.sz / 2 + layer * (plank.sz + 0.12), pos.Z)
	return CFrame.fromMatrix(pos, right, look)
end

local function anchor(piece: Piece, on: boolean)
	for _, part in pairs(piece.parts) do
		part.Anchored = on
	end
	piece.root.Anchored = on
end

local function tell(userId: number, text: string)
	local c = ctx
	if not c or userId == 0 then
		return
	end
	local player = game:GetService("Players"):GetPlayerByUserId(userId)
	if player then
		c.notify(player, text)
	end
end

local function refuse(piece: Piece, why: string, mill: ItemCatalog.SawmillDef)
	local text = SawmillLogic.Toast(why, mill)
	if not text or piece.model:GetAttribute("MillNote") == why then
		return
	end
	piece.model:SetAttribute("MillNote", why)
	tell(piece.ownerId, text)
end

local function abort(job: Job)
	local piece = job.piece
	local c = ctx
	if piece.model.Parent and not piece.dead and not job.consumed then
		piece.selling = nil
		anchor(piece, false)
		if c then
			c.moved(piece.model)
		end
	end
end

local function startJob(c: Context, mill: Model, piece: Piece, millDef: ItemCatalog.SawmillDef, now: number)
	local view = viewOf(piece)
	-- The parts now, not the record and not anything a client sent.
	local volume = SawmillLogic.MeasuredVolume(view)
	if volume < 0 or not SawmillLogic.VolumeMatches(piece.volume, volume) then
		refuse(piece, "size", millDef)
		return
	end
	local planks = SawmillLogic.Cut(volume, settingsOf(mill, millDef), millDef)
	if #planks == 0 then
		refuse(piece, "small", millDef)
		return
	end
	c.release(piece.model, "mill")
	piece.selling = true
	piece.model:SetAttribute("MillNote", nil)
	c.moved(piece.model)
	WoodService.Physics.SetOwner(piece.root, nil)
	anchor(piece, true)
	local fromCf, toCf
	local belt = beltPart(mill)
	if belt then
		fromCf, toCf = beltEnds(belt, piece)
	else
		fromCf = piece.model:GetPivot()
		local intake = mill:FindFirstChild("Intake")
		toCf = if intake and intake:IsA("BasePart") then intake.CFrame else outputCf(mill)
	end
	piece.model:PivotTo(fromCf)
	firstSeen[piece.model] = nil
	jobs[mill] = {
		mill = mill,
		piece = piece,
		from = fromCf,
		to = toCf,
		start = now,
		duration = SawmillLogic.ProcessSeconds(volume),
		planks = planks,
		woodId = piece.woodId,
		ownerId = piece.ownerId,
		figure = piece.figure,
		boost = piece.boost,
		lux = piece.lux == true,
		lastHolderId = piece.lastHolderId,
		consumed = false,
		next = 1,
		nextAt = 0,
	}
end

local function consider(
	c: Context,
	mill: Model,
	piece: Piece,
	now: number,
	inside: { [Model]: boolean },
	blocked: { [Model]: boolean }
)
	inside[piece.model] = true
	if piece.selling or piece.dead or piece.shopItem or not piece.verdictOk then
		return
	end
	if piece.root.Parent == nil then
		return
	end
	-- A teleport or a fling. Don't start the settle clock while it's moving.
	if jumped(piece, now) or not SawmillLogic.Rested(speedOf(piece)) then
		firstSeen[piece.model] = nil
		return
	end
	local millId = mill:GetAttribute("MillId")
	local millDef = if type(millId) == "string" then ItemCatalog.GetSawmill(millId) else nil
	if not millDef then
		return
	end
	local view = viewOf(piece)
	local measured = SawmillLogic.MeasuredVolume(view)
	local ok, why = SawmillLogic.Accepts(view, millDef)
	if ok and not SawmillLogic.VolumeMatches(piece.volume, measured) then
		ok = false
		why = "size"
	end
	if not ok then
		if why then
			refuse(piece, why, millDef)
			if SawmillLogic.ShowsBlockage(why) then
				blocked[mill] = true
			end
		end
		return
	end
	local seen = firstSeen[piece.model]
	if not seen then
		firstSeen[piece.model] = now
		return
	end
	if now - seen < SawmillService.Settle then
		return
	end
	startJob(c, mill, piece, millDef, now)
end

local function poll(c: Context, now: number)
	local inside: { [Model]: boolean } = {}
	local blocked: { [Model]: boolean } = {}
	for _, mill in ipairs(c.mills()) do
		if jobs[mill] or mill.Parent == nil then
			continue
		end
		local intake = mill:FindFirstChild("Intake")
		if not intake or not intake:IsA("BasePart") then
			continue
		end
		local touched: { [Piece]: boolean } = {}
		for _, part in ipairs(c.partsIn(intake)) do
			local piece = c.pieceOf(part)
			if piece and not touched[piece] then
				touched[piece] = true
				consider(c, mill, piece, now, inside, blocked)
				if jobs[mill] then
					break
				end
			end
		end
		MachineArt.SetBlockage(mill, blocked[mill] == true)
	end
	for model in pairs(firstSeen) do
		if not inside[model] then
			firstSeen[model] = nil
		end
	end
end

-- The owner is online: tell MilestoneService a plank was made. BadgeService
-- listens there. No per-second scan of loose wood. A missing Players stub
-- (some specs) is not an error, and an offline owner earns nothing.
local function notePlank(ownerId: number)
	local ok, players = pcall(function(): any
		return game:GetService("Players")
	end)
	if not ok or players == nil or type((players :: any).GetPlayerByUserId) ~= "function" then
		return
	end
	local player = (players :: any):GetPlayerByUserId(ownerId)
	if player == nil then
		return
	end
	local MilestoneService = require(script.Parent.MilestoneService)
	MilestoneService.Event(player, "plank")
end

local function emitOne(c: Context, job: Job)
	local plank = job.planks[job.next]
	if not plank then
		jobs[job.mill] = nil
		return
	end
	local out = outputCf(job.mill)
	local cf = plankCf(out, plank, job.next)
	local spawned = c.spawn({
		woodId = job.woodId,
		size = Vector3.new(plank.sx, plank.sy, plank.sz),
		cf = cf,
		ownerId = job.ownerId,
		figure = job.figure,
		boost = job.boost,
		lux = job.lux,
		lastHolderId = job.lastHolderId,
	})
	-- Shove it out along the outfeed. SpawnPlank leaves the plank loose.
	if spawned and spawned.root then
		spawned.root.AssemblyLinearVelocity = unit(out.LookVector) * GameConfig.ConveyorSpeed
	end
	notePlank(job.ownerId)
	job.next += 1
	job.nextAt += SawmillService.PlankGap
	if job.planks[job.next] == nil then
		jobs[job.mill] = nil
	end
end

local function stepJobs(c: Context, now: number)
	for mill, job in pairs(jobs) do
		if mill.Parent == nil then
			abort(job)
			jobs[mill] = nil
			continue
		end
		if not job.consumed then
			local piece = job.piece
			if piece.dead or piece.model.Parent == nil or piece.root.Parent == nil then
				jobs[mill] = nil
				continue
			end
			local alpha = math.clamp((now - job.start) / math.max(job.duration, 0.05), 0, 1)
			piece.model:PivotTo(job.from:Lerp(job.to, alpha))
			local travel = job.to.Position - job.from.Position
			if travel.Magnitude > 1e-3 then
				piece.root.AssemblyLinearVelocity = travel.Unit * GameConfig.ConveyorSpeed
			end
			c.moved(piece.model)
			if alpha < 1 then
				continue
			end
			job.consumed = true
			job.nextAt = now
			c.remove(piece)
		end
		while jobs[mill] == job and job.consumed and now + 1e-9 >= job.nextAt do
			emitOne(c, job)
		end
	end
end

-- One poll and one step of every job. The live loop calls it; specs do too.
function SawmillService.Tick()
	local c = ctx
	if not c then
		return
	end
	local now = c.now()
	for _, mill in ipairs(c.mills()) do
		MachineArt.AimBelt(mill)
	end
	poll(c, now)
	stepJobs(c, now)
end

local function nearMill(player: Player, model: Model, mill: ItemCatalog.SawmillDef): boolean
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not hrp then
		return false
	end
	local reach = SawmillService.ReachPad + math.max(mill.width, mill.depth) / 2 + GameConfig.RangeTolerance
	return (hrp.Position - model:GetPivot().Position).Magnitude <= reach
end

-- SawmillSet: nudge the cut one step. Owner only, standing at the mill.
function SawmillService.Set(player: Player, uid: unknown, axis: unknown, dir: unknown)
	local c = ctx
	local stepAxis = if axis == "x" or axis == "y" then axis else nil
	local stepDir = if dir == 1 or dir == -1 then dir else nil
	if not c or type(uid) ~= "string" or stepAxis == nil or stepDir == nil then
		return
	end
	if not RateLimiter.Allow(player, "SawmillSet") then
		return
	end
	local model: Model? = nil
	for _, mill in ipairs(c.mills()) do
		if mill:GetAttribute("Uid") == uid then
			model = mill
			break
		end
	end
	if not model or model:GetAttribute("OwnerId") ~= player.UserId then
		return
	end
	local millId = model:GetAttribute("MillId")
	local mill = if type(millId) == "string" then ItemCatalog.GetSawmill(millId) else nil
	if not mill or not nearMill(player, model, mill) then
		return
	end
	local settings = SawmillLogic.Step(mill, settingsOf(model, mill), stepAxis, stepDir :: number)
	model:SetAttribute("CutX", settings.x)
	model:SetAttribute("CutY", settings.y)
	MachineArt.SetCut(model, settings.x, settings.y)
	local profile = ProfileService.GetProfile(player)
	if profile then
		for _, item in ipairs(profile.plot.placed) do
			if item.uid == uid then
				item.data = { x = settings.x, y = settings.y }
				break
			end
		end
	end
end

local function liveContext(notifyFn: (Player, string) -> ()): Context
	return {
		notify = notifyFn,
		now = os.clock,
		partsIn = defaultPartsIn,
		pieceOf = function(part: BasePart): Piece?
			return WoodService.FromPart(part)
		end,
		mills = defaultMills,
		release = GrabService.ReleasePiece,
		remove = function(piece: Piece)
			WoodService.Remove(piece, "milled")
		end,
		spawn = WoodService.SpawnPlank,
		moved = WoodService.Moved,
	}
end

function SawmillService.Init(notifyFn: (Player, string) -> (), remote: RemoteEvent)
	ctx = liveContext(notifyFn)
	table.clear(jobs)
	table.clear(firstSeen)
	remote.OnServerEvent:Connect(function(player: Player, uid: unknown, axis: unknown, dir: unknown)
		SawmillService.Set(player, uid, axis, dir)
	end)
	if running then
		return
	end
	running = true
	task.spawn(function()
		while running do
			task.wait(GameConfig.SellPollSec)
			local ok, err = pcall(function(): any
				SawmillService.Tick()
				return nil
			end)
			if not ok then
				warn("[SawmillService] tick failed: " .. tostring(err))
			end
		end
	end)
end

function SawmillService._reset()
	ctx = nil
	running = false
	table.clear(jobs)
	table.clear(firstSeen)
end

-- Specs: a context and no polling loop.
function SawmillService._use(partial: {
	notify: (Player, string) -> (),
	now: (() -> number)?,
	partsIn: ((BasePart) -> { BasePart })?,
	pieceOf: ((BasePart) -> Piece?)?,
	mills: (() -> { Model })?,
	release: ((Model, string) -> ())?,
	remove: ((Piece) -> ())?,
	spawn: ((WoodService.PlankInfo) -> Piece?)?,
	moved: ((Model) -> ())?,
})
	ctx = {
		notify = partial.notify,
		now = partial.now or os.clock,
		partsIn = partial.partsIn or defaultPartsIn,
		pieceOf = partial.pieceOf or function(part: BasePart): Piece?
			return WoodService.FromPart(part)
		end,
		mills = partial.mills or defaultMills,
		release = partial.release or GrabService.ReleasePiece,
		remove = partial.remove or function(piece: Piece)
			WoodService.Remove(piece, "milled")
		end,
		spawn = partial.spawn or WoodService.SpawnPlank,
		moved = partial.moved or function(_model: Model) end,
	}
	table.clear(jobs)
	table.clear(firstSeen)
end

return SawmillService
