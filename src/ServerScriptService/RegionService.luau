--!strict
-- RegionService: the Bayou and Red Mesa (Lane R). Builds their art into the
-- map, and owns what happens in them:
--   * The quarry: a prompt on each of the eight SlabNodes gives one sandstone
--     slab (BuildMaterials.ReturnSlab: the carried slab Lane F fills pieces
--     with, at most SlabData.MaxLoose a player). A node refills on a timer
--     (Shared/Regions/QuarryLogic). Needs Stage 4. Slabs sell for $0 and the
--     Ore Chute refuses them (SlabData); they survive a rejoin through the
--     loose save (LooseService).
--   * The rare finds: one prompt at each UniqueItemSpawn anchor
--     (Shared/Regions/RegionItems). Both ship disabled ("Something rare lives
--     here"); the spawn, pickup and save paths are live and tested.
--   * The Bait Shack counter: Wader Boots for $2,000 plus 20 u³ of Bog Cypress
--     planks laid by the counter. The boots remove the Bayou's mud slowdown
--     (BiomeService reads MudLogic).
--   * First visits: the first time a slot enters each region, its name shows
--     once (a toast until Lane E's banner lands) and MilestoneService hears
--     ("area", { id }) so badges can listen.
-- Prompts are ProximityPrompts (touch, mouse, keyboard and controller work),
-- not remotes; every handler checks stage, distance, ownership and the rate
-- through RateLimiter. Only EconomyService touches cash. RegionBoot starts it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BayouData = require(ReplicatedStorage.Shared.Regions.BayouData)
local BiomeData = require(ReplicatedStorage.Shared.BiomeData)
local BuildMaterials = require(script.Parent.BuildMaterials)
local EconomyService = require(script.Parent.EconomyService)
local HandInLogic = require(ReplicatedStorage.Shared.HandInLogic)
local HandInWood = require(script.Parent.HandInWood)
local InputKit = require(ReplicatedStorage.Shared.InputKit)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local MesaData = require(ReplicatedStorage.Shared.Regions.MesaData)
local MilestoneService = require(script.Parent.MilestoneService)
local MudLogic = require(ReplicatedStorage.Shared.Regions.MudLogic)
local ProfileService = require(script.Parent.ProfileService)
local QuarryLogic = require(ReplicatedStorage.Shared.Regions.QuarryLogic)
local RateLimiter = require(script.Parent.RateLimiter)
local RegionArt = require(ReplicatedStorage.Shared.Art.RegionArt)
local RegionItems = require(ReplicatedStorage.Shared.Regions.RegionItems)
local RegionScatter = require(ReplicatedStorage.Shared.Regions.RegionScatter)
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)
local SlabData = require(ReplicatedStorage.Shared.SlabData)
local StageOf = require(ReplicatedStorage.Shared.StageOf)
local TerrainGen = require(ReplicatedStorage.Shared.World.TerrainGen)
local WorldPlan = require(ReplicatedStorage.Shared.World.WorldPlan)

local RegionService = {}

local RATE = "RegionAction"
local SWEEP_SECONDS = 2

local quarry: QuarryLogic.State = QuarryLogic.New()
local anchors: RegionItems.Anchors = RegionItems.NewAnchors()
local counterAt: Vector3? = nil -- the Bait Shack counter (set when it is built)
local nodeAt: { [string]: Vector3 } = {}
local findAt: { [string]: Vector3 } = {}
local warned: { [Player]: { [string]: boolean } } = {}
local started = false

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local notifyOverride: ((Player, string) -> ())? = nil

local function notify(player: Player, text: string)
	if notifyOverride then
		notifyOverride(player, text)
		return
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = if remotes then remotes:FindFirstChild("Notify") else nil
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, text)
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function stageOf(profile: any): number
	return StageOf.Current(profile)
end

local function stamps(profile: any): { [string]: boolean }
	if type(profile.guideStamps) ~= "table" then
		profile.guideStamps = {}
	end
	return profile.guideStamps
end

local function gearSet(profile: any): { [string]: boolean }
	local set: { [string]: boolean } = {}
	if type(profile.gear) == "table" then
		for _, id in ipairs(profile.gear) do
			set[id] = true
		end
	end
	return set
end

local function distance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

---------------------------------------------------------------------------
-- The quarry
---------------------------------------------------------------------------

