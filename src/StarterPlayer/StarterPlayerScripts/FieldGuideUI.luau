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
local UITheme = require(script.Parent.UITheme)

local FieldGuideUI = {}

local player = Players.LocalPlayer

local SILHOUETTE = Color3.fromRGB(70, 60, 52)

local function found(): { [string]: boolean }
	return ShopLogic.DecodeSet((player:GetAttribute("FieldGuide") :: string?) or "")
end

local function guide(): ShopUI.Shop
	local n, total = FieldGuide.Count(found())
	return {
		building = nil,
		promptText = "",
		title = "Field Guide",
		subtitle = string.format("%d of %d woods found. Fell one of each to fill in its page.", n, total),
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
				ring = if known and wood.id == "lumenwood" then UITheme.Colors.Ice else nil,
				dim = not known,
				button = if known then "Found" else "?",
				state = if known then "full" else "locked",
				onClick = function()
					HUD.Toast(if known then FieldGuide.Facts(wood) else FieldGuide.Hint(wood))
				end,
			}
		end,
	}
end

function FieldGuideUI.Start()
	local gui = UITheme.Screen("FieldGuideButton")
	local b = UITheme.Button({
		name = "FieldGuide",
		text = "FIELD GUIDE",
		size = Vector2.new(130, 34),
		style = "bark",
		textSize = 14,
	})
	UITheme.LeftColumn(b.root) -- where the tutorial tracker was
	b.root.Visible = false
	b.root.Parent = gui
	b.face.Activated:Connect(function()
		ShopUI.OpenCustom(guide())
	end)
	gui.Parent = player:WaitForChild("PlayerGui")

	local function refresh()
		b.root.Visible = player:GetAttribute("HasFieldGuide") == true
		ShopUI.Refresh()
	end
	player:GetAttributeChangedSignal("HasFieldGuide"):Connect(refresh)
	player:GetAttributeChangedSignal("FieldGuide"):Connect(refresh)
	refresh()
end

return FieldGuideUI
