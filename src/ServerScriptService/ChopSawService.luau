--!strict
-- ChopSawService: a placed chop saw cuts a rested log or plank to the
-- length on its panel (wave 2, B10). The server decides. A client only
-- asks to step that length (ChopSawSet: one stud of X, owner or someone
-- the plot lets interact, in range). This is the only ChopSawSet handler.
--
-- The blade guard is the only damage box. A hit is min(10, Health - 1),
-- a shove of about 12 studs, and at most one hit per player per second.
-- It never leaves a player at 0. A stopped saw (Run off) neither cuts nor
-- hits. Cut pieces keep the wood's owner and its kind.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChopSawLogic = require(ReplicatedStorage.Shared.ChopSawLogic)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local MachineArt = require(ReplicatedStorage.Shared.Art.MachineArt)
local RateLimiter = require(script.Parent.RateLimiter)
local SectionLogic = require(ReplicatedStorage.Shared.SectionLogic)

local ChopSawService = {}

type NodeRec = { parent: number?, children: { number } }

type Piece = {
	model: Model,
	root: BasePart,
	kind: string,
	woodId: string,
	parts: { [number]: BasePart },
	nodes: { [number]: NodeRec },
	ownerId: number,
	selling: boolean?,
	dead: boolean?,
}

type Body = {
	userId: number,
	health: () -> number,
	setHealth: (number) -> (),
	root: BasePart,
}

type Job = {
	piece: Piece,
	start: number,
	duration: number,
	cutStuds: number,
	ownerId: number,
	kind: string,
}

type Context = {
	notify: (Player, string) -> (),
	now: () -> number,
	partsIn: (BasePart) -> { BasePart },
	bodies: (BasePart) -> { Body },
	pieceOf: (BasePart) -> Piece?,
	saws: () -> { Model },
	split: (Piece, number, number) -> { Piece },
	mayUse: (Player, Model) -> boolean,
	-- Writes the length onto the owner's profile. `profile` is how a spec
	-- hands that profile in; the live game looks the owner up itself.
	save: (number, string, number) -> (),
	profile: ((number) -> any)?,
	byUserId: (number) -> Player?,
	near: (Player, Model) -> boolean,
}

local ctx: Context? = nil
local jobs: { [Model]: Job } = {}
local firstSeen: { [Model]: number } = {}
local warned: { [Model]: boolean } = {}
local lastHit: { [number]: number } = {}
local lastSet: { [number]: number } = {}
local running = false
local bound = false

local function unit(v: Vector3): Vector3
	if v.Magnitude < 1e-6 then
		return Vector3.zAxis
	end
	return v.Unit
end

local function findPart(model: Model, name: string): BasePart?
	local inst = model:FindFirstChild(name, true)
	if inst and inst:IsA("BasePart") then
		return inst
	end
	return nil
end

local function runFlag(model: Model): boolean?
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BoolValue") and d.Name == "Run" then
			return d.Value
		end
	end
	return nil
end

local function isRunning(model: Model): boolean
	return ChopSawLogic.IsRunning(model:GetAttribute("Run"), runFlag(model))
end

local function cutOf(model: Model): number
	local u = model:GetAttribute("CutU")
	return ChopSawLogic.Clamp(if type(u) == "number" then u else ChopSawLogic.DefaultCut)
end

local function longest(piece: Piece): (number?, number, number, number)
	local best: number? = nil
	local length = 0
	local sx, sz = 1, 1
	for id, part in pairs(piece.parts) do
		if part.Size.Y > length then
			best = id
			length = part.Size.Y
			sx = part.Size.X
			sz = part.Size.Z
		end
	end
	return best, length, sx, sz
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

local function outputCf(model: Model): CFrame
	local att = model:FindFirstChild("Output", true)
	if att and att:IsA("Attachment") then
		local parent = att.Parent
		if parent and parent:IsA("BasePart") then
			return parent.CFrame * att.CFrame
		end
	end
	return model:GetPivot()
end

local function shove(model: Model, piece: Piece)
	local out = outputCf(model)
	local look = unit(out.LookVector)
	local pos = out.Position + look * (piece.root.Size.Y / 2 + 1)
	local rot = piece.root.CFrame - piece.root.CFrame.Position
	for _, part in pairs(piece.parts) do
		part.Anchored = false
	end
	piece.root.Anchored = false
	piece.root.CFrame = CFrame.new(pos) * rot
	pcall(function()
		piece.root.AssemblyLinearVelocity = look * GameConfig.ConveyorSpeed
	end)
