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
-- the lobby furnishings (store restyle, in the Hearth & Home's look: wooden display
-- tables, wall shelving with binders and model trucks, framed pictures, rugs, plants), the
-- event expansion room and its banner (ShopEventKit). The vehicles' own stock, order, prices
-- and bays are untouched.

local ShopKit = require(script.Parent.Parent.ShopKit)
local Kit = require(script.Parent.Parent.Kit)
local DealershipLot = require(script.Parent.Parent.DealershipLot)
local ShopEventKit = require(script.Parent.Parent.ShopEventKit)
local Palette = require(script.Parent.Parent.Palette)
local StoreEventData = require(script.Parent.Parent.Parent.StoreEventData)

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
local BLUE_DEEP = hex("#285A96") -- the rugs
local RUNNER = ShopKit.Table.runner -- the runners, #8A3B2E fabric
local BRASS_STRIPE = hex("#E3B73C")

local Dealership = {}

-- `bays` are the vehicle bays in hall space (see BuildingArt.dealership):
-- x, z (the plinth's middle), row, zNear / zFar (the plinth's edge facing the
-- central aisle, and its far edge).
export type Bay = { x: number, z: number, row: number, aisleZ: number }

-- The signs hang this far under the ceiling line (frame.ceilY - 0.9 is the
-- underside of the beams).
Dealership.HeaderY = 11.3 -- a header's middle
Dealership.CheckoutY = 9.9 -- the CHECKOUT board's middle, flat on the back wall over the keeper (ShopKit.CheckoutY)
Dealership.HeaderWidth = 10.4
Dealership.HeaderYaw = math.rad(90) -- a header faces the door end (west), so it reads from the lobby and down the aisle
Dealership.WallTuck = 0.5 -- a beam or rafter runs this far past the interior frame, into the wall (the wall's face is 0.4 out)
Dealership.TopY = DealershipLot.HallHeight + 0.1 -- the highest part the interior adds (the beams' tops)

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
	labelled: boolean, -- gets a hung header: the first run of its kind in its row (a kind that comes back later in the row is told by the plinths' own name signs)
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
				labelled = true,
			})
		end
	end
	for i, run in ipairs(runs) do
		for j = 1, i - 1 do
			if runs[j].row == run.row and runs[j].kind == run.kind then
				run.labelled = false
			end
		end
	end
	return runs
end

-- The sub-sign over a bay: what the vehicle hauls (ShopLogic's own words for
-- the shop card: "Bed: 12 logs", "No bed", "+12 bed space").
function Dealership.SubText(kind: string, id: string): string
	return DealershipLot.BedText(kind, id)
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

---------------------------------------------------------------------------
-- The room's furnishings beyond the stock (looks only, all inside the walls)
---------------------------------------------------------------------------

-- Where a wall's inner face is, past the interior frame (the walls' faces are this far out of it).
local WALL_OUT = 0.4
local BINDER = { hex("#2F6DB5"), hex("#C9A24A"), hex("#7FA3C8"), hex("#B5594A") }
local MODEL_PAINT = { hex("#B5594A"), hex("#2F6DB5"), hex("#C9A24A"), hex("#4E7A3E") }

