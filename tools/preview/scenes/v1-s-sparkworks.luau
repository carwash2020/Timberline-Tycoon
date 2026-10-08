--!nocheck
-- Sparkworks pieces in close groups, and one wired example, lit and unlit.
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
		Common.ground(ctx, root, 280, C3.fromRGB(116, 164, 84), V3.new(60, -0.5, -20))

		local function put(id, x, z, rot)
			local model = Models.Build(PlotData.Blueprint(id), false)
			model.Parent = root
			Models.Place(model, CF.identity, x, z, rot or 0, 0)
			return model
		end

		-- A small board lying on the grass. Text is on the top face, so the
		-- plaque stays at the piece's feet and does not stand in the shot.
		local function plaque(text, x, z, wide)
			-- Turned so the name reads upright from the 3/4 camera (it sits at +X,+Z).
			local board = Kit.part(
				root,
				"Plaque",
				V3.new(wide or 3.2, 0.06, 1.15),
				CF.new(x, 0.04, z) * CF.Angles(0, math.pi, 0),
				C3.fromHex("#F4ECD8"),
				Enum.Material.SmoothPlastic
			)
			Kit.signText(board, text, C3.fromHex("#3C2814"), { Enum.NormalId.Top })
			return board
		end

		local function beam(name, a, b, lit)
			local part = Kit.part(
				root,
				name,
				V3.new(0.16, 0.16, math.max((b - a).Magnitude, 0.2)),
				CF.lookAt((a + b) / 2, b),
				C3.fromHex(if lit then "#FFC872" else "#6E6254"),
				if lit then Enum.Material.Neon else Enum.Material.Metal
			)
			part.CanCollide = false
			return part
		end

		-- At most four pieces, two by two, far enough apart that one camera
		-- does not see the next group's plaques.
		local spots = { { 0, 0 }, { 9, 0 }, { 0, 9 }, { 9, 9 } }
		local cameras = {}
		local per = 4
		local groups = math.ceil(#LogicItems / per)
		for g = 1, groups do
			local originX = (g - 1) * 50
			local count = math.min(per, #LogicItems - (g - 1) * per)
			local sx, sz = 0, 0
			for i = 1, count do
				local bp = LogicItems[(g - 1) * per + i]
				local spot = spots[i]
				local x = originX + spot[1]
				local z = spot[2]
				put(bp.id, x, z, 0)
				local front = bp.footprint.Y / 2 + 0.85
				plaque(bp.displayName, x, z + front, if #bp.displayName > 10 then 4.2 else 3.2)
				sx += x
				sz += z
			end
			local cx = sx / count
			local cz = sz / count
			-- 3/4, about 12 studs from the middle of the group.
			local ox, oy, oz = 6.6, 6.2, 7.4
			table.insert(cameras, {
				pos = { cx + ox, oy, cz + oz },
				target = { cx, 2.4, cz },
				fov = 46,
				label = "pieces-" .. g,
			})
		end

		-- Lever and button on the left, AND in the middle, lamp on the right.
		-- One straight run each. The same circuit, off and on, side by side.
		local function circuit(ox, oz, lit)
			local lever = put("Lever", ox, oz + 2.8, 0)
			local button = put("Button", ox, oz - 2.8, 0)
			local gate = put("GateAnd", ox + 8, oz, 1)
			local lamp = put("SparkLamp", ox + 14.5, oz, 0)
			local function at(part)
				return part.CFrame.Position
			end
			local inputs = { gate:FindFirstChild("Part2"), gate:FindFirstChild("Part3") }
			local leverIn, buttonIn = inputs[1], inputs[2]
			if buttonIn and leverIn and at(buttonIn).Z > at(leverIn).Z then
				leverIn, buttonIn = buttonIn, leverIn
			end
			local out = gate:FindFirstChild("Part4")
			local leverAt = lever:GetPivot().Position
			local buttonAt = button:GetPivot().Position
			local gateAt = gate:GetPivot().Position
			local lampAt = lamp:GetPivot().Position
			-- Two parallel runs along X, then a short stub into each input,
			-- then one straight run from the gate to the lamp. They do not cross.
			local stop = gateAt.X - 1.15
			beam("LeverRun" .. ox, V3.new(leverAt.X + 0.7, 1.7, leverAt.Z), V3.new(stop, 1.7, leverAt.Z), lit)
			if leverIn then
				beam("LeverIn" .. ox, V3.new(stop, 1.7, leverAt.Z), at(leverIn), lit)
			end
			beam("ButtonRun" .. ox, V3.new(buttonAt.X + 0.7, 0.85, buttonAt.Z), V3.new(stop, 0.85, buttonAt.Z), lit)
			if buttonIn then
				beam("ButtonIn" .. ox, V3.new(stop, 0.85, buttonAt.Z), at(buttonIn), lit)
			end
			if out then
				local from = at(out)
				beam("LampWire" .. ox, from, V3.new(lampAt.X - 0.45, from.Y, lampAt.Z), lit)
			end
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
			local board = Kit.part(
				root,
				tag,
				V3.new(1.8, 0.55, 0.06),
				CF.new(ox + 8, 5.6, oz),
				C3.fromHex("#F4ECD8"),
				Enum.Material.SmoothPlastic
			)
			Kit.signText(board, tag, C3.fromHex("#3C2814"), { Enum.NormalId.Front, Enum.NormalId.Back })
		end

		circuit(0, -70, false)
		circuit(20, -70, true)
		table.insert(cameras, {
			pos = { 17, 7.5, -52 },
			target = { 17, 2, -70 },
			fov = 58,
			label = "wired",
		})

		return {
			root = root,
			cameras = cameras,
		}
	end,
}
