--!strict
-- ForestService: the Living Forest (GAME_DESIGN §16). Rules in
-- Shared/ForestLogic, numbers in Shared/ForestData, models in
-- Shared/Art/ForestArt, the screen side in ForestUI.
--   * The Hidden Grain: every tree that grows (in Init for the trees
--     MapBuilder planted, then on each regrow) may hide a figure; its bark
--     clue goes on the trunk (TreeService.Decorate). When it's felled, its
--     logs get the figure (value, tags.figure, a coloured band).
--   * Storms: WeatherService calls Strike(position); the nearest standing
--     tree glows for two minutes; felled in time its logs are Stormgrain.
--   * Elders: every 8 to 15 minutes a grove may wake a giant (a flat 40%
--     chance; workspace ElderUid / ElderWood / ElderBiome / ElderPos).
--     Everyone who chopped 10% of it shares 10% of the value, and its logs
--     are free to grab.
--   * The Skyroot Bloom: 8 minutes on, 30 minutes off (workspace
--     SkyrootBloom), doubling figure chances. Not gated on grove vitality.
-- WorldFX kinds sent to clients (payload tables): Struck, Elder,
-- ElderFallen, ElderFaded, ElderShare, Reveal.
--
-- The v2 loop (CoreLoop 2, V2_PLAN.md §3i): the same rules on section
-- trees. Under it GameServer passes Init SectionTrees (the same API and
-- records as TreeService) and WoodService's SetFigure, and wires the
-- hooks V2Hooks returns into SectionTrees:
--   * Every piece a cut frees from a standing tree (OnPieceFreed: limbs
--     and the felled trunk) gets the tree's figure (Stormgrain while it's
--     struck). An Elder's helpers (10% of the damage) share 10% of the
--     value freed from it.
--   * Bark clues go on the trunk section (ForestArt.SectionClue on
--     ForestArt.ClueSection) of a tree that has sections, again on every
--     new model as it grows (OnRebuilt); a storm's glow fades if it grows.
--   * Felled = the first cut through a trunk (OnFelled with the piece).
--     Figure chances stay at the Healthy tier, and double during a bloom.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BiomeData = require(ReplicatedStorage.Shared.BiomeData)
local ForestData = require(ReplicatedStorage.Shared.ForestData)
local ForestLogic = require(ReplicatedStorage.Shared.ForestLogic)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local TreeLogic = require(ReplicatedStorage.Shared.TreeLogic)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local WorldTime = require(ReplicatedStorage.Shared.WorldTime)
local ForestArt = require(ReplicatedStorage.Shared.Art.ForestArt)
local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local TerrainGen = require(ReplicatedStorage.Shared.World.TerrainGen)
local WorldPlan = require(ReplicatedStorage.Shared.World.WorldPlan)
local DailyService = require(script.Parent.DailyService)
local EconomyService = require(script.Parent.EconomyService)
local FieldGuideService = require(script.Parent.FieldGuideService)
local ProfileService = require(script.Parent.ProfileService)
local TreeService = require(script.Parent.TreeService)

type Profile = ProfileService.Profile
type TreeRecord = TreeService.TreeRecord

local ForestService = {}

-- The trees: TreeService, or under the v2 loop SectionTrees (the same API
-- and record shape), which Init is given.
local Trees = TreeService
local v2 = false
local setFigure: (piece: any, figure: string?) -> () = function(_piece: any, _figure: string?) end

export type Remotes = { WorldFX: RemoteEvent }

-- Tests pass their own clocks and dice, and tick by hand. Under the v2
-- loop GameServer passes SectionTrees and WoodService.SetFigure.
export type Options = {
	clock: (() -> number)?,
	serverTime: (() -> number)?, -- the day and night clock (workspace:GetServerTimeNow())
	random: (() -> number)?,
	manual: boolean?, -- no background loop: call ForestService.Tick(dt)
	sectionTrees: any?, -- v2: SectionTrees (TreeService's API and record shape)
	setFigure: ((piece: any, figure: string?) -> ())?, -- v2: WoodService.SetFigure
}

-- What onPieceFreed reads of a WoodService piece.
type FreedPiece = { volume: number, value: number }

type Struck = { untilAt: number, glow: Instance, roll: number }
type Elder = { uid: string, woodId: string, biome: string, wokeAt: number, aura: Model? }

local remotes: Remotes? = nil
local clock: () -> number = os.clock
local serverTime: () -> number = function(): number
	return workspace:GetServerTimeNow()
end
local random: () -> number = math.random

local figureOf: { [string]: string } = {} -- the figure each standing tree hides
local clueOf: { [string]: Instance } = {} -- its bark clue
local stakeOf: { [string]: Model } = {} -- name stakes still in the world (none are added)
local struck: { [string]: Struck } = {}
local vitality: { [string]: number } = {}
local elder: Elder? = nil
local nextElderCheck = 0
local bloomUntil = 0 -- clock time the bloom ends; 0 = not blooming
local bloomRestUntil = 0
local marks: Folder? = nil
-- v2: the value freed from a standing tree, for an Elder's helpers.
local freedOf: { [string]: number } = {}

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

-- A trunk's thickness: a v1 Trunk is a cylinder along X (Size.Y is its
-- diameter), a v2 section a square block along Y (Size.X).
local function trunkWidth(trunk: BasePart): number
	return if v2 then trunk.Size.X else trunk.Size.Y
