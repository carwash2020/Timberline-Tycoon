--!strict
-- WoodFX: what cutting and felling look like in the v2 core loop
-- (V2_PLAN.md §3e, §3f, §16, M1.3), drawn on every client from the
-- server's WorldFX and attributes. Under the v1 loop it does nothing
-- (TreeFX and TreeUI draw the v1 trees).
--   * A swing (WorldFX "Cut"): chips in the wood's core colour hop out of
--     the cut and lie a moment (pooled: QualityBudgets ChipCount), a thunk,
--     and for the one swinging a small ring at the cut that fills as the
--     cut goes through (the notch itself is the server's part, growing
--     on the face you hit). The ring fades a couple of seconds after the
--     last swing.
--   * A felling: the trunk falls by real physics (the server's); when it
--     lands ("Felled" {pos, mass}) the crash, a puff of dust, and the
--     camera shakes for anyone within ShakeRange if it's heavier than
--     ShakeMass. Its leaves come off LeafDropSec later ("LeafFall"): the
--     server drops the parts, and pooled leaves (LeafPool) flutter down
--     from where they were.
--   * Chips from an offcut too small to keep ("Chips"), a clink when the
--     axe can't dent the wood ("Clink"), and a "+$" that rises off the
--     sell pad for every piece sold ("Sold").
--   * Figured pieces (attribute Figure) wear a coloured band
--     (ForestArt.SectionBand), drawn here only: the server adds no parts.
--   * A tree that just grew (attribute GrewAt) springs up from smaller; a
--     dead one (Dead, DeadAt) sinks into the ground over DeadSinkSec and
--     fades. On the low quality tier leaf parts cast no shadow
--     (QualityBudgets LeafShadows).

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local QualityBudgets = require(ReplicatedStorage.Shared.QualityBudgets)
local Net = require(ReplicatedStorage.Shared.Net)
local SoundData = require(ReplicatedStorage.Shared.SoundData)
local TreeLogic = require(ReplicatedStorage.Shared.TreeLogic)
local Util = require(ReplicatedStorage.Shared.Util)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local ForestArt = require(ReplicatedStorage.Shared.Art.ForestArt)
local TreeArt = require(ReplicatedStorage.Shared.Art.TreeArt)
local CameraShake = require(script.Parent.CameraShake)
local Quality = require(script.Parent.Quality)

type WoodDef = WoodData.WoodDef

local WoodFX = {}

WoodFX.FxRange = 150 -- studs from the camera; farther effects aren't drawn
WoodFX.ShakeRange = 40 -- a landing shakes the camera this near ...
WoodFX.ShakeMass = 5 -- ... if it's heavier than this
WoodFX.ChipsPerHit = 5
WoodFX.ChipMin = 0.3 -- studs; the long side of a chip never starts under this
WoodFX.ChipsPerOffcut = 10
WoodFX.LeavesPerFall = 14
WoodFX.RingDots = 16
WoodFX.RingHold = 2.5 -- seconds the ring stays after the last swing
WoodFX.SpringFrom = 0.72 -- a tree that grew springs up from this much of its size
WoodFX.SpringTime = 0.9
WoodFX.SpringWindow = 1.5 -- seconds after GrewAt a tree still springs (it may stream in late)
WoodFX.BootWait = 120

local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local LEAF_FLAT = CFrame.Angles(0, 0, math.pi / 2)
local LEAF_ROCK = math.rad(40)
local LEAF_FLUTTER = 8
local RING_ON = Color3.fromRGB(255, 244, 214)
local RING_OFF = Color3.fromRGB(40, 30, 22)
local POP_COLOR = Color3.fromRGB(255, 226, 120)

local player = Players.LocalPlayer

local function nearCamera(point: Vector3, range: number?): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - point).Magnitude <= (range or WoodFX.FxRange)
end

-- The leaf colours of a wood (its v2 shape's, else today's palette).
function WoodFX.LeafColors(def: WoodDef): { Color3 }
	local shape = if def.v2 then def.v2.shape else nil
	if shape and #shape.leafColors > 0 then
		local out: { Color3 } = {}
		for i, h in ipairs(shape.leafColors) do
			out[i] = Color3.fromHex(h)
		end
		return out
	end
	return TreeArt.Palette(def).leaves
end

-- Whether a landing of `mass` at `distance` studs shakes the camera.
function WoodFX.Shakes(distance: number, mass: number): boolean
	return distance <= WoodFX.ShakeRange and mass > WoodFX.ShakeMass
