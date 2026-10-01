--!strict
-- FieldGuideUI: the Field Guide (pages in Shared/FieldGuide), opened from a
-- FIELD GUIDE button on the left once Murph has handed it over (the end of
-- the tutorial). Drawn by ShopUI, in two pages:
--   * Woods: every wood, found ones with their facts, the rest as
--     silhouettes with a hint where to look.
--   * The Hidden Grain (GAME_DESIGN §16): every figure, its bark clue, what
--     its logs sell for and how many you've revealed at the sawmill.
-- The first row of each page switches to the other. The header's counts
-- ("3 of 9 woods found") stay current while the guide is open: ShopUI only
-- draws a header when a screen opens, so a change reopens the page.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FieldGuide = require(ReplicatedStorage.Shared.FieldGuide)
local ForestLogic = require(ReplicatedStorage.Shared.ForestLogic)
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local ForestArt = require(ReplicatedStorage.Shared.Art.ForestArt)
local HUD = require(script.Parent.HUD)
local ShopUI = require(script.Parent.ShopUI)
local UITheme = require(script.Parent.UITheme)

local FieldGuideUI = {}

local player = Players.LocalPlayer

local SILHOUETTE = Color3.fromRGB(70, 60, 52)
local PAGE_ROW = "_page" -- the row that switches pages
local INTRO_ROW = "_intro"

type Page = "woods" | "grain"

local page: Page = "woods"
local current: ShopUI.Shop? = nil -- the guide screen last opened
local seenOpen = false -- set when ShopUI redraws `current` (so it's the open screen)

local function found(): { [string]: boolean }
	return ShopLogic.DecodeSet((player:GetAttribute("FieldGuide") :: string?) or "")
end

local function revealed(): { [string]: number }
	local counts = ShopLogic.DecodeOwned((player:GetAttribute("FieldGuideFigures") :: string?) or "")
	return counts
end

local open: (Page) -> ()

local function woodsPage(): ShopUI.Shop
	local shop: ShopUI.Shop
	shop = {
		building = nil,
		promptText = "",
		title = "Field Guide",
		subtitle = FieldGuide.WoodsSubtitle(found()),
		ids = function()
			local ids = { PAGE_ROW }
			for _, wood in ipairs(WoodData.All()) do
				table.insert(ids, wood.id)
			end
			return ids
		end,
		view = function(id: string): ShopUI.RowView
			if current == shop then
				seenOpen = true
			end
			if id == PAGE_ROW then
				local n, total = FieldGuide.FigureCount(revealed())
				return {
					name = "The Hidden Grain",
					own = string.format("· %d of %d revealed", n, total),
					detail = "Some trees hide figured wood that sells for far more. Learn to read the bark.",
					color = ForestArt.HeartseedColor,
					ring = UITheme.Colors.Amber,
					dim = false,
					button = "Open",
					state = "use",
					onClick = function()
						open("grain")
					end,
				}
			end
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
	return shop
end

local function grainPage(): ShopUI.Shop
	local shop: ShopUI.Shop
	shop = {
		building = nil,
		promptText = "",
		title = "The Hidden Grain",
		subtitle = FieldGuide.GrainSubtitle(revealed()),
		ids = function()
			local ids = { PAGE_ROW, INTRO_ROW }
			for _, f in ipairs(FieldGuide.Figures()) do
				table.insert(ids, f.id)
			end
			return ids
		end,
		view = function(id: string): ShopUI.RowView
			if current == shop then
				seenOpen = true
			end
			if id == PAGE_ROW then
				local n, total = FieldGuide.Count(found())
				return {
					name = "Woods",
					own = string.format("· %d of %d found", n, total),
					detail = "Back to the wood pages.",
					color = UITheme.Colors.Green,
					dim = false,
					button = "Back",
					state = "use",
					onClick = function()
						open("woods")
					end,
				}
			elseif id == INTRO_ROW then
				return {
					name = "Reading the bark",
					detail = FieldGuide.GrainIntro(),
					color = UITheme.Colors.Bark,
					dim = false,
					button = "Got it",
					state = "full",
					onClick = function()
						HUD.Toast("Sell figured logs at the sawmill to see what was hiding inside.")
					end,
				}
			end
			local f = ForestLogic.Figure(id)
			if not f then
				return {
					name = "???",
					detail = "",
					color = SILHOUETTE,
					dim = true,
					button = "?",
					state = "locked",
					onClick = function() end,
				}
			end
			local n = revealed()[id] or 0
			return {
				name = string.format("%s %s", f.displayName, ForestLogic.MultiplierText(f.multiplier)),
				detail = FieldGuide.FigureFacts(f, n),
				color = f.color,
				ring = if f.source then UITheme.Colors.Amber else nil,
				dim = n == 0,
				button = if n > 0 then string.format("%d found", n) else "Not yet",
				state = if n > 0 then "full" else "locked",
				onClick = function()
					HUD.Toast(string.format("%s: look for %s.", f.displayName, f.clue))
				end,
			}
		end,
	}
	return shop
end

open = function(which: Page)
	page = which
	local shop = if which == "grain" then grainPage() else woodsPage()
	current = shop
	ShopUI.OpenCustom(shop)
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
		open(page)
	end)
	gui.Parent = player:WaitForChild("PlayerGui")

	local function refresh()
		b.root.Visible = player:GetAttribute("HasFieldGuide") == true
		local shop = current
		if not shop then
			return
		end
		-- Redraws the open screen's rows; if that touched our page, it's open,
		-- and a header that changed needs the page opened again.
		seenOpen = false
		ShopUI.Refresh()
		if seenOpen then
			local fresh = if page == "grain" then grainPage() else woodsPage()
			if fresh.subtitle ~= shop.subtitle then
				current = fresh
				ShopUI.OpenCustom(fresh)
			end
		end
	end
	player:GetAttributeChangedSignal("HasFieldGuide"):Connect(refresh)
	player:GetAttributeChangedSignal("FieldGuide"):Connect(refresh)
	player:GetAttributeChangedSignal("FieldGuideFigures"):Connect(refresh)
	refresh()
end

return FieldGuideUI
