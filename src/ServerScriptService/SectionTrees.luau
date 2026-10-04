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
--     whoever did most of that cut (SectionLogic.Owner). A cut through the
--     root (depth 0) frees that whole section and everything on it: no
--     sliver, no stump. Through a trunk section the tree is felled
--     (OnFelled once). The rooted base, if any is left, stays cuttable.
--     When nothing rooted is left the record is an open slot and grows
--     back later at a new spot in its zone. Cutting only limbs ("limbing")
--     never fells it.
--   * Felled = the first cut through a trunk section: OnFelled(feller,
--     rec, pieceUids, fallDir) fires once. The loose piece falls; the
--     standing model is not tagged Stump and is not marked Felled, so the
--     base can still be cut. The first cut claims a tree, and nobody else
--     may cut it while the claimer is in the server and has hit it within
--     GameConfig.TreeClaimSec (SectionLogic.ClaimBlocks). A felling clears
--     the claim. An Elder is everyone's: its feller is ForestLogic.Feller
--     over its damageBy, a piece's owner whoever did most of that cut
--     (SectionLogic.Owner). An Elder leaves no slot.
--   * Night-only woods (the Gloam Hollow): SetBiomeDormant hides a biome's
--     trees and stubs by day (a half-cut tree is whole again tomorrow
--     night) and brings them back at night (WorldClock).
--   * A tree that comes back solid (regrown, grown a stage, woken) where a
--     truck, loose Wood, a placed plank, or someone stands is a ghost (no
--     collisions) until the spot is clear, checked every GhostRetry seconds.
-- Model contract (CutController, WoodFX, WindSway, CanopyFade, ForestUI):
-- tag Tree, in TimberlineMap/Trees, Atomic; FromSkeleton's parts and
-- attributes (WoodId, Seed, Stage, Scale, Elder, Felled, Dormant,
-- Uid) plus HomePivot (its PrimaryPart's CFrame), SwayTop (the
-- top of its trunk, where the crown rocks about), Sapling (true while a
-- sapling), GrewAt (server time it last grew: the regrow spring),
-- PreDead, Dead and DeadAt (server time: the death sink), HP (1 while it
-- can be cut, else 0). A loose piece carries FellAt and FallDir; the
-- standing model is not tagged Stump.

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
local TerrainGen = require(ReplicatedStorage.Shared.World.TerrainGen)
local TreeFill = require(ReplicatedStorage.Shared.World.TreeFill)
local WorldPlan = require(ReplicatedStorage.Shared.World.WorldPlan)
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
	damageBy: { [number]: number }, -- damage each player has done to this growth
	claim: SectionLogic.Claim?, -- who is cutting it (SectionLogic.ClaimBlocks), nil = nobody
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
	zone: WorldPlan.TreeZone?, -- where it may grow back
	cap: number?, -- boot count for this zone (and wood, except Wild)
	slot: boolean, -- nothing rooted is left: waiting on regrowAt
}

export type SpawnOptions = {
	seed: number?,
	size: TreeLogic.SizeClass?, -- an Elder passes ForestLogic.ElderSize (name "elder")
	temporary: boolean?,
	boot: boolean?, -- a site planted at server start: GrowLogic.BootAge
	stage: number?, -- start at this stage (0 sapling ... 1 mature; default mature)
	zone: WorldPlan.TreeZone?,
	cap: number?,
}

export type RegrowOptions = { stage: number? } -- 1: back mature at once

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
local openSlot: (rec: TreeRecord, now: number) -> ()
local tryRegrow: (rec: TreeRecord, now: number) -> ()

-- Specs set this to a 0..1 roll. Live servers use math.random.
SectionTrees._roll = nil :: (() -> number)?

-- A missed regrow (no legal spot, or the zone is over its cap) waits this
-- long instead of trying again on the next tick.
SectionTrees.RetrySec = 30

local function unit(): number
	local roll = SectionTrees._roll
	if roll then
		return roll()
	end
	return math.random()
end

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

-- The tree each player is cutting (their claim): one at a time, so nobody
-- can lock up a grove by hitting every tree once.
local claimOf: { [number]: TreeRecord } = {}

