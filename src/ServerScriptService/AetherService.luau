--!strict
-- AetherService: the Aether Isles (GAME_DESIGN §10), apart from the gondola
-- (GondolaService) and the crystal nodes (NodeService).
--   * Cloud Chutes on the outer isles: "Send logs down" moves the logs in
--     your hands into your Sky Bin at the sawmill (profile.skyBin, up to
--     BiomeData sky.skyBinCapacity). Selling on the sawmill pad sells the
--     bin too (GameServer calls TakeSkyBin).
--   * The Starfall Forge on the main isle: "Add lumenwood" puts carried
--     logs into it (profile.forgeLogs); "Forge" takes the recipe's cash and
--     Sky Shards and makes a Starfall Axe (ItemCatalog forge recipe,
--     Shared/ForgeLogic).
--   * Falling off: the logs in your hands are lost to the clouds, unless you
--     wear the Featherfall Cloak, which lets you glide down.
--   * Logs in the Sky Bin keep their value and figure (the Hidden Grain, a
--     Starfall Burl), so figured logs can go down the chute too. The forge
--     doesn't take them (they're worth more sold).
-- Mirrored on the SkyBin (log count) and ForgeLogs attributes.
--
-- The v2 loop (V2_PLAN.md §5, M1.7b; GameServer calls InitV2 only under
-- CoreLoop.V2()): nobody carries logs, so the chutes are hoppers. Wood
-- that rests a moment (SellService.Settle) with its middle in a chute's
-- hopper box (HopperZone: one box query over the Wood folder per chute
-- every 0.25 s, as the sell pad does) goes down into its payee's Sky Bin
-- (SellLogic.Payee: the owner, else the last holder, online) as a
-- profile.skyWood entry (SellLogic.Entry: wood, u³, figure, plank, boost),
-- up to the sky's skyBinVolume u³. A piece that won't fit is left where
-- it is, with a toast now and then. The chute's prompt only says how it
-- works and how full the bin is. Taking a piece is the pad's: the record
-- marked selling, let go of, forgotten, destroyed. Mirrored on the
-- SkyBinVolume attribute (u³ in the bin).
--   * The Sky Bin by the sell pad gets a "Sell Sky Bin" prompt (from
--     beside it, RateLimiter "SellSkyBin"): SellService.PayEntries pays the
--     entries as the pad pays pieces, and the bin empties.

local AnalyticsService = game:GetService("AnalyticsService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BiomeData = require(ReplicatedStorage.Shared.BiomeData)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ForgeLogic = require(ReplicatedStorage.Shared.ForgeLogic)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local SellLogic = require(ReplicatedStorage.Shared.SellLogic)
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)
local AxeService = require(script.Parent.AxeService)
local CarryService = require(script.Parent.CarryService)
local EconomyService = require(script.Parent.EconomyService)
local NodeService = require(script.Parent.NodeService)
local ProfileSchema = require(script.Parent.ProfileSchema)
local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)
local SellService = require(script.Parent.SellService)
local TreeService = require(script.Parent.TreeService)

type Profile = ProfileService.Profile
type Piece = SellService.Piece

-- What the v2 loop's hoppers need (GameServer, under CoreLoop.V2()).
export type V2Deps = {
	woodFolder: Instance, -- TimberlineMap/Wood: the loose pieces
	resolve: (Model) -> Piece?, -- a piece's record (as SellService's resolve)
	release: (Model) -> (), -- lets go of a held piece before it goes
	forget: (Model) -> (), -- drops it from the registries
	skyBin: BasePart?, -- SellArea's SkyBin by the pad: its "Sell Sky Bin" prompt
	-- Seams for the specs: what's in a box, the clock, who's online.
	partsInBox: ((CFrame, Vector3, Instance) -> { BasePart })?,
	now: (() -> number)?,
	player: ((number) -> Player?)?,
}

local AetherService = {}

local FORGED_AXE = "StarfallAxe"
local GLIDE_SPEED = 14 -- studs/s: the cloak holds your fall to this
local DECK_ABOVE_AREA = 40 -- the isles' walking surfaces sit about 50 above the sky area's y (WorldPlan.Sky)
local GLIDE_BELOW = 15 -- studs under the deck where the cloak opens
local FALL_BELOW = 40 -- studs under the deck that count as falling off
local NEAR = 250 -- further than this from the isles (sideways) isn't a fall: a respawn or teleport

