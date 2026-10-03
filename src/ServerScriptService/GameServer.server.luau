--!strict
-- GameServer: bootstrap + remote handlers.
--   * Creates ReplicatedStorage/Remotes (names listed in Shared/Net).
--   * PlayerAdded: load save -> spawn Rustbucket -> hand over every owned axe
--     (AxeService; axes are items the player can switch, drop and pick up).
--   * PlayerRemoving: drop carried logs, final save + release the session.
--   * Every remote is rate-limited and server-validated. The client only
--     sends intents; the services own the truth. BuyItem is handled by
--     ShopService.
-- Autosave, shutdown flushing and session locks are ProfileStore's job
-- (see ProfileService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AetherService = require(script.Parent.AetherService)
local AxeService = require(script.Parent.AxeService)
local BiomeService = require(script.Parent.BiomeService)
local BootReport = require(script.Parent.BootReport)
local DailyService = require(script.Parent.DailyService)
local DevCommands = require(script.Parent.DevCommands)
local EconomyService = require(script.Parent.EconomyService)
local FieldGuideService = require(script.Parent.FieldGuideService)
local ForestService = require(script.Parent.ForestService)
local GondolaService = require(script.Parent.GondolaService)
local GrabService = require(script.Parent.GrabService)
local SectionTrees = require(script.Parent.SectionTrees)
local SellService = require(script.Parent.SellService)
local MilestoneService = require(script.Parent.MilestoneService)
local MonetizationService = require(script.Parent.MonetizationService)
local NodeService = require(script.Parent.NodeService)
local NPCService = require(script.Parent.NPCService)
local PlaceCheck = require(script.Parent.PlaceCheck)
local PlotService = require(script.Parent.PlotService)
local ProfileSchema = require(script.Parent.ProfileSchema)
local ProfileService = require(script.Parent.ProfileService)
local QuestService = require(script.Parent.QuestService)
local SaveFlush = require(script.Parent.SaveFlush)
local RateLimiter = require(script.Parent.RateLimiter)
local ShopService = require(script.Parent.ShopService)
local TruckLoad = require(script.Parent.TruckLoad)
local VehicleService = require(script.Parent.VehicleService)
local WeatherService = require(script.Parent.WeatherService)
local WoodService = require(script.Parent.WoodService)
local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Net = require(ReplicatedStorage.Shared.Net)
local SellLogic = require(ReplicatedStorage.Shared.SellLogic)
local Util = require(ReplicatedStorage.Shared.Util)

-- Runs one service's Init, join or leave hook on its own: an error in one
-- is logged with a traceback and doesn't stop the others (a broken Init
-- must never keep players out). tostring first: debug.traceback itself
-- errors on a non-string error.
local function safely(name: string, fn: (...any) -> ...any, ...: any)
	local args = table.pack(...)
	local ok, err = xpcall(function(): any
		fn(table.unpack(args, 1, args.n))
		return nil
	end, function(e: any): string
		return debug.traceback(tostring(e), 2)
	end)
	if not ok then
		warn(string.format("[GameServer] %s failed:\n%s", name, tostring(err)))
	end
end

-- Does the live place match default.project.json (and, in Studio, can it
-- save)? A warning names each fix; "[PlaceCheck] OK" when all match. Its
-- own thread: in Studio it waits a moment for ProfileStore's access probe.
task.spawn(function()
	safely("PlaceCheck.Run", PlaceCheck.Run)
end)

-- Wait for the code-built world. MapBuilder writes the terrain first (a few
-- seconds to a minute) and adds the SellArea last, once everything exists.
local mapFolder = workspace:WaitForChild("TimberlineMap", 60)
assert(mapFolder, "[GameServer] TimberlineMap was not built (MapBuilder failed?)")
local sellArea = mapFolder:WaitForChild("SellArea", 600)
assert(sellArea, "[GameServer] SellArea missing")
local sellZoneInst = sellArea:WaitForChild("SellZone", 30)
assert(sellZoneInst and sellZoneInst:IsA("BasePart"), "[GameServer] SellZone missing")
local sellZone = sellZoneInst :: BasePart

