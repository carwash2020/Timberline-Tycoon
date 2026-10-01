--!strict
-- TreeFX: everything a tree does on screen, drawn locally on every client
-- from the server's attributes, so everyone nearby sees it smoothly.
-- One animator per tree, so a wobble, a fall and a regrow never fight:
--   * Hit (HP drops): the tree wobbles around its base, wood chips fly and
--     a thunk plays (Shared/SoundData). Chips use no physics: each one arcs
--     along a TreeLogic flight to the ground under it (one raycast), rests
--     about a second and fades. They're pooled and capped.
--   * Fall (Felled = true): the tree leans away from the chopper, slowly
--     at first, then thumps down along FallDir (Shared/TreeLogic timing),
--     with a puff of dust in its biome's colour, leaves shaken out of its
--     canopy (pooled wedges in its palette that flutter down), a creak and
--     a crash, and a small camera shake for anyone close. Once down it
--     fades out (LocalTransparencyModifier, TreeLogic.FellFade: from
--     FallTime + 0.1 to + 0.4) into the logs the server lays, and the
--     server hides it.
--   * Regrow (Felled = false): the fade is undone and the tree springs
--     back up from sapling size. A standing tree that streams in is made
--     solid too, whatever this client last did to it.
-- The server never moves a tree, so everything here starts and ends on the
-- HomePivot attribute.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SoundData = require(ReplicatedStorage.Shared.SoundData)
local TreeArt = require(ReplicatedStorage.Shared.Art.TreeArt)
local TreeLogic = require(ReplicatedStorage.Shared.TreeLogic)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local CameraShake = require(script.Parent.CameraShake)

type WoodDef = WoodData.WoodDef

local TreeFX = {}

local FX_RANGE = 120 -- studs from the camera; farther trees aren't animated
local WOBBLE_DEGREES = { 2.6, -1.4, 0.6, 0 }
local WOBBLE_STEP = 0.05
local CHIP_COUNT = 6
local CHIP_CAP = 36 -- chips on screen at once; the oldest is reused past this
local CHIP_SPREAD = math.rad(70) -- either side of straight out of the cut
local GROUND_PROBE_UP = 6 -- a ground ray starts this far over the trunk's foot (or a leaf) ...
local GROUND_PROBE_DOWN = 14 -- ... and reaches this far down
local LEAF_COUNT = 10 -- leaves a landing tree shakes loose
local LEAF_CAP = 40
local LEAF_ROCK = math.rad(40) -- a falling leaf rocks this far either way ...
local LEAF_FLUTTER = 8 -- ... this fast (radians a second)
local LEAF_FLAT = CFrame.Angles(0, 0, math.pi / 2) -- a leaf wedge's thin X axis up: lying flat
local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local REGROW_TIME = 2.2

type State = {
	conns: { RBXScriptConnection },
	lastHp: number,
	token: number, -- bumps whenever a new animation takes over
	busy: boolean, -- falling or regrowing: hits don't wobble it
}

local states: { [Model]: State } = {}

-- Trees this client faded out after a fall, to bring back when they regrow
-- (weak keys: a destroyed tree just drops out, so attach doesn't rely on
-- this to make a tree that streams back in solid).
local faded: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- A chip (or leaf) in flight or lying on the ground.
type Piece = {
	part: BasePart,
	flight: TreeLogic.Flight,
	born: number, -- os.clock() when it spawned
	life: number, -- seconds until it has faded out
	rest: CFrame, -- its turn once it lies on the ground
	spinAxis: Vector3, -- it tumbles about this in the air ...
	spin: number, -- ... at this many radians a second, unwinding to `rest` as it lands
	rock: number, -- leaves: how far it rocks either way as it drifts down (0: chips)
}

-- Pieces of one kind: the parts waiting to be reused, the ones out now
-- (oldest first) and how many may be out at once.
type Batch = { idle: { BasePart }, out: { Piece }, cap: number, make: () -> BasePart }

local pieceFolder: Folder? = nil
local pieceConn: RBXScriptConnection? = nil
local batches: { Batch } = {}

local function newChipPart(): BasePart
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

local function newLeafPart(): BasePart
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

