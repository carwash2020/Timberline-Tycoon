--!nocheck
-- Screenshots of the real CraftUI and MiningUI layouts. The panel box,
-- type size and row contents come from those modules. Gotham and Fredoka
-- are not on this machine; the page uses Trebuchet MS as a stand-in.
--
--   lune run tools/preview/ui-shot
-- Writes preview/ui-craft-1280.html, preview/ui-craft-667.html,
-- preview/ui-shop-1280.html and preview/ui-shop-667.html.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

assert(fs.isFile("rokit.toml"), "Run this from the repo root")

local function signal()
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
	}
end
pcall(roblox.implementProperty, "TextButton", "Activated", signal)

local Loader = luau.load(fs.readFile("tools/loader.luau"), { debugName = "tools/loader.luau" })()

local function hex(color)
	return string.format(
		"#%02X%02X%02X",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5)
	)
end

local function esc(text)
	text = tostring(text or "")
	text = string.gsub(text, "&", "&amp;")
	text = string.gsub(text, "<", "&lt;")
	text = string.gsub(text, ">", "&gt;")
	return text
end

local function boot(w, h)
	local phone = math.min(w, h) < 500
	return Loader.new({
		services = {
			GuiService = {
				SelectedObject = nil,
				IsTenFootInterface = function()
					return false
				end,
				GetGuiInset = function()
					return roblox.Vector2.zero, roblox.Vector2.new(0, 36)
				end,
			},
			Players = { LocalPlayer = { Name = "Connor" } },
			UserInputService = {
				TouchEnabled = phone,
				KeyboardEnabled = not phone,
				GetLastInputType = function()
					return if phone then roblox.Enum.UserInputType.Touch else roblox.Enum.UserInputType.Keyboard
				end,
			},
			TextChatService = {},
		},
		globals = {
			workspace = { CurrentCamera = { ViewportSize = roblox.Vector2.new(w, h) } },
		},
	})
end

local function rowHtml(child)
	local name = child:FindFirstChild("Name")
	local cost = child:FindFirstChild("Cost") or child:FindFirstChild("Price")
	local icon = child:FindFirstChild("Icon")
	local button = if child:IsA("TextButton") then child else child:FindFirstChild("Craft")
	local h = child.Size.Y.Offset
	local bg = hex(child.BackgroundColor3)
	local nameSize = if name then name.TextSize else 16
	local nameColor = if name then hex(name.TextColor3) else "#3C2814"
	local costSize = if cost then cost.TextSize else 14
	local costColor = if cost then hex(cost.TextColor3) else "#583A22"
	local iconBg = if icon then hex(icon.BackgroundColor3) else "#583A22"
	local iconText = ""
	if icon then
		local mark = icon:FindFirstChildWhichIsA("TextLabel")
		if mark then
			iconText = mark.Text
		end
	end
	local btn = ""
	if button and button:IsA("TextButton") and button ~= child then
		btn = string.format(
			'<button type="button" style="position:absolute;right:8px;top:10px;width:%dpx;height:%dpx;background:%s;color:%s;font-size:%dpx">%s</button>',
			button.Size.X.Offset,
			button.Size.Y.Offset,
			hex(button.BackgroundColor3),
			hex(button.TextColor3),
			button.TextSize,
			esc(button.Text)
		)
	end
	local iconHtml = ""
	local pad = " shop"
	if icon then
		pad = ""
		iconHtml = string.format('<div class="icon" style="background:%s">%s</div>', iconBg, esc(iconText))
	end
	return string.format(
		'<div class="row" style="height:%dpx;background:%s">%s<div class="copy%s"><div class="name" style="font-size:%dpx;color:%s">%s</div><div class="cost" style="font-size:%dpx;color:%s">%s</div></div>%s</div>',
		h,
		bg,
		iconHtml,
		pad,
		nameSize,
		nameColor,
		esc(if name then name.Text else ""),
		costSize,
		costColor,
		esc(if cost then cost.Text else ""),
		btn
	)
end

local function panelHtml(list, rect, title, paper)
	local layout = list:FindFirstChildOfClass("UIListLayout")
	local gap = if layout then layout.Padding.Offset else 8
	local rows = {}
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextButton") then
			table.insert(rows, rowHtml(child))
		end
	end
	return string.format(
		'<section class="panel" style="left:%dpx;top:%dpx;width:%dpx;height:%dpx;background:%s"><header><h1>%s</h1><button type="button" class="close">Close</button></header><div class="rows" style="gap:%dpx">%s</div></section>',
		rect.x,
		rect.y,
		rect.w,
		rect.h,
		paper,
		esc(title),
		gap,
		table.concat(rows)
	)
end