-- Remotes -----------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local remote: { [string]: RemoteEvent } = {}
for _, name in ipairs(Net.RemoteNames) do
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = remotes
	remote[name] = re
end
remotes.Parent = ReplicatedStorage

safely("EconomyService.Init", EconomyService.Init, remotes)

-- Per-player state ---------------------------------------------------------
local nextSwingAt: { [number]: number } = {}
local lastNotice: { [number]: { [string]: number } } = {}

-- Short on-screen message. The same text at most once a second, so
-- spam-clicking can't spam toasts.
local function notify(player: Player, message: string)
	local seen = lastNotice[player.UserId]
	if not seen then
		return
	end
	local now = os.clock()
	local last = seen[message]
	if last and now - last < 1 then
		return
	end
	seen[message] = now
	-- Most messages are one-offs (cash amounts, counts): forget old ones so
	-- the table doesn't grow for as long as the player stays.
	if math.random() < 0.05 then
		for text, at in pairs(seen) do
			if now - at > 2 then
				seen[text] = nil
			end
		end
	end
	remote.Notify:FireClient(player, message)
end

local function getCharacterParts(player: Player): (Model?, BasePart?)
	local char = player.Character
	if not char then
		return nil, nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	return char, hrp
end

-- One swing at a crystal node (any axe; the same swing cooldown as chopping).
local function onMineNode(player: Player, nodeUid: unknown)
	if type(nodeUid) ~= "string" or not RateLimiter.Allow(player, "MineNode") then
		return
	end
	local char = getCharacterParts(player)
	if not char or not AxeService.GetEquippedAxe(player) then
		return
	end
	local now = os.clock()
	local due = nextSwingAt[player.UserId] or 0
	if now < due - GameConfig.SwingTolerance then
		return
	end
	local result = NodeService.Hit(player, nodeUid)
	if result == "far" then
		notify(player, "Too far away. Walk closer to mine.")
	elseif result then
		nextSwingAt[player.UserId] = math.max(now, due) + GameConfig.SwingCooldown
	end
end

-- Instant Delivery (a Robux product): sells the loose wood on the truck
-- from anywhere. SellService checks the wallet before spending a use.
local function onInstantDelivery(player: Player)
	if not RateLimiter.Allow(player, "UseInstantDelivery") then
		return
	end
	SellService.SellBed(player, function(): boolean
		return MonetizationService.UseInstantDelivery(player)
	end)
end

-- A sale (SellService, per payee per tick), which SellService has paid
-- and toasted: what the stopwatch, the Living Forest's reveals, the
-- tutorial and the daily goals hear about.
local function onWoodSold(sale: SellService.Sale)
	local player = sale.payee
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return -- left meanwhile: nothing was credited
	end
	profile.stats.volumeSold = (profile.stats.volumeSold or 0) + sale.volume
	local credited = sale.credited
	MilestoneService.Mark(player, "First sale")
	MilestoneService.CashEarned(player, credited)
	MilestoneService.WoodSold(player, sale.pieces, sale.woods)
	if #sale.figures > 0 then
		local figures: { [string]: number } = {}
		for _, figure in ipairs(sale.figures) do
			figures[figure] = (figures[figure] or 0) + 1
		end
		safely("ForestService.OnSale", ForestService.OnSale, player, figures)
	end
	local overflow = sale.paid - credited
	if overflow > 0 then
		notify(
			player,
			string.format(
				"Wallet full at %s: %s didn't fit. Spend some!",
				Util.formatCash(GameConfig.CashCap),
				Util.formatCash(overflow)
			)
		)
	end
	-- After the sale's toasts, so rewards read last.
	safely("QuestService.WoodSold", QuestService.WoodSold, player, sale.pieces, credited)
	safely("DailyService.WoodSold", DailyService.WoodSold, player, {
		volume = sale.volume,
		cash = credited,
		byWood = sale.woods,
		pieces = sale.pieceVolumes,
		figured = sale.figured,
	})
end