-- A player works a slab node. Returns whether a slab was made (for specs).
function RegionService.Quarry(player: Player, nodeId: unknown): boolean
	if not RateLimiter.Allow(player, RATE) then
		return false
	end
	local profile = ProfileService.GetProfile(player)
	local root = rootOf(player)
	if profile == nil or root == nil or type(nodeId) ~= "string" then
		return false
	end
	local at: Vector3? = nodeAt[nodeId]
	local now = os.clock()
	local verdict = QuarryLogic.Check(quarry, nodeId, now, {
		known = at ~= nil,
		distance = if at then distance(root.Position, at) else math.huge,
		loose = SlabData.MaxLoose - BuildMaterials.SlabRoom(player.UserId),
		stage = stageOf(profile),
	})
	if not verdict.ok then
		if verdict.reason then
			notify(player, verdict.reason)
		end
		return false
	end
	-- Take the node first, so a second prompt in the same frame finds it empty.
	QuarryLogic.Take(quarry, nodeId, now)
	local c = MesaData.Centre
	local out = Vector3.new(c.x - (at :: Vector3).X, 0, c.z - (at :: Vector3).Z).Unit
	local spawn = (at :: Vector3) + out * 5 + Vector3.new(0, 3, 0)
	if not BuildMaterials.ReturnSlab(player.UserId, CFrame.lookAt(spawn, spawn + out)) then
		QuarryLogic.Refund(quarry, nodeId)
		notify(player, "No room for another slab.")
		return false
	end
	notify(player, "You quarried a sandstone slab. Carry it to your plot for the building kit.")
	return true
end

---------------------------------------------------------------------------
-- The rare finds
---------------------------------------------------------------------------

-- A player uses the prompt at a region's anchor. Returns whether they found it.
function RegionService.Find(player: Player, anchorId: unknown): boolean
	if not RateLimiter.Allow(player, RATE) then
		return false
	end
	local profile = ProfileService.GetProfile(player)
	local root = rootOf(player)
	if profile == nil or root == nil or type(anchorId) ~= "string" then
		return false
	end
	local item = RegionItems.ForAnchor(anchorId)
	local at: Vector3? = findAt[anchorId]
	if item == nil or at == nil then
		return false
	end
	local pos = root.Position
	local place = BiomeData.RegionAt(pos.X, pos.Z)
	local verdict = RegionItems.Pick(anchors, item, os.clock(), {
		region = place or "",
		distance = distance(pos, at),
		stage = stageOf(profile),
		hasIt = RegionItems.Has(profile.guideStamps, item.id),
		frame = os.clock(),
	})
	if not verdict.ok then
		if verdict.reason then
			notify(player, verdict.reason)
		end
		return false
	end
	RegionItems.Stamp(stamps(profile), item.id)
	notify(player, string.format("You found the %s!", item.name))
	return true
end

---------------------------------------------------------------------------
-- The Bait Shack counter: Wader Boots
---------------------------------------------------------------------------

-- A player asks for Wader Boots at the counter. Returns whether they got them.
function RegionService.BuyBoots(player: Player): boolean
	if not RateLimiter.Allow(player, RATE) then
		return false
	end
	local profile = ProfileService.GetProfile(player)
	local root = rootOf(player)
	local counter = counterAt
	if profile == nil or root == nil or counter == nil then
		return false
	end
	local boots = BayouData.WaderBoots
	local gear = ItemCatalog.GetGear(boots.gearId)
	if gear == nil then
		return false
	end
	if gearSet(profile)[boots.gearId] then
		notify(player, "You already have your Wader Boots.")
		return false
	end
	if stageOf(profile) < BayouData.NeedsStage then
		notify(player, "Come back when you are further along. " .. BayouData.GateLine .. ".")
		return false
	end
	if distance(root.Position, counter) > 14 then
		notify(player, "Step up to the counter.")
		return false
	end
	local list, byUid = HandInWood.Near(counter)
	local have = HandInLogic.Planks(list, player.UserId)[boots.woodId] or 0
	if have + 1e-6 < boots.planksU3 then
		notify(
			player,
			string.format(
				"Wader Boots: %s and %d u³ of Bog Cypress planks laid by the counter (you have %.0f).",
				"$" .. tostring(boots.priceCash),
				boots.planksU3,
				have
			)
		)
		return false
	end
	if EconomyService.GetCash(player) < boots.priceCash then
		notify(player, string.format("You need $%d for the Wader Boots.", boots.priceCash))
		return false
	end
	-- Cash first: if it does not go through, nothing else moves. Then the
	-- planks, then the boots.
	if not EconomyService.SpendCash(player, boots.priceCash, "bought " .. gear.displayName, gear.id) then
		return false
	end
	HandInWood.Take(byUid, HandInLogic.PickPlanks(list, player.UserId, boots.woodId, boots.planksU3), "wader boots")
	if type(profile.gear) ~= "table" then
		profile.gear = {}
	end
	table.insert(profile.gear, gear.id)
	player:SetAttribute("OwnedGear", ShopLogic.EncodeSet(profile.gear))
	notify(player, "You got the Wader Boots! The Bayou's mud will not slow you down.")
	return true
