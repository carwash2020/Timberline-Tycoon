--!strict
-- TreeService: owns every tree and log in the world.
--   * Trees are built by Shared/Art/TreeArt (one silhouette per wood) in a
--     size class (Shared/TreeLogic: small, normal or large; big trees take
--     more chopping and drop an extra log).
--   * Server-side HP; ApplyChop validates range and applies axe damage.
--     Hit feedback (shake, chips, sound) is drawn on each client by TreeFX.
--   * Felling: the tree tips away from whoever felled it. The server never
--     moves the tree: it sets Felled / FallDir / FellAt and every client
--     animates the fall smoothly (TreeFX). When it has landed, the server
--     hides it, leaves a stump, and lays exactly the tree's logs along the
--     fall line. After the wood's respawnSec the stump goes and the tree
--     is back (clients play it growing from a sapling).
--   * Night-only woods (the Phantom Grove): SetBiomeDormant hides a biome's
--     trees by day and brings them back at night (WorldClock).
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

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local TreeArt = require(ReplicatedStorage.Shared.Art.TreeArt)
local TreeLogic = require(ReplicatedStorage.Shared.TreeLogic)
local Util = require(ReplicatedStorage.Shared.Util)
local WoodData = require(ReplicatedStorage.Shared.WoodData)

type WoodDef = WoodData.WoodDef

local TreeService = {}

local TREE_TAG = "Tree"
local LOG_TAG = "Log"
local LOG_LENGTH = 3
local LOG_DIAMETER = 1.2
local LOG_GAP = 0.25
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
}

local trees: { [string]: TreeRecord } = {}
local logs: { [string]: LogRecord } = {}
local treeCounters: { [string]: number } = {}

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
		seed = seed,
		planterId = opts.planterId,
		damageBy = {},
		temporary = opts.temporary == true,
		growth = 0,
	}
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

local function setTreeVisible(rec: TreeRecord, visible: boolean)
	for part, state in pairs(rec.parts) do
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

local function removeStump(rec: TreeRecord)
	if rec.stump then
		rec.stump:Destroy()
		rec.stump = nil
	end
end

local function placeStump(rec: TreeRecord)
	removeStump(rec)
	local stump = TreeArt.Stump(rec.def, rec.seed, rec.size.scale)
	stump.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	Kit.placeAt(stump, CFrame.new(rec.base) * CFrame.Angles(0, Kit.rng(rec.seed + 202):range(0, math.pi * 2), 0))
	stump:SetAttribute("WoodId", rec.def.id)
	stump:SetAttribute("TreeUid", rec.uid)
	CollectionService:AddTag(stump, "Stump")
	stump.Parent = getFolder("Stumps")
	rec.stump = stump
end

-- Log despawn: each (re)entry into the world gets a fresh token, so an old
-- timer can't delete a log that was picked up and dropped again since.
local function scheduleDespawn(uid: string, rec: LogRecord)
	rec.despawnToken += 1
	local token = rec.despawnToken
	task.delay(GameConfig.LogDespawnSec, function()
		if logs[uid] == rec and rec.state == "world" and rec.despawnToken == token then
			logs[uid] = nil
			rec.model:Destroy()
		end
	end)
end

-- Spawns one pickup-able log at `cframe` (cylinder axis = the CFrame's X).
function TreeService.SpawnLog(def: WoodDef, cframe: CFrame, ownerId: number): (Model, string)
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
-- (trees on the Aether Isles stand far above the terrain).
local function groundY(params: RaycastParams, x: number, z: number, fromY: number, fallback: number): number
	local hit = workspace:Raycast(Vector3.new(x, fromY + 10, z), Vector3.new(0, -40, 0), params)
	return if hit then hit.Position.Y else fallback
end

local function fellTree(player: Player, uid: string)
	local rec = trees[uid]
	if not rec or not rec.alive then
		return
	end
	rec.alive = false
	rec.felled = true
	rec.growth += 1
	local growth = rec.growth
	local model = rec.model
	local fellerId = player.UserId

	-- Fall away from the feller, a little randomly.
	local char = player.Character
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
		local multiplier = if TreeService.LogMultiplier then TreeService.LogMultiplier(player) else 1
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
			task.spawn(onFelled, player, rec, uids, fallDir)
		end
	end)

	task.delay(if rec.temporary then TreeLogic.FallTime + 8 else rec.def.respawnSec, function()
		-- Planted back early and felled again since? That felling has its
		-- own timer.
		if trees[uid] ~= rec or rec.growth ~= growth then
			return
		end
		if rec.temporary then
			TreeService.Remove(uid)
		else
			TreeService.Regrow(uid)
		end
	end)
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
	rec.model:SetAttribute("Felled", false)
	if not rec.dormant then
		setTreeVisible(rec, true)
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
			local stump = rec.stump
			if stump then
				for _, d in ipairs(stump:GetDescendants()) do
					if d:IsA("BasePart") then
						d.Transparency = if dormant then 1 else 0
					end
				end
			end
			if dormant and rec.alive then
				rec.alive = false
				rec.hp = rec.maxHp -- a half-chopped tree is whole again tomorrow night
				rec.model:SetAttribute("HP", rec.hp)
				setTreeVisible(rec, false)
			elseif not dormant and not rec.felled then
				setTreeVisible(rec, true)
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

-- Validates range server-side, applies the axe's damage for this tree's
-- biome, returns new HP (nil + reason on reject).
function TreeService.ApplyChop(player: Player, treeUid: string, axe: ItemCatalog.AxeDef): (number?, string?)
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
		fellTree(player, treeUid)
	end
	return rec.hp, nil
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
	scheduleDespawn(uid, rec)
end

return TreeService
