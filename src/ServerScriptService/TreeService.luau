--!strict
-- TreeService: owns every tree and log in the world.
--   * Trees are built by Shared/Art/TreeArt (one silhouette per wood) in a
--     size class (Shared/TreeLogic: small, normal or large; big trees take
--     more chopping and drop an extra log).
--   * Server-side HP; ApplyChop validates range and applies axe damage.
--     Hit feedback (shake, chips, sound) is drawn on each client by TreeFX.
--   * Felling: the tree tips away from whoever swung last. The felling
--     (its logs, OnFelled) counts for whoever chopped the most of it
--     (ForestLogic.Feller), so a last swing can't take someone's tree. The
--     server never moves the tree: it sets Felled / FallDir / FellAt and
--     every client animates the fall smoothly (TreeFX). When it has
--     landed, the server hides it, leaves a stump, and lays exactly the
--     tree's logs along the fall line. After the wood's respawnSec the
--     stump goes and the tree is back (clients play it growing from a
--     sapling).
--   * A tree only comes back solid (regrown, woken at night, or new) when
--     no truck or player is where it stands; until then it's a ghost (no
--     collisions), checked again every couple of seconds.
--   * Night-only woods (the Phantom Grove): SetBiomeDormant hides a biome's
--     trees and stumps by day and brings them back at night (WorldClock).
--   * Log records: state "world" | "carried". Ownership: PickupGraceSec to
--     the feller, then free-for-all. Logs left in the world despawn after
--     LogDespawnSec.
-- GameServer assigns TreeService.PickupCallback for ProximityPrompt pickups.
--
-- Tree model contract (TreeFX, TreeUI, ChopController, QuestUI): tag "Tree";
-- PrimaryPart "Trunk" (its CFrame = the HomePivot attribute, at mid-trunk);
-- attributes WoodId, MaxHP, HP, Uid, BarOffset, HomePivot, Size, Dormant,
-- Felled, FallDir, FellAt (and PlanterId for planted trees).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ForestLogic = require(ReplicatedStorage.Shared.ForestLogic)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local TreeArt = require(ReplicatedStorage.Shared.Art.TreeArt)
local TreeLogic = require(ReplicatedStorage.Shared.TreeLogic)
local Util = require(ReplicatedStorage.Shared.Util)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local TerrainGen = require(ReplicatedStorage.Shared.World.TerrainGen)

type WoodDef = WoodData.WoodDef

local TreeService = {}

local TREE_TAG = "Tree"
local LOG_TAG = "Log"
local LOG_LENGTH = 3
local LOG_DIAMETER = 1.2
local LOG_GAP = 0.25
local GHOST_RETRY = 2 -- seconds between checks while something stands where a tree came back
local MAX_HOLD = 240 -- seconds: HoldRegrow never keeps a stump longer than this from now
local HOLD_SLACK = 0.1 -- seconds: a timer waking this close to the due time regrows now
TreeService.LogDiameter = LOG_DIAMETER

-- What a part looked like before the tree was hidden.
type PartState = { transparency: number, collide: boolean, query: boolean }

export type TreeRecord = {
	uid: string,
	model: Model,
	def: WoodDef,
	size: TreeLogic.SizeClass,
	maxHp: number,
	hp: number,
	alive: boolean,
	pivot: CFrame, -- upright pivot (trunk centre)
	base: Vector3, -- ground point under the trunk
	radius: number, -- the trunk's radius: chop range is measured from the bark
	parts: { [BasePart]: PartState },
	effects: { [Instance]: boolean }, -- lights and particles, with Enabled
	felled: boolean, -- down and waiting to regrow
	dormant: boolean, -- hidden for now (night-only woods by day)
	stump: Model?,
	stumpParts: { [BasePart]: PartState }?, -- how the stump looked before it was hidden
	ghost: boolean, -- standing but not solid yet: a truck or someone was where it came back
	regrowAt: number?, -- os.clock() its natural regrowth is due, while it's down
	heldUntil: number?, -- os.clock() a hold on its stump ends (HoldRegrow), while it's down
	seed: number,
	planterId: number?, -- who planted it (the Living Forest), if anyone
	damageBy: { [number]: number }, -- HP each player has chopped off this growth (co-op credit)
	temporary: boolean, -- removed after it's felled instead of regrowing (Elder trees)
	growth: number, -- counts fellings: a timer from an earlier felling checks it and gives up
}