-- Each Init on its own (safely): one failing leaves that service broken
-- but the server, the other services and spawning carry on. The services
-- that read v2 data (prices, tutorial steps, daily goals) get the core
-- loop that runs (MapBuilder published it before the map was built).
local activeLoop = CoreLoop.Active()
safely("MilestoneService.Init", MilestoneService.Init, notify, activeLoop)
safely("AxeService.Init", AxeService.Init, notify)
safely("ShopService.Init", ShopService.Init, mapFolder, remote.BuyItem, remote.EquipItem, notify, activeLoop)
safely("VehicleService.Init", VehicleService.Init, notify)
safely("QuestService.Init", QuestService.Init, remote.SkipTutorial, notify, activeLoop)
safely("DailyService.Init", DailyService.Init, notify, nil, activeLoop)
safely("BiomeService.Init", BiomeService.Init, notify)
safely("MonetizationService.Init", MonetizationService.Init, remote.BuyRobuxItem, notify)
safely("FieldGuideService.Init", FieldGuideService.Init, notify)
safely("NodeService.Init", NodeService.Init, notify)
safely("AetherService.Init", AetherService.Init, notify)
safely("GondolaService.Init", GondolaService.Init, mapFolder, notify)
safely("PlotService.Init", PlotService.Init, mapFolder, {
	PlaceBlueprint = remote.PlaceBlueprint,
	MoveBlueprint = remote.MoveBlueprint,
	SellPlaced = remote.SellPlaced,
	UpgradePlot = remote.UpgradePlot,
}, notify)
safely("ForestService.Init", ForestService.Init, { PlantSeed = remote.PlantSeed, WorldFX = remote.WorldFX }, notify, {
	sectionTrees = SectionTrees,
	setFigure = WoodService.SetFigure,
})
safely("WeatherService.Init", WeatherService.Init, remote.WorldFX)
safely("NPCService.Init", NPCService.Init, mapFolder)
-- Grab and drag loose wood, and Studio's /spawnwood.
-- Grabbing a piece: the tutorial's drag step and the funnel's pickup.
GrabService.Hooks.onGrab = function(player: Player, _piece: GrabService.Piece)
	safely("woodGrabbed", function()
		MilestoneService.Mark(player, "First log picked up")
		QuestService.Event(player, "woodGrabbed")
	end)
end
-- The sell pad sells loose wood by volume (M1.7).
local woodFolder = mapFolder:FindFirstChild("Wood")
if not woodFolder then
	local made = Instance.new("Folder")
	made.Name = "Wood"
	made.Parent = mapFolder
	woodFolder = made
