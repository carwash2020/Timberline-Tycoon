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
-- sized by BoxSize from the vehicle's footprint).
--
-- Two rows side-on need more width than the old single row of eight, so
-- the lot (and the reserved lawn in WorldLayout) is wider: it keeps the
-- same west edge and the same depth.

local CollectionService = game:GetService("CollectionService")

local BoxSize = require(script.Parent.Parent.BoxSize)
local CoreLoop = require(script.Parent.Parent.CoreLoop)
local GameConfig = require(script.Parent.Parent.GameConfig)
local ItemCatalog = require(script.Parent.Parent.ItemCatalog)
local Kit = require(script.Parent.Kit)
local ShopLogic = require(script.Parent.Parent.ShopLogic)
local StoreStock = require(script.Parent.Parent.StoreStock)
local TruckArt = require(script.Parent.TruckArt)
local TruckLayout = require(script.Parent.Parent.TruckLayout)
local Util = require(script.Parent.Parent.Util)
local VehicleLogic = require(script.Parent.Parent.VehicleLogic)

local DealershipLot = {}

-- Southwest corner of the lot, inside the reserved lawn (WorldLayout.Reserved
-- DealershipLot). The path occupies z 64 to 70; the bays start at z 70.
DealershipLot.OriginX = 132
DealershipLot.OriginZ = 77.0

-- The hall round the bays (BuildingArt's Dealership): a lobby this wide at
-- the west end with the counter and the door, the bays beside it.
DealershipLot.Lobby = 15.5
DealershipLot.HallWallThick = 0.8
DealershipLot.FloorY = 0.4 -- the hall floor's top (BuildingArt's slab)

-- Studs. A plinth is this much wider than its vehicle on every side, the
-- gap between neighbouring plinths, the walk space at the ends, and so on.
DealershipLot.PlinthMargin = 0.4
DealershipLot.BayGap = 1.5
DealershipLot.SideMargin = 2
DealershipLot.FrontMargin = 0.6
DealershipLot.BoxGap = 0.6 -- between a box and the plinth behind it
DealershipLot.BackMargin = 0
DealershipLot.RowGap = 0.3
DealershipLot.PlinthHeight = 1.2

local ORDER = {
	{ kind = "Truck", id = "Rustbucket" },
	{ kind = "Truck", id = "Pickup" },
	{ kind = "Truck", id = "ScoutATV" },
	{ kind = "Truck", id = "Flatbed" },
	{ kind = "Truck", id = "LoggingRig" },
	{ kind = "Trailer", id = "PonyTrailer" },
	{ kind = "Trailer", id = "RanchTrailer" },
	{ kind = "Trailer", id = "HeavyHauler" },
}

-- The loop the price signs use. MapBuilder publishes CoreLoopActive before
-- it builds the lot, so a Studio override shows here. Tests have no
-- workspace; the configured loop (GameConfig.CoreLoop) is the price then.
local function priceLoop(): number
	local ok, n = pcall(CoreLoop.Active)
	if ok and (n == 1 or n == 2) then
		local published = false
		pcall(function()
			published = workspace:GetAttribute(CoreLoop.ActiveAttribute) ~= nil
		end)
		if published then
			return n
		end
	end
	return if GameConfig.CoreLoop == 2 then 2 else 1