end

---------------------------------------------------------------------------
-- First visits and the gate line
---------------------------------------------------------------------------

local REGION_LINES: { [string]: { toast: string, gate: string, stage: number } } = {
	bayou = { toast = BayouData.Toast, gate = BayouData.GateLine, stage = BayouData.NeedsStage },
	mesa = { toast = MesaData.Toast, gate = MesaData.GateLine, stage = MesaData.NeedsStage },
}

-- One sweep over the players: a first visit shows the region's name once and
-- tells MilestoneService; a visitor short of the stage hears what it asks for
-- (once a visit).
function RegionService.Sweep()
	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootOf(player)
		local profile = ProfileService.GetProfile(player)
		if root and profile then
			local pos = root.Position
			local id = BiomeData.RegionAt(pos.X, pos.Z)
			local line = if id then REGION_LINES[id] else nil
			if id and line then
				local seen = RegionItems.SeenKey(id)
				local map = stamps(profile)
				if map[seen] ~= true then
					map[seen] = true
					notify(player, line.toast)
					MilestoneService.Event(player, "area", { id = id })
				end
				local w = warned[player]
				if w == nil then
					w = {}
					warned[player] = w
				end
				if stageOf(profile) < line.stage and not w[id] then
					w[id] = true
					notify(player, line.gate .. ".")
				end
			else
				warned[player] = nil
			end
		end
	end
end

---------------------------------------------------------------------------
-- The world
---------------------------------------------------------------------------

local function prompt(
	part: BasePart,
	name: string,
	action: string,
	object: string,
	hold: number,
	input: string,
	fn: (Player) -> ()
)
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold
	p.MaxActivationDistance = 12
	InputKit.PromptDefaults(p, input)
	p.RequiresLineOfSight = false
	p.Parent = part
	p.Triggered:Connect(fn)
end

local function scatter(parent: Instance, regionId: string, ground: RegionArt.Ground)
	local trees: { Vector3 } = {}
	for _, spot in ipairs(WorldPlan.RegionTrees()) do
		table.insert(trees, spot.position)
	end
	local folder = Instance.new("Folder")
	folder.Name = "Scatter_" .. regionId
	for _, site in ipairs(RegionScatter.Sites(regionId, trees, TerrainGen.RoadClearance)) do
		local piece = RegionArt.Scatter(site.kind, site.seed)
		if piece then
			piece:PivotTo(CFrame.new(site.x, ground(site.x, site.z), site.z) * CFrame.Angles(0, site.yaw, 0))
			piece.Parent = folder
		end
	end
	folder.Parent = parent
end

