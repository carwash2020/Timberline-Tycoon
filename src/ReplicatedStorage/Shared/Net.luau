--!strict
-- Net: one place that knows the remote names. The server creates them at
-- startup (GameServer); the client waits for them here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

Net.RemoteNames = {
	"ChopTree", -- client -> server: (treeUid)
	"PickupLog", -- client -> server: (logUid)
	"LoadToTruck", -- client -> server: ()
	"SellLogs", -- client -> server: ()
	"DropAxe", -- client -> server: (axeUid)
	"BuyItem", -- client -> server: (category, itemId); the result comes back as a Notify toast
	"SkipTutorial", -- client -> server: ()
	"EquipItem", -- client -> server: (category, itemId) switch to something you own (a truck)
	"AdminRun", -- client -> server: (request) the owner menu; the server refuses anyone but the owner (AdminService)
	"Sprint", -- client -> server: (on) hold to run; the server sets the speed (SprintLogic)
	"CallTruck", -- client -> server: () send your truck back to your parking slot
	"BuyRobuxItem", -- client -> server: ("Pass" | "Product", key) the server shows Roblox's prompt
	"UseInstantDelivery", -- client -> server: () sell the truck bed from anywhere (a Robux product)
	"MineNode", -- client -> server: (nodeUid) one swing at a crystal node
	"PlaceBlueprint", -- client -> server: (blueprintId, x, z, rot) build on your plot (plot-local studs)
	"MoveBlueprint", -- client -> server: (uid, x, z, rot) move a placed item on your plot
	"UseBlueprint", -- client -> server: (uid) use the rolled plan in your hand: it is consumed and the building joins your blueprint book
	"DropBlueprint", -- client -> server: (uid) lay an unused plan on the ground
	"BlueprintEdit", -- client -> server: (request) rotate, move, resize, copy, delete, or undo an unfilled kit ghost
	"SellPlaced", -- client -> server: (uid) sell a placed item back (PlotData.SellBack)
	"UpgradePlot", -- client -> server: () grow your plot to the next base tier
	"PlotOffer", -- server -> client: (offer) the open homesteads and the price, for the Land Office (or a returning owner's join) picker
	"ClaimPlot", -- client -> server: (index) buy that homestead; the server checks the Land Office range, the pad and the price, then charges
	"PlotPass", -- client -> server: () close the picker (a returning owner is given a free pad; a buyer gets nothing)
	"SaveSetting", -- client -> server: (key, value) remember a Settings choice (SettingsLogic)
	"ResetTutorial", -- client -> server: () start the tutorial over (QuestService)
	"TutorialSeen", -- client -> server: ("build" | "land") the player opened the hammer's blueprint list or the Land panel (QuestService)
	"Grab", -- client -> server: (part, hitPos) take hold of a loose piece of wood (v2 loop: GrabService)
	"Release", -- client -> server: (part) let go of it
	"Chop", -- client -> server: (part, hitPos, normal) one swing at a section, standing or loose (v2 loop: SectionTrees)
	"Swing", -- client -> server: (woodId | "node" | "v1", cancel?) the pose. Damage stays on Chop / ChopTree / MineNode
	"SawmillSet", -- client -> server: (uid, "x" | "y", 1 | -1) nudge a placed mill's cut (v2 loop: SawmillService)
	"Dialogue", -- client -> server: ("open", npcId) or ("pick", nodeId, i). The reply is server -> client.
	"BoxOpen", -- client -> server: (box) open a box you own
	"SpawnPadPress", -- client -> server: (pad) the button on a vehicle pad
	"ChopSawSet", -- client -> server: (uid, "x" | "y", 1 | -1) one step of a chop saw's cut
	"ExpandLand", -- client -> server: (x, z) buy the square that touches yours
	"VisitPlot", -- client -> server: (ownerUserId) go to that player's plot, if their visit flag allows it
	"SetPermission", -- client -> server: (userId, flag, on)
	"Wire", -- client -> server: (fromUid, port, toUid, port) or ("cut", uid)
	"TollPay", -- client -> server: () pay the toll
	"FerryBoard", -- client -> server: () board the ferry
	"BadgeSync", -- server -> client: badges already awarded. The client never fires it.
	"CashChanged", -- server -> client: (cash)
	"Notify", -- server -> client: (message) short on-screen toast
	"WorldFX", -- server -> client: (kind, payload) one-off effects: seed pops, figure reveals, lightning...
	"SlotAction", -- client -> server: ("load" | "reset", index, confirm)
	"SlotState", -- server -> client: (summary) the three slots
	"BoardRequest", -- client -> server: () ask for the leaderboard; the server answers from its cache (LeaderboardService)
	"BoardData", -- server -> client: (payload) the top rows and your own (LeaderboardLogic.ParsePayload)
	"PaintTruck", -- client -> server: (truckId, color) Paint Shop; the server clamps it
}

local folder: Folder? = nil

function Net.Remote(name: string): RemoteEvent
	if folder == nil then
		folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
	return (folder :: Folder):WaitForChild(name) :: RemoteEvent
end

return Net
