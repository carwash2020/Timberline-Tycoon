--!strict
-- SectionTrees: the v2 loop's standing trees (V2_PLAN.md §3b-§3i). Under
-- CoreLoop 2 it takes over from TreeService for everything standing:
-- MapBuilder plants the world's tree sites with it, GameServer sends it
-- the Chop remote, and ForestService, WorldClock, WeatherService and
-- QuestService use it through the same public API and TreeRecord shape
-- TreeService has (SpawnTree, Remove, Decorate, Forget, HoldRegrow, Regrow,
-- SetBiomeDormant, GetTreeWood, GetTree, AllTrees, RegrowsIn; OnFelled,
-- OnRegrown, StumpHold, LogMultiplier). Loose wood is WoodService's.
--
--   * A site's tree is a Shared/TreeGen skeleton dressed by
--     TreeArt.FromSkeleton (sections you can cut, leaves and details that
--     ride them), standing where TreeService would have put it, turned and
--     sized the same way (GrowLogic.Site). When the server starts most are
--     mature and some are young (GrowLogic.BootAge), so the world isn't
--     all saplings.
--   * Growth: a tree sprouts as a sapling (TreeArt.GrowingSapling, not
--     cuttable), then grows through GrowStages stages over the wood's
--     growSec (TreeGen.AtStage). It lives its lifespan, drops its leaves at
--     PreDeadAt of it, then dies: dark bark, dull glow, nothing to cut;
--     every client sinks it over DeadSinkSec and then it goes. A tree
--     someone has cut stops growing. Every GrowTickSec at most
--     TreesPerGrowTick trees change (GrowLogic.TakeDue), so growth never
--     spikes the server.
--   * Cutting (Chop, below): a swing's damage goes into a cut at a height
--     on a section (SectionLogic: within CutWindow of a cut it adds to it,
--     at most MaxCutsPerSection); a notch grows on the face it was started
--     from (TreeArt.Notch). Once a cut is through, the section splits: its
--     bottom stays (resized, anchored, a cut face on top) and everything
--     above it becomes one loose piece (WoodService.Adopt), owned by
--     whoever did most of that cut (SectionLogic.Owner). Through a trunk
--     section the tree is felled: it tips away from the cutter, and the
--     stub left standing is the tree's model, tagged Stump (ForestUI's
--     planting prompt) until the site regrows after the wood's respawnSec
--     (HoldRegrow and StumpHold as TreeService has them). Cutting only
--     limbs ("limbing") never fells it.
--   * Felled = the first cut through a trunk section: OnFelled(feller,
--     rec, pieceUids, fallDir) fires once, the feller decided by
--     ForestLogic.Feller over the whole tree's damageBy.
--   * Night-only woods (the Gloam Hollow): SetBiomeDormant hides a biome's
--     trees and stubs by day (a half-cut tree is whole again tomorrow
--     night) and brings them back at night (WorldClock).
--   * A tree that comes back solid (regrown, grown a stage, woken) where a
--     truck or someone stands is a ghost (no collisions) until the spot
--     is clear, checked every GhostRetry seconds.
-- Model contract (CutController, WoodFX, WindSway, CanopyFade, ForestUI):
-- tag Tree, in TimberlineMap/Trees, Atomic; FromSkeleton's parts and
-- attributes (WoodId, Seed, Stage, Scale, Elder, Felled, Dormant,
-- PlanterId, Uid) plus HomePivot (its PrimaryPart's CFrame), SwayTop (the
-- top of its trunk, where the crown rocks about), Sapling (true while a
-- sapling), GrewAt (server time it last grew: the regrow spring),
-- PreDead, Dead and DeadAt (server time: the death sink), and after a
-- felling the Stump tag with TreeUid, FellAt and FallDir.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ForestData = require(ReplicatedStorage.Shared.ForestData)
local ForestLogic = require(ReplicatedStorage.Shared.ForestLogic)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local GrabLogic = require(ReplicatedStorage.Shared.GrabLogic)
local GrowLogic = require(ReplicatedStorage.Shared.GrowLogic)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local SectionLogic = require(ReplicatedStorage.Shared.SectionLogic)
local TreeArt = require(ReplicatedStorage.Shared.Art.TreeArt)
local TreeGen = require(ReplicatedStorage.Shared.TreeGen)
local TreeLogic = require(ReplicatedStorage.Shared.TreeLogic)
local Tune = require(ReplicatedStorage.Shared.Tune)
local Util = require(ReplicatedStorage.Shared.Util)
local VehicleLogic = require(ReplicatedStorage.Shared.VehicleLogic)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local GrabService = require(script.Parent.GrabService)
local RateLimiter = require(script.Parent.RateLimiter)
local WoodService = require(script.Parent.WoodService)

type WoodDef = WoodData.WoodDef
type Cut = SectionLogic.Cut

local SectionTrees = {}

SectionTrees.TreeTag = "Tree"
SectionTrees.StumpTag = "Stump"
SectionTrees.GhostRetry = 2 -- seconds between checks while something stands where a tree came back
SectionTrees.MaxHold = 240 -- seconds: HoldRegrow never keeps a stub longer than this from now
SectionTrees.ElderStubSec = TreeLogic.FallTime + 8 -- an Elder's stub goes this soon
SectionTrees.DeadBark = Color3.fromRGB(43, 38, 36) -- a dead tree's bark
SectionTrees.DeadGlow = Color3.fromRGB(74, 90, 120) -- and its glow, gone dull blue
SectionTrees.HeadUp = 1.5 -- studs from the root part to the eyes, without a Head
SectionTrees.SightSlack = 0.3 -- studs short of the hit point the sight line may stop
SectionTrees.SightNear = 1.5 -- a sight line ending this near the hit point, on the same tree, is clear

-- What a part looked like before the tree was hidden.
type PartState = { transparency: number, collide: boolean, query: boolean }