export type LogRecord = {
	model: Model,
	def: WoodDef,
	ownerId: number,
	fellTime: number,
	state: "world" | "carried",
	despawnToken: number,
	value: number, -- what this log sells for (figure and other bonuses included)
	tags: { [string]: any }, -- facts other systems attach (figure, planter, ...)
	graceUntil: number?, -- os.time() until which only the owner may pick it up (default: fellTime + PickupGraceSec)
	despawnSec: number?, -- how long it lies in the world (default: GameConfig.LogDespawnSec)
}

export type LogOptions = {
	graceSec: number?, -- the owner's exclusive pickup window (default PickupGraceSec)
	despawnSec: number?, -- how long it lies before it disappears (default LogDespawnSec)
}

local trees: { [string]: TreeRecord } = {}
local logs: { [string]: LogRecord } = {}
local treeCounters: { [string]: number } = {}
local makeSolid: (rec: TreeRecord) -> () -- below: solid, or a ghost while something's in the way
local stumpSolidWhenClear: (rec: TreeRecord) -> () -- below: the same for a stump

local folders: { [string]: Folder } = {}
local function getFolder(name: string): Folder
	local cached = folders[name]
	if cached then
		return cached
	end
	local map = workspace:WaitForChild("TimberlineMap", 30)
	assert(map, "[TreeService] TimberlineMap not found")
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = map
	folders[name] = folder
	return folder
end

-- Assigned by GameServer: (player, logUid) -> (). Server-validated pickup.
TreeService.PickupCallback = nil :: ((Player, string) -> ())?
-- Assigned by GameServer: how many times its logs a player's fell drops
-- (2 during a 2x Wood boost).
TreeService.LogMultiplier = nil :: ((Player) -> number)?
-- Assigned by the forest systems: called once a felled tree has landed and
-- its logs are down, with the logs' uids (seed drops, figure, royalties).
TreeService.OnFelled = nil :: ((player: Player, rec: TreeRecord, logUids: { string }, fallDir: Vector3) -> ())?
-- Assigned by the forest systems: called when a tree regrows.
TreeService.OnRegrown = nil :: ((rec: TreeRecord) -> ())?
-- Assigned by QuestService: how many seconds a stump this player has just
-- felled should wait before its tree grows back on its own (0 = the wood's
-- usual respawnSec). Murph's tutorial keeps the stump for its plant step.
TreeService.StumpHold = nil :: ((feller: Player) -> number)?

local function addPickupPrompt(logPart: BasePart, uid: string, def: WoodDef)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = def.displayName .. " Log"
	prompt.MaxActivationDistance = GameConfig.PickupPromptRange
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = logPart
	prompt.Triggered:Connect(function(player: Player)
		local cb = TreeService.PickupCallback
		if cb then
			cb(player, uid)
		end
	end)
end

-- Remembers how every part and effect of a tree looks, so it can be hidden
-- and brought back exactly.
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

-- Builds a tree on the ground at `cframe` (its position is the ground point
-- under the trunk). options.seed fixes its look, options.size its size
-- class, options.planterId who planted it. Returns the Model.
export type SpawnOptions = {
	seed: number?,
	size: TreeLogic.SizeClass?,
	planterId: number?,
	temporary: boolean?, -- gone for good once felled (Elder trees)
}
function TreeService.SpawnTree(woodId: string, cframe: CFrame, options: SpawnOptions?): Model
	local def = WoodData.Get(woodId)
	assert(def, "[TreeService] Unknown wood: " .. tostring(woodId))
	local opts: SpawnOptions = options or {}
	treeCounters[woodId] = (treeCounters[woodId] or 0) + 1
	local uid = Util.guid()
	local pos = cframe.Position
	local seed = opts.seed or Kit.seedAt(pos.X, pos.Z)
	local size = opts.size or TreeLogic.SizeFor(Kit.rng(seed + 101):next())

	local model = TreeArt.Build(def, seed, size.scale)
	model.Name = string.format("Tree_%s_%d", woodId, treeCounters[woodId])
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- trunk + leaves stream in together
	-- Built around the origin; turn it a random way and stand it on the spot.
	local yaw = Kit.rng(seed + 202):range(0, math.pi * 2)
	Kit.placeAt(model, CFrame.new(pos) * CFrame.Angles(0, yaw, 0))

	local pivot = model:GetPivot()
	local trunkPart = model.PrimaryPart
	local radius = if trunkPart then trunkPart.Size.Y / 2 else 1 -- the trunk cylinder's axis is its X
	local maxHp = TreeLogic.MaxHP(def.treeHP, size)
	model:SetAttribute("WoodId", woodId)
	model:SetAttribute("MaxHP", maxHp)
	model:SetAttribute("HP", maxHp)
	model:SetAttribute("Uid", uid)
	model:SetAttribute("Size", size.name)
	model:SetAttribute("BarOffset", TreeArt.BarHeight(def, size.scale))
	model:SetAttribute("HomePivot", pivot) -- clients shake and fell the tree around this
	model:SetAttribute("TrunkRadius", radius) -- ChopController measures reach from the bark
	model:SetAttribute("Felled", false)
	if opts.planterId then
		model:SetAttribute("PlanterId", opts.planterId)
	end
	CollectionService:AddTag(model, TREE_TAG)
	model.Parent = getFolder("Trees")

	local parts, effects = snapshot(model)
	trees[uid] = {
		uid = uid,
		model = model,
		def = def,
		size = size,
		maxHp = maxHp,
		hp = maxHp,
		alive = true,
		pivot = pivot,
		base = pos,
		radius = radius,
		parts = parts,
		effects = effects,
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
		growth = 0,
	}
	makeSolid(trees[uid]) -- an Elder may wake where a truck is parked
	return model