-- Sets (or clears) who is cutting `rec`, mirrored on its model as
-- ClaimedBy (a UserId, 0 = nobody) and ClaimedAt (server time of their
-- last hit) for anything on the client that wants to show it. A player's
-- new claim ends their old one.
local function setClaim(rec: TreeRecord, claim: SectionLogic.Claim?)
	local old = rec.claim
	if old and claimOf[old.userId] == rec then
		claimOf[old.userId] = nil
	end
	if claim then
		local previous = claimOf[claim.userId]
		if previous and previous ~= rec and previous.claim and previous.claim.userId == claim.userId then
			previous.claim = nil
			if previous.model.Parent ~= nil then
				previous.model:SetAttribute("ClaimedBy", 0)
				previous.model:SetAttribute("ClaimedAt", nil)
			end
		end
		claimOf[claim.userId] = rec
	end
	rec.claim = claim
	local model = rec.model
	if model.Parent ~= nil then
		model:SetAttribute("ClaimedBy", if claim then claim.userId else 0)
		model:SetAttribute("ClaimedAt", if claim then serverTime() else nil)
	end
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

-- True when a truck, loose Wood, a placed plank, or someone's character
-- is in the way of the tree's solid parts, so making them solid now would
-- trap or fling them.
local function blocked(rec: TreeRecord): boolean
	local include: { Instance } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(include, player.Character)
		end
	end
	for _, tag in ipairs({ "Truck", "Wood", "PlacedItem" }) do
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do
			table.insert(include, inst)
		end
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

-- A section still parented to the standing model is rooted.
local function rootedLeft(rec: TreeRecord): boolean
	for _, part in pairs(rec.sections) do
		if part.Parent ~= nil then
			return true
		end
	end
	return false
end

-- Felled is fine while a rooted base is still there. Dying trees are not.
local function canBeCut(rec: TreeRecord): boolean
	if rec.dormant or rec.dead or rec.slot or rec.stage <= 0 then
		return false
	end
	if rec.felled and not rootedLeft(rec) then
		return false
	end
	return true
end

-- The model's HP attribute mirrors it, 1 or 0, for code that finds a
-- standing tree that way (QuestUI's beacon; TreeUI shows no bar without
-- MaxHP).
local function setAlive(rec: TreeRecord, alive: boolean)
	rec.alive = alive
	rec.model:SetAttribute("HP", if alive then 1 else 0)
end

local function refreshAlive(rec: TreeRecord)
	setAlive(rec, canBeCut(rec))
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
	-- Descendants, not only direct children: a section grouped under a
	-- folder (a box trunk) is still that section.
	for _, d in ipairs(model:GetDescendants()) do
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
		model:SetAttribute("Sapling", true)
		if def.id == WoodData.LanternId then
			model:AddTag("Lanternwood")
			model:SetAttribute("NightHost", "tree")
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and (d.Name == "Leaves" or d.Name == "Facet" or d.Name == "CoreBand") then
					d:SetAttribute("NightGlow", true)
				end
			end
		end
	else
		local staged = TreeGen.AtStage(rec.skel, rec.stage)
		skel = staged
		model = TreeArt.FromSkeleton(def, staged, { uid = rec.uid })
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
		if old.Parent ~= nil then
			old:Destroy()
		end
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
function SectionTrees.SpawnTree(woodId: string, cframe: CFrame, options: SpawnOptions?): Model?
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
		damageBy = {},
		claim = nil,
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
		zone = opts.zone,
		cap = opts.cap or (if opts.zone then opts.zone.cap else nil),
		slot = false,
	}
	trees[uid] = rec
	rebuild(rec, false)
	-- A trunk whose saved spot sits in a widened haul road keeps that index
	-- and does not stand there. The first regrow is due now; a miss waits
	-- RetrySec.
	if opts.boot and TreeFill.InHaulLane(pos.X, pos.Z) then
		openSlot(rec, now)
		rec.regrowAt = now
		return nil
	end
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
	setAlive(rec, false)
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

-- Keeps an open slot at least `seconds` more (at most MaxHold) before it
-- grows back; never sooner.
function SectionTrees.HoldRegrow(uid: string, seconds: number)
	local rec = trees[uid]
	local at = if rec and rec.slot then rec.regrowAt else nil
	if not rec or not at or seconds ~= seconds then
		return
	end
	local untilAt = math.max(rec.heldUntil or 0, clock() + math.clamp(seconds, 0, SectionTrees.MaxHold))
	rec.heldUntil = untilAt
	rec.regrowAt = math.max(at, untilAt)
end

-- Grows an open slot back, at a new spot in its zone. See tryRegrow.
function SectionTrees.Regrow(uid: string, _opts: RegrowOptions?)
	local rec = trees[uid]
	if not rec or not rec.slot then
		return
	end
	tryRegrow(rec, clock())