-- A site's tree. The first block is TreeService's TreeRecord, field for
-- field (ForestService, WeatherService and QuestService read those); the
-- rest is the section tree's own.
export type TreeRecord = {
	uid: string,
	model: Model,
	def: WoodDef,
	size: TreeLogic.SizeClass, -- name small | normal | large | elder; scale = the v2 scale
	maxHp: number, -- the damage that cuts through its base (for anything that shows HP)
	hp: number,
	alive: boolean, -- standing, grown past a sapling, awake, not dead: it can be cut
	pivot: CFrame, -- its PrimaryPart at rest (HomePivot)
	base: Vector3, -- the ground point under the trunk
	radius: number, -- half the trunk's thickness
	parts: { [BasePart]: PartState },
	effects: { [Instance]: boolean },
	felled: boolean, -- down (a stub, or nothing after a death) and waiting to regrow
	dormant: boolean,
	stump: Model?, -- the stub (the tree's own model) while felled
	stumpParts: { [BasePart]: PartState }?,
	ghost: boolean,
	regrowAt: number?,
	heldUntil: number?,
	seed: number,
	planterId: number?,
	damageBy: { [number]: number }, -- damage each player has done to this growth
	temporary: boolean, -- an Elder: gone once felled or faded
	growth: number, -- counts growths (fellings, deaths): stale work checks it
	-- The section tree:
	cuts: { [number]: { Cut } }, -- cuts in progress, by section id
	marks: { [Cut]: WoodService.Mark },
	nodes: { [number]: WoodService.Node }, -- its sections' links
	sections: { [number]: BasePart },
	depth: { [number]: number },
	nextId: number,
	trunkSegments: number,
	skel: TreeGen.Skeleton, -- the mature tree
	scale: number,
	elder: boolean,
	homeCf: CFrame, -- the base, turned the site's way
	stage: number, -- 0 = a sapling ... 1 = mature
	bornAt: number, -- clock time it sprouted
	life: number, -- seconds it lives
	cut: boolean, -- someone has cut it: it stops growing
	preDead: boolean, -- its leaves have dropped
	dead: boolean, -- dead and sinking
	deadUntil: number?, -- when its sinking model goes
	builds: number, -- how many models it has had (names)
}

export type SpawnOptions = {
	seed: number?,
	size: TreeLogic.SizeClass?, -- an Elder passes ForestLogic.ElderSize (name "elder")
	planterId: number?,
	temporary: boolean?,
	boot: boolean?, -- a site planted at server start: GrowLogic.BootAge
	stage: number?, -- start at this stage (0 sapling ... 1 mature; default mature)
}

export type RegrowOptions = { stage: number? } -- 1: back mature at once (a planted Heartseed)

-- What GameServer gives it (seams the specs fill in).
export type Deps = {
	notify: (Player, string) -> (),
	worldFx: RemoteEvent?,
	getAxe: (Player) -> ItemCatalog.AxeDef?,
	canChop: (Player, WoodDef) -> (boolean, string?),
	swingDue: (Player) -> number, -- when the next swing is due (os.clock), shared with MineNode
	setSwingDue: (Player, number) -> (),
	clock: (() -> number)?,
	manual: boolean?, -- specs: no growth loop, call GrowTick by hand
}

local trees: { [string]: TreeRecord } = {}
local byModel: { [Model]: TreeRecord } = {}
local counters: { [string]: number } = {}
local deps: Deps? = nil
local clock: () -> number = os.clock
local started = false
local makeSolid: (rec: TreeRecord) -> ()

-- Hooks, assigned like TreeService's (the forest systems, QuestService,
-- GameServer).
SectionTrees.OnFelled = nil :: ((player: Player, rec: TreeRecord, pieceUids: { string }, fallDir: Vector3) -> ())?
SectionTrees.OnRegrown = nil :: ((rec: TreeRecord) -> ())?
SectionTrees.StumpHold = nil :: ((feller: Player) -> number)?
SectionTrees.LogMultiplier = nil :: ((Player) -> number)?
-- v2 only: every piece a cut frees from a standing tree (limbs and the
-- felled trunk), before OnFelled; and every new model of a tree (a growth
-- stage, a regrow), before it's parented (decorations go on here).
SectionTrees.OnPieceFreed = nil :: ((cutter: Player, rec: TreeRecord, piece: WoodService.Piece) -> ())?
SectionTrees.OnRebuilt = nil :: ((rec: TreeRecord) -> ())?
-- GameServer's: the felling's stats, quest, daily and milestone events, and
-- every accepted swing.
export type Hooks = {
	onFelled: ((feller: Player, rec: TreeRecord) -> ())?,
	onSwing: ((player: Player, woodId: string) -> ())?,
}
SectionTrees.Hooks = {} :: Hooks

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local folders: { [string]: Instance } = {}
local function getFolder(name: string): Instance
	local cached = folders[name]
	if cached and cached.Parent then
		return cached
	end
	local map = workspace:WaitForChild("TimberlineMap", 30)
	assert(map, "[SectionTrees] TimberlineMap not found")
	local existing = map:FindFirstChild(name)
	if existing then
		folders[name] = existing
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = map
	folders[name] = folder
	return folder
end

local function serverTime(): number
	return workspace:GetServerTimeNow()
end

local function isHere(userId: number): boolean
	return Players:GetPlayerByUserId(userId) ~= nil
end

local function notify(player: Player, message: string?)
	local d = deps
	if d and message then
		d.notify(player, message)
	end
end

local function finite(v: Vector3): boolean
	return VehicleLogic.Finite(v)
end

-- The parts of a model (and its lights and particles), as they look now.
local function snapshot(model: Model): ({ [BasePart]: PartState }, { [Instance]: boolean })
	local parts: { [BasePart]: PartState } = {}
	local effects: { [Instance]: boolean } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			parts[d] = { transparency = d.Transparency, collide = d.CanCollide, query = d.CanQuery }
		elseif d:IsA("Light") or d:IsA("ParticleEmitter") then
			effects[d] = (d :: any).Enabled
		end
	end
	return parts, effects
end

local function showParts(parts: { [BasePart]: PartState }, visible: boolean)
	for part, state in pairs(parts) do
		if part.Parent == nil then
			continue
		end
		part.Transparency = if visible then state.transparency else 1
		part.CanTouch = false
		if visible then
			part.CanQuery = state.query
			part.CanCollide = state.collide
		else
			part.CanCollide = false -- before CanQuery can go false
			part.CanQuery = false
		end
	end
