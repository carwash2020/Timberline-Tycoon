--!strict
-- PlanerService: a loose plank goes into a placed planer and comes out a
-- finished board (V2_PLAN.md §2h). The server decides everything. A client
-- only asks to nudge the setting (PlanerSet: owner, in range, one step).
--
-- Every GameConfig.SellPollSec each planer's Intake is one box query over the
-- Wood folder, as the sawmill's is. A plank that has rested there for Settle
-- seconds, that PlanerLogic.Plane will take at the current setting, whose
-- WoodWatch verdict is good, is anchored and slid through to the outfeed over
-- 1 to 2.5 s (it is marked selling meanwhile so it can't be grabbed, sold or
-- planed twice). At the far end its section is planed down to the setting (a
-- bigger plank loses the shavings; a smaller one was refused at the door),
-- it is stamped with the planer's boardBonus (never lowering an existing
-- stamp) and let go, shoved out the front. It is the SAME piece: its owner,
-- wood, figure, boost, lux, mill bonus and Prosperous stamp `t` carry;
-- SellLogic does the rest.
--
-- Belts: a plank nobody has touched for AutomationLogic.HandWindow seconds
-- came by belt: it is capped by the tier's autoRate and refused for rare
-- wood, someone else's wood, an offline owner or a full plot, exactly as at
-- the sawmill. A hand-fed plank is never capped.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AutomationLogic = require(ReplicatedStorage.Shared.AutomationLogic)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local MachineArt = require(ReplicatedStorage.Shared.Art.MachineArt)
local PlanerLogic = require(ReplicatedStorage.Shared.PlanerLogic)
local SawmillLogic = require(ReplicatedStorage.Shared.SawmillLogic)
local SellLogic = require(ReplicatedStorage.Shared.SellLogic)
local VehicleLogic = require(ReplicatedStorage.Shared.VehicleLogic)
local GrabService = require(script.Parent.GrabService)
local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)
local WoodService = require(script.Parent.WoodService)

local PlanerService = {}

PlanerService.Settle = PlanerLogic.Settle
PlanerService.ReachPad = 12 -- studs past the planer's edge that still count as at the panel

type Piece = WoodService.Piece

type Job = {
	planer: Model,
	piece: Piece,
	from: CFrame,
	to: CFrame,
	start: number,
	duration: number,
	size: PlanerLogic.Plank,
	board: number,
	out: CFrame,
	pausedAt: number?, -- Lane W: power went off mid-plane at this time
}

type Context = {
	notify: (Player, string) -> (),
	now: () -> number,
	partsIn: (BasePart) -> { BasePart },
	pieceOf: (BasePart) -> Piece?,
	planers: () -> { Model },
	release: (Model, string) -> (),
	finish: (Piece, PlanerLogic.Plank, number) -> (), -- plane the section, stamp the bonus, publish
	moved: (Model) -> (),
	online: (number) -> boolean,
	outputs: (number) -> number,
}

local ctx: Context? = nil
local jobs: { [Model]: Job } = {}
local firstSeen: { [Model]: number } = {}
local buckets: { [Model]: AutomationLogic.Bucket } = {}
local running = false

local function defaultPartsIn(intake: BasePart): { BasePart }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { WoodService.Folder() }
	return workspace:GetPartBoundsInBox(intake.CFrame, intake.Size, params)
end

local function defaultPlaners(): { Model }
	local out: { Model } = {}
	for _, inst in ipairs(CollectionService:GetTagged(PlanerLogic.Tag)) do
		if inst:IsA("Model") and inst.Parent then
			table.insert(out, inst)
		end
	end
	return out
end

local function viewOf(piece: Piece): PlanerLogic.View
	local sections = {}
	for id, part in pairs(piece.parts) do
		local node = piece.nodes[id]
		table.insert(sections, {
			length = part.Size.Y,
			sx = part.Size.X,
			sz = part.Size.Z,
			children = if node then #node.children else 0,
		})
	end
	return { kind = piece.kind, finished = piece.board > 1, sections = sections }
end

local function speedOf(piece: Piece): number
	local ok, vel = pcall(function()
		return piece.root.AssemblyLinearVelocity
	end)
	if not ok or typeof(vel) ~= "Vector3" then
		return 0
	end
	return vel.Magnitude
end

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