end

-- Hides (or brings back) every tree of a biome, e.g. the Gloam Hollow by
-- day. A tree that's down stays down; a half-cut one is whole again.
function SectionTrees.SetBiomeDormant(biomeId: string, dormant: boolean)
	for _, rec in pairs(trees) do
		if rec.def.biome == biomeId and rec.dormant ~= dormant and rec.model.Parent ~= nil then
			rec.dormant = dormant
			rec.model:SetAttribute("Dormant", dormant)
			if dormant then
				if not rec.slot and not rec.dead then
					for id in pairs(rec.cuts) do
						WoodService.ClearCuts(rec, id)
					end
					rec.damageBy = {}
					setClaim(rec, nil)
				end
				rec.ghost = false
				setVisible(rec, false)
			else
				setVisible(rec, true)
				if not rec.slot and not rec.dead and rec.stage > 0 and rootedLeft(rec) then
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

-- Seconds until an open slot grows back (nil if the tree is still
-- rooted, or never will: an Elder).
function SectionTrees.RegrowsIn(uid: string): number?
	local rec = trees[uid]
	local at = if rec and rec.slot then rec.regrowAt else nil
	return if at then math.max(0, at - clock()) else nil
end

-- The standing tree a part belongs to and the section it is (nil, nil if
-- it isn't a section of one). The part may sit under a folder or an inner
-- model (a box trunk); walk up to the tagged tree. A part that streamed
-- out has no parent and is not a section. A dress part that only carries
-- the section id is not the section itself (the client sends the Section).
function SectionTrees.FromPart(part: Instance): (TreeRecord?, number?)
	local node: Instance? = part.Parent
	for _ = 1, 8 do
		if node == nil then
			return nil, nil
		end
		if node:IsA("Model") then
			local rec = byModel[node]
			if rec and rec.model == node then
				local id = part:GetAttribute("Section")
				if type(id) ~= "number" or rec.sections[id] ~= part then
					return rec, nil
				end
				return rec, id
			end
		end
		node = node.Parent
	end
	return nil, nil
end

---------------------------------------------------------------------------
-- Cutting
---------------------------------------------------------------------------

-- The first trunk cut. The loose piece falls on its own; the standing
-- model stays (cuttable, no Stump tag) until nothing rooted is left.
-- An Elder is removed on a timer and never becomes a slot.
local function fall(rec: TreeRecord, swinger: Player, dir: Vector3, pieceUid: string): Player
	rec.felled = true
	rec.ghost = false
	local claim = if rec.elder then nil else rec.claim
	local most = if claim then claim.userId else ForestLogic.Feller(rec.damageBy, swinger.UserId, isHere)
	local feller = Players:GetPlayerByUserId(most) or swinger
	setClaim(rec, nil)
	refreshAlive(rec)
	if rec.temporary then
		rec.regrowAt = nil
		local growth = rec.growth
		task.delay(SectionTrees.ElderStubSec, function()
			if trees[rec.uid] == rec and rec.growth == growth and not rec.slot then
				SectionTrees.Remove(rec.uid)
			end
		end)
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
local function split(
	rec: TreeRecord,
	player: Player,
	sid: number,
	hit: WoodService.Hit,
	luxSwing: boolean?
): (WoodService.Piece, Player?)
	local def = rec.def
	local part = rec.sections[sid]
	local depth = rec.depth[sid] or 0
	local felled = depth < rec.trunkSegments
	local rootCut = depth == 0
	WoodService.ClearCuts(rec, sid)
	local high: BasePart
	local ids: { [number]: boolean }
	local stubFace: BasePart? = nil
	if rootCut then
		-- The whole rooted section leaves. No bottom sliver, no stub.
		high = part
		ids = WoodService.Reach(rec.nodes, sid)
		TreeArt.CutFace(def, high, false)
	else
		local newId = rec.nextId
		rec.nextId += 1
		high = WoodService.SplitPart(part, hit.height, newId)
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
		ids = WoodService.Reach(rec.nodes, newId)
		stubFace = TreeArt.CutFace(def, part, true)
		TreeArt.CutFace(def, high, false)
	end
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
	if stubFace then
		rec.parts[stubFace] = { transparency = stubFace.Transparency, collide = false, query = false }
	end
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
	-- What a claimed tree yields is its claimer's (the one cutting it: only
	-- they can cut it while it's claimed); an Elder's goes by who did most
	-- of the cut.
	local claim = if rec.elder then nil else rec.claim
	local ownerId = if claim then claim.userId else SectionLogic.Owner(hit.cut, player.UserId, isHere)
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
		lux = luxSwing == true,
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
	if rootCut then
		if not rec.felled then
			feller = fall(rec, player, dir, piece.uid)
		end
		if rec.temporary then
			SectionTrees.Remove(rec.uid)
		elseif trees[rec.uid] == rec then
			openSlot(rec, clock())
		end
	elseif felled then
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
	damage: number,
	luxSwing: boolean?
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
		lux = luxSwing == true,
	})
	local result: SwingResult = { tree = rec, piece = nil, hit = hit, freed = {}, feller = nil }
	if hit.through then
		local piece, feller = split(rec, player, sid, hit, luxSwing)
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
	-- Someone else's tree, mid-cut: theirs while they're at it.
	if rec then
		local holder = SectionLogic.ClaimBlocks(rec.claim, player.UserId, now, rec.elder, isHere)
		if holder then
			local who = Players:GetPlayerByUserId(holder)
			notify(player, SectionLogic.Message("claimed", if who then who.DisplayName else nil))
			return false, "claimed", nil
		end
	end
	local p = piece
	if p then
		local held = GrabService.HeldBy(p.model)
		-- Wood on someone's truck bed is theirs to cut, as it is to grab (TruckLoad).
		local bedHook = GrabService.Hooks.bedOwner
		local bedOwner: Player? = nil
		if bedHook then
			local found, who = pcall(bedHook, p :: any)
			bedOwner = if found then who else nil
		end
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
			bedOwnerId = if bedOwner then bedOwner.UserId else nil,
			ownerHere = p.ownerId ~= 0 and isHere(p.ownerId),
		}
		local ok, reason = GrabLogic.CanGrab(facts)
		if not ok then
			local owner = if reason == "owned" then Players:GetPlayerByUserId(p.ownerId) else nil
			local who = if reason == "bed" then bedOwner else owner
			notify(player, GrabLogic.Message(reason, facts, if who then who.DisplayName else nil))
			return false, reason, nil
		end
	end
	d.setSwingDue(player, math.max(now, due) + (cooldown or stats.cooldown))
	local luxSwing = axe.id == GameConfig.LuxAxeId
	local hook = SectionTrees.Hooks.onSwing
	if hook then
		task.spawn(hook, player, def.id)
	end
	if rec and sid then
		if not rec.elder then
			-- The first cut claims the tree; every hit of theirs keeps it.
			setClaim(rec, { userId = player.UserId, at = now })
		end
		return true, nil, cutStanding(player, rec, sid, at, facing, damage, luxSwing)
	end
	local cutPiece = p :: WoodService.Piece
	local result = WoodService.CutPiece(player, cutPiece, target, at, facing, damage, luxSwing)
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