end

local function setVisible(rec: TreeRecord, visible: boolean)
	showParts(rec.parts, visible)
	for effect, enabled in pairs(rec.effects) do
		if effect.Parent ~= nil and (effect:IsA("Light") or effect:IsA("ParticleEmitter")) then
			(effect :: any).Enabled = visible and enabled
		end
	end
end

local function setSolid(rec: TreeRecord, solid: boolean)
	for part, state in pairs(rec.parts) do
		if part.Parent ~= nil then
			part.CanCollide = solid and state.collide
		end
	end
end

-- True when a truck or someone's character is in the way of the tree's
-- solid parts, so making them solid now would trap or fling them.
local function blocked(rec: TreeRecord): boolean
	local include: { Instance } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(include, player.Character)
		end
	end
	for _, truck in ipairs(CollectionService:GetTagged("Truck")) do
		table.insert(include, truck)
	end
	if #include == 0 then
		return false
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	params.RespectCanCollide = true
	params.MaxParts = 1
	for part, state in pairs(rec.parts) do
		if state.collide and part.Parent ~= nil then
			if #workspace:GetPartBoundsInBox(part.CFrame, part.Size + Vector3.one, params) > 0 then
				return true
			end
		end
	end
	return false
end

-- Solid, or a ghost while something is in the way (see the header).
makeSolid = function(rec: TreeRecord)
	if not blocked(rec) then
		rec.ghost = false
		setSolid(rec, true)
		return
	end
	setSolid(rec, false)
	if rec.ghost then
		return -- already waiting
	end
	rec.ghost = true
	local model = rec.model
	local function retry()
		if trees[rec.uid] ~= rec or rec.model ~= model or not rec.ghost or rec.dormant then
			return
		end
		if blocked(rec) then
			task.delay(SectionTrees.GhostRetry, retry)
			return
		end
		rec.ghost = false
		setSolid(rec, true)
	end
	task.delay(SectionTrees.GhostRetry, retry)
end

local function canBeCut(rec: TreeRecord): boolean
	return not rec.felled and not rec.dormant and not rec.dead and rec.stage > 0
end

local function refreshAlive(rec: TreeRecord)
	rec.alive = canBeCut(rec)
end

---------------------------------------------------------------------------
-- Building a tree's model
---------------------------------------------------------------------------

-- Section ids, links and depths from a skeleton.
local function readSkeleton(rec: TreeRecord, skel: TreeGen.Skeleton, model: Model)
	rec.nodes = {}
	rec.depth = {}
	rec.sections = {}
	for _, sec in ipairs(skel.sections) do
		rec.nodes[sec.id] = { parent = sec.parent, children = table.clone(sec.children) }
		rec.depth[sec.id] = sec.depth
	end
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") and d.Name == "Section" then
			local id = d:GetAttribute("Section")
			if type(id) == "number" then
				rec.sections[id] = d
			end
		end
	end
	rec.nextId = #skel.sections + 1
	rec.trunkSegments = skel.trunkSegments
end

-- The top of the trunk (its last trunk section), in world space.
local function trunkTop(rec: TreeRecord): Vector3?
	local best: BasePart? = nil
	local bestDepth = -1
	for id, part in pairs(rec.sections) do
		local depth = rec.depth[id] or 0
		if depth < rec.trunkSegments and depth > bestDepth then
			best, bestDepth = part, depth
		end
	end
	if not best then
		return nil
	end
	return (best.CFrame * CFrame.new(0, best.Size.Y / 2, 0)).Position
end