end

-- How hard: heavier lands harder, at most a big shake.
function WoodFX.ShakeStrength(mass: number): number
	return math.clamp(0.25 + mass / 80, 0.25, 0.9)
end

-- How many of `dots` a ring lights for `progress` (0-1).
function WoodFX.RingLit(progress: number, dots: number?): number
	local n = dots or WoodFX.RingDots
	return math.clamp(math.floor(progress * n + 0.5), 0, n)
end

-- The spring's size at `x` (0-1 of SpringTime): from SpringFrom to 1 with
-- a little overshoot.
function WoodFX.SpringScale(x: number): number
	local u = math.clamp(x, 0, 1)
	local s = WoodFX.SpringFrom + (1 - WoodFX.SpringFrom) * (1 - (1 - u) ^ 3) + math.sin(u * math.pi) * 0.05
	return if u >= 1 then 1 else s
end

-- How far a dead tree has sunk `t` seconds after it died (0-1).
function WoodFX.SinkAt(t: number, sinkSec: number?): number
	local total = sinkSec or GameConfig.DeadSinkSec
	return math.clamp(t / math.max(0.05, total), 0, 1)
end

---------------------------------------------------------------------------
-- Pooled chips and leaves (no physics: each flies a TreeLogic flight)
---------------------------------------------------------------------------

type Piece = {
	part: BasePart,
	flight: TreeLogic.Flight,
	born: number,
	life: number,
	rest: CFrame,
	spinAxis: Vector3,
	spin: number,
	rock: number,
}
type Batch = { idle: { BasePart }, out: { Piece }, cap: () -> number, make: () -> BasePart }

local fxFolder: Folder? = nil
local stepConn: RBXScriptConnection? = nil
local batches: { Batch } = {}

local function folder(): Folder
	local f = fxFolder
	if f and f.Parent then
		return f
	end
	local made = Instance.new("Folder")
	made.Name = "WoodFX" -- client-only: nothing here replicates
	made.Parent = workspace
	fxFolder = made
	return made
end

local function newChip(): BasePart
	local chip = Instance.new("Part")
	chip.Name = "WoodChip"
	chip.Material = Enum.Material.Wood
	chip.Anchored = true
	chip.CanCollide = false
	chip.CanQuery = false
	chip.CanTouch = false
	chip.CastShadow = false
	return chip
end

local function newLeaf(): BasePart
	local leaf = Instance.new("WedgePart")
	leaf.Name = "FallingLeaf"
	leaf.Material = Enum.Material.SmoothPlastic
	leaf.Anchored = true
	leaf.CanCollide = false
	leaf.CanQuery = false
	leaf.CanTouch = false
	leaf.CastShadow = false
	return leaf
end

local chipBatch: Batch = {
	idle = {},
	out = {},
	cap = function(): number
		return Quality.Budget().ChipCount
	end,
	make = newChip,
}
local leafBatch: Batch = {
	idle = {},
	out = {},
	cap = function(): number
		return Quality.Budget().LeafPool
	end,
	make = newLeaf,
}
table.insert(batches, chipBatch)
table.insert(batches, leafBatch)

local sincePieces = 0
local function stepPieces(dt: number?)
	sincePieces += if type(dt) == "number" then dt else 0
	if not QualityBudgets.CosmeticDue(Quality.Budget().CosmeticHz, sincePieces) then
		return
	end
	sincePieces = 0
	local now = os.clock()
	local any = false
	for _, batch in ipairs(batches) do
		local i = 1
		while i <= #batch.out do
			local piece = batch.out[i]
			local t = now - piece.born
			if piece.part.Parent == nil and t > 0 then
				table.remove(batch.out, i)
				continue
			elseif t >= piece.life then
				table.remove(batch.out, i)
				piece.part.Parent = nil
				table.insert(batch.idle, piece.part)
				continue
			end
			local f = piece.flight
			local turn = piece.rest
			if t < f.landT then
				local left = f.landT - t
				turn = piece.rest * CFrame.fromAxisAngle(piece.spinAxis, piece.spin * left)
				if piece.rock > 0 then
					turn *= CFrame.Angles(0, 0, piece.rock * math.sin(t * LEAF_FLUTTER) * math.min(1, left / 0.4))
				end
			end
			piece.part.CFrame = CFrame.new(TreeLogic.FlightAt(f, t)) * turn
			piece.part.Transparency = TreeLogic.FlightFade(f, t)
			any = true
			i += 1
		end
	end
	if not any and stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