end

-- Removes a tree (and its stump) for good, e.g. an Elder that was felled
-- or that nobody felled in time. Its logs stay where they lie.
function TreeService.Remove(uid: string)
	local rec = trees[uid]
	if not rec then
		return
	end
	trees[uid] = nil
	if rec.stump then
		rec.stump:Destroy()
		rec.stump = nil
	end
	rec.model:Destroy()
end

-- Adds parts to a standing tree (bark clues, a storm's glow, an Elder's
-- aura) and remembers them, so hiding and regrowing the tree includes
-- them. `build` gets the tree's Model and record; parts it adds should be
-- decoration (Kit.decor).
function TreeService.Decorate(uid: string, build: (Model, TreeRecord) -> ())
	local rec = trees[uid]
	if not rec then
		return
	end
	build(rec.model, rec)
	local visible = not rec.felled and not rec.dormant
	for _, d in ipairs(rec.model:GetDescendants()) do
		if d:IsA("BasePart") and rec.parts[d] == nil then
			rec.parts[d] = { transparency = d.Transparency, collide = d.CanCollide, query = d.CanQuery }
			if not visible then
				d.Transparency = 1
				d.CanCollide = false
				d.CanQuery = false
			elseif rec.ghost then
				-- A ghost (something stands where it regrew): a new solid
				-- part waits with the rest, so it never closes round a
				-- player or a truck. makeSolid restores it.
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
function TreeService.Forget(uid: string, inst: Instance)
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
			-- CanCollide must go false before CanQuery can.
			part.CanCollide = false
			part.CanQuery = false -- clicks and raycasts pass through the hidden tree
		end
	end
end

local function setTreeVisible(rec: TreeRecord, visible: boolean)
	showParts(rec.parts, visible)
	for effect, enabled in pairs(rec.effects) do
		if effect:IsA("Light") or effect:IsA("ParticleEmitter") then
			(effect :: any).Enabled = visible and enabled
		end
	end
end

-- Stops the tree pushing anyone around while it falls.
local function setTreeSolid(rec: TreeRecord, solid: boolean)
	for part, state in pairs(rec.parts) do
		if part.Parent ~= nil then
			part.CanCollide = solid and state.collide
		end
	end
end

-- Hidden stumps (the Phantom Grove by day) are no invisible obstacle either.
local function setStumpVisible(rec: TreeRecord, visible: boolean)
	local parts = rec.stumpParts
	if rec.stump and parts then
		showParts(parts, visible)
		if visible then
			stumpSolidWhenClear(rec)
		end
	end
end

local function removeStump(rec: TreeRecord)
	if rec.stump then
		rec.stump:Destroy()
		rec.stump = nil
	end
	rec.stumpParts = nil
end

