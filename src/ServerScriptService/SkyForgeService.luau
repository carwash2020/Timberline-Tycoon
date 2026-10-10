--!strict
-- SkyForgeService: the Sky Forge's end-game actions at the Starfall Forge
-- anvil (the part MapBuilder tags "StarfallForge"). AetherService keeps the
-- Starfall Axe loop; this adds, beside it:
--   * tempering an owned axe (TemperLogic: Keen, Heavy, Prosperous, I-III)
--     for cash, Sky Shards and planks laid by the anvil;
--   * the four relics (RelicData): one figured log or plank plus shards,
--     paid once per save slot;
--   * Old Bram's weekly order (ForgeOrderLogic): planks laid by the anvil,
--     paid once a week.
-- Remotes: ForgeOpen (client asks; the server answers with the view) and
-- ForgeAction ("starfall" | "temper" uid prefix | "relic" id | "order"),
-- RateLimiter "ForgeOpen" / "ForgeAction", only within ForgeRange of an
-- anvil. Every rule is checked here; the client only shows the view.
-- An "Open the Sky Forge" prompt (F / ButtonY) sends the same view.
-- Nothing here touches Robux; cash goes through EconomyService.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ForgeLogic = require(ReplicatedStorage.Shared.ForgeLogic)
local ForgeOrderLogic = require(ReplicatedStorage.Shared.ForgeOrderLogic)
local HandInLogic = require(ReplicatedStorage.Shared.HandInLogic)
local InputKit = require(ReplicatedStorage.Shared.InputKit)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local RelicData = require(ReplicatedStorage.Shared.RelicData)
local TemperLogic = require(ReplicatedStorage.Shared.TemperLogic)
local Util = require(ReplicatedStorage.Shared.Util)
local AetherService = require(script.Parent.AetherService)
local AxeService = require(script.Parent.AxeService)
local EconomyService = require(script.Parent.EconomyService)
local HandInWood = require(script.Parent.HandInWood)
local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)

local SkyForgeService = {}

SkyForgeService.Tag = "StarfallForge"
SkyForgeService.ForgeRange = 20
SkyForgeService.Clock = os.time -- the specs swap this for a fixed time

export type Ctx = {
	remotes: { [string]: Instance }?,
	notify: ((Player, string) -> ())?,
}

local notify: (Player, string) -> () = function(_p: Player, _m: string) end
local openRemote: RemoteEvent? = nil
local started = false

local function shardsOf(profile: any): number
	local m = profile.materials
	local n = if type(m) == "table" then m.SkyShard else nil
	return if type(n) == "number" then n else 0
end

local function rootOf(player: Player): BasePart?
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

-- Anvils: the isle forge's (tagged StarfallForge) and any part holding a
-- "TemperSpot" attachment (the town Sky Forge Court's anvil, where Old
-- Bram works; BuildingArt names it). Found as the map builds.
local spots: { BasePart } = {}

local function addSpot(inst: Instance)
	if inst:IsA("Attachment") and inst.Name == "TemperSpot" then
		local part = inst.Parent
		if part and part:IsA("BasePart") and table.find(spots, part) == nil then
			table.insert(spots, part)
		end
	end
end

function SkyForgeService._addSpot(part: BasePart)
	if table.find(spots, part) == nil then
		table.insert(spots, part)
	end
end

-- The anvil the player stands by, or nil.
function SkyForgeService.AnvilNear(player: Player): BasePart?
	local root = rootOf(player)
	if not root then
		return nil
	end
	local at = root.Position
	local function near(inst: Instance): boolean
		return inst:IsA("BasePart")
			and inst.Parent ~= nil
			and ((inst :: BasePart).Position - at).Magnitude <= SkyForgeService.ForgeRange
	end
	for _, inst in ipairs(CollectionService:GetTagged(SkyForgeService.Tag)) do
		if near(inst) then
			return inst :: BasePart
		end
	end
	for _, part in ipairs(spots) do
		if near(part) then
			return part
		end
	end
	return nil
end

