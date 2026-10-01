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
--   * Figured logs (the Hidden Grain, a Starfall Burl) carry their figure on
--     the log, and the Sky Bin only keeps wood ids, so they stay in your
--     hands: you ride them down on the gondola and sell them at the mill.
--     The forge doesn't take them either (they're worth more sold).
-- Mirrored on the SkyBin (log count) and ForgeLogs attributes.

local AnalyticsService = game:GetService("AnalyticsService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BiomeData = require(ReplicatedStorage.Shared.BiomeData)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ForgeLogic = require(ReplicatedStorage.Shared.ForgeLogic)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)
local AxeService = require(script.Parent.AxeService)
local CarryService = require(script.Parent.CarryService)
local EconomyService = require(script.Parent.EconomyService)
local NodeService = require(script.Parent.NodeService)
local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)
local TreeService = require(script.Parent.TreeService)

type Profile = ProfileService.Profile

local AetherService = {}

local FORGED_AXE = "StarfallAxe"
local GLIDE_SPEED = 14 -- studs/s: the cloak holds your fall to this
local DECK_ABOVE_AREA = 40 -- the isles' walking surfaces sit about 50 above the sky area's y (WorldPlan.Sky)
local GLIDE_BELOW = 15 -- studs under the deck where the cloak opens
local FALL_BELOW = 40 -- studs under the deck that count as falling off
local NEAR = 250 -- further than this from the isles (sideways) isn't a fall: a respawn or teleport

local notify: (Player, string) -> () = function(_player: Player, _message: string) end
local onIsles: { [Player]: boolean } = {}

local function sky(): BiomeData.BiomeDef
	return BiomeData.Get("sky") :: BiomeData.BiomeDef
end

local function binCapacity(): number
	return sky().skyBinCapacity or 30
end

local function publish(player: Player, profile: Profile)
	player:SetAttribute("SkyBin", #profile.skyBin)
	player:SetAttribute("ForgeLogs", ShopLogic.EncodeOwned(profile.forgeLogs))
end

local function stockOf(profile: Profile): ForgeLogic.Stock
	return { cash = profile.cash, logs = profile.forgeLogs, materials = profile.materials }
end

local function recipe(): ItemCatalog.ForgeRecipe
	local axe = ItemCatalog.GetAxe(FORGED_AXE) :: ItemCatalog.AxeDef
	return axe.forge :: ItemCatalog.ForgeRecipe
end

-- Runs `take` with the player's figured logs set aside, so it can't take
-- them (CarryService.TakeWhere only sees each log's wood). Returns what
-- `take` returned and how many figured logs stayed in hand.
local function withoutFigured(player: Player, take: () -> { string }): ({ string }, number)
	local hands = CarryService.Hands(player)
	local aside: { string } = {}
	if hands then
		for uid in pairs(hands) do
			local log = TreeService.GetLog(uid)
			if log and log.tags.figure ~= nil then
				table.insert(aside, uid)
			end
		end
		for _, uid in ipairs(aside) do
			hands[uid] = nil
		end
	end
	local taken = take()
	if hands then
		for _, uid in ipairs(aside) do
			hands[uid] = true
		end
		CarryService.Publish(player)
	end
	return taken, #aside
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
	local sent, kept = withoutFigured(player, function()
		return CarryService.TakeWhere(player, function()
			return true
		end, space)
	end)
	if kept > 0 then
		notify(
			player,
			"Figured wood is too precious for the chute: carry it down on the gondola and sell it at the mill."
		)
	end
	if #sent == 0 then
		if kept == 0 then
			notify(player, "Bring logs to send them down the Cloud Chute.")
		end
		return
	end
	for _, woodId in ipairs(sent) do
		table.insert(profile.skyBin, woodId)
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

-- Empties the player's Sky Bin (selling at the sawmill) and returns the wood ids.
function AetherService.TakeSkyBin(player: Player): { string }
	local profile = ProfileService.GetProfile(player)
	if not profile or #profile.skyBin == 0 then
		return {}
	end
	local out = profile.skyBin
	profile.skyBin = {}
	publish(player, profile)
	return out
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
	local added, figured = 0, 0
	for woodId in pairs(r.logs) do
		local want = ForgeLogic.LogsWanted(r, stockOf(profile), woodId)
		if want > 0 then
			local taken, kept = withoutFigured(player, function()
				return CarryService.TakeWhere(player, function(wood)
					return wood.id == woodId
				end, want)
			end)
			profile.forgeLogs[woodId] = (profile.forgeLogs[woodId] or 0) + #taken
			added += #taken
			figured = math.max(figured, kept)
		end
	end
	if figured > 0 then
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

local function addPrompt(part: Instance, action: string, object: string, hold: number, fn: (Player) -> ())
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.MaxActivationDistance = 10
	prompt.HoldDuration = hold
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(fn)
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
		addPrompt(part, "Send logs down", "Cloud Chute", 0, AetherService.SendDown)
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
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		onIsles[player] = nil
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

return AetherService