end

local function takePart(batch: Batch): BasePart
	if #batch.out >= batch.cap() then
		local oldest = table.remove(batch.out, 1) :: Piece
		if oldest.part.Parent ~= nil then
			return oldest.part
		end
	end
	return table.remove(batch.idle) or batch.make()
end

local function launch(
	batch: Batch,
	part: BasePart,
	flight: TreeLogic.Flight,
	rest: CFrame,
	axis: Vector3,
	spin: number,
	rock: number
)
	part.Transparency = 0
	part.CFrame = CFrame.new(flight.origin) * rest
	part.Parent = folder()
	table.insert(batch.out, {
		part = part,
		flight = flight,
		born = os.clock(),
		life = TreeLogic.FlightLife(flight),
		rest = rest,
		spinAxis = axis,
		spin = spin,
		rock = rock,
	})
	if not stepConn then
		stepConn = RunService.Heartbeat:Connect(stepPieces)
	end
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

-- The ground under `at`, looking down from just above it.
local function groundAt(at: Vector3): (number, Vector3)
	local skip: { Instance } = { folder() }
	local char = player.Character
	if char then
		table.insert(skip, char)
	end
	groundParams.FilterDescendantsInstances = skip
	local hit = workspace:Raycast(at + Vector3.new(0, 2, 0), Vector3.new(0, -40, 0), groundParams)
	if hit then
		return hit.Position.Y, hit.Normal
	end
	return at.Y - 3, Vector3.yAxis
end

local function randomAxis(): Vector3
	local v = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	return if v.Magnitude > 0.01 then v.Unit else Vector3.xAxis
end

-- `n` chips out of `pos` along `normal`, in the wood's core (and a few in
-- its bark) colour.
local function chips(def: WoodDef, pos: Vector3, normal: Vector3, n: number)
	if not nearCamera(pos) then
		return
	end
	local core = TreeArt.Core(def)
	local bark = def.trunkColor
	local flat = Vector3.new(normal.X, 0, normal.Z)
	local toward = if flat.Magnitude > 0.05 then flat.Unit else Vector3.xAxis
	local groundY, groundNormal = groundAt(pos)
	local origin = pos + normal * 0.15
	for i = 1, n do
		local flight = TreeLogic.Launch(
			TreeLogic.Chip,
			origin,
			toward,
			math.rad(70),
			groundY,
			math.random(),
			math.random(),
			math.random()
		)
		local chip = takePart(chipBatch)
		chip.Size = Vector3.new(WoodFX.ChipMin + math.random() * 0.16, 0.16, WoodFX.ChipMin + math.random() * 0.22)
		chip.Color = if i % 4 == 0 then bark else core
		local rest = TreeLogic.Upright(groundNormal) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
		launch(chipBatch, chip, flight, rest, randomAxis(), 10 + math.random() * 10, 0)
	end
end

