--!strict
-- FieldGuideUI: the Field Guide (pages in Shared/FieldGuide), opened from a
-- FIELD GUIDE button on the left once Murph has handed it over (the end of
-- the tutorial). Every wood is listed: found ones with their facts, the
-- rest as silhouettes with a hint where to look. Drawn by ShopUI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FieldGuide = require(ReplicatedStorage.Shared.FieldGuide)
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local HUD = require(script.Parent.HUD)
local ShopUI = require(script.Parent.ShopUI)

local FieldGuideUI = {}

local player = Players.LocalPlayer

local SILHOUETTE = Color3.fromRGB(70, 60, 52)
local MUTED = Color3.fromRGB(160, 145, 120)
local GREEN = Color3.fromRGB(76, 140, 64)

local function found(): { [string]: boolean }
	return ShopLogic.DecodeSet((player:GetAttribute("FieldGuide") :: string?) or "")
end

local function guide(): ShopUI.Shop
	local n, total = FieldGuide.Count(found())
	return {
		building = nil,
		promptText = "",
		title = "FIELD GUIDE",
		subtitle = string.format("%d of %d woods found. Fell a tree of each to fill in its page.", n, total),
		ids = function()
			local ids = {}
			for _, wood in ipairs(WoodData.All()) do
				table.insert(ids, wood.id)
			end
			return ids
		end,
		view = function(id: string): ShopUI.RowView
			local wood = WoodData.Get(id) :: WoodData.WoodDef
			local known = found()[id] == true
			return {
				name = if known then wood.displayName else "???",
				detail = if known then FieldGuide.Facts(wood) else FieldGuide.Hint(wood),
				color = if known then wood.leafColor else SILHOUETTE,
				glow = known and wood.id == "lumenwood",
				dim = not known,
				button = if known then "Found" else "?",
				buttonColor = if known then GREEN else MUTED,
				onClick = function()
					HUD.Toast(if known then FieldGuide.Facts(wood) else FieldGuide.Hint(wood))
				end,
			}
		end,
	}
end

function FieldGuideUI.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "FieldGuideButton"
	gui.ResetOnSpawn = false
	local b = Instance.new("TextButton")
	b.Name = "FieldGuide"
	b.Position = UDim2.new(0, 12, 0.3, 0) -- where the tutorial tracker was
	b.Size = UDim2.fromOffset(130, 36)
	b.BackgroundColor3 = Color3.fromRGB(88, 58, 34)
	b.Font = Enum.Font.Fantasy
	b.TextSize = 18
	b.TextColor3 = Color3.fromRGB(245, 235, 215)
	b.Text = "FIELD GUIDE"
	b.Visible = false
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = b
	b.Parent = gui
	b.Activated:Connect(function()
		ShopUI.OpenCustom(guide())
	end)
	gui.Parent = player:WaitForChild("PlayerGui")

	local function refresh()
		b.Visible = player:GetAttribute("HasFieldGuide") == true
		ShopUI.Refresh()
	end
	player:GetAttributeChangedSignal("HasFieldGuide"):Connect(refresh)
	player:GetAttributeChangedSignal("FieldGuide"):Connect(refresh)
	refresh()
end

return FieldGuideUI