end
-- Loose wood (M1.3): every piece a cut frees, its despawn and caps, and
-- WoodWatch (which judges held wood too, so GrabService doesn't).
safely("WoodService.Init", WoodService.Init, { worldFx = remote.WorldFX, folder = woodFolder })
GrabService.SetResolver(function(part: BasePart): GrabService.Piece?
	return WoodService.FromPart(part) :: any
end)
GrabService.JudgeMoves = false
safely("GrabService.Init", GrabService.Init, { Grab = remote.Grab, Release = remote.Release }, notify)
safely("DevCommands.Init", DevCommands.Init, notify)
-- A sold piece's "+$" pop on the pad: what its payee is paid for it.
local function saleFx(model: Model)
	local piece = WoodService.FromModel(model)
	if not piece then
		return
	end
	local payeeId = SellLogic.Payee(piece.ownerId, piece.lastHolderId, function(userId: number): boolean
		return Players:GetPlayerByUserId(userId) ~= nil
	end)
	local payee = if payeeId then Players:GetPlayerByUserId(payeeId) else nil
	if payee then
		WoodService.SaleFx(model, SellLogic.Payout(piece.value, MonetizationService.SaleMultiplier(payee)))
	end
end
safely("SellService.Init", SellService.Init, {
	zone = sellZone,
	woodFolder = woodFolder :: Instance,
	resolve = function(model: Model): SellService.Piece?
		-- Only wood WoodWatch last found where it should be (no teleports to the pad).
		local piece = WoodService.FromModel(model)
		if piece and not WoodService.VerdictOk(piece) then
			return nil
		end
		return piece :: any
	end,
	addCash = function(player: Player, amount: number, reason: string, sku: string): number?
		local credited = EconomyService.AddCash(player, amount, reason, sku)
		return credited
	end,
	saleMultiplier = MonetizationService.SaleMultiplier,
	notify = notify,
	release = function(model: Model)
		GrabService.ReleasePiece(model, "sold")
	end,
	forget = function(model: Model)
		saleFx(model)
		WoodService.Forget(model)
		GrabService.Unregister(model)
	end,
	onSold = onWoodSold,
	-- Instant Delivery v2: the wood riding on the player's beds.
	bedPieces = function(player: Player): { Model }
		return TruckLoad.PiecesOn(player)
	end,
	walletRoom = function(player: Player): number
		local profile = ProfileService.GetProfile(player)
		return if profile then GameConfig.CashCap - profile.cash else 0
	end,
})
-- Loose wood rides on the truck beds (M1.6): by friction, simulated by
-- the driver's device while they drive, saved in profile.truckLoad.
safely("TruckLoad.Init", TruckLoad.Init, {
	woodFolder = woodFolder :: Instance,
	truckOf = VehicleService.GetVehicle,
	profileOf = function(player: Player): any
		return ProfileService.GetProfile(player)
	end,
	notify = notify,
	-- A saved load comes back as WoodService pieces (its sections
	-- linked by contact), so they cut, grab and sell like any other.
	build = function(saved: any, owner: Player, cf: CFrame, graceSec: number): Model?
		local model = TruckLoad.Build(saved, owner, cf, graceSec)
		if model then
			GrabService.Unregister(model)
			WoodService.Register(model, {
				woodId = saved.w,
				nodes = {},
				parts = {},
				ownerId = owner.UserId,
				figure = saved.f,
				boost = saved.x,
				createdAt = os.clock() - GameConfig.PickupGraceSec + math.max(0, graceSec),
			})
		end
		return model
	end,
	forget = function(model: Model)
		WoodService.Forget(model)
		GrabService.Unregister(model)
	end,
	moved = WoodService.Moved,
})
VehicleService.Hooks.onDriverChanged = TruckLoad.OnDriverChanged
VehicleService.Hooks.onRebuild = TruckLoad.OnRebuild
VehicleService.Hooks.loadCount = TruckLoad.LoadCount
-- A piece of yours came to rest on your own bed: the tutorial's "load"
-- step (TutorialData.StepsV2) and the funnel.
TruckLoad.Hooks.onLoaded = function(player: Player)
	MilestoneService.Mark(player, "First log loaded")
	QuestService.Event(player, "woodLoaded")
end
-- The section trees (M1.3): the Living Forest moves onto them, and the
-- Chop remote cuts them (and loose pieces) wherever you swing.
SectionTrees.StumpHold = QuestService.StumpHoldFor
SectionTrees.LogMultiplier = MonetizationService.LogMultiplier
-- A felling counts for whoever cut the most of the tree (stats, the
-- tutorial's treeFelled, dailies, the Field Guide), as in v1.
SectionTrees.Hooks.onFelled = function(feller: Player, rec: SectionTrees.TreeRecord)
	local profile = ProfileService.GetProfile(feller)
	if not profile then
		return
	end
	profile.stats.treesChopped += 1
	MilestoneService.Mark(feller, "First tree felled")
	QuestService.Event(feller, "treeFelled")
	DailyService.Event(feller, "treeFelled", 1)
	FieldGuideService.Discover(feller, rec.def.id)
end
SectionTrees.Hooks.onSwing = function(player: Player)
	MilestoneService.Mark(player, "First chop")
end
safely("SectionTrees.Init", SectionTrees.Init, {
	notify = notify,
	worldFx = remote.WorldFX,
	getAxe = AxeService.GetEquippedAxe,
	canChop = BiomeService.CanChop,
	swingDue = function(player: Player): number
		return nextSwingAt[player.UserId] or 0
	end,
	setSwingDue = function(player: Player, at: number)
		nextSwingAt[player.UserId] = at
	end,
})
remote.Chop.OnServerEvent:Connect(function(player: Player, part: unknown, hitPos: unknown, normal: unknown)
	SectionTrees.Chop(player, part, hitPos, normal)
end)
-- The isles take loose wood (M1.7b): the Cloud Chutes and the Starfall
-- Forge are hoppers found the way the pad finds pieces, the Sky Bin by
-- the pad sells through SellService.PayEntries, and wood that falls off
-- the isles is lost.
local skyBinPart = sellArea:FindFirstChild("SkyBin")
safely("AetherService.InitV2", AetherService.InitV2, {
	woodFolder = woodFolder :: Instance,
	resolve = function(model: Model): SellService.Piece?
		-- As the pad: only wood WoodWatch last found where it should be.
		local piece = WoodService.FromModel(model)
		if piece and not WoodService.VerdictOk(piece) then
			return nil
		end
		return piece :: any
	end,
	release = function(model: Model)
		GrabService.ReleasePiece(model, "taken")
	end,
	forget = function(model: Model)
		WoodService.Forget(model)
		GrabService.Unregister(model)
	end,
	skyBin = if skyBinPart and skyBinPart:IsA("BasePart") then skyBinPart else nil,
	heldBy = GrabService.HeldBy,
})
remote.MineNode.OnServerEvent:Connect(onMineNode)
remote.UseInstantDelivery.OnServerEvent:Connect(onInstantDelivery)

remote.DropAxe.OnServerEvent:Connect(AxeService.Drop)
remote.CallTruck.OnServerEvent:Connect(function(player: Player)
	if not RateLimiter.Allow(player, "CallTruck") then
		return
	end
	local ok, why = VehicleService.Recall(player)
	if ok then
		notify(player, "Your truck is back in your parking spot.")
	elseif why then
		notify(player, why)
	end
end)

-- Settings toggles (music, sound effects), mirrored on SettingMusic /
-- SettingSfx attributes so the client applies them when the save loads.
local SETTING_ATTRIBUTES = { music = "SettingMusic", sfx = "SettingSfx" }
remote.SaveSetting.OnServerEvent:Connect(function(player: Player, key: unknown, on: unknown)
	if not RateLimiter.Allow(player, "SaveSetting") then
		return
	end
	local profile = ProfileService.GetProfile(player)
	if not profile or type(key) ~= "string" or type(on) ~= "boolean" or not SETTING_ATTRIBUTES[key] then
		return
	end
	(profile.settings :: any)[key] = on
	player:SetAttribute(SETTING_ATTRIBUTES[key], on)
end)

-- Player lifecycle --------------------------------------------------------

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	if player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 10) then
		AxeService.GiveLoadout(player, character)
	end
end

local function onPlayerAdded(player: Player)
	player:SetAttribute("ProfileLoaded", false) -- the HUD shows "Loading your save..."
	lastNotice[player.UserId] = {}

	local profile, err = ProfileService.LoadProfile(player)
	if not profile then
		if err == "failed" then
			player:Kick("Timberline Tycoon couldn't load your save right now. Your progress is safe. Please rejoin.")
		end
		return -- "left": they're already gone
	end

	-- A save naming a truck that no longer exists (or isn't owned) falls
	-- back to the starter.
	if
		not ItemCatalog.GetTruck(profile.equippedTruck) or not table.find(profile.ownedTrucks, profile.equippedTruck)
	then
		profile.equippedTruck = "Rustbucket"
	end
	if profile.equippedTrailer ~= "" and not table.find(profile.ownedTrailers, profile.equippedTrailer) then
		profile.equippedTrailer = ""
	end

	-- v1 logs still on hand are bought back (and a first join topped up to
	-- StartingCash) into v2Credit, before the truck spawns (V2_PLAN.md §14).
	-- MigrateV2 is idempotent, so a save already on v2 is left alone.
	local boughtBack = 0
	safely("ProfileSchema.MigrateV2", function()
		local moved = ProfileSchema.MigrateV2(profile)
		boughtBack = moved.boughtBack
		if moved.migrated then
			print(
				string.format(
					"[GameServer] %s's save is now on the v2 loop (bought back $%d, topped up $%d)",
					player.Name,
					moved.boughtBack,
					moved.toppedUp
				)
			)
		end
	end)

	player:SetAttribute("Cash", profile.cash)
	player:SetAttribute("SettingMusic", profile.settings.music ~= false)
	player:SetAttribute("SettingSfx", profile.settings.sfx ~= false)
	if profile.pendingCash > 0 then
		player:SetAttribute("PendingCash", profile.pendingCash)
		EconomyService.PayPending(player)
	end
	-- What MigrateV2 left owed, through the wallet (overflow banked).
	if profile.v2Credit > 0 then
		safely("pay v2Credit", function()
			local owed = math.floor(profile.v2Credit)
			profile.v2Credit = 0
			local credited, banked = EconomyService.AddOwedCash(player, owed, "v2 buy-back", "v2BuyBack")
			local text = ProfileSchema.CreditText(credited + banked, boughtBack)
			if text then
				notify(player, text)
			end
		end)
	end
	safely("VehicleService.SpawnTruck", function()
		VehicleService.SpawnTruck(player, profile.equippedTruck, nil, profile.equippedTrailer)
	end)

	player.CharacterAdded:Connect(function(char)
		onCharacterAdded(player, char)
	end)
	local existing = player.Character
	if existing then
		task.spawn(onCharacterAdded, player, existing)
	end

	player:SetAttribute("ProfileLoaded", true)
	remote.CashChanged:FireClient(player, profile.cash)
	safely("MilestoneService.Start", MilestoneService.Start, player, profile)
	safely("QuestService.Start", QuestService.Start, player, profile)
	safely("DailyService.Start", DailyService.Start, player, profile)
	safely("ShopService.PlayerJoined", ShopService.PlayerJoined, player, profile)
	safely("MonetizationService.PlayerJoined", MonetizationService.PlayerJoined, player, profile)
	safely("FieldGuideService.Refresh", FieldGuideService.Refresh, player)
	safely("NodeService.Publish", NodeService.Publish, player)
	safely("AetherService.PlayerJoined", AetherService.PlayerJoined, player, profile)
	safely("PlotService.PlayerJoined", PlotService.PlayerJoined, player, profile)
	safely("ForestService.PlayerJoined", ForestService.PlayerJoined, player, profile)
	print(string.format("[GameServer] %s joined (cash $%d)", player.Name, profile.cash))
end

local function onPlayerRemoving(player: Player)
	-- Playtime and the truck's wood are also copied in ProfileStore's OnSave
	-- (SaveFlush), which runs on BindToClose before this handler. Stop and
	-- PlayerRemoving still write them here, then seal the truck snapshot so
	-- a later save doesn't blank it after the models are gone.
	safely("MilestoneService.Stop", MilestoneService.Stop, player)
	safely("AxeService.PlayerRemoving", AxeService.PlayerRemoving, player) -- world models only; the axe stays in the save
	safely("MonetizationService.PlayerRemoving", MonetizationService.PlayerRemoving, player)
	safely("PlotService.PlayerRemoving", PlotService.PlayerRemoving, player)
	safely("ForestService.PlayerRemoving", ForestService.PlayerRemoving, player)
	safely("TruckLoad.PlayerRemoving", TruckLoad.PlayerRemoving, player)
	ProfileService.ReleaseProfile(player)
	VehicleService.DespawnTruck(player)
	RateLimiter.Forget(player)
	nextSwingAt[player.UserId] = nil
	lastNotice[player.UserId] = nil
	print(string.format("[GameServer] %s left (saving)", player.Name))
end

-- Before any profile loads: every save, including BindToClose, copies
-- live playtime and truck wood into the profile first.
SaveFlush.Add(function(player: Player)
	MilestoneService.Flush(player)
end)
SaveFlush.Add(function(player: Player)
	TruckLoad.Flush(player)
end)

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
-- Catch players who joined before this script ran.
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, p)
end

-- The boot report (PLAY-01): how long the world took, trees, players.
print(BootReport.Line(workspace, #Players:GetPlayers()))