end

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
local measureVehicle: (string, string) -> Measured

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
	box: Vector3, -- the box standing in front
	boxZ: number, -- the box's centre, lot space
	boxClass: string,
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
		local fp = StoreStock.VehicleFootprint(entry.kind, entry.id)
		local class = BoxSize.ClassFor({ kind = entry.kind, footprint = fp })
		local m = measureVehicle(entry.kind, entry.id)
		table.insert(entries, {
			kind = entry.kind,
			id = entry.id,
			length = m.length,
			span = m.span,
			box = class.size,
			boxClass = class.id,
			bay = math.max(m.length, class.size.X) + 2 * DealershipLot.PlinthMargin,
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
		local plinthDepth = maxSpan + 2 * DealershipLot.PlinthMargin
		local rowDepth = maxBox + DealershipLot.BoxGap + plinthDepth + DealershipLot.BackMargin
		local x = -rowWidth(range[1], range[2]) / 2
		for i = range[1], range[2] do
			local e = entries[i]
			table.insert(bays, {
				kind = e.kind,
				id = e.id,
				row = rowIndex,
				x = x + e.bay / 2,
				z = zCursor + maxBox + DealershipLot.BoxGap + plinthDepth / 2,
				width = e.bay,
				depth = plinthDepth,
				length = e.length,
				span = e.span,
				box = e.box,
				boxZ = zCursor + e.box.Z / 2,
				boxClass = e.boxClass,
			})
			x += e.bay + DealershipLot.BayGap
		end
		zCursor += rowDepth + DealershipLot.RowGap
		depth = zCursor - DealershipLot.RowGap
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
		end
	end
end

local function priceOf(kind: string, id: string): string
	local item = itemOf(kind, id)
	if not item then
		return id
	end
	return item.displayName .. "\n" .. Util.formatCash(ShopLogic.Price(item, priceLoop()))
end

local function placeTruck(id: string): Model?
	local def = ItemCatalog.GetTruck(id)
	if not def then
		return nil
	end
	local model = TruckArt.Build(def)
	prep(model, "Truck", id)
	return model
end

local function placeTrailer(id: string): Model?
	local def = ItemCatalog.GetTrailer(id)
	local truck = ItemCatalog.GetTruck("Pickup")
	if not def or not truck then
		return nil
	end
	local lay = TruckLayout.ForTrailer(def, TruckLayout.For(truck))
	local model = Instance.new("Model")
	model.Name = id
	TruckArt.AddTrailer(model, def, lay)
	-- Nose (the hitch) toward -Z, centred on the pivot, same as a truck.
	model:PivotTo(CFrame.new(0, 0, -(lay.hitchZ + lay.length / 2)))
	prep(model, "Trailer", id)
	return model
end

local function paintOf(kind: string, id: string): Color3
	local item = itemOf(kind, id)
	if item and item.look and type(item.look.color) == "string" then
		return Color3.fromHex(item.look.color)
	end
	return Color3.fromRGB(150, 150, 150)
end

local function modelOf(kind: string, id: string): Model?
	return if kind == "Truck" then placeTruck(id) else placeTrailer(id)
end

measureVehicle = function(kind: string, id: string): Measured
	measuring = true
	local model = modelOf(kind, id)
	measuring = false
	if model == nil then
		return { length = 20, span = 10, cx = 0, cz = 0, feet = 2 }
	end
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
	model:Destroy()
	return { length = hi.Z - lo.Z, span = hi.X - lo.X, cx = (hi.X + lo.X) / 2, cz = (hi.Z + lo.Z) / 2, feet = -lo.Y }
end

-- The lot around the origin, front (-Z) toward the path. Place it with
-- Kit.placeAt. Returns the model; each vehicle is a child model.
function DealershipLot.Build(): Model
	local layout = DealershipLot.Layout()
	local depth = layout.depth
	local lot = Instance.new("Model")
	lot.Name = "DealershipLot"
	local top = DealershipLot.PlinthHeight
	local oz = -depth / 2
	for _, bay in ipairs(layout.bays) do
		local cx, cz = bay.x, oz + bay.z
		local color = paintOf(bay.kind, bay.id)

		-- The plinth: a slab you can walk up onto, a stripe of the vehicle's
		-- paint along its front edge, a lamp post at the back corner.
		local slab = Kit.part(
			lot,
			"Plinth",
			Vector3.new(bay.width, top, bay.depth),
			CFrame.new(cx, top / 2, cz),
			Color3.fromRGB(150, 146, 138),
			Enum.Material.Concrete
		)
		slab:SetAttribute("ItemId", bay.id)
		local stripe = Kit.part(
			lot,
			"PlinthStripe",
			Vector3.new(bay.width - 0.6, 0.12, 0.6),
			CFrame.new(cx, top + 0.06, cz - bay.depth / 2 + 0.5),
			color,
			Enum.Material.SmoothPlastic
		)
		Kit.decor(stripe, false)
		local postX, postZ = cx - bay.width / 2 + 0.7, cz + bay.depth / 2 - 0.7
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
		Kit.lantern(lot, CFrame.new(postX, top + 7.8, postZ), 1.2)

		local model = modelOf(bay.kind, bay.id)
		if model then
			model.Parent = lot
			-- Side-on, nose toward the approach (west), on the plinth: its
			-- measured middle over the plinth's middle, its feet on the top.
			local m = measureVehicle(bay.kind, bay.id)
			model:PivotTo(
				CFrame.new(cx, top + m.feet, cz) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.new(-m.cx, 0, -m.cz)
			)
			-- The sign at the plinth's front-right corner, in front of the vehicle.
			local sign = Kit.part(
				model,
				"PriceSign",
				Vector3.new(4.2, 2.2, 0.3),
				CFrame.new(cx + bay.width / 2 - 2.6, top + 1.3, cz - bay.depth / 2 + 1.4),
				Color3.fromRGB(62, 42, 24),
				Enum.Material.Wood
			)
			Kit.decor(sign, false)
			Kit.signText(
				sign,
				priceOf(bay.kind, bay.id),
				Color3.fromRGB(245, 235, 215),
				{ Enum.NormalId.Front, Enum.NormalId.Back }
			)
		end

		-- The box: what you pick up and carry to the counter. In front of
		-- the vehicle, on the ground.
		local spot = Kit.part(
			lot,
			"BoxSpot",
			bay.box,
			CFrame.new(cx, bay.box.Y / 2, oz + bay.boxZ),
			Color3.fromRGB(196, 148, 90),
			Enum.Material.Wood
		)
		spot.CanCollide = false
		spot.CanQuery = false
		spot.CanTouch = false
		spot.Transparency = 1
		spot:SetAttribute("ItemId", bay.id)
		spot:SetAttribute("Category", bay.kind)
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
