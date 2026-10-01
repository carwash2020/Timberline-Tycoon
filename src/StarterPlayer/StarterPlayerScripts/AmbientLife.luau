--!strict
-- AmbientLife: the world never looks empty (REDESIGN.md "an active
-- environment"; GAME_DESIGN §16 "thriving groves come alive"). All of it
-- is built on this client only, around the player, and never collides.
--
-- 1. Ground decoration. The map is cut into 64-stud cells; each cell's
--    flowers, bushes, rocks, mushrooms and crystals come from
--    EnvironmentData.DecorSpots (deterministic, so every player sees the
--    same meadow), placed on TerrainGen's ground without raycasts, never
--    on roads, water, town or the plots, nor within 4 studs of a tree.
--    Cells load within ~200 studs and unload past ~260, a couple per
--    frame; models are pooled and the live count is capped. Thriving
--    groves (workspace "Vitality_<biome>") grow more flowers: when a
--    grove changes tier, its cells re-scatter.
-- 2. Critters (Shared/Art/CritterArt), at most EnvironmentData.MaxCritters
--    animated models at once, chosen by EnvironmentData.CritterPlan:
--    flocks circling over the woods that scatter when you come close,
--    songbirds pecking that fly off, butterflies by day near flowers,
--    fireflies at night, rabbits and deer that bound away, ducks on the
--    starter pond, fish leaping in the river and lake, wisps in the
--    Phantom Grove at night, ember sprites at the Volcano. One BulkMoveTo
--    a frame moves them all.
-- 3. Golden motes around the Skyroot, pouring off its crown during a
--    Skyroot Bloom (workspace "SkyrootBloom").

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CritterArt = require(ReplicatedStorage.Shared.Art.CritterArt)
local EnvironmentData = require(ReplicatedStorage.Shared.EnvironmentData)
local PropArt = require(ReplicatedStorage.Shared.Art.PropArt)
local SoundData = require(ReplicatedStorage.Shared.SoundData)
local TerrainGen = require(ReplicatedStorage.Shared.World.TerrainGen)
local WorldLayout = require(ReplicatedStorage.Shared.World.WorldLayout)
local WorldPlan = require(ReplicatedStorage.Shared.World.WorldPlan)
local LightingController = require(script.Parent.LightingController)

type Environment = LightingController.Environment
type DecorKind = EnvironmentData.DecorKind
type DecorSpot = EnvironmentData.DecorSpot

local AmbientLife = {}

local TAU = math.pi * 2

local folder: Folder? = nil
local function root(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local made = Instance.new("Folder")
	made.Name = "AmbientLife"
	made.Parent = workspace
	folder = made
	return made
end

-- Where the player is (their character, else the camera).
local function focusPoint(): Vector3
	local player = Players.LocalPlayer
	local char = if player then player.Character else nil
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if hrp and hrp:IsA("BasePart") then
		return hrp.Position
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.Focus.Position else Vector3.zero
end

local function vitalityOf(biomeId: string): number
	local v = workspace:GetAttribute("Vitality_" .. biomeId)
	return if type(v) == "number" then v else EnvironmentData.DefaultVitality
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

---------------------------------------------------------------------------
-- 1. Ground decoration
---------------------------------------------------------------------------

local CELL = EnvironmentData.DecorCell
local LOAD_RADIUS = 200
local UNLOAD_RADIUS = 260
local MAX_DECOR = 420 -- live decoration models, all cells together
local TREE_CLEARANCE = 4
local CELLS_PER_FRAME = 2
local SCAN_EVERY = 0.4
local POOL_SPARE = 24 -- unused models kept per look

-- One pooled decoration model: its parts and where they sit around its
-- origin, so placing it is one CFrame per part.
type Decor = { model: Model, parts: { BasePart }, locals: { CFrame }, key: string }

type Cell = {
	key: string,
	cx: number,
	cz: number,
	items: { Decor },
	biomes: { [string]: boolean }, -- groves whose vitality shaped it
}

local function paletteOf(row: DecorKind): { Color3 }
	local p = if row.palette then EnvironmentData.DecorPalettes[row.palette] else nil
	return p or EnvironmentData.DecorPalettes.stone
end

local function sizeOf(row: DecorKind, variant: number): number
	local size = row.size
	if not size then
		return 1
	end
	local t = if row.variants > 1 then (variant - 1) / (row.variants - 1) else 0.5
	return size[1] + (size[2] - size[1]) * t
end

-- How to build each decoration kind from PropArt. `biome` is the Decor
-- table the spot came from ("meadow" and "shore" take the Starter Forest's
-- tints); PropArt.Tints gives each biome its grass, leaf, bark and moss.
type Builder = (row: DecorKind, variant: number, seed: number, biome: string) -> Model
local function tints(biome: string): PropArt.Tints
	return PropArt.Tints(if biome == "meadow" or biome == "shore" then "starter" else biome)
end
local BUILDERS: { [string]: Builder } = {
	Flowers = function(row, _variant, seed)
		return PropArt.Flowers(seed, paletteOf(row))
	end,
	Bush = function(row, variant, seed)
		return PropArt.Bush(sizeOf(row, variant), seed, paletteOf(row))
	end,
	Rock = function(row, variant, seed)
		return PropArt.Rock(sizeOf(row, variant), seed, paletteOf(row))
	end,
	Mushroom = function(row, _variant, seed)
		return PropArt.Mushroom(seed, row.glowing == true)
	end,
	Crystal = function(row, variant, seed)
		return PropArt.Crystal(seed, paletteOf(row)[1], sizeOf(row, variant))
	end,
	GrassTuft = function(_row, _variant, seed, biome)
		return PropArt.GrassTuft(seed, tints(biome).grass)
	end,
	Fern = function(_row, _variant, seed, biome)
		return PropArt.Fern(seed, tints(biome).grass)
	end,
	Pebbles = function(_row, _variant, seed, biome)
		return PropArt.Pebbles(seed, tints(biome).stone)
	end,
	BerryBush = function(_row, _variant, seed)
		return PropArt.BerryBush(seed)
	end,
	FallenLog = function(_row, _variant, seed, biome)
		local t = tints(biome)
		return PropArt.FallenLog(seed, t.bark, t.moss)
	end,
	Stump = function(_row, _variant, seed, biome)
		local t = tints(biome)
		return PropArt.Stump(seed, t.bark, t.moss)
	end,
	DeadBranch = function(_row, _variant, seed)
		return PropArt.DeadBranch(seed)
	end,
	SnowPile = function(row, variant, seed)
		return PropArt.SnowPile(seed, sizeOf(row, variant))
	end,
	LavaRock = function(row, variant, seed)
		return PropArt.LavaRock(seed, sizeOf(row, variant))
	end,
	Reeds = function(_row, _variant, seed)
		return PropArt.Reeds(seed)
	end,
	Cattails = function(_row, _variant, seed)
		return PropArt.Cattails(seed)
	end,
	LilyPad = function(_row, _variant, seed)
		return PropArt.LilyPad(seed)
	end,
}

local decorPools: { [string]: { Decor } } = {}
local liveDecor = 0

local function seedOf(biome: string, index: number, variant: number): number
	local h = 17
	for i = 1, #biome do
		h = (h * 31 + string.byte(biome, i)) % 99991
	end
	return h * 13 + index * 101 + variant * 7
end

local function buildDecor(spot: DecorSpot, key: string): Decor?
	local rows = EnvironmentData.Decor[spot.biome]
	local row = if rows then rows[spot.index] else nil
	local builder = if row then BUILDERS[row.kind] else nil
	if not row or not builder then
		return nil
	end
	local model = builder(row, spot.variant, seedOf(spot.biome, spot.index, spot.variant), spot.biome)
	local parts: { BasePart } = {}
	local locals: { CFrame } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			-- Client decoration never collides (even PropArt's climbable rocks).
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = d.Size.Magnitude > 4
			table.insert(parts, d)
			table.insert(locals, d.CFrame) -- built around the origin
		end
	end
	return { model = model, parts = parts, locals = locals, key = key }
end

local function acquireDecor(spot: DecorSpot): Decor?
	local key = string.format("%s/%d/%d", spot.biome, spot.index, spot.variant)
	local pool = decorPools[key]
	local d = if pool then table.remove(pool) else nil
	if not d then
		d = buildDecor(spot, key)
	end
	return d
end

local function releaseDecor(d: Decor)
	d.model.Parent = nil
	local pool = decorPools[d.key]
	if not pool then
		pool = {}
		decorPools[d.key] = pool
	end
	if #pool < POOL_SPARE then
		table.insert(pool, d)
	else
		d.model:Destroy()
	end
end

-- Trees, binned by 16 studs, so a spot can check its neighbours cheaply.
local TREE_BIN = 16
local treeBins: { [string]: { [Instance]: Vector3 } } = {}
local treeAt: { [Instance]: string } = {} -- tree -> its bin key

local function binKey(x: number, z: number): string
	return string.format("%d,%d", x // TREE_BIN, z // TREE_BIN)
end

local function nearTree(x: number, z: number): boolean
	local bx, bz = x // TREE_BIN, z // TREE_BIN
	for dx = -1, 1 do
		for dz = -1, 1 do
			local bin = treeBins[string.format("%d,%d", bx + dx, bz + dz)]
			if bin then
				for _, p in pairs(bin) do
					local ddx, ddz = p.X - x, p.Z - z
					if ddx * ddx + ddz * ddz < TREE_CLEARANCE * TREE_CLEARANCE then
						return true
					end
				end
			end
		end
	end
	return false
end

local cells: { [string]: Cell } = {}
local dirty: { [string]: boolean } = {}
local loadQueue: { { cx: number, cz: number, key: string } } = {}
local groundOfCell: { [string]: number } = {}

local function cellKey(cx: number, cz: number): string
	return string.format("%d,%d", cx, cz)
end

local function cellGround(cx: number, cz: number, key: string): number
	local y = groundOfCell[key]
	if y == nil then
		y = TerrainGen.HeightAt((cx + 0.5) * CELL, (cz + 0.5) * CELL)
		groundOfCell[key] = y
	end
	return y
end

local function unloadCell(cell: Cell)
	for _, d in ipairs(cell.items) do
		releaseDecor(d)
	end
	liveDecor -= #cell.items
	cells[cell.key] = nil
end

local function loadCell(cx: number, cz: number, key: string)
	local consulted: { [string]: boolean } = {}
	local spots = EnvironmentData.DecorSpots(cx, cz, function(biomeId: string): number
		consulted[biomeId] = true
		return vitalityOf(biomeId)
	end)
	local cell: Cell = { key = key, cx = cx, cz = cz, items = {}, biomes = consulted }
	local parent = root()
	for _, spot in ipairs(spots) do
		if liveDecor >= MAX_DECOR then
			break
		end
		if not nearTree(spot.x, spot.z) then
			local d = acquireDecor(spot)
			if d then
				local at = CFrame.new(spot.x, spot.y, spot.z) * CFrame.Angles(0, spot.yaw, 0)
				for i, part in ipairs(d.parts) do
					part.CFrame = at * d.locals[i]
				end
				d.model.Parent = parent
				table.insert(cell.items, d)
				liveDecor += 1
			end
		end
	end
	cells[key] = cell
end

-- Which cells should be loaded around `focus`, nearest first.
local function scanCells(focus: Vector3)
	table.clear(loadQueue)
	local fx, fz = focus.X, focus.Z
	local reach = math.ceil(LOAD_RADIUS / CELL) + 1
	local ccx, ccz = fx // CELL, fz // CELL
	local wanted: { { cx: number, cz: number, key: string, d: number } } = {}
	for dx = -reach, reach do
		for dz = -reach, reach do
			local cx, cz = ccx + dx, ccz + dz
			local mx, mz = (cx + 0.5) * CELL, (cz + 0.5) * CELL
			local d = math.sqrt((mx - fx) ^ 2 + (mz - fz) ^ 2)
			if d <= LOAD_RADIUS then
				local key = cellKey(cx, cz)
				-- Up on the isles the ground is ~650 studs below: skip it.
				if math.abs(focus.Y - cellGround(cx, cz, key)) < 160 then
					local cell: Cell? = cells[key]
					if cell and dirty[key] then
						unloadCell(cell)
						cell = nil
					end
					if not cell then
						table.insert(wanted, { cx = cx, cz = cz, key = key, d = d })
					end
				end
			end
		end
	end
	table.sort(wanted, function(a, b)
		return a.d < b.d
	end)
	for _, w in ipairs(wanted) do
		table.insert(loadQueue, { cx = w.cx, cz = w.cz, key = w.key })
	end
	-- Far cells (or the ground far below the isles) go back to the pools.
	for key, cell in pairs(cells) do
		local mx, mz = (cell.cx + 0.5) * CELL, (cell.cz + 0.5) * CELL
		local d = math.sqrt((mx - fx) ^ 2 + (mz - fz) ^ 2)
		if d > UNLOAD_RADIUS or math.abs(focus.Y - cellGround(cell.cx, cell.cz, key)) > 200 then
			unloadCell(cell)
		end
	end
end

local function markCellsNear(x: number, z: number, margin: number)
	for _, ox in ipairs({ -margin, 0, margin }) do
		for _, oz in ipairs({ -margin, 0, margin }) do
			local key = cellKey((x + ox) // CELL, (z + oz) // CELL)
			if cells[key] then
				dirty[key] = true
			end
		end
	end
end

local function addTree(tree: Instance)
	if not tree:IsA("Model") or treeAt[tree] then
		return
	end
	local home = tree:GetAttribute("HomePivot")
	local p = if typeof(home) == "CFrame" then home.Position else tree:GetPivot().Position
	local key = binKey(p.X, p.Z)
	local bin = treeBins[key]
	if not bin then
		bin = {}
		treeBins[key] = bin
	end
	bin[tree] = p
	treeAt[tree] = key
	markCellsNear(p.X, p.Z, TREE_CLEARANCE)
end

local function removeTree(tree: Instance)
	local key = treeAt[tree]
	if key then
		local bin = treeBins[key]
		if bin then
			bin[tree] = nil
		end
		treeAt[tree] = nil
	end
end

local lastTier: { [string]: string } = {}

local function onVitalityChanged(attribute: string)
	local biomeId = string.match(attribute, "^Vitality_(.+)$")
	if not biomeId then
		return
	end
	local tier = EnvironmentData.VitalityTier(vitalityOf(biomeId))
	if lastTier[biomeId] == tier then
		return
	end
	lastTier[biomeId] = tier
	for key, cell in pairs(cells) do
		if cell.biomes[biomeId] then
			dirty[key] = true
		end
	end
end

-- Flower spots near a point (butterflies visit them).
local function flowersNear(p: Vector3, minR: number, maxR: number): { Vector3 }
	local out: { Vector3 } = {}
	for _, cell in pairs(cells) do
		local mx, mz = (cell.cx + 0.5) * CELL, (cell.cz + 0.5) * CELL
		if math.abs(mx - p.X) < maxR + CELL and math.abs(mz - p.Z) < maxR + CELL then
			for _, d in ipairs(cell.items) do
				if d.model.Name == "Flowers" then
					local first = d.parts[1]
					if first then
						local q = first.CFrame.Position
						local dist = (flat(q) - flat(p)).Magnitude
						if dist >= minR and dist <= maxR then
							table.insert(out, q)
						end
					end
				end
			end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- 2. Critters
---------------------------------------------------------------------------

local CRITTER_RANGE = 170 -- past this they're gone at once
local PLAN_EVERY = 0.6
local SPAWNS_PER_PLAN = 2

-- One animated model: its parts, their rest CFrames (model space) and how
-- each moves.
type Body = {
	model: Model,
	key: string,
	parts: { BasePart },
	rest: { CFrame },
	anims: { string },
	hinges: { Vector3 },
	phases: { number },
	root: CFrame,
}

-- How a body is posed this frame (degrees).
type Pose = {
	flap: number,
	sweep: number,
	roll: number,
	head: number,
	legSwing: number,
	legT: number, -- 0..1 through the stride
	tail: number,
}

local function newPose(): Pose
	return { flap = 0, sweep = 0, roll = 0, head = 0, legSwing = 0, legT = 0, tail = 0 }
end

type Critter = {
	kind: string,
	cost: number,
	bodies: { Body },
	poses: { Pose },
	age: number,
	life: number, -- seconds before it wanders off on its own
	leaving: boolean,
	pos: Vector3,
	data: { [string]: any },
	step: (c: Critter, dt: number, ctx: Ctx) -> boolean, -- false = done, release it
	cloud: Model?, -- particle-cloud critters (fireflies)
}

type Ctx = { player: Vector3, now: number, env: Environment }

local bodyPools: { [string]: { Body } } = {}
local critters: { Critter } = {}

local function makeBody(model: Model, key: string): Body
	local parts: { BasePart } = {}
	local rest: { CFrame } = {}
	local anims: { string } = {}
	local hinges: { Vector3 } = {}
	local phases: { number } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			table.insert(rest, d.CFrame) -- built around the origin
			local a = d:GetAttribute("Anim")
			table.insert(anims, if type(a) == "string" then a else "")
			local h = d:GetAttribute("Hinge")
			table.insert(hinges, if typeof(h) == "Vector3" then h else Vector3.zero)
			local ph = d:GetAttribute("Phase")
			table.insert(phases, if type(ph) == "number" then ph else 0)
		end
	end
	return {
		model = model,
		key = key,
		parts = parts,
		rest = rest,
		anims = anims,
		hinges = hinges,
		phases = phases,
		root = CFrame.identity,
	}
end

local function acquireBody(key: string, build: () -> Model): Body
	local pool = bodyPools[key]
	local b = if pool then table.remove(pool) else nil
	if not b then
		b = makeBody(build(), key)
	end
	local body = b :: Body
	body.model.Parent = root()
	return body
end

local function releaseBody(b: Body)
	b.model.Parent = nil
	local pool = bodyPools[b.key]
	if not pool then
		pool = {}
		bodyPools[b.key] = pool
	end
	if #pool < 8 then
		table.insert(pool, b)
	else
		b.model:Destroy()
	end
end

local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}

local function poseBody(b: Body, p: Pose)
	local rootCf = b.root
	for i, part in ipairs(b.parts) do
		local a = b.anims[i]
		local rest = b.rest[i]
		local cf: CFrame
		if a == "WingL" then
			cf = rootCf * CritterArt.WingPose(b.hinges[i], -1, p.flap, p.sweep, p.roll) * rest
		elseif a == "WingR" then
			cf = rootCf * CritterArt.WingPose(b.hinges[i], 1, p.flap, p.sweep, p.roll) * rest
		elseif a == "Head" then
			local h = b.hinges[i]
			cf = rootCf * CFrame.new(h) * CFrame.Angles(math.rad(p.head), 0, 0) * CFrame.new(-h) * rest
		elseif a == "Leg" then
			local h = b.hinges[i]
			local swing = math.rad(p.legSwing * math.sin((p.legT + b.phases[i]) * TAU))
			cf = rootCf * CFrame.new(h) * CFrame.Angles(swing, 0, 0) * CFrame.new(-h) * rest
		elseif a == "Tail" then
			local h = b.hinges[i]
			cf = rootCf * CFrame.new(h) * CFrame.Angles(0, math.rad(p.tail), 0) * CFrame.new(-h) * rest
		else
			cf = rootCf * rest -- moves with the body
		end
		table.insert(moveParts, part)
		table.insert(moveFrames, cf)
	end
end

local function groundY(x: number, z: number): number
	return TerrainGen.HeightAt(x, z)
end

-- Open ground a walker may stand on.
local function walkable(x: number, z: number): boolean
	return WorldLayout.FlatWeight(x, z) <= 0
		and TerrainGen.WaterLevelAt(x, z) == nil
		and TerrainGen.RoadClearance(x, z) > 2
		and math.abs(x) < WorldLayout.WorldHalf - 30
		and math.abs(z) < WorldLayout.WorldHalf - 30
end

-- A point around the player, mostly in front of the camera (so critters
-- appear where you're looking), between minR and maxR studs.
local function aroundPlayer(player: Vector3, minR: number, maxR: number): Vector3
	local camera = workspace.CurrentCamera
	local look = if camera then camera.CFrame.LookVector else Vector3.zAxis
	local yaw = math.atan2(look.Z, look.X)
	local a = yaw + (math.random() - 0.5) * 2.4
	local r = minR + (maxR - minR) * math.random()
	return Vector3.new(player.X + math.cos(a) * r, player.Y, player.Z + math.sin(a) * r)
end

local function findGround(player: Vector3, minR: number, maxR: number, tries: number): Vector3?
	for _ = 1, tries do
		local p = aroundPlayer(player, minR, maxR)
		if walkable(p.X, p.Z) then
			return Vector3.new(p.X, groundY(p.X, p.Z), p.Z)
		end
	end
	return nil
end

-- A CFrame at `pos` facing horizontally along `dir`.
local function facing(pos: Vector3, dir: Vector3): CFrame
	local d = flat(dir)
	if d.Magnitude < 1e-3 then
		return CFrame.new(pos)
	end
	return CFrame.lookAt(pos, pos + d)
end

local function awayFrom(from: Vector3, of: Vector3): Vector3
	local d = flat(of - from)
	if d.Magnitude < 1e-3 then
		local a = math.random() * TAU
		return Vector3.new(math.cos(a), 0, math.sin(a))
	end
	return d.Unit
end

local function newCritter(
	kind: string,
	bodies: { Body },
	pos: Vector3,
	life: number,
	step: (Critter, number, Ctx) -> boolean
): Critter
	local poses: { Pose } = {}
	for i = 1, #bodies do
		poses[i] = newPose()
	end
	return {
		kind = kind,
		cost = EnvironmentData.CritterCost[kind] or 1,
		bodies = bodies,
		poses = poses,
		age = 0,
		life = life,
		leaving = false,
		pos = pos,
		data = {},
		step = step,
		cloud = nil,
	}
end

---------------------------------------------------------------------------
-- Birds
---------------------------------------------------------------------------

local FLOCK_SIZE = 5

local function stepFlock(c: Critter, dt: number, ctx: Ctx): boolean
	local d = c.data
	local center: Vector3 = d.center
	local t = c.age
	if not d.scattered then
		local near = (flat(ctx.player) - flat(center)).Magnitude < 32
		if near or c.leaving or c.age > c.life then
			d.scattered = true
			d.scatterAt = t
			SoundData.PlayAt("Wings", center + Vector3.new(0, d.height, 0))
			-- Burst outward, away from whoever came close, climbing.
			for i, body in ipairs(c.bodies) do
				local out = awayFrom(ctx.player, body.root.Position)
				local jitter = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
				d.vel[i] = (out + jitter).Unit * (12 + math.random() * 4) + Vector3.new(0, 8 + math.random() * 5, 0)
			end
		end
	end
	for i, body in ipairs(c.bodies) do
		local pose = c.poses[i]
		local vel: Vector3
		local pos: Vector3
		if d.scattered then
			local v: Vector3 = d.vel[i]
			v += Vector3.new(0, 4, 0) * dt + v.Unit * 6 * dt
			d.vel[i] = v
			pos = body.root.Position + v * dt
			vel = v
			pose.flap = math.sin(t * 17 + i) * 55
		else
			local ang = d.angle + t * d.spin + (i - 1) * 0.34
			local r = d.radius + ((i * 37) % 7) - 3
			local h = d.height + math.sin(t * 0.8 + i) * 1.6 + (i % 3)
			pos = center + Vector3.new(math.cos(ang) * r, h, math.sin(ang) * r)
			vel = Vector3.new(-math.sin(ang), 0, math.cos(ang)) * d.spin * r
			-- Flap a while, glide a while.
			local gliding = math.sin(t * 0.7 + i * 1.3) > 0.35
			pose.flap = if gliding then 6 else math.sin(t * 12 + i * 2) * 48
			d.vel[i] = vel
		end
		local bank = if d.scattered then 0 else math.rad(-18 * math.sign(d.spin))
		body.root = facing(pos, vel) * CFrame.Angles(0, 0, bank)
	end
	c.pos = center
	if d.scattered then
		return t - (d.scatterAt :: number) < 5
	end
	return true
end

local function spawnFlock(ctx: Ctx): Critter?
	local spot = findGround(ctx.player, 50, 110, 6)
	if not spot then
		return nil
	end
	local seed = math.random(0, 4)
	local bodies: { Body } = {}
	for i = 1, FLOCK_SIZE do
		local look = (seed + i) % 5
		table.insert(
			bodies,
			acquireBody("FlockBird" .. look, function(): Model
				return CritterArt.Bird(look, 1.6, true)
			end)
		)
	end
	local c = newCritter("Flock", bodies, spot, 60 + math.random() * 60, stepFlock)
	c.data.center = spot
	c.data.height = 34 + math.random() * 16
	c.data.radius = 18 + math.random() * 8
	c.data.angle = math.random() * TAU
	c.data.spin = (if math.random() < 0.5 then -1 else 1) * (0.28 + math.random() * 0.12)
	local away = {}
	for i = 1, FLOCK_SIZE do
		local a = math.random() * TAU
		away[i] = Vector3.new(math.cos(a) * 18, 10 + math.random() * 6, math.sin(a) * 18)
	end
	c.data.vel = away
	return c
end

local function stepPerched(c: Critter, dt: number, ctx: Ctx): boolean
	local d = c.data
	local body = c.bodies[1]
	local pose = c.poses[1]
	local t = c.age
	if not d.flying then
		if (flat(ctx.player) - flat(c.pos)).Magnitude < 14 or c.leaving or t > c.life then
			d.flying = true
			d.flyAt = t
			d.dir = awayFrom(ctx.player, c.pos)
			SoundData.PlayAt("Wings", c.pos)
		end
		-- Hop about and peck.
		local peck = math.sin(t * 5.5) > 0.6
		pose.head = if peck then -40 else math.sin(t * 1.3) * 8
		pose.flap, pose.sweep, pose.roll = 0, CritterArt.FoldedSweep, CritterArt.FoldedRoll
		if t >= (d.nextHop :: number) then
			d.nextHop = t + 1.2 + math.random() * 2.5
			d.yaw += (math.random() - 0.5) * 2
			local step = Vector3.new(math.cos(d.yaw), 0, math.sin(d.yaw)) * 0.8
			local x, z = c.pos.X + step.X, c.pos.Z + step.Z
			if walkable(x, z) then
				c.pos = Vector3.new(x, groundY(x, z), z)
			end
			d.hopAt = t
		end
		local hop = math.clamp((t - (d.hopAt :: number)) / 0.25, 0, 1)
		local lift = math.sin(hop * math.pi) * 0.35
		body.root = facing(c.pos + Vector3.new(0, lift, 0), Vector3.new(math.cos(d.yaw), 0, math.sin(d.yaw)))
		return true
	end
	-- Away it goes: wings unfold, then up and off.
	local since = t - (d.flyAt :: number)
	local unfold = math.clamp(since / 0.25, 0, 1)
	pose.sweep = CritterArt.FoldedSweep * (1 - unfold)
	pose.roll = CritterArt.FoldedRoll * (1 - unfold)
	pose.flap = math.sin(since * 18) * 55 * unfold
	pose.head = 0
	local dir: Vector3 = d.dir
	local speed = math.min(18, 4 + since * 14)
	c.pos += (dir * speed + Vector3.new(0, 7 + since * 2, 0)) * dt
	body.root = facing(c.pos, dir) * CFrame.Angles(math.rad(-12), 0, 0)
	return since < 4
end

local function spawnPerched(ctx: Ctx): Critter?
	local spot = findGround(ctx.player, 22, 55, 6)
	if not spot then
		return nil
	end
	local look = math.random(0, 4)
	local body = acquireBody("Songbird" .. look, function(): Model
		return CritterArt.Bird(look, 1, false)
	end)
	local c = newCritter("PerchedBird", { body }, spot, 30 + math.random() * 40, stepPerched)
	c.data.yaw = math.random() * TAU
	c.data.nextHop = 1 + math.random() * 2
	c.data.hopAt = -1
	return c
end

---------------------------------------------------------------------------
-- Butterflies and fireflies
---------------------------------------------------------------------------

local function stepButterfly(c: Critter, dt: number, _ctx: Ctx): boolean
	local d = c.data
	local t = c.age
	local body = c.bodies[1]
	local pose = c.poses[1]
	if (c.leaving or t > c.life) and not d.leaveAt then
		d.leaveAt = t
	end
	local anchor: Vector3 = d.anchor
	local phase: number = d.phase
	local function at(time: number): Vector3
		local lift = 1.3 + math.sin(time * 1.9 + phase) * 0.6 + math.abs(math.sin(time * 0.45)) * 1.1
		if d.leaveAt then
			lift += (time - (d.leaveAt :: number)) ^ 2 * 2
		end
		return anchor + Vector3.new(math.sin(time * 0.7 + phase) * 3.5, lift, math.sin(time * 0.53 + phase * 2) * 3.5)
	end
	local pos = at(t)
	local ahead = at(t + 0.08)
	pose.flap = 12 + math.abs(math.sin(t * 13 + phase)) * 62
	body.root = facing(pos, ahead - pos)
	c.pos = pos
	-- Drift slowly from flower to flower.
	d.anchor = anchor + (d.drift :: Vector3) * dt
	if d.leaveAt then
		return t - (d.leaveAt :: number) < 4
	end
	return true
end

local function spawnButterfly(ctx: Ctx): Critter?
	local flowers = flowersNear(ctx.player, 12, 60)
	local anchor: Vector3
	if #flowers > 0 then
		anchor = flowers[math.random(1, #flowers)]
	else
		local g = findGround(ctx.player, 14, 45, 5)
		if not g then
			return nil
		end
		anchor = g
	end
	local look = math.random(0, 4)
	local body = acquireBody("Butterfly" .. look, function(): Model
		return CritterArt.Butterfly(look)
	end)
	local c = newCritter("Butterfly", { body }, anchor, 40 + math.random() * 50, stepButterfly)
	c.data.anchor = anchor
	c.data.phase = math.random() * TAU
	local a = math.random() * TAU
	c.data.drift = Vector3.new(math.cos(a), 0, math.sin(a)) * 0.35
	return c
end

local function stepCloud(c: Critter, _dt: number, ctx: Ctx): boolean
	local d = c.data
	if (c.leaving or c.age > c.life or ctx.env.daylight > 0.35) and not d.fadeAt then
		d.fadeAt = c.age
		local cloud = c.cloud
		local emitter = if cloud then cloud:FindFirstChild("Particles", true) else nil
		if emitter and emitter:IsA("ParticleEmitter") then
			emitter.Enabled = false -- the last ones blink out on their own
		end
	end
	if d.fadeAt then
		return c.age - (d.fadeAt :: number) < 6
	end
	return true
end

local fireflyPool: { Model } = {}

local function spawnFireflies(ctx: Ctx): Critter?
	local spot = findGround(ctx.player, 18, 60, 6)
	if not spot then
		return nil
	end
	local life = EnvironmentData.LifeFactor(vitalityOf(if ctx.env.biomeId == "" then "starter" else ctx.env.biomeId))
	local model = table.remove(fireflyPool) or CritterArt.Fireflies(Vector3.new(26, 5, 26), 6)
	local cloud = model:FindFirstChild("Cloud")
	if cloud and cloud:IsA("BasePart") then
		cloud.CFrame = CFrame.new(spot + Vector3.new(0, 2.6, 0))
	end
	local emitter = model:FindFirstChild("Particles", true)
	if emitter and emitter:IsA("ParticleEmitter") then
		emitter.Rate = 3 + 3 * life
		emitter.Enabled = true
	end
	model.Parent = root()
	local c = newCritter("Fireflies", {}, spot, 120 + math.random() * 120, stepCloud)
	c.cloud = model
	return c
end

---------------------------------------------------------------------------
-- Rabbits and deer
---------------------------------------------------------------------------

-- Moves a walker toward `dir` by `dist`, staying on open ground. Returns
-- false if the way ahead is blocked. (The full ground check runs every
-- couple of studs, looking ahead; in between it only follows the height.)
local function walk(c: Critter, dir: Vector3, dist: number): boolean
	local x, z = c.pos.X + dir.X * dist, c.pos.Z + dir.Z * dist
	local d = c.data
	local checked: Vector3? = d.checkedAt
	if not checked or (Vector3.new(x, 0, z) - (checked :: Vector3)).Magnitude > 1.5 then
		if not walkable(x + dir.X * 2, z + dir.Z * 2) then
			return false
		end
		d.checkedAt = Vector3.new(x, 0, z)
	end
	c.pos = Vector3.new(x, groundY(x, z), z)
	return true
end

local function stepRabbit(c: Critter, dt: number, ctx: Ctx): boolean
	local d = c.data
	local t = c.age
	local body = c.bodies[1]
	local pose = c.poses[1]
	local dist = (flat(ctx.player) - flat(c.pos)).Magnitude
	if not d.fleeing and (dist < 25 or c.leaving or t > c.life) then
		d.fleeing = true
		d.fleeAt = t
		d.dir = awayFrom(ctx.player, c.pos)
		d.state = "hop"
		d.hopT = 0
	end
	if d.state == "sit" then
		pose.head = math.sin(t * 2.2) * 6 + (if math.sin(t * 0.9) > 0.8 then -18 else 0) -- nibbling
		if t >= (d.until_ :: number) then
			d.state = "hop"
			d.hops = math.random(2, 5)
			d.hopT = 0
			local a = math.random() * TAU
			d.dir = Vector3.new(math.cos(a), 0, math.sin(a))
		end
		body.root = facing(c.pos, d.dir)
		return true
	end
	-- Hopping: each hop an arc; fleeing hops are long and quick.
	local hopTime = if d.fleeing then 0.3 else 0.36
	local hopLen = if d.fleeing then 4.2 else 1.5
	d.hopT += dt / hopTime
	local moved = walk(c, d.dir, hopLen * dt / hopTime)
	if not moved then
		local a = math.random() * TAU
		d.dir = Vector3.new(math.cos(a), 0, math.sin(a))
	end
	local phase = d.hopT % 1
	local lift = math.sin(phase * math.pi) * (if d.fleeing then 1.1 else 0.55)
	pose.head = 0
	body.root = facing(c.pos + Vector3.new(0, lift, 0), d.dir) * CFrame.Angles(math.rad(10 - phase * 20), 0, 0)
	if d.hopT >= 1 and not d.fleeing then
		d.hopT -= 1
		d.hops -= 1
		if d.hops <= 0 then
			d.state = "sit"
			d.until_ = t + 1.5 + math.random() * 3
		end
	end
	if d.fleeing then
		local since = t - (d.fleeAt :: number)
		return since < 3.5 or (dist < 60 and since < 10)
	end
	return true
end

local function spawnRabbit(ctx: Ctx): Critter?
	local spot = findGround(ctx.player, 30, 70, 6)
	if not spot then
		return nil
	end
	local snowy = ctx.env.biomeId == "snow"
	local look = math.random(1, 3)
	local key = if snowy then "Hare" else "Rabbit" .. look
	local body = acquireBody(key, function(): Model
		return CritterArt.Rabbit(if snowy then 9 else look, snowy)
	end)
	local c = newCritter("Rabbit", { body }, spot, 50 + math.random() * 60, stepRabbit)
	local a = math.random() * TAU
	c.data.dir = Vector3.new(math.cos(a), 0, math.sin(a))
	c.data.state = "sit"
	c.data.until_ = 1 + math.random() * 2
	c.data.hops = 0
	c.data.hopT = 0
	return c
end

local function stepDeer(c: Critter, dt: number, ctx: Ctx): boolean
	local d = c.data
	local t = c.age
	local body = c.bodies[1]
	local pose = c.poses[1]
	local dist = (flat(ctx.player) - flat(c.pos)).Magnitude
	if not d.fleeing and (dist < 25 or c.leaving or t > c.life) then
		d.fleeing = true
		d.fleeAt = t
		d.dir = (awayFrom(ctx.player, c.pos) + Vector3.new((math.random() - 0.5) * 0.6, 0, (math.random() - 0.5) * 0.6)).Unit
		d.stride = 0
	end
	if d.fleeing then
		-- Bounding away: long leaps, legs flying, tail up.
		local speed = 20
		d.stride += dt / 0.55
		if not walk(c, d.dir, speed * dt) then
			d.dir = (d.dir :: Vector3):Cross(Vector3.yAxis).Unit * (if math.random() < 0.5 then 1 else -1)
		end
		local phase = d.stride % 1
		local lift = math.sin(phase * math.pi) * 1.4
		pose.legSwing, pose.legT = 38, phase
		pose.head = 12
		pose.tail = 0
		body.root = facing(c.pos + Vector3.new(0, lift, 0), d.dir) * CFrame.Angles(math.rad(8 - phase * 16), 0, 0)
		local since = t - (d.fleeAt :: number)
		return since < 4 or (dist < 70 and since < 10)
	end
	if d.state == "graze" then
		pose.head = -52 + math.sin(t * 1.7) * 5
		pose.legSwing = 0
		pose.tail = math.sin(t * 6) * 10
		if t >= (d.until_ :: number) then
			d.state = "look"
			d.until_ = t + 1 + math.random() * 1.5
		end
	elseif d.state == "look" then
		pose.head = math.sin(t * 0.8) * 4
		if t >= (d.until_ :: number) then
			d.state = "walk"
			d.until_ = t + 2.5 + math.random() * 3
			local a = math.random() * TAU
			d.dir = Vector3.new(math.cos(a), 0, math.sin(a))
			d.stride = 0
		end
	else
		d.stride += dt * 1.1
		pose.legSwing, pose.legT = 20, d.stride % 1
		pose.head = -6
		if not walk(c, d.dir, 3.2 * dt) then
			d.until_ = t
		end
		if t >= (d.until_ :: number) then
			d.state = "graze"
			d.until_ = t + 4 + math.random() * 5
			pose.legSwing = 0
		end
	end
	body.root = facing(c.pos, d.dir)
	return true
end

local function spawnDeer(ctx: Ctx): Critter?
	local spot = findGround(ctx.player, 45, 90, 8)
	if not spot then
		return nil
	end
	local seed = math.random(1, 6)
	local body = acquireBody("Deer" .. (seed % 2), function(): Model
		return CritterArt.Deer(seed)
	end)
	local c = newCritter("Deer", { body }, spot, 70 + math.random() * 80, stepDeer)
	local a = math.random() * TAU
	c.data.dir = Vector3.new(math.cos(a), 0, math.sin(a))
	c.data.state = "graze"
	c.data.until_ = 2 + math.random() * 4
	c.data.stride = 0
	return c
end

---------------------------------------------------------------------------
-- Ducks and fish
---------------------------------------------------------------------------

local POND = WorldLayout.Pond

local function stepDuck(c: Critter, dt: number, ctx: Ctx): boolean
	local d = c.data
	local t = c.age
	local body = c.bodies[1]
	local pose = c.poses[1]
	-- Paddle slowly round the pond, steering away from anyone close.
	d.angle += dt * (d.speed :: number) / (d.radius :: number)
	local center = Vector3.new(POND.x, WorldLayout.LakeLevel - 0.05, POND.z)
	local pos = center
		+ Vector3.new(math.cos(d.angle) * d.radius, math.sin(t * 2 + d.angle) * 0.05, math.sin(d.angle) * d.radius)
	if (flat(pos) - flat(ctx.player)).Magnitude < 7 then
		-- Someone's close: paddle to the far side of the circle from them.
		local playerOut = (flat(ctx.player) - flat(center)).Magnitude
		local push = if playerOut < d.radius then 1 else -1
		d.radius = math.clamp(d.radius + dt * 2 * push, 3, POND.radius - 4)
	end
	local heading = Vector3.new(-math.sin(d.angle), 0, math.cos(d.angle)) * math.sign(d.speed)
	local dipping = math.sin(t * 0.35 + d.angle * 3) > 0.92
	pose.head = if dipping then -75 else math.sin(t * 1.5) * 6
	pose.tail = math.sin(t * 3) * 8
	body.root = facing(pos, heading)
	c.pos = pos
	return not c.leaving or (flat(ctx.player) - flat(pos)).Magnitude < 120
end

local function spawnDuck(_ctx: Ctx): Critter?
	local look = math.random(1, 4)
	local body = acquireBody("Duck" .. (look % 2), function(): Model
		return CritterArt.Duck(look)
	end)
	local c = newCritter("Duck", { body }, Vector3.new(POND.x, WorldLayout.LakeLevel, POND.z), math.huge, stepDuck)
	c.data.angle = math.random() * TAU
	c.data.radius = 4 + math.random() * (POND.radius - 9)
	c.data.speed = (if math.random() < 0.5 then -1 else 1) * (0.8 + math.random() * 0.6)
	return c
end

local splashPool: { Model } = {}

local function splash(at: Vector3)
	local model = table.remove(splashPool) or CritterArt.Splash()
	local part = model:FindFirstChild("Splash")
	local emitter = if part then part:FindFirstChild("Particles") else nil
	if part and part:IsA("BasePart") and emitter and emitter:IsA("ParticleEmitter") then
		part.CFrame = CFrame.new(at)
		model.Parent = root()
		emitter:Emit(14)
		task.delay(1.2, function()
			model.Parent = nil
			table.insert(splashPool, model)
		end)
	end
	SoundData.PlayAt("FishSplash", at)
end

-- A spot of open water near the player, deep enough for a fish.
local function waterSpot(player: Vector3): Vector3?
	local p = EnvironmentData.NearestWater(player.X, player.Z)
	for _ = 1, 6 do
		local x = p.X + (math.random() - 0.5) * 24
		local z = p.Z + (math.random() - 0.5) * 24
		local surface = TerrainGen.WaterLevelAt(x, z)
		if surface and surface - TerrainGen.HeightAt(x, z) > 1.5 then
			return Vector3.new(x, surface, z)
		end
	end
	return nil
end

local JUMP_TIME = 0.95

local function stepFish(c: Critter, _dt: number, ctx: Ctx): boolean
	local d = c.data
	local body = c.bodies[1]
	local pose = c.poses[1]
	local t = c.age
	if not d.jumping then
		if c.leaving or t > c.life then
			return false
		end
		if t >= (d.nextJump :: number) then
			local spot = waterSpot(ctx.player)
			if spot and (flat(spot) - flat(ctx.player)).Magnitude < 90 then
				d.jumping = true
				d.jumpAt = t
				d.from = spot
				local a = math.random() * TAU
				d.dir = Vector3.new(math.cos(a), 0, math.sin(a))
				body.model.Parent = root()
				splash(spot)
			else
				d.nextJump = t + 3
			end
		end
		return true
	end
	local u = (t - (d.jumpAt :: number)) / JUMP_TIME
	local from: Vector3 = d.from
	local dir: Vector3 = d.dir
	if u >= 1 then
		d.jumping = false
		d.nextJump = t + 4 + math.random() * 7
		body.model.Parent = nil
		splash(from + dir * 3)
		return true
	end
	local pos = from + dir * (3 * u) + Vector3.new(0, -0.8 + 3.6 * math.sin(u * math.pi), 0)
	local pitch = math.cos(u * math.pi) * 1.1 -- nose up rising, down falling
	pose.tail = math.sin(t * 30) * 25
	body.root = facing(pos, dir) * CFrame.Angles(pitch, 0, 0)
	c.pos = pos
	return true
end

local function spawnFish(ctx: Ctx): Critter?
	local look = math.random(1, 3)
	local body = acquireBody("Fish" .. look, function(): Model
		return CritterArt.Fish(look)
	end)
	body.model.Parent = nil -- hidden until it leaps
	local near = EnvironmentData.NearestWater(ctx.player.X, ctx.player.Z)
	local c = newCritter("Fish", { body }, near, 60 + math.random() * 60, stepFish)
	c.data.nextJump = 1 + math.random() * 3
	c.data.jumping = false
	return c
end

---------------------------------------------------------------------------
-- Wisps and ember sprites
---------------------------------------------------------------------------

local function stepWisp(c: Critter, dt: number, ctx: Ctx): boolean
	local d = c.data
	local t = c.age
	local body = c.bodies[1]
	local pose = c.poses[1]
	local anchor: Vector3 = d.anchor
	-- Curious: drift toward the player, never closer than ~9 studs.
	local toPlayer = flat(ctx.player - anchor)
	if toPlayer.Magnitude > 16 then
		anchor += toPlayer.Unit * dt * 1.4
	elseif toPlayer.Magnitude < 9 and toPlayer.Magnitude > 1e-3 then
		anchor -= toPlayer.Unit * dt * 3
	end
	if c.leaving or t > c.life or ctx.env.daylight > 0.3 then
		anchor += Vector3.new(0, dt * 6, 0) -- rise away into the dark
		d.gone = (d.gone or 0) + dt
	end
	d.anchor = anchor
	local seed: number = d.seed
	local wander = Vector3.new(math.noise(t * 0.25, seed) * 7, 0, math.noise(seed, t * 0.25) * 7)
	local ground = groundY(anchor.X + wander.X, anchor.Z + wander.Z)
	local pos = Vector3.new(
		anchor.X + wander.X,
		math.max(ground, anchor.Y) + 2.6 + math.sin(t * 1.3 + seed) * 0.7,
		anchor.Z + wander.Z
	)
	if d.gone then
		pos += Vector3.new(0, (d.gone :: number) * 4, 0)
	end
	local last: Vector3 = d.last or pos
	d.last = pos
	pose.tail = math.sin(t * 2.4 + seed) * 25
	body.root = facing(pos, pos - last + Vector3.new(0.001, 0, 0))
	c.pos = pos
	return d.gone == nil or (d.gone :: number) < 3
end

local function spawnWisp(ctx: Ctx): Critter?
	local spot = findGround(ctx.player, 18, 45, 6)
	if not spot then
		return nil
	end
	local look = math.random(1, 3)
	local body = acquireBody("Wisp" .. look, function(): Model
		return CritterArt.Wisp(look)
	end)
	local c = newCritter("Wisp", { body }, spot, 90 + math.random() * 90, stepWisp)
	c.data.anchor = spot
	c.data.seed = math.random() * 100
	return c
end

local function stepEmber(c: Critter, dt: number, ctx: Ctx): boolean
	local d = c.data
	local t = c.age
	local body = c.bodies[1]
	local pose = c.poses[1]
	local dist = (flat(ctx.player) - flat(c.pos)).Magnitude
	if dist < 9 and not d.zipping then
		d.zipping = t
		d.dir = awayFrom(ctx.player, c.pos)
	end
	local speed = if d.zipping then 12 else 1.6
	if d.zipping and t - (d.zipping :: number) > 1.5 then
		d.zipping = nil
	end
	if t >= (d.turnAt :: number) and not d.zipping then
		d.turnAt = t + 1.5 + math.random() * 2.5
		local a = math.random() * TAU
		d.dir = Vector3.new(math.cos(a), 0, math.sin(a))
	end
	local x, z = c.pos.X + d.dir.X * speed * dt, c.pos.Z + d.dir.Z * speed * dt
	if TerrainGen.WaterLevelAt(x, z) == nil and WorldLayout.FlatWeight(x, z) <= 0 then
		c.pos = Vector3.new(x, groundY(x, z), z)
	else
		d.dir = -(d.dir :: Vector3)
	end
	local bounce = math.abs(math.sin(t * (if d.zipping then 9 else 3.2))) * (if d.zipping then 1.4 else 0.7)
	pose.tail = math.sin(t * 14) * 14
	body.root = facing(c.pos + Vector3.new(0, 0.55 + bounce, 0), d.dir)
	if c.leaving or t > c.life then
		return dist < 60 and t < c.life + 6
	end
	return true
end

local function spawnEmber(ctx: Ctx): Critter?
	local spot = findGround(ctx.player, 16, 50, 6)
	if not spot then
		return nil
	end
	local look = math.random(1, 3)
	local body = acquireBody("Ember" .. look, function(): Model
		return CritterArt.EmberSprite(look)
	end)
	local c = newCritter("EmberSprite", { body }, spot, 80 + math.random() * 80, stepEmber)
	local a = math.random() * TAU
	c.data.dir = Vector3.new(math.cos(a), 0, math.sin(a))
	c.data.turnAt = 1
	return c
end

local SPAWNERS: { [string]: (Ctx) -> Critter? } = {
	Flock = spawnFlock,
	PerchedBird = spawnPerched,
	Butterfly = spawnButterfly,
	Fireflies = spawnFireflies,
	Rabbit = spawnRabbit,
	Deer = spawnDeer,
	Duck = spawnDuck,
	Fish = spawnFish,
	Wisp = spawnWisp,
	EmberSprite = spawnEmber,
}

local function releaseCritter(c: Critter)
	for _, b in ipairs(c.bodies) do
		releaseBody(b)
	end
	local cloud = c.cloud
	if cloud then
		cloud.Parent = nil
		if #fireflyPool < 4 then
			table.insert(fireflyPool, cloud)
		else
			cloud:Destroy()
		end
	end
end

local function plan(ctx: Ctx)
	local env = ctx.env
	local player = ctx.player
	local biomeId = env.biomeId
	local pondDistance = (flat(player) - Vector3.new(POND.x, 0, POND.z)).Magnitude
	local _, waterDistance, waterKind = EnvironmentData.NearestWater(player.X, player.Z)
	local wants = EnvironmentData.CritterPlan({
		biomeId = biomeId,
		daylight = env.daylight,
		weather = env.weather,
		intensity = env.intensity,
		vitality = vitalityOf(if biomeId == "" then "starter" else biomeId),
		nearPond = pondDistance < 130 and math.abs(player.Y - WorldLayout.LakeLevel) < 60,
		nearWater = waterDistance < 60 and waterKind ~= "pond" and math.abs(player.Y - WorldLayout.LakeLevel) < 60,
	})
	-- What's out already, and what's no longer wanted.
	local wantCount: { [string]: number } = {}
	for _, w in ipairs(wants) do
		wantCount[w.kind] = w.count
	end
	local have: { [string]: number } = {}
	local spent = 0
	for _, c in ipairs(critters) do
		if not c.leaving then
			local n = (have[c.kind] or 0) + 1
			if n > (wantCount[c.kind] or 0) then
				c.leaving = true -- too many of these now: this one wanders off
			else
				have[c.kind] = n
			end
		end
		spent += c.cost
	end
	-- Fill up, most special first, within the budget.
	local spawned = 0
	for _, w in ipairs(wants) do
		local cost = EnvironmentData.CritterCost[w.kind] or 1
		while (have[w.kind] or 0) < w.count and spawned < SPAWNS_PER_PLAN do
			if spent + cost > EnvironmentData.MaxCritters then
				return
			end
			local spawner = SPAWNERS[w.kind]
			local c = if spawner then spawner(ctx) else nil
			if not c then
				break
			end
			table.insert(critters, c)
			have[w.kind] = (have[w.kind] or 0) + 1
			spent += cost
			spawned += 1
		end
	end
end

local function stepCritters(dt: number, ctx: Ctx)
	table.clear(moveParts)
	table.clear(moveFrames)
	for i = #critters, 1, -1 do
		local c = critters[i]
		c.age += dt
		local alive = c.step(c, dt, ctx)
		local far = (flat(c.pos) - flat(ctx.player)).Magnitude > CRITTER_RANGE
		if not alive or far then
			releaseCritter(c)
			table.remove(critters, i)
		else
			for k, body in ipairs(c.bodies) do
				if body.model.Parent then
					poseBody(body, c.poses[k])
				end
			end
		end
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

---------------------------------------------------------------------------
-- 3. The Skyroot's motes
---------------------------------------------------------------------------

type Motes = { near: Model, bloom: Model, nearEmitter: ParticleEmitter?, bloomEmitter: ParticleEmitter? }
local motes: Motes? = nil
local skyPlan: WorldPlan.Sky? = nil

local function emitterOf(model: Model): ParticleEmitter?
	local e = model:FindFirstChild("Particles", true)
	return if e and e:IsA("ParticleEmitter") then e else nil
end

local function cloudOf(model: Model): BasePart?
	local p = model:FindFirstChild("Cloud")
	return if p and p:IsA("BasePart") then p else nil
end

local function updateMotes(player: Vector3)
	local sky = skyPlan
	if not sky then
		return
	end
	local m = motes
	if not m then
		local near = CritterArt.Motes(Vector3.new(150, 120, 150), Color3.fromRGB(255, 226, 140), 14, 0.5)
		local bloom = CritterArt.Motes(Vector3.new(320, 140, 320), Color3.fromRGB(255, 214, 110), 70, 2.6)
		local made: Motes =
			{ near = near, bloom = bloom, nearEmitter = emitterOf(near), bloomEmitter = emitterOf(bloom) }
		local bloomCloud = cloudOf(bloom)
		if bloomCloud then
			-- Pouring off the crown, under the isles.
			bloomCloud.CFrame = CFrame.new(sky.root + Vector3.new(0, sky.trunkHeight - 60, 0))
		end
		near.Parent = root()
		bloom.Parent = root()
		m = made
		motes = made
	end
	local mm = m :: Motes
	local blooming = workspace:GetAttribute("SkyrootBloom") == true
	local d = (flat(player) - flat(sky.root)).Magnitude
	local nearCloud = cloudOf(mm.near)
	local nearOn = d < 650
	if nearCloud and nearOn then
		local y = math.clamp(player.Y, sky.root.Y + 30, sky.root.Y + sky.trunkHeight)
		nearCloud.CFrame = CFrame.new(sky.root.X, y, sky.root.Z)
	end
	local ne = mm.nearEmitter
	if ne then
		ne.Enabled = nearOn
		local rate = if blooming then 45 else 14
		if ne.Rate ~= rate then
			ne.Rate = rate
		end
	end
	local be = mm.bloomEmitter
	if be and be.Enabled ~= blooming then
		be.Enabled = blooming
	end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

function AmbientLife.Start()
	skyPlan = WorldPlan.Sky()

	for _, tree in ipairs(CollectionService:GetTagged("Tree")) do
		addTree(tree)
	end
	CollectionService:GetInstanceAddedSignal("Tree"):Connect(addTree)
	CollectionService:GetInstanceRemovedSignal("Tree"):Connect(removeTree)
	workspace.AttributeChanged:Connect(onVitalityChanged)
	for name in pairs(workspace:GetAttributes()) do
		onVitalityChanged(name)
	end

	local sinceScan = math.huge
	local sincePlan = 0
	RunService.Heartbeat:Connect(function(dt: number)
		local player = focusPoint()
		-- Decoration: rescan now and then, load a couple of cells a frame.
		sinceScan += dt
		if sinceScan >= SCAN_EVERY then
			sinceScan = 0
			scanCells(player)
			table.clear(dirty)
			updateMotes(player)
		end
		for _ = 1, CELLS_PER_FRAME do
			local queued = table.remove(loadQueue, 1)
			if not queued or liveDecor >= MAX_DECOR then
				break
			end
			if not cells[queued.key] then
				loadCell(queued.cx, queued.cz, queued.key)
			end
		end
		-- Critters.
		local ctx: Ctx = { player = player, now = os.clock(), env = LightingController.Environment() }
		sincePlan += dt
		if sincePlan >= PLAN_EVERY then
			sincePlan = 0
			plan(ctx)
		end
		stepCritters(math.min(dt, 0.1), ctx)
	end)
end

return AmbientLife
