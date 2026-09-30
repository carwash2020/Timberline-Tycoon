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
