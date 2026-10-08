--!nocheck
-- Sparkworks pieces, and one wired example, lit and unlit.
-- Prices stay off the models. The settings panel is a screen, shot
-- separately (tools/preview/logic-panel.html), not as parts.

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
		Common.ground(ctx, root, 220, C3.fromRGB(116, 164, 84), V3.new(40, -0.5, 10))

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

		local function beam(name, a, b, lit)
			local part = Kit.part(
				root,
				name,
				V3.new(0.22, 0.22, math.max((b - a).Magnitude, 0.2)),
				CF.lookAt((a + b) / 2, b),
				C3.fromHex(if lit then "#FFC872" else "#6E6254"),
				if lit then Enum.Material.Neon else Enum.Material.Metal
			)
			part.CanCollide = false
			return part
		end

		local function wire(name, a, b, lit)
			local mid = (a + b) / 2 + V3.new(0, 2.2, 0.6)
			beam(name .. "A", a, mid, lit)
			beam(name .. "B", mid, b, lit)
		end

		-- Two rows, names above the pieces so a 3/4 view keeps every label.
		local cols = 7
		local gapX = 11
		local gapZ = 20
		local cam = V3.new(80, 24, 70)
		for i, bp in ipairs(LogicItems) do
			local col = (i - 1) % cols
			local row = math.floor((i - 1) / cols)
			local x = col * gapX
			local z = row * gapZ
			put(bp.id, x, z, 0)
			local at = V3.new(x, 8.2, z)
			sign(bp.displayName, CF.lookAt(at, V3.new(cam.X, at.Y, cam.Z)), V3.new(9.2, 1.6, 0.1))
		end

		-- Lever and button into AND into a lamp. The same circuit, off and on.
		local function circuit(ox, lit)
			local lever = put("Lever", ox, -28, 0)
			local button = put("Button", ox, -22, 0)
			local gate = put("GateAnd", ox + 8, -25, 0)
			local lamp = put("SparkLamp", ox + 16, -25, 0)
			local function at(model, dx, dy, dz)
				return model:GetPivot().Position + V3.new(dx, dy, dz)
			end
			wire("W" .. ox .. "L", at(lever, 0, 2.6, 0.3), at(gate, -0.45, 1.3, 0.5), lit)
			wire("W" .. ox .. "B", at(button, 0, 1.3, 0.2), at(gate, 0.45, 1.3, 0.5), lit)
			wire("W" .. ox .. "A", at(gate, 0, 1.4, -0.5), at(lamp, 0, 4.2, 0.4), lit)
			local pip = gate:FindFirstChild("Part4")
			local bulb = lamp:FindFirstChild("Part2")
			if lit then
				local handle = lever:FindFirstChild("Part3")
				local leverRoot = lever:FindFirstChild("Root")
				if handle and leverRoot then
					handle.CFrame = leverRoot.CFrame * CF.new(0, 2.3, 0.25) * CF.Angles(0, 0, -0.7)
				end
				local cap = button:FindFirstChild("Part3")
				if cap then
					cap.CFrame = cap.CFrame * CF.new(0, -0.12, 0)
					cap.Material = Enum.Material.Neon
					cap.Color = C3.fromHex("#FF7A2E")
				end
				if pip then
					pip.Material = Enum.Material.Neon
					pip.Color = C3.fromHex("#FFC872")
				end
				if bulb then
					bulb.Material = Enum.Material.Neon
					bulb.Color = C3.fromHex("#FFE9A8")
				end
			else
				if pip then
					pip.Material = Enum.Material.Metal
					pip.Color = C3.fromHex("#3B3634")
				end
				if bulb then
					bulb.Material = Enum.Material.SmoothPlastic
					bulb.Color = C3.fromHex("#8A8172")
				end
			end
			local tag = if lit then "Lit" else "Unlit"
			local tagAt = V3.new(ox + 8, 8.2, -25)
			sign(tag, CF.lookAt(tagAt, V3.new(ox + 8, tagAt.Y, 20)), V3.new(6, 1.5, 0.1))
		end

		circuit(0, false)
		circuit(28, true)

		return {
			root = root,
			cameras = {
				{
					pos = { 80, 24, 70 },
					target = { 33, 4, 8 },
					fov = 52,
					label = "pieces",
				},
				{
					pos = { 22, 14, 8 },
					target = { 22, 3, -25 },
					fov = 46,
					label = "wired",
				},
			},
		}
	end,
}
