--!strict
-- GameConfig: gameplay tuning shared by server and client, so the two sides
-- can never disagree about a range or a cooldown. Wood and item balance
-- still lives in WoodData / ItemCatalog.

local GameConfig = {
	-- Economy
	CashCap = 2_000_000, -- most cash a wallet holds; hardcore players can grind, not run away
	-- Chopping
	SwingCooldown = 0.8, -- seconds between chops (GAME_DESIGN §14.8)
	SwingTolerance = 0.15, -- server accepts a swing this early, to absorb network jitter
	ChopRange = 12, -- studs, horizontal, character to the bark (trunk radius added per tree, §14.4)
	AutoTargetRange = 6, -- nothing under the pointer? chop the nearest tree this close to its bark

	-- Logs
	PickupPromptRange = 10, -- studs (§14.9)
	RangeTolerance = 3, -- extra studs the server allows over any prompt range
	HandCapacity = 2,
	PickupGraceSec = 10, -- the feller's exclusive pickup window
	LogDespawnSec = 300, -- logs left lying in the world disappear after this
	LeftLoadGraceSec = 600, -- a truck load left behind (Truck to lot, rejoin) stays yours this long
	LeftLoadDespawnSec = 1200, -- and lies there this long, so there's time to drive back for it

	-- Axes (items: see AxeService)
	AxePickupByOthers = false, -- true lets anyone pick up a dropped axe (a gift); off until trading exists
	MaxDroppedAxes = 10, -- per player, lying in the world at once
	MaxOwnedAxes = 20, -- the shop stops selling past this (keeps hotbars and saves small)

	-- World (biome areas and rules are in BiomeData)
	DayCycleMinutes = 20, -- one full day and night, real minutes; the same on every server
	NightStartsAt = 19, -- in-game hour (ClockTime) the night starts
	NightEndsAt = 5, -- ... and ends; the Phantom Grove only exists in between
	LavaDamagePerSecond = 5, -- on the Volcano without Heat Boots (100 health = 20 s)

	-- HUD
	-- Roblox's own player list opens top right on computers, right over the
	-- cash. Off until our own leaderboard (GAME_DESIGN §8 phase 7).
	ShowRobloxPlayerList = false,
	-- World prompts ("Browse axes", "Pick up", ...) in the game's own wood
	-- look (UI spec 05, PromptUI). false = Roblox's default prompts.
	CustomPrompts = true,

	-- Shops (Tool Shed, Dealership)
	ShopPromptRange = 10, -- studs from the counter to open the shop
	ShopRange = 20, -- the shop screen closes past this; the server allows + RangeTolerance

	-- Truck + sawmill
	LoadPromptRange = 8, -- studs from the tailgate (the server allows + RangeTolerance)
	SellTruckRange = 35, -- the truck bed only sells if the truck is this close to the sell zone

	-- Driving (each truck's top speed and turn rate are in ItemCatalog)
	VehiclePhysics = true, -- false = Phase 1 arcade driving (glides through trees and walls)
	VehicleAccel = 14, -- studs/s², throttle held
	VehicleBrake = 40, -- studs/s², throttle against the direction of travel
	VehicleCoast = 8, -- studs/s², no throttle
	ReverseFactor = 0.5, -- reverse top speed, as a share of forward
	TruckRecallCooldown = 10, -- seconds between "Truck to lot" presses

	-- Sound asset ids (e.g. "rbxassetid://123"). Pick them from the Creator
	-- Store; empty = silent.
	ChopSoundId = "",
	FellSoundId = "",
}

return GameConfig
