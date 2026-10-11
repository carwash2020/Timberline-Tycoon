--!strict
-- Dealership: the showroom hall's interior (Shared/Art/ShopInterior
-- dispatches here). Built from the older helpers; to apply the new look see
-- ShopInteriors/ToolShed (the pilot) and the recipe in STATUS.md.

local ShopKit = require(script.Parent.Parent.ShopKit)
local Kit = require(script.Parent.Parent.Kit)
local ShowroomLight = require(script.Parent.Parent.Parent.ShowroomLight)

type Frame = ShopKit.Frame
local V3, CF = Vector3.new, CFrame.new
local MAT = Enum.Material
local hex = Kit.hex
local dBox = ShopKit.dBox
local hangSign = ShopKit.hangSign
local plant = ShopKit.plant
local crateStack = ShopKit.crateStack
local trashCan = ShopKit.trashCan
local counterDetail = ShopKit.counterDetail
local backDoor = ShopKit.backDoor
local banner = ShopKit.banner
local TABLE = ShopKit.Table.body
local TABLE_TOP = ShopKit.Table.top
local TIMBER = ShopKit.Table.timber
local IRON = ShopKit.Table.iron
local PAPER = ShopKit.Table.paper
local RUNNER = ShopKit.Table.runner
local RUNNER_EDGE = ShopKit.Table.runnerEdge
local LAYER1 = ShopKit.Layer[1]
local LAYER2 = ShopKit.Layer[2]
local LAYER3 = ShopKit.Layer[3]

local Dealership = {}

-- `bays` are the vehicle bays in hall space (see BuildingArt.dealership):
-- x, z (the plinth's middle), row, zNear / zFar (the plinth's edge facing the
-- central aisle, and its far edge).
export type Bay = { x: number, z: number, row: number, aisleZ: number }

