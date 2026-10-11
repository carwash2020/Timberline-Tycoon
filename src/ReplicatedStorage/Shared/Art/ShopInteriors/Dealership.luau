--!strict
-- Dealership: the showroom hall's interior (Shared/Art/ShopInterior
-- dispatches here), in the new store look (ShopKit; the recipe is in
-- STATUS.md, "Store interiors", and ShopInteriors/ToolShed is the pilot).
--
-- The hall is 154 x 61 studs with the lobby (door, counter, keeper) at the
-- west end and the two rows of bays east of it; the vehicles, their plinths,
-- name signs and tier stands are DealershipLot's (MapBuilder stands them in
-- the hall). This module is everything else: the warm plank floor with a blue
-- runner down the central aisle and the lobby, timber beams, warm lanterns
-- under ShopKit's caps, a big header sign over each run of one kind of vehicle
-- (TRUCKS, TRAILERS), a small sub-sign over each bay (what the vehicle
-- hauls), the lobby's SHOWROOM board, the CHECKOUT sign over the counter, and
-- the lobby furnishings. The vehicles' own stock, order, prices and bays are
-- untouched.

local ShopKit = require(script.Parent.Parent.ShopKit)
local Kit = require(script.Parent.Parent.Kit)
local DealershipLot = require(script.Parent.Parent.DealershipLot)
local ItemCatalog = require(script.Parent.Parent.Parent.ItemCatalog)

type Frame = ShopKit.Frame
local V3, CF = Vector3.new, CFrame.new
local MAT = Enum.Material
local hex = Kit.hex
local dBox = ShopKit.dBox
local plant = ShopKit.plant
local trashCan = ShopKit.trashCan
local counterDetail = ShopKit.counterDetail
local backDoor = ShopKit.backDoor
local plankFloor = ShopKit.plankFloor
local floorBorder = ShopKit.floorBorder
local TABLE = ShopKit.Table.body
local TABLE_TOP = ShopKit.Table.top
local TIMBER = ShopKit.Table.timber
local IRON = ShopKit.Table.iron
local PAPER = ShopKit.Table.paper
local RUNNER_EDGE = ShopKit.Table.runnerEdge
local LAYER2 = ShopKit.Layer[2]
local LAYER3 = ShopKit.Layer[3]

local BLUE = hex("#2F6DB5") -- the Dealership's accent (its sign, its paint)
local BLUE_DEEP = hex("#285A96") -- the runner
local BRASS_STRIPE = hex("#E3B73C")

local Dealership = {}

-- `bays` are the vehicle bays in hall space (see BuildingArt.dealership):
-- x, z (the plinth's middle), row, zNear / zFar (the plinth's edge facing the
-- central aisle, and its far edge).
export type Bay = { x: number, z: number, row: number, aisleZ: number }

