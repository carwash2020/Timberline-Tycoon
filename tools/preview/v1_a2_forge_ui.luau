--!nocheck
-- The Sky Forge window (ForgeUI) for the A2 previews, from the real module:
-- SkyForgeService.View builds the view from a save (against mocks, like
-- tests/SkyForgeService.spec), ForgeUI.Ensure / Show build the real
-- instance tree for the screen size, and this writes every visible piece
-- (its rect, fill, corner, stroke, shine and text) to preview/forge-ui-*.json.
-- tools/preview/v1_a2_ui.py draws that over the forge court render and the
-- round-3 HUD.
--
--   lune run tools/preview/v1_a2_forge_ui
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

assert(fs.isFile("rokit.toml"), "Run this from the repo root")

local Vector2, Vector3, Enum = roblox.Vector2, roblox.Vector3, roblox.Enum
local function signal()
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
	}
end
for _, name in ipairs({ "Activated", "InputBegan", "InputEnded", "SelectionLost", "MouseEnter", "MouseLeave" }) do
	pcall(roblox.implementProperty, "TextButton", name, signal)
	pcall(roblox.implementProperty, "GuiButton", name, signal)
end

local Loader = luau.load(fs.readFile("tools/loader.luau"), { debugName = "tools/loader.luau" })()
local MON = 1791158400 -- Monday 2026-10-05 00:00 UTC

-- A save partway through the end game: Obsidian Axe at Heavy I, a Steel
-- Axe, the Frost Relic forged, 18 u³ of Gloamwood (phantomwood) planks
-- laid by the anvil.
local function view()
	local profile = {
		cash = 64000,
		materials = { SkyShard = 9 },
		axes = { { uid = "o1", id = "ObsidianAxe" }, { uid = "s1", id = "SteelAxe" }, { uid = "lux", id = "LuxAxe" } },
		temper = { o1 = { prefix = "Heavy", tier = 1 } },
		relics = { FrostRelic = true },
		forgeOrder = { week = -1, delivered = {}, claimed = false },
		forgeWood = { lumenwood = 18 },
	}
	local anvil = { Position = Vector3.new(0, 3, 0), Parent = true }
	function anvil:IsA(class)
		return class == "BasePart"
	end
	function anvil:FindFirstChild(name)
		return name == "SkyForgePoint"
	end
	local root = { Position = Vector3.new(4, 3, 0) }
	function root:IsA(class)
		return class == "BasePart"
	end
	local char = {}
	function char:FindFirstChild(name)
		return if name == "HumanoidRootPart" then root else nil
	end
	local player = { UserId = 7, Name = "Connor", Character = char }
	function player:SetAttribute() end
	local pieces = {
		{ uid = "p1", woodId = "phantomwood", kind = "plank", volume = 18, owner = 7, distance = 4 },
	}
	local loader = Loader.new({
		mocks = {
			ProfileService = {
				GetProfile = function(p)
					return if p == player then profile else nil
				end,
			},
			AxeService = {
				OwnedCounts = function()
					return {}, 0
				end,
			},
			AetherService = { Forge = function() end },
			HandInWood = {
				Near = function()
					return pieces, { p1 = pieces[1] }
				end,
			},
			RateLimiter = {
				Allow = function()
					return true
				end,
			},
			EconomyService = {},
		},
		globals = {
			task = { spawn = function() end },
			workspace = {
				FindFirstChild = function()
					return nil
				end,
			},
		},
		services = {
			CollectionService = {
				GetTagged = function()
					return { anvil }
				end,
				GetInstanceAddedSignal = function()
					return { Connect = function() end }
				end,
			},
			Players = {
				PlayerAdded = { Connect = function() end },
				GetPlayers = function()
					return {}
				end,
			},
		},
	})
	local S = loader:server("SkyForgeService")
	S._reset()
	S.V1Init({ notify = function() end })
	S.Clock = function()
		return MON + 3600
	end
	return assert(S.View(player), "no view")
end

local function boot(w, h, phone)
	return Loader.new({
		mocks = { HUD = { SetModal = function() end } },
		services = {
			GuiService = {
				SelectedObject = nil,
				IsTenFootInterface = function()
					return false
				end,
				GetGuiInset = function()
					return Vector2.zero, Vector2.new(0, 36)
				end,
			},
			Players = { LocalPlayer = { Name = "Connor" } },
			UserInputService = {
				TouchEnabled = phone,
				KeyboardEnabled = not phone,
				GetLastInputType = function()
					return if phone then Enum.UserInputType.Touch else Enum.UserInputType.Keyboard
				end,
			},
			TextChatService = {},
			ContextActionService = {},
		},
		globals = {
			workspace = { CurrentCamera = { ViewportSize = Vector2.new(w, h) } },
		},
	})
end

local function rgb(c)
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end