-- Builds (or rebuilds) the tree's model at its stage, swapping it in for
-- the old one. `grew`: it grew (the clients' regrow spring).
local function rebuild(rec: TreeRecord, grew: boolean)
	local def = rec.def
	local model: Model
	local skel: TreeGen.Skeleton? = nil
	if rec.stage <= 0 then
		model = TreeArt.GrowingSapling(def, rec.seed, GrowLogic.SaplingGrowth)
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		model:AddTag(SectionTrees.TreeTag)
		model:SetAttribute("WoodId", def.id)
		model:SetAttribute("Seed", rec.seed)
		model:SetAttribute("Stage", 0)
		model:SetAttribute("Scale", rec.scale)
		model:SetAttribute("Elder", rec.elder)
		model:SetAttribute("Felled", false)
		model:SetAttribute("Dormant", false)
		model:SetAttribute("PlanterId", rec.planterId or 0)
		model:SetAttribute("Sapling", true)
	else
		local staged = TreeGen.AtStage(rec.skel, rec.stage)
		skel = staged
		model = TreeArt.FromSkeleton(def, staged, { uid = rec.uid, planterId = rec.planterId })
	end
	rec.builds += 1
	counters[def.id] = (counters[def.id] or 0) + 1
	model.Name = string.format("Tree_%s_%d", def.id, counters[def.id])
	model:SetAttribute("Uid", rec.uid)
	Kit.placeAt(model, rec.homeCf)
	if skel then
		readSkeleton(rec, skel, model)
	else
		rec.nodes, rec.depth, rec.sections = {}, {}, {}
		rec.nextId, rec.trunkSegments = 1, 0
	end
	local pivot = model:GetPivot()
	rec.pivot = pivot
	model:SetAttribute("HomePivot", pivot)
	local first = rec.sections[1]
	local thickness = if first then math.min(first.Size.X, first.Size.Z) else 0.4
	rec.radius = thickness / 2
	local hardness = if def.v2 then def.v2.hardness else def.hardness
	rec.maxHp = SectionLogic.Required(hardness, thickness, thickness)
	rec.hp = rec.maxHp
	local top = trunkTop(rec)
	model:SetAttribute("SwayTop", top)
	model:SetAttribute("TrunkRadius", rec.radius)
	if grew then
		model:SetAttribute("GrewAt", serverTime())
	end
	if rec.dormant then
		model:SetAttribute("Dormant", true)
	end
	local old = rec.model
	rec.model = model
	rec.cuts, rec.marks = {}, {}
	rec.parts, rec.effects = snapshot(model)
	rec.stump, rec.stumpParts = nil, nil
	byModel[model] = rec
	local onRebuilt = SectionTrees.OnRebuilt
	if onRebuilt then
		local ok, err = pcall(function(): any
			onRebuilt(rec)
			return nil
		end)
		if not ok then
			warn("[SectionTrees] OnRebuilt failed: " .. tostring(err))
		end
	end
	if rec.dormant then
		setVisible(rec, false)
	end
	model.Parent = getFolder("Trees")
	if old and old ~= model then
		byModel[old] = nil
		old:Destroy()
	end
	refreshAlive(rec)
	if not rec.dormant and rec.stage > 0 then
		makeSolid(rec)
	end
end

local function sizeClass(name: string, scale: number): TreeLogic.SizeClass
	return { name = name, scale = scale, hpMul = 1, logDelta = 0, weight = 0 }
end

---------------------------------------------------------------------------
-- Public: TreeService's API
---------------------------------------------------------------------------

-- Plants a site's tree on the ground at `cframe` (its position is the
-- ground point under the trunk). See SpawnOptions. Returns its Model.
function SectionTrees.SpawnTree(woodId: string, cframe: CFrame, options: SpawnOptions?): Model
	local def = WoodData.Get(woodId)
	assert(def, "[SectionTrees] Unknown wood: " .. tostring(woodId))
	local opts: SpawnOptions = options or {}
	local pos = cframe.Position
	local seed, sizeName, scale, yaw = GrowLogic.Site(pos, opts.seed)
	local elder = false
	if opts.size then
		sizeName = opts.size.name
		elder = sizeName == "elder"
		scale = if elder then ForestData.Elder.scale else TreeGen.ScaleFor(sizeName)
	end
	local skel = TreeGen.Skeleton(woodId, seed, scale, { elder = elder })
	local uid = Util.guid()
	local now = clock()
	local growth = 0
	local life = GrowLogic.Lifespan(def, seed, growth)
	local growSec = GrowLogic.GrowSec(def)
	local age: number
	if opts.stage ~= nil then
		age = GrowLogic.StageStartsAt(opts.stage, growSec)
	elseif opts.boot and not opts.temporary then
		age = GrowLogic.BootAge(def, seed, life)
	else
		age = growSec
	end
	local rec: TreeRecord = {
		uid = uid,
		model = nil :: any, -- rebuild sets it
		def = def,
		size = sizeClass(sizeName, scale),
		maxHp = 1,
		hp = 1,
		alive = false,
		pivot = CFrame.new(pos),
		base = pos,
		radius = 1,
		parts = {},
		effects = {},
		felled = false,
		dormant = false,
		stump = nil,
		stumpParts = nil,
		ghost = false,
		regrowAt = nil,
		heldUntil = nil,
		seed = seed,
		planterId = opts.planterId,
		damageBy = {},
		temporary = opts.temporary == true,
		growth = growth,
		cuts = {},
		marks = {},
		nodes = {},
		sections = {},
		depth = {},
		nextId = 1,
		trunkSegments = 0,
		skel = skel,
		scale = scale,
		elder = elder,
		homeCf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0),
		stage = GrowLogic.StageAt(age, growSec),
		bornAt = now - age,
		life = life,
		cut = false,
		preDead = false,
		dead = false,
		deadUntil = nil,
		builds = 0,
	}
	trees[uid] = rec
	rebuild(rec, false)
	return rec.model
end

-- The parts of a tree that are leaves (they drop before it dies).
local LEAF_NAMES: { [string]: boolean } = {
	Leaves = true,
	Frond = true,
	Facet = true,
	Coconut = true,
	Pod = true,
	PodStem = true,
}
local function dropLeaves(rec: TreeRecord)
	local points: { Vector3 } = {}
	local count = 0
	for _, c in ipairs(rec.model:GetChildren()) do
		local leaf = (c:IsA("BasePart") and LEAF_NAMES[c.Name]) or (c:IsA("Model") and c.Name == "Tier")
		if leaf then
			count += 1
			local at: Vector3? = nil
			if c:IsA("BasePart") then
				at = c.CFrame.Position
			else
				local p = c:FindFirstChildWhichIsA("BasePart")
				at = if p then p.CFrame.Position else nil
			end
			if at and #points < WoodService.LeafPoints and count % 2 == 1 then
				table.insert(points, at)
			end
			for _, d in ipairs(c:GetDescendants()) do
				rec.parts[d :: any] = nil
				rec.effects[d] = nil
			end
			if c:IsA("BasePart") then
				rec.parts[c] = nil
			end
			c:Destroy()
		end
	end
	rec.preDead = true
	rec.model:SetAttribute("PreDead", true)
	if #points > 0 and not rec.dormant then
		WoodService.FireNear(points[1], "LeafFall", { points = points, woodId = rec.def.id, count = count })
	end
end

-- Dead: dark, dull, nothing to cut; clients sink it, then it goes.
local function die(rec: TreeRecord)
	rec.dead = true
	rec.alive = false
	local model = rec.model
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Material == Enum.Material.Neon then
				d.Material = Enum.Material.SmoothPlastic
				d.Color = SectionTrees.DeadGlow
			elseif d.Name == "Section" or d.Name == "Root" or d.Name == "Stem" then
				d.Color = SectionTrees.DeadBark
			end
			CollectionService:RemoveTag(d, WoodService.SectionTag)
			d.CanCollide = false
			d.CanQuery = false
		elseif d:IsA("Light") or d:IsA("ParticleEmitter") then
			(d :: any).Enabled = false
		end
	end
	for id in pairs(rec.cuts) do
		WoodService.ClearCuts(rec, id)
	end
	model:SetAttribute("Dead", true)
	model:SetAttribute("DeadAt", serverTime())
	rec.deadUntil = clock() + (Tune.Get("DeadSinkSec") :: number)
end