local function settingsOf(model: Model, def: PlanerLogic.Def): PlanerLogic.Settings
	local x = model:GetAttribute("CutX")
	local y = model:GetAttribute("CutY")
	return PlanerLogic.Clamp(def, if type(x) == "number" then x else 1, if type(y) == "number" then y else 0.6)
end

local function unit(v: Vector3): Vector3
	if v.Magnitude < 1e-6 then
		return Vector3.zAxis
	end
	return v.Unit
end

-- The plank's length (its Y) lies along `dir`, centred at `pos`.
local function along(pos: Vector3, dir: Vector3): CFrame
	local yAxis = unit(dir)
	local xAxis = yAxis:Cross(Vector3.yAxis)
	if xAxis.Magnitude < 0.2 then
		xAxis = yAxis:Cross(Vector3.xAxis)
	end
	xAxis = xAxis.Unit
	return CFrame.fromMatrix(pos, xAxis, yAxis, xAxis:Cross(yAxis))
end

local function outputCf(model: Model): CFrame
	local att = model:FindFirstChild("Output", true)
	if att and att:IsA("Attachment") then
		local parent = att.Parent
		if parent and parent:IsA("BasePart") then
			return parent.CFrame * att.CFrame
		end
	end
	return model:GetPivot() * CFrame.new(0, 2, 6)
end

-- The two poses of the slide: the middle of the throat and the mouth, both
-- on the belt's line and as high as the belt's top.
local function ends(model: Model, piece: Piece): (CFrame, CFrame)
	local belt = model:FindFirstChild("Conveyor", true)
	if belt and belt:IsA("BasePart") then
		local look = unit(belt.CFrame.LookVector)
		local half = belt.Size.Z / 2
		local thick = 0.2
		for _, part in pairs(piece.parts) do
			thick = math.max(thick, math.min(part.Size.X, part.Size.Z) / 2)
		end
		local lift = belt.CFrame.UpVector * (belt.Size.Y / 2 + thick)
		local at = belt.CFrame.Position
		return along(at - look * (half * 0.55) + lift, look), along(at + look * (half * 0.55) + lift, look)
	end
	local out = outputCf(model)
	local pivot = model:GetPivot()
	return along(pivot.Position + Vector3.new(0, 1.5, 0), out.LookVector), along(out.Position, out.LookVector)
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

local function note(piece: Piece, key: string, text: string?)
	if not text or piece.model:GetAttribute("MillNote") == key then
		return
	end
	piece.model:SetAttribute("MillNote", key)
	tell(piece.ownerId, text)
end

local function startJob(
	c: Context,
	planer: Model,
	piece: Piece,
	def: PlanerLogic.Def,
	size: PlanerLogic.Plank,
	now: number
)
	c.release(piece.model, "planer")
	piece.selling = true
	piece.model:SetAttribute("MillNote", nil)
	c.moved(piece.model)
	WoodService.Physics.SetOwner(piece.root, nil)
	anchor(piece, true)
	local fromCf, toCf = ends(planer, piece)
	piece.model:PivotTo(fromCf)
	firstSeen[piece.model] = nil
	local volume = PlanerLogic.Volume({ sx = size.sx, sy = size.sy, sz = size.sz })
	jobs[planer] = {
		planer = planer,
		piece = piece,
		from = fromCf,
		to = toCf,
		start = now,
		duration = PlanerLogic.ProcessSeconds(volume),
		size = size,
		board = PlanerLogic.Stamp(piece.board, def),
		out = outputCf(planer),
	}
end