-- Leaves flutter down from `points` in the wood's colours.
local function leaves(def: WoodDef, points: { Vector3 })
	if #points == 0 or not nearCamera(points[1]) then
		return
	end
	local colors = WoodFX.LeafColors(def)
	local grounds: { [number]: number } = {}
	local normals: { [number]: Vector3 } = {}
	for i = 1, WoodFX.LeavesPerFall do
		local k = (i - 1) % #points + 1
		if not grounds[k] then
			grounds[k], normals[k] = groundAt(points[k])
		end
		local origin = points[k] + Vector3.new(math.random() - 0.5, math.random() * 0.6, math.random() - 0.5) * 2
		local a = math.random() * math.pi * 2
		local flight = TreeLogic.Launch(
			TreeLogic.Leaf,
			origin,
			Vector3.new(math.cos(a), 0, math.sin(a)),
			0,
			grounds[k],
			math.random(),
			math.random(),
			0.5
		)
		local leaf = takePart(leafBatch)
		leaf.Size = Vector3.new(0.08, 0.45 + math.random() * 0.25, 0.6 + math.random() * 0.3)
		leaf.Color = colors[(i - 1) % #colors + 1]
		local rest = TreeLogic.Upright(normals[k]) * CFrame.Angles(0, math.random() * math.pi * 2, 0) * LEAF_FLAT
		launch(leafBatch, leaf, flight, rest, Vector3.xAxis, (math.random() - 0.5) * 8, LEAF_ROCK)
	end
end

-- Dust where a felled piece lands, in its home biome's ground colour.
local function dust(def: WoodDef, at: Vector3, mass: number)
	local anchor = Instance.new("Part")
	anchor.Name = "FellDust"
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Size = Vector3.new(6, 1, 6)
	anchor.CFrame = CFrame.new(at)
	anchor.Parent = folder()
	local puff = Instance.new("ParticleEmitter")
	puff.Texture = DUST_TEXTURE
	puff.Color = ColorSequence.new(TreeArt.DustColor(def))
	puff.LightInfluence = 1
	puff.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
	puff.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	puff.Lifetime = NumberRange.new(0.8, 1.6)
	puff.Speed = NumberRange.new(4, 10)
	puff.SpreadAngle = Vector2.new(80, 80)
	puff.Rotation = NumberRange.new(0, 360)
	puff.RotSpeed = NumberRange.new(-40, 40)
	puff.Acceleration = Vector3.new(0, 2, 0)
	puff.Drag = 3
	puff.Rate = 0
	puff.Parent = anchor
	puff:Emit(math.clamp(math.floor(8 + mass / 2), 8, 30))
	Debris:AddItem(anchor, 3)
end

---------------------------------------------------------------------------
-- The cut's ring
---------------------------------------------------------------------------

type Ring = { gui: BillboardGui, dots: { Frame }, anchor: Attachment?, lastAt: number }
local ring: Ring? = nil

local function makeRing(): Ring
	local gui = Instance.new("BillboardGui")
	gui.Name = "CutRing"
	gui.Size = UDim2.fromOffset(54, 54)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 60
	gui.ResetOnSpawn = false
	gui.Enabled = false
	local dots: { Frame } = {}
	for i = 1, WoodFX.RingDots do
		local a = (i - 1) / WoodFX.RingDots * math.pi * 2 - math.pi / 2
		local dot = Instance.new("Frame")
		dot.Name = "Dot" .. i
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Size = UDim2.fromOffset(7, 7)
		dot.Position = UDim2.new(0.5, math.cos(a) * 20, 0.5, math.sin(a) * 20)
		dot.BorderSizePixel = 0
		dot.BackgroundColor3 = RING_OFF
		dot.BackgroundTransparency = 0.35
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = dot
		dot.Parent = gui
		dots[i] = dot
	end
	gui.Parent = player:FindFirstChildOfClass("PlayerGui")
	return { gui = gui, dots = dots, anchor = nil, lastAt = 0 }
end

local function showRing(part: BasePart, pos: Vector3, progress: number, through: boolean)
	local r = ring or makeRing()
	ring = r
	if through then
		r.gui.Enabled = false
		return
	end
	local old = r.anchor
	if not old or old.Parent ~= part then
		if old then
			old:Destroy()
		end
		local anchor = Instance.new("Attachment")
		anchor.Name = "CutRingAt"
		anchor.Parent = part
		r.anchor = anchor
	end
	local anchor = r.anchor :: Attachment
	anchor.WorldPosition = pos
	r.gui.Adornee = anchor
	local lit = WoodFX.RingLit(progress)
	for i, dot in ipairs(r.dots) do
		local on = i <= lit
		dot.BackgroundColor3 = if on then RING_ON else RING_OFF
		dot.BackgroundTransparency = if on then 0 else 0.35
	end
	r.gui.Enabled = true
	r.lastAt = os.clock()
end

local function hideRingIfIdle()
	local r = ring
	if r and r.gui.Enabled and os.clock() - r.lastAt > WoodFX.RingHold then
		r.gui.Enabled = false
	end
end

---------------------------------------------------------------------------
-- "+$" off the sell pad
---------------------------------------------------------------------------

local function moneyPop(pos: Vector3, amount: number)
	if not nearCamera(pos, 200) then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = "SoldPop"
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(pos + Vector3.new(0, 2, 0))
	anchor.Parent = folder()
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 44)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 200
	gui.Adornee = anchor
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = POP_COLOR
	label.TextStrokeTransparency = 0.2
	label.Text = "+" .. Util.formatCash(amount)
	label.Parent = gui
	TweenService:Create(gui, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = Vector3.new(0, 5, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	SoundData.PlayAt("Sell", pos)
	Debris:AddItem(anchor, 1.6)
end

---------------------------------------------------------------------------
-- WorldFX
---------------------------------------------------------------------------

local function woodOf(payload: { [string]: any }): WoodDef?
	local id = payload.woodId
	return if type(id) == "string" then WoodData.Get(id) else nil
end

local function onWorldFX(kind: string, payload: any)
	if type(payload) ~= "table" then
		return
	end
	if kind == "Cut" then
		local def, pos, normal = woodOf(payload), payload.pos, payload.normal
		if not def or typeof(pos) ~= "Vector3" or typeof(normal) ~= "Vector3" then
			return
		end
		chips(def, pos, normal, WoodFX.ChipsPerHit)
		SoundData.PlayAt(if payload.through == true then "ChopFinal" else "Chop", pos)
		local part = payload.part
		if payload.userId == player.UserId and typeof(part) == "Instance" and part:IsA("BasePart") then
			local progress = if type(payload.progress) == "number" then payload.progress else 0
			showRing(part, pos, progress, payload.through == true)
		end
	elseif kind == "LeafFall" then
		local def = woodOf(payload)
		local raw = payload.points
		if not def or type(raw) ~= "table" then
			return
		end
		local points: { Vector3 } = {}
		for _, p in ipairs(raw) do
			if typeof(p) == "Vector3" then
				table.insert(points, p)
			end
		end
		leaves(def, points)
	elseif kind == "Felled" then
		local def, pos, mass = woodOf(payload), payload.pos, payload.mass
		if not def or typeof(pos) ~= "Vector3" or type(mass) ~= "number" then
			return
		end
		SoundData.PlayAt("TreeFall", pos)
		if nearCamera(pos) then
			dust(def, pos, mass)
		end
		local camera = workspace.CurrentCamera
		local char = player.Character
		local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
		local from = if hrp and hrp:IsA("BasePart") then hrp.Position elseif camera then camera.CFrame.Position else nil
		if from and WoodFX.Shakes((from - pos).Magnitude, mass) then
			CameraShake.Shake(WoodFX.ShakeStrength(mass), 0.4)
		end
	elseif kind == "Chips" then
		local def, pos = woodOf(payload), payload.pos
		if def and typeof(pos) == "Vector3" then
			chips(def, pos, Vector3.yAxis, WoodFX.ChipsPerOffcut)
		end
	elseif kind == "Clink" then
		local pos = payload.pos
		if typeof(pos) == "Vector3" then
			SoundData.PlayAt("ChopTooHard", pos)
		end
	elseif kind == "Sold" then
		local pos, amount = payload.pos, payload.amount
		if typeof(pos) == "Vector3" and type(amount) == "number" and amount > 0 then
			moneyPop(pos, amount)
		end
	end
end

---------------------------------------------------------------------------
-- Trees: the spring, the sink, the low tier's shadows
---------------------------------------------------------------------------

type Sink = { tree: Model, home: CFrame, depth: number, deadAt: number, parts: { BasePart } }
local sinks: { [Model]: Sink } = {}
local sinkConn: RBXScriptConnection? = nil
local springing: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local LEAF_NAMES: { [string]: boolean } = { Leaves = true, Frond = true, Facet = true }

local sinceSinks = 0
local function stepSinks(dt: number?)
	sinceSinks += if type(dt) == "number" then dt else 0
	if not QualityBudgets.CosmeticDue(Quality.Budget().CosmeticHz, sinceSinks) then
		return
	end
	sinceSinks = 0
	local now = workspace:GetServerTimeNow()
	local any = false
	for tree, s in pairs(sinks) do
		if tree.Parent == nil then
			sinks[tree] = nil
			continue
		end
		any = true
		local u = WoodFX.SinkAt(now - s.deadAt)
		tree:PivotTo(s.home - Vector3.new(0, s.depth * u, 0))
		for _, p in ipairs(s.parts) do
			if p.Parent then
				p.LocalTransparencyModifier = u
			end
		end
	end
	if not any and sinkConn then
		sinkConn:Disconnect()
		sinkConn = nil
	end
end

local function startSink(tree: Model)
	if sinks[tree] then
		return
	end
	local deadAt = tree:GetAttribute("DeadAt")
	local _, size = tree:GetBoundingBox()
	local parts: { BasePart } = {}
	for _, d in ipairs(tree:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	sinks[tree] = {
		tree = tree,
		home = tree:GetPivot(),
		depth = size.Y + 1,
		deadAt = if type(deadAt) == "number" then deadAt else workspace:GetServerTimeNow(),
		parts = parts,
	}
	if not sinkConn then
		sinkConn = RunService.Heartbeat:Connect(stepSinks)
	end
end

-- A tree that just grew springs up from smaller, its foot staying put.
local function spring(tree: Model)
	local root = tree.PrimaryPart
	if not root or springing[tree] then
		return
	end
	springing[tree] = true
	local home = tree:GetPivot()
	local half = root.Size.Y / 2
	local foot = home * CFrame.new(0, -half, 0)
	task.spawn(function()
		local t = 0
		while t < WoodFX.SpringTime do
			if tree.Parent == nil or tree:GetAttribute("Felled") == true then
				break
			end
			local s = WoodFX.SpringScale(t / WoodFX.SpringTime)
			tree:ScaleTo(s)
			tree:PivotTo(foot * CFrame.new(0, half * s, 0))
			t += RunService.Heartbeat:Wait()
		end
		if tree.Parent then
			tree:ScaleTo(1)
			tree:PivotTo(home)
		end
		springing[tree] = nil
	end)
end

local function watchTree(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local tree = inst
	if not Quality.Budget().LeafShadows then
		for _, d in ipairs(tree:GetDescendants()) do
			if d:IsA("BasePart") and LEAF_NAMES[d.Name] then
				d.CastShadow = false
			end
		end
	end
	if tree:GetAttribute("Dead") == true then
		startSink(tree)
	else
		local grewAt = tree:GetAttribute("GrewAt")
		local home = tree:GetAttribute("HomePivot")
		if
			type(grewAt) == "number"
			and workspace:GetServerTimeNow() - grewAt <= WoodFX.SpringWindow
			and typeof(home) == "CFrame"
			and nearCamera(home.Position)
		then
			spring(tree)
		end
	end
	tree:GetAttributeChangedSignal("Dead"):Connect(function()
		if tree:GetAttribute("Dead") == true then
			startSink(tree)
		end
	end)
end

---------------------------------------------------------------------------
-- Figured pieces' bands
---------------------------------------------------------------------------

local function refreshBand(piece: Model)
	local root = piece.PrimaryPart
	if not root then
		return
	end
	local figure = piece:GetAttribute("Figure")
	local band = root:FindFirstChild("FigureBand")
	if type(figure) == "string" and figure ~= "" then
		if not band or band:GetAttribute("Figure") ~= figure then
			ForestArt.SectionBand(root, figure)
		end
	elseif band then
		band:Destroy()
	end
end

local function watchPiece(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local piece = inst
	refreshBand(piece)
	piece:GetAttributeChangedSignal("Figure"):Connect(function()
		refreshBand(piece)
	end)
	-- A split can hand the piece a new root: the band follows.
	piece:GetPropertyChangedSignal("PrimaryPart"):Connect(function()
		refreshBand(piece)
	end)
end

function WoodFX.Start()
	-- MapBuilder says which loop runs before it builds anything.
	local waited = 0
	while workspace:GetAttribute(CoreLoop.ActiveAttribute) == nil and waited < WoodFX.BootWait do
		waited += task.wait(0.25)
	end
	if not CoreLoop.V2() then
		return -- the v1 loop: TreeFX draws the trees
	end
	Net.Remote("WorldFX").OnClientEvent:Connect(function(kind: unknown, payload: unknown)
		if type(kind) == "string" then
			onWorldFX(kind, payload)
		end
	end)
	for _, inst in ipairs(CollectionService:GetTagged("Tree")) do
		watchTree(inst)
	end
	CollectionService:GetInstanceAddedSignal("Tree"):Connect(watchTree)
	for _, inst in ipairs(CollectionService:GetTagged("Wood")) do
		watchPiece(inst)
	end
	CollectionService:GetInstanceAddedSignal("Wood"):Connect(watchPiece)
	local since = 0
	local sinceCosmetic = 0
	RunService.Heartbeat:Connect(function(dt: number)
		sinceCosmetic += dt
		if not QualityBudgets.CosmeticDue(Quality.Budget().CosmeticHz, sinceCosmetic) then
			return
		end
		local step = sinceCosmetic
		sinceCosmetic = 0
		since += step
		if since >= 0.25 then
			since = 0
			hideRingIfIdle()
		end
	end)
end

return WoodFX