end

local function tell(userId: number, text: string)
	local c = ctx
	if not c or userId == 0 then
		return
	end
	local player = c.byUserId(userId)
	if player then
		c.notify(player, text)
	end
end

-- Dice `piece` at `cutStuds`. Every result keeps `ownerId` and `kind`
-- (the wood's, never a bystander's).
local function produce(c: Context, saw: Model, piece: Piece, cutStuds: number, ownerId: number, kind: string)
	local current = piece
	local guard = 0
	while guard < ChopSawLogic.MaxCut do
		guard += 1
		local sid, length, sx, sz = longest(current)
		if sid == nil or length <= cutStuds + 1e-3 then
			current.ownerId = ownerId
			current.kind = kind
			shove(saw, current)
			return
		end
		local remain = length - cutStuds
		if SectionLogic.IsChips(SectionLogic.Volume(sx, remain, sz)) then
			current.ownerId = ownerId
			current.kind = kind
			shove(saw, current)
			return
		end
		local results = c.split(current, sid, cutStuds)
		local nxt: Piece? = nil
		for _, part in ipairs(results) do
			part.ownerId = ownerId
			part.kind = kind
			local _, len = longest(part)
			if len > cutStuds + 1e-3 and nxt == nil then
				nxt = part
			else
				shove(saw, part)
			end
		end
		if nxt == nil then
			return
		end
		current = nxt
	end
end

local function splitsNeeded(piece: Piece, cutStuds: number): (number, number, number)
	local _, length, sx, sz = longest(piece)
	local n = 0
	local left = length
	while left > cutStuds + 1e-3 and n < ChopSawLogic.MaxCut do
		local remain = left - cutStuds
		if SectionLogic.IsChips(SectionLogic.Volume(sx, remain, sz)) then
			break
		end
		n += 1
		left = remain
	end
	return n, sx, sz
end

local function hurt(c: Context, saw: Model, now: number)
	if not isRunning(saw) then
		return
	end
	local guard = findPart(saw, "BladeGuard")
	if not guard or guard:GetAttribute("Damage") ~= true then
		return
	end
	for _, body in ipairs(c.bodies(guard)) do
		local health = body.health()
		local dmg = ChopSawLogic.Hurt(health)
		if dmg > 0 then
			local at = lastHit[body.userId]
			if not (at and now - at < ChopSawLogic.BladeHitGap) then
				lastHit[body.userId] = now
				body.setHealth(health - dmg)
				local pos = body.root.CFrame.Position
				local nextPos = ChopSawLogic.Push(pos, guard.CFrame.Position)
				local rot = body.root.CFrame - pos
				body.root.CFrame = CFrame.new(nextPos) * rot
			end
		end
	end
end

local function poll(c: Context, saw: Model, now: number)
	if jobs[saw] or not isRunning(saw) then
		return
	end
	local intake = findPart(saw, "Intake")
	if not intake then
		return
	end
	for _, part in ipairs(c.partsIn(intake)) do
		local piece = c.pieceOf(part)
		if piece and not piece.dead and not piece.selling then
			local refusal = ChopSawLogic.Refusal(piece.woodId)
			if refusal then
				if not warned[piece.model] then
					warned[piece.model] = true
					local ownerId = saw:GetAttribute("OwnerId")
					if type(ownerId) == "number" then
						tell(ownerId, refusal)
					end
				end
			elseif ChopSawLogic.AcceptsKind(piece.kind) then
				local seen = firstSeen[piece.model]
				if not seen then
					firstSeen[piece.model] = now
				elseif now - seen >= ChopSawLogic.Settle and speedOf(piece) <= ChopSawLogic.RestSpeed then
					local cutStuds = cutOf(saw) * GameConfig.WoodUnit
					local cuts, sx, sz = splitsNeeded(piece, cutStuds)
					local duration = ChopSawLogic.Seconds(piece.woodId, sx, sz, cuts)
					for _, p in pairs(piece.parts) do
						p.Anchored = true
					end
					jobs[saw] = {
						piece = piece,
						start = now,
						duration = duration,
						cutStuds = cutStuds,
						ownerId = piece.ownerId,
						kind = piece.kind,
					}
					return
				end
			end
		end
	end
end

local function finishDue(c: Context, now: number)
	local due: { Model } = {}
	for saw, job in pairs(jobs) do
		if now >= job.start + job.duration - 1e-9 then
			table.insert(due, saw)
		end
	end
	for _, saw in ipairs(due) do
		local job = jobs[saw]
		jobs[saw] = nil
		if job then
			firstSeen[job.piece.model] = nil
			produce(c, saw, job.piece, job.cutStuds, job.ownerId, job.kind)
		end
	end