-- Absolute rects: offsets and scales, and UIListLayout stacking (vertical,
-- by LayoutOrder) for the rows. ScrollingFrames clip their children.
local function dump(gui)
	local out = {}
	local function walk(inst, px, py, pw, ph, clip, z)
		local items = {}
		for _, child in ipairs(inst:GetChildren()) do
			if child:IsA("GuiObject") and child.Visible then
				table.insert(items, child)
			end
		end
		local layout = inst:FindFirstChildOfClass("UIListLayout")
		local pad = inst:FindFirstChildOfClass("UIPadding")
		local pl = if pad then pad.PaddingLeft.Offset else 0
		local pt = if pad then pad.PaddingTop.Offset else 0
		local pr = if pad then pad.PaddingRight.Offset else 0
		local pb = if pad then pad.PaddingBottom.Offset else 0
		local cx, cy, cw, ch = px + pl, py + pt, pw - pl - pr, ph - pt - pb
		if layout then
			table.sort(items, function(a, b)
				if a.LayoutOrder ~= b.LayoutOrder then
					return a.LayoutOrder < b.LayoutOrder
				end
				return a.Name < b.Name
			end)
		end
		local stack = 0
		for _, child in ipairs(items) do
			local s, p = child.Size, child.Position
			local w = s.X.Scale * cw + s.X.Offset
			local h = s.Y.Scale * ch + s.Y.Offset
			local x, y
			if layout then
				x, y = cx, cy + stack
				stack += h + layout.Padding.Offset
			else
				x = cx + p.X.Scale * cw + p.X.Offset
				y = cy + p.Y.Scale * ch + p.Y.Offset
			end
			local node = {
				name = child.Name,
				class = child.ClassName,
				x = x,
				y = y,
				w = w,
				h = h,
				clip = clip,
				z = z,
				bg = rgb(child.BackgroundColor3),
				bgT = child.BackgroundTransparency,
			}
			local corner = child:FindFirstChildOfClass("UICorner")
			if corner then
				node.corner = corner.CornerRadius.Offset + corner.CornerRadius.Scale * math.min(w, h)
			end
			local stroke = child:FindFirstChildOfClass("UIStroke")
			if stroke and stroke.Enabled then
				node.stroke = { color = rgb(stroke.Color), thickness = stroke.Thickness }
			end
			local shine = child:FindFirstChildOfClass("UIGradient")
			if shine then
				node.shine = true
			end
			if child:IsA("TextLabel") or child:IsA("TextButton") then
				local tp = child:FindFirstChildOfClass("UIPadding")
				local fit = child:FindFirstChildOfClass("UITextSizeConstraint")
				node.text = child.Text
				node.color = rgb(child.TextColor3)
				node.size = child.TextSize
				node.font = child.Font.Name
				node.xalign = child.TextXAlignment.Name
				node.yalign = child.TextYAlignment.Name
				node.wrapped = child.TextWrapped
				node.scaled = child.TextScaled
				node.truncate = child.TextTruncate.Name
				node.maxSize = if fit then fit.MaxTextSize else nil
				node.minSize = if fit then fit.MinTextSize else nil
				node.pad = if tp
					then { tp.PaddingLeft.Offset, tp.PaddingTop.Offset, tp.PaddingRight.Offset, tp.PaddingBottom.Offset }
					else nil
			end
			table.insert(out, node)
			local childClip = clip
			if child:IsA("ScrollingFrame") then
				childClip = { x, y, x + w, y + h }
			end
			walk(child, x, y, w, h, childClip, z + 1)
		end
	end
	walk(gui, 0, 0, 0, 0, nil, 0)
	return out
end

local shots = {
	{ name = "phone-temper", w = 667, h = 375, phone = true, tab = "Temper" },
	{ name = "phone-confirm", w = 667, h = 375, phone = true, tab = "Temper", pick = { uid = "o1", prefix = "Keen" } },
	{ name = "phone-starfall", w = 667, h = 375, phone = true, tab = "Starfall" },
	{ name = "pc-temper", w = 1280, h = 720, phone = false, tab = "Temper" },
	{ name = "pc-confirm", w = 1280, h = 720, phone = false, tab = "Temper", pick = { uid = "o1", prefix = "Keen" } },
	{ name = "pc-relics", w = 1280, h = 720, phone = false, tab = "Relics" },
	{ name = "pc-order", w = 1280, h = 720, phone = false, tab = "Order" },
}

local v = view()
for _, shot in ipairs(shots) do
	local loader = boot(shot.w, shot.h, shot.phone)
	local ForgeUI = loader:load("StarterPlayer/StarterPlayerScripts/ForgeUI")
	local gui = ForgeUI.Ensure(Vector2.new(shot.w, shot.h), shot.phone)
	ForgeUI.Show(v, shot.tab, shot.pick)
	local file = string.format("preview/forge-ui-%s.json", shot.name)
	fs.writeFile(
		file,
		serde.encode("json", {
			w = shot.w,
			h = shot.h,
			phone = shot.phone,
			rect = ForgeUI.Rects(shot.w, shot.h, shot.phone),
			nodes = dump(gui),
		})
	)
	print(file)
end