local function placeStump(rec: TreeRecord)
	removeStump(rec)
	local stump = TreeArt.Stump(rec.def, rec.seed, rec.size.scale)
	stump.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	Kit.placeAt(stump, CFrame.new(rec.base) * CFrame.Angles(0, Kit.rng(rec.seed + 202):range(0, math.pi * 2), 0))
	stump:SetAttribute("WoodId", rec.def.id)
	stump:SetAttribute("TreeUid", rec.uid)
	CollectionService:AddTag(stump, "Stump")
	rec.stump = stump
	rec.stumpParts = (snapshot(stump))
	if rec.dormant then
		setStumpVisible(rec, false) -- it landed after dawn: hidden with the rest of its grove
	end
	stump.Parent = getFolder("Stumps")
	stumpSolidWhenClear(rec) -- a ghost tree's stump lands where something stood
end

-- True when a truck or someone's character is in the way of any of these
-- solid parts (a trunk, a stump), so making them solid now would trap or
-- fling them.
local function blockedParts(parts: { [BasePart]: PartState }): boolean
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
	for part, state in pairs(parts) do
		if state.collide and part.Parent ~= nil then
			if #workspace:GetPartBoundsInBox(part.CFrame, part.Size + Vector3.one, params) > 0 then
				return true
			end
		end
	end
	return false
end

local function blocked(rec: TreeRecord): boolean
	return blockedParts(rec.parts)
end

-- A stump that appears (a tree landed, a grove woke) where a truck or a
-- player is stays walk-through until the spot is clear, like a ghost tree.
stumpSolidWhenClear = function(rec: TreeRecord)
	local stump, parts = rec.stump, rec.stumpParts
	if not stump or not parts or rec.dormant or not blockedParts(parts) then
		return
	end
	for part in pairs(parts) do
		if part.Parent ~= nil then
			part.CanCollide = false
		end
	end
	local function retry()
		if rec.stump ~= stump or rec.dormant then
			return -- gone, replaced or hidden: they look after its collisions
		end
		if blockedParts(parts) then
			task.delay(GHOST_RETRY, retry)
			return
		end
		for part, state in pairs(parts) do
			if part.Parent ~= nil then
				part.CanCollide = state.collide
			end
		end
	end
	task.delay(GHOST_RETRY, retry)
end

-- Makes a standing tree solid, or, while something is in the way, a ghost
-- (seen and choppable, no collisions) that tries again every GHOST_RETRY
-- seconds. Felling or hiding the tree ends the wait.
makeSolid = function(rec: TreeRecord)
	if not blocked(rec) then
		rec.ghost = false
		setTreeSolid(rec, true)
		return
	end
	setTreeSolid(rec, false)
	if rec.ghost then
		return -- already waiting
	end
	rec.ghost = true
	local function retry()
		if trees[rec.uid] ~= rec or not rec.ghost then
			return
		end
		if blocked(rec) then
			task.delay(GHOST_RETRY, retry)
			return
		end
		rec.ghost = false
		setTreeSolid(rec, true)
	end
	task.delay(GHOST_RETRY, retry)
end

-- Log despawn: each (re)entry into the world gets a fresh token, so an old
-- timer can't delete a log that was picked up and dropped again since.
local function scheduleDespawn(uid: string, rec: LogRecord)
	rec.despawnToken += 1
	local token = rec.despawnToken
	task.delay(rec.despawnSec or GameConfig.LogDespawnSec, function()
		if logs[uid] == rec and rec.state == "world" and rec.despawnToken == token then
			logs[uid] = nil
			rec.model:Destroy()
		end
	end)
end