-- Removes a tree for good: an Elder that was felled or faded. It sinks
-- the way a dead tree does (clients), then goes; its record goes now.
function SectionTrees.Remove(uid: string)
	local rec = trees[uid]
	if not rec then
		return
	end
	trees[uid] = nil
	local model = rec.model
	if not rec.dead then
		die(rec)
	end
	task.delay(Tune.Get("DeadSinkSec") :: number, function()
		byModel[model] = nil
		model:Destroy()
	end)
end

-- Adds parts to a standing tree (bark clues, a storm's glow, an Elder's
-- aura) and remembers them, so hiding it includes them. As TreeService's.
function SectionTrees.Decorate(uid: string, build: (Model, TreeRecord) -> ())
	local rec = trees[uid]
	if not rec then
		return
	end
	build(rec.model, rec)
	local visible = not rec.dormant
	for _, d in ipairs(rec.model:GetDescendants()) do
		if d:IsA("BasePart") and rec.parts[d] == nil then
			rec.parts[d] = { transparency = d.Transparency, collide = d.CanCollide, query = d.CanQuery }
			if not visible then
				d.Transparency = 1
				d.CanCollide = false
				d.CanQuery = false
			elseif rec.ghost then
				d.CanCollide = false
			end
		elseif (d:IsA("Light") or d:IsA("ParticleEmitter")) and rec.effects[d] == nil then
			rec.effects[d] = (d :: any).Enabled
			if not visible then
				(d :: any).Enabled = false
			end
		end
	end
end

