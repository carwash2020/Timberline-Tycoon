--!nocheck
-- Writes preview/t420-hammer/layout.json: the numbers the blueprint picker is laid
-- out with, from the real modules (BuildMenuLogic, HammerPicker), and the real card
-- text (name, blurb, cost) for the first cards of each tab. tools/preview/picker_layout.py
-- draws the diagrams from it. Run from the repo root:  lune run tools/preview/picker_layout
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local Loader = luau.load(fs.readFile("tools/loader.luau"), { debugName = "tools/loader.luau" })()
local m = Loader.new()
local BuildMenuLogic = m:shared("BuildMenuLogic")
local HammerPicker = m:shared("HammerPicker")
local BlueprintBook = m:shared("BlueprintBook")
local PlotData = m:shared("PlotData")

local ids = {}
for _, bp in ipairs(PlotData.Blueprints) do
	table.insert(ids, bp.id)
end
local entries = BlueprintBook.Entries(ids, {}, true)
local ctx = { tier = 5, cash = 100000, boxed = false }
local tabs = {}
for _, tab in ipairs(HammerPicker.TabList(entries)) do
	local cards = {}
	for i, e in ipairs(tab.entries) do
		if i <= 6 then
			local c = HammerPicker.Card(e, ctx)
			table.insert(
				cards,
				{ name = c.name, blurb = c.blurb, cost = c.costText, size = c.sizeText, state = c.state }
			)
		end
	end
	table.insert(tabs, { label = tab.label, count = #tab.entries, cards = cards })
end

local sizes = {}
for _, s in ipairs({
	{ label = "667x375 phone", w = 667, h = 375, phone = true, scale = 1 },
	{ label = "1920x1080 computer", w = 1920, h = 1080, phone = false, scale = 1.25 },
}) do
	local layout = BuildMenuLogic.Layout(s.w, s.phone, s.scale)
	local grid = HammerPicker.GridFor(layout.panelW, s.phone)
	table.insert(sizes, {
		label = s.label,
		w = s.w,
		h = s.h,
		scale = s.scale,
		phone = s.phone,
		panelW = layout.panelW,
		rail = layout.sizes.rail,
		before = { cols = layout.cols, tileW = layout.tileW, tileH = layout.sizes.tileH },
		after = {
			cols = grid.cols,
			tileW = grid.tileW,
			tileH = HammerPicker.CardSizes(s.phone).h,
			card = HammerPicker.CardSizes(s.phone),
		},
	})
end
fs.writeDir("preview/t420-hammer")
fs.writeFile("preview/t420-hammer/layout.json", serde.encode("json", { sizes = sizes, tabs = tabs }, true))
print("wrote preview/t420-hammer/layout.json")
