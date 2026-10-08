--!nocheck
-- Sparkworks pieces, a wired demo board, and the settings panel, as parts.
-- Prices stay off the models. The panel is a physical stand-in for
-- LogicPanelUI so the preview can show the layout.

local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local PlotData = ctx.shared("PlotData")
		local Models = ctx.shared("BlueprintModels")
		local LogicItems = ctx.shared("LogicItems")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 160, C3.fromRGB(116, 164, 84), V3.new(20, -0.5, 24))

		local function put(id, x, z, rot)
			local model = Models.Build(PlotData.Blueprint(id), false)
			model.Parent = root
			Models.Place(model, CF.identity, x, z, rot or 0, 0)
			return model
		end

		local function sign(text, cf, size)
			local board = Kit.part(
				root,
				"Sign",
				size or V3.new(3.2, 1.1, 0.15),
				cf,
				C3.fromHex("#F4ECD8"),
				Enum.Material.SmoothPlastic
			)
			Kit.signText(board, text, C3.fromHex("#3C2814"), { Enum.NormalId.Front, Enum.NormalId.Back })
			return board
		end

		local function beam(name, a, b)
			local part = Kit.part(
				root,
				name,
				V3.new(0.14, 0.14, math.max((b - a).Magnitude, 0.2)),
				CF.lookAt((a + b) / 2, b),
				C3.fromHex("#FFC872"),
				Enum.Material.Neon
			)
			part.CanCollide = false
			return part
		end

		-- Every piece, names only.
		for i, bp in ipairs(LogicItems) do
			local x = (i - 1) * 7
			put(bp.id, x, 0, 0)
			sign(bp.displayName, CF.new(x, 0.7, 4.2), V3.new(4.4, 1.2, 0.12))
		end

		-- Demo board: lever into an AND, a clock into a lamp, a plate into a hatch.
		local board = Kit.part(
			root,
			"DemoBoard",
			V3.new(28, 8, 0.6),
			CF.new(18, 4.2, -16),
			C3.fromHex("#3B3634"),
			Enum.Material.Metal
		)
		Kit.signText(board, "SPARKWORKS", C3.fromHex("#F2E7CF"), { Enum.NormalId.Front })
		local lever = put("Lever", 8, -12, 0)
		local gate = put("GateAnd", 14, -12, 0)
		local clock = put("Clock", 22, -12, 0)
		local lamp = put("SparkLamp", 28, -12, 0)
		put("PressurePlate", 8, -8, 0)
		local hatch = put("Hatch", 16, -8, 0)

		local function top(model, y)
			return model:GetPivot().Position + V3.new(0, y, 0)
		end
		beam("DemoWireAnd", top(lever, 2.4), top(gate, 1.2))
		beam("DemoWireLamp", top(clock, 1.6), top(lamp, 4))
		beam("DemoWireHatch", V3.new(8, 0.6, -8), V3.new(16, 0.5, -8))

		-- Lever on, AND glowing, lamp lit, hatch open: one moment of the demo.
		local handle = lever:FindFirstChild("Part3")
		local leverRoot = lever:FindFirstChild("Root")
		if handle and leverRoot then
			handle.CFrame = leverRoot.CFrame * CF.new(0, 2.3, 0.25) * CF.Angles(0, 0, -0.7)
		end
		local pip = gate:FindFirstChild("Part4")
		if pip then
			pip.Material = Enum.Material.Neon
			pip.Color = C3.fromHex("#FFC872")
		end
		local bulb = lamp:FindFirstChild("Part2")
		if bulb then
			bulb.Material = Enum.Material.Neon
			bulb.Color = C3.fromHex("#FFE9A8")
		end
		local leaf = hatch:FindFirstChild("Part2")
		if leaf then
			local half = leaf.Size.Z / 2
			leaf.CFrame = leaf.CFrame * CF.new(0, 0, half) * CF.Angles(-1.25, 0, 0) * CF.new(0, 0, -half)
		end

		-- Settings panel, the same layout as LogicPanelUI: title, value, minus, plus, Done.
		local card = Kit.part(
			root,
			"SettingsCard",
			V3.new(8, 5.2, 0.25),
			CF.new(48, 3.2, 0),
			C3.fromHex("#F0E1C3"),
			Enum.Material.SmoothPlastic
		)
		sign("Delay", CF.new(48, 4.7, 0.2), V3.new(6, 0.9, 0.08))
		sign("2.0 s", CF.new(48, 3.5, 0.2), V3.new(4, 0.9, 0.08))
		local minus = Kit.part(
			root,
			"Minus",
			V3.new(2.2, 1.1, 0.16),
			CF.new(45.6, 2.3, 0.2),
			C3.fromHex("#E2CFAA"),
			Enum.Material.SmoothPlastic
		)
		Kit.signText(minus, "-", C3.fromHex("#3C2814"), { Enum.NormalId.Front })
		local plus = Kit.part(
			root,
			"Plus",
			V3.new(2.2, 1.1, 0.16),
			CF.new(50.4, 2.3, 0.2),
			C3.fromHex("#FFB840"),
			Enum.Material.SmoothPlastic
		)
		Kit.signText(plus, "+", C3.fromHex("#3C2814"), { Enum.NormalId.Front })
		local done = Kit.part(
			root,
			"Done",
			V3.new(6.4, 0.9, 0.16),
			CF.new(48, 1.2, 0.2),
			C3.fromHex("#4C8C40"),
			Enum.Material.SmoothPlastic
		)
		Kit.signText(done, "DONE", C3.fromHex("#F5EBD7"), { Enum.NormalId.Front })
		card.CanCollide = false

		return {
			root = root,
			cameras = {
				{ pos = { 42, 10, 16 }, target = { 42, 2, 0 }, label = "pieces" },
				{ pos = { 18, 8, 2 }, target = { 18, 2, -12 }, label = "wires" },
				{ pos = { 18, 7, -4 }, target = { 18, 3, -14 }, label = "demo" },
				{ pos = { 48, 3.4, 8 }, target = { 48, 3.2, 0 }, label = "panel" },
			},
		}
	end,
}
