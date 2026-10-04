--!nocheck
-- The preview's night preset (tools/preview/night.luau, WLD-19): a night
-- camera lights the same parts and lights the game's LightingController
-- switches on after dark, in the same colours.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

return function(t)
	local roblox = t.roblox
	local C3, CF = roblox.Color3, roblox.CFrame
	local Night = luau.load(fs.readFile("tools/preview/night.luau"), { debugName = "tools/preview/night.luau" })()
	local loader = t.loader()
	local BuildingArt = loader:load("ReplicatedStorage/Shared/Art/BuildingArt")
	local Kit = loader:load("ReplicatedStorage/Shared/Art/Kit")
	local IsleArt = loader:load("ReplicatedStorage/Shared/Art/IsleArt")
	local controller = fs.readFile("src/StarterPlayer/StarterPlayerScripts/LightingController.luau")

	local function find(model, name)
		for _, d in ipairs(model:GetDescendants()) do
			if d.Name == name then
				return d
			end
		end
		return nil
	end

	local function rgbHex(constant: string): string
		local r, g, b = string.match(controller, "local " .. constant .. " = Color3%.fromRGB%((%d+), (%d+), (%d+)%)")
		assert(r, "LightingController has no " .. constant)
		return C3.fromRGB(tonumber(r), tonumber(g), tonumber(b)):ToHex()
	end

	t.test("glow names and night colours match LightingController", function()
		local list = string.match(controller, "local GLOW_NAMES[^=]*= {([^}]*)}")
		t.ok(list, "LightingController has no GLOW_NAMES table")
		local names = {}
		for name in string.gmatch(list, "(%w+) = true") do
			names[name] = true
		end
		t.eq(Night.GlowNames, names)
		t.eq(Night.WindowColor, rgbHex("WINDOW_NIGHT"))
		t.eq(Night.LanternColor, rgbHex("LANTERN_NIGHT"))
	end)

	t.test("a street lamp's LampGlow keeps its Neon colour and its light comes on", function()
		local lamp = BuildingArt.LampPost()
		local glow = find(lamp, "LampGlow")
		t.ok(glow and glow.Material == roblox.Enum.Material.Neon, "LampPost has a Neon LampGlow")
		-- Kit.lantern builds this glow in the lantern colour itself, so this
		-- line can't tell "keeps its colour" from "takes the lantern colour";
		-- the isle lantern test below can.
		t.eq(Night.GlowColor(glow), glow.Color:ToHex())
		local light = glow:FindFirstChildWhichIsA("PointLight")
		t.ok(light, "LampGlow holds the lamp's light")
		t.ok(Night.IsNightLight(light), "the lamp's light is a night light")
		t.eq(Night.GlowColor(find(lamp, "Post")), nil)
		t.eq(Night.GlowColor(find(lamp, "LanternCap")), nil)
	end)

	t.test("a Neon glow part in its own colour keeps it, not the lantern colour", function()
		-- IsleArt.LanternPost recolours its Kit.lantern glow to #FFE2A0; the
		-- Hearth & Home shop lanterns (#F2C14E) rely on the same rule.
		local post = IsleArt.LanternPost(1)
		local glow = find(post, "LanternGlow")
		t.ok(glow and glow.Material == roblox.Enum.Material.Neon, "LanternPost has a Neon LanternGlow")
		t.eq(glow.Color:ToHex(), "FFE2A0")
		t.ok(glow.Color:ToHex() ~= Night.LanternColor, "the sample glow isn't already the lantern colour")
		t.eq(Night.GlowColor(glow), "FFE2A0")

		local part = roblox.Instance.new("Part")
		part.Name = "LampGlow"
		part.Material = roblox.Enum.Material.Neon
		part.Color = C3.fromRGB(120, 200, 255)
		t.eq(Night.GlowColor(part), part.Color:ToHex())
		t.ok(Night.GlowColor(part) ~= Night.LanternColor, "a blue Neon lamp keeps its blue")
	end)

	t.test("windows glow the warm window colour, lit or not", function()
		local model = roblox.Instance.new("Model")
		local frame = C3.fromRGB(90, 60, 40)
		local dark = Kit.window(model, CF.new(0, 4, 0), 3, 2.5, frame, false)
		local lit = Kit.window(model, CF.new(6, 4, 0), 3, 2.5, frame, true)
		t.eq(dark.Material, roblox.Enum.Material.Glass)
		t.eq(Night.GlowColor(dark), Night.WindowColor)
		t.eq(Night.GlowColor(lit), Night.WindowColor)
		t.eq(Night.GlowColor(find(model, "WindowFrame")), nil)
	end)

	t.test("a glow part that isn't Neon by day takes the lantern colour", function()
		local part = roblox.Instance.new("Part")
		part.Name = "LanternGlow"
		part.Material = roblox.Enum.Material.SmoothPlastic
		part.Color = C3.fromRGB(240, 230, 210)
		t.eq(Night.GlowColor(part), Night.LanternColor)
	end)

	t.test("a Lanternwood NightGlow part takes the wood's night colour", function()
		local WoodData = t.shared("WoodData")
		local part = roblox.Instance.new("Part")
		part.Name = "Leaves"
		part.Material = roblox.Enum.Material.SmoothPlastic
		part.Color = roblox.Color3.fromHex(WoodData.LanternLeaf)
		part:SetAttribute("NightGlow", true)
		t.eq(Night.WoodGlow, string.sub(WoodData.LanternGlow, 2))
		t.eq(Night.GlowColor(part), Night.WoodGlow)
		local plain = roblox.Instance.new("Part")
		plain.Name = "Section"
		plain.Material = roblox.Enum.Material.Wood
		t.eq(Night.GlowColor(plain), nil, "a log section without NightGlow stays dark")
	end)

	t.test("lights in a StreetLamp model count; other lights don't", function()
		local lampModel = roblox.Instance.new("Model")
		lampModel:AddTag("StreetLamp")
		local arm = roblox.Instance.new("Part")
		arm.Name = "Arm"
		arm.Parent = lampModel
		local loose = roblox.Instance.new("PointLight")
		loose.Parent = arm
		t.ok(Night.IsNightLight(loose), "a loose light in a StreetLamp model")

		local fire = roblox.Instance.new("Part")
		fire.Name = "Embers"
		local always = roblox.Instance.new("PointLight")
		always.Parent = fire
		t.ok(not Night.IsNightLight(always), "a campfire's light isn't switched by the clock")
	end)
end
