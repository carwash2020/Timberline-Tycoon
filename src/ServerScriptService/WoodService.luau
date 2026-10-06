--!strict
-- WoodService: loose wood in the v2 core loop (V2_PLAN.md §3f, §3g and
-- WoodWatch in §4a). Everything here runs only under CoreLoop 2:
-- GameServer starts it, SectionTrees hands it what a cut frees, and
-- DevCommands registers its Studio pieces with it.
--
-- A piece is a Model "Wood_<uid>" under TimberlineMap/Wood, tagged Wood,
-- Atomic. Its PrimaryPart is its largest section; every other part is
-- welded (WeldConstraint) to it and nothing is anchored. Sections are
-- Blocks named "Section" (tag WoodSection, attribute Section = its id,
-- length along Y) with CustomPhysicalProperties(WoodDensity,
-- WoodFriction, WoodElasticity); everything else (cut faces, notches,
-- bark details, clues, leaves until they drop) is massless dress riding a
-- section (attribute Section). Attributes, for display only: Uid, Owner
-- (UserId, 0 = nobody), WoodId, Kind ("log" | "plank"), Volume (u³,
-- worked out here), Value ($), Figure, Boost, HeldBy (GrabService), Elder.
-- The record is the truth: who owns it, who last held it, its figure and
-- boost, the tree and planter it came from, when it was made and last
-- touched, WoodWatch's last good pose and verdict, and whether it's
-- selling.
--
--   * Adopt(model, info): a component a cut just freed from a standing tree
--     (SectionTrees). Welded, unanchored, given its physics and its record.
--     A felled trunk tips away from the cutter (info.fall): turned a few
--     degrees over its far edge and set spinning that way, its device the
--     cutter's for FellOwnerSec, in collision group WoodFalling (no
--     players) for FallNoCollideSec, its leaves gone after LeafDropSec
--     (WorldFX "LeafFall": clients flutter pooled leaves instead), and
--     WorldFX "Felled" {pos, mass} once it has landed (the crash and the
--     camera shake).
--   * CutPiece: a swing at a loose piece (SectionTrees validates it first).
--     The damage goes into a cut on that section (SectionLogic); once it's
--     through, the piece splits into exactly two (SectionLogic.SplitGraph),
--     both keeping the owner, figure, boost and creation time, the volume
--     shared exactly between them. A part smaller than MinPieceVolume
--     becomes chips.
--   * Despawn and caps (Tick, every second): off any plot and untouched
--     for WoodUnownedAfterSec it loses its owner; unowned and untouched for
--     WoodDespawnAfterSec more it goes. Held wood and wood on its owner's
--     bed (Hooks.onBed) count as touched. Past MaxWoodPiecesPerPlayer
--     (a player's oldest untouched go) or MaxWoodPartsServer (the oldest
--     unowned loose wood goes first, then the oldest untouched) pieces
--     are removed. Sawmill planks are pieces too: the cap counts every
--     part on the model, a plank included, not a cached guess.
--     Wood that drops 50 below the isles' floor is lost to the clouds.
--   * WoodWatch (Watch, every WoodJudgeEvery): every piece a player's
--     device simulates (held, just let go, freshly felled, on a driven
--     truck) is judged with VehicleLogic.JudgeMove against WoodMaxSpeed. A
--     move further than anything can is put back, stopped, and kept by the
--     server for PutBackHoldSec; until its next good verdict SellService
--     won't take it (VerdictOk). GrabService defers to this.
--   * FromPart(part): the record a part belongs to (GrabService's and
--     SellService's resolver).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FallLogic = require(ReplicatedStorage.Shared.FallLogic)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SectionLogic = require(ReplicatedStorage.Shared.SectionLogic)
local SellLogic = require(ReplicatedStorage.Shared.SellLogic)
local Tune = require(ReplicatedStorage.Shared.Tune)
local Util = require(ReplicatedStorage.Shared.Util)
local VehicleLogic = require(ReplicatedStorage.Shared.VehicleLogic)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local TreeArt = require(ReplicatedStorage.Shared.Art.TreeArt)
local MeshKit = require(ReplicatedStorage.Shared.Art.MeshKit)
local GrabService = require(script.Parent.GrabService)

type WoodDef = WoodData.WoodDef
type Cut = SectionLogic.Cut

local WoodService = {}

WoodService.Tag = "Wood"
WoodService.SectionTag = "WoodSection"
WoodService.WoodGroup = "Wood"
WoodService.FallingGroup = "WoodFalling"
WoodService.HeldGroup = "WoodHeld"
WoodService.LeavesGroup = "Leaves"
WoodService.PlayersGroup = "Players"
-- Plot sawmills (MachineArt). Mill is the cage: players and a falling tree
-- hit it, loose and carried logs do not, so a feed can pass the blade.
-- MillBelt is the conveyor: loose logs ride it; players, held logs and
-- falling trees do not.
WoodService.MillGroup = "Mill"
WoodService.MillBeltGroup = "MillBelt"
WoodService.FellOwnerSec = 3 -- the cutter's device simulates a fresh piece this long
WoodService.PutBackHoldSec = 1 -- a piece WoodWatch put back stays the server's this long
WoodService.FellTilt = math.rad(4) -- a felled trunk starts this far over its far edge
WoodService.LimbPush = 2 -- studs/s: a freed limb drops away from the tree
WoodService.FallWatchSec = 5 -- a fall is watched this long for its landing
WoodService.LandedShare = 0.35 -- landed: moving at this share of its fastest
WoodService.CloudsBelow = 50 -- studs under the isles' floor: lost to the clouds
WoodService.SkyFloor = 650 -- the isles' floor (BiomeData sky area y)
WoodService.FxRange = 250 -- studs: WorldFX for a piece goes to players this near
WoodService.LeafPoints = 10 -- leaf positions a LeafFall sends at most

-- The dress that drops off a felled piece after LeafDropSec.
local LEAF_NAMES: { [string]: boolean } = {
	Leaves = true,
	Frond = true,
	Facet = true,
	Coconut = true,
	Pod = true,
	PodStem = true,
}

export type Kind = "log" | "plank"

-- A section's place in its piece: who it hangs from and what hangs off it.
export type Node = { parent: number?, children: { number } }

-- A cut in progress and what shows it: the face it was started on and its
-- notch.
export type Mark = { normal: Vector3, notch: BasePart? }

-- Where cuts in progress are kept (a piece's record, a standing tree's).
export type CutHolder = {
	cuts: { [number]: { Cut } },
	marks: { [Cut]: Mark },
}

export type Piece = {
	uid: string,
	model: Model,
	root: BasePart,
	woodId: string,
	def: WoodDef,
	kind: Kind,
	nodes: { [number]: Node },
	parts: { [number]: BasePart }, -- its sections by id
	cuts: { [number]: { Cut } },
	marks: { [Cut]: Mark },
	nextId: number, -- the id the next split's new section gets
	ownerId: number, -- 0 = nobody
	lastHolderId: number?,
	figure: string?,
	boost: number,
	lux: boolean, -- a Lux swing tagged this piece, or the piece it was cut from (SellLogic.InheritLux)
	treeUid: string?,
	createdAt: number, -- os.clock() it was cut free (GrabLogic's grace)
	lastInteracted: number,
	lastGood: CFrame, -- WoodWatch: where its root was last accepted
	lastGoodAt: number,
	verdictOk: boolean, -- WoodWatch's last verdict was good (or the server simulates it)
	putBackUntil: number?, -- put back: the server keeps it till then
	selling: boolean?,
	dead: boolean?,
	elder: boolean?,
	shopItem: boolean?,
	sky: boolean, -- made up on the isles: lost if it drops below them
	volume: number, -- u³
	value: number, -- $ as a log (figure and boost included)
	partCount: number,
}

-- What SectionTrees knows about a component it freed.
export type Fall = {
	cutter: Player?, -- its device simulates the fall
	dir: Vector3, -- flat: the way it falls (away from the cutter)
	felled: boolean, -- a trunk (tip it over its far edge) or a limb (let it drop)
	pivot: Vector3?, -- felled: the cut's centre, where it tips from
}

export type Info = {
	woodId: string,
	kind: Kind?,
	nodes: { [number]: Node },
	parts: { [number]: BasePart },
	cuts: { [number]: { Cut } }?,
	marks: { [Cut]: Mark }?,
	nextId: number?,
	ownerId: number,
	lastHolderId: number?,
	figure: string?,
	boost: number?,
	lux: boolean?,
	treeUid: string?,
	createdAt: number?,
	elder: boolean?,
	fall: Fall?,
	uid: string?,
}

-- Hooks for later slices: onBed, the player whose truck bed the piece
-- rests on (M1.6; resting on its owner's bed, it never ages); onPlot,
-- true while it lies on a plot (M3: plot wood never loses its owner);
-- onRemoved, after a piece is gone (despawned, capped, lost, chips).
export type Hooks = {
	onBed: ((Piece) -> Player?)?,
	onPlot: ((Piece) -> boolean)?,
	onRemoved: ((Piece, string) -> ())?,
}
WoodService.Hooks = {} :: Hooks

-- Network ownership and motion, behind a seam: Lune, which runs the
-- specs, has no physics.
WoodService.Physics = {
	SetOwner = function(part: BasePart, player: Player?): boolean
		local ok = pcall(function(): any
			part:SetNetworkOwner(player)
			return nil
		end)
		return ok
	end,
	SetAuto = function(part: BasePart)
		pcall(function(): any
			part:SetNetworkOwnershipAuto()
			return nil
		end)
	end,
	-- The player whose device simulates `part`, nil for the server.
	GetOwner = function(part: BasePart): Player?
		local ok, owner = pcall(function(): Player?
			return part:GetNetworkOwner()
		end)
		return if ok then owner else nil
	end,
	-- How fast the assembly moves: linear studs/s, angular rad/s.
	Speed = function(part: BasePart): (number, number)
		return part.AssemblyLinearVelocity.Magnitude, part.AssemblyAngularVelocity.Magnitude
	end,
	GetVelocity = function(part: BasePart): (Vector3, Vector3)
		return part.AssemblyLinearVelocity, part.AssemblyAngularVelocity
	end,
	SetVelocity = function(part: BasePart, linear: Vector3, angular: Vector3)
		part.AssemblyLinearVelocity = linear
		part.AssemblyAngularVelocity = angular
	end,
}

type Watching = {
	piece: Piece,
	startAt: number,
	peak: number,
	reach: number, -- studs from the root to its far end (angular speed to tip speed)
	landed: boolean,
	trunk: boolean, -- a felled trunk (a limb lands without dust)
}

local pieces: { [string]: Piece } = {}
local byModel: { [Model]: Piece } = {}
local falls: { Watching } = {}
local timers: { { at: number, fn: () -> () } } = {}
local worldFx: RemoteEvent? = nil
local folder: Instance? = nil
local started = false
local clock: () -> number = os.clock

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

-- Runs `fn` at least `seconds` from now (on WoodService's own clock, so the
-- specs can step it).
local function after(seconds: number, fn: () -> ())
	table.insert(timers, { at = clock() + seconds, fn = fn })
end

local function physics(): PhysicalProperties
	return PhysicalProperties.new(
		Tune.Get("WoodDensity") :: number,
		Tune.Get("WoodFriction") :: number,
		Tune.Get("WoodElasticity") :: number
	)
end

local function round2(n: number): number
	return math.floor(n * 100 + 0.5) / 100
end

-- WorldFX `kind` to everyone within FxRange of `pos`.
local function fireNear(pos: Vector3, kind: string, payload: { [string]: any })
	local remote = worldFx
	if not remote then
		return
	end
	local range = WoodService.FxRange
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
		if hrp and hrp:IsA("BasePart") and (hrp.Position - pos).Magnitude <= range then
			remote:FireClient(player, kind, payload)
		end
	end
end
WoodService.FireNear = fireNear

-- The section id an item of dress rides on, if it has one.
local function sectionOf(inst: Instance): number?
	local id = inst:GetAttribute("Section")
	return if type(id) == "number" then id else nil
end

local function isSection(inst: Instance): boolean
	return inst:IsA("BasePart") and inst.Name == "Section" and sectionOf(inst) ~= nil
end

-- Where an item of dress is: a part's centre, or a model's first part's.
local function positionOf(inst: Instance): Vector3?
	if inst:IsA("BasePart") then
		return inst.CFrame.Position
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			return d.CFrame.Position
		end
	end
	return nil
end

local function setSection(inst: Instance, id: number)
	inst:SetAttribute("Section", id)
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			d:SetAttribute("Section", id)
		end
	end
end

local function partsIn(model: Model): number
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		-- Crown meshes are looks-only. A cut section is still one part.
		if d:IsA("BasePart") and MeshKit.Counts(d) then
			n += 1
		end
	end
	return n
end

-- A live section part as SectionLogic's Node (its bottom centre, Y up).
local function liveNode(id: number, part: BasePart, node: Node): SectionLogic.Node
	return {
		id = id,
		parent = node.parent,
		children = table.clone(node.children),
		cf = part.CFrame * CFrame.new(0, -part.Size.Y / 2, 0),
		length = part.Size.Y,
		thickness = math.min(part.Size.X, part.Size.Z),
	}
end

local function graphOf(nodes: { [number]: Node }, parts: { [number]: BasePart }): SectionLogic.Graph
	local graph: SectionLogic.Graph = {}
	for id, node in pairs(nodes) do
		local part = parts[id]
		if part then
			graph[id] = liveNode(id, part, node)
		end
	end
	return graph
end

---------------------------------------------------------------------------
-- Collision groups
---------------------------------------------------------------------------

-- Registers the v2 wood groups once (MapBuilder does it before it builds
-- the trees, GameServer again for safety; GrabService registers WoodHeld
-- and Players too). Falling and held wood pass through players; the
-- server's sight ray (CollisionGroup "Wood") skips leaves. Mill and
-- MillBelt are the plot sawmill's cage and conveyor (see the sets below).
-- Safe to call again.
-- True if done.
function WoodService.RegisterGroups(): boolean
	local ok, err = pcall(function(): any
		local PhysicsService = game:GetService("PhysicsService")
		for _, name in ipairs({
			WoodService.WoodGroup,
			WoodService.FallingGroup,
			WoodService.HeldGroup,
			WoodService.LeavesGroup,
			WoodService.PlayersGroup,
			WoodService.MillGroup,
			WoodService.MillBeltGroup,
		}) do
			if not PhysicsService:IsCollisionGroupRegistered(name) then
				PhysicsService:RegisterCollisionGroup(name)
			end
		end
		PhysicsService:CollisionGroupSetCollidable(WoodService.FallingGroup, WoodService.PlayersGroup, false)
		-- Pieces freed together never push each other apart.
		PhysicsService:CollisionGroupSetCollidable(WoodService.FallingGroup, WoodService.FallingGroup, false)
		PhysicsService:CollisionGroupSetCollidable(WoodService.HeldGroup, WoodService.PlayersGroup, false)
		PhysicsService:CollisionGroupSetCollidable(WoodService.LeavesGroup, WoodService.WoodGroup, false)
		-- The cage (roof, end guards, blade guard) stops players. A loose or
		-- carried log passes through it onto the belt. A tree still falling
		-- hits the mill like any other building.
		for _, wood in ipairs({ WoodService.WoodGroup, WoodService.HeldGroup }) do
			PhysicsService:CollisionGroupSetCollidable(WoodService.MillGroup, wood, false)
		end
		-- The belt carries loose logs. It does not grab a player, a log in
		-- someone's arms, or a tree on its way down, and it doesn't fight
		-- the cage where the two overlap.
		PhysicsService:CollisionGroupSetCollidable(WoodService.MillBeltGroup, WoodService.PlayersGroup, false)
		PhysicsService:CollisionGroupSetCollidable(WoodService.MillBeltGroup, WoodService.HeldGroup, false)
		PhysicsService:CollisionGroupSetCollidable(WoodService.MillBeltGroup, WoodService.FallingGroup, false)
		PhysicsService:CollisionGroupSetCollidable(WoodService.MillBeltGroup, WoodService.MillGroup, false)
		return nil
	end)
	if not ok then
		warn("[WoodService] Collision groups failed: " .. tostring(err))
	end
	return ok
end

---------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------

-- TimberlineMap/Wood (made if missing).
function WoodService.Folder(): Instance
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local map = workspace:FindFirstChild("TimberlineMap")
	local found = if map then map:FindFirstChild("Wood") else nil
	if not found then
		local made = Instance.new("Folder")
		made.Name = "Wood"
		made.Parent = map or workspace
		found = made
	end
	folder = found
	return found :: Instance
end

-- The piece a part belongs to (its model, or a few levels up), or nil.
function WoodService.FromPart(part: Instance): Piece?
	local node: Instance? = part
	for _ = 1, 5 do
		if node == nil then
			return nil
		end
		if node:IsA("Model") then
			local piece = byModel[node]
			if piece then
				return piece
			end
		end
		node = node.Parent
	end
	return nil
end

function WoodService.FromModel(model: Model): Piece?
	return byModel[model]
end

function WoodService.Get(uid: string): Piece?
	return pieces[uid]
end

function WoodService.All(): { [string]: Piece }
	return pieces
end

-- WoodWatch's last word: the server simulates it, or its device's last
-- move was believable. SellService takes only these.
function WoodService.VerdictOk(piece: Piece): boolean
	return piece.verdictOk
end

-- Volume (u³) and value ($) of a piece's sections.
local function worth(p: Piece): (number, number)
	local volume = 0
	for _, part in pairs(p.parts) do
		volume += SectionLogic.Volume(part.Size.X, part.Size.Y, part.Size.Z)
	end
	return volume, SellLogic.PieceValue(p.woodId, p.kind, volume, p.figure, p.boost, p.lux)
end

-- The piece's mass by its sections (dress is massless), as the engine
-- will see it: studs³ x WoodDensity.
function WoodService.MassOf(p: Piece): number
	local studs = 0
	for _, part in pairs(p.parts) do
		studs += part.Size.X * part.Size.Y * part.Size.Z
	end
	return studs * (Tune.Get("WoodDensity") :: number)
end

-- Writes the display attributes from the record.
local function publish(p: Piece)
	local volume, value = worth(p)
	p.volume = volume
	p.value = value
	p.partCount = partsIn(p.model)
	local m = p.model
	m:SetAttribute("Uid", p.uid)
	m:SetAttribute("Owner", p.ownerId)
	m:SetAttribute("WoodId", p.woodId)
	m:SetAttribute("Kind", p.kind)
	m:SetAttribute("Volume", round2(volume))
	m:SetAttribute("Value", round2(value))
	m:SetAttribute("Figure", p.figure)
	m:SetAttribute("Boost", if p.boost > 1 then p.boost else nil)
	m:SetAttribute("LuxCut", if p.lux then true else nil)
	m:SetAttribute("Elder", if p.elder then true else nil)
	m:SetAttribute("LastInteracted", p.lastInteracted)
	if m:GetAttribute("HeldBy") == nil then
		m:SetAttribute("HeldBy", 0)
	end
	-- Lanternwood planks glow on the client. Logs stay plain, and a plank
	-- never gets a light (WoodFX).
	if p.kind == "plank" and p.woodId == WoodData.LanternId then
		if not m:HasTag("Lanternwood") then
			m:AddTag("Lanternwood")
		end
		m:SetAttribute("NightHost", "plank")
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "Section" then
				d:SetAttribute("NightGlow", true)
			end
		end
	end
end
WoodService.Publish = publish

-- Gives a piece a new figure (the Living Forest), or none.
function WoodService.SetFigure(p: Piece, figure: string?)
	p.figure = figure
	publish(p)
end

-- Every part welded to `root`, nothing anchored; sections get the wood's
-- physics, dress is massless and never collides.
local function weld(model: Model, root: BasePart)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	local props = physics()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true -- while the welds go on
			if isSection(d) then
				d.CustomPhysicalProperties = props
				d.Massless = false
				d.CanCollide = true
				d.CanQuery = true
				d.CanTouch = false
				CollectionService:AddTag(d, WoodService.SectionTag)
			else
				d.Massless = true
				d.CanCollide = false
				d.CanTouch = false
			end
			if d ~= root then
				local w = Instance.new("WeldConstraint")
				w.Part0 = root
				w.Part1 = d
				w.Parent = d
			end
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end
end

local function setGroup(model: Model, group: string)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and isSection(d) then
			d.CollisionGroup = group
		end
	end
end

-- Builds the record for `model` (its parts already in place) and files it.
local function makeRecord(model: Model, info: Info): Piece
	local def = WoodData.Get(info.woodId)
	assert(def, "[WoodService] unknown wood " .. tostring(info.woodId))
	local graph = graphOf(info.nodes, info.parts)
	local rootId = SectionLogic.Largest(graph)
	assert(rootId, "[WoodService] a piece needs a section")
	local root = info.parts[rootId]
	local now = clock()
	local uid = info.uid or Util.guid()
	local maxId = 0
	for id in pairs(info.parts) do
		maxId = math.max(maxId, id)
	end
	local p: Piece = {
		uid = uid,
		model = model,
		root = root,
		woodId = def.id,
		def = def,
		kind = info.kind or "log",
		nodes = info.nodes,
		parts = info.parts,
		cuts = info.cuts or {},
		marks = info.marks or {},
		nextId = math.max(info.nextId or 0, maxId + 1),
		ownerId = info.ownerId,
		lastHolderId = info.lastHolderId,
		figure = info.figure,
		boost = math.max(1, info.boost or 1),
		lux = info.lux == true,
		treeUid = info.treeUid,
		createdAt = info.createdAt or now,
		lastInteracted = now,
		lastGood = root.CFrame,
		lastGoodAt = now,
		verdictOk = true,
		putBackUntil = nil,
		selling = nil,
		dead = nil,
		elder = info.elder,
		shopItem = nil,
		sky = root.CFrame.Position.Y >= WoodService.SkyFloor,
		volume = 0,
		value = 0,
		partCount = 0,
	}
	model.Name = "Wood_" .. uid
	model.PrimaryPart = root
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	CollectionService:AddTag(model, WoodService.Tag)
	pieces[uid] = p
	byModel[model] = p
	publish(p)
	return p
end

-- The pieces to remove so the caps hold (pure; see the header). Entries
-- that are `protected` (held, selling) never go. Returns uids, in order.
export type CapEntry = {
	uid: string,
	ownerId: number,
	parts: number,
	lastInteracted: number,
	protected: boolean?,
}
function WoodService.PickEvictions(entries: { CapEntry }, maxPerPlayer: number, maxParts: number): { string }
	local out: { string } = {}
	local gone: { [string]: boolean } = {}
	local byOwner: { [number]: { CapEntry } } = {}
	local total = 0
	for _, e in ipairs(entries) do
		total += e.parts
		if e.ownerId ~= 0 then
			local list = byOwner[e.ownerId] or {}
			table.insert(list, e)
			byOwner[e.ownerId] = list
		end
	end
	local function oldestFirst(a: CapEntry, b: CapEntry): boolean
		if a.lastInteracted ~= b.lastInteracted then
			return a.lastInteracted < b.lastInteracted
		end
		return a.uid < b.uid
	end
	local function evict(e: CapEntry)
		gone[e.uid] = true
		table.insert(out, e.uid)
		total -= e.parts
	end
	-- A player's own cap: their oldest untouched pieces go.
	local owners: { number } = {}
	for ownerId in pairs(byOwner) do
		table.insert(owners, ownerId)
	end
	table.sort(owners)
	for _, ownerId in ipairs(owners) do
		local list = byOwner[ownerId]
		table.sort(list, oldestFirst)
		local count = #list
		for _, e in ipairs(list) do
			if count <= maxPerPlayer then
				break
			end
			if not e.protected then
				evict(e)
				count -= 1
			end
		end
	end
	-- The server's part cap: the oldest unowned first, then the oldest
	-- untouched of everyone's.
	if total > maxParts then
		local sorted = table.clone(entries)
		table.sort(sorted, oldestFirst)
		for _, pass in ipairs({ true, false }) do
			for _, e in ipairs(sorted) do
				if total <= maxParts then
					break
				end
				local unowned = e.ownerId == 0
				if not gone[e.uid] and not e.protected and (unowned or not pass) then
					evict(e)
				end
			end
		end
	end
	return out
end

-- A piece the server just moved itself (TruckLoad carrying a load onto a
-- recalled truck): WoodWatch takes its new place as good.
function WoodService.Moved(model: Model)
	local p = byModel[model]
	if not p then
		return
	end
	p.lastGood = p.root.CFrame
	p.lastGoodAt = clock()
	p.verdictOk = true
end

-- Forgets a piece without destroying it (SellService destroys what it sells).
function WoodService.Forget(model: Model)
	local p = byModel[model]
	if not p then
		return
	end
	byModel[model] = nil
	if pieces[p.uid] == p then
		pieces[p.uid] = nil
	end
end

-- Removes a piece for good: let go of, forgotten and destroyed.
function WoodService.Remove(p: Piece, reason: string)
	GrabService.ReleasePiece(p.model, reason)
	WoodService.Forget(p.model)
	p.dead = true
	p.model:Destroy()
	local onRemoved = WoodService.Hooks.onRemoved
	if onRemoved then
		onRemoved(p, reason)
	end
end

-- Keeps the caps (see PickEvictions).
local function enforceCaps()
	local entries: { CapEntry } = {}
	for uid, p in pairs(pieces) do
		-- Count the parts that are actually there (a sawmill plank is one
		-- section; a log's bark and cut faces count too). The oldest loose
		-- wood is what PickEvictions drops first.
		local parts = partsIn(p.model)
		p.partCount = parts
		table.insert(entries, {
			uid = uid,
			ownerId = p.ownerId,
			parts = parts,
			lastInteracted = p.lastInteracted,
			protected = p.selling == true or GrabService.HeldBy(p.model) ~= nil,
		})
	end
	local evict = WoodService.PickEvictions(
		entries,
		Tune.Get("MaxWoodPiecesPerPlayer") :: number,
		Tune.Get("MaxWoodPartsServer") :: number
	)
	for _, uid in ipairs(evict) do
		local p = pieces[uid]
		if p then
			WoodService.Remove(p, "capped")
		end
	end
end
WoodService.EnforceCaps = enforceCaps

---------------------------------------------------------------------------
-- New pieces
---------------------------------------------------------------------------

-- Leaves (and fronds, tiers, coconuts, pods) of a piece: they drop.
local function leafItems(model: Model): { Instance }
	local out: { Instance } = {}
	for _, c in ipairs(model:GetChildren()) do
		if (c:IsA("BasePart") and LEAF_NAMES[c.Name]) or (c:IsA("Model") and c.Name == "Tier") then
			table.insert(out, c)
		end
	end
	return out
end

local function dropLeaves(p: Piece)
	if p.model.Parent == nil then
		return
	end
	local items = leafItems(p.model)
	if #items == 0 then
		return
	end
	local points: { Vector3 } = {}
	local step = math.max(1, math.floor(#items / WoodService.LeafPoints))
	for i, item in ipairs(items) do
		if i % step == 0 and #points < WoodService.LeafPoints then
			local at = positionOf(item)
			if at then
				table.insert(points, at)
			end
		end
	end
	for _, item in ipairs(items) do
		item:Destroy()
	end
	p.partCount = partsIn(p.model)
	if #points > 0 then
		fireNear(points[1], "LeafFall", { points = points, woodId = p.woodId, count = #items })
	end
end

-- The far end of a piece from its root (for its tip speed).
local function reachOf(p: Piece): number
	local most = 0
	local at = p.root.CFrame.Position
	for _, part in pairs(p.parts) do
		local d = (part.CFrame.Position - at).Magnitude + part.Size.Y / 2
		most = math.max(most, d)
	end
	return math.max(1, most)
end

-- Starts a freed component on its way down (see Adopt).
local function startFall(p: Piece, fall: Fall)
	local root = p.root
	local model = p.model
	local now = clock()
	setGroup(model, WoodService.FallingGroup)
	local dir = Vector3.new(fall.dir.X, 0, fall.dir.Z)
	dir = if dir.Magnitude > 1e-6 then dir.Unit else Vector3.xAxis
	local reach = reachOf(p)
	if fall.felled then
		local axis = Vector3.new(0, 1, 0):Cross(dir)
		local spin = FallLogic.StartSpin(Tune.Get("FellImpulse") :: number, reach)
		WoodService.Physics.SetVelocity(root, Vector3.zero, axis * spin)
	else
		WoodService.Physics.SetVelocity(root, dir * WoodService.LimbPush, Vector3.zero)
	end
	local cutter = fall.cutter
	if cutter and cutter.Parent ~= nil then
		WoodService.Physics.SetOwner(root, cutter)
		after(WoodService.FellOwnerSec, function()
			if byModel[model] == p and not p.putBackUntil and GrabService.HeldBy(model) == nil then
				WoodService.Physics.SetAuto(root)
			end
		end)
	end
	-- Players again after FallNoCollideSec (held wood waits till it's let go).
	local function solid()
		if model.Parent == nil then
			return
		end
		if GrabService.HeldBy(model) ~= nil then
			after(0.5, solid)
			return
		end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.CollisionGroup == WoodService.FallingGroup then
				d.CollisionGroup = WoodService.WoodGroup
			end
		end
	end
	after(Tune.Get("FallNoCollideSec") :: number, solid)
	after(Tune.Get("LeafDropSec") :: number, function()
		if byModel[model] == p then
			dropLeaves(p)
		end
	end)
	table.insert(
		falls,
		{ piece = p, startAt = now, peak = 0, reach = reach, landed = false, trunk = fall.felled == true }
	)
end

-- An empty model in the Wood folder for a new piece's parts: they move
-- straight into it, never leaving the world (so nothing streams twice).
function WoodService.NewModel(): Model
	local model = Instance.new("Model")
	model.Name = "Wood_new"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = WoodService.Folder()
	return model
end

-- Takes a component a cut freed from a standing tree (see the header).
-- Its parts are in `model` (from NewModel), anchored where they stood:
-- sections by id in info.parts with their links in info.nodes, dress
-- beside them. Returns its record.
function WoodService.Adopt(model: Model, info: Info): Piece
	local graph = graphOf(info.nodes, info.parts)
	local rootId = SectionLogic.Largest(graph)
	assert(rootId, "[WoodService] Adopt: no sections")
	local root = info.parts[rootId]
	local fall = info.fall
	if fall and fall.felled and fall.pivot then
		-- Tip it a few degrees over the far edge of its cut, so gravity
		-- takes it the way it's meant to go (an impulse alone can stall on
		-- a flat stub).
		local dir = Vector3.new(fall.dir.X, 0, fall.dir.Z)
		if dir.Magnitude > 1e-6 then
			dir = dir.Unit
			local half = math.min(root.Size.X, root.Size.Z) / 2
			local edge = fall.pivot + dir * half
			local axis = Vector3.new(0, 1, 0):Cross(dir)
			local turn = CFrame.new(0, FallLogic.LiftGap, 0)
				* CFrame.new(edge)
				* CFrame.fromAxisAngle(axis, WoodService.FellTilt)
				* CFrame.new(-edge)
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CFrame = turn * d.CFrame
				end
			end
		end
	end
	model.PrimaryPart = root
	weld(model, root)
	local p = makeRecord(model, info)
	setGroup(model, WoodService.WoodGroup)
	if model.Parent == nil then
		model.Parent = WoodService.Folder()
	end
	if fall then
		startFall(p, fall)
	end
	enforceCaps()
	return p
end

-- How far apart two sections' boxes may be and still count as joined
-- (LinkByContact).
WoodService.ContactSlack = 0.15

-- Whether box `b` reaches box `a`: b's centre within b's own largest half
-- extent (plus slack) of a's box, in a's frame.
local function reaches(a: BasePart, b: BasePart): boolean
	local half = a.Size / 2
	local rel = a.CFrame:PointToObjectSpace(b.CFrame.Position)
	local dx = math.max(0, math.abs(rel.X) - half.X)
	local dy = math.max(0, math.abs(rel.Y) - half.Y)
	local dz = math.max(0, math.abs(rel.Z) - half.Z)
	local reach = math.max(b.Size.X, b.Size.Y, b.Size.Z) / 2 + WoodService.ContactSlack
	return dx * dx + dy * dy + dz * dz <= reach * reach
end

-- A section graph for a piece rebuilt without one (a load saved off a
-- truck bed, Studio's /spawnwood): a tree grown from its largest section
-- through the sections that touch (both ways). Sections touching nothing
-- hang off the root, so the piece stays one tree.
function WoodService.LinkByContact(parts: { [number]: BasePart }): { [number]: Node }
	local nodes: { [number]: Node } = {}
	local ids: { number } = {}
	for id in pairs(parts) do
		table.insert(ids, id)
	end
	table.sort(ids)
	if #ids == 0 then
		return nodes
	end
	local root, rootVolume = ids[1], -1
	for _, id in ipairs(ids) do
		local size = parts[id].Size
		local v = size.X * size.Y * size.Z
		if v > rootVolume then
			root, rootVolume = id, v
		end
	end
	nodes[root] = { parent = nil, children = {} }
	local queue = { root }
	local head = 1
	while head <= #queue do
		local at = queue[head]
		head += 1
		for _, id in ipairs(ids) do
			if nodes[id] == nil and reaches(parts[at], parts[id]) and reaches(parts[id], parts[at]) then
				nodes[id] = { parent = at, children = {} }
				table.insert(nodes[at].children, id)
				table.insert(queue, id)
			end
		end
	end
	for _, id in ipairs(ids) do
		if nodes[id] == nil then
			nodes[id] = { parent = root, children = {} }
			table.insert(nodes[root].children, id)
		end
	end
	return nodes
end

-- Files a piece built elsewhere, already welded and unanchored (a load
-- rebuilt off a truck bed, Studio's /spawnwood). Its sections are its
-- parts named Section; a section's links come from `nodes` or, without
-- them, from which sections touch (LinkByContact).
function WoodService.Register(model: Model, info: Info?): Piece
	local i: Info = info or { woodId = "", nodes = {}, parts = {}, ownerId = 0 }
	local parts: { [number]: BasePart } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if isSection(d) then
			parts[sectionOf(d) :: number] = d :: BasePart
			CollectionService:AddTag(d, WoodService.SectionTag)
		end
	end
	local nodes = i.nodes
	if next(nodes) == nil then
		nodes = WoodService.LinkByContact(parts)
	end
	local woodId = if i.woodId ~= "" then i.woodId else tostring(model:GetAttribute("WoodId"))
	local kind: Kind = if model:GetAttribute("Kind") == "plank" then "plank" else "log"
	local uidAttr = model:GetAttribute("Uid")
	return makeRecord(model, {
		woodId = woodId,
		kind = i.kind or kind,
		nodes = nodes,
		parts = parts,
		ownerId = i.ownerId,
		figure = i.figure,
		boost = i.boost,
		lux = if i.lux ~= nil then i.lux else model:GetAttribute("LuxCut") == true,
		createdAt = i.createdAt,
		uid = i.uid or (if type(uidAttr) == "string" and uidAttr ~= "" then uidAttr else nil),
	})
end

export type PlankInfo = {
	woodId: string,
	size: Vector3, -- studs; Y is the length
	cf: CFrame, -- the plank's centre
	ownerId: number,
	figure: string?,
	boost: number?,
	lux: boolean?,
	lastHolderId: number?,
}

-- One loose plank (a sawmill's output). Core colour all the way through,
-- the log's figure and boost kept, so it drags, rides and sells like any
-- other piece. Nil for an unknown wood.
function WoodService.SpawnPlank(info: PlankInfo): Piece?
	local def = WoodData.Get(info.woodId)
	if not def or info.size.X <= 0 or info.size.Y <= 0 or info.size.Z <= 0 then
		return nil
	end
	local model = WoodService.NewModel()
	local section = Instance.new("Part")
	section.Name = "Section"
	section.Size = info.size
	section.CFrame = info.cf
	section.Anchored = true
	local color, material = TreeArt.Core(def)
	section.Color = color
	section.Material = material
	section.TopSurface = Enum.SurfaceType.Smooth
	section.BottomSurface = Enum.SurfaceType.Smooth
	section:SetAttribute("Section", 1)
	section.Parent = model
	model.PrimaryPart = section
	local p = makeRecord(model, {
		woodId = def.id,
		kind = "plank",
		nodes = { [1] = { parent = nil, children = {} } },
		parts = { [1] = section },
		ownerId = info.ownerId,
		lastHolderId = info.lastHolderId,
		figure = info.figure,
		boost = info.boost,
		lux = info.lux,
	})
	weld(model, section)
	setGroup(model, WoodService.WoodGroup)
	enforceCaps()
	return if byModel[model] == p then p else nil
end

---------------------------------------------------------------------------
-- Cutting
---------------------------------------------------------------------------

export type Hit = {
	cut: Cut,
	required: number,
	through: boolean,
	height: number, -- studs up the section
	progress: number, -- 0-1
	sectionId: number,
}

-- One swing's damage into the cuts of `holder` (a piece's record, or a
-- standing tree's) on section `part` (id `sectionId`): the cut it lands
-- in (SectionLogic.AddHit: within CutWindow, at most MaxCutsPerSection,
-- the least-damaged giving way), its notch grown on the face it was
-- started from, and whether it's through.
function WoodService.ApplyHit(
	holder: CutHolder,
	def: WoodDef,
	part: BasePart,
	sectionId: number,
	hitPos: Vector3,
	normal: Vector3,
	damage: number,
	userId: number
): Hit
	local length = part.Size.Y
	local localY = part.CFrame:PointToObjectSpace(hitPos).Y
	local h = SectionLogic.ClampHeight(localY, length)
	local list = holder.cuts[sectionId]
	if not list then
		list = {}
		holder.cuts[sectionId] = list
	end
	local cut, replaced = SectionLogic.AddHit(list, h, damage, userId)
	if replaced then
		-- The cut that gave way: its notch goes.
		local live: { [Cut]: boolean } = {}
		for _, c in ipairs(list) do
			live[c] = true
		end
		for c, mark in pairs(holder.marks) do
			if not live[c] and mark.notch and mark.notch:GetAttribute("Section") == sectionId then
				mark.notch:Destroy()
				holder.marks[c] = nil
			end
		end
	end
	local mark = holder.marks[cut]
	if not mark then
		mark = { normal = SectionLogic.SideFacing(part.CFrame, normal), notch = nil }
		holder.marks[cut] = mark
	end
	local hardness = if def.v2 then def.v2.hardness else def.hardness
	local required = SectionLogic.Required(hardness, part.Size.X, part.Size.Z)
	local through = SectionLogic.IsThrough(cut, required)
	local old = mark.notch
	if old then
		old:Destroy()
		mark.notch = nil
	end
	if not through and part.Parent then
		mark.notch = TreeArt.Notch(def, part, cut.height, mark.normal, cut.damage, required)
	end
	return {
		cut = cut,
		required = required,
		through = through,
		height = cut.height,
		progress = if required > 0 then math.clamp(cut.damage / required, 0, 1) else 1,
		sectionId = sectionId,
	}
end

-- Drops every cut (and notch) on section `sectionId` of `holder`.
function WoodService.ClearCuts(holder: CutHolder, sectionId: number)
	local list = holder.cuts[sectionId]
	if not list then
		return
	end
	for _, c in ipairs(list) do
		local mark = holder.marks[c]
		if mark and mark.notch then
			mark.notch:Destroy()
		end
		holder.marks[c] = nil
	end
	holder.cuts[sectionId] = nil
end

-- A fresh section part copying `s`'s look and physics (no children).
local function copySection(s: BasePart): Part
	local p = Instance.new("Part")
	p.Name = "Section"
	p.Size = s.Size
	p.CFrame = s.CFrame
	p.Color = s.Color
	p.Material = s.Material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = s.Anchored
	p.CanCollide = s.CanCollide
	p.CanQuery = s.CanQuery
	p.CanTouch = s.CanTouch
	p.CastShadow = s.CastShadow
	p.CollisionGroup = s.CollisionGroup
	p.CustomPhysicalProperties = s.CustomPhysicalProperties
	p.Massless = s.Massless
	CollectionService:AddTag(p, WoodService.SectionTag)
	return p
end

-- Cuts section part `s` (anchored, or with its welds gone) `h` studs up
-- from its bottom: `s` keeps the bottom h, resized in place, and a new
-- part (id `newId`, beside it in the same parent) takes the rest. Dress
-- riding `s` above the cut rides the new part now; its notches go (the
-- cut that made them is done). Returns the new part.
function WoodService.SplitPart(s: BasePart, h: number, newId: number): BasePart
	local length = s.Size.Y
	local cut = math.clamp(h, 0, length)
	local cf = s.CFrame
	local sid = sectionOf(s)
	local high = copySection(s)
	high.Size = Vector3.new(s.Size.X, length - cut, s.Size.Z)
	high.CFrame = cf * CFrame.new(0, cut / 2, 0)
	high:SetAttribute("Section", newId)
	s.Size = Vector3.new(s.Size.X, cut, s.Size.Z)
	s.CFrame = cf * CFrame.new(0, -(length - cut) / 2, 0)
	local parent = s.Parent
	if parent and sid then
		for _, item in ipairs(parent:GetChildren()) do
			if item ~= s and not isSection(item) and sectionOf(item) == sid then
				if item.Name == "Notch" then
					item:Destroy()
				else
					local at = positionOf(item)
					if at and cf:PointToObjectSpace(at).Y + length / 2 > cut then
						setSection(item, newId)
					end
				end
			end
		end
	end
	high.Parent = parent
	return high
end

-- The ids reachable from `start` along `nodes`' links.
function WoodService.Reach(nodes: { [number]: Node }, start: number): { [number]: boolean }
	local seen: { [number]: boolean } = {}
	local stack = { start }
	while #stack > 0 do
		local id = table.remove(stack) :: number
		local n = nodes[id]
		if n and not seen[id] then
			seen[id] = true
			if n.parent and nodes[n.parent] then
				table.insert(stack, n.parent)
			end
			for _, c in ipairs(n.children) do
				table.insert(stack, c)
			end
		end
	end
	return seen
end

-- Moves the sections `ids` of `from` and the dress riding them into `to`.
function WoodService.MoveSections(from: Instance, to: Instance, ids: { [number]: boolean })
	for _, item in ipairs(from:GetChildren()) do
		local id = sectionOf(item)
		if id and ids[id] then
			item.Parent = to
		end
	end
end

-- Destroys a component too small to keep: chips fly (WorldFX "Chips").
local function chip(model: Model, woodId: string)
	local at = positionOf(model)
	model:Destroy()
	if at then
		fireNear(at, "Chips", { pos = at, woodId = woodId })
	end
end

export type CutResult = {
	hit: Hit,
	pieces: { Piece }, -- after a split: the piece cut (kept) and the new one (none if it was chips)
}

-- A swing at loose piece `p`'s section `part` (SectionTrees has checked
-- range, sight, the axe and permission). See the header.
function WoodService.CutPiece(
	player: Player,
	p: Piece,
	part: BasePart,
	hitPos: Vector3,
	normal: Vector3,
	damage: number,
	swingLux: boolean?
): CutResult?
	local sid = sectionOf(part)
	if not sid or p.parts[sid] ~= part or byModel[p.model] ~= p then
		return nil
	end
	local hit = WoodService.ApplyHit(p, p.def, part, sid, hitPos, normal, damage, player.UserId)
	p.lastInteracted = clock()
	p.model:SetAttribute("LastInteracted", p.lastInteracted)
	fireNear(hitPos, "Cut", {
		part = part,
		pos = hitPos,
		normal = normal,
		woodId = p.woodId,
		progress = hit.progress,
		userId = player.UserId,
		through = hit.through,
		lux = swingLux == true,
	})
	if not hit.through then
		return { hit = hit, pieces = {} }
	end
	return { hit = hit, pieces = WoodService.SplitPiece(p, sid, hit.height, swingLux) }
end

-- Splits loose piece `p` through section `sid` at `h` studs up it: the
-- piece keeps the low side (and its uid and record), a new piece takes the
-- high side; both keep the owner, figure, boost and creation time, and the
-- assembly's motion. Returns the pieces left (one if a side was chips).
function WoodService.SplitPiece(p: Piece, sid: number, h: number, swingLux: boolean?): { Piece }
	local model = p.model
	local root = p.root
	GrabService.ReleasePiece(model, "cut")
	local linear, angular = WoodService.Physics.GetVelocity(root)
	local now = clock()
	-- Unweld and hold still while the parts change.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("WeldConstraint") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local s = p.parts[sid]
	local newId = p.nextId
	p.nextId += 1
	local graph = graphOf(p.nodes, p.parts)
	local a, b = SectionLogic.SplitGraph(graph, sid, h, newId)
	WoodService.ClearCuts(p, sid)
	local high = WoodService.SplitPart(s, h, newId)
	-- The new topology, from SplitGraph's answer.
	local nodesA: { [number]: Node } = {}
	local nodesB: { [number]: Node } = {}
	local partsA: { [number]: BasePart } = {}
	local partsB: { [number]: BasePart } = {}
	for id, n in pairs(a) do
		nodesA[id] = { parent = n.parent, children = table.clone(n.children) }
		partsA[id] = if id == newId then high else p.parts[id]
	end
	for id, n in pairs(b) do
		nodesB[id] = { parent = n.parent, children = table.clone(n.children) }
		partsB[id] = if id == newId then high else p.parts[id]
	end
	TreeArt.CutFace(p.def, s, true)
	TreeArt.CutFace(p.def, high, false)
	-- Side B into a model of its own, with its cuts.
	local other = WoodService.NewModel()
	local idsB: { [number]: boolean } = {}
	for id in pairs(nodesB) do
		idsB[id] = true
	end
	WoodService.MoveSections(model, other, idsB)
	local cutsB: { [number]: { Cut } } = {}
	local marksB: { [Cut]: Mark } = {}
	for id in pairs(idsB) do
		local list = p.cuts[id]
		if list then
			cutsB[id] = list
			for _, c in ipairs(list) do
				marksB[c] = p.marks[c]
				p.marks[c] = nil
			end
			p.cuts[id] = nil
		end
	end
	local volA = SectionLogic.GraphVolume(a)
	local volB = SectionLogic.GraphVolume(b)
	-- Both sides keep a Lux tag, and a Lux chop through a plain log tags both.
	p.lux = SellLogic.InheritLux(p.lux, swingLux)
	local out: { Piece } = {}
	-- Side A stays in this model and record.
	if SectionLogic.IsChips(volA) then
		WoodService.Forget(model)
		chip(model, p.woodId)
		p.dead = true
	else
		p.nodes = nodesA
		p.parts = partsA
		local rootA = partsA[SectionLogic.Largest(a) :: number]
		p.root = rootA
		model.PrimaryPart = rootA
		weld(model, rootA)
		setGroup(model, WoodService.WoodGroup)
		p.lastInteracted = now
		p.lastGood = rootA.CFrame
		p.lastGoodAt = now
		p.verdictOk = true
		publish(p)
		WoodService.Physics.SetVelocity(rootA, linear, angular)
		table.insert(out, p)
	end
	if SectionLogic.IsChips(volB) then
		chip(other, p.woodId)
	else
		local rootB = partsB[SectionLogic.Largest(b) :: number]
		other.PrimaryPart = rootB
		weld(other, rootB)
		local q = makeRecord(other, {
			woodId = p.woodId,
			kind = p.kind,
			nodes = nodesB,
			parts = partsB,
			cuts = cutsB,
			marks = marksB,
			nextId = p.nextId,
			ownerId = p.ownerId,
			lastHolderId = p.lastHolderId,
			figure = p.figure,
			boost = p.boost,
			lux = p.lux,
			treeUid = p.treeUid,
			createdAt = p.createdAt,
			elder = p.elder,
		})
		setGroup(other, WoodService.WoodGroup)
		WoodService.Physics.SetVelocity(rootB, linear, angular)
		table.insert(out, q)
	end
	enforceCaps()
	return out
end

---------------------------------------------------------------------------
-- The clock: falls, despawn, caps, WoodWatch
---------------------------------------------------------------------------

-- Watches falling pieces for their landing (WorldFX "Felled").
function WoodService.StepFalls(now: number)
	local i = 1
	while i <= #falls do
		local f = falls[i]
		local p = f.piece
		if byModel[p.model] ~= p or p.model.Parent == nil then
			table.remove(falls, i)
			continue
		end
		-- One rigid trunk: nothing may launch it (a depenetration kick, a bounce).
		if now - f.startAt < FallLogic.CapSec then
			local lin, ang = WoodService.Physics.GetVelocity(p.root)
			local capL, capA = FallLogic.Capped(lin, ang)
			if capL and capA then
				WoodService.Physics.SetVelocity(p.root, capL, capA)
			end
		end
		local linear, angular = WoodService.Physics.Speed(p.root)
		local speed = linear + angular * f.reach
		f.peak = math.max(f.peak, speed)
		local t = now - f.startAt
		local landed = (t > 0.5 and f.peak > 4 and speed < f.peak * WoodService.LandedShare)
			or t >= WoodService.FallWatchSec
		if landed then
			table.remove(falls, i)
			fireNear(p.root.CFrame.Position, "Felled", {
				pos = p.root.CFrame.Position,
				mass = WoodService.MassOf(p),
				woodId = p.woodId,
				uid = p.uid,
				trunk = f.trunk,
			})
			continue
		end
		i += 1
	end
end

-- Pieces falling right now (specs).
function WoodService.Falling(): number
	return #falls
end

-- Lost below the isles, aged out, unowned, capped (see the header). Once
-- a second (GameServer's clock), or by hand in the specs.
function WoodService.Tick(now: number)
	local unownedAfter = Tune.Get("WoodUnownedAfterSec") :: number
	local despawnAfter = Tune.Get("WoodDespawnAfterSec") :: number
	local hooks = WoodService.Hooks
	for _, p in pairs(pieces) do
		local model = p.model
		if model.Parent == nil or p.root.Parent == nil then
			WoodService.Forget(model) -- fell into the void, or destroyed elsewhere
			continue
		end
		if p.sky and p.root.CFrame.Position.Y < WoodService.SkyFloor - WoodService.CloudsBelow then
			WoodService.Remove(p, "clouds")
			continue
		end
		if p.selling then
			continue
		end
		local bedOwner = if hooks.onBed then hooks.onBed(p) else nil
		local held = GrabService.HeldBy(model) ~= nil
		if held or (bedOwner ~= nil and bedOwner.UserId == p.ownerId) then
			p.lastInteracted = now -- in hand, or on its owner's bed: never ages
			continue
		end
		local idle = now - p.lastInteracted
		local onPlot = if hooks.onPlot then hooks.onPlot(p) else false
		if p.ownerId ~= 0 and not onPlot and idle >= unownedAfter then
			p.ownerId = 0
			model:SetAttribute("Owner", 0)
		end
		if p.ownerId == 0 and not onPlot and idle >= unownedAfter + despawnAfter then
			WoodService.Remove(p, "despawned")
		end
	end
	enforceCaps()
end

-- Takes a piece back from a device that moved it further than anything
-- can: back where it was last accepted, stopped, the server's for a bit.
local function putBack(p: Piece, now: number, who: string, moved: number, dt: number)
	warn(string.format("[AntiExploit] %s's wood moved %d studs in %.1fs; putting it back", who, math.floor(moved), dt))
	GrabService.ReleasePiece(p.model, "teleport")
	WoodService.Physics.SetOwner(p.root, nil)
	p.model:PivotTo(p.lastGood)
	WoodService.Physics.SetVelocity(p.root, Vector3.zero, Vector3.zero)
	p.putBackUntil = now + WoodService.PutBackHoldSec
	p.verdictOk = false
end

-- WoodWatch: one pass over every piece (see the header).
function WoodService.Watch(now: number)
	local maxSpeed = Tune.Get("WoodMaxSpeed") :: number
	for _, p in pairs(pieces) do
		local root = p.root
		if p.model.Parent == nil or root.Parent == nil then
			continue
		end
		local hold = p.putBackUntil
		if hold then
			if now < hold then
				continue
			end
			p.putBackUntil = nil
			WoodService.Physics.SetAuto(root)
		end
		local cf = root.CFrame
		local owner = WoodService.Physics.GetOwner(root)
		if owner == nil then
			p.lastGood = cf
			p.lastGoodAt = now
			p.verdictOk = true
			continue
		end
		local verdict = VehicleLogic.JudgeMove(p.lastGood.Position, cf.Position, now - p.lastGoodAt, maxSpeed)
		if verdict == "tooFar" then
			putBack(p, now, owner.Name, (cf.Position - p.lastGood.Position).Magnitude, now - p.lastGoodAt)
		elseif verdict == "ok" then
			p.lastGood = cf
			p.lastGoodAt = now
			p.verdictOk = true
		else
			p.verdictOk = true
		end
	end
end

-- Runs the timers that are due (specs call it with their own clock).
function WoodService.RunTimers(now: number)
	local due: { () -> () } = {}
	local i = 1
	while i <= #timers do
		local t = timers[i]
		if t.at <= now then
			table.insert(due, t.fn)
			table.remove(timers, i)
		else
			i += 1
		end
	end
	for _, fn in ipairs(due) do
		fn()
	end
end

-- A sold piece's "+$" pop on the pad (WorldFX "Sold"), for everyone near.
function WoodService.SaleFx(model: Model, amount: number)
	local root = model.PrimaryPart
	if root and amount > 0 then
		fireNear(root.CFrame.Position, "Sold", { pos = root.CFrame.Position, amount = amount })
	end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

export type Deps = {
	worldFx: RemoteEvent?,
	folder: Instance?,
	clock: (() -> number)?,
	manual: boolean?, -- specs: no Heartbeat, call Tick / Watch / StepFalls / RunTimers by hand
}

-- Runs one step of the clock on its own: an error is warned, not fatal.
local function safely(name: string, fn: (number) -> (), now: number)
	local ok, err = pcall(function(): any
		fn(now)
		return nil
	end)
	if not ok then
		warn(string.format("[WoodService] %s failed: %s", name, tostring(err)))
	end
end

-- Starts the clock (the v2 loop only: GameServer checks).
function WoodService.Init(deps: Deps)
	worldFx = deps.worldFx
	folder = deps.folder
	clock = deps.clock or os.clock
	if started then
		return
	end
	started = true
	if deps.manual then
		return
	end
	WoodService.RegisterGroups()
	local sinceTick, sinceWatch, sinceFall = 0, 0, 0
	RunService.Heartbeat:Connect(function(dt: number)
		local now = clock()
		sinceFall += dt
		if sinceFall >= 0.1 then
			sinceFall = 0
			safely("timers", WoodService.RunTimers, now)
			safely("falls", WoodService.StepFalls, now)
		end
		sinceWatch += dt
		if sinceWatch >= GameConfig.WoodJudgeEvery then
			sinceWatch = 0
			safely("watch", WoodService.Watch, now)
		end
		sinceTick += dt
		if sinceTick >= 1 then
			sinceTick = 0
			safely("tick", WoodService.Tick, now)
		end
	end)
end

-- For the specs: forget everything.
function WoodService._reset()
	table.clear(pieces)
	table.clear(byModel)
	table.clear(falls)
	table.clear(timers)
	started = false
	worldFx = nil
	folder = nil
	clock = os.clock
end

return WoodService