local function relicsOf(profile: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(profile.relics) == "table" then
		for id, v in pairs(profile.relics) do
			if type(id) == "string" and v == true and RelicData.Get(id) then
				out[id] = true
			end
		end
	end
	return out
end

local function publishRelics(player: Player, profile: any)
	local ids: { string } = {}
	for _, relic in ipairs(RelicData.List) do
		if relicsOf(profile)[relic.id] then
			table.insert(ids, relic.id)
		end
	end
	-- ForgeUI lights these sockets on the anvil for this player.
	player:SetAttribute("Relics", table.concat(ids, ","))
end

export type TemperOption = {
	prefix: string,
	tier: number?,
	grade: string,
	effect: string,
	cost: string,
	refusal: string?,
}
export type AxeRow = { uid: string, id: string, name: string, label: string, options: { TemperOption } }
export type RelicRow = {
	id: string,
	name: string,
	cost: string,
	pays: number,
	owned: boolean,
	color: string,
	refusal: string?,
}
export type StarfallRow = { name: string, cost: string, progress: string, owned: number, refusal: string? }
export type View = {
	cash: number,
	shards: number,
	starfall: StarfallRow?,
	axes: { AxeRow },
	relics: { RelicRow },
	order: { text: string, pays: number, shards: number, claimed: boolean, endsIn: number },
}

local function costText(cost: TemperLogic.Cost): string
	return string.format(
		"%s + %d Sky Shards + %d %s planks",
		Util.formatCash(cost.cash),
		cost.shards,
		cost.u3,
		ForgeOrderLogic.WoodName(cost.woodId)
	)
end

local function temperRefusal(cost: TemperLogic.Cost, profile: any, planks: { [string]: number }): string?
	if (profile.cash or 0) < cost.cash then
		return "Not enough cash."
	end
	if shardsOf(profile) < cost.shards then
		return string.format("%d more Sky Shards needed.", cost.shards - shardsOf(profile))
	end
	local have = planks[cost.woodId] or 0
	if have + 1e-6 < cost.u3 then
		return string.format(
			"Lay %d more %s planks by the anvil.",
			math.ceil(cost.u3 - have),
			ForgeOrderLogic.WoodName(cost.woodId)
		)
	end
	return nil
end

-- Everything the forge window shows, from the server's own facts.
function SkyForgeService.View(player: Player): View?
	local profile: any = ProfileService.GetProfile(player)
	if not profile then
		return nil
	end
	local anvil = SkyForgeService.AnvilNear(player)
	local list: { HandInLogic.Candidate } = {}
	if anvil then
		list = HandInWood.Near(anvil.Position)
	end
	local planks = HandInLogic.Planks(list, player.UserId)
	local tempers = TemperLogic.Clean(profile.temper)
	local axes: { AxeRow } = {}
	for _, item in ipairs(profile.axes or {}) do
		local def = ItemCatalog.GetAxe(item.id)
		if def and TemperLogic.CanTemperAxe(item.id) then
			local current = tempers[item.uid]
			local options: { TemperOption } = {}
			for _, prefix in ipairs(TemperLogic.Prefixes) do
				local tier = TemperLogic.NextTier(item.id, current, prefix)
				local cost = if tier then TemperLogic.CostFor(tier) else nil
				table.insert(options, {
					prefix = prefix,
					tier = tier,
					grade = if tier then TemperLogic.GradeNames[tier] else "III",
					effect = TemperLogic.EffectText(prefix, tier or 3),
					cost = if cost then costText(cost) else "",
					refusal = if cost then temperRefusal(cost, profile, planks) else "Already " .. prefix .. " III.",
				})
			end
			table.insert(axes, {
				uid = item.uid,
				id = item.id,
				name = def.displayName,
				label = TemperLogic.Label(current),
				options = options,
			})
		end
	end
	local owned = relicsOf(profile)
	local relics: { RelicRow } = {}
	for _, relic in ipairs(RelicData.List) do
		table.insert(relics, {
			id = relic.id,
			name = relic.displayName,
			cost = RelicData.CostText(relic),
			pays = relic.pays,
			owned = owned[relic.id] == true,
			color = relic.color,
			refusal = RelicData.Refusal(
				relic,
				owned,
				shardsOf(profile),
				HandInLogic.Figured(list, player.UserId, relic.woodId)
			),
		})
	end
	local starfall: StarfallRow? = nil
	local axe = ItemCatalog.GetAxe("StarfallAxe")
	local recipe = if axe then ForgeLogic.RecipeV2(axe) else nil
	if axe and recipe then
		local stock = {
			cash = profile.cash or 0,
			wood = if type(profile.forgeWood) == "table" then profile.forgeWood else {},
			materials = if type(profile.materials) == "table" then profile.materials else {},
		}
		local missing = ForgeLogic.MissingV2(recipe, stock)
		local counts = AxeService.OwnedCounts(player)
		local shards = 0
		for _, n in pairs(recipe.materials) do
			shards += n
		end
		local wood = 0
		for _, u3 in pairs(recipe.wood) do
			wood += u3
		end
		starfall = {
			name = axe.displayName,
			cost = string.format(
				"%s + %d Sky Shards + %d plain %s fed to the isle forge",
				Util.formatCash(recipe.cash),
				shards,
				wood,
				ForgeLogic.WoodNames(recipe)
			),
			progress = ForgeLogic.ProgressV2(recipe, stock),
			owned = counts[axe.id] or 0,
			refusal = if #missing > 0 then "Needs " .. table.concat(missing, ", ") .. "." else nil,
		}
	end
	local now = SkyForgeService.Clock()
	local week = ForgeOrderLogic.WeekId(now)
	local state = ForgeOrderLogic.Current(profile.forgeOrder, week)
	return {
		cash = profile.cash or 0,
		shards = shardsOf(profile),
		starfall = starfall,
		axes = axes,
		relics = relics,
		order = {
			text = ForgeOrderLogic.ProgressText(state),
			pays = ForgeOrderLogic.Pays,
			shards = ForgeOrderLogic.Shards,
			claimed = state.claimed,
			endsIn = math.max(0, ForgeOrderLogic.WeekEnds(week) - now),
		},
	}
end

local function sendView(player: Player)
	local remote = openRemote
	local view = SkyForgeService.View(player)
	if remote and view then
		remote:FireClient(player, view)
	end
end

-- AetherService.OpenForge (Old Bram's talk): the window, wherever he is.
function SkyForgeService.Open(player: Player)
	sendView(player)
end

-- Relic trophies: a small row of pedestals with a glowing gem per forged
-- relic, beside the owner's plot sign (outside the pad, so it never blocks
-- a build). Built from parts; rebuilt when the plot is claimed or a relic
-- is forged, and gone when the plot is let go.
local TROPHY = "RelicTrophies"

local function plotOf(userId: number): Model?
	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, plot in ipairs(plots:GetChildren()) do
		if plot:IsA("Model") and plot:GetAttribute("OwnerId") == userId then
			return plot
		end
	end
	return nil
end

function SkyForgeService.BuildTrophies(player: Player)
	local profile: any = ProfileService.GetProfile(player)
	local plot = plotOf(player.UserId)
	if not profile or not plot then
		return
	end
	local old = plot:FindFirstChild(TROPHY)
	if old then
		old:Destroy()
	end
	local post = plot:FindFirstChild("SignPost")
	if not post or not post:IsA("BasePart") then
		return
	end
	local ids: { string } = {}
	local owned = relicsOf(profile)
	for _, relic in ipairs(RelicData.List) do
		if owned[relic.id] then
			table.insert(ids, relic.id)
		end
	end
	local model = RelicData.Trophies(ids, post.CFrame, post.Size.Y)
	if model then
		model.Name = TROPHY
		model.Parent = plot
	end
end

local function watchPlots()
	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return
	end
	local function watch(plot: Instance)
		plot:GetAttributeChangedSignal("OwnerId"):Connect(function()
			local old = plot:FindFirstChild(TROPHY)
			if old then
				old:Destroy()
			end
			local id = plot:GetAttribute("OwnerId")
			local owner = if type(id) == "number" then Players:GetPlayerByUserId(id) else nil
			if owner then
				SkyForgeService.BuildTrophies(owner)
			end
		end)
	end
	for _, plot in ipairs(plots:GetChildren()) do
		watch(plot)
	end
	plots.ChildAdded:Connect(watch)
end

-- Tempers axe `uid` with `prefix`. Returns the toast, or nil when refused
-- silently (bad input).
function SkyForgeService.Temper(player: Player, uid: unknown, prefix: unknown): string?
	if type(uid) ~= "string" or type(prefix) ~= "string" or not TemperLogic.Known(prefix) then
		return nil
	end
	local profile: any = ProfileService.GetProfile(player)
	local anvil = SkyForgeService.AnvilNear(player)
	if not profile or not anvil then
		return nil
	end
	local item = nil
	for _, it in ipairs(profile.axes or {}) do
		if it.uid == uid then
			item = it
		end
	end
	if not item then
		return nil
	end
	local tempers = TemperLogic.Clean(profile.temper)
	local tier = TemperLogic.NextTier(item.id, tempers[uid], prefix)
	local cost = if tier then TemperLogic.CostFor(tier) else nil
	if not tier or not cost then
		local text = if TemperLogic.CanTemperAxe(item.id)
			then "That axe is already " .. prefix .. " III."
			else "That axe can't be tempered."
		notify(player, text)
		return text
	end
	local list, byUid = HandInWood.Near(anvil.Position)
	local planks = HandInLogic.Planks(list, player.UserId)
	local refusal = temperRefusal(cost, profile, planks)
	if refusal then
		notify(player, refusal)
		return refusal
	end
	if not EconomyService.SpendCash(player, cost.cash, "tempered axe", "Temper" .. prefix .. tostring(tier)) then
		notify(player, "Not enough cash.")
		return "Not enough cash."
	end
	profile.materials.SkyShard = shardsOf(profile) - cost.shards
	HandInWood.Take(byUid, HandInLogic.PickPlanks(list, player.UserId, cost.woodId, cost.u3), "temper")
	tempers[uid] = { prefix = prefix, tier = tier }
	profile.temper = tempers
	if type(AxeService.StampTemper) == "function" then
		AxeService.StampTemper(player, uid)
	end
	local rec = tempers[uid]
	local text = string.format("Your axe is now %s: %s.", TemperLogic.Label(rec), TemperLogic.EffectText(prefix, tier))
	notify(player, text)
	return text
end

-- Forges relic `id`. Pays its reward once.
function SkyForgeService.Relic(player: Player, id: unknown): string?
	local relic = if type(id) == "string" then RelicData.Get(id) else nil
	local profile: any = ProfileService.GetProfile(player)
	local anvil = SkyForgeService.AnvilNear(player)
	if not relic or not profile or not anvil then
		return nil
	end
	local list, byUid = HandInWood.Near(anvil.Position)
	local owned = relicsOf(profile)
	local refusal =
		RelicData.Refusal(relic, owned, shardsOf(profile), HandInLogic.Figured(list, player.UserId, relic.woodId))
	if refusal then
		notify(player, refusal)
		return refusal
	end
	local pick = HandInLogic.PickFigured(list, player.UserId, relic.woodId)
	if not pick then
		return nil
	end
	-- Claim first, then use up and pay: a second press can't pay twice.
	if type(profile.relics) ~= "table" then
		profile.relics = {}
	end
	profile.relics[relic.id] = true
	profile.materials.SkyShard = shardsOf(profile) - relic.shards
	HandInWood.Take(byUid, { pick }, "relic")
	EconomyService.AddCash(player, relic.pays, "forged " .. relic.displayName, relic.id)
	publishRelics(player, profile)
	SkyForgeService.BuildTrophies(player)
	local text = string.format("You forged the %s! +%s.", relic.displayName, Util.formatCash(relic.pays))
	notify(player, text)
	return text
end

-- Delivers planks laid by the anvil to this week's order.
function SkyForgeService.Order(player: Player): string?
	local profile: any = ProfileService.GetProfile(player)
	local anvil = SkyForgeService.AnvilNear(player)
	if not profile or not anvil then
		return nil
	end
	local week = ForgeOrderLogic.WeekId(SkyForgeService.Clock())
	local state = ForgeOrderLogic.Current(profile.forgeOrder, week)
	if state.claimed then
		local text = "This week's order is done. A new one comes Monday."
		notify(player, text)
		return text
	end
	local list, byUid = HandInWood.Near(anvil.Position)
	local nextState, used, finished = ForgeOrderLogic.Deliver(state, HandInLogic.Planks(list, player.UserId))
	for woodId, u3 in pairs(used) do
		HandInWood.Take(byUid, HandInLogic.PickPlanks(list, player.UserId, woodId, u3), "order")
	end
	profile.forgeOrder = nextState
	local text: string
	if finished then
		if type(profile.materials) == "table" then
			profile.materials.SkyShard = shardsOf(profile) + ForgeOrderLogic.Shards
		end
		EconomyService.AddCash(player, ForgeOrderLogic.Pays, "weekly forge order", "ForgeOrder")
		text = string.format(
			"Order filled! +%s and %d Sky Shards.",
			Util.formatCash(ForgeOrderLogic.Pays),
			ForgeOrderLogic.Shards
		)
	elseif next(used) == nil then
		text = "Lay planks for the order by the anvil: " .. ForgeOrderLogic.ProgressText(nextState) .. "."
	else
		text = "Delivered. " .. ForgeOrderLogic.ProgressText(nextState) .. "."
	end
	notify(player, text)
	return text
end

function SkyForgeService.Act(player: Player, kind: unknown, a: unknown, b: unknown)
	if kind == "starfall" then
		if SkyForgeService.AnvilNear(player) then
			AetherService.Forge(player)
		end
	elseif kind == "temper" then
		SkyForgeService.Temper(player, a, b)
	elseif kind == "relic" then
		SkyForgeService.Relic(player, a)
	elseif kind == "order" then
		SkyForgeService.Order(player)
	else
		return
	end
	sendView(player)
end

local function addPrompt(inst: Instance)
	if not inst:IsA("BasePart") or inst:FindFirstChild("SkyForgePoint") then
		return
	end
	local point = Instance.new("Attachment")
	point.Name = "SkyForgePoint" -- its own spot, beside the Starfall prompts
	point.Position = Vector3.new(0, 3, 0)
	point.Parent = inst
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SkyForge"
	prompt.ActionText = "Open the Sky Forge"
	prompt.ObjectText = "Sky Forge"
	prompt.MaxActivationDistance = 12
	prompt.HoldDuration = 0
	InputKit.PromptDefaults(prompt, "Open")
	prompt.RequiresLineOfSight = false
	prompt.Parent = point
	prompt.Triggered:Connect(function(player: Player)
		if RateLimiter.Allow(player, "ForgeOpen") then
			sendView(player)
		end
	end)
end

function SkyForgeService.V1Init(ctx: Ctx?)
	if started then
		return
	end
	started = true
	if ctx and ctx.notify then
		notify = ctx.notify
	end
	local remotes = if ctx then ctx.remotes else nil
	local open = if remotes then remotes.ForgeOpen else nil
	if open and open:IsA("RemoteEvent") then
		openRemote = open
		open.OnServerEvent:Connect(function(player: Player)
			if RateLimiter.Allow(player, "ForgeOpen") and SkyForgeService.AnvilNear(player) then
				sendView(player)
			end
		end)
	end
	local action = if remotes then remotes.ForgeAction else nil
	if action and action:IsA("RemoteEvent") then
		action.OnServerEvent:Connect(function(player: Player, kind: unknown, a: unknown, b: unknown)
			if RateLimiter.Allow(player, "ForgeAction") then
				SkyForgeService.Act(player, kind, a, b)
			end
		end)
	end
	for _, inst in ipairs(CollectionService:GetTagged(SkyForgeService.Tag)) do
		addPrompt(inst)
	end
	CollectionService:GetInstanceAddedSignal(SkyForgeService.Tag):Connect(addPrompt)
	task.spawn(function()
		local map = workspace:WaitForChild("TimberlineMap", 120)
		if map then
			local function found(d: Instance)
				addSpot(d)
				local part = d.Parent
				if d:IsA("Attachment") and d.Name == "TemperSpot" and part then
					addPrompt(part)
				end
			end
			map.DescendantAdded:Connect(found)
			for _, d in ipairs(map:GetDescendants()) do
				found(d)
			end
		end
	end)
	task.spawn(function()
		workspace:WaitForChild("Plots", 120)
		watchPlots()
	end)
	local function joined(player: Player)
		task.spawn(function()
			for _ = 1, 60 do
				local profile = ProfileService.GetProfile(player)
				if profile then
					publishRelics(player, profile)
					SkyForgeService.BuildTrophies(player)
					return
				end
				task.wait(1)
			end
		end)
	end
	Players.PlayerAdded:Connect(joined)
	for _, player in ipairs(Players:GetPlayers()) do
		joined(player)
	end
end

function SkyForgeService._reset()
	started = false
	table.clear(spots)
	openRemote = nil
	notify = function(_p: Player, _m: string) end
	SkyForgeService.Clock = os.time
end

return SkyForgeService