local chipBatch: Batch = { idle = {}, out = {}, cap = CHIP_CAP, make = newChipPart }
local leafBatch: Batch = { idle = {}, out = {}, cap = LEAF_CAP, make = newLeafPart }
table.insert(batches, chipBatch)
table.insert(batches, leafBatch)

local function folder(): Folder
	local f = pieceFolder
	if f and f.Parent then
		return f
	end
	local made = Instance.new("Folder")
	made.Name = "TreeFXPieces" -- client-only: nothing here replicates or streams
	made.Parent = workspace
	pieceFolder = made
	return made
end

local function release(batch: Batch, piece: Piece)
	piece.part.Parent = nil
	table.insert(batch.idle, piece.part)
end

-- Moves every piece along its flight; stops when none are left.
local function stepPieces()
	local now = os.clock()
	local any = false
	for _, batch in ipairs(batches) do
		local i = 1
		while i <= #batch.out do
			local piece = batch.out[i]
			local t = now - piece.born
			if piece.part.Parent == nil then
				table.remove(batch.out, i) -- destroyed under us: never reuse it
				continue
			elseif t >= piece.life then
				table.remove(batch.out, i)
				release(batch, piece)
				continue
			end
			local f = piece.flight
			local turn = piece.rest
			if t < f.landT then
				local left = f.landT - t
				turn = piece.rest * CFrame.fromAxisAngle(piece.spinAxis, piece.spin * left)
				if piece.rock > 0 then
					-- Rocks as it drifts, settling flat as it lands.
					turn *= CFrame.Angles(0, 0, piece.rock * math.sin(t * LEAF_FLUTTER) * math.min(1, left / 0.4))
				end
			end
			piece.part.CFrame = CFrame.new(TreeLogic.FlightAt(f, t)) * turn
			piece.part.Transparency = TreeLogic.FlightFade(f, t)
			any = true
			i += 1
		end
	end
	if not any then
		local conn = pieceConn
		if conn then
			conn:Disconnect()
			pieceConn = nil
		end
	end
end

-- A part for a new piece: an idle one, a new one, or (at the cap) the
-- oldest one out.
local function takePart(batch: Batch): BasePart
	if #batch.out >= batch.cap then
		local oldest = table.remove(batch.out, 1) :: Piece
		if oldest.part.Parent ~= nil then
			return oldest.part
		end
	end
	local idle = table.remove(batch.idle)
	return idle or batch.make()
end

local function launchPiece(
	batch: Batch,
	part: BasePart,
	flight: TreeLogic.Flight,
	rest: CFrame,
	spinAxis: Vector3,
	spin: number,
	rock: number
)
	local piece: Piece = {
		part = part,
		flight = flight,
		born = os.clock(),
		life = TreeLogic.FlightLife(flight),
		rest = rest,
		spinAxis = spinAxis,
		spin = spin,
		rock = rock,
	}
	part.Transparency = 0
	part.CFrame = CFrame.new(flight.origin) * rest
	part.Parent = folder()
	table.insert(batch.out, piece)
	if not pieceConn then
		pieceConn = RunService.Heartbeat:Connect(stepPieces)
	end
end

-- What the ground rays skip: the tree itself, people and trucks (only
-- colliding parts count, so leaves, logs and decoration are skipped too).
local function groundParams(tree: Model): RaycastParams
	local skip: { Instance } = { tree }
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char then
			table.insert(skip, char)
		end
	end
	for _, tag in ipairs({ "Truck", "NPC" }) do
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do
			table.insert(skip, inst)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = skip
	params.RespectCanCollide = true
	return params
end

-- The ground's height and normal under `at`, looking down from `fromY`
-- (or `fallbackY` and straight up if nothing is there yet).
local function groundAt(at: Vector3, fromY: number, fallbackY: number, params: RaycastParams): (number, Vector3)
	local hit = workspace:Raycast(
		Vector3.new(at.X, fromY + GROUND_PROBE_UP, at.Z),
		Vector3.new(0, -(GROUND_PROBE_UP + GROUND_PROBE_DOWN), 0),
		params
	)
	if hit then
		return hit.Position.Y, hit.Normal
	end
	return fallbackY, Vector3.yAxis
end

local function homeOf(tree: Model): CFrame?
	local home = tree:GetAttribute("HomePivot")
	return if typeof(home) == "CFrame" then home else nil
end

