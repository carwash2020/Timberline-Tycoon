--!strict
-- The dealership's open display lot: every truck and trailer on its own
-- bay, side-on to the path along the south side (-Z) so you can see what
-- the vehicle is before you buy it. Each bay is a raised plinth (stone
-- slab, a stripe of the vehicle's paint along its front edge, a lamp post)
-- with the REAL vehicle model on it (the same TruckArt builders the live
-- vehicles use: anchored, no scripts, looks only, never a seat to sit in)
-- and the vehicle's box standing in front of it, so the box is what you
-- pick up and the vehicle behind it is what you are buying. A sign on the
-- plinth gives the name and the one price. Bays are ordered by price, left
-- to right: the cheap rigs on the front row, the dear ones on the back.
-- MapBuilder places the model; the boxes are the purchase (BoxSpot parts,
-- sized by ItemBox from the vehicle's real bounds, the vehicle seen through the
-- box's window, on a block in the vehicle's accent colour).
--
-- Two rows side-on need more width than the old single row of eight, so
-- the lot (and the reserved lawn in WorldLayout) is wider: it keeps the
-- same west edge and the same depth.

local CollectionService = game:GetService("CollectionService")

local BoxLook = require(script.Parent.Parent.BoxLook)
local ItemBox = require(script.Parent.Parent.ItemBox)
local ItemCatalog = require(script.Parent.Parent.ItemCatalog)
local VehicleMeshGate = require(script.Parent.Parent.VehicleMeshGate)
local HoverTag = require(script.Parent.Parent.HoverTag)
local Kit = require(script.Parent.Kit)
local MeshKit = require(script.Parent.MeshKit)
local Palette = require(script.Parent.Palette)
local ShowroomLight = require(script.Parent.Parent.ShowroomLight)
local StoreTier = require(script.Parent.Parent.StoreTier)
local TruckArt = require(script.Parent.TruckArt)
local VehicleLogic = require(script.Parent.Parent.VehicleLogic)
local VehicleModels = require(script.Parent.VehicleModels)

local DealershipLot = {}

-- Southwest corner of the rows' floor (the hall's lobby is west of it), inside
-- the reserved lawn (WorldLayout.Reserved DealershipLot). The hall's front wall
-- stands at z 100 (outside face; the East Link, z 66 to 94, now runs by it), north of the Land Office and its sign, so the
-- hall stays clear of them and of the spawn's line to the lighthouse.
DealershipLot.OriginX = 207
DealershipLot.OriginZ = 100.2

-- The hall round the bays (BuildingArt's Dealership): a lobby this wide at
-- the west end with the counter at the back and the door in front, the rows
-- of bays beside it.
DealershipLot.Lobby = 26
DealershipLot.HallWallThick = 0.8
DealershipLot.FloorY = 0.4 -- the hall floor's top (BuildingArt's slab)

-- Studs. A plinth is this much wider than its vehicle on every side, the
-- gap between neighbouring plinths, the walk space at the ends, and so on.
-- The box stands ON its plinth, at the edge facing the central aisle, with
-- the vehicle behind it; the aisle between the two rows stays clear.
DealershipLot.PlinthMargin = 0.4
DealershipLot.BayGap = 1.5
DealershipLot.SideMargin = 3
DealershipLot.FrontMargin = 3.5
DealershipLot.BackMargin = 3.5
DealershipLot.BoxGap = 0.6 -- between a box and the plinth's edge, and the vehicle
DealershipLot.Aisle = 14 -- the clear central walkway between the rows' plinths
DealershipLot.PlinthHeight = 1.2
-- The vehicle's box stands on a flush inlay, not a slab (store restyle): a thin accent-coloured mat (BoxBlock) inside a
-- wood border (BoxMatFrame), both painted straight onto the plinth's top and never taller than a coat of paint, so
-- nothing reads as a loose pad sitting on the plinth. The border's edge meets the aisle stripe's inner edge.
DealershipLot.BlockHeight = 0.1 -- the accent-coloured mat a vehicle's box stands on
DealershipLot.BlockMargin = 0.12 -- the mat is this much bigger than the box all round
DealershipLot.FrameMargin = 0.13 -- and the wood border this much bigger again
DealershipLot.FrameHeight = 0.05