local function page(w, h, body, phone, cashRight)
	local stick = ""
	local jump = ""
	if phone then
		stick = string.format(
			'<div class="stick" style="left:18px;top:%dpx;width:120px;height:120px"></div>',
			math.floor(h * 0.62)
		)
		jump = string.format(
			'<button type="button" class="jump" style="left:%dpx;top:%dpx">Jump</button>',
			w - 96,
			h - 110
		)
	end
	local cashSize = if phone then 20 else 26
	return string.format(
		[[<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"/>
<title>Timberline panel</title>
<style>
  html, body { margin: 0; }
  .stage { position: relative; overflow: hidden; font-family: "Trebuchet MS", "Segoe UI", sans-serif; }
  .yard { position: absolute; inset: 0; background: linear-gradient(#8eaf72, #6d8d58 55%%, #8a7048 55%%, #6e5838); }
  .cash { position: absolute; top: 16px; right: %dpx; background: #F0E1C3; color: #3C2814; border: 3px solid #583A22; border-radius: 12px; padding: 6px 16px; font-family: "Trebuchet MS", sans-serif; font-weight: 700; font-size: %dpx; }
  .panel { position: absolute; border-radius: 12px; box-sizing: border-box; padding: 8px; display: flex; flex-direction: column; box-shadow: 0 8px 18px rgba(0,0,0,.28); }
  header { display: flex; align-items: center; height: 44px; }
  h1 { margin: 0; flex: 1; font-size: 18px; color: #3C2814; font-weight: 700; }
  .close { width: 64px; height: 44px; border: 0; border-radius: 8px; background: #583A22; color: #F5EBD7; font-weight: 700; font-size: 14px; }
  .rows { margin-top: 4px; display: flex; flex-direction: column; overflow: auto; min-height: 0; flex: 1; }
  .row { position: relative; border-radius: 8px; flex: 0 0 auto; }
  .icon { position: absolute; left: 8px; top: 12px; width: 40px; height: 40px; border-radius: 8px; color: #F5EBD7; display: flex; align-items: center; justify-content: center; font-weight: 700; font-size: 16px; }
  .copy { position: absolute; left: 56px; right: 60px; top: 8px; }
  .copy.shop { left: 10px; right: 12px; top: 4px; }
  .name { font-weight: 700; line-height: 22px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .cost { line-height: 18px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .row button { border: 0; border-radius: 8px; font-weight: 700; }
  .hotbar { position: absolute; left: 50%%; bottom: 10px; transform: translateX(-50%%); display: flex; gap: 6px; }
  .slot { width: 52px; height: 52px; border-radius: 8px; background: rgba(20,16,12,.55); border: 2px solid rgba(245,235,215,.75); }
  .stick { position: absolute; border-radius: 999px; background: rgba(255,255,255,.35); border: 3px solid rgba(255,255,255,.7); }
  .chip { position: absolute; box-sizing: border-box; border-radius: 10px; display: flex; align-items: center; padding: 0 12px; font-weight: 700; font-size: 14px; white-space: nowrap; overflow: hidden; }
  .jump { position: absolute; width: 74px; height: 74px; border-radius: 16px; border: 0; background: #f4f4f4; color: #222; font-weight: 700; font-size: 16px; }
</style></head>
<body><div class="stage" style="width:%dpx;height:%dpx"><div class="yard"></div><div class="cash">$20,000</div>%s<div class="hotbar"><div class="slot"></div><div class="slot"></div><div class="slot"></div><div class="slot"></div><div class="slot"></div><div class="slot"></div></div>%s%s</div></body></html>
]],
		cashRight or 16,
		cashSize,
		w,
		h,
		body,
		stick,
		jump
	)
end

local shots = {
	{ file = "preview/ui-craft-1280.html", w = 1280, h = 720, kind = "craft" },
	{ file = "preview/ui-craft-667.html", w = 667, h = 375, kind = "craft" },
	{ file = "preview/ui-shop-1280.html", w = 1280, h = 720, kind = "shop" },
	{ file = "preview/ui-shop-667.html", w = 667, h = 375, kind = "shop" },
}

for _, shot in ipairs(shots) do
	local loader = boot(shot.w, shot.h)
	local MiningUI = loader:load("StarterPlayer/StarterPlayerScripts/MiningUI")
	local CraftUI = loader:load("StarterPlayer/StarterPlayerScripts/CraftUI")
	local Util = loader:load("ReplicatedStorage/Shared/Util")
	local phone = math.min(shot.w, shot.h) < 500
	local cashRight = 16
	local body
	if shot.kind == "craft" then
		local rect = CraftUI.Rects(shot.w, shot.h)
		local gui = CraftUI.Ensure(roblox.Vector2.new(shot.w, shot.h))
		CraftUI.SetReady(true)
		CraftUI.Fill({
			ingots = { Copper = 1, Iron = 2, Silver = 0 },
			chunks = { Coal = 1 },
		}, false)
		local list = gui:FindFirstChild("Rows", true)
		local panel = gui:FindFirstChild("Bench")
		body = panelHtml(list, rect, "Craft", hex(panel.BackgroundColor3))
	else
		local rects = MiningUI.Rects(shot.w, shot.h)
		local gui = MiningUI.Ensure(roblox.Vector2.new(shot.w, shot.h))
		MiningUI.SetChip(MiningUI.ChipLine("Iron Pick", 3, 2, true, false))
		MiningUI.FillShop(20000, { RustyPick = true })
		cashRight = shot.w - rects.chip.x + 12
		local list = gui:FindFirstChild("Rows", true)
		local panel = gui:FindFirstChild("Shop")
		body = panelHtml(list, rects.panel, "Prospector", hex(panel.BackgroundColor3))
		local chip = gui:FindFirstChild("Chip")
		local chipText = chip and chip:FindFirstChild("ChipText")
		body ..= string.format(
			'<div class="chip" style="left:%dpx;top:%dpx;width:%dpx;height:%dpx;background:%s;color:%s">%s</div>',
			rects.chip.x,
			rects.chip.y,
			rects.chip.w,
			rects.chip.h,
			hex(chip.BackgroundColor3),
			if chipText then hex(chipText.TextColor3) else "#F5EBD7",
			esc(if chipText then chipText.Text else "Rusty Pick")
		)
	end
	if Util.formatCash(20000) ~= "$20,000" then
		error("plaque text drifted from Util.formatCash")
	end
	fs.writeFile(shot.file, page(shot.w, shot.h, body, phone, cashRight))
	print(shot.file)
end
