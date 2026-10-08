--!nocheck
-- Sparkworks pieces in close groups, and one wired example, lit and unlit.
-- Each camera frames only its own group. The settings panel is a screen,
-- shot separately (tools/preview/logic-panel.html).

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
		-- One grass pad big enough that every camera hits grass, not sky.
		-- The shadow map has to cover that pad or the outer shots go flat.
		Common.ground(ctx, root, 1600, C3.fromRGB(116, 164, 84), V3.new(0, -0.5, 120))

		-- 3/4: 30 degrees off the front, 30 degrees up. Renders are 1400x900.
		local AZ = math.rad(30)
		local EL = math.rad(30)
		local FOV = 42
		local ASPECT = 1400 / 900

		local function put(id, x, z, rot)
			local model = Models.Build(PlotData.Blueprint(id), false)
			model.Parent = root
			Models.Place(model, CF.identity, x, z, rot or 0, 0)
			return model
		end

		-- Flat on the grass, in front of the piece. Yaw matches the camera
		-- so the top-face text reads upright (tops of the letters point away).
		local function plaque(text, x, z, wide)
			local board = Kit.part(
				root,
				"Plaque",
				V3.new(wide or 3.2, 0.06, 1.15),
				CF.new(x, 0.04, z) * CF.Angles(0, AZ, 0),
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
				V3.new(0.14, 0.14, math.max((b - a).Magnitude, 0.2)),
				CF.lookAt((a + b) / 2, b),
				C3.fromHex(if lit then "#FFC872" else "#6E6254"),
				if lit then Enum.Material.Neon else Enum.Material.Metal
			)
			part.CanCollide = false
			return part
		end

		-- Right angles only. Each segment is along one axis.
		local function run(name, points, lit, owned)
			for i = 1, #points - 1 do
				table.insert(owned, beam(name .. i, points[i], points[i + 1], lit))
			end
		end

		local function eachCorner(list, fn)
			local function one(part)
				if part.Transparency >= 1 then
					return
				end
				local cf = part.CFrame
				local h = part.Size * 0.5
				for _, sx in ipairs({ -1, 1 }) do
					for _, sy in ipairs({ -1, 1 }) do
						for _, sz in ipairs({ -1, 1 }) do
							fn(
								cf.Position
									+ cf.RightVector * (h.X * sx)
									+ cf.UpVector * (h.Y * sy)
									- cf.LookVector * (h.Z * sz)
							)
						end
					end
				end
			end
			for _, inst in ipairs(list) do
				if inst:IsA("BasePart") then
					one(inst)
				end
				for _, d in ipairs(inst:GetDescendants()) do
					if d:IsA("BasePart") then
						one(d)
					end
				end
			end
		end

		-- Distance so the group is about 70% of the width, and fully in frame.
		-- Fit the real part corners. An axis-aligned box would include empty
		-- air (a tall lamp's height at another piece's corner) and back the
		-- camera up.
		local function frame(list, fill)
			local minV = V3.new(math.huge, math.huge, math.huge)
			local maxV = V3.new(-math.huge, -math.huge, -math.huge)
			eachCorner(list, function(p)
				minV = V3.new(math.min(minV.X, p.X), math.min(minV.Y, p.Y), math.min(minV.Z, p.Z))
				maxV = V3.new(math.max(maxV.X, p.X), math.max(maxV.Y, p.Y), math.max(maxV.Z, p.Z))
			end)
			local center = (minV + maxV) / 2
			local back = V3.new(math.sin(AZ) * math.cos(EL), math.sin(EL), math.cos(AZ) * math.cos(EL))
			local forward = -back
			local right = forward:Cross(V3.new(0, 1, 0)).Unit
			local up = right:Cross(forward).Unit
			local halfW, halfH = 0, 0
			eachCorner(list, function(p)
				local d = p - center
				halfW = math.max(halfW, math.abs(d:Dot(right)))
				halfH = math.max(halfH, math.abs(d:Dot(up)))
			end)
			halfW *= 1.06
			halfH *= 1.06
			local hfov = 2 * math.atan(math.tan(math.rad(FOV) / 2) * ASPECT)
			local distW = halfW / math.tan(fill * hfov / 2)
			local distH = halfH / math.tan(math.rad(FOV) * 0.42)
			local dist = math.max(distW, distH)
			return {
				pos = { center.X + back.X * dist, center.Y + back.Y * dist, center.Z + back.Z * dist },
				target = { center.X, center.Y, center.Z },
				fov = FOV,
			}
		end

		local cameras = {}
		local spots = { { 0, 0 }, { 9, 0 }, { 0, 9 }, { 9, 9 } }
		local per = 4
		local groups = math.ceil(#LogicItems / per)
		for g = 1, groups do
			-- Far enough apart that this camera cannot see another group,
			-- and still inside the grass pad.
			local originX = (g - 1) * 260 - 390
			local count = math.min(per, #LogicItems - (g - 1) * per)
			local owned = {}
			for i = 1, count do
				local bp = LogicItems[(g - 1) * per + i]
				local spot = spots[i]
				local x = originX + spot[1]
				local z = spot[2]
				table.insert(owned, put(bp.id, x, z, 0))
				local front = bp.footprint.Y / 2 + 0.9
				table.insert(owned, plaque(bp.displayName, x, z + front, if #bp.displayName > 10 then 4.2 else 3.2))
			end
			local cam = frame(owned, 0.74)
			cam.label = "pieces-" .. g
			table.insert(cameras, cam)
		end

		-- Lever and button on the left, AND in the middle, lamp on the right.
		-- Wires stay on their own lanes: along X, then along Z, never across.
		local function circuit(ox, oz, lit)
			local owned = {}
			local lever = put("Lever", ox, oz + 3.2, 0)
			local button = put("Button", ox, oz - 3.2, 0)
			local gate = put("GateAnd", ox + 8, oz, 1)
			local lamp = put("SparkLamp", ox + 15, oz, 0)
			table.insert(owned, lever)
			table.insert(owned, button)
			table.insert(owned, gate)
			table.insert(owned, lamp)
			local y = 1.15
			local bus = ox + 5.4
			local leverZ = oz + 3.2
			local buttonZ = oz - 3.2
			run("L" .. ox, {
				V3.new(ox + 0.9, y, leverZ),
				V3.new(bus, y, leverZ),
				V3.new(bus, y, oz + 0.7),
			}, lit, owned)
			run("B" .. ox, {
				V3.new(ox + 0.9, y + 0.35, buttonZ),
				V3.new(bus, y + 0.35, buttonZ),
				V3.new(bus, y + 0.35, oz - 0.7),
			}, lit, owned)
			run("A" .. ox, {
				V3.new(ox + 8.9, y, oz),
				V3.new(ox + 14.2, y, oz),
			}, lit, owned)
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
				if pip and pip:IsA("BasePart") then
					pip.Material = Enum.Material.Neon
					pip.Color = C3.fromHex("#FFC872")
				end
				if bulb and bulb:IsA("BasePart") then
					bulb.Material = Enum.Material.Neon
					bulb.Color = C3.fromHex("#FFE9A8")
				end
			else
				if pip and pip:IsA("BasePart") then
					pip.Material = Enum.Material.Metal
					pip.Color = C3.fromHex("#3B3634")
				end
				if bulb and bulb:IsA("BasePart") then
					bulb.Material = Enum.Material.SmoothPlastic
					bulb.Color = C3.fromHex("#8A8172")
				end
			end
			local tag = if lit then "Lit" else "Unlit"
			local board = Kit.part(
				root,
				tag,
				V3.new(1.7, 0.5, 0.06),
				CF.new(ox + 8, 4.4, oz),
				C3.fromHex("#F4ECD8"),
				Enum.Material.SmoothPlastic
			)
			Kit.signText(board, tag, C3.fromHex("#3C2814"), { Enum.NormalId.Front, Enum.NormalId.Back })
			table.insert(owned, board)
			return owned
		end

		-- Behind every piece camera, so none of those shots can see it.
		local wired = {}
		for _, part in ipairs(circuit(-20, 420, false)) do
			table.insert(wired, part)
		end
		for _, part in ipairs(circuit(8, 420, true)) do
			table.insert(wired, part)
		end
		local wiredCam = frame(wired, 0.74)
		wiredCam.label = "wired"
		table.insert(cameras, wiredCam)

		return {
			root = root,
			cameras = cameras,
			shadowRadius = 700,
		}
	end,
}