-- Spawns one pickup-able log at `cframe` (cylinder axis = the CFrame's X).
-- `options` lengthens the owner's pickup window and the log's life (a truck
-- load left where the truck stood).
function TreeService.SpawnLog(def: WoodDef, cframe: CFrame, ownerId: number, options: LogOptions?): (Model, string)
	local uid = Util.guid()
	local model = TreeArt.Log(def, LOG_LENGTH, LOG_DIAMETER)
	-- Built at the origin: move every part (the caps are welded to LogPart).
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CFrame = cframe * d.CFrame
		end
	end
	model:SetAttribute("WoodId", def.id)
	model:SetAttribute("Value", def.pricePerLog)
	model:SetAttribute("Uid", uid)
	CollectionService:AddTag(model, LOG_TAG)
	model.Parent = getFolder("Logs")

	local rec: LogRecord = {
		model = model,
		def = def,
		ownerId = ownerId,
		fellTime = os.time(),
		state = "world",
		despawnToken = 0,
		value = def.pricePerLog,
		tags = {},
		graceUntil = if options and options.graceSec then os.time() + options.graceSec else nil,
		despawnSec = if options then options.despawnSec else nil,
	}
	logs[uid] = rec
	addPickupPrompt(model.PrimaryPart :: BasePart, uid, def)
	scheduleDespawn(uid, rec)
	return model, uid
end

-- Things a dropped or landing log mustn't come to rest on: people, trucks,
-- trees and other logs.
local function groundParams(extra: { Instance }?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true -- skip invisible zones and foliage
	local skip: { Instance } = { getFolder("Trees"), getFolder("Logs") }
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(skip, player.Character)
		end
	end
	for _, truck in ipairs(CollectionService:GetTagged("Truck")) do
		table.insert(skip, truck)
	end
	for _, inst in ipairs(extra or {}) do
		table.insert(skip, inst)
	end
	params.FilterDescendantsInstances = skip
	return params
end

-- The ground height under (x, z), searching down from just above `fromY`
-- (trees on the Aether Isles stand far above the terrain), or from above
-- the terrain there if that's higher (a log laid uphill of its stump).
local function groundY(params: RaycastParams, x: number, z: number, fromY: number, fallback: number): number
	local top = math.max(fromY, TerrainGen.HeightAt(x, z)) + 10
	local hit = workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, fromY - 30 - top, 0), params)
	return if hit then hit.Position.Y else fallback
end

-- Fells a tree `swinger` just finished; returns the player the felling
-- counts for (nil if there was no tree to fell).
local function fellTree(swinger: Player, uid: string): Player?
	local rec = trees[uid]
	if not rec or not rec.alive then
		return nil
	end
	rec.alive = false
	rec.felled = true
	rec.ghost = false
	rec.growth += 1
	local growth = rec.growth
	local model = rec.model
	-- It counts for whoever (still here) chopped the most of it.
	local most = ForestLogic.Feller(rec.damageBy, swinger.UserId, function(userId: number): boolean
		return Players:GetPlayerByUserId(userId) ~= nil
	end)
	local feller = Players:GetPlayerByUserId(most) or swinger
	local fellerId = feller.UserId

	-- Fall away from the swinger, a little randomly.
	local char = swinger.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local fallDir = TreeLogic.FallDirection(rec.base, if hrp then hrp.Position else nil, (math.random() - 0.5) * 0.7)
	setTreeSolid(rec, false)
	model:SetAttribute("FallDir", fallDir)
	model:SetAttribute("FellAt", workspace:GetServerTimeNow())
	model:SetAttribute("Felled", true)

	task.delay(TreeLogic.FallTime + 0.35, function()
		if trees[uid] ~= rec or not rec.felled or rec.growth ~= growth then
			return
		end
		-- Landed: hide the tree, leave a stump, lay its logs along the fall.
		setTreeVisible(rec, false)
		placeStump(rec)
		local multiplier = if TreeService.LogMultiplier then TreeService.LogMultiplier(feller) else 1
		local count = TreeLogic.LogCount(rec.def.logsPerTree, rec.size, multiplier)
		local trunkLength = (rec.def.trunkHeight + rec.def.foliageSize * 0.5) * rec.size.scale
		local skip: { Instance } = { getFolder("Stumps") }
		local params = groundParams(skip)
		local uids: { string } = {}
		for _, cf in
			ipairs(TreeLogic.LogLayout(rec.base, fallDir, trunkLength, count, LOG_LENGTH, LOG_DIAMETER, LOG_GAP))
		do
			local p = cf.Position
			local y = groundY(params, p.X, p.Z, rec.base.Y, rec.base.Y)
			local _, logUid = TreeService.SpawnLog(rec.def, cf + Vector3.new(0, y - rec.base.Y, 0), fellerId)
			table.insert(uids, logUid)
		end
		local onFelled = TreeService.OnFelled
		if onFelled then
			task.spawn(onFelled, feller, rec, uids, fallDir)
		end
	end)

	local downFor = if rec.temporary then TreeLogic.FallTime + 8 else rec.def.respawnSec
	rec.regrowAt = if rec.temporary then nil else os.clock() + downFor
	rec.heldUntil = nil
	local function due()
		-- Planted back early and felled again since? That felling has its
		-- own timer.
		if trees[uid] ~= rec or rec.growth ~= growth then
			return
		end
		if rec.temporary then
			TreeService.Remove(uid)
			return
		end
		-- Held (HoldRegrow): wait out the rest of the hold, then regrow.
		local held = rec.heldUntil
		local left = if rec.felled and held then held - os.clock() else 0
		if left > HOLD_SLACK then
			task.delay(left, due)
			return
		end
		TreeService.Regrow(uid)
	end
	task.delay(downFor, due)
	local hold = TreeService.StumpHold
	if hold and not rec.temporary then
		local ok, seconds = pcall(hold, feller)
		if ok and type(seconds) == "number" and seconds > 0 then
			TreeService.HoldRegrow(uid, seconds)
		elseif not ok then
			warn("[TreeService] StumpHold failed: " .. tostring(seconds))
		end
	end
	return feller