-- A wall shelf unit: a back panel, two boards and what stands on them (binders and little model trucks). `at` is
-- the unit's middle on the wall's face at the floor, its +Z pointing into the room and its X along the wall; `len`
-- is its length along the wall, `lowY` the lower board's height over the floor.
local function wallShelves(model: Model, at: CFrame, len: number, lowY: number, seed: number)
	dBox(model, "NookPanel", V3(len, 4.4, 0.2), at * CF(0, lowY + 1.9, 0.1), TABLE)
	local ys = { lowY, lowY + 2.6 }
	for _, y in ipairs(ys) do
		dBox(model, "NookBoard", V3(len, 0.25, 1.2), at * CF(0, y, 0.7), TABLE_TOP)
	end
	local function put(name: string, size: Vector3, topY: number, dx: number, color: Color3)
		return dBox(model, name, size, at * CF(dx, topY + size.Y / 2, 0.7), color, MAT.SmoothPlastic)
	end
	local top1, top2 = ys[1] + 0.125, ys[2] + 0.125
	local u = len / 8
	-- lower board: three binders, two model trucks, a binder
	for i, dx in ipairs({ -3 * u, -2.5 * u, -2 * u }) do
		put("NookBinder", V3(0.4, 1.1 + 0.15 * i, 0.9), top1, dx, BINDER[1 + (seed + i) % 4])
	end
	put("NookModel", V3(2.0, 0.5, 0.8), top1, 0.6 * u, MODEL_PAINT[1 + seed % 4])
	put("NookModel", V3(0.8, 0.5, 0.7), top1, 0.6 * u + 1.1, MODEL_PAINT[1 + (seed + 1) % 4])
	put("NookBinder", V3(0.4, 1.3, 0.9), top1, 3 * u, BINDER[1 + (seed + 2) % 4])
	-- upper board: two model trucks
	put("NookModel", V3(2.4, 0.6, 0.9), top2, -1.8 * u, MODEL_PAINT[1 + (seed + 2) % 4])
	put("NookModel", V3(2.4, 0.6, 0.9), top2, 1.8 * u, MODEL_PAINT[1 + (seed + 3) % 4])
end

-- A framed picture flat on a wall: a wood frame and a canvas just proud of it. `at` as for wallShelves, `y` its middle.
local function picture(model: Model, at: CFrame, y: number, w: number, h: number, canvas: Color3)
	dBox(model, "PictureFrame", V3(w, h, 0.2), at * CF(0, y, 0.1), TABLE)
	dBox(model, "PictureArt", V3(w - 0.5, h - 0.5, 0.1), at * CF(0, y, 0.22), canvas, MAT.SmoothPlastic)
end

-- A rug lying flush on the floor: a body and a lighter edge board, both thin skins on the floor's own layers.
local function rug(model: Model, fy: number, x: number, z: number, w: number, d: number, body: Color3, edge: Color3)
	dBox(model, "LobbyRug", V3(w, 0.06, d), CF(x, fy + LAYER2, z), body, MAT.Fabric)
	dBox(model, "LobbyRugEdge", V3(w - 1.0, 0.07, d - 1.0), CF(x, fy + LAYER3, z), edge, MAT.Fabric)
end