local function consider(c: Context, planer: Model, piece: Piece, now: number, inside: { [Model]: boolean })
	inside[piece.model] = true
	if piece.selling or piece.dead or piece.shopItem or not piece.verdictOk then
		return
	end
	if piece.root.Parent == nil then
		return
	end
	if jumped(piece, now) or not SawmillLogic.Rested(speedOf(piece)) then
		firstSeen[piece.model] = nil
		return
	end
	local planerId = planer:GetAttribute("PlanerId")
	local _machine, def = PlanerLogic.Get(planerId)
	if not def then
		return
	end
	local ok, why, size = PlanerLogic.Plane(viewOf(piece), def, settingsOf(planer, def))
	if not ok or not size then
		if why then
			note(piece, why, PlanerLogic.Toast(why, def))
		end
		return
	end
	local seen = firstSeen[piece.model]
	if not seen then
		firstSeen[piece.model] = now
		return
	end
	if now - seen < PlanerService.Settle then
		return
	end
	local machineOwner = planer:GetAttribute("OwnerId")
	local ownerId = if type(machineOwner) == "number" then machineOwner else 0
	local touched = piece.lastInteracted
	local automated = type(touched) == "number" and AutomationLogic.IsAutomated(now - touched)
	if automated then
		local reason = AutomationLogic.Refusal({
			automated = true,
			woodId = piece.woodId,
			figure = piece.figure,
			elder = piece.elder,
			lux = piece.lux,
			pieceOwnerId = piece.ownerId,
			machineOwnerId = ownerId,
			ownerOnline = c.online(ownerId),
			looseOutputs = c.outputs(ownerId),
		})
		if reason then
			if reason ~= "offline" then
				note(piece, reason, AutomationLogic.RefusalLine(reason))
			end
			return
		end
		local bucket = buckets[planer]
		if not bucket then
			bucket = AutomationLogic.NewBucket(def.autoRate, now)
			buckets[planer] = bucket
		end
		if not AutomationLogic.Ready(bucket, now) then
			return
		end
		AutomationLogic.Take(bucket, piece.volume, now)
	end
	startJob(c, planer, piece, def, size, now)
end

local function poll(c: Context, now: number)
	local inside: { [Model]: boolean } = {}
	for _, planer in ipairs(c.planers()) do
		if
			jobs[planer]
			or planer.Parent == nil
			or not AutomationLogic.MachinePowered(planer:GetAttribute("PowerIn"))
		then
			continue
		end
		local intake = planer:FindFirstChild("Intake")
		if not intake or not intake:IsA("BasePart") then
			continue
		end
		local touched: { [Piece]: boolean } = {}
		for _, part in ipairs(c.partsIn(intake)) do
			local piece = c.pieceOf(part)
			if piece and not touched[piece] then
				touched[piece] = true
				consider(c, planer, piece, now, inside)
				if jobs[planer] then
					break
				end
			end
		end
	end
	for model in pairs(firstSeen) do
		if not inside[model] then
			firstSeen[model] = nil
		end
	end
end

local function stepJobs(c: Context, now: number)
	for planer, job in pairs(jobs) do
		local piece = job.piece
		if planer.Parent == nil then
			-- The planer was taken apart mid-job: let the plank go, unplaned.
			if piece.model.Parent and not piece.dead then
				piece.selling = nil
				anchor(piece, false)
				c.moved(piece.model)
			end
			jobs[planer] = nil
			continue
		end
		if piece.dead or piece.model.Parent == nil or piece.root.Parent == nil then
			jobs[planer] = nil
			continue
		end
		-- Lane W: power off pauses the plank where it is; the clock resumes
		-- with power, so the board comes out once, the same size.
		if not AutomationLogic.MachinePowered(planer:GetAttribute("PowerIn")) then
			if job.pausedAt == nil then
				job.pausedAt = now
			end
			piece.root.AssemblyLinearVelocity = Vector3.zero
			continue
		elseif job.pausedAt ~= nil then
			job.start += AutomationLogic.PauseShift(job.pausedAt, now)
			job.pausedAt = nil
		end
		local alpha = math.clamp((now - job.start) / math.max(job.duration, 0.05), 0, 1)
		piece.model:PivotTo(job.from:Lerp(job.to, alpha))
		c.moved(piece.model)
		if alpha < 1 then
			continue
		end
		c.finish(piece, job.size, job.board)
		piece.selling = nil
		anchor(piece, false)
		local look = unit(job.out.LookVector)
		piece.root.AssemblyLinearVelocity = look * GameConfig.ConveyorSpeed
		c.moved(piece.model)
		jobs[planer] = nil
	end
end

-- One poll and one step of every job. The live loop calls it; specs do too.
function PlanerService.Tick()
	local c = ctx
	if not c then
		return
	end
	local now = c.now()
	for _, planer in ipairs(c.planers()) do
		MachineArt.AimBelt(planer, if AutomationLogic.MachinePowered(planer:GetAttribute("PowerIn")) then nil else 0)
	end
	poll(c, now)
	stepJobs(c, now)
end