-- Forgets parts removed from a tree (a storm's glow that faded).
function SectionTrees.Forget(uid: string, inst: Instance)
	local rec = trees[uid]
	if not rec then
		return
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			rec.parts[d] = nil
		end
		rec.effects[d] = nil
	end
	if inst:IsA("BasePart") then
		rec.parts[inst] = nil
	end
	rec.effects[inst] = nil
end

-- Keeps a felled tree's stub at least `seconds` more (at most MaxHold)
-- before the site regrows on its own; never sooner. As TreeService's.
function SectionTrees.HoldRegrow(uid: string, seconds: number)
	local rec = trees[uid]
	local at = if rec and rec.felled and not rec.temporary then rec.regrowAt else nil
	if not rec or not at or seconds ~= seconds then
		return
	end
	local untilAt = math.max(rec.heldUntil or 0, clock() + math.clamp(seconds, 0, SectionTrees.MaxHold))
	rec.heldUntil = untilAt
	rec.regrowAt = math.max(at, untilAt)
end

-- Brings a felled site back: a sapling that grows up over the wood's
-- growSec, or (opts.stage = 1, a planted Heartseed) mature at once.
-- `planterId` marks who planted it (nil = it grew back wild).
function SectionTrees.Regrow(uid: string, planterId: number?, opts: RegrowOptions?)
	local rec = trees[uid]
	if not rec or not rec.felled then
		return
	end
	local stage = math.clamp(if opts and opts.stage then opts.stage else 0, 0, 1)
	rec.planterId = planterId
	rec.felled = false
	rec.regrowAt = nil
	rec.heldUntil = nil
	rec.damageBy = {}
	rec.cut = false
	rec.preDead = false
	rec.dead = false
	rec.deadUntil = nil
	rec.ghost = false
	local growSec = GrowLogic.GrowSec(rec.def)
	rec.life = GrowLogic.Lifespan(rec.def, rec.seed, rec.growth)
	rec.stage = GrowLogic.StageAt(GrowLogic.StageStartsAt(stage, growSec), growSec)
	rec.bornAt = clock() - GrowLogic.StageStartsAt(rec.stage, growSec)
	rebuild(rec, true)
	local onRegrown = SectionTrees.OnRegrown
	if onRegrown then
		task.spawn(onRegrown, rec)
	end
end

-- Hides (or brings back) every tree of a biome, e.g. the Gloam Hollow by
-- day. A tree that's down stays down; a half-cut one is whole again.
function SectionTrees.SetBiomeDormant(biomeId: string, dormant: boolean)
	for _, rec in pairs(trees) do
		if rec.def.biome == biomeId and rec.dormant ~= dormant then
			rec.dormant = dormant
			rec.model:SetAttribute("Dormant", dormant)
			if dormant then
				if not rec.felled and not rec.dead then
					for id in pairs(rec.cuts) do
						WoodService.ClearCuts(rec, id)
					end
					rec.damageBy = {}
				end
				rec.ghost = false
				setVisible(rec, false)
			else
				setVisible(rec, true)
				if not rec.felled and not rec.dead and rec.stage > 0 then
					makeSolid(rec) -- a truck may have parked on its spot by day
				end
			end
			refreshAlive(rec)
		end
	end
end

-- The wood of a tree that can be cut right now, or nil.
function SectionTrees.GetTreeWood(uid: string): WoodDef?
	local rec = trees[uid]
	return if rec and rec.alive then rec.def else nil
end

function SectionTrees.GetTree(uid: string): TreeRecord?
	return trees[uid]
end

function SectionTrees.AllTrees(): { [string]: TreeRecord }
	return trees
end

-- Seconds until a felled site grows back on its own (nil if it isn't
-- down, or never will: an Elder).
function SectionTrees.RegrowsIn(uid: string): number?
	local rec = trees[uid]
	local at = if rec and rec.felled then rec.regrowAt else nil
	return if at then math.max(0, at - clock()) else nil
end

-- The standing tree a part belongs to and the section it is (nil, nil if
-- it isn't a section of one).
function SectionTrees.FromPart(part: Instance): (TreeRecord?, number?)
	local model = part.Parent
	if not model or not model:IsA("Model") then
		return nil, nil
	end
	local rec = byModel[model]
	if not rec or rec.model ~= model then
		return nil, nil
	end
	local id = part:GetAttribute("Section")
	if type(id) ~= "number" or rec.sections[id] ~= part then
		return rec, nil
	end
	return rec, id
end

---------------------------------------------------------------------------
-- Cutting
---------------------------------------------------------------------------

local function fall(rec: TreeRecord, swinger: Player, dir: Vector3, pieceUid: string): Player
	rec.alive = false
	rec.felled = true
	rec.ghost = false
	rec.growth += 1
	local most = ForestLogic.Feller(rec.damageBy, swinger.UserId, isHere)
	local feller = Players:GetPlayerByUserId(most) or swinger
	local model = rec.model
	model:SetAttribute("Felled", true)
	model:SetAttribute("FellAt", serverTime())
	model:SetAttribute("FallDir", dir)
	model:SetAttribute("TreeUid", rec.uid)
	CollectionService:AddTag(model, SectionTrees.StumpTag)
	rec.stump = model
	rec.stumpParts = rec.parts
	if rec.temporary then
		rec.regrowAt = nil
		local growth = rec.growth
		task.delay(SectionTrees.ElderStubSec, function()
			if trees[rec.uid] == rec and rec.growth == growth then
				SectionTrees.Remove(rec.uid)
			end
		end)
	else
		rec.regrowAt = clock() + rec.def.respawnSec
		rec.heldUntil = nil
		local hold = SectionTrees.StumpHold
		if hold then
			local ok, seconds = pcall(hold, feller)
			if ok and type(seconds) == "number" and seconds > 0 then
				SectionTrees.HoldRegrow(rec.uid, seconds)
			elseif not ok then
				warn("[SectionTrees] StumpHold failed: " .. tostring(seconds))
			end
		end
	end
	local onFelled = SectionTrees.OnFelled
	if onFelled then
		task.spawn(onFelled, feller, rec, { pieceUid }, dir)
	end
	local hook = SectionTrees.Hooks.onFelled
	if hook then
		task.spawn(hook, feller, rec)
	end
	return feller
end

-- Section `sid` of a standing tree is cut through at `h`: everything above
-- the cut is one loose piece; through a trunk section the tree is felled.
-- Returns the piece and, for a felling, who it counts for.
local function split(rec: TreeRecord, player: Player, sid: number, hit: WoodService.Hit): (WoodService.Piece, Player?)
	local def = rec.def
	local part = rec.sections[sid]
	local depth = rec.depth[sid] or 0
	local felled = depth < rec.trunkSegments
	local newId = rec.nextId
	rec.nextId += 1
	WoodService.ClearCuts(rec, sid)
	local high = WoodService.SplitPart(part, hit.height, newId)
	-- Links: the new part takes the cut section's children.
	local node = rec.nodes[sid]
	local children = node.children
	node.children = {}
	rec.nodes[newId] = { parent = nil, children = children }
	for _, c in ipairs(children) do
		local child = rec.nodes[c]
		if child then
			child.parent = newId
		end
	end
	rec.sections[newId] = high
	rec.depth[newId] = depth
	local ids = WoodService.Reach(rec.nodes, newId)
	local stubFace = TreeArt.CutFace(def, part, true)
	TreeArt.CutFace(def, high, false)
	local pieceModel = WoodService.NewModel()
	WoodService.MoveSections(rec.model, pieceModel, ids)
	local nodes: { [number]: WoodService.Node } = {}
	local parts: { [number]: BasePart } = {}
	local cuts: { [number]: { Cut } } = {}
	local marks: { [Cut]: WoodService.Mark } = {}
	for id in pairs(ids) do
		nodes[id] = rec.nodes[id]
		parts[id] = rec.sections[id]
		local list = rec.cuts[id]
		if list then
			cuts[id] = list
			for _, c in ipairs(list) do
				marks[c] = rec.marks[c]
				rec.marks[c] = nil
			end
		end
		rec.cuts[id] = nil
		rec.nodes[id] = nil
		rec.sections[id] = nil
		rec.depth[id] = nil
	end
	for _, d in ipairs(pieceModel:GetDescendants()) do
		if d:IsA("BasePart") then
			rec.parts[d] = nil
		end
		rec.effects[d] = nil
	end
	rec.parts[stubFace] = { transparency = stubFace.Transparency, collide = false, query = false }
	-- Which way it goes: a trunk away from the cutter, a limb away from the tree.
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	local from = if hrp and hrp:IsA("BasePart") then hrp.Position else nil
	local dir: Vector3
	if felled then
		dir = TreeLogic.FallDirection(rec.base, from, (math.random() - 0.5) * 0.7)
	else
		local out = high.CFrame.Position - rec.base
		dir = Vector3.new(out.X, 0, out.Z)
		dir = if dir.Magnitude > 0.05 then dir.Unit else TreeLogic.FallDirection(rec.base, from, 0)
	end
	local ownerId = SectionLogic.Owner(hit.cut, player.UserId, isHere)
	local owner = Players:GetPlayerByUserId(ownerId) or player
	local boost = 1
	local multiplier = SectionTrees.LogMultiplier
	if multiplier then
		local ok, m = pcall(multiplier, owner)
		if ok and type(m) == "number" and m > 1 then
			boost = m
		end
	end
	local pivot = (part.CFrame * CFrame.new(0, part.Size.Y / 2, 0)).Position
	local piece = WoodService.Adopt(pieceModel, {
		woodId = def.id,
		nodes = nodes,
		parts = parts,
		cuts = cuts,
		marks = marks,
		nextId = rec.nextId,
		ownerId = ownerId,
		boost = boost,
		planterId = rec.planterId,
		treeUid = rec.uid,
		elder = rec.elder,
		fall = { cutter = player, dir = dir, felled = felled, pivot = pivot },
	})
	local freed = SectionTrees.OnPieceFreed
	if freed then
		local ok, err = pcall(function(): any
			freed(player, rec, piece)
			return nil
		end)
		if not ok then
			warn("[SectionTrees] OnPieceFreed failed: " .. tostring(err))
		end
	end
	local feller: Player? = nil
	if felled then
		feller = fall(rec, player, dir, piece.uid)
	end
	return piece, feller
end

export type SwingResult = {
	tree: TreeRecord?,
	piece: WoodService.Piece?,
	hit: WoodService.Hit?,
	freed: { WoodService.Piece },
	feller: Player?,
}

-- Applies one accepted swing to a standing tree's section.
local function cutStanding(
	player: Player,
	rec: TreeRecord,
	sid: number,
	hitPos: Vector3,
	normal: Vector3,
	damage: number
): SwingResult
	local part = rec.sections[sid]
	local hit = WoodService.ApplyHit(rec, rec.def, part, sid, hitPos, normal, damage, player.UserId)
	rec.damageBy[player.UserId] = (rec.damageBy[player.UserId] or 0) + damage
	rec.cut = true -- a tree that has been cut stops growing
	if sid == 1 then
		rec.hp = math.max(0, rec.maxHp - hit.cut.damage)
	end
	WoodService.FireNear(hitPos, "Cut", {
		part = part,
		pos = hitPos,
		normal = normal,
		woodId = rec.def.id,
		progress = hit.progress,
		userId = player.UserId,
		through = hit.through,
	})
	local result: SwingResult = { tree = rec, piece = nil, hit = hit, freed = {}, feller = nil }
	if hit.through then
		local piece, feller = split(rec, player, sid, hit)
		table.insert(result.freed, piece)
		result.feller = feller
	end
	return result
end

-- The eyes a swing is seen from.
local function eyeOf(char: Model, hrp: BasePart): Vector3
	local head = char:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.CFrame.Position
	end
	return hrp.Position + Vector3.new(0, SectionTrees.HeadUp, 0)
end

-- One sight line from the eyes to the hit point (leaves don't block it:
-- the ray is in collision group Wood): clear if it reaches the point, or
-- stops on the part swung at, or on the same tree or piece close to it.
local function canSee(char: Model, from: Vector3, hitPos: Vector3, part: BasePart): boolean
	local offset = hitPos - from
	local dist = offset.Magnitude
	if dist < 1e-3 then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	params.CollisionGroup = WoodService.WoodGroup
	local result = workspace:Raycast(from, offset.Unit * (dist + 0.75), params)
	if not result then
		return true
	end
	local hit = result.Instance
	if hit == part then
		return true
	end
	if (result.Position - from).Magnitude >= dist - SectionTrees.SightSlack then
		return true
	end
	local model = part.Parent
	if model and hit:IsDescendantOf(model) and (result.Position - hitPos).Magnitude <= SectionTrees.SightNear then
		return true
	end
	return false
end

-- The Chop remote (V2_PLAN.md §3d), checked in this order: the rate, the
-- arguments, a live character, the equipped axe, the swing schedule
-- (shared with MineNode; the axe's cooldown for this wood, with
-- SwingTolerance), a known section (a standing tree's or a loose
-- piece's), the reach (the axe's v2 range + RangeTolerance from the root
-- part to the hit), the hit inside the section's box (+0.6), a clear
-- sight line from the eyes, BiomeService.CanChop, damage > 0, and for a
-- loose piece GrabLogic.CanGrab. Returns whether it cut, and why not.
function SectionTrees.Chop(
	player: Player,
	part: unknown,
	hitPos: unknown,
	normal: unknown
): (boolean, string?, SwingResult?)
	local d = deps
	if not d then
		return false, "off", nil
	end
	if not RateLimiter.Allow(player, "Chop") then
		return false, "rate", nil
	end
	if typeof(part) ~= "Instance" or typeof(hitPos) ~= "Vector3" or typeof(normal) ~= "Vector3" then
		return false, "bad", nil
	end
	local inst = part :: Instance
	local at = hitPos :: Vector3
	local facing = normal :: Vector3
	if not inst:IsA("BasePart") or not finite(at) or not finite(facing) then
		return false, "bad", nil
	end
	local target = inst :: BasePart
	local char = player.Character
	local hrpInst = if char then char:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if not char or not hrpInst or not hrpInst:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return false, "dead", nil
	end
	local hrp = hrpInst :: BasePart
	local axe = d.getAxe(player)
	local stats = if axe then axe.v2 else nil
	if not axe or not stats then
		return false, "noAxe", nil
	end
	local now = clock()
	local due = d.swingDue(player)
	if now < due - GameConfig.SwingTolerance then
		return false, "cooldown", nil
	end
	-- What it is: a standing tree's section, or a loose piece's.
	local rec, sid = SectionTrees.FromPart(target)
	local piece: WoodService.Piece? = nil
	local def: WoodDef
	if rec and sid then
		if not canBeCut(rec) then
			return false, "gone", nil
		end
		def = rec.def
	else
		rec = nil
		local p = WoodService.FromPart(target)
		local pid = target:GetAttribute("Section")
		if not p or type(pid) ~= "number" or p.parts[pid] ~= target or p.dead or p.selling then
			return false, "unknown", nil
		end
		piece = p
		def = p.def
	end
	if (hrp.Position - at).Magnitude > stats.range + GameConfig.RangeTolerance then
		notify(player, SectionLogic.Message("far"))
		return false, "far", nil
	end
	if not SectionLogic.InBox(target.CFrame, target.Size, at) then
		return false, "bad", nil
	end
	if not canSee(char, eyeOf(char, hrp), at, target) then
		notify(player, SectionLogic.Message("noLOS"))
		return false, "noLOS", nil
	end
	local allowed, why = d.canChop(player, def)
	if not allowed then
		notify(player, why)
		return false, "biome", nil
	end
	local damage, cooldown = ItemCatalog.AxeStats(axe, def.id)
	if not damage or damage <= 0 then
		notify(player, SectionLogic.Message("tooHard"))
		WoodService.FireNear(at, "Clink", { pos = at, userId = player.UserId })
		return false, "tooHard", nil
	end
	local p = piece
	if p then
		local held = GrabService.HeldBy(p.model)
		local facts: GrabLogic.Facts = {
			userId = player.UserId,
			ownerId = p.ownerId,
			createdAt = p.createdAt,
			now = now,
			heldBy = if held then held.UserId else 0,
			dead = p.dead,
			selling = p.selling,
			elder = p.elder,
			shopItem = p.shopItem,
		}
		local ok, reason = GrabLogic.CanGrab(facts)
		if not ok then
			notify(player, GrabLogic.Message(reason, facts))
			return false, reason, nil
		end
	end
	d.setSwingDue(player, math.max(now, due) + (cooldown or stats.cooldown))
	local hook = SectionTrees.Hooks.onSwing
	if hook then
		task.spawn(hook, player, def.id)
	end
	if rec and sid then
		return true, nil, cutStanding(player, rec, sid, at, facing, damage)
	end
	local cutPiece = p :: WoodService.Piece
	local result = WoodService.CutPiece(player, cutPiece, target, at, facing, damage)
	return true,
		nil,
		{
			tree = nil,
			piece = cutPiece,
			hit = if result then result.hit else nil,
			freed = if result then result.pieces else {},
			feller = nil,
		}
end

---------------------------------------------------------------------------
-- Growth
---------------------------------------------------------------------------

-- When `rec` next changes, or nil if nothing is coming.
local function nextChange(rec: TreeRecord): number?
	if rec.dormant then
		return nil
	end
	if rec.dead then
		return rec.deadUntil
	end
	if rec.felled then
		if rec.temporary then
			return nil
		end
		return rec.regrowAt
	end
	if rec.temporary then
		return nil
	end
	local growSec = GrowLogic.GrowSec(rec.def)
	local candidates: { number } = {}
	if not rec.cut then
		local nextStage = GrowLogic.NextStage(rec.stage)
		if nextStage then
			table.insert(candidates, rec.bornAt + GrowLogic.StageStartsAt(nextStage, growSec))
		end
	end
	if not rec.preDead then
		table.insert(candidates, rec.bornAt + rec.life * GameConfig.PreDeadAt)
	end
	table.insert(candidates, rec.bornAt + rec.life)
	local soonest: number? = nil
	for _, t in ipairs(candidates) do
		if soonest == nil or t < soonest then
			soonest = t
		end
	end
	return soonest
end

-- Moves one tree on: regrows a stub, grows a stage, drops leaves, dies,
-- or clears a sunk tree away.
local function advance(rec: TreeRecord, now: number)
	if rec.dead then
		if rec.deadUntil and now >= rec.deadUntil then
			-- Sunk: the site is empty until it regrows.
			rec.deadUntil = nil
			byModel[rec.model] = nil
			rec.model:Destroy() -- kept as the record's model (no parent) until it regrows
			rec.parts, rec.effects = {}, {}
			rec.sections, rec.nodes, rec.depth = {}, {}, {}
			rec.dead = false
			rec.felled = true
			rec.alive = false
			rec.stump, rec.stumpParts = nil, nil
			rec.growth += 1
			rec.regrowAt = now + rec.def.respawnSec
			rec.heldUntil = nil
		end
		return
	end
	if rec.felled then
		if rec.regrowAt and now >= rec.regrowAt then
			SectionTrees.Regrow(rec.uid)
		end
		return
	end
	local age = now - rec.bornAt
	local phase = GrowLogic.PhaseAt(age, rec.life)
	if phase == "dead" then
		if not rec.preDead then
			dropLeaves(rec)
		end
		die(rec)
		return
	end
	if not rec.cut then
		local stage = GrowLogic.StageAt(age, GrowLogic.GrowSec(rec.def))
		if stage > rec.stage then
			rec.stage = stage
			rebuild(rec, true)
		end
	end
	if phase == "preDead" and not rec.preDead then
		dropLeaves(rec)
	end
end

-- One growth tick: at most TreesPerGrowTick trees whose change is due.
-- Returns their uids (specs).
function SectionTrees.GrowTick(now: number): { string }
	local due: { GrowLogic.Due } = {}
	for uid, rec in pairs(trees) do
		local at = nextChange(rec)
		if at and at <= now then
			table.insert(due, { uid = uid, at = at })
		end
	end
	local picked = GrowLogic.TakeDue(due, now, Tune.Get("TreesPerGrowTick") :: number)
	for _, uid in ipairs(picked) do
		local rec = trees[uid]
		if rec then
			local ok, err = pcall(function(): any
				advance(rec, now)
				return nil
			end)
			if not ok then
				warn("[SectionTrees] growing " .. rec.def.id .. " failed: " .. tostring(err))
			end
		end
	end
	return picked
end

-- The v2 wood collision groups (WoodService.RegisterGroups), registered
-- before any tree is built: MapBuilder calls this first.
function SectionTrees.RegisterGroups(): boolean
	return WoodService.RegisterGroups()
end

-- How many sites there are and how many trees stand (the boot line).
function SectionTrees.Counts(): (number, number)
	local sites, standing = 0, 0
	for _, rec in pairs(trees) do
		sites += 1
		if not rec.felled and not rec.dead then
			standing += 1
		end
	end
	return sites, standing
end

-- Starts the Chop handling and the growth tick (the v2 loop only:
-- GameServer checks).
function SectionTrees.Init(newDeps: Deps)
	deps = newDeps
	clock = newDeps.clock or os.clock
	if started then
		return
	end
	started = true
	local sites, standing = SectionTrees.Counts()
	print(string.format("[SectionTrees] %d trees on %d sites", standing, sites))
	if newDeps.manual then
		return
	end
	task.spawn(function()
		while true do
			task.wait(Tune.Get("GrowTickSec") :: number)
			local ok, err = pcall(SectionTrees.GrowTick, clock())
			if not ok then
				warn("[SectionTrees] growth tick failed: " .. tostring(err))
			end
		end
	end)
end

-- For the specs: a clock before Init (MapBuilder plants before GameServer).
function SectionTrees._useClock(fn: () -> number)
	clock = fn
end

-- For the specs: forget everything.
function SectionTrees._reset()
	table.clear(trees)
	table.clear(byModel)
	table.clear(counters)
	table.clear(folders)
	deps = nil
	started = false
	clock = os.clock
	SectionTrees.OnFelled = nil
	SectionTrees.OnRegrown = nil
	SectionTrees.StumpHold = nil
	SectionTrees.LogMultiplier = nil
	SectionTrees.OnPieceFreed = nil
	SectionTrees.OnRebuilt = nil
	SectionTrees.Hooks = {}
end

return SectionTrees