-- A table in the Hearth & Home's wood (ShopKit.DisplayTable): a plank top, a dark apron, a cream trim and four legs
-- to `floorY` (the rug's top under it). `topH` is the top's height over that. Parts are named <name>Top, <name>Apron, <name>Trim, <name>Leg.
local function woodTable(
	model: Model,
	name: string,
	x: number,
	z: number,
	floorY: number,
	w: number,
	d: number,
	topH: number
)
	return ShopKit.DisplayTable(model, {
		name = name,
		cx = x,
		cz = z,
		width = w,
		depth = d,
		topY = floorY + topH,
		apronH = 0.4,
		legs = 4,
		floorY = floorY,
	})
end

-- The "Coming soon" card on its easel, standing on a table top in the zone's frame: a cream board
-- (about 2 x 1.2 studs) in a brass frame, leaning back 15 degrees on a small easel, the words in
-- FredokaOne sign ink. Looks only (no collide, query, touch or shadow), no prompt, no price. Its
-- parts carry EventRole "card": ShopEventKit.SetTablesShown hides them while an event is on.
Dealership.CardSize = V3(2, 1.2, 0.08)
Dealership.CardTilt = math.rad(15)
Dealership.CardText = "Coming soon"

local function comingSoonCard(parent: Instance, name: string, x: number, topY: number, z: number)
	local size, tilt = Dealership.CardSize, Dealership.CardTilt
	local function add(part: Part): Part
		Kit.decor(part, false)
		part:SetAttribute(ShopEventKit.RoleAttribute, "card")
		return part
	end
	-- the card stands on the table, tilted back about its own bottom edge
	local pivot = CF(x, topY + 0.15, z - 0.25) * CFrame.Angles(tilt, 0, 0)
	local up = CF(0, size.Y / 2, 0)
	add(
		Kit.part(
			parent,
			name .. "Frame",
			V3(size.X + 0.24, size.Y + 0.24, 0.06),
			pivot * up * CF(0, 0, 0.05),
			Palette.Brass,
			MAT.Metal
		)
	)
	local board = add(Kit.part(parent, name .. "Board", size, pivot * up, Palette.SignCream, MAT.SmoothPlastic))
	-- (the easel's one back leg, leaning the other way, holds the card up)
	add(
		Kit.part(
			parent,
			name .. "Leg",
			V3(0.12, 1.4, 0.12),
			CF(x, topY + 0.7, z + 0.2) * CFrame.Angles(math.rad(-20), 0, 0),
			TIMBER,
			MAT.Wood
		)
	)
	Kit.signText(board, Dealership.CardText, Palette.SignInk, { Enum.NormalId.Front }, Enum.Font.FredokaOne, 0.2)
end

-- What a table holds while an event is on: a parcel (the generic stand-in the store item
-- models fall back to, StoreModelSlots' Parcel) until an approved item has a model of its own.
-- Built hidden; ShopEventKit.SetTablesShown shows it. Parts carry EventRole "held".
local function heldParcel(parent: Instance, name: string, x: number, topY: number, z: number, paint: Color3)
	local model = Kit.model(name, parent)
	local function add(part: Part)
		Kit.decor(part, false)
		part:SetAttribute(ShopEventKit.RoleAttribute, "held")
		part.Transparency = 1
		return part
	end
	add(Kit.part(model, name .. "Box", V3(1.3, 0.9, 1.1), CF(x, topY + 0.45, z), paint, MAT.SmoothPlastic))
	return model
end

-- The event room's three tables, on the zone's pads (ShopEventKit's markers): the Hearth & Home's wood table kit
-- (a plank top, a dark apron, a cream trim, four legs), built in the zone's own frame and turned with it. Looks only:
-- the roped-off room has nothing to walk into. Each table carries the "Coming soon" card on an easel and, hidden, the
-- parcel it holds once an event is on (the card and the parcel stand in the shop beside the zone's tables; ShopEventKit.SetZoneActive switches them).
local function eventTables(model: Model, zone: Model, anchor: CFrame)
	local tmp = Instance.new("Model")
	local inZone = Instance.new("Model")
	local topY = 2.3
	for i, marker in ipairs(ShopEventKit.TableMarkers(zone)) do
		local at = anchor:PointToObjectSpace(marker.CFrame.Position)
		ShopKit.DisplayTable(tmp, {
			name = "EventDisplay" .. i,
			cx = at.X,
			cz = at.Z,
			width = marker.Size.X - 0.2,
			depth = marker.Size.Z - 0.3,
			topY = topY,
			apronH = 0.35,
			legs = 4,
			floorY = 0.14,
			solid = false,
		})
		comingSoonCard(inZone, "EventCard" .. i, at.X, topY, at.Z)
		heldParcel(inZone, "EventHeld" .. i, at.X, topY, at.Z, MODEL_PAINT[1 + (i - 1) % #MODEL_PAINT])
	end
	for _, holder in ipairs({ tmp, inZone }) do
		for _, d in ipairs(holder:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CFrame = anchor * d.CFrame
			end
		end
	end
	for _, child in ipairs(tmp:GetChildren()) do
		child.Parent = model
	end
	for _, child in ipairs(inZone:GetChildren()) do
		child.Parent = model
	end
	tmp:Destroy()
	inZone:Destroy()
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
		dBox(model, "AisleRunner", V3(ax1 - ax0, 0.06, 5), CF(acx, fy + LAYER2, acz), RUNNER, MAT.Fabric)
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
	dBox(model, "LobbyRunner", V3(5, 0.06, depth - 8), CF(lobbyCx, fy + LAYER2, midZ), RUNNER, MAT.Fabric)
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

	-- Painted stripes along the lobby runner's edges, like the aisle's.
	for _, s in ipairs({ -1, 1 }) do
		dBox(
			model,
			"LobbyStripe",
			V3(0.4, 0.07, depth - 8),
			CF(lobbyCx + s * 3.0, fy + LAYER3, midZ),
			BRASS_STRIPE,
			MAT.SmoothPlastic
		)
	end
	ShopKit.Ceiling(model, frame)

	-- Warm timber beams across the hall and rafters along it. None over the
	-- logging rig's crane (it stands tall at the back row, x 11 to 29).
	-- The beams and rafters run into the walls (the kit's stop 0.7 short of them,
	-- which leaves a timber hanging in the air in a hall this wide).
	local into = Dealership.WallTuck
	for _, z in ipairs({ zf + 6, zf + 17, midZ - 3.3, midZ + 6, zb - 1.5 }) do
		dBox(model, "CeilingBeam", V3(2 * (frame.halfW + into), 0.9, 0.9), CF(0, ceil - 0.45, z), TIMBER)
	end
	for _, x in ipairs({ west + 19, cx - 6, east - 36, east - 8 }) do
		dBox(model, "CeilingRafter", V3(0.7, 0.7, 2 * (frame.halfD + into)), CF(x, ceil - 0.35, 0), TIMBER)
	end

	-- Signs: SHOWROOM over the lobby, a header over each run, a sub-sign over
	-- each bay. `keepOut` lists what a lantern must stay clear of.
	local keepOut: { { x0: number, x1: number, z0: number, z1: number } } = {}
	-- Every chain runs up to the roof's underside (the ceiling line), so a sign or a
	-- lantern is welded to the roof and never hangs from nothing under it.
	local chainTop = ceil
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
			if not run.labelled then
				continue
			end
			local first = bays[run.first]
			-- The row's aisle edge: the header stands over the plinth's aisle end, so
			-- the front row's headers are in z -13 to -4 and the back row's 4 to 13.
			local s = if run.row == 1 then 1 else -1 -- toward the aisle
			local hz = first.aisleZ - s * 1.5
			local hx = first.x - plinthW[run.first] / 2 + (if run.row == 1 then 0.9 else -6.6)
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
		end
	end
	-- CHECKOUT hangs flat on the back wall over the keeper, so it reads from the door over the counter and
	-- nothing hangs in front of it (no chains across another sign). The kit also lays the keeper's mat; no plaque.
	ShopKit.CheckoutSign(
		model,
		frame,
		{ plaque = false, onCounter = true, cy = Dealership.CheckoutY, w = 5.4, h = 1.5, z = frame.halfD + 0.1 } -- (against the hall's back wall, whose face is 0.4 out)
	)

	-- Lanterns: six down the aisle and three in the lobby (each plinth has its own lamp post); every one is the family's warm capped lamp, and none hangs where a
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
	for _, z in ipairs({ zf + 10, midZ + 2, zb - 16 }) do
		lamp(lobbyCx, z)
	end

	-- Lobby: brochure racks against the front wall, a reception corner (a wooden table, two chairs, a rug), a finance
	-- table with brochures, wall shelving, framed pictures, plants and the crate corner (real Crate and Barrel meshes,
	-- parts first). The doorway aisle (the door's walk to the counter, the runner) and every bay stay clear.
	for i, x in ipairs({ west + 23.4, west + 26.4 }) do
		dBox(model, "BrochureRack", V3(2.4, 4.2, 0.8), CF(x, fy + 2.1, zf), TABLE, MAT.Wood)
		for r = 1, 3 do
			dBox(
				model,
				"Brochure",
				V3(1.9, 0.9, 0.12),
				CF(x, fy + 0.9 + r * 0.95, zf + 0.46),
				if (i + r) % 2 == 0 then PAPER else hex("#7FA3C8"),
				MAT.SmoothPlastic
			)
		end
	end
	-- (the rug's edge board is its highest skin: what stands on the rug stands on that, so no leg or chair is sunk in it)
	-- East of the door's 8-wide walk (the door sits near the west wall, so the
	-- old west corner stood in that walk).
	local onRug = fy + LAYER3 + 0.035
	local recvZ = zb - 24
	local recvX = west + 17.5
	rug(model, fy, recvX + 0.6, recvZ, 8.6, 12.0, BLUE_DEEP, RUNNER_EDGE)
	woodTable(model, "Reception", recvX, recvZ, onRug, 4.4, 2.4, 2.0)
	for _, z in ipairs({ zb - 28, zb - 20 }) do
		dBox(model, "ReceptionChair", V3(2, 1.2, 2), CF(recvX, onRug + 0.6, z), BLUE, MAT.Fabric)
		dBox(model, "ReceptionChairBack", V3(0.4, 1.8, 2), CF(recvX - 1.2, onRug + 1.5, z), BLUE, MAT.Fabric)
	end
	-- the finance table, east of the runner, with a rug under it and a few brochures on it
	local finX, finZ = west + 20.4, zb - 18
	rug(model, fy, finX, finZ, 8, 6, hex("#3E5F7A"), RUNNER_EDGE)
	woodTable(model, "Finance", finX, finZ, onRug, 4.4, 2.4, 2.0)
	for i, dx in ipairs({ -1.2, 0, 1.2 }) do
		dBox(
			model,
			"Brochure",
			V3(0.9, 0.12, 1.2),
			CF(finX + dx, onRug + 2.06, finZ),
			if i % 2 == 0 then PAPER else hex("#7FA3C8"),
			MAT.SmoothPlastic
		)
	end
	-- wall shelving (west wall over the crate corner, back wall east of the counter) and framed pictures
	local westWall = CF(-(frame.halfW + WALL_OUT), fy, 0) * CFrame.Angles(0, math.pi / 2, 0)
	local backWall = CF(0, fy, frame.halfD + WALL_OUT) * CFrame.Angles(0, math.pi, 0)
	wallShelves(model, westWall * CF(-(zb - 12.2), 0, 0), 9, 5.0, 0)
	wallShelves(model, backWall * CF(-(west + 29.6), 0, 0), 8, 4.4, 1)
	for _, z in ipairs({ zf + 8, zb - 38.7, zb - 24 }) do
		picture(model, westWall * CF(-z, 0, 0), 8.6, 3.4, 2.4, hex("#9CC3D8"))
	end
	picture(model, backWall * CF(-(west + 22.6), 0, 0), 9.2, 3.4, 2.4, hex("#E0B77A"))
	picture(model, backWall * CF(-(west + 29.6), 0, 0), 11.6, 3.4, 2.4, hex("#C98B7B"))
	picture(model, backWall * CF(-(west + 1.6), 0, 0), 9.2, 2.4, 2.6, hex("#8DB08A"))
	plant(model, west + 1.8, fy, zf + 3, 1.4)
	plant(model, west + lobbyW - 2, fy, zb - 12, 1.4)
	plant(model, west + 16.6, fy, zb - 9.2, 1.2)
	trashCan(model, west + lobbyW - 2, fy, zb - 5.5)
	stockProp(model, "Crate", west + 1.8, fy, zb - 15, 0.1)
	stockProp(model, "Crate", west + 1.8, fy, zb - 12.6, -0.15)
	stockProp(model, "Barrel", west + 4.6, fy, zb - 13, 0)

	-- The event expansion room (EVENTS.md, ShopEventKit): a roped-off 16 x 9 area east of the door's walk, turned so its
	-- open front faces east toward the showroom, between the door's end of the lobby and the reception corner (clear of the
	-- doorway aisle and every bay), with its three tables on the pads; and the event banner in the front corner east of the
	-- door, just outside the door's width (so the door's sensor, the runner and the walk in stay clear), facing into the
	-- lobby with the front wall behind it (in the east it stood in front of the first truck from the door).
	local zoneAnchor = CF(west + 19.7, fy, zf + 21.7) * CFrame.Angles(0, -math.pi / 2, 0)
	local zone = ShopEventKit.BuildZone(model, "Dealership", zoneAnchor, V3(16, 0, 9))
	eventTables(model, zone, zoneAnchor)
	-- The cards show until an event is on (StoreEventData.Events holds one for this store); the server
	-- switches them with the room (ShopEventKit.SetZoneActive).
	ShopEventKit.SetTablesShown(zone, ShopEventKit.HoldsEvent(StoreEventData.Events, "Dealership"))
	ShopEventKit.BuildBanner(model, "Dealership", CF(west + 18.4, fy, zf + 3) * CFrame.Angles(0, math.pi, 0), 4.4)
	counterDetail(model, frame)
	backDoor(model, frame, west + 5.7, zb, true, 0)
end

return Dealership