local function nearPlaner(player: Player, model: Model, def: PlanerLogic.Def): boolean
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not hrp then
		return false
	end
	local reach = PlanerService.ReachPad + math.max(def.width, def.depth) / 2 + GameConfig.RangeTolerance
	return (hrp.Position - model:GetPivot().Position).Magnitude <= reach
end

-- PlanerSet: nudge the setting one step. Owner only, standing at the planer,
-- rate limited, clamped to the tier, saved on the placed piece's data.
function PlanerService.Set(player: Player, uid: unknown, axis: unknown, dir: unknown)
	local c = ctx
	local stepAxis = if axis == "x" or axis == "y" then axis else nil
	local stepDir = if dir == 1 or dir == -1 then dir else nil
	if not c or type(uid) ~= "string" or stepAxis == nil or stepDir == nil then
		return
	end
	if not RateLimiter.Allow(player, "PlanerSet") then
		return
	end
	local model: Model? = nil
	for _, planer in ipairs(c.planers()) do
		if planer:GetAttribute("Uid") == uid then
			model = planer
			break
		end
	end
	if not model or model:GetAttribute("OwnerId") ~= player.UserId then
		return
	end
	local _machine, def = PlanerLogic.Get(model:GetAttribute("PlanerId"))
	if not def or not nearPlaner(player, model, def) then
		return
	end
	local settings = PlanerLogic.Step(def, settingsOf(model, def), stepAxis, stepDir :: number)
	model:SetAttribute("CutX", settings.x)
	model:SetAttribute("CutY", settings.y)
	MachineArt.SetCut(model, settings.x, settings.y, PlanerLogic.RangeText(def))
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
		planers = defaultPlaners,
		release = GrabService.ReleasePiece,
		finish = function(piece: Piece, size: PlanerLogic.Plank, board: number)
			for _, part in pairs(piece.parts) do
				part.Size = Vector3.new(size.sx, size.sy, size.sz)
			end
			piece.board = board
			piece.temper = SellLogic.Temper(piece.temper)
			WoodService.Publish(piece)
		end,
		moved = WoodService.Moved,
		online = function(userId: number): boolean
			return game:GetService("Players"):GetPlayerByUserId(userId) ~= nil
		end,
		outputs = WoodService.CountOutputs,
	}
end

function PlanerService.Init(notifyFn: (Player, string) -> (), remote: RemoteEvent)
	ctx = liveContext(notifyFn)
	table.clear(jobs)
	table.clear(firstSeen)
	table.clear(buckets)
	remote.OnServerEvent:Connect(function(player: Player, uid: unknown, axis: unknown, dir: unknown)
		PlanerService.Set(player, uid, axis, dir)
	end)
	if running then
		return
	end
	running = true
	task.spawn(function()
		while running do
			task.wait(GameConfig.SellPollSec)
			local ok, err = pcall(function(): any
				PlanerService.Tick()
				return nil
			end)
			if not ok then
				warn("[PlanerService] tick failed: " .. tostring(err))
			end
		end
	end)
end

function PlanerService._reset()
	ctx = nil
	running = false
	table.clear(jobs)
	table.clear(firstSeen)
	table.clear(buckets)
end

-- Specs: a context and no polling loop.
function PlanerService._use(partial: {
	notify: (Player, string) -> (),
	now: (() -> number)?,
	partsIn: ((BasePart) -> { BasePart })?,
	pieceOf: ((BasePart) -> Piece?)?,
	planers: (() -> { Model })?,
	release: ((Model, string) -> ())?,
	finish: ((Piece, PlanerLogic.Plank, number) -> ())?,
	moved: ((Model) -> ())?,
	online: ((number) -> boolean)?,
	outputs: ((number) -> number)?,
})
	local live = liveContext(partial.notify)
	ctx = {
		notify = partial.notify,
		now = partial.now or os.clock,
		partsIn = partial.partsIn or defaultPartsIn,
		pieceOf = partial.pieceOf or live.pieceOf,
		planers = partial.planers or defaultPlaners,
		release = partial.release or GrabService.ReleasePiece,
		finish = partial.finish or live.finish,
		moved = partial.moved or function(_model: Model) end,
		online = partial.online or function(_userId: number): boolean
			return true
		end,
		outputs = partial.outputs or function(_userId: number): number
			return 0
		end,
	}
	table.clear(jobs)
	table.clear(firstSeen)
	table.clear(buckets)
end

return PlanerService