end

-- Keeps a felled tree's stump for at least `seconds` more (at most
-- MAX_HOLD) before the tree grows back on its own; never brings it back
-- sooner. Planting a Heartseed in it still regrows it early. Nothing for a
-- standing tree or an Elder's stump.
function TreeService.HoldRegrow(uid: string, seconds: number)
	local rec = trees[uid]
	local at = if rec and rec.felled and not rec.temporary then rec.regrowAt else nil
	if not rec or not at or seconds ~= seconds then
		return
	end
	local untilAt = math.max(rec.heldUntil or 0, os.clock() + math.clamp(seconds, 0, MAX_HOLD))
	rec.heldUntil = untilAt
	rec.regrowAt = math.max(at, untilAt)
end

-- Brings a felled tree back: whole HP, stump gone, standing again (clients
-- play it growing). Also used to regrow a tree early (a planted Heartseed):
-- `planterId` marks who planted it (nil = it grew back wild).
function TreeService.Regrow(uid: string, planterId: number?)
	local rec = trees[uid]
	if not rec or not rec.felled then
		return
	end
	rec.planterId = planterId
	rec.model:SetAttribute("PlanterId", planterId)
	removeStump(rec)
	rec.hp = rec.maxHp
	rec.damageBy = {}
	rec.model:SetAttribute("HP", rec.hp)
	rec.felled = false
	rec.regrowAt = nil
	rec.heldUntil = nil
	rec.model:SetAttribute("Felled", false)
	if not rec.dormant then
		setTreeVisible(rec, true)
		makeSolid(rec)
		rec.alive = true
	end
	local onRegrown = TreeService.OnRegrown
	if onRegrown then
		task.spawn(onRegrown, rec)
	end
end

-- Hides (or brings back) every tree of a biome, e.g. the Phantom Grove by
-- day. A tree that's down stays down until it regrows.
function TreeService.SetBiomeDormant(biomeId: string, dormant: boolean)
	for _, rec in pairs(trees) do
		if rec.def.biome == biomeId and rec.dormant ~= dormant then
			rec.dormant = dormant
			rec.model:SetAttribute("Dormant", dormant) -- clients don't aim at hidden trees
			setStumpVisible(rec, not dormant)
			if dormant and rec.alive then
				rec.alive = false
				rec.ghost = false
				rec.hp = rec.maxHp -- a half-chopped tree is whole again tomorrow night
				rec.damageBy = {}
				rec.model:SetAttribute("HP", rec.hp)
				setTreeVisible(rec, false)
			elseif not dormant and not rec.felled then
				setTreeVisible(rec, true)
				makeSolid(rec) -- a truck may have parked on its spot by day
				rec.alive = true
			end
		end
	end
end

-- The wood of a standing tree, or nil if there's no such tree up right now.
function TreeService.GetTreeWood(uid: string): WoodDef?
	local rec = trees[uid]
	return if rec and rec.alive then rec.def else nil
end

-- The record behind a tree (standing or not), for the forest systems.
function TreeService.GetTree(uid: string): TreeRecord?
	return trees[uid]
end

-- Every tree record (read-only use: counting, finding a tree to strike).
function TreeService.AllTrees(): { [string]: TreeRecord }
	return trees
end

-- Seconds until a felled tree grows back on its own (nil if it isn't down,
-- or never will: an Elder).
function TreeService.RegrowsIn(uid: string): number?
	local rec = trees[uid]
	local at = if rec and rec.felled then rec.regrowAt else nil
	return if at then math.max(0, at - os.clock()) else nil
end

