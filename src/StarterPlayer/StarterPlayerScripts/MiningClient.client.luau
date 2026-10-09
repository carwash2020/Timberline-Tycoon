--!strict
-- MiningClient: wires the mining chip and the craft bench. The ore label
-- is HoverTagUI (one tag for the whole game). A missing remote shows
-- "Coming soon" instead of erroring. The chip shows only while a pick or
-- bomb is equipped, or while the server says you are in a mine.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CraftUI = require(script.Parent.CraftUI)
local MiningUI = require(script.Parent.MiningUI)

local player = Players.LocalPlayer

local function hasRemote(name: string): boolean
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = folder and folder:FindFirstChild(name)
	return remote ~= nil and remote:IsA("RemoteEvent")
end

local function syncChip()
	local name = player:GetAttribute("MiningPick")
	local level = player:GetAttribute("PickLevel")
	local bombs = player:GetAttribute("MiningBombs")
	MiningUI.SetChip(
		MiningUI.ChipLine(
			if type(name) == "string" then name else "Rusty Pick",
			if type(level) == "number" then level else 1,
			if type(bombs) == "number" then bombs else 0,
			player:GetAttribute("MiningLamp") == true,
			player:GetAttribute("MiningHardhat") == true
		)
	)
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local held = false
	if tool then
		held = tool:GetAttribute("PickId") ~= nil or tool:GetAttribute("Bomb") ~= nil
	end
	MiningUI.SetChipVisible(held or player:GetAttribute("InMine") == true)
end

local function watchCharacter(character: Model)
	character.ChildAdded:Connect(syncChip)
	character.ChildRemoved:Connect(syncChip)
	syncChip()
end

MiningUI.Start({ ready = hasRemote("MineAction") })
CraftUI.Start({ ready = hasRemote("CraftAction") })
syncChip()

for _, attr in ipairs({ "PickLevel", "MiningBombs", "MiningLamp", "MiningHardhat", "MiningPick", "InMine" }) do
	player:GetAttributeChangedSignal(attr):Connect(syncChip)
end

if player.Character then
	watchCharacter(player.Character)
end
player.CharacterAdded:Connect(watchCharacter)

player:GetAttributeChangedSignal("MiningShop"):Connect(function()
	if player:GetAttribute("MiningShop") == nil then
		return
	end
	MiningUI.SetReady(hasRemote("MineAction"))
	local cash = player:GetAttribute("Cash")
	MiningUI.FillShop(if type(cash) == "number" then cash else 0, MiningUI.OwnedMap(player:GetAttribute("MiningOwned")))
	MiningUI.Open()
end)

player:GetAttributeChangedSignal("OpenCraft"):Connect(function()
	if player:GetAttribute("OpenCraft") == nil then
		return
	end
	CraftUI.SetReady(hasRemote("CraftAction"))
	local stock, logOk = CraftUI.CountWorld(player.UserId)
	CraftUI.Fill(stock, logOk)
	CraftUI.Open()
end)