-- The trunk's length and its ground point, from the trunk cylinder (its X
-- axis runs up the trunk).
local function trunkInfo(tree: Model, home: CFrame): (number, Vector3)
	local trunk = tree.PrimaryPart
	local length = if trunk then trunk.Size.X else 8
	return length, home.Position - home.RightVector * (length / 2)
end

local function nearCamera(point: Vector3, range: number?): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - point).Magnitude <= (range or FX_RANGE)
end

-- Horizontal unit vector from the local player toward `point` (or +Z).
local function awayFromPlayer(point: Vector3): Vector3
	local char = Players.LocalPlayer.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if hrp then
		local v = Vector3.new(point.X - hrp.Position.X, 0, point.Z - hrp.Position.Z)
		if v.Magnitude > 0.1 then
			return v.Unit
		end
	end
	return Vector3.zAxis
end

local function wobble(tree: Model, state: State, home: CFrame)
	state.token += 1
	local token = state.token
	local _, base = trunkInfo(tree, home)
	local axis = Vector3.new(0, 1, 0):Cross(awayFromPlayer(base)) -- tips the top away from you
	task.spawn(function()
		for _, degrees in ipairs(WOBBLE_DEGREES) do
			if state.token ~= token or tree.Parent == nil then
				return
			end
			local tilt = CFrame.new(base) * CFrame.fromAxisAngle(axis, math.rad(degrees)) * CFrame.new(-base)
			tree:PivotTo(tilt * home)
			task.wait(WOBBLE_STEP)
		end
	end)
end

-- Chips fly out of the cut toward whoever swung, land around the trunk's
-- foot and lie there a moment.
local function chips(tree: Model, def: WoodDef, home: CFrame)
	local _, base = trunkInfo(tree, home)
	local trunk = tree.PrimaryPart
	local radius = if trunk then trunk.Size.Y / 2 else 1
	local toward = -awayFromPlayer(base)
	local origin = base + Vector3.new(0, 2.6, 0) + toward * (radius + 0.15)
	local inner = TreeArt.HeartColor(def)
	local params = groundParams(tree)
	for i = 1, CHIP_COUNT do
		local kind = TreeLogic.Chip
		-- Aim at the trunk's foot, then land on the ground where it comes down.
		local aim =
			TreeLogic.Launch(kind, origin, toward, CHIP_SPREAD, base.Y, math.random(), math.random(), math.random())
		local groundY, normal = groundAt(TreeLogic.FlightAt(aim, aim.landT), base.Y, base.Y, params)
		local flight = TreeLogic.Flight(kind, origin, aim.velocity, groundY)
		local chip = takePart(chipBatch)
		chip.Size = Vector3.new(0.25 + math.random() * 0.25, 0.14, 0.35 + math.random() * 0.3)
		chip.Color = if i % 3 == 0 then def.trunkColor else inner
		local rest = TreeLogic.Upright(normal) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
		local axis = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
		local spinAxis = if axis.Magnitude > 0.01 then axis.Unit else Vector3.xAxis
		launchPiece(chipBatch, chip, flight, rest, spinAxis, 10 + math.random() * 10, 0)
	end
end

