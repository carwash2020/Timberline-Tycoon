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
	"CallTruck", -- client -> server: () send your truck back to your parking slot
	"BuyRobuxItem", -- client -> server: ("Pass" | "Product", key) the server shows Roblox's prompt
	"UseInstantDelivery", -- client -> server: () sell the truck bed from anywhere (a Robux product)
	"MineNode", -- client -> server: (nodeUid) one swing at a crystal node
	"CashChanged", -- server -> client: (cash)
	"Notify", -- server -> client: (message) short on-screen toast
}

local folder: Folder? = nil

function Net.Remote(name: string): RemoteEvent
	if folder == nil then
		folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
	return (folder :: Folder):WaitForChild(name) :: RemoteEvent
end

return Net