-- A vehicle has no tier stand (T391): the plinth's front band and aisle-edge stripe are the
-- vehicle's own paint, and a name sign stands at the plinth. Only a vehicle that is an upgraded
-- version of another (ItemCatalog `upgradeOf`, checked by StoreTier.UpgradeOf) gets a small
-- cream-and-brass plaque on its name sign (the words are StoreTier.UpgradeMark and UpgradeLine). No tier colour,
-- no flag, no post.
DealershipLot.NameSignSize = Vector3.new(5.0, 1.9, 0.16) -- the plinth's name sign: the name, and under it what it hauls
DealershipLot.PlaqueSize = Vector3.new(3.0, 1.0, 0.14) -- the upgrade plaque's brass frame (its board is inset 0.12 all round)
DealershipLot.PlaqueInset = 0.12
DealershipLot.PlaqueMinText = 14 -- UITextSizeConstraint.MinTextSize on both lines
DealershipLot.BandHeight = 0.55
DealershipLot.StripeWidth = 0.3 -- the aisle-edge stripe: at the very edge, clear of the box's block
-- The stripe and band are paint, not slabs: thin skins (decal-style parts, never
-- collide, never cast a shadow) the full width of their plinth, edge to edge, so the
-- stripe's ends sit exactly on the plinth's corners and the band's top edge exactly on
-- the plinth's top edge. The stripe lies ON the top (its underside the slab's top, 0.05
-- of paint above it) along the aisle edge; the band is the aisle face's own outer skin
-- (the slab is one thickness shallower than the bay, the band fills the rest: its outer
-- face is the bay's edge, its top face continues the slab's top, the stripe's edge
-- meets it). Nothing is coplanar with another face and nothing leaves the bay.
DealershipLot.PaintThickness = 0.05
local BRASS = Palette.Get("Brass")
local SIGN_CREAM = Palette.Get("SignCream")
local SIGN_INK = Palette.Get("SignInk")
-- A display vehicle's Neon lenses are never near-white (ShopKit.NearWhite, luma 0.86): the live
-- trucks' pale headlamp lens (#FFE9B0) blows out in a lit hall, so the display copy wears warm amber.
DealershipLot.MaxNeonLuma = 0.86
-- The hall's height (T421): walls, glass band, beams and roof are built from it. It was 15, and the Logging Rig's crane
-- (16.5 over its wheels' ground) did not fit, so its display copy was scaled down. No display copy is scaled any more:
-- the rig stands at full size, its top 0.4 (floor) + 1.2 (plinth) + 16.5 = 18.1 over the lot's floor line, the beams'
-- underside is HallHeight - 0.9 = 19.1 and the rafters' HallHeight - 0.7. The hall's footprint (154 x 61) is unchanged.
DealershipLot.HallHeight = 20
DealershipLot.DisplayLens = Color3.fromRGB(255, 205, 125)

-- The vehicles on show: ItemBox.Showroom, the one list.
local ORDER = ItemBox.Showroom

local function itemOf(kind: string, id: string): any
	return if kind == "Truck" then ItemCatalog.GetTruck(id) else ItemCatalog.GetTrailer(id)
end

-- The price the bays are ordered by: the catalog's v2 price, so the order
-- (and so the lot's size) never depends on which loop is running.
local function orderPrice(kind: string, id: string): number
	local item = itemOf(kind, id)
	if not item then
		return 0
	end
	return if item.v2 and type(item.v2.price) == "number" then item.v2.price else item.priceCash
end

-- A vehicle as built: its real length and width (the parts' own bounds, not
-- the layout's wheelbase), where the middle of that is from the pivot, and
-- how far the pivot is above the lowest part. Measured once from a built
-- model (defined below, after the builders).
export type Measured = { length: number, span: number, cx: number, cz: number, feet: number }
local measureVehicle: (string, string, boolean?) -> Measured

export type Bay = {
	kind: string,
	id: string,
	row: number, -- 1 front, 2 back
	x: number, -- centre, lot space
	z: number, -- the plinth's centre, lot space (0 = the lot's front edge)
	width: number, -- plinth width (along x)
	depth: number, -- plinth depth (along z)
	length: number, -- the vehicle, nose to tail
	span: number, -- the vehicle, side to side
	box: Vector3, -- the box standing on the plinth, aisle side
	boxZ: number, -- the box's centre, lot space
	vz: number, -- the vehicle's middle line, lot space
}

export type Layout = { bays: { Bay }, width: number, depth: number }

local cached: Layout? = nil

-- Where everything goes. Pure data from the catalog and TruckLayout, so
-- Size() is the same everywhere and needs no models.
function DealershipLot.Layout(): Layout
	if cached then
		return cached
	end
	local sorted = table.clone(ORDER)
	table.sort(sorted, function(a, b)
		return orderPrice(a.kind, a.id) < orderPrice(b.kind, b.id)
	end)
	local entries = {}
	for _, entry in ipairs(sorted) do
		local fit = ItemBox.For(entry.kind, entry.id)
		local m = measureVehicle(entry.kind, entry.id)
		table.insert(entries, {
			kind = entry.kind,
			id = entry.id,
			length = m.length,
			span = m.span,
			box = fit.size,
			bay = math.max(m.length, fit.size.X) + 2 * DealershipLot.PlinthMargin,
		})
	end
	local function rowWidth(from: number, to: number): number
		local w = 0
		for i = from, to do
			w += entries[i].bay
		end
		return w + math.max(0, to - from) * DealershipLot.BayGap
	end
	-- Split the price-ordered list into a front row and a back row of the
	-- most even width.
	local split, best = 1, math.huge
	for k = 1, #entries - 1 do
		local worst = math.max(rowWidth(1, k), rowWidth(k + 1, #entries))
		if worst < best then
			best = worst
			split = k
		end
	end
	local width = best + 2 * DealershipLot.SideMargin
	local rows = { { 1, split }, { split + 1, #entries } }
	local bays: { Bay } = {}
	local zCursor = DealershipLot.FrontMargin
	local depth = 0
	for rowIndex, range in ipairs(rows) do
		local maxBox, maxSpan = 0, 0
		for i = range[1], range[2] do
			maxBox = math.max(maxBox, entries[i].box.Z)
			maxSpan = math.max(maxSpan, entries[i].span)
		end
		local carDepth = maxSpan + 2 * DealershipLot.PlinthMargin
		local strip = maxBox + 2 * DealershipLot.BoxGap
		local plinthDepth = carDepth + strip
		local pz0 = zCursor
		local x = -rowWidth(range[1], range[2]) / 2
		for i = range[1], range[2] do
			local e = entries[i]
			-- Row 1 (front, by the street) has its aisle side at +Z: the
			-- vehicle is at the front of the plinth and the box behind it.
			-- Row 2 mirrors it: its aisle is at -Z.
			local vz, boxZ
			if rowIndex == 1 then
				vz = pz0 + DealershipLot.PlinthMargin + maxSpan / 2
				boxZ = pz0 + plinthDepth - DealershipLot.BoxGap - e.box.Z / 2
			else
				vz = pz0 + plinthDepth - DealershipLot.PlinthMargin - maxSpan / 2
				boxZ = pz0 + DealershipLot.BoxGap + e.box.Z / 2
			end
			table.insert(bays, {
				kind = e.kind,
				id = e.id,
				row = rowIndex,
				x = x + e.bay / 2,
				z = pz0 + plinthDepth / 2,
				width = e.bay,
				depth = plinthDepth,
				length = e.length,
				span = e.span,
				box = e.box,
				boxZ = boxZ,
				vz = vz,
			})
			x += e.bay + DealershipLot.BayGap
		end
		zCursor = pz0 + plinthDepth
		if rowIndex == 1 then
			zCursor += DealershipLot.Aisle
		else
			depth = zCursor + DealershipLot.BackMargin
		end
	end
	local result: Layout = { bays = bays, width = width, depth = depth }
	cached = result
	return result
end

-- Width and depth of the open lot, in studs.
function DealershipLot.Size(): (number, number)
	local layout = DealershipLot.Layout()
	return layout.width, layout.depth
end

-- The showroom hall's inside and where it stands: the lobby, then the lot.
-- The front wall's outside face sits on z 70.2, clear of the road.
export type Hall = { innerW: number, innerD: number, cx: number, cz: number }

function DealershipLot.Hall(): Hall
	local width, depth = DealershipLot.Size()
	local innerW = width + DealershipLot.Lobby
	local innerD = depth + 0.8
	return {
		innerW = innerW,
		innerD = innerD,
		cx = DealershipLot.OriginX - DealershipLot.Lobby + innerW / 2,
		cz = DealershipLot.OriginZ - 0.4 + innerD / 2,
	}
end

-- True while a vehicle is built only to be measured (no tag, no services).
local measuring = false

local function prep(model: Model, category: string, id: string)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("Category", category)
	model:SetAttribute("ItemId", id)
	if not measuring then
		CollectionService:AddTag(model, "ShopDisplay")
	end
	local scripts: { Instance } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("VehicleSeat") then
			-- Decoration: nobody sits in or drives a display model.
			d.Disabled = true
			d.MaxSpeed = 0
			d.Torque = 0
		elseif d:IsA("Seat") then
			d.Disabled = true
		end
		if d.ClassName == "Script" or d.ClassName == "LocalScript" then
			table.insert(scripts, d)
		end
	end
	for _, d in ipairs(scripts) do
		d:Destroy()
	end
	-- Looks only and anchored (Kit.decor: no collision, no queries, no touch).
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			Kit.decor(d)
			local c = d.Color
			if
				d.Material == Enum.Material.Neon
				and 0.299 * c.R + 0.587 * c.G + 0.114 * c.B > DealershipLot.MaxNeonLuma
			then
				d.Color = DealershipLot.DisplayLens
			end
			-- A mesh piece is decoration like the rest: it casts no shadow (MeshKit.Visual leaves it on).
			if d:GetAttribute("VisualMesh") == true then
				d.CastShadow = false
			end
		end
	end
end

-- The vehicle's name, which the sign beside it shows. Its price is not
-- printed: aiming at the vehicle, its plinth or its box shows the price in a
-- tag (Shared/HoverTag).
-- What the vehicle hauls, the second line of its name sign (ShopLogic's own words for the
-- shop card: "Bed: 12 logs", "No bed", "+12 bed space"). The hung sub-signs that used to say
-- this over each bay are gone: one sign per plinth now carries the name and the bed.
DealershipLot.ComingSoonText = "COMING SOON"

function DealershipLot.BedText(kind: string, id: string): string
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

local function nameOf(kind: string, id: string): string
	local item = itemOf(kind, id)
	return if item then item.displayName else id
end

-- The two builders are the ones the live vehicles use (TruckArt.Build for a truck, the trailer
-- TruckArt.AddTrailer draws and VehicleMeshes dresses): meshes go on inside them, so what is
-- fitted, prepped and moved afterwards is already the meshed vehicle.
local function placeTruck(id: string): Model?
	local def = ItemCatalog.GetTruck(id)
	if not def then
		return nil
	end
	return TruckArt.Build(def)
end

-- A trailer on its own, hitch toward -Z, and where to put its middle (nose, centred on the pivot,
-- same as a truck) once everything else is done.
local function placeTrailer(id: string): (Model?, CFrame?)
	local def = ItemCatalog.GetTrailer(id)
	local truck = ItemCatalog.GetTruck("Pickup")
	if not def or not truck then
		return nil, nil
	end
	local model, lay = TruckArt.BuildTrailer(def, truck)
	return model, CFrame.new(0, 0, -(lay.hitchZ + lay.length / 2))
end

local function paintOf(kind: string, id: string): Color3
	local item = itemOf(kind, id)
	if item and item.look and type(item.look.color) == "string" then
		return Color3.fromHex(item.look.color)
	end
	return Color3.fromRGB(150, 150, 150)
end

-- A display copy is never scaled (T421): the hall is tall enough for the tallest vehicle. The copy is still marked
-- "Fitted" once the lot has measured and moved it: no mesh may be placed on it later.
local function fitUnderCeiling(model: Model)
	model:SetAttribute("Fitted", true)
end

-- One display vehicle, in this order and no other: build it (the meshes go on inside the build),
-- fit it under the ceiling, prep it (anchored, decoration, no scripts), then move it. A mesh
-- placed after the fit would land at the unscaled offsets, so a fitted copy refuses late
-- meshes (VehicleMeshes, the `Fitted` attribute).
local function modelOf(kind: string, id: string, fitted: boolean?): Model?
	local model: Model?
	local move: CFrame? = nil
	if kind == "Truck" then
		model = placeTruck(id)
	else
		model, move = placeTrailer(id)
	end
	if model == nil then
		return nil
	end
	if fitted == true then
		fitUnderCeiling(model)
	end
	prep(model, kind, id)
	if move then
		model:PivotTo(move)
	end
	return model
end

-- The one display copy of a vehicle, as the lot stands it before it is put on a plinth (a spec
-- compares it with the bought vehicle).
function DealershipLot.Vehicle(kind: string, id: string): Model?
	return modelOf(kind, id, true)
end

local function measureModel(model: Model): Measured
	local pivot = model:GetPivot()
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local corner = d.CFrame * Vector3.new(d.Size.X / 2 * sx, d.Size.Y / 2 * sy, d.Size.Z / 2 * sz)
						local p = pivot:PointToObjectSpace(corner)
						lo, hi = lo:Min(p), hi:Max(p)
					end
				end
			end
		end
	end
	return { length = hi.Z - lo.Z, span = hi.X - lo.X, cx = (hi.X + lo.X) / 2, cz = (hi.Z + lo.Z) / 2, feet = -lo.Y }
end

measureVehicle = function(kind: string, id: string, fitted: boolean?): Measured
	measuring = true
	local model = modelOf(kind, id, fitted)
	measuring = false
	if model == nil then
		return { length = 20, span = 10, cx = 0, cz = 0, feet = 2 }
	end
	local m = measureModel(model)
	model:Destroy()
	return m
end

-- Loads every vehicle mesh before the lot is built (the deferred build step may wait: it is its
-- own thread, and the start-up preload has most of them already). A mesh that is still missing
-- afterwards keeps its whole part-built vehicle (VehicleMeshes says so once).
function DealershipLot.Preload(): MeshKit.PreloadResult
	local entries: { MeshKit.Entry } = {}
	for _, piece in ipairs(VehicleModels.AllPieces()) do
		table.insert(entries, { id = piece.meshId, hull = piece.wheel })
	end
	-- T421: the keyed ids (the trailers', the Timber Classic's and the recoloured trucks').
	for _, key in ipairs(VehicleMeshGate.AllKeys()) do
		local n = VehicleMeshGate.NumberFor(key)
		if n then
			table.insert(entries, { id = n, hull = string.sub(key, -6) == "/Wheel" })
		end
	end
	return MeshKit.Preload(entries)
end

-- The upgrade plaque: a brass frame round a cream board, about 3 x 1 studs, the mark (FredokaOne)
-- over the "upgrade of <base name>" line (Gotham), in sign ink, on both faces. Looks only. `at` is its
-- middle, facing the way the name sign does. Returns the board (named "UpgradePlaque").
function DealershipLot.Plaque(parent: Instance, at: CFrame, baseName: string): Part
	local size, inset = DealershipLot.PlaqueSize, DealershipLot.PlaqueInset
	Kit.decor(Kit.part(parent, "UpgradePlaqueFrame", size, at, BRASS, Enum.Material.Metal), false)
	local board = Kit.part(
		parent,
		"UpgradePlaque",
		Vector3.new(size.X - 2 * inset, size.Y - 2 * inset, size.Z + 0.02),
		at,
		SIGN_CREAM,
		Enum.Material.SmoothPlastic
	)
	Kit.decor(board, false)
	local lines: { { text: string, font: Enum.Font, share: number } } = {
		{ text = StoreTier.UpgradeMark, font = Enum.Font.FredokaOne, share = 0.55 },
		{ text = StoreTier.UpgradeLine(baseName), font = Enum.Font.Gotham, share = 0.45 },
	}
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "PlaqueText"
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 80
		gui.LightInfluence = Kit.SIGN_LIGHT_INFLUENCE
		gui.Parent = board
		local top = 0
		for _, line in ipairs(lines) do
			local label = Instance.new("TextLabel")
			label.Name = "PlaqueLine"
			label.BackgroundTransparency = 1
			label.Position = UDim2.fromScale(0, top)
			label.Size = UDim2.fromScale(1, line.share)
			label.Font = line.font
			label.TextScaled = true
			label.TextColor3 = SIGN_INK
			label.Text = line.text
			label.Parent = gui
			local limit = Instance.new("UITextSizeConstraint")
			limit.MinTextSize = DealershipLot.PlaqueMinText
			limit.MaxTextSize = 60
			limit.Parent = label
			top += line.share
		end
	end
	return board
end

-- The lot around the origin, front (-Z) toward the path. Place it with
-- Kit.placeAt. Returns the model; each vehicle is a child model.
function DealershipLot.Build(): Model
	DealershipLot.Preload()
	local layout = DealershipLot.Layout()
	local depth = layout.depth
	local lot = Instance.new("Model")
	lot.Name = "DealershipLot"
	local top = DealershipLot.PlinthHeight
	local oz = -depth / 2
	for _, bay in ipairs(layout.bays) do
		local cx, cz = bay.x, oz + bay.z
		local paint = paintOf(bay.kind, bay.id)
		-- The stripe and band are the vehicle's own paint: a vehicle has no tier colour.
		local color = paint

		-- The plinth: a slab you can walk up onto, a stripe of the vehicle's paint
		-- along its front edge, a lamp post at the back corner.
		-- The slab stops one paint thickness short of the aisle edge; the band's skin fills
		-- that last bit (its outer face is the bay's edge), so no face is coplanar with
		-- another and nothing sticks out past the bay.
		local aisleSide = if bay.row == 1 then 1 else -1 -- +Z or -Z: toward the central aisle
		local skin = DealershipLot.PaintThickness
		local slab = Kit.part(
			lot,
			"Plinth",
			Vector3.new(bay.width, top, bay.depth - skin),
			CFrame.new(cx, top / 2, cz - aisleSide * skin / 2),
			Color3.fromRGB(150, 146, 138),
			Enum.Material.Concrete
		)
		slab:SetAttribute("ItemId", bay.id)
		local stripe = Kit.part(
			lot,
			"PlinthStripe",
			Vector3.new(bay.width, skin, DealershipLot.StripeWidth),
			CFrame.new(cx, top + skin / 2, cz + aisleSide * (bay.depth / 2 - skin - DealershipLot.StripeWidth / 2)),
			color,
			Enum.Material.SmoothPlastic
		)
		Kit.decor(stripe, false)
		-- The band on the plinth's aisle face, from the top edge down, so the vehicle's
		-- colour reads from across the hall.
		local band = Kit.part(
			lot,
			"PlinthBand",
			Vector3.new(bay.width, DealershipLot.BandHeight, skin),
			CFrame.new(cx, top - DealershipLot.BandHeight / 2, cz + aisleSide * (bay.depth / 2 - skin / 2)),
			color,
			Enum.Material.SmoothPlastic
		)
		Kit.decor(band, false)
		local postX, postZ = cx - bay.width / 2 + 0.7, cz - aisleSide * (bay.depth / 2 - 0.7)
		Kit.decor(
			Kit.part(
				lot,
				"LampPost",
				Vector3.new(0.35, 7, 0.35),
				CFrame.new(postX, top + 3.5, postZ),
				Color3.fromRGB(45, 40, 38),
				Enum.Material.Metal
			),
			false
		)
		local glow = Kit.lantern(lot, CFrame.new(postX, top + 7.8, postZ), 1.2)
		for _, d in ipairs(glow:GetChildren()) do
			if d:IsA("PointLight") then
				d.Brightness = ShowroomLight.LanternBrightness
				d.Range = ShowroomLight.LanternRange
			end
		end

		-- T421: a vehicle whose meshes are not all in is not stocked: no vehicle, no box (nothing can be bought),
		-- and never a part-built stand-in. The plinth stays (the hall is laid out round it) and says so.
		local stocked = VehicleMeshGate.Complete(bay.kind, bay.id)
		local model = if stocked then modelOf(bay.kind, bay.id, true) else nil
		if not stocked then
			local sign = Kit.part(
				lot,
				"NameSign",
				DealershipLot.NameSignSize,
				CFrame.new(
					cx + bay.width / 2 - DealershipLot.NameSignSize.X / 2,
					DealershipLot.NameSignSize.Y / 2,
					cz + aisleSide * (bay.depth / 2 + 0.15)
				),
				Color3.fromRGB(62, 42, 24),
				Enum.Material.Wood
			)
			Kit.decor(sign, false)
			Kit.signText(
				sign,
				nameOf(bay.kind, bay.id) .. "\n" .. DealershipLot.ComingSoonText,
				Color3.fromRGB(245, 235, 215),
				{ Enum.NormalId.Front, Enum.NormalId.Back }
			)
		end
		if model then
			model.Parent = lot
			-- Side-on, nose toward the approach (west), on the plinth: its
			-- measured middle over the plinth's middle, its feet on the top.
			local m = measureModel(model)
			model:PivotTo(
				CFrame.new(cx, top + m.feet, oz + bay.vz)
					* CFrame.Angles(0, math.pi / 2, 0)
					* CFrame.new(-m.cx, 0, -m.cz)
			)
			-- The sign stands at the plinth's aisle edge, at its east end.
			local sign = Kit.part(
				model,
				"NameSign",
				DealershipLot.NameSignSize,
				CFrame.new(
					cx + bay.width / 2 - DealershipLot.NameSignSize.X / 2,
					DealershipLot.NameSignSize.Y / 2,
					cz + aisleSide * (bay.depth / 2 + 0.15)
				), -- on the floor, against the plinth's band
				Color3.fromRGB(62, 42, 24),
				Enum.Material.Wood
			)
			Kit.decor(sign, false)
			Kit.signText(
				sign,
				nameOf(bay.kind, bay.id) .. "\n" .. DealershipLot.BedText(bay.kind, bay.id),
				Color3.fromRGB(245, 235, 215),
				{ Enum.NormalId.Front, Enum.NormalId.Back }
			)
			local upgraded = StoreTier.UpgradeOf(bay.kind, bay.id)
			if upgraded then
				DealershipLot.Plaque(
					model,
					CFrame.new(
						sign.CFrame.Position.X,
						DealershipLot.NameSignSize.Y + DealershipLot.PlaqueSize.Y / 2 + 0.05,
						sign.CFrame.Position.Z
					),
					nameOf(bay.kind, upgraded)
				)
			end
		end

		if not stocked then
			HoverTag.Mark(slab, {
				key = "Vehicle:" .. bay.kind .. ":" .. bay.id,
				name = nameOf(bay.kind, bay.id),
				kind = bay.kind,
				itemId = bay.id,
				shop = "Dealership",
				anchor = true,
			})
			continue
		end
		-- The box: what you pick up and carry to the counter. On the plinth at
		-- the aisle edge, the vehicle beside it, so nothing stands in the aisle.
		-- Its front (the name strip and the big window) faces the aisle: the
		-- front row's aisle is at +Z, so those boxes are turned half way round.
		local block = DealershipLot.BlockHeight
		local blockMargin = DealershipLot.BlockMargin
		local frameMargin = blockMargin + DealershipLot.FrameMargin
		Kit.decor(
			Kit.part(
				lot,
				"BoxMatFrame",
				Vector3.new(bay.box.X + 2 * frameMargin, DealershipLot.FrameHeight, bay.box.Z + 2 * frameMargin),
				CFrame.new(cx, top + DealershipLot.FrameHeight / 2, oz + bay.boxZ),
				Color3.fromRGB(106, 69, 38),
				Enum.Material.Wood
			),
			false
		)
		Kit.decor(
			Kit.part(
				lot,
				"BoxBlock",
				Vector3.new(bay.box.X + 2 * blockMargin, block, bay.box.Z + 2 * blockMargin),
				CFrame.new(cx, top + block / 2, oz + bay.boxZ),
				BoxLook.Accent(bay.kind, bay.id),
				Enum.Material.SmoothPlastic
			),
			false
		)
		local spot = Kit.part(
			lot,
			"BoxSpot",
			bay.box,
			CFrame.new(cx, top + block + bay.box.Y / 2, oz + bay.boxZ)
				* CFrame.Angles(0, if bay.row == 1 then math.pi else 0, 0),
			Color3.fromRGB(196, 148, 90),
			Enum.Material.Wood
		)
		spot.CanCollide = false
		spot.CanQuery = false
		spot.CanTouch = false
		spot.Transparency = 1
		spot:SetAttribute("ItemId", bay.id)
		spot:SetAttribute("Category", bay.kind)
		-- The vehicle, its plinth and its box are one item for the hover tag
		-- (the tag sits over the vehicle).
		local hover: HoverTag.Spec = {
			key = "Vehicle:" .. bay.kind .. ":" .. bay.id,
			name = nameOf(bay.kind, bay.id),
			kind = bay.kind,
			itemId = bay.id,
			shop = "Dealership",
		}
		HoverTag.Mark(slab, hover)
		HoverTag.Mark(spot, hover)
		if model then
			hover.anchor = true
			HoverTag.Mark(model, hover)
		else
			hover.anchor = true
			HoverTag.Mark(slab, hover)
		end
	end
	return lot
end

-- A spawn pad: the footprint, corner marks in the truck colour, and the
-- orange button post outside the front-left corner. `cf` is the slab centre.
function DealershipLot.BuildPad(parent: Instance, cf: CFrame, color: Color3, length: number, width: number): Model
	local size = VehicleLogic.PadSize(length, width)
	local pad = Instance.new("Model")
	pad.Name = "SpawnPad"
	local slab = Kit.part(pad, "Slab", size, cf, Color3.fromRGB(90, 90, 94), Enum.Material.Concrete)
	slab.CanCollide = true
	local mark = 0.6
	local y = size.Y / 2 + 0.05
	local hx, hz = size.X / 2 - mark, size.Z / 2 - mark
	for _, corner in ipairs({
		Vector3.new(-hx, y, -hz),
		Vector3.new(hx, y, -hz),
		Vector3.new(-hx, y, hz),
		Vector3.new(hx, y, hz),
	}) do
		local stud = Kit.part(
			pad,
			"CornerMark",
			Vector3.new(mark, 0.15, mark),
			cf * CFrame.new(corner),
			color,
			Enum.Material.SmoothPlastic
		)
		Kit.decor(stud)
	end
	local buttonSize = Vector3.new(VehicleLogic.ButtonX, VehicleLogic.ButtonY, VehicleLogic.ButtonZ)
	local button = Kit.part(
		pad,
		"PadButton",
		buttonSize,
		cf * CFrame.new(VehicleLogic.ButtonOffset(size)),
		VehicleLogic.ButtonOrange,
		Enum.Material.SmoothPlastic
	)
	button.CanCollide = false
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PadPrompt"
	prompt.ActionText = "Spawn"
	prompt.ObjectText = "Truck"
	prompt.MaxActivationDistance = 12
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("TapPx", 44)
	local InputKit = require(script.Parent.Parent.InputKit)
	InputKit.PromptDefaults(prompt, "Interact")
	prompt.Parent = button
	pad.PrimaryPart = slab
	pad.Parent = parent
	return pad
end

return DealershipLot