end

function ChopSawService.Tick()
	local c = ctx
	if not c then
		return
	end
	local now = c.now()
	for _, saw in ipairs(c.saws()) do
		hurt(c, saw, now)
	end
	finishDue(c, now)
	for _, saw in ipairs(c.saws()) do
		poll(c, saw, now)
	end
end

local function defaultNear(player: Player, model: Model): boolean
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if not hrp or not hrp:IsA("BasePart") then
		return false
	end
	local fp = ChopSawLogic.Footprint()
	local reach = ChopSawLogic.PromptRange + math.max(fp.X, fp.Y) / 2 + GameConfig.RangeTolerance
	return (hrp.CFrame.Position - model:GetPivot().Position).Magnitude <= reach
end

local function defaultSaws(): { Model }
	local out: { Model } = {}
	for _, inst in ipairs(CollectionService:GetTagged("ChopSaw")) do
		if inst:IsA("Model") and inst.Parent then
			table.insert(out, inst)
		end
	end
	return out
end

-- ChopSawSet: one step of the length. "y" and anything that isn't ±1 are
-- ignored before the budget, so they don't spend it. A second accepted
-- shape inside SetGap changes nothing.
function ChopSawService.Set(player: Player, uid: unknown, axis: unknown, dir: unknown)
	local c = ctx
	if not c or type(uid) ~= "string" or axis ~= "x" or (dir ~= 1 and dir ~= -1) then
		return
	end
	if not RateLimiter.Allow(player, "ChopSawSet") then
		return
	end
	local model: Model? = nil
	for _, saw in ipairs(c.saws()) do
		if saw:GetAttribute("Uid") == uid then
			model = saw
			break
		end
	end
	if not model or not c.mayUse(player, model) or not c.near(player, model) then
		return
	end
	local now = c.now()
	local at = lastSet[player.UserId]
	if at and now - at < ChopSawLogic.SetGap then
		return
	end
	local nextCut = ChopSawLogic.Step(cutOf(model), "x", dir :: number)
	if nextCut == nil then
		return
	end
	lastSet[player.UserId] = now
	model:SetAttribute("CutU", nextCut)
	MachineArt.SetLength(model, nextCut)
	local ownerId = model:GetAttribute("OwnerId")
	if type(ownerId) == "number" then
		c.save(ownerId, uid, nextCut)
	end
end