-- Builds both regions into `parent` (a Folder under the map) and hangs the
-- prompts. `ground` is the terrain's height at a point. Returns the Folder.
function RegionService.Build(parent: Instance, ground: RegionArt.Ground): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Regions"
	-- The Bayou.
	local bayou = Instance.new("Folder")
	bayou.Name = "Bayou"
	bayou.Parent = folder
	RegionArt.MudAndPools(bayou, ground)
	local walk = RegionArt.Boardwalk(bayou, ground)
	local deckTop = (walk:GetAttribute("DeckTop") :: number?)
		or ground(BayouData.Boardwalk.x, BayouData.Boardwalk.z) + 1.4
	local shack = RegionArt.BaitShack(bayou, ground, deckTop)
	RegionArt.Lanterns(bayou, ground, deckTop)
	RegionArt.Landing(bayou, ground)
	RegionArt.RarePlinth(bayou, ground)
	RegionArt.MistZone(bayou, ground)
	scatter(bayou, "bayou", ground)
	-- Red Mesa.
	local mesa = Instance.new("Folder")
	mesa.Name = "RedMesa"
	mesa.Parent = folder
	local quarryModel = RegionArt.QuarryFace(mesa, ground)
	RegionArt.MesaLanterns(mesa, ground)
	local overlookModel = RegionArt.Overlook(mesa, ground)
	local archModel = RegionArt.Arch(mesa, ground)
	RegionArt.Butte(mesa, ground)
	scatter(mesa, "mesa", ground)

	-- The Bait Shack counter: the boots.
	local counter = shack:FindFirstChild("Counter")
	if counter and counter:IsA("BasePart") then
		counterAt = counter.CFrame.Position
		local boots = BayouData.WaderBoots
		prompt(
			counter,
			"WaderBoots",
			string.format("Wader Boots $%d + %d u³ cypress planks", boots.priceCash, boots.planksU3),
			"Bait Shack",
			0,
			"Buy",
			function(player: Player)
				RegionService.BuyBoots(player)
			end
		)
	end
	-- The quarry's nodes.
	for _, inst in ipairs(mesa:GetDescendants()) do
		if inst:IsA("BasePart") and inst.Name == "SlabNode" then
			local id = inst:GetAttribute("NodeId")
			if type(id) == "string" then
				nodeAt[id] = inst.CFrame.Position
				prompt(
					inst,
					"Quarry",
					"Quarry a slab",
					"Sandstone",
					MesaData.Quarry.holdSec,
					"Interact",
					function(player: Player)
						RegionService.Quarry(player, id)
					end
				)
			end
		end
	end
	-- The rare finds.
	for _, regionFolder in ipairs({ bayou, mesa }) do
		for _, inst in ipairs(regionFolder:GetDescendants()) do
			if inst:IsA("BasePart") and inst:GetAttribute("UniqueSpot") == true then
				local anchorId = if regionFolder == bayou then "bayou" else "redmesa"
				findAt[anchorId] = inst.CFrame.Position
				local item = RegionItems.ForAnchor(anchorId)
				prompt(
					inst,
					"RareFind",
					"Look around",
					if item then item.name else "Rare find",
					0,
					"Interact",
					function(player: Player)
						RegionService.Find(player, anchorId)
					end
				)
			end
		end
	end
	folder.Parent = parent
	-- The boot log's budget line (Lane R, phone budgets): parts a region holds.
	print(
		string.format(
			"[RegionService] built: Bayou %d parts (boardwalk %d, Bait Shack %d), Red Mesa %d parts (quarry %d, overlook %d, arch %d)",
			RegionArt.PartCount(bayou),
			RegionArt.PartCount(walk),
			RegionArt.PartCount(shack),
			RegionArt.PartCount(mesa),
			RegionArt.PartCount(quarryModel),
			RegionArt.PartCount(overlookModel),
			RegionArt.PartCount(archModel)
		)
	)
	return folder
end

-- Starts the sweep and builds the regions into the map when it is there. A
-- second call does nothing.
function RegionService.Init()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local map = workspace:WaitForChild("TimberlineMap", 120)
		if map then
			local ok, err = pcall(function(): any
				RegionService.Build(map, TerrainGen.HeightAt)
				return nil
			end)
			if not ok then
				warn("[RegionService] build failed: " .. tostring(err))
			end
		end
	end)
	task.spawn(function()
		while started do
			task.wait(SWEEP_SECONDS)
			local ok, err = pcall(function(): any
				RegionService.Sweep()
				return nil
			end)
			if not ok then
				warn("[RegionService] sweep failed: " .. tostring(err))
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		warned[player] = nil
	end)
end

-- For specs: where toasts go.
function RegionService.SetNotify(fn: ((Player, string) -> ())?)
	notifyOverride = fn
end

-- For specs: forget the quarry and the anchors.
function RegionService.Reset()
	quarry = QuarryLogic.New()
	anchors = RegionItems.NewAnchors()
	table.clear(nodeAt)
	table.clear(findAt)
	table.clear(warned)
	counterAt = nil
end

-- For specs: where a node, an anchor or the counter is.
function RegionService.SetSpots(nodes: { [string]: Vector3 }?, finds: { [string]: Vector3 }?, counter: Vector3?)
	for id, v in pairs(nodes or {}) do
		nodeAt[id] = v
	end
	for id, v in pairs(finds or {}) do
		findAt[id] = v
	end
	if counter then
		counterAt = counter
	end
end

-- The mud check BiomeService runs, for a spec to see the same answer.
RegionService.MudFactor = MudLogic.Factor

return RegionService