local TREE_GAP = 10

local function liveBaseNear(rec: TreeRecord, x: number, z: number): boolean
	local g2 = TREE_GAP * TREE_GAP
	for _, other in pairs(trees) do
		if other ~= rec and not other.slot and not other.dead and other.model.Parent ~= nil then
			local dx, dz = other.base.X - x, other.base.Z - z
			if dx * dx + dz * dz < g2 then
				return true
			end
		end
	end
	return false
end

-- A new ground point for `rec`, or nil when this tick found nothing.
-- No zone (the specs' trees): twelve studs off the old base, so a regrow
-- still happens without a world disc. Fixed zones (Sky Lumenwood) stay.
local function pickSpot(rec: TreeRecord): Vector3?
	local base = rec.base
	local zone = rec.zone
	if not zone then
		return Vector3.new(base.X + 12, base.Y, base.Z)
	end
	if zone.fixed then
		return base
	end
	local n = 0
	local x, z = ForestLogic.FindSpot(zone.cx, zone.cz, zone.radius, 48, function()
		n += 1
		return (unit() + n * 0.173) % 1
	end, function(px: number, pz: number): boolean
		local dx, dz = px - base.X, pz - base.Z
		if dx * dx + dz * dz < TREE_GAP * TREE_GAP then
			return false
		end
		if not TreeFill.Ground(px, pz) then
			return false
		end
		return not liveBaseNear(rec, px, pz)
	end)
	if not x or not z then
		return nil
	end
	return Vector3.new(x, TerrainGen.HeightAt(x, z) - 0.3, z)
end

local function zoneFull(rec: TreeRecord): boolean
	local cap = rec.cap
	local zone = rec.zone
	if not cap or not zone then
		return false
	end
	local n = 0
	for _, other in pairs(trees) do
		local otherZone = other.zone
		-- Open slots are not rooted, so they do not hold the cap shut.
		if otherZone and otherZone.id == zone.id and not other.temporary and not other.slot then
			if zone.id == "wild" or other.def.id == rec.def.id then
				n += 1
			end
		end
	end
	-- The record waiting to regrow is itself a slot, so it is not in n.
	-- A zone already at its cap of rooted trees is full.
	return n >= cap
end

-- Nothing rooted is left (or a dead tree has sunk). The record waits
-- out respawnSec times 0.7 to 1.3, then grows back.
openSlot = function(rec: TreeRecord, now: number)
	if rec.temporary or trees[rec.uid] ~= rec or rec.slot then
		return
	end
	rec.slot = true
	rec.felled = true
	rec.dead = false
	rec.deadUntil = nil
	rec.alive = false
	rec.stump = nil
	rec.stumpParts = nil
	rec.ghost = false
	setClaim(rec, nil)
	local model = rec.model
	if model then
		model:SetAttribute("HP", 0)
		CollectionService:RemoveTag(model, SectionTrees.StumpTag)
		byModel[model] = nil
		model:Destroy()
	end
	rec.parts, rec.effects = {}, {}
	rec.sections, rec.nodes, rec.depth = {}, {}, {}
	rec.cuts, rec.marks = {}, {}
	rec.regrowAt = now + GrowLogic.RespawnDelay(rec.def.respawnSec, unit())
	rec.heldUntil = nil
end

tryRegrow = function(rec: TreeRecord, now: number)
	if trees[rec.uid] ~= rec or not rec.slot then
		return
	end
	if zoneFull(rec) then
		rec.regrowAt = now + SectionTrees.RetrySec
		return
	end
	local pos = pickSpot(rec)
	if not pos then
		rec.regrowAt = now + SectionTrees.RetrySec
		return
	end
	local salt = rec.growth + 1
	local seed = Kit.seedAt(pos.X + salt * 13.1, pos.Z - salt * 7.7)
	local _, sizeName, scale, yaw = GrowLogic.Site(pos, seed)
	rec.growth = salt
	rec.seed = seed
	rec.scale = scale
	rec.size = sizeClass(sizeName, scale)
	rec.skel = TreeGen.Skeleton(rec.def.id, seed, scale, { elder = rec.elder })
	rec.base = pos
	rec.homeCf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	rec.felled = false
	rec.slot = false
	rec.regrowAt = nil
	rec.heldUntil = nil
	rec.damageBy = {}
	setClaim(rec, nil)
	rec.cut = false
	rec.preDead = false
	rec.dead = false
	rec.deadUntil = nil
	rec.ghost = false
	rec.life = GrowLogic.Lifespan(rec.def, seed, rec.growth)
	rec.stage = 0
	rec.bornAt = now
	rebuild(rec, true)
	local onRegrown = SectionTrees.OnRegrown
	if onRegrown then
		task.spawn(onRegrown, rec)
	end
end

-- When `rec` next changes, or nil if nothing is coming.
local function nextChange(rec: TreeRecord): number?
	if rec.dormant then
		return nil
	end
	if rec.slot then
		return rec.regrowAt
	end
	if rec.dead then
		return rec.deadUntil
	end
	if rec.temporary then
		return nil
	end
	-- A felled base still ages on the life clock. The slot opens when it sinks.
	local growSec = GrowLogic.GrowSec(rec.def)
	local candidates: { number } = {}
	if not rec.cut and not rec.felled then
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

-- Moves one tree on: grows a slot back, grows a stage, drops leaves,
-- dies, or opens a slot once a dead tree has sunk.
local function advance(rec: TreeRecord, now: number)
	if rec.slot then
		if rec.regrowAt and now >= rec.regrowAt then
			tryRegrow(rec, now)
		end
		return
	end
	if rec.dead then
		if rec.deadUntil and now >= rec.deadUntil then
			openSlot(rec, now)
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
	if not rec.cut and not rec.felled then
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
		if rec.model.Parent ~= nil and not rec.dead and not rec.slot then
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
	table.clear(claimOf)
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
	SectionTrees._roll = nil
end

return SectionTrees
