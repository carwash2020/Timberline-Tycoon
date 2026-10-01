--!strict
-- ForestService: the Living Forest (GAME_DESIGN §16). Rules in
-- Shared/ForestLogic, numbers in Shared/ForestData, models in
-- Shared/Art/ForestArt, the screen side in ForestUI.
--   * The Hidden Grain: every tree that grows (in Init for the trees
--     MapBuilder planted, then on each regrow) may hide a figure; its bark
--     clue goes on the trunk (TreeService.Decorate). When it's felled, its
--     logs get the figure (value, tags.figure, a coloured band).
--   * Heartseeds: a felled tree's seeds fly to the feller (WorldFX
--     "SeedPop"); the pouch is profile.heartseeds, mirrored on the
--     Seeds_<woodId> and Heartseeds player attributes.
--   * PlantSeed(treeUid): validated (rate, a felled non-temporary tree with
--     its stump, in range, a seed of that wood); a sapling sprouts for
--     ForestData.SproutSeconds, then TreeService.Regrow marks the tree as
--     yours and a name stake goes up at its foot.
--   * The planter's share: someone else fells your tree, you get a share of
--     its logs' base value (EconomyService), if you're online. Felling your
--     own gives the steward's extra seed instead.
--   * Grove Vitality per ground grove: workspace attributes
--     Vitality_<biome> (0-100, one decimal) and VitalityTier_<biome>
--     ("Thinning" | "Healthy" | "Thriving" | "OldGrowth").
--   * Storms: WeatherService calls Strike(position); the nearest standing
--     tree glows for two minutes; felled in time its logs are Stormgrain.
--   * Elders: now and then a Thriving or Old Growth grove wakes a giant
--     (workspace ElderUid / ElderWood / ElderBiome / ElderPos); everyone who
--     chopped 10% of it shares the harvest, and its logs are free to grab.
--   * The Skyroot Bloom: the groves together thriving make the Skyroot
--     bloom (workspace SkyrootBloom), doubling figure chances.
-- WorldFX kinds sent to clients (payload tables): SeedPop, Sprout, Struck,
-- Elder, ElderFallen, ElderFaded, ElderShare, Royalty, Reveal.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BiomeData = require(ReplicatedStorage.Shared.BiomeData)
local ForestData = require(ReplicatedStorage.Shared.ForestData)
local ForestLogic = require(ReplicatedStorage.Shared.ForestLogic)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local TreeLogic = require(ReplicatedStorage.Shared.TreeLogic)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local ForestArt = require(ReplicatedStorage.Shared.Art.ForestArt)
local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local TerrainGen = require(ReplicatedStorage.Shared.World.TerrainGen)
local WorldPlan = require(ReplicatedStorage.Shared.World.WorldPlan)
local DailyService = require(script.Parent.DailyService)
local EconomyService = require(script.Parent.EconomyService)
local FieldGuideService = require(script.Parent.FieldGuideService)
local ProfileService = require(script.Parent.ProfileService)
local QuestService = require(script.Parent.QuestService)
local RateLimiter = require(script.Parent.RateLimiter)
local TreeService = require(script.Parent.TreeService)

type Profile = ProfileService.Profile
type TreeRecord = TreeService.TreeRecord

local ForestService = {}

export type Remotes = { PlantSeed: RemoteEvent, WorldFX: RemoteEvent }

-- Tests pass their own clock and dice, and tick by hand.
export type Options = {
	clock: (() -> number)?,
	random: (() -> number)?,
	manual: boolean?, -- no background loop: call ForestService.Tick(dt)
}

type Struck = { untilAt: number, glow: Instance }
type Elder = { uid: string, woodId: string, biome: string, wokeAt: number, aura: Model? }

local remotes: Remotes? = nil
local notify: (Player, string) -> () = function(_player: Player, _message: string) end
local clock: () -> number = os.clock
local random: () -> number = math.random