-- The signs hang this far under the ceiling line (frame.ceilY - 0.9 is the
-- underside of the beams).
Dealership.HeaderY = 11.3 -- a header's middle
Dealership.SubY = 8.6 -- a sub-sign's middle (over the tallest box, 7.3)
Dealership.HeaderWidth = 9.2
Dealership.SubWidth = 8.4
Dealership.HeaderYaw = math.rad(90) -- a header faces the door end (west), so it reads from the lobby and down the aisle
Dealership.SubYaw = math.rad(14) -- a sub-sign is turned a little to the aisle
Dealership.TopY = 15.1 -- the highest part the interior adds (the beams' tops)

---------------------------------------------------------------------------
-- What the signs say, from the vehicle stock (DealershipLot.Layout: the same
-- bays, in the same order, so the signs follow the stock)
---------------------------------------------------------------------------

export type Run = {
	row: number,
	kind: string, -- "Truck" or "Trailer"
	header: string, -- "TRUCKS", "TRAILERS"
	ids: { string }, -- the vehicles under it, in bay order
	first: number, -- index of the first bay in the layout
	last: number,
}

-- A run is neighbouring bays of one row that sell one kind of vehicle. The bays
-- are ordered by price (front row then back row), so a kind can come back.
function Dealership.Runs(): { Run }
	local runs: { Run } = {}
	for i, bay in ipairs(DealershipLot.Layout().bays) do
		local last = runs[#runs]
		if last and last.row == bay.row and last.kind == bay.kind then
			table.insert(last.ids, bay.id)
			last.last = i
		else
			table.insert(runs, {
				row = bay.row,
				kind = bay.kind,
				header = if bay.kind == "Truck" then "TRUCKS" else "TRAILERS",
				ids = { bay.id },
				first = i,
				last = i,
			})
		end
	end
	return runs
end

-- The sub-sign over a bay: what the vehicle hauls (ShopLogic's own words for
-- the shop card: "Bed: 12 logs", "No bed", "+12 bed space").
function Dealership.SubText(kind: string, id: string): string
	if kind == "Truck" then
		local truck = ItemCatalog.GetTruck(id)
		if truck and truck.bedCapacity > 0 then
			return string.format("BED: %d LOGS", truck.bedCapacity)
		end
		return "NO BED"
	end
	local trailer = ItemCatalog.GetTrailer(id)
	return if trailer then string.format("+%d BED SPACE", trailer.extraCapacity) else "TRAILER"
end

---------------------------------------------------------------------------
-- Signs turned about the vertical axis (ShopKit's boards face -Z)
---------------------------------------------------------------------------

-- Builds a kit sign at the origin and turns it `yaw` about its own middle, then
-- stands it at (x, z): every part of it (board, frame, accent bar, chains) is
-- moved together, so the text stays on its faces.
local function yawed(parent: Instance, x: number, z: number, yaw: number, build: (Model) -> ())
	local tmp = Instance.new("Model")
	build(tmp)
	local base = CF(x, 0, z) * CFrame.Angles(0, yaw, 0)
	for _, d in ipairs(tmp:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CFrame = base * d.CFrame
		end
	end
	for _, child in ipairs(tmp:GetChildren()) do
		child.Parent = parent
	end
	tmp:Destroy()
end

-- A stock crate or barrel in the lobby corner: the real mesh (Crate, Barrel),
-- with a part-built stand-in that is dropped when the mesh has loaded
-- (ShopKit.MeshProp: fallback first, swap later, never a yielding load).
local function stockProp(model: Model, asset: string, x: number, y: number, z: number, yaw: number)
	local fallback = Instance.new("Model")
	fallback.Name = asset .. "Fallback"
	local at = CF(x, y, z) * CFrame.Angles(0, yaw, 0)
	if asset == "Crate" then
		dBox(fallback, "Crate", V3(2, 2.4, 2), at * CF(0, 1.2, 0), TABLE_TOP)
		dBox(fallback, "CrateBand", V3(2.06, 0.2, 2.06), at * CF(0, 1.2, 0), TIMBER)
	else
		dBox(fallback, "Barrel", V3(1.6, 2.2, 1.6), at * CF(0, 1.1, 0), TABLE)
		dBox(fallback, "BarrelHoop", V3(1.7, 0.16, 1.7), at * CF(0, 1.1, 0), IRON)
	end
	fallback.Parent = model
	ShopKit.MeshProp(model, asset, at, fallback)
end

function Dealership.Build(model: Model, frame: Frame, west: number, east: number, zf: number, zb: number, bays: { Bay })
	local rng = Kit.rng(2606)
	local cx = (east + west) / 2
	local depth = zb - zf
	local fy = frame.floorTop
	local ceil = frame.ceilY
	local lobbyW = 26
	local lobbyCx = west + 12.6
	local midZ = (zf + zb) / 2

	-- Floor: warm boards (a base and a few long boards in other tones, as the
	-- Tool Shed has), a dark border.
	plankFloor(model, frame, hex("#D8BC8E"), { hex("#C9AA7A"), hex("#E2C9A0"), hex("#BE9E70") }, 3.4, rng)
	floorBorder(model, frame, 0.8, TIMBER, MAT.Wood)

	-- The central walkway between the rows: a blue runner with brass-cream edges
	-- and the two yellow safety lines along the plinths' aisle edges.
	local aisleLo, aisleHi = math.huge, -math.huge
	for _, bay in ipairs(bays) do
		if bay.row == 1 then
			aisleLo = math.min(aisleLo, bay.aisleZ)
		else
			aisleHi = math.max(aisleHi, bay.aisleZ)
		end
	end
	local ax0, ax1 = west + lobbyW, east - 1.5
	local acx = (ax0 + ax1) / 2
	if aisleLo < aisleHi then
		local acz = (aisleLo + aisleHi) / 2
		dBox(model, "AisleRunner", V3(ax1 - ax0, 0.06, 5), CF(acx, fy + LAYER2, acz), BLUE_DEEP, MAT.Fabric)
		for _, s in ipairs({ -1, 1 }) do
			dBox(
				model,
				"AisleRunnerEdge",
				V3(ax1 - ax0, 0.07, 0.35),
				CF(acx, fy + LAYER3, acz + s * 2.2),
				RUNNER_EDGE,
				MAT.Fabric
			)
		end
		for _, z in ipairs({ aisleLo + 0.5, aisleHi - 0.5 }) do
			dBox(
				model,
				"AisleStripe",
				V3(ax1 - ax0, 0.07, 0.4),
				CF(acx, fy + LAYER3, z),
				BRASS_STRIPE,
				MAT.SmoothPlastic
			)
		end
	end
	-- A runner down the lobby from the door to the counter.
	dBox(model, "LobbyRunner", V3(5, 0.06, depth - 8), CF(lobbyCx, fy + LAYER2, midZ), BLUE_DEEP, MAT.Fabric)
	for _, s in ipairs({ -1, 1 }) do
		dBox(
			model,
			"LobbyRunnerEdge",
			V3(0.35, 0.07, depth - 8),
			CF(lobbyCx + s * 2.2, fy + LAYER3, midZ),
			RUNNER_EDGE,
			MAT.Fabric
		)
	end

	-- Warm timber beams across the hall and rafters along it. None over the
	-- logging rig's crane (it stands tall at the back row, x 11 to 29).
	ShopKit.Beams(model, frame, { zf + 6, zf + 17, midZ - 3.3, midZ + 6, zb - 1.5 })
	for _, x in ipairs({ west + 19, cx - 6, east - 36, east - 8 }) do
		ShopKit.Rafter(model, frame, x)
	end

	-- Signs: SHOWROOM over the lobby, a header over each run, a sub-sign over
	-- each bay. `keepOut` lists what a lantern must stay clear of.
	local keepOut: { { x0: number, x1: number, z0: number, z1: number } } = {}
	local chainTop = ceil - 0.9
	ShopKit.HeaderSign(model, {
		cx = lobbyCx,
		cy = Dealership.HeaderY,
		z = zf + 18,
		w = 9,
		h = ShopKit.HeaderMinHeight + 0.4,
		text = "SHOWROOM",
		accent = BLUE,
		ceilY = chainTop,
	})
	table.insert(keepOut, { x0 = lobbyCx - 5, x1 = lobbyCx + 5, z0 = zf + 17, z1 = zf + 19 })
	local layout = DealershipLot.Layout().bays
	if #bays == #layout then
		local plinthW = {}
		for i, lot in ipairs(layout) do
			plinthW[i] = lot.width
		end
		for _, run in ipairs(Dealership.Runs()) do
			local first = bays[run.first]
			-- The row's aisle edge: the header stands over the plinth's aisle end, so
			-- the front row's headers are in z -13 to -4 and the back row's 4 to 13.
			local s = if run.row == 1 then 1 else -1 -- toward the aisle
			local hz = first.aisleZ - s * 1.5
			local hx = first.x - plinthW[run.first] / 2 + (if run.row == 1 then 0.9 else -3.6)
			yawed(model, hx, hz, Dealership.HeaderYaw, function(tmp)
				ShopKit.HeaderSign(tmp, {
					cx = 0,
					cy = Dealership.HeaderY,
					z = 0,
					w = Dealership.HeaderWidth + (if run.kind == "Trailer" then 1.6 else 0),
					h = ShopKit.HeaderMinHeight + 0.4,
					text = run.header,
					accent = BLUE,
					ceilY = chainTop,
				})
			end)
			table.insert(keepOut, {
				x0 = hx - 1.2,
				x1 = hx + 1.2,
				z0 = hz - Dealership.HeaderWidth / 2 - 1,
				z1 = hz + Dealership.HeaderWidth / 2 + 1,
			})
			for i = run.first, run.last do
				local bay = bays[i]
				local lotBay = layout[i]
				yawed(model, bay.x, bay.aisleZ - s * 0.8, -s * Dealership.SubYaw, function(tmp)
					ShopKit.SubSign(tmp, {
						cx = 0,
						cy = Dealership.SubY,
						z = 0,
						w = Dealership.SubWidth,
						h = ShopKit.SubMinHeight + 0.2,
						text = Dealership.SubText(lotBay.kind, lotBay.id),
						accent = BLUE,
						ceilY = chainTop,
					})
				end)
			end
		end
	end
	ShopKit.CheckoutSign(model, frame, true)

	-- Lanterns: six down the aisle, one over each bay at its aisle edge, three in
	-- the lobby; every one is the family's warm capped lamp, and none hangs where a
	-- header is.
	local function lamp(x: number, z: number)
		for _, k in ipairs(keepOut) do
			if x >= k.x0 and x <= k.x1 and z >= k.z0 and z <= k.z1 then
				return
			end
		end
		ShopKit.WarmLamp(model, x, ceil - 3.4, z, chainTop)
	end
	local aisleZ = if aisleLo < aisleHi then (aisleLo + aisleHi) / 2 else midZ
	for i = 0, 5 do
		lamp(ax0 + 10 + i * 20, aisleZ)
	end
	for _, bay in ipairs(bays) do
		lamp(bay.x, bay.aisleZ + (if bay.row == 1 then -3.2 else 3.2))
	end
	for _, z in ipairs({ zf + 10, midZ + 2, zb - 16 }) do
		lamp(lobbyCx, z)
	end

	-- Lobby: brochure racks and a reception corner with plants, the crate corner
	-- (real Crate and Barrel meshes, parts first), the flags along the front wall.
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
	dBox(model, "ReceptionTable", V3(3.6, 1.2, 2), CF(west + 4, fy + 0.6, zb - 24), TABLE_TOP, MAT.Wood)
	for _, z in ipairs({ zb - 28, zb - 20 }) do
		dBox(model, "ReceptionChair", V3(2, 1.2, 2), CF(west + 4, fy + 0.6, z), BLUE, MAT.Fabric)
		dBox(model, "ReceptionChairBack", V3(0.4, 1.8, 2), CF(west + 2.6, fy + 1.5, z), BLUE, MAT.Fabric)
	end
	plant(model, west + 1.8, fy, zf + 3, 1.4)
	plant(model, west + lobbyW - 2, fy, zf + 3, 1.4)
	plant(model, west + lobbyW - 2, fy, zb - 12, 1.4)
	trashCan(model, west + lobbyW - 2, fy, zb - 1.5)
	stockProp(model, "Crate", west + 1.8, fy, zb - 15, 0.1)
	stockProp(model, "Crate", west + 1.8, fy, zb - 12.6, -0.15)
	stockProp(model, "Barrel", west + 4.6, fy, zb - 13, 0)
	for i, x in ipairs({ west + 36, west + 66, west + 96, west + 126 }) do
		dBox(model, "FlagPole", V3(0.2, 5, 0.2), CF(x, fy + 2.5, zf + 0.6), IRON, MAT.Metal)
		dBox(
			model,
			"FlagCloth",
			V3(2.4, 1.5, 0.1),
			CF(x + 1.3, fy + 4.2, zf + 0.6),
			if i % 2 == 0 then BLUE else hex("#C8402F"),
			MAT.Fabric
		)
	end
	counterDetail(model, frame)
	backDoor(model, frame, west + 5.7, zb, true, 0)
end

return Dealership