function Dealership.Build(model: Model, frame: Frame, west: number, east: number, zf: number, zb: number, bays: { Bay })
	local rng = Kit.rng(2606)
	local width = east - west
	local cx = (east + west) / 2
	local depth = zb - zf
	local fy = frame.floorTop
	-- Polished marble floor with a slate border, a runner and safety stripes
	-- along the central aisle.
	dBox(
		model,
		"FloorBoards",
		V3(width - 0.4, 0.06, depth - 0.4),
		CF(cx, fy + LAYER1, (zf + zb) / 2),
		hex("#DCD6CB"),
		MAT.Marble
	)
	for _, s in ipairs({ -1, 1 }) do
		dBox(
			model,
			"FloorBorder",
			V3(width - 0.4, 0.06, 1.0),
			CF(cx, fy + LAYER2, (zf + zb) / 2 + s * (depth / 2 - 0.7)),
			hex("#4B5560"),
			MAT.Slate
		)
		dBox(
			model,
			"FloorBorder",
			V3(1.0, 0.06, depth - 2.4),
			CF(cx + s * (width / 2 - 0.7), fy + LAYER2, (zf + zb) / 2),
			hex("#4B5560"),
			MAT.Slate
		)
	end
	local lobbyW = 26
	local lobbyCx = west + 12.6
	-- The central walkway between the rows: a pale lane edged with yellow
	-- stripes, with a few blue bars across it.
	local aisleLo, aisleHi = math.huge, -math.huge
	for _, bay in ipairs(bays) do
		if bay.row == 1 then
			aisleLo = math.min(aisleLo, bay.aisleZ)
		else
			aisleHi = math.max(aisleHi, bay.aisleZ)
		end
	end
	if aisleLo < aisleHi then
		local ax0, ax1 = west + lobbyW, east - 1.5
		local acx = (ax0 + ax1) / 2
		local acz = (aisleLo + aisleHi) / 2
		dBox(
			model,
			"AisleLane",
			V3(ax1 - ax0, 0.06, aisleHi - aisleLo - 1.6),
			CF(acx, fy + LAYER2, acz),
			hex("#C3BDB1"),
			MAT.Marble
		)
		for _, z in ipairs({ aisleLo + 0.5, aisleHi - 0.5 }) do
			dBox(
				model,
				"AisleStripe",
				V3(ax1 - ax0, 0.07, 0.4),
				CF(acx, fy + LAYER3, z),
				hex("#E3B73C"),
				MAT.SmoothPlastic
			)
		end
		local x = ax0 + 6
		while x < ax1 - 4 do
			dBox(
				model,
				"AisleMark",
				V3(0.5, 0.07, aisleHi - aisleLo - 3.2),
				CF(x, fy + LAYER3, acz),
				hex("#7FA3C8"),
				MAT.SmoothPlastic
			)
			x += 14
		end
	end
	-- A runner down the lobby from the door to the counter.
	dBox(model, "AisleRunner", V3(5, 0.06, depth - 8), CF(lobbyCx, fy + LAYER2, (zf + zb) / 2), RUNNER, MAT.Fabric)
	for _, s in ipairs({ -1, 1 }) do
		dBox(
			model,
			"AisleRunnerEdge",
			V3(0.35, 0.07, depth - 8),
			CF(lobbyCx + s * 2.2, fy + LAYER3, (zf + zb) / 2),
			RUNNER_EDGE,
			MAT.Fabric
		)
	end
	local ceil = frame.ceilY
	-- Beams across the hall with strip lights along them.
	for _, z in ipairs({ zf + 20, zf + 36, zf + 52 }) do
		dBox(model, "CeilingBeam", V3(width - 0.6, 0.9, 0.9), CF(cx, ceil - 0.45, z), TIMBER)
		local x = west + 12
		while x < east - 6 do
			local strip =
				dBox(model, "StripLight", V3(9, 0.2, 0.5), CF(x, ceil - 1.1, z), ShowroomLight.StripColor, MAT.Neon)
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 236, 205)
			light.Range = ShowroomLight.StripRange
			light.Brightness = ShowroomLight.StripBrightness
			light.Shadows = false
			light.Parent = strip
			x += 28
		end
	end
	-- Three low display plinths. The strip lights already cover the hall,
	-- so these only add a capped lantern each (not another can and rod).
	for i = 1, math.min(3, #bays) do
		local bay = bays[i]
		local plinth =
			dBox(model, "DisplayPlinth", V3(6, 0.5, 4), CF(bay.x, fy + 0.25, bay.z), hex("#D9D3C7"), MAT.Marble)
		local glow = Instance.new("PointLight")
		glow.Brightness = ShowroomLight.LanternBrightness
		glow.Range = ShowroomLight.LanternRange
		glow.Shadows = false
		glow.Color = Color3.fromRGB(255, 236, 205)
		glow.Parent = plinth
	end
	hangSign(model, lobbyCx, ceil - 3.6, zf + 5, 9, 1.7, ceil - 0.9, "SHOWROOM", hex("#2F6DB5"), PAPER)
	-- Lobby: banners, brochure racks, reception chairs and a low table, plants.
	banner(model, west + 3, ceil - 5, zf + 12, hex("#2F6DB5"), "NEW\nRIGS")
	banner(model, west + 23, ceil - 5, zf + 12, hex("#C8402F"), "SALE")
	banner(model, west + 3, ceil - 5, zf + 30, hex("#E3B73C"), "TRUCKS")
	for i, x in ipairs({ west + 1.5, west + 1.5 }) do
		dBox(model, "BrochureRack", V3(2.4, 4.2, 0.8), CF(x, fy + 2.1, zf + 22 + (i - 1) * 3.5), TABLE, MAT.Wood)
		for r = 1, 3 do
			dBox(
				model,
				"Brochure",
				V3(1.9, 0.9, 0.12),
				CF(x, fy + 0.9 + r * 0.95, zf + 21.55 + (i - 1) * 3.5),
				if (i + r) % 2 == 0 then PAPER else hex("#7FA3C8"),
				MAT.SmoothPlastic
			)
		end
	end
	-- Reception: chairs and a low table by the west wall.
	dBox(model, "ReceptionTable", V3(3.6, 1.2, 2), CF(west + 4, fy + 0.6, zb - 24), TABLE_TOP, MAT.Wood)
	for _, z in ipairs({ zb - 28, zb - 20 }) do
		dBox(model, "ReceptionChair", V3(2, 1.2, 2), CF(west + 4, fy + 0.6, z), hex("#2F6DB5"), MAT.Fabric)
		dBox(model, "ReceptionChairBack", V3(0.4, 1.8, 2), CF(west + 2.6, fy + 1.5, z), hex("#2F6DB5"), MAT.Fabric)
	end
	plant(model, west + 1.8, fy, zf + 3, 1.4)
	plant(model, west + lobbyW - 2, fy, zf + 3, 1.4)
	plant(model, west + lobbyW - 2, fy, zb - 12, 1.4)
	trashCan(model, west + lobbyW - 2, fy, zb - 1.5)
	-- Flags along the front wall, inside the hall.
	for i, x in ipairs({ west + 36, west + 66, west + 96, west + 126 }) do
		dBox(model, "FlagPole", V3(0.2, 5, 0.2), CF(x, fy + 2.5, zf + 0.6), IRON, MAT.Metal)
		dBox(
			model,
			"FlagCloth",
			V3(2.4, 1.5, 0.1),
			CF(x + 1.3, fy + 4.2, zf + 0.6),
			if i % 2 == 0 then hex("#2F6DB5") else hex("#C8402F"),
			MAT.Fabric
		)
	end
	crateStack(model, east - 4, fy, zb - 3, 3, rng)
	counterDetail(model, frame)
	backDoor(model, frame, west + 5.7, zb, true, 0)
end

-- Adds the interior. `frame` is the shop's final-stud frame (see Frame);
-- for the Dealership `extra` is the showroom's inner west x, east x, front

return Dealership