local function liveMayUse(player: Player, model: Model): boolean
	local ownerId = model:GetAttribute("OwnerId")
	if type(ownerId) ~= "number" then
		return false
	end
	if player.UserId == ownerId then
		return true
	end
	local owner = Players:GetPlayerByUserId(ownerId)
	if not owner then
		return false
	end
	-- Lane F: the one edit-rights rule (PlotService.CanEdit's twin).
	local EditRights = require(script.Parent.EditRights)
	return EditRights.Can(player, owner, ChopSawLogic.UseFlag)
end

-- The owner's placed saw stores the length. Other placed items are left alone.
local function persist(profile: any, uid: string, cut: number)
	if type(profile) ~= "table" then
		return
	end
	local plot = profile.plot
	if type(plot) ~= "table" or type(plot.placed) ~= "table" then
		return
	end
	for _, item in ipairs(plot.placed) do
		if type(item) == "table" and item.uid == uid then
			item.data = { x = cut, y = 0 }
			return
		end
	end
end

local function liveSave(ownerId: number, uid: string, cut: number)
	local owner = Players:GetPlayerByUserId(ownerId)
	if not owner then
		return
	end
	local ProfileService = require(script.Parent.ProfileService)
	persist(ProfileService.GetProfile(owner), uid, cut)
end

local function liveContext(notifyFn: (Player, string) -> ()): Context
	return {
		notify = notifyFn,
		now = os.clock,
		partsIn = function(intake: BasePart): { BasePart }
			local WoodService = require(script.Parent.WoodService)
			local params = OverlapParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { WoodService.Folder() }
			return workspace:GetPartBoundsInBox(intake.CFrame, intake.Size, params)
		end,
		bodies = function(guard: BasePart): { Body }
			local out: { Body } = {}
			for _, player in ipairs(Players:GetPlayers()) do
				local char = player.Character
				local hrpInst = if char then char:FindFirstChild("HumanoidRootPart") else nil
				local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
				local hrp = if hrpInst and hrpInst:IsA("BasePart") then hrpInst else nil
				if hrp and hum and hum:IsA("Humanoid") and ChopSawLogic.Inside(guard, hrp.CFrame.Position) then
					local humanoid = hum
					table.insert(out, {
						userId = player.UserId,
						health = function(): number
							return humanoid.Health
						end,
						setHealth = function(n: number)
							humanoid.Health = n
						end,
						root = hrp,
					})
				end
			end
			return out
		end,
		pieceOf = function(part: BasePart): Piece?
			local WoodService = require(script.Parent.WoodService)
			return WoodService.FromPart(part) :: any
		end,
		saws = defaultSaws,
		split = function(piece: Piece, sid: number, h: number): { Piece }
			local WoodService = require(script.Parent.WoodService)
			local GrabService = require(script.Parent.GrabService)
			GrabService.ReleasePiece(piece.model, "cut")
			return WoodService.SplitPiece(piece :: any, sid, h) :: any
		end,
		mayUse = liveMayUse,
		save = liveSave,
		byUserId = function(userId: number): Player?
			return game:GetService("Players"):GetPlayerByUserId(userId)
		end,
		near = defaultNear,
	}
end

function ChopSawService.Init(notifyFn: (Player, string) -> (), remote: RemoteEvent)
	ctx = liveContext(notifyFn)
	table.clear(jobs)
	table.clear(firstSeen)
	table.clear(warned)
	table.clear(lastHit)
	table.clear(lastSet)
	if not bound then
		bound = true
		remote.OnServerEvent:Connect(function(player: Player, uid: unknown, axis: unknown, dir: unknown)
			ChopSawService.Set(player, uid, axis, dir)
		end)
		Players.PlayerRemoving:Connect(function(player: Player)
			ChopSawService.PlayerRemoving(player)
		end)
	end
	if running then
		return
	end
	running = true
	task.spawn(function()
		while running do
			task.wait(GameConfig.SellPollSec)
			local ok, err = pcall(function(): any
				ChopSawService.Tick()
				return nil
			end)
			if not ok then
				warn("[ChopSawService] tick failed: " .. tostring(err))
			end
		end
	end)
end

function ChopSawService.PlayerRemoving(player: Player)
	lastHit[player.UserId] = nil
	lastSet[player.UserId] = nil
end

function ChopSawService._reset()
	ctx = nil
	running = false
	bound = false
	table.clear(jobs)
	table.clear(firstSeen)
	table.clear(warned)
	table.clear(lastHit)
	table.clear(lastSet)
end

function ChopSawService._use(partial: {
	notify: (Player, string) -> (),
	now: (() -> number)?,
	partsIn: ((BasePart) -> { BasePart })?,
	bodies: ((BasePart) -> { Body })?,
	pieceOf: ((BasePart) -> Piece?)?,
	saws: (() -> { Model })?,
	split: ((Piece, number, number) -> { Piece })?,
	mayUse: ((Player, Model) -> boolean)?,
	save: ((number, string, number) -> ())?,
	profile: ((number) -> any)?,
	byUserId: ((number) -> Player?)?,
	near: ((Player, Model) -> boolean)?,
})
	ctx = {
		notify = partial.notify,
		now = partial.now or os.clock,
		partsIn = partial.partsIn or function(_intake: BasePart): { BasePart }
			return {}
		end,
		bodies = partial.bodies or function(_guard: BasePart): { Body }
			return {}
		end,
		pieceOf = partial.pieceOf or function(_part: BasePart): Piece?
			return nil
		end,
		saws = partial.saws or defaultSaws,
		split = partial.split or function(piece: Piece, _sid: number, _h: number): { Piece }
			return { piece }
		end,
		mayUse = partial.mayUse or function(player: Player, model: Model): boolean
			local ownerId = model:GetAttribute("OwnerId")
			if type(ownerId) ~= "number" then
				return false
			end
			return ChopSawLogic.MayUse(player.UserId, ownerId, nil)
		end,
		profile = partial.profile,
		save = partial.save or function(ownerId: number, uid: string, cut: number)
			local current = ctx
			if current and current.profile then
				persist(current.profile(ownerId), uid, cut)
			end
		end,
		byUserId = partial.byUserId or function(_userId: number): Player?
			return nil
		end,
		near = partial.near or defaultNear,
	}
	table.clear(jobs)
	table.clear(firstSeen)
	table.clear(warned)
	table.clear(lastHit)
	table.clear(lastSet)
end

return ChopSawService