end

-- The top of a trunk part (v1: its X axis runs up it; v2: its Y axis).
local function trunkTop(trunk: BasePart): Vector3
	local up = if v2 then trunk.Size.Y else trunk.Size.X
	return trunk.CFrame.Position + Vector3.new(0, up / 2, 0)
end

local function forgetDecoration(uid: string, inst: Instance?)
	if inst then
		Trees.Forget(uid, inst)
		inst:Destroy()
	end
end

local function isBlooming(): boolean
	return bloomUntil > 0
end

-- The tier a tree of this biome grows in (nil outside the groves).
local function tierFor(biomeId: string): string?
	if not ForestLogic.IsGrove(biomeId) then
		return nil
	end
	return ForestLogic.TierFor(vitality[biomeId] or ForestData.Vitality.rest).id
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
	Trees.Decorate(uid, function(model: Model, rec: TreeRecord)
		if v2 then
			-- On the trunk section (none yet on a sapling: it comes as it grows).
			local section = ForestArt.ClueSection(model)
			if section then
				clueOf[uid] = ForestArt.SectionClue(model, section, rec.def, figure, rec.seed)
			end
			return
		end
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
		for _, rec in pairs(Trees.AllTrees()) do
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
	local model = Trees.SpawnTree(woodId, CFrame.new(base), {
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
	local aura = ForestArt.ElderAura((if trunk then trunkWidth(trunk) else 3) * 1.6 + 2)
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

-- Seconds of the night left (0 by day, or while WorldClock still says day).
local function nightLeft(): number
	local now = serverTime()
	if workspace:GetAttribute("IsNight") ~= true or not WorldTime.IsNight(WorldTime.ClockTime(now)) then
		return 0
	end
	return WorldTime.SecondsUntilChange(now)
end

local function checkElder()
	if elder ~= nil then
		return
	end
	local groves: { ForestLogic.GroveState } = {}
	for _, id in ipairs(ForestData.Groves) do
		local biome = BiomeData.Get(id)
		-- Night-only groves (the Gloam Hollow) only wake one at night, with
		-- enough of it left to fell it (it fades at dawn).
		local awake = biome ~= nil and (not biome.nightOnly or nightLeft() >= ForestData.Elder.nightLeftSeconds)
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
	local def = rec.def
	local bonus: number
	local helpers: { number }
	if v2 then
		-- 10% of the value freed from it, to everyone who did 10% of the damage.
		bonus = ForestLogic.HelperBonus(freedOf[rec.uid] or 0)
		local total = 0
		for _, dealt in pairs(rec.damageBy) do
			total += dealt
		end
		helpers = ForestLogic.Helpers(rec.damageBy, total)
	else
		local logCount = TreeLogic.LogCount(def.logsPerTree, rec.size, 1)
		bonus = ForestLogic.HelperBonus(logCount * ForestLogic.LogValue(def.pricePerLog, figure))
		helpers = ForestLogic.Helpers(rec.damageBy, rec.maxHp)
	end
	local paid = 0
	for _, userId in ipairs(helpers) do
		local helper = Players:GetPlayerByUserId(userId)
		local profile = if helper then ProfileService.GetProfile(helper) else nil
		if helper and profile then
			paid += 1
			local credited = EconomyService.AddCash(helper, bonus, "Elder helper's bonus: " .. def.id, "elder")
			profile.forest.elders += 1
			fireOne(helper, "ElderShare", { woodId = def.id, amount = credited })
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

-- A felled tree has landed and its logs are down.
local function onFelled(player: Player, rec: TreeRecord, logUids: { string }, _fallDir: Vector3)
	local uid = rec.uid
	local def = rec.def
	local hidden = figureOf[uid]
	figureOf[uid] = nil
	local strike = struck[uid]
	local figure = if strike then ForestLogic.BoltFigure(hidden, strike.roll) else hidden
	clearStruck(uid)
	removeClue(uid)
	removeStake(uid)
	local current = elder
	local isElder = current ~= nil and current.uid == uid

	-- v2: the pieces already carry the figure (onPieceFreed).
	for _, logUid in ipairs(if v2 then {} else logUids) do
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

	if isElder then
		elderFallen(player, rec, figure)
	end
	freedOf[uid] = nil
end

-- v2: a cut has freed `piece` from standing tree `rec` (a limb, or the
-- felled trunk): it gets the tree's figure (Stormgrain while struck), and
-- its value counts toward the planter's share and an Elder's helpers.
local function onPieceFreed(_cutter: Player, rec: TreeRecord, piece: FreedPiece)
	local uid = rec.uid
	local hidden = figureOf[uid]
	local strike = struck[uid]
	local figure = if strike then ForestLogic.BoltFigure(hidden, strike.roll) else hidden
	if figure then
		setFigure(piece, figure)
	end
	freedOf[uid] = (freedOf[uid] or 0) + piece.value
end

-- v2: a tree has a new model (it grew a stage, or came back): its clue
-- goes back on, and a storm's glow (on the old model) is over.
local function onRebuilt(rec: TreeRecord)
	clearStruck(rec.uid)
	clueOf[rec.uid] = nil -- it went with the old model
	local figure = figureOf[rec.uid]
	if figure then
		addClue(rec.uid, figure)
	end
end

local function onRegrown(rec: TreeRecord)
	if rec.temporary then
		return
	end
	grow(rec)
	removeStake(rec.uid)
end

---------------------------------------------------------------------------
-- The clock: drift, storms fading, Elders, the Bloom
---------------------------------------------------------------------------

function ForestService.Tick(_dt: number)
	local now = clock()

	for uid, s in pairs(struck) do
		-- Felled in time: it keeps the strike while it falls (onFelled clears it).
		local rec = Trees.GetTree(uid)
		if now >= s.untilAt and not (rec and rec.felled) then
			clearStruck(uid)
		end
	end

	-- Stakes hide with their trees (the Gloam Hollow by day).
	for uid, stake in pairs(stakeOf) do
		local rec = Trees.GetTree(uid)
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
		local rec = Trees.GetTree(e.uid)
		if not rec then
			clearElder()
		elseif not rec.felled and (rec.dormant or now - e.wokeAt >= ForestData.Elder.fadeSeconds) then
			-- Unfelled in time, or a night-only one at dawn.
			figureOf[e.uid] = nil
			clueOf[e.uid] = nil
			Trees.Remove(e.uid)
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
	elseif now >= bloomRestUntil then
		bloomUntil = now + ForestData.Bloom.seconds
		workspace:SetAttribute("SkyrootBloom", true)
	end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

-- Call once at startup, after MapBuilder has planted the world's trees.
function ForestService.Init(r: Remotes, _notifyFn: (Player, string) -> (), options: Options?)
	local opts: Options = options or {}
	remotes = r
	clock = opts.clock or os.clock
	serverTime = opts.serverTime or serverTime
	random = opts.random or math.random
	for _, id in ipairs(ForestData.Groves) do
		vitality[id] = ForestData.Vitality.start
	end
	workspace:SetAttribute("SkyrootBloom", false)
	bloomRestUntil = clock() + ForestData.Bloom.restSeconds
	setElderAttributes(nil, nil)

	Trees = TreeService
	TreeService.OnFelled = onFelled
	TreeService.OnRegrown = onRegrown
	if opts.sectionTrees then
		ForestService.UseV2(opts.sectionTrees, opts.setFigure)
	else
		-- The trees already standing get their hidden figures now.
		for _, rec in pairs(Trees.AllTrees()) do
			if not rec.felled and not rec.temporary then
				grow(rec)
			end
		end
	end

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

-- The v2 loop (GameServer, after Init): the Living Forest on section trees
-- from now on. `trees` is SectionTrees (its hooks are set here),
-- `figureFn` WoodService.SetFigure. The trees standing get their hidden
-- figures now.
function ForestService.UseV2(trees: any, figureFn: ((piece: any, figure: string?) -> ())?)
	v2 = true
	Trees = trees :: any
	setFigure = figureFn or setFigure
	trees.OnFelled = onFelled
	trees.OnRegrown = onRegrown
	trees.OnPieceFreed = onPieceFreed
	trees.OnRebuilt = onRebuilt
	for _, rec in pairs(Trees.AllTrees()) do
		if not rec.felled and not rec.temporary then
			grow(rec)
		end
	end
end

-- Call once the save has loaded.
function ForestService.PlayerJoined(_player: Player, _profile: Profile) end

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
	for uid, rec in pairs(Trees.AllTrees()) do
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
	Trees.Decorate(uid, function(model: Model, r: TreeRecord)
		local trunk = trunkOf(model)
		if trunk then
			glow = ForestArt.StormGlow(model, trunk, r.def, r.seed + math.floor(random() * 1000))
		end
	end)
	local made = glow
	if not made then
		return nil
	end
	struck[uid] = {
		untilAt = clock() + ForestData.Storm.glowSeconds,
		glow = made,
		roll = ForestLogic.BoltRoll(rec.base.X, rec.base.Z),
	}
	local trunk = trunkOf(rec.model)
	fireAll("Struck", {
		uid = uid,
		pos = rec.base,
		top = if trunk then trunkTop(trunk) else rec.base,
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
