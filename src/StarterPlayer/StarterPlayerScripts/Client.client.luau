--!strict
-- Client: entry point for the Timberline Tycoon client.
-- Just starts each controller. All game state lives on the server;
-- these controllers only render UI and effects, and send intents.
-- Each one loads and starts in its own protected call: one that errors
-- (at its top level, in Start, or waiting forever on something that never
-- streams in) can't stop the others, and its error goes to Output with a
-- traceback. The HUD starts first, also protected: if it fails, the
-- others still start (without the HUD's corner and side buttons, which
-- they skip with a warning).

-- StarterPlayerScripts' modules are copied into PlayerScripts one by one,
-- and this script can start before all its siblings have arrived: a plain
-- require of one that isn't there yet stops the whole client (no HUD,
-- quest, axe or drag). So wait for every one of them first (each module
-- requires its siblings directly), MODULE_WAIT seconds for all of them
-- together. The list is every module in this folder (Client.spec checks
-- it).
-- ReplicatedStorage.Shared may not have replicated yet either: wait for the
-- folder (bounded) before the first require of anything in it.
local SHARED_WAIT = 30
local SharedFolder = game:GetService("ReplicatedStorage"):WaitForChild("Shared", SHARED_WAIT)
if not SharedFolder then
	warn("[Client] ReplicatedStorage.Shared did not arrive in " .. SHARED_WAIT .. " seconds; the client cannot start")
	return
end
local ModulesReady = require(SharedFolder:WaitForChild("ModulesReady", SHARED_WAIT))
local MODULES = {
	"AdminUI",
	"AmbientLife",
	"AmbientSound",
	"AxeController",
	"BadgeUI",
	"BlueprintPlacer",
	"BoxPoof",
	"BuilderTools",
	"CameraShake",
	"CanopyFade",
	"CarryController",
	"CarryPose",
	"ChopController",
	"ChopSawController",
	"CraftUI",
	"CutController",
	"DailyUI",
	"DialogueUI",
	"DoorAnim",
	"DragController",
	"FaceTarget",
	"FerryController",
	"FieldGuideUI",
	"ForestFiller",
	"ForestUI",
	"ForgeUI",
	"GamepadNav",
	"GondolaController",
	"HUD",
	"HammerController",
	"HoverTagUI",
	"HudLayout",
	"HudNav",
	"IdlePing",
	"HudRules",
	"LeaderboardUI",
	"LifeFX",
	"LightingController",
	"LogicPanelUI",
	"LuxFX",
	"MenuPad",
	"MiningUI",
	"NPCController",
	"NewsUI",
	"PlaceControls",
	"PlotPickerUI",
	"PlotUI",
	"PromptSwitch",
	"PromptUI",
	"Quality",
	"QualityDressing",
	"QualityPickerUI",
	"QuestUI",
	"QuickMenuUI",
	"RegionFX",
	"SaveSlotUI",
	"SawmillController",
	"SettingsUI",
	"ShopDoorAnim",
	"ShopUI",
	"StorePrices",
	"StoreStandState",
	"StoreUI",
	"SprintController",
	"SwingPose",
	"TownFX",
	"TownMarkers",
	"TreeCosmetics",
	"TreeFX",
	"TreeUI",
	"UIArt",
	"UITheme",
	"VehicleController",
	"VehicleFX",
	"WeatherController",
	"WindSway",
	"WireTool",
	"WoodFX",
	"WorldUI",
}
local MODULE_WAIT = 30 -- seconds for all of them together, then it starts without the missing ones
do
	local folder = script.Parent
	local deadline = os.clock() + MODULE_WAIT
	for _, name in ipairs(MODULES) do
		if folder:FindFirstChild(name) == nil then
			local left = deadline - os.clock()
			if left <= 0 or folder:WaitForChild(name, left) == nil then
				warn(string.format("[Client] %s never arrived in PlayerScripts; starting without it", name))
			end
		end
	end
	-- MiningClient and ForgeClient run on their own and wait for this before
	-- their first require (a half-synced folder cached CraftUI and others as
	-- failed). Set it even after a timeout: they would only hang otherwise.
	ModulesReady.Mark(folder)
end