local CHUTE_ZONE_HEIGHT = 6 -- studs above a chute's hopper box that count as in it
local PROMPT_RANGE = 10 -- every prompt here (ProximityPrompt.MaxActivationDistance)
AetherService.RefuseToastSec = 4 -- at most one "won't fit" toast per player this often

local notify: (Player, string) -> () = function(_player: Player, _message: string) end
local onIsles: { [Player]: boolean } = {}

type HopperKind = "chute"
type Hopper = { part: BasePart, kind: HopperKind, firstSeen: { [Model]: number } }
type PromptText = { prompt: ProximityPrompt, v1: string, v2: string }

local v2: V2Deps? = nil -- set by InitV2: the v2 loop runs
local hoppers: { Hopper } = {}
local relabel: { PromptText } = {} -- prompts whose text differs under v2
local refusedAt: { [Player]: { [string]: number } } = {}

local function sky(): BiomeData.BiomeDef
	return BiomeData.Get("sky") :: BiomeData.BiomeDef
end

local function binCapacity(): number
	return sky().skyBinCapacity or 30
end

-- u³ the v2 Sky Bin holds at most.
local function binVolume(): number
	return sky().skyBinVolume or 120
end

-- u³ in the player's v2 Sky Bin.
local function binUsed(profile: Profile): number
	local _value, volume = SellLogic.EntriesValue(profile.skyWood)
	return volume
end

local function round2(n: number): number
	return math.floor(n * 100 + 0.5) / 100
end

