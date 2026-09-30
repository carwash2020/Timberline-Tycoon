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
	ChopRange = 20, -- studs, horizontal, character to trunk (§14.4)
	AutoTargetRange = 10, -- nothing under the pointer? chop the nearest tree this close

	-- Logs
	PickupPromptRange = 10, -- studs (§14.9)
	RangeTolerance = 3, -- extra studs the server allows over any prompt range
	HandCapacity = 2,
	PickupGraceSec = 10, -- the feller's exclusive pickup window
	LogDespawnSec = 300, -- logs left lying in the world disappear after this

	-- Axes (items: see AxeService)
	AxePickupByOthers = false, -- true lets anyone pick up a dropped axe (a gift); off until trading exists
	MaxDroppedAxes = 10, -- per player, lying in the world at once
	MaxOwnedAxes = 20, -- the shop stops selling past this (keeps hotbars and saves small)

	-- Shops (Tool Shed, later the Dealership)
	ShopPromptRange = 10, -- studs from the counter to open the shop
	ShopRange = 20, -- the shop screen closes past this; the server allows + RangeTolerance

	-- Truck + sawmill
	LoadPromptRange = 8, -- studs from the tailgate
	TruckLoadRange = 16, -- studs from the truck's centre (server check)
	SellTruckRange = 35, -- the truck bed only sells if the truck is this close to the sell zone

	-- Sound asset ids (e.g. "rbxassetid://123"). Pick them from the Creator
	-- Store; empty = silent.
	ChopSoundId = "",
	FellSoundId = "",
}

return GameConfig