-- Where a tree's canopy is right now (its leaf parts' centres): Leaves and
-- Frond parts and a pine's Tier models, as WindSway finds them.
local function canopySpots(tree: Model): { Vector3 }
	local spots: { Vector3 } = {}
	for _, d in ipairs(tree:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local parent = d.Parent
			local inTier = parent ~= nil and parent ~= tree and parent:IsA("Model") and parent.Name == "Tier"
			if d.Name == "Leaves" or d.Name == "Frond" or inTier then
				table.insert(spots, d.CFrame.Position)
			end
		end
	end
	return spots
end

-- Leaves shaken out of a landing tree's canopy: they burst up and flutter
-- down around it, in its palette.
local function shakeLeaves(tree: Model, def: WoodDef, groundY: number)
	local spots = canopySpots(tree)
	if #spots == 0 then
		return
	end
	local colors = TreeArt.Palette(def).leaves
	local params = groundParams(tree)
	for i = 1, LEAF_COUNT do
		local jitter = Vector3.new(math.random() - 0.5, math.random() * 0.5, math.random() - 0.5)
		local origin = spots[math.random(1, #spots)] + jitter
		local a = math.random() * math.pi * 2
		local kind = TreeLogic.Leaf
		local aim = TreeLogic.Launch(
			kind,
			origin,
			Vector3.new(math.cos(a), 0, math.sin(a)),
			0,
			groundY,
			math.random(),
			math.random(),
			0.5
		)
		local y, normal = groundAt(TreeLogic.FlightAt(aim, aim.landT), origin.Y, groundY, params)
		local flight = TreeLogic.Flight(kind, origin, aim.velocity, y)
		local leaf = takePart(leafBatch)
		leaf.Size = Vector3.new(0.08, 0.4 + math.random() * 0.2, 0.55 + math.random() * 0.25)
		leaf.Color = colors[(i - 1) % #colors + 1]
		local rest = TreeLogic.Upright(normal) * CFrame.Angles(0, math.random() * math.pi * 2, 0) * LEAF_FLAT
		-- Its thin X axis points up once it lies flat, so a turn about X spins it flat.
		launchPiece(leafBatch, leaf, flight, rest, Vector3.xAxis, (math.random() - 0.5) * 8, LEAF_ROCK)
	end
end

-- A burst of dust where the tree lands (and leaves, for leafy trees).
local function landingBurst(tree: Model, def: WoodDef, at: Vector3)
	local anchor = Instance.new("Part")
	anchor.Name = "FellBurst"
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Size = Vector3.new(6, 1, 6)
	anchor.CFrame = CFrame.new(at)
	anchor.Parent = workspace
	-- Soft smoke puffs (the default texture is a sparkle) in the colour of
	-- the ground it fell on.
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = DUST_TEXTURE
	dust.Color = ColorSequence.new(TreeArt.DustColor(def))
	dust.LightInfluence = 1
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.8, 1.6)
	dust.Speed = NumberRange.new(4, 10)
	dust.SpreadAngle = Vector2.new(80, 80)
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-40, 40)
	dust.Acceleration = Vector3.new(0, 2, 0)
	dust.Drag = 3
	dust.Rate = 0
	dust.Parent = anchor
	dust:Emit(20)
	Debris:AddItem(anchor, 3)
	if def.silhouette ~= "dead" then
		shakeLeaves(tree, def, at.Y)
	end
end

local function partsOf(tree: Model, visibleOnly: boolean): { BasePart }
	local out: { BasePart } = {}
	for _, d in ipairs(tree:GetDescendants()) do
		if d:IsA("BasePart") and (not visibleOnly or d.Transparency < 1) then
			table.insert(out, d)
		end
	end
	return out
end

local function setFade(parts: { BasePart }, alpha: number)
	for _, p in ipairs(parts) do
		p.LocalTransparencyModifier = alpha
	end
end

-- Undoes a fade, so a regrown tree (or one streamed back in) is solid.
local function unfade(tree: Model)
	faded[tree] = nil
	setFade(partsOf(tree, false), 0)
end

local function fall(tree: Model, def: WoodDef, state: State)
	local home = homeOf(tree)
	local dir = tree:GetAttribute("FallDir")
	local fellAt = tree:GetAttribute("FellAt")
	if not home or typeof(dir) ~= "Vector3" or type(fellAt) ~= "number" then
		return
	end
	local length, base = trunkInfo(tree, home)
	if not nearCamera(base) then
		return
	end
	local started = workspace:GetServerTimeNow() - fellAt
	if started > TreeLogic.FallTime then
		return -- streamed in after it already fell
	end
	state.token += 1
	state.busy = true
	local token = state.token
	local axis = Vector3.new(0, 1, 0):Cross(dir)
	SoundData.PlayAt("TreeCreak", base + Vector3.new(0, length / 2, 0))
	task.spawn(function()
		local landed = false
		local fading: { BasePart }? = nil
		local t = math.max(0, started)
		local stop = math.max(TreeLogic.FallTime + 0.05, TreeLogic.FellFadeStart + TreeLogic.FellFadeTime)
		while true do
			if state.token ~= token or tree.Parent == nil then
				return
			end
			local angle = TreeLogic.FallProgress(t) * TreeLogic.FallAngle
			tree:PivotTo(CFrame.new(base) * CFrame.fromAxisAngle(axis, angle) * CFrame.new(-base) * home)
			if not landed and t >= TreeLogic.FallTime * 0.86 then
				landed = true
				local tip = base + dir * (length * 0.85)
				landingBurst(tree, def, tip)
				SoundData.PlayAt("TreeFall", tip)
				if nearCamera(tip, 45) then
					CameraShake.Shake(0.45, 0.35)
				end
			end
			if t >= TreeLogic.FellFadeStart then
				-- Down: fade out into the logs the server is about to lay.
				local parts = fading or partsOf(tree, true)
				fading = parts
				faded[tree] = true
				setFade(parts, TreeLogic.FellFade(t))
			end
			if t >= stop then
				break
			end
			t += RunService.Heartbeat:Wait()
		end
	end)
end

local function regrow(tree: Model, state: State)
	unfade(tree) -- first, whatever happens next: a regrown tree is never left see-through
	local home = homeOf(tree)
	if not home then
		return
	end
	state.token += 1
	local token = state.token
	local length, base = trunkInfo(tree, home)
	tree:PivotTo(home)
	if not nearCamera(base) then
		state.busy = false
		return
	end
	state.busy = true
	local up = home.RightVector
	task.spawn(function()
		local t = 0
		while t < REGROW_TIME do
			if state.token ~= token or tree.Parent == nil then
				return
			end
			local x = t / REGROW_TIME
			-- Ease out with a little overshoot, like a spring.
			local s = 0.2 + 0.8 * (1 - (1 - x) ^ 3) + math.sin(x * math.pi) * 0.06
			tree:ScaleTo(math.max(0.05, s))
			tree:PivotTo(CFrame.new(base + up * (length * s / 2)) * home.Rotation)
			t += RunService.Heartbeat:Wait()
		end
		tree:ScaleTo(1)
		tree:PivotTo(home)
		state.busy = false
	end)
end

local function attach(tree: Model)
	if states[tree] then
		return
	end
	local def = WoodData.Get(tostring(tree:GetAttribute("WoodId")))
	if not def then
		return
	end
	local woodDef: WoodDef = def
	local state: State = {
		conns = {},
		lastHp = (tree:GetAttribute("HP") :: number?) or 0,
		token = 0,
		busy = false,
	}
	states[tree] = state
	if tree:GetAttribute("Felled") ~= true then
		-- Standing (so not mid-fall either): solid, always. It may have
		-- faded out before it streamed away and regrown since, and the weak
		-- `faded` set can have forgotten it by then.
		unfade(tree)
	end
	table.insert(
		state.conns,
		tree:GetAttributeChangedSignal("HP"):Connect(function()
			local hp = (tree:GetAttribute("HP") :: number?) or 0
			local prev = state.lastHp
			state.lastHp = hp
			if hp >= prev then
				return -- regrown
			end
			local home = homeOf(tree)
			if not home or not nearCamera(home.Position) then
				return
			end
			chips(tree, woodDef, home)
			local trunk = tree.PrimaryPart
			if trunk then
				SoundData.PlayAt(if hp > 0 then "Chop" else "ChopFinal", trunk.CFrame.Position)
			end
			if hp > 0 and not state.busy then
				wobble(tree, state, home)
			end
		end)
	)
	table.insert(
		state.conns,
		tree:GetAttributeChangedSignal("Felled"):Connect(function()
			if tree:GetAttribute("Felled") == true then
				fall(tree, woodDef, state)
			else
				regrow(tree, state)
			end
		end)
	)
end

local function detach(tree: Model)
	local state = states[tree]
	if state then
		state.token += 1
		for _, c in ipairs(state.conns) do
			c:Disconnect()
		end
	end
	states[tree] = nil
end

-- True while a tree is falling or regrowing (wind sway leaves it alone).
function TreeFX.IsBusy(tree: Model): boolean
	local state = states[tree]
	return state ~= nil and state.busy
end

function TreeFX.Start()
	for _, inst in ipairs(CollectionService:GetTagged("Tree")) do
		if inst:IsA("Model") then
			attach(inst)
		end
	end
	CollectionService:GetInstanceAddedSignal("Tree"):Connect(function(inst)
		if inst:IsA("Model") then
			attach(inst)
		end
	end)
	-- Fires when a tree streams out of range, too.
	CollectionService:GetInstanceRemovedSignal("Tree"):Connect(function(inst)
		if inst:IsA("Model") then
			detach(inst)
		end
	end)
end

return TreeFX