local function publish(player: Player, profile: Profile)
	player:SetAttribute("SkyBin", #profile.skyBin)
	player:SetAttribute("ForgeLogs", ShopLogic.EncodeOwned(profile.forgeLogs))
	if v2 then
		player:SetAttribute("SkyBinVolume", round2(binUsed(profile)))
	end
end

local function stockOf(profile: Profile): ForgeLogic.Stock
	return { cash = profile.cash, logs = profile.forgeLogs, materials = profile.materials }
end

local function recipe(): ItemCatalog.ForgeRecipe
	local axe = ItemCatalog.GetAxe(FORGED_AXE) :: ItemCatalog.AxeDef
	return axe.forge :: ItemCatalog.ForgeRecipe
end

-- How many figured logs of these woods the player is holding.
local function figuredInHand(player: Player, woodIds: { [string]: any }): number
	local n = 0
	for uid in pairs(CarryService.Hands(player) or {}) do
		local log = TreeService.GetLog(uid)
		if log and woodIds[log.def.id] ~= nil and log.tags.figure ~= nil then
			n += 1
		end
	end
	return n
end

-- Sends the logs in the player's hands down the Cloud Chute.
function AetherService.SendDown(player: Player)
	if not RateLimiter.Allow(player, "LoadToTruck") then
		return
	end
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return
	end
	local space = binCapacity() - #profile.skyBin
	if space <= 0 then
		notify(player, string.format("Your Sky Bin is full (%d). Sell it at the sawmill.", binCapacity()))
		return
	end
	-- Each log keeps its value and figure in the bin.
	local sent = CarryService.TakeLogs(player, function()
		return true
	end, space)
	if #sent == 0 then
		notify(player, "Bring logs to send them down the Cloud Chute.")
		return
	end
	for _, log in ipairs(sent) do
		table.insert(profile.skyBin, { woodId = log.woodId, value = log.value, figure = log.figure })
	end
	publish(player, profile)
	notify(
		player,
		string.format(
			"Sent %d log%s down the Cloud Chute. Sky Bin %d/%d.",
			#sent,
			if #sent == 1 then "" else "s",
			#profile.skyBin,
			binCapacity()
		)
	)
end

-- Empties the player's Sky Bin (selling at the sawmill) and returns its logs.
function AetherService.TakeSkyBin(player: Player): { ProfileSchema.BedLog }
	local profile = ProfileService.GetProfile(player)
	if not profile or #profile.skyBin == 0 then
		return {}
	end
	local out = profile.skyBin
	profile.skyBin = {}
	publish(player, profile)
	return out
end

---------------------------------------------------------------------------
-- The v2 loop: hoppers (V2_PLAN.md §5)
---------------------------------------------------------------------------

local function playerById(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

local function defaultPartsInBox(cf: CFrame, size: Vector3, folder: Instance): { BasePart }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	return workspace:GetPartBoundsInBox(cf, size, params)
end

-- The tagged Wood model a part belongs to (a few levels up at most).
local function pieceModel(part: BasePart): Model?
	local node: Instance? = part.Parent
	for _ = 1, 4 do
		if node == nil then
			return nil
		end
		if node:IsA("Model") and node:HasTag(SellService.Tag) then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function attrNumber(model: Model, name: string): number?
	local v = model:GetAttribute(name)
	return if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then v else nil
end

local function attrString(model: Model, name: string): string?
	local v = model:GetAttribute(name)
	return if type(v) == "string" and v ~= "" then v else nil
end

local function inBox(cf: CFrame, size: Vector3, point: Vector3): boolean
	local p = cf:PointToObjectSpace(point)
	return math.abs(p.X) <= size.X / 2 and math.abs(p.Y) <= size.Y / 2 and math.abs(p.Z) <= size.Z / 2
end

-- The box a chute takes wood from: its hopper box's footprint (half a stud
-- more each side) from just under the rim up CHUTE_ZONE_HEIGHT studs, so
-- wood laid on it is in and wood lying beside it isn't.
function AetherService.HopperZone(part: BasePart): (CFrame, Vector3)
	local size = part.Size
	local h = CHUTE_ZONE_HEIGHT
	return part.CFrame * CFrame.new(0, size.Y / 2 - 0.25 + h / 2, 0), Vector3.new(size.X + 1, h, size.Z + 1)
end

-- The pieces that have rested SellService.Settle seconds with their
-- middle (the PrimaryPart's centre) in hopper `h`'s box, oldest first. A
-- piece that left starts its wait again.
local function settled(h: Hopper, d: V2Deps, now: number): { Model }
	local cf, size = AetherService.HopperZone(h.part)
	local query: (CFrame, Vector3, Instance) -> { BasePart } = d.partsInBox or defaultPartsInBox
	local checked: { [Model]: boolean } = {}
	local seen: { [Model]: boolean } = {}
	for _, part in ipairs(query(cf, size, d.woodFolder)) do
		local model = pieceModel(part)
		if model and not checked[model] then
			checked[model] = true
			local root = model.PrimaryPart
			if root and inBox(cf, size, root.CFrame.Position) then
				seen[model] = true
				if h.firstSeen[model] == nil then
					h.firstSeen[model] = now
				end
			end
		end
	end
	local ready: { Model } = {}
	for model, since in pairs(h.firstSeen) do
		if not seen[model] then
			h.firstSeen[model] = nil
		elseif now - since >= SellService.Settle then
			table.insert(ready, model)
		end
	end
	table.sort(ready, function(a: Model, b: Model): boolean
		local ta, tb = h.firstSeen[a], h.firstSeen[b]
		if ta ~= tb then
			return ta < tb
		end
		return a.Name < b.Name
	end)
	return ready
end

-- What a hopper needs to know of a piece: its record, and what the
-- attributes only the server writes say (as SellService reads them).
type Facts = {
	piece: Piece,
	woodId: string,
	kind: SellLogic.Kind,
	volume: number,
	figure: string?,
	boost: number,
	payee: Player,
	profile: Profile,
}

-- A piece's facts, or nil to leave it alone: unknown, already going,
-- dead, a shop's, without a wood or a volume, or nobody online to take it
-- (SellLogic.Payee: its owner, else its last holder).
local function factsOf(d: V2Deps, model: Model): Facts?
	local piece = d.resolve(model)
	if not piece or piece.selling or piece.dead or piece.shopItem then
		return nil
	end
	local woodId = attrString(model, "WoodId")
	local volume = attrNumber(model, "Volume")
	if not woodId or not volume or volume <= 0 then
		return nil
	end
	local find: (number) -> Player? = d.player or playerById
	local payeeId = SellLogic.Payee(piece.ownerId, piece.lastHolderId, function(userId: number): boolean
		return find(userId) ~= nil
	end)
	local payee = if payeeId then find(payeeId) else nil
	local profile = if payee then ProfileService.GetProfile(payee) else nil
	if not payee or not profile then
		return nil
	end
	local kind: SellLogic.Kind = if model:GetAttribute("Kind") == "plank" then "plank" else "log"
	return {
		piece = piece,
		woodId = woodId,
		kind = kind,
		volume = volume,
		figure = attrString(model, "Figure"),
		boost = attrNumber(model, "Boost") or 1,
		payee = payee,
		profile = profile,
	}
end

-- Takes a piece out of the world, as the sell pad does: marked going (no
-- second hopper or pad takes it), let go of, forgotten, destroyed.
local function take(d: V2Deps, h: Hopper, model: Model, piece: Piece)
	piece.selling = true
	h.firstSeen[model] = nil
	d.release(model)
	d.forget(model)
	model:Destroy()
end

-- A "won't take it" toast, at most once per RefuseToastSec per player and
-- text: a refused piece stays in the hopper and is asked about each poll.
local function refuse(player: Player, text: string, now: number)
	local seen = refusedAt[player] or {}
	refusedAt[player] = seen
	local last = seen[text]
	if last and now - last < AetherService.RefuseToastSec then
		return
	end
	seen[text] = now
	notify(player, text)
end

-- One poll of a chute: each settled piece that fits goes down into its
-- payee's Sky Bin; one toast per payee for what went.
local function chuteTick(h: Hopper, d: V2Deps, now: number)
	local cap = binVolume()
	local sent: { [Player]: number } = {}
	local order: { Player } = {}
	for _, model in ipairs(settled(h, d, now)) do
		local f = factsOf(d, model)
		if not f then
			continue
		end
		if not SellLogic.Fits(binUsed(f.profile), f.volume, cap) then
			local text = if f.volume > cap
				then string.format(
					"That piece is too big for the Sky Bin (%s). Cut it smaller.",
					SellLogic.VolumeText(cap)
				)
				else string.format("Your Sky Bin is full (%s). Sell it at the sawmill.", SellLogic.VolumeText(cap))
			refuse(f.payee, text, now)
			continue
		end
		take(d, h, model, f.piece)
		table.insert(f.profile.skyWood, SellLogic.Entry(f.woodId, f.kind, f.volume, f.figure, f.boost))
		if sent[f.payee] == nil then
			sent[f.payee] = 0
			table.insert(order, f.payee)
		end
		sent[f.payee] += 1
	end
	for _, player in ipairs(order) do
		local profile = ProfileService.GetProfile(player)
		if profile then
			publish(player, profile)
			local n = sent[player]
			notify(
				player,
				string.format(
					"Sent %d piece%s down the Cloud Chute. Sky Bin %s.",
					n,
					if n == 1 then "" else "s",
					SellLogic.BinText(binUsed(profile), cap)
				)
			)
		end
	end
end

-- One poll of every hopper (the Heartbeat runs it every 0.25 s under v2).
function AetherService.HopperTick()
	local d = v2
	if not d then
		return
	end
	local clock: () -> number = d.now or os.clock
	local now = clock()
	for _, h in ipairs(hoppers) do
		if h.part.Parent ~= nil then
			chuteTick(h, d, now)
		end
	end
end

-- The chute's prompt under v2: how it works, and how full your bin is.
function AetherService.ChuteInfo(player: Player)
	if not RateLimiter.Allow(player, "LoadToTruck") then
		return
	end
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return
	end
	notify(
		player,
		string.format(
			"Lay wood in the Cloud Chute and it goes down to your Sky Bin by the sawmill. Sky Bin %s.",
			SellLogic.BinText(binUsed(profile), binVolume())
		)
	)
end

-- The Sky Bin's prompt by the sell pad (v2): sells what the chutes sent
-- down through SellService.PayEntries (paid, toasted and counted as a pad
-- sale), from beside the bin. The entries leave the save before the sale
-- and come back only if the pad isn't selling yet.
function AetherService.SellSkyBin(player: Player)
	local d = v2
	if not d or not RateLimiter.Allow(player, "SellSkyBin") then
		return
	end
	local profile = ProfileService.GetProfile(player)
	local bin = d.skyBin
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if not profile or not bin or not root or not root:IsA("BasePart") then
		return
	end
	local reach = PROMPT_RANGE + GameConfig.RangeTolerance
	if (root.CFrame.Position - bin.CFrame.Position).Magnitude > reach then
		return
	end
	if #profile.skyWood == 0 then
		notify(player, "Your Sky Bin is empty. Lay wood in a Cloud Chute on the Aether Isles to fill it.")
		return
	end
	local entries = profile.skyWood
	profile.skyWood = {}
	if not SellService.PayEntries(player, entries) then
		profile.skyWood = entries
	end
	publish(player, profile)
end

-- Puts the lumenwood in the player's hands into the forge (up to the recipe).
function AetherService.AddToForge(player: Player)
	if not RateLimiter.Allow(player, "LoadToTruck") then
		return
	end
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return
	end
	local r = recipe()
	local added = 0
	for woodId in pairs(r.logs) do
		local want = ForgeLogic.LogsWanted(r, stockOf(profile), woodId)
		if want > 0 then
			-- Figured logs are worth more sold: the forge leaves them in hand.
			local taken = CarryService.TakeLogs(player, function(wood, figure)
				return wood.id == woodId and figure == nil
			end, want)
			profile.forgeLogs[woodId] = (profile.forgeLogs[woodId] or 0) + #taken
			added += #taken
		end
	end
	if figuredInHand(player, r.logs) > 0 then
		notify(player, "Figured logs are worth more sold than forged: take them to the sawmill.")
	end
	publish(player, profile)
	if added == 0 then
		notify(player, "The forge takes Lumenwood logs. Progress: " .. ForgeLogic.Progress(r, stockOf(profile)))
	else
		notify(player, "Into the forge. " .. ForgeLogic.Progress(r, stockOf(profile)))
	end
end

-- Forges a Starfall Axe if everything's there; otherwise says what's missing.
function AetherService.Forge(player: Player)
	if not RateLimiter.Allow(player, "BuyItem") then
		return
	end
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return
	end
	local _counts, ownedTotal = AxeService.OwnedCounts(player)
	if ownedTotal >= GameConfig.MaxOwnedAxes then
		notify(player, string.format("You own %d axes, the most you can carry. Drop one first.", ownedTotal))
		return
	end
	local r = recipe()
	local missing = ForgeLogic.Missing(r, stockOf(profile))
	if #missing > 0 then
		notify(player, "The forge needs " .. table.concat(missing, ", ") .. ".")
		return
	end
	-- Nothing below yields, so the check above still holds.
	if not EconomyService.SpendCash(player, r.cash, "forged Starfall Axe", FORGED_AXE) then
		return
	end
	for woodId, n in pairs(r.logs) do
		profile.forgeLogs[woodId] -= n
	end
	for materialId, n in pairs(r.materials) do
		profile.materials[materialId] -= n
	end
	local _item, tool = AxeService.Grant(player, FORGED_AXE)
	local char = player.Character
	local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if tool and humanoid then
		humanoid:EquipTool(tool)
	end
	publish(player, profile)
	NodeService.Publish(player)
	notify(player, "The Starfall Axe is yours! It fells Lumenwood in 12 hits.")
	pcall(function()
		AnalyticsService:LogCustomEvent(player, "StarfallForged")
	end)
end

local function hasCloak(player: Player): boolean
	local profile = ProfileService.GetProfile(player)
	return profile ~= nil and table.find(profile.gear, "FeatherfallCloak") ~= nil
end

-- The cloak opens: a vertical-only velocity limit, so you drift down at
-- GLIDE_SPEED and still steer sideways. It closes when you land.
local function startGlide(player: Player, root: BasePart)
	if root:FindFirstChild("Featherfall") then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "FeatherfallAttachment"
	attachment.Parent = root
	local glide = Instance.new("LinearVelocity")
	glide.Name = "Featherfall"
	glide.Attachment0 = attachment
	glide.RelativeTo = Enum.ActuatorRelativeTo.World
	glide.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	glide.LineDirection = Vector3.new(0, 1, 0)
	glide.LineVelocity = -GLIDE_SPEED
	glide.MaxForce = root.AssemblyMass * workspace.Gravity * 4
	glide.Parent = root
	notify(player, "Your Featherfall Cloak catches the wind.")
end

local function stopGlide(root: BasePart)
	for _, name in ipairs({ "Featherfall", "FeatherfallAttachment" }) do
		local inst = root:FindFirstChild(name)
		if inst then
			inst:Destroy()
		end
	end
end

-- Fell off without a cloak: the logs in your hands are lost to the clouds.
local function loseLogs(player: Player)
	local lost = CarryService.TakeWhere(player, function()
		return true
	end)
	if #lost > 0 then
		notify(player, string.format("You fell! %d log%s lost to the clouds.", #lost, if #lost == 1 then "" else "s"))
	end
end

local function tick()
	local area = sky().area
	if not area then
		return
	end
	local deck = (area.y or 0) + DECK_ABOVE_AREA
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
		if root and humanoid then
			local pos = root.Position
			local dx, dz = pos.X - area.x, pos.Z - area.z
			local flat2 = dx * dx + dz * dz
			if player:GetAttribute("Riding") == true then
				onIsles[player] = false
			elseif flat2 <= (area.radius + 30) ^ 2 and pos.Y >= deck - 5 then
				onIsles[player] = true
			elseif onIsles[player] then
				if flat2 > (area.radius + NEAR) ^ 2 then
					onIsles[player] = false -- gone some other way
				elseif hasCloak(player) then
					if pos.Y < deck - GLIDE_BELOW and root.AssemblyLinearVelocity.Y < -8 then
						onIsles[player] = false
						startGlide(player, root)
					end
				elseif pos.Y < deck - FALL_BELOW then
					onIsles[player] = false
					loseLogs(player)
				end
			end
			-- The glide ends on landing (or in the water).
			if
				root:FindFirstChild("Featherfall")
				and (
					humanoid.FloorMaterial ~= Enum.Material.Air
					or humanoid:GetState() == Enum.HumanoidStateType.Swimming
				)
			then
				stopGlide(root)
			end
		end
	end
end

-- Call once the save has loaded.
function AetherService.PlayerJoined(player: Player, profile: Profile)
	publish(player, profile)
end

local function addPrompt(
	part: Instance,
	action: string,
	object: string,
	hold: number,
	fn: (Player) -> ()
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.MaxActivationDistance = PROMPT_RANGE
	prompt.HoldDuration = hold
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(fn)
	return prompt
end

-- A prompt whose action reads `v1Text` or, under the v2 loop, `v2Text`
-- (InitV2 relabels the ones made before it).
local function loopPrompt(part: Instance, v1Text: string, v2Text: string, object: string, fn: (Player) -> ())
	local prompt = addPrompt(part, if v2 then v2Text else v1Text, object, 0, fn)
	table.insert(relabel, { prompt = prompt, v1 = v1Text, v2 = v2Text })
end

-- A tagged part the v2 loop polls as a hopper (once, however often its tag
-- signal fires).
local function addHopper(part: Instance, kind: HopperKind)
	if not part:IsA("BasePart") then
		return
	end
	for _, h in ipairs(hoppers) do
		if h.part == part then
			return
		end
	end
	table.insert(hoppers, { part = part, kind = kind, firstSeen = {} })
end

-- MapBuilder tags the chutes "CloudChute" and the forge's anvil
-- "StarfallForge"; the prompts go on them as they appear.
local function onTagged(tag: string, setup: (Instance) -> ())
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		setup(inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(setup)
end

-- `notifyFn` shows a toast (GameServer's notify).
function AetherService.Init(notifyFn: (Player, string) -> ())
	notify = notifyFn
	onTagged("CloudChute", function(part)
		loopPrompt(part, "Send logs down", "Check Sky Bin", "Cloud Chute", function(player: Player)
			if v2 then
				AetherService.ChuteInfo(player)
			else
				AetherService.SendDown(player)
			end
		end)
		addHopper(part, "chute")
	end)
	onTagged("StarfallForge", function(part)
		addPrompt(part, "Add lumenwood", "Starfall Forge", 0, AetherService.AddToForge)
		local forge = Instance.new("Attachment") -- a second prompt needs its own spot
		forge.Name = "ForgePoint"
		forge.Position = Vector3.new(0, 1.5, 0)
		forge.Parent = part
		addPrompt(forge, "Forge the Starfall Axe", "Starfall Forge", 1.5, AetherService.Forge)
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= 0.25 then
			elapsed = 0
			tick()
			if v2 then
				local ok, err = pcall(function(): any
					AetherService.HopperTick()
					return nil
				end)
				if not ok then
					warn("[AetherService] hopper tick failed: " .. tostring(err))
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		onIsles[player] = nil
		refusedAt[player] = nil
	end)
	-- A new character starts wherever it spawns, not on the isles.
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterAdded:Connect(function()
			onIsles[player] = nil
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function()
			onIsles[player] = nil
		end)
	end
end

-- The v2 loop's hoppers (GameServer, under CoreLoop.V2(), after Init).
-- The chutes' prompts turn informational; the Sky Bin gets its prompt.
function AetherService.InitV2(deps: V2Deps)
	v2 = deps
	for _, entry in ipairs(relabel) do
		entry.prompt.ActionText = entry.v2
	end
	local bin = deps.skyBin
	if bin then
		local prompt = addPrompt(bin, "Sell Sky Bin", "Sky Bin", 0, AetherService.SellSkyBin)
		prompt.Name = "SellSkyBin" -- WorldUI shows it only while your bin has wood in it
	else
		warn("[AetherService] No Sky Bin by the sell pad: it can't be sold")
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = ProfileService.GetProfile(player)
		if profile then
			publish(player, profile)
		end
	end
end

return AetherService