local Players = game:GetService("Players")
local JoinFlow = require(SharedFolder:WaitForChild("JoinFlow", SHARED_WAIT))
local Net = require(SharedFolder:WaitForChild("Net", SHARED_WAIT))
local ClientBoot = require(SharedFolder:WaitForChild("ClientBoot", SHARED_WAIT))
local PerfProbe = require(SharedFolder:WaitForChild("PerfProbe", SHARED_WAIT))

-- Which controllers wait until the player can play (ClientBoot), and in what
-- order (lowest first: what a player reaches soonest). Everything else starts
-- at once, as it always did: input, the HUD, camera, grab and drag, chop, the
-- tools, the join screens (plot picker, save slots, quality), the shops, the
-- quest card, vehicles, prompts and the loading handoff are needed to play.
-- A deferred one used before its turn starts on first use (ClientBoot.Ensure:
-- the tools when one is equipped or begun, the dialogue box when a talk opens,
-- the news and the foreman's board when opened). None of them is something
-- the server's join resend (JoinSync: cash, plot offer, save slots) targets.
local DEFERRED: { [string]: number } = {
	HammerController = 10, -- until a hammer is held (the tool watcher below, or Equip)
	BlueprintPlacer = 11, -- until a blueprint is held (Begin)
	DialogueUI = 12, -- the talk box (Talk)
	DailyUI = 13, -- the foreman's job board (OpenForeman)
	WoodFX = 14,
	LuxFX = 15,
	NewsUI = 16, -- (Open)
	TownMarkers = 17,
	TreeCosmetics = 18,
	WindSway = 19,
	RegionFX = 20,
	TownFX = 21,
	LifeFX = 22,
	AmbientLife = 23,
	AmbientSound = 24,
	CanopyFade = 25,
	StoreStandState = 26,
	ForestFiller = 30, -- last: it plans the filler forest on its own, after the player is in
}
-- Frames the queue waits after the player can play (the loading card's fade).
local RELEASE_SETTLE_FRAMES = 30

type Controller = { Start: () -> () }

-- Requires one module (`get` does the require), protected: a module whose
-- top level errors, or that never arrived, is skipped with a warning.
local function load(name: string, get: () -> any): Controller?
	local ok, result = xpcall(get, debug.traceback)
	if not ok then
		warn(string.format("[Client] %s failed to load:\n%s", name, tostring(result)))
		return nil
	end
	return result :: Controller
end

local HUD = load("HUD", function()
	return require(script.Parent.HUD)
end)

local controllers: { { name: string, get: () -> any } } = {
	{
		name = "Quality",
		get = function()
			return require(script.Parent.Quality)
		end,
	},
	{
		name = "QualityDressing", -- the shop boxes' windows and lights for the Lower / Higher choice
		get = function()
			return require(script.Parent.QualityDressing)
		end,
	},
	{
		name = "LightingController",
		get = function()
			return require(script.Parent.LightingController)
		end,
	},
	{
		name = "ChopController",
		get = function()
			return require(script.Parent.ChopController)
		end,
	},
	{
		name = "ChopSawController",
		get = function()
			return require(script.Parent.ChopSawController)
		end,
	},
	{
		name = "TreeUI",
		get = function()
			return require(script.Parent.TreeUI)
		end,
	},
	{
		name = "TreeFX",
		get = function()
			return require(script.Parent.TreeFX)
		end,
	},
	{
		name = "CarryController",
		get = function()
			return require(script.Parent.CarryController)
		end,
	},
	{
		name = "SwingPose", -- before CarryPose, so a carried log wins the arms
		get = function()
			return require(script.Parent.SwingPose)
		end,
	},
	{
		name = "CarryPose",
		get = function()
			return require(script.Parent.CarryPose)
		end,
	},
	{
		name = "DoorAnim",
		get = function()
			return require(script.Parent.DoorAnim)
		end,
	},
	{
		name = "BoxPoof",
		get = function()
			return require(script.Parent.BoxPoof)
		end,
	},
	{
		name = "ShopDoorAnim",
		get = function()
			return require(script.Parent.ShopDoorAnim)
		end,
	},
	{
		name = "DragController", -- the v2 loop only
		get = function()
			return require(script.Parent.DragController)
		end,
	},
	{
		name = "CutController", -- the v2 loop only
		get = function()
			return require(script.Parent.CutController)
		end,
	},
	{
		name = "WoodFX", -- the v2 loop only
		get = function()
			return require(script.Parent.WoodFX)
		end,
	},
	{
		name = "LuxFX",
		get = function()
			return require(script.Parent.LuxFX)
		end,
	},
	{
		name = "AxeController",
		get = function()
			return require(script.Parent.AxeController)
		end,
	},
	{
		name = "ShopUI",
		get = function()
			return require(script.Parent.ShopUI)
		end,
	},
	{
		name = "QuestUI",
		get = function()
			return require(script.Parent.QuestUI)
		end,
	},
	{
		name = "VehicleController",
		get = function()
			return require(script.Parent.VehicleController)
		end,
	},
	{
		name = "VehicleFX",
		get = function()
			return require(script.Parent.VehicleFX)
		end,
	},
	{
		name = "GondolaController",
		get = function()
			return require(script.Parent.GondolaController)
		end,
	},
	{
		name = "FerryController",
		get = function()
			return require(script.Parent.FerryController)
		end,
	},
	-- DailyUI is now Rook Calloway's job board (Lane E): it no longer needs
	-- the removed DailyButton size, so it starts again. NPCController opens it.
	{
		name = "DailyUI",
		get = function()
			return require(script.Parent.DailyUI)
		end,
	},
	{
		name = "DialogueUI",
		get = function()
			return require(script.Parent.DialogueUI)
		end,
	},
	{
		name = "WorldUI",
		get = function()
			return require(script.Parent.WorldUI)
		end,
	},
	{
		name = "StoreUI",
		get = function()
			return require(script.Parent.StoreUI)
		end,
	},
	{
		name = "HoverTagUI",
		get = function()
			return require(script.Parent.HoverTagUI)
		end,
	},
	{
		name = "StoreStandState", -- greys a store stand while its item is locked for you
		get = function()
			return require(script.Parent.StoreStandState)
		end,
	},
	{
		name = "FieldGuideUI",
		get = function()
			return require(script.Parent.FieldGuideUI)
		end,
	},
	{
		name = "BadgeUI",
		get = function()
			return require(script.Parent.BadgeUI)
		end,
	},
	{
		name = "BlueprintPlacer",
		get = function()
			return require(script.Parent.BlueprintPlacer)
		end,
	},
	{
		name = "BuilderTools",
		get = function()
			return require(script.Parent.BuilderTools)
		end,
	},
	{
		name = "WireTool",
		get = function()
			return require(script.Parent.WireTool)
		end,
	},
	{
		name = "HammerController",
		get = function()
			return require(script.Parent.HammerController)
		end,
	},
	{
		name = "PlotPickerUI",
		get = function()
			return require(script.Parent.PlotPickerUI)
		end,
	},
	{
		name = "PlotUI",
		get = function()
			return require(script.Parent.PlotUI)
		end,
	},
	{
		name = "SaveSlotUI",
		get = function()
			return require(script.Parent.SaveSlotUI)
		end,
	},
	{
		name = "SawmillController", -- the v2 loop only
		get = function()
			return require(script.Parent.SawmillController)
		end,
	},
	{
		name = "ForestUI",
		get = function()
			return require(script.Parent.ForestUI)
		end,
	},
	{
		name = "WeatherController",
		get = function()
			return require(script.Parent.WeatherController)
		end,
	},
	{
		name = "AmbientLife",
		get = function()
			return require(script.Parent.AmbientLife)
		end,
	},
	{
		name = "LifeFX",
		get = function()
			return require(script.Parent.LifeFX)
		end,
	},
	{
		name = "RegionFX",
		get = function()
			return require(script.Parent.RegionFX)
		end,
	},
	{
		name = "ForestFiller",
		get = function()
			return require(script.Parent.ForestFiller)
		end,
	},
	{
		name = "WindSway",
		get = function()
			return require(script.Parent.WindSway)
		end,
	},
	{
		name = "TreeCosmetics",
		get = function()
			return require(script.Parent.TreeCosmetics)
		end,
	},
	{
		name = "CanopyFade",
		get = function()
			return require(script.Parent.CanopyFade)
		end,
	},
	{
		name = "AmbientSound",
		get = function()
			return require(script.Parent.AmbientSound)
		end,
	},
	{
		name = "NPCController",
		get = function()
			return require(script.Parent.NPCController)
		end,
	},
	{
		name = "PromptUI",
		get = function()
			return require(script.Parent.PromptUI)
		end,
	},
	{
		name = "QualityPickerUI", -- the join screen: Lower or Higher quality, once per account
		get = function()
			return require(script.Parent.QualityPickerUI)
		end,
	},
	{
		name = "NewsUI",
		get = function()
			return require(script.Parent.NewsUI)
		end,
	},
	{
		name = "SettingsUI",
		get = function()
			return require(script.Parent.SettingsUI)
		end,
	},
	{
		name = "SprintController",
		get = function()
			return require(script.Parent.SprintController)
		end,
	},
	{
		name = "IdlePing", -- tells the server the player is at the controls (the idle kick)
		get = function()
			return require(script.Parent.IdlePing)
		end,
	},
	{
		name = "AdminUI",
		get = function()
			return require(script.Parent.AdminUI)
		end,
	},
	{
		name = "QuickMenuUI", -- the gamepad's menu of every HUD button
		get = function()
			return require(script.Parent.QuickMenuUI)
		end,
	},
	{
		name = "TownFX",
		get = function()
			return require(script.Parent.TownFX)
		end,
	},
	{
		name = "TownMarkers",
		get = function()
			return require(script.Parent.TownMarkers)
		end,
	},
}

local startedCount = 0 -- controllers whose Start has returned (or that had nothing to start)
local totalStarts = 0

local function start(name: string, module: Controller?)
	if module == nil then
		startedCount += 1
		return -- it failed to load (warned above)
	end
	local startedAt = os.clock()
	local ok, err = xpcall(function(): any
		module.Start()
		return nil
	end, debug.traceback)
	if not ok then
		warn(string.format("[Client] %s failed to start:\n%s", name, tostring(err)))
	end
	local took = os.clock() - startedAt
	startedCount += 1
	if took >= 0.1 then
		print(string.format("[Load] client %s Start took %.2fs", name, took))
	end
end

-- Every module loads before anything starts, in this order, as it always
-- has (only now one that fails is skipped instead of stopping the rest).
local loaded: { { name: string, module: Controller? } } = {}
local clientStart = os.clock()
for _, c in ipairs(controllers) do
	table.insert(loaded, { name = c.name, module = load(c.name, c.get) })
end

print(string.format("[Load] client: %d modules required in %.2fs", #loaded, os.clock() - clientStart))

-- First, and waited for (it starts UITheme), so toasts and side buttons
-- work for everything after it.
start("HUD", HUD)
-- HUD.Start returns once the HUD and its loading card are drawn (the wait for
-- the server's Remotes runs in its own thread), so everything below starts at
-- once; it used to wait here for the whole world build (34.8 s, 7 October).
print(
	string.format(
		"[Load] client: HUD drawn %.2fs after the client started; the controllers start now",
		os.clock() - clientStart
	)
)

-- The critical controllers start now, all at once; the handshake below waits
-- for these. The deferred ones are queued (ClientBoot) and start after the
-- player can play, one or two a frame.
local criticalStarts = 0
for _, c in ipairs(loaded) do
	local priority = DEFERRED[c.name]
	local module = c.module
	if priority ~= nil and module ~= nil then
		ClientBoot.Default.Register(c.name, {
			priority = priority,
			start = function()
				module.Start()
			end,
		})
	else
		criticalStarts += 1
		task.spawn(start, c.name, c.module)
	end
end
totalStarts = criticalStarts

-- The join handshake. The controllers now start at +0.2 s, long before the
-- server has made its remotes, and each connects its handlers when its Start
-- gets past the wait for them. A one-shot the server fires before a handler
-- is connected is lost (the plot offer, the save slots, the cash). So once
-- every Start has returned (or CLIENT_READY_WAIT seconds, for one that waits
-- on something that never streams in), the client tells the server
-- ClientReady; the server holds the player's release until it hears it and
-- sends its state again (ServerScriptService/JoinSync), and every handler
-- applies state, so hearing it twice is harmless. The fire is repeated every
-- few seconds until the save is in, in case the server had not connected
-- its listener yet.
task.spawn(function()
	local waitStart = os.clock()
	local CLIENT_READY_WAIT = 20
	while startedCount < totalStarts and os.clock() - waitStart < CLIENT_READY_WAIT do
		task.wait(0.1)
	end
	local ok, remote = pcall(function(): RemoteEvent
		return Net.Remote("ClientReady")
	end)
	if not ok then
		warn("[Client] ClientReady remote not found: " .. tostring(remote))
		return
	end
	local localPlayer = Players.LocalPlayer
	local firedAt = os.clock()
	print(
		string.format(
			"[Load] client ready handshake %.2fs after the client started (%d/%d controllers started)",
			firedAt - clientStart,
			startedCount,
			totalStarts
		)
	)
	-- The server connects its listener only once its services have started,
	-- which can be later than the first fire: keep asking for longer than the
	-- server's gate wait (JoinFlow.ClientReadyTries), not for a fixed 18 s.
	for _ = 1, JoinFlow.ClientReadyTries do
		remote:FireServer()
		task.wait(JoinFlow.ClientReadyEvery)
		if localPlayer:GetAttribute("ProfileLoaded") == true then
			return
		end
	end
end)

-- The deferred controllers (DEFERRED above) start once the player can play: the
-- save is in (ProfileLoaded), the loading card has faded, then one or two a
-- frame, soonest-needed first. A save that never loads does not keep them away
-- for good (a timeout). Used before their turn, they start on first use.
task.spawn(function()
	local localPlayer = Players.LocalPlayer
	ClientBoot.ReleaseWhenPlaying(ClientBoot.Default, function(): boolean
		return localPlayer ~= nil and localPlayer:GetAttribute("ProfileLoaded") == true
	end, { settleFrames = RELEASE_SETTLE_FRAMES, timeout = 30 })
end)

-- A server event that a deferred controller listens for, arriving before that
-- controller's Start has connected its own listener, would be lost: a box opened
-- in the first seconds (WorldFX "PlaceBox" starts the placer), Old Hank's or a
-- keeper's line (Dialogue). A light listener here starts the controller on the
-- spot and hands it the event it missed; once started, its own listener has it.
local EARLY_EVENTS: { { remote: string, name: string, handler: string, only: string? } } = {
	{ remote = "WorldFX", name = "BlueprintPlacer", handler = "HandleWorldFx", only = "PlaceBox" },
	{ remote = "Dialogue", name = "DialogueUI", handler = "HandleServer", only = nil },
}
for _, early in ipairs(EARLY_EVENTS) do
	task.spawn(function()
		pcall(function()
			local module: any = nil
			for _, c in ipairs(loaded) do
				if c.name == early.name then
					module = c.module
				end
			end
			if module == nil or module[early.handler] == nil then
				return
			end
			Net.Remote(early.remote).OnClientEvent
				:Connect(ClientBoot.EarlyHandler(ClientBoot.Default, early.name, module, early.handler, early.only))
		end)
	end)
end

-- A tool in the hand (the hammer, a rolled plan) starts the two tool
-- controllers at once if their turn has not come yet: they bind the tool's
-- Activated, and a click on a tool that nothing listens to would do nothing.
pcall(function()
	local localPlayer = Players.LocalPlayer
	local function equipped(child: Instance)
		if child:IsA("Tool") then
			ClientBoot.Ensure("HammerController")
			ClientBoot.Ensure("BlueprintPlacer")
		end
	end
	local function watchCharacter(character: Model)
		for _, child in ipairs(character:GetChildren()) do
			equipped(child)
		end
		character.ChildAdded:Connect(equipped)
	end
	localPlayer.CharacterAdded:Connect(watchCharacter)
	if localPlayer.Character then
		watchCharacter(localPlayer.Character)
	end
end)

-- Mesh swap-ins on this client (a dressing whose mesh landed late) go nearest
-- the camera first, a few a frame (MeshKit.Pump).
pcall(function()
	local MeshKit = require(SharedFolder:WaitForChild("Art"):WaitForChild("MeshKit"))
	MeshKit.Focus = function(): { { x: number, z: number } }
		local camera = workspace.CurrentCamera
		if camera == nil then
			return {}
		end
		local at = camera.CFrame.Position
		return { { x = at.X, z = at.Z } }
	end
end)

-- [Perf] lines (Shared/PerfProbe): can play, fully built, and the worst frame
-- after the character spawned, every 5 s and once at +30 s. Cheap: one
-- Heartbeat function until the 30 s are up, then nothing.
pcall(function()
	local localPlayer = Players.LocalPlayer
	local probe = PerfProbe.new({ log = print })
	local beat: RBXScriptConnection? = nil
	beat = game:GetService("RunService").Heartbeat:Connect(function(dt: number)
		probe.Frame(dt)
		if probe.Done() and beat then
			beat:Disconnect()
			beat = nil
		end
	end)
	if localPlayer.Character then
		probe.MarkSpawn()
	end
	localPlayer.CharacterAdded:Connect(probe.MarkSpawn)
	local function playable()
		if localPlayer:GetAttribute("ProfileLoaded") == true then
			probe.MarkCanPlay()
		end
	end
	playable()
	localPlayer:GetAttributeChangedSignal("ProfileLoaded"):Connect(playable)
	-- Once, 3 s after start, on every device: the numbers the safe-area and
	-- device layouts read, to check against a photo.
	task.delay(3, function()
		local UITheme = require(script.Parent.UITheme)
		local UserInputService = game:GetService("UserInputService")
		local side, bottom = UITheme.Margin()
		local camera = workspace.CurrentCamera
		print(
			string.format(
				"[Safe] tenFoot=%s device=%s gamepad=%s touch=%s keyboard=%s margin=(%d, %d) scale=%.3f viewport=%s",
				tostring(game:GetService("GuiService"):IsTenFootInterface()),
				tostring(UITheme.Device()),
				tostring(UserInputService.GamepadEnabled),
				tostring(UserInputService.TouchEnabled),
				tostring(UserInputService.KeyboardEnabled),
				side,
				bottom,
				UITheme.Scale(),
				tostring(if camera then camera.ViewportSize else "none")
			)
		)
	end)
	-- TEMPORARY grey-box debug (remove once the offender is fixed): 3 s after
	-- can play, list every big painted GuiObject on screen.
	local function greyBoxDump()
		local gui = localPlayer:FindFirstChildOfClass("PlayerGui")
		if gui == nil then
			return
		end
		local found = 0
		for _, d in ipairs(gui:GetDescendants()) do
			if
				d:IsA("GuiObject")
				and d.BackgroundTransparency < 1
				and d.AbsoluteSize.X > 200
				and d.AbsoluteSize.Y > 200
			then
				local shown, node = true, d :: Instance?
				while node ~= nil and node ~= gui do
					if (node:IsA("GuiObject") and not node.Visible) or (node:IsA("ScreenGui") and not node.Enabled) then
						shown = false
					end
					node = node.Parent
				end
				if shown then
					found += 1
					print(
						string.format(
							"[GreyBox] %s  colour=%s  transparency=%.2f  size=%dx%d",
							d:GetFullName(),
							tostring(d.BackgroundColor3),
							d.BackgroundTransparency,
							d.AbsoluteSize.X,
							d.AbsoluteSize.Y
						)
					)
				end
			end
		end
		print(string.format("[GreyBox] %d visible painted GuiObject(s) over 200x200", found))
	end
	local dumped = false
	localPlayer:GetAttributeChangedSignal("ProfileLoaded"):Connect(function()
		if localPlayer:GetAttribute("ProfileLoaded") == true and not dumped then
			dumped = true
			task.delay(3, greyBoxDump)
		end
	end)
	if localPlayer:GetAttribute("ProfileLoaded") == true and not dumped then
		dumped = true
		task.delay(3, greyBoxDump)
	end
	local function built()
		if workspace:GetAttribute("WorldBuilt") == true then
			probe.MarkBuilt()
		end
	end
	built()
	workspace:GetAttributeChangedSignal("WorldBuilt"):Connect(built)
end)

print(string.format("[Load] client controllers started in %.2fs", os.clock() - clientStart))
print("[Client] Timberline Tycoon client started.")