local figureOf: { [string]: string } = {} -- the figure each standing tree hides
local clueOf: { [string]: Instance } = {} -- its bark clue
local stakeOf: { [string]: Model } = {} -- planted trees' name stakes (in ForestMarks)
local planterName: { [string]: string } = {} -- who planted each tree, for its stake
local struck: { [string]: Struck } = {}
local sprouting: { [string]: boolean } = {}
local vitality: { [string]: number } = {}
local shownVitality: { [string]: number } = {}
local shownTier: { [string]: string } = {}
local elder: Elder? = nil
local nextElderCheck = 0
local bloomUntil = 0 -- clock time the bloom ends; 0 = not blooming
local bloomRestUntil = 0
local marks: Folder? = nil

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function fireAll(kind: string, payload: { [string]: any })
	local r = remotes
	if r then
		r.WorldFX:FireAllClients(kind, payload)
	end
end

local function fireOne(player: Player, kind: string, payload: { [string]: any })
	local r = remotes
	if r then
		r.WorldFX:FireClient(player, kind, payload)
	end
end

local function analytics(player: Player, name: string, value: number?)
	pcall(function()
		AnalyticsService:LogCustomEvent(player, name, value or 1)
	end)
end

-- Where stakes and auras live: a folder beside the trees, so they stay put
-- while a tree falls (bark clues fall with it: they're on the bark).
local function marksFolder(): Folder
	local existing = marks
	if existing and existing.Parent then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "ForestMarks"
	folder.Parent = workspace:FindFirstChild("TimberlineMap") or workspace
	marks = folder
	return folder
end

local function trunkOf(model: Model): BasePart?
	local trunk = model.PrimaryPart or model:FindFirstChild("Trunk")
	return if trunk and trunk:IsA("BasePart") then trunk else nil
end

local function forgetDecoration(uid: string, inst: Instance?)
	if inst then
		TreeService.Forget(uid, inst)
		inst:Destroy()
	end
end

local function isBlooming(): boolean
	return bloomUntil > 0
end

---------------------------------------------------------------------------
-- Grove Vitality
---------------------------------------------------------------------------

local function publishVitality(force: boolean?)
	for _, id in ipairs(ForestData.Groves) do
		local v = vitality[id] or ForestData.Vitality.rest
		local shown = math.floor(v * 10 + 0.5) / 10
		if force or shownVitality[id] ~= shown then
			shownVitality[id] = shown
			workspace:SetAttribute("Vitality_" .. id, shown)
		end
		local tier = ForestLogic.TierFor(v).id
		if force or shownTier[id] ~= tier then
			shownTier[id] = tier
			workspace:SetAttribute("VitalityTier_" .. id, tier)
		end
	end
end

local function changeVitality(biomeId: string, delta: number)
	if not ForestLogic.IsGrove(biomeId) then
		return
	end
	vitality[biomeId] = ForestLogic.ApplyVitality(vitality[biomeId] or ForestData.Vitality.rest, delta)
	publishVitality()
end

-- The tier a tree of this biome grows in (nil outside the groves).
local function tierFor(biomeId: string): string?
	if not ForestLogic.IsGrove(biomeId) then
		return nil
	end
	return ForestLogic.TierFor(vitality[biomeId] or ForestData.Vitality.rest).id
end

---------------------------------------------------------------------------
-- Heartseeds
---------------------------------------------------------------------------

local function publishSeeds(player: Player, profile: Profile)
	for _, wood in ipairs(WoodData.All()) do
		local n = profile.heartseeds[wood.id] or 0
		local attr = "Seeds_" .. wood.id
		if player:GetAttribute(attr) ~= n then
			player:SetAttribute(attr, n)
		end
	end
	player:SetAttribute("Heartseeds", ForestLogic.TotalSeeds(profile.heartseeds))
end

-- Puts up to `count` seeds of a wood in the player's pouch; they fly to
-- them from `from`. `reasons` explains the extras ("big tree", ...).
local function giveSeeds(player: Player, woodId: string, count: number, from: Vector3, reasons: { string }): number
	local profile = ProfileService.GetProfile(player)
	if not profile or count <= 0 then
		return 0
	end
	local added = ForestLogic.AddSeeds(profile.heartseeds, woodId, count)
	publishSeeds(player, profile)
	if added > 0 then
		fireAll("SeedPop", {
			pos = from,
			userId = player.UserId,
			woodId = woodId,
			count = added,
			reasons = reasons,
		})
	end
	if added < count then
		local s = ForestData.Seeds
		notify(
			player,
			string.format(
				"Your Heartseed pouch is full (%d of a wood, %d in all). Plant some!",
				s.maxPerWood,
				s.maxTotal
			)
		)
	end
	return added
end

---------------------------------------------------------------------------
-- Bark clues, stakes, storms
---------------------------------------------------------------------------

local function removeClue(uid: string)
	local clue = clueOf[uid]
	clueOf[uid] = nil
	forgetDecoration(uid, clue)
end

local function addClue(uid: string, figure: string)
	removeClue(uid)
	TreeService.Decorate(uid, function(model: Model, rec: TreeRecord)
		local trunk = trunkOf(model)
		if trunk then
			clueOf[uid] = ForestArt.BarkClue(model, trunk, rec.def, figure, rec.seed)
		end
	end)
end

local function removeStake(uid: string)
	local stake = stakeOf[uid]
	stakeOf[uid] = nil
	if stake then
		stake:Destroy()
	end
end

local function addStake(rec: TreeRecord)
	removeStake(rec.uid)
	local trunk = trunkOf(rec.model)
	local radius = if trunk then trunk.Size.Y / 2 else 1
	local name = planterName[rec.uid]
	local planterId = rec.planterId
	if not name and planterId then
		local planter = Players:GetPlayerByUserId(planterId)
		name = if planter then planter.DisplayName else nil
	end
	local stake = ForestArt.NameStake(name or "A friend", rec.seed)
	stake.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	stake:SetAttribute("TreeUid", rec.uid)
	stake:SetAttribute("PlanterId", planterId or 0)
	-- At the trunk's foot, on a side picked from the tree's seed, facing out
	-- (the stake's board faces -Z, the way CFrame.lookAt points).
	local angle = Kit.rng(rec.seed + 61):range(0, math.pi * 2)
	local out = Vector3.new(math.sin(angle), 0, math.cos(angle))
	local at = rec.base + out * (radius + 1.3)
	Kit.placeAt(stake, CFrame.lookAt(at, at + out))
	stake.Parent = if rec.dormant or rec.felled then nil else marksFolder()
	stakeOf[rec.uid] = stake
end

local function clearStruck(uid: string)
	local s = struck[uid]
	struck[uid] = nil
	if s then
		forgetDecoration(uid, s.glow)
	end
end

-- Rolls the hidden figure of a tree that has just grown.
local function rollFigure(rec: TreeRecord): string?
	local chance = ForestLogic.FigureChance(tierFor(rec.def.biome), rec.planterId ~= nil, isBlooming())
	return ForestLogic.RollFigure(rec.def.id, chance, random(), random(), random())
end

local function grow(rec: TreeRecord)
	removeClue(rec.uid)
	clearStruck(rec.uid)
	local figure = rollFigure(rec)
	figureOf[rec.uid] = nil
	if figure then
		figureOf[rec.uid] = figure
		addClue(rec.uid, figure)
	end
end

---------------------------------------------------------------------------
-- Elders
---------------------------------------------------------------------------

local function setElderAttributes(e: Elder?, pos: Vector3?)
	workspace:SetAttribute("ElderUid", if e then e.uid else "")
	workspace:SetAttribute("ElderWood", if e then e.woodId else "")
	workspace:SetAttribute("ElderBiome", if e then e.biome else "")
	workspace:SetAttribute("ElderPos", pos)
end

local function clearElder()
	local e = elder
	elder = nil
	if e and e.aura then
		e.aura:Destroy()
	end
	setElderAttributes(nil, nil)
end

-- A spot an Elder may grow on: WorldPlan's test for trees, a little
-- stricter for a giant (further from roads, flatter).
local function goodGround(x: number, z: number): boolean
	return WorldPlan.GoodGround(x, z, 9, 0.6)
end

-- One of a grove's woods, weighted by how many of each it grows.
local function woodForGrove(biome: BiomeData.BiomeDef): string?
	local counts = biome.trees
	if not counts then
		return nil
	end
	local ids: { string } = {}
	local total = 0
	for id, n in pairs(counts) do
		if WoodData.Get(id) and n > 0 then
			table.insert(ids, id)
			total += n
		end
	end
	if #ids == 0 then
		return nil
	end
	table.sort(ids)
	local roll = random() * total
	for _, id in ipairs(ids) do
		roll -= counts[id]
		if roll < 0 then
			return id
		end
	end
	return ids[#ids]
end

local function wakeElder(biomeId: string): string?
	local biome = BiomeData.Get(biomeId)
	local area = if biome then biome.area else nil
	if not biome or not area then
		return nil
	end
	local woodId = woodForGrove(biome)
	local def = if woodId then WoodData.Get(woodId) else nil
	if not woodId or not def then
		return nil
	end
	local gap = ForestData.Elder.minGap
	local x, z = ForestLogic.FindSpot(area.x, area.z, area.radius - 12, 60, random, function(px: number, pz: number)
		if not goodGround(px, pz) then
			return false
		end
		for _, rec in pairs(TreeService.AllTrees()) do
			local dx, dz = rec.base.X - px, rec.base.Z - pz
			if dx * dx + dz * dz < gap * gap then
				return false
			end
		end
		return true
	end)
	if not x or not z then
		return nil
	end
	local base = Vector3.new(x, TerrainGen.HeightAt(x, z) - 0.3, z)
	local model = TreeService.SpawnTree(woodId, CFrame.new(base), {
		size = ForestLogic.ElderSize(def),
		seed = math.floor(random() * 99999) + 1,
		temporary = true,
	})
	model:SetAttribute("Elder", true)
	local uid = model:GetAttribute("Uid")
	if type(uid) ~= "string" then
		return nil
	end
	local figure = ForestLogic.PickFigure(woodId, random(), random(), ForestData.Elder.figures)
	figureOf[uid] = figure
	addClue(uid, figure)
	local trunk = trunkOf(model)
	local aura = ForestArt.ElderAura((if trunk then trunk.Size.Y else 3) * 1.6 + 2)
	aura.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	Kit.placeAt(aura, CFrame.new(base))
	aura:SetAttribute("TreeUid", uid)
	aura.Parent = marksFolder()
	local e: Elder = { uid = uid, woodId = woodId, biome = biomeId, wokeAt = clock(), aura = aura }
	elder = e
	setElderAttributes(e, base)
	fireAll("Elder", { uid = uid, pos = base, woodId = woodId, biome = biomeId })
	return uid
end

local function elderInterval(): number
	local e = ForestData.Elder
	return e.checkMinSeconds + (e.checkMaxSeconds - e.checkMinSeconds) * random()
end

local function checkElder()
	if elder ~= nil then
		return
	end
	local groves: { ForestLogic.GroveState } = {}
	for _, id in ipairs(ForestData.Groves) do
		local biome = BiomeData.Get(id)
		-- Night-only groves (the Phantom Grove) only wake one at night.
		local awake = biome ~= nil and (not biome.nightOnly or workspace:GetAttribute("IsNight") == true)
		if biome and biome.area and biome.trees and awake then
			table.insert(groves, { biome = id, vitality = vitality[id] or ForestData.Vitality.rest })
		end
	end
	local pick = ForestLogic.PickElderGrove(groves, random(), random())
	if pick then
		wakeElder(pick)
	end
end

-- Everyone who chopped enough shares an Elder's harvest.
local function elderFallen(feller: Player, rec: TreeRecord, figure: string?)
	local e = ForestData.Elder
	local def = rec.def
	local logCount = TreeLogic.LogCount(def.logsPerTree, rec.size, 1)
	local bonus = ForestLogic.HelperBonus(logCount * ForestLogic.LogValue(def.pricePerLog, figure))
	local helpers = ForestLogic.Helpers(rec.damageBy, rec.maxHp)
	local paid = 0
	for _, userId in ipairs(helpers) do
		local helper = Players:GetPlayerByUserId(userId)
		local profile = if helper then ProfileService.GetProfile(helper) else nil
		if helper and profile then
			paid += 1
			local credited = EconomyService.AddCash(helper, bonus, "Elder helper's bonus: " .. def.id, "elder")
			profile.forest.elders += 1
			giveSeeds(helper, def.id, e.helperSeeds, rec.base, { "Elder" })
			fireOne(helper, "ElderShare", { woodId = def.id, amount = credited, seeds = e.helperSeeds })
			analytics(helper, "ElderFelled", #helpers)
		end
	end
	fireAll("ElderFallen", {
		woodId = def.id,
		biome = def.biome,
		feller = feller.DisplayName,
		helpers = paid,
		pos = rec.base,
	})
	clearElder()
end

---------------------------------------------------------------------------
-- TreeService hooks
---------------------------------------------------------------------------

local function payPlanter(planterId: number, feller: Player, rec: TreeRecord)
	local planter = Players:GetPlayerByUserId(planterId)
	local profile = if planter then ProfileService.GetProfile(planter) else nil
	if not planter or not profile then
		return -- the share is for planters who are here to see it
	end
	local def = rec.def
	local amount = ForestLogic.Royalty(def.pricePerLog, TreeLogic.LogCount(def.logsPerTree, rec.size, 1))
	local credited = EconomyService.AddCash(planter, amount, "planter's share: " .. def.id, "royalty")
	profile.forest.harvested += 1
	profile.forest.royalties += credited
	fireOne(planter, "Royalty", { woodId = def.id, feller = feller.DisplayName, amount = credited })
	analytics(planter, "PlanterShare", credited)
end

-- A felled tree has landed and its logs are down.
local function onFelled(player: Player, rec: TreeRecord, logUids: { string }, _fallDir: Vector3)
	local uid = rec.uid
	local def = rec.def
	local hidden = figureOf[uid]
	figureOf[uid] = nil
	local wasStruck = struck[uid] ~= nil
	local figure = if wasStruck then ForestLogic.StruckFigure(hidden) else hidden
	clearStruck(uid)
	removeClue(uid)
	removeStake(uid)
	planterName[uid] = nil
	local current = elder
	local isElder = current ~= nil and current.uid == uid

	for _, logUid in ipairs(logUids) do
		local log = TreeService.GetLog(logUid)
		if log then
			if figure then
				log.value = ForestLogic.LogValue(def.pricePerLog, figure)
				log.tags.figure = figure
				log.model:SetAttribute("Value", log.value)
				log.model:SetAttribute("Figure", figure)
				local part = log.model.PrimaryPart
				if part then
					ForestArt.FigureBand(part, figure)
				end
			end
			if isElder then
				-- Free to grab at once: past the feller's pickup grace.
				log.fellTime = os.time() - GameConfig.PickupGraceSec - 1
			end
		end
	end

	local planterId = rec.planterId
	changeVitality(def.biome, ForestLogic.FellDelta(planterId ~= nil))

	local steward = planterId == player.UserId
	local roll = random()
	local facts: ForestLogic.DropFacts = {
		large = ForestLogic.IsLarge(rec.size),
		storm = wasStruck,
		steward = steward,
		roll = roll,
	}
	local reasons: { string } = {}
	if facts.large then
		table.insert(reasons, if isElder then "Elder" else "big tree")
	end
	if roll < ForestData.Seeds.rollChance then
		table.insert(reasons, "lucky")
	end
	if wasStruck then
		table.insert(reasons, "storm-struck")
	end
	if steward then
		table.insert(reasons, "steward's bonus")
	end
	giveSeeds(player, def.id, ForestLogic.SeedDrop(facts), rec.base, reasons)

	if planterId and not steward then
		payPlanter(planterId, player, rec)
	end
	if isElder then
		elderFallen(player, rec, figure)
	end
end

local function onRegrown(rec: TreeRecord)
	if rec.temporary then
		return
	end
	grow(rec)
	if rec.planterId then
		addStake(rec)
	else
		removeStake(rec.uid)
		planterName[rec.uid] = nil
	end
end

---------------------------------------------------------------------------
-- Planting
---------------------------------------------------------------------------

local function finishSprout(uid: string, userId: number)
	sprouting[uid] = nil
	local rec = TreeService.GetTree(uid)
	if not rec then
		return
	end
	if rec.felled then
		TreeService.Regrow(uid, userId) -- OnRegrown rolls its figure and puts up the stake
	elseif rec.planterId == nil then
		-- It grew back on its own while the sapling sprouted: still yours.
		rec.planterId = userId
		rec.model:SetAttribute("PlanterId", userId)
		addStake(rec)
	end
end

local function onPlantSeed(player: Player, treeUid: unknown)
	if type(treeUid) ~= "string" or not RateLimiter.Allow(player, "PlantSeed") then
		return
	end
	local profile = ProfileService.GetProfile(player)
	local rec = TreeService.GetTree(treeUid)
	if not profile or not rec then
		return
	end
	if not rec.felled or not rec.stump or rec.temporary or rec.dormant then
		return -- nothing to plant in (still standing, mid-fall, an Elder's, hidden by day)
	end
	if sprouting[treeUid] then
		notify(player, "Something's already sprouting there.")
		return
	end
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not hrp then
		return
	end
	local offset = hrp.Position - rec.base
	local reach = ForestData.PlantRange + GameConfig.RangeTolerance
	if Vector3.new(offset.X, 0, offset.Z).Magnitude > reach or math.abs(offset.Y) > reach then
		notify(player, "Walk closer to the stump to plant.")
		return
	end
	local def = rec.def
	if not ForestLogic.TakeSeed(profile.heartseeds, def.id) then
		local wood = string.lower(def.displayName)
		notify(player, string.format("You have no %s Heartseeds. Fell a %s tree to find some.", wood, wood))
		return
	end
	publishSeeds(player, profile)
	profile.forest.planted += 1
	changeVitality(def.biome, ForestData.Vitality.plant)
	sprouting[treeUid] = true
	planterName[treeUid] = player.DisplayName
	local stump = rec.stump
	local stumpPart = if stump then stump.PrimaryPart else nil
	local top = if stumpPart then stumpPart.CFrame.Position.Y + stumpPart.Size.X / 2 else rec.base.Y + 1
	fireAll("Sprout", {
		uid = treeUid,
		pos = Vector3.new(rec.base.X, top, rec.base.Z),
		woodId = def.id,
		seed = rec.seed,
		seconds = ForestData.SproutSeconds,
		planter = player.DisplayName,
		userId = player.UserId,
	})
	notify(player, string.format("Planted! Your %s will stand again in a moment.", string.lower(def.displayName)))
	QuestService.Event(player, "seedPlanted")
	DailyService.Event(player, "seedPlanted", 1)
	analytics(player, "HeartseedPlanted", profile.forest.planted)
	task.delay(ForestData.SproutSeconds, finishSprout, treeUid, player.UserId)
end

---------------------------------------------------------------------------
-- The clock: drift, storms fading, Elders, the Bloom
---------------------------------------------------------------------------

function ForestService.Tick(dt: number)
	local now = clock()
	for _, id in ipairs(ForestData.Groves) do
		vitality[id] = ForestLogic.Drift(vitality[id] or ForestData.Vitality.rest, dt)
	end
	publishVitality()

	for uid, s in pairs(struck) do
		if now >= s.untilAt then
			clearStruck(uid)
		end
	end

	-- Stakes hide with their trees (the Phantom Grove by day).
	for uid, stake in pairs(stakeOf) do
		local rec = TreeService.GetTree(uid)
		if not rec then
			removeStake(uid)
		else
			local want: Instance? = if rec.dormant or rec.felled then nil else marksFolder()
			if stake.Parent ~= want then
				stake.Parent = want
			end
		end
	end

	local e = elder
	if e then
		local rec = TreeService.GetTree(e.uid)
		if not rec then
			clearElder()
		elseif not rec.felled and now - e.wokeAt >= ForestData.Elder.fadeSeconds then
			figureOf[e.uid] = nil
			clueOf[e.uid] = nil
			TreeService.Remove(e.uid)
			fireAll("ElderFaded", { woodId = e.woodId, biome = e.biome, pos = rec.base })
			clearElder()
		end
	end
	if now >= nextElderCheck then
		nextElderCheck = now + elderInterval()
		checkElder()
	end

	if isBlooming() then
		if now >= bloomUntil then
			bloomUntil = 0
			bloomRestUntil = now + ForestData.Bloom.restSeconds
			workspace:SetAttribute("SkyrootBloom", false)
		end
	elseif now >= bloomRestUntil and ForestLogic.BloomReady(vitality) then
		bloomUntil = now + ForestData.Bloom.seconds
		workspace:SetAttribute("SkyrootBloom", true)
	end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

-- Call once at startup, after MapBuilder has planted the world's trees.
function ForestService.Init(r: Remotes, notifyFn: (Player, string) -> (), options: Options?)
	local opts: Options = options or {}
	remotes = r
	notify = notifyFn
	clock = opts.clock or os.clock
	random = opts.random or math.random
	for _, id in ipairs(ForestData.Groves) do
		vitality[id] = ForestData.Vitality.start
	end
	publishVitality(true)
	workspace:SetAttribute("SkyrootBloom", false)
	setElderAttributes(nil, nil)

	TreeService.OnFelled = onFelled
	TreeService.OnRegrown = onRegrown
	-- The trees already standing get their hidden figures now.
	for _, rec in pairs(TreeService.AllTrees()) do
		if not rec.felled and not rec.temporary then
			grow(rec)
		end
	end

	r.PlantSeed.OnServerEvent:Connect(onPlantSeed)
	nextElderCheck = clock() + elderInterval()
	if not opts.manual then
		task.spawn(function()
			local last = clock()
			while true do
				task.wait(1)
				local now = clock()
				local dt = now - last
				local ok, err = pcall(function(): any
					ForestService.Tick(dt)
					return nil
				end)
				if not ok then
					warn("[ForestService] tick failed: " .. tostring(err))
				end
				last = now
			end
		end)
	end
end

-- Call once the save has loaded.
function ForestService.PlayerJoined(player: Player, profile: Profile)
	profile.heartseeds = ForestLogic.CleanSeeds(profile.heartseeds)
	publishSeeds(player, profile)
end

function ForestService.PlayerRemoving(_player: Player)
	-- Nothing to save: the pouch and the stats live in the profile, and a
	-- tree you planted stays yours (the share only pays while you're here).
end

-- After a sale: how many figured logs of each figure were just sold (the
-- reveal, stats and the Field Guide).
function ForestService.OnSale(player: Player, figures: { [string]: number })
	if not ProfileService.GetProfile(player) then
		return
	end
	local clean: { [string]: number } = {}
	local list: { { figure: string, count: number } } = {}
	local total = 0
	for _, f in ipairs(ForestData.Figures) do
		local n = figures[f.id]
		if type(n) == "number" and n >= 1 then
			local count = math.floor(n)
			clean[f.id] = count
			total += count
			table.insert(list, { figure = f.id, count = count }) -- rarest last
		end
	end
	if total == 0 then
		return
	end
	FieldGuideService.RevealFigures(player, clean)
	DailyService.Event(player, "figuredSold", total)
	fireOne(player, "Reveal", { figures = list })
end

-- Lightning struck near `position` (WeatherService): may strike a tree.
-- Returns the struck tree's uid, if any.
function ForestService.Strike(position: Vector3): string?
	local best: TreeRecord? = nil
	local bestDistance = ForestData.Storm.strikeRadius
	for uid, rec in pairs(TreeService.AllTrees()) do
		if rec.alive and not rec.felled and not rec.dormant and not struck[uid] then
			local dx, dz = rec.base.X - position.X, rec.base.Z - position.Z
			local d = math.sqrt(dx * dx + dz * dz)
			if d <= bestDistance and math.abs(rec.base.Y - position.Y) <= 200 then
				best, bestDistance = rec, d
			end
		end
	end
	local rec = best
	if not rec then
		return nil
	end
	local uid = rec.uid
	local glow: Instance? = nil
	TreeService.Decorate(uid, function(model: Model, r: TreeRecord)
		local trunk = trunkOf(model)
		if trunk then
			glow = ForestArt.StormGlow(model, trunk, r.def, r.seed + math.floor(random() * 1000))
		end
	end)
	local made = glow
	if not made then
		return nil
	end
	struck[uid] = { untilAt = clock() + ForestData.Storm.glowSeconds, glow = made }
	local trunk = trunkOf(rec.model)
	fireAll("Struck", {
		uid = uid,
		pos = rec.base,
		top = if trunk then trunk.CFrame.Position + Vector3.new(0, trunk.Size.X / 2, 0) else rec.base,
		woodId = rec.def.id,
		seconds = ForestData.Storm.glowSeconds,
	})
	return uid
end

-- For other systems (AmbientLife, tests): a grove's vitality, the Elder.
function ForestService.Vitality(biomeId: string): number
	return vitality[biomeId] or ForestData.Vitality.rest
end

function ForestService.ElderUid(): string?
	local e = elder
	return if e then e.uid else nil
end

-- Wakes an Elder in a grove right now (tests, admin tools). Returns its uid.
function ForestService.WakeElder(biomeId: string): string?
	if elder ~= nil then
		return nil
	end
	return wakeElder(biomeId)
end

return ForestService