-- Validates range server-side, applies the axe's damage for this tree's
-- biome, returns new HP (nil + reason on reject) and, if this swing felled
-- it, the player the felling counts for (the one who chopped the most).
function TreeService.ApplyChop(player: Player, treeUid: string, axe: ItemCatalog.AxeDef): (number?, string?, Player?)
	local rec = trees[treeUid]
	if not rec or not rec.alive then
		return nil, "gone"
	end
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not hrp then
		return nil, "nochar"
	end
	local offset = hrp.Position - rec.base
	local horizontal = Vector3.new(offset.X, 0, offset.Z).Magnitude
	if
		horizontal - rec.radius > GameConfig.ChopRange + GameConfig.RangeTolerance
		or math.abs(offset.Y) > rec.def.trunkHeight * rec.size.scale + 10
	then
		return nil, "far"
	end
	local damage = ItemCatalog.AxeDamage(axe, rec.def)
	if damage <= 0 then
		return nil, "tooHard"
	end
	local dealt = math.min(damage, rec.hp)
	rec.hp = math.max(0, rec.hp - damage)
	rec.damageBy[player.UserId] = (rec.damageBy[player.UserId] or 0) + dealt
	rec.model:SetAttribute("HP", rec.hp)
	if rec.hp <= 0 then
		return rec.hp, nil, fellTree(player, treeUid)
	end
	return rec.hp, nil, nil
end

function TreeService.GetLog(uid: string): LogRecord?
	return logs[uid]
end

-- Marks a world log as carried (caller welds the model). False if unavailable.
function TreeService.ClaimLog(uid: string): boolean
	local rec = logs[uid]
	if not rec or rec.state ~= "world" then
		return false
	end
	rec.state = "carried"
	local pp = rec.model.PrimaryPart
	if pp then
		local prompt = pp:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt:Destroy()
		end
		-- Carried logs mustn't catch the chop pointer meant for a tree.
		pp.CanQuery = false
	end
	return true
end

-- Removes the log record entirely (sold / loaded). The caller destroys the model.
-- A left-behind log, saved where it lay (profile.leftLoad).
export type LeftLog = { woodId: string, value: number, figure: string?, x: number, y: number, z: number }

-- Takes every log left behind for `ownerId` (a truck load left where the
-- truck stood, tag leftBehind) that's still lying in the world out of it,
-- and returns what and where they were (saved when the owner leaves).
function TreeService.TakeLeftBehind(ownerId: number): { LeftLog }
	local out: { LeftLog } = {}
	for uid, rec in pairs(logs) do
		if rec.ownerId == ownerId and rec.state == "world" and rec.tags.leftBehind == true then
			local pp = rec.model.PrimaryPart
			if pp then
				local p = pp.CFrame.Position
				local figure = rec.tags.figure
				table.insert(out, {
					woodId = rec.def.id,
					value = rec.value,
					figure = if type(figure) == "string" then figure else nil,
					x = p.X,
					y = p.Y,
					z = p.Z,
				})
			end
			logs[uid] = nil
			rec.model:Destroy()
		end
	end
	return out
end

function TreeService.TakeLog(uid: string): LogRecord?
	local rec = logs[uid]
	logs[uid] = nil
	return rec
end

-- Drops a carried log back onto the ground near `nearPos` (player died or
-- left). The dropper gets the pickup grace window again.
function TreeService.DropLog(uid: string, nearPos: Vector3, dropper: Player)
	local rec = logs[uid]
	if not rec or rec.state ~= "carried" then
		return
	end
	local pp = rec.model.PrimaryPart
	if not pp or pp.Parent == nil then
		-- Lost with its carrier (fell into the void): nothing left to drop.
		logs[uid] = nil
		rec.model:Destroy()
		return
	end
	for _, child in ipairs(pp:GetChildren()) do
		if child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end
	local spot = nearPos + Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
	local y = groundY(groundParams(), spot.X, spot.Z, nearPos.Y, spot.Y - 3)
	pp.Anchored = true
	pp.Massless = false
	pp.CanQuery = true
	pp.CFrame = CFrame.new(spot.X, y + LOG_DIAMETER / 2, spot.Z) * CFrame.Angles(0, math.random() * math.pi, 0)
	addPickupPrompt(pp, uid, rec.def)
	rec.state = "world"
	rec.ownerId = dropper.UserId
	rec.fellTime = os.time()
	rec.graceUntil = nil -- dropped again: the usual rules
	rec.despawnSec = nil
	scheduleDespawn(uid, rec)
end

return TreeService
