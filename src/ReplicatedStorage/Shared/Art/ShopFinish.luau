--!strict
-- ShopFinish: the last coat on a dressed shop. The town stores already have
-- ceilings, runners and hanging signs from their interiors; here they get the
-- slate threshold and the plank door frames. The four booths have none of it,
-- so they get a plank ceiling, a hanging sign, a runner, wall shelves with
-- stock, peg boards and a door frame. All looks only: nothing here collides.

local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local ShopBounds = require(script.Parent.Parent.World.ShopBounds)

local ShopFinish = {}

local PLANKS = Enum.Material.WoodPlanks
local CEILING = Kit.hex("#C49A63")
local RUNNER = Kit.hex("#8A3B2E")
local RUNNER_EDGE = Kit.hex("#E3C98A")
local SLATE = Kit.hex("#8C877E")
local IRON = Kit.hex("#3B3634")

local SIGN_TEXT: { [string]: string } = {
	CoatKiosk = "COATS",
	HeatBoots = "BOOTS",
	OddsAndEnds = "ODDS & ENDS",
	SecretShop = "SECRET",
}

-- Stock colours for the wall shelves: warm, in the kit's palette.
local STOCK: { Color3 } = {
	Palette.TimberBrown,
	Palette.PlankHoney,
	Palette.SignCream,
	Kit.hex("#963E2C"),
	Kit.hex("#4E7A3E"),
	Kit.hex("#3E5F7A"),
}

local function findPart(model: Model, name: string): BasePart?
	local inst = model:FindFirstChild(name, true)
	if inst and inst:IsA("BasePart") then
		return inst
	end
	return nil
end

local function decor(part: Part, shadow: boolean): Part
	Kit.decor(part, if shadow then nil else false)
	return part
end

-- Lowest y a part reaches (tilt included).
local function lowest(part: BasePart): number
	local cf, s = part.CFrame, part.Size
	local hy = (math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z) / 2
	return cf.Position.Y - hy
end

-- The room, read off the built walls. Booths are built unturned, in model
-- space, so world axes are the shop's own.
type Room = {
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	floorY: number,
	ceilY: number, -- the ceiling board's underside
}

local function roomOf(model: Model, door: BasePart): Room?
	local x1 = math.huge
	local z1 = math.huge
	local roofLow = math.huge
	local doorZ = door.CFrame.Position.Z
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") then
			local p = d.CFrame.Position
			if d.Name == "Wall" and d.Size.X < 1.5 and d.Size.Z > 5 then
				x1 = math.min(x1, math.abs(p.X) - d.Size.X / 2)
			elseif d.Name == "Wall" and d.Size.X > 5 and d.Size.Y > 5 and p.Z > doorZ then
				z1 = math.min(z1, p.Z - d.Size.Z / 2)
			elseif d.Name == "Roof" then
				roofLow = math.min(roofLow, lowest(d))
			end
		end
	end
	if x1 == math.huge or z1 == math.huge or roofLow == math.huge then
		return nil
	end
	return {
		x0 = -x1,
		x1 = x1,
		z0 = doorZ + 0.2,
		z1 = z1,
		floorY = door.CFrame.Position.Y - door.Size.Y / 2,
		ceilY = roofLow - 0.4,
	}
end

local function ceiling(model: Model, room: Room)
	local board = decor(
		Kit.part(
			model,
			"ShopCeiling",
			Vector3.new(room.x1 - room.x0, 0.4, room.z1 - room.z0),
			CFrame.new((room.x0 + room.x1) / 2, room.ceilY + 0.2, (room.z0 + room.z1) / 2),
			CEILING,
			PLANKS
		),
		false
	)
	board.CastShadow = false
end

-- Two chains and a double-faced board over the counter, under the ceiling.
local function hangSign(model: Model, room: Room, counter: BasePart, text: string)
	local w, h, chain = 3.0, 0.7, 0.4
	local at = counter.CFrame.Position
	local x = math.clamp(at.X, room.x0 + w / 2 + 0.4, room.x1 - w / 2 - 0.4)
	local top = room.ceilY
	local y = top - chain - h / 2
	local board = decor(
		Kit.part(
			model,
			"ShopHangSign",
			Vector3.new(w, h, 0.2),
			CFrame.new(x, y, at.Z),
			Palette.SignCream,
			Enum.Material.SmoothPlastic
		),
		false
	)
	Kit.signText(board, text, Palette.SignInk, nil, Enum.Font.FredokaOne, 0.15)
	for _, s in ipairs({ -1, 1 }) do
		decor(
			Kit.part(
				model,
				"ShopSignChain",
				Vector3.new(0.1, chain + 0.05, 0.1),
				CFrame.new(x + s * (w / 2 - 0.3), top - (chain + 0.05) / 2 + 0.05, at.Z),
				IRON,
				Enum.Material.Metal
			),
			false
		)
	end
end

-- A runner from the door's inside face along the walk, edge stripes each side.
local function runner(model: Model, room: Room)
	local walk = ShopBounds.Walk(model)
	if walk == nil then
		return
	end
	local w = 3.6
	local base = walk.cf * CFrame.new(0, -walk.size.Y / 2 + 0.03, 0)
	-- Walk starts a little above the opening's floor; sit on the floor itself.
	local lift = room.floorY + 0.03 - base.Position.Y
	local at = base * CFrame.new(0, lift, 0)
	decor(
		Kit.part(model, "AisleRunner", Vector3.new(w, 0.06, walk.size.Z - 0.4), at, RUNNER, Enum.Material.Fabric),
		false
	)
	for _, s in ipairs({ -1, 1 }) do
		decor(
			Kit.part(
				model,
				"AisleRunnerEdge",
				Vector3.new(0.3, 0.07, walk.size.Z - 0.4),
				at * CFrame.new(s * (w / 2 - 0.4), 0.045, 0),
				RUNNER_EDGE,
				Enum.Material.Fabric
			),
			false
		)
	end
end

-- Two honey shelves on the back wall with stock sitting flush on each board.
local function shelves(model: Model, room: Room, sideGap: { number })
	local x0 = room.x0 + 0.6 + sideGap[1]
	local x1 = room.x1 - 0.6 - sideGap[2]
	local width = x1 - x0
	local depth = 0.5
	local zc = room.z1 - depth / 2
	for row, up in ipairs({ 6.0, 8.2 }) do
		local y = room.floorY + up
		local board = decor(
			Kit.part(
				model,
				"WallShelf",
				Vector3.new(width, 0.25, depth),
				CFrame.new((x0 + x1) / 2, y, zc),
				Palette.PlankHoney,
				PLANKS
			),
			false
		)
		local n = math.max(3, math.floor(width / 1.5))
		local pitch = width / n
		for i = 1, n do
			local hgt = 0.7 + ((i * 7 + row * 3) % 4) * 0.2
			local color = STOCK[((i + row * 2) % #STOCK) + 1]
			decor(
				Kit.part(
					model,
					"WallStock",
					Vector3.new(pitch * 0.7, hgt, depth * 0.8),
					CFrame.new(x0 + pitch * (i - 0.5), y + 0.125 + hgt / 2, zc),
					color,
					PLANKS
				),
				false
			)
		end
		board:SetAttribute("Row", row)
	end
end

-- A peg board flat on each side wall, with a few flat tags hung on it. It
-- stays inside the 4-stud half walk.
local function pegboards(model: Model, room: Room, z0: number, z1: number)
	local len = z1 - z0
	if len < 3 then
		return
	end
	local y = room.floorY + 7.0
	for _, s in ipairs({ -1, 1 }) do
		local wallX = if s < 0 then room.x0 else room.x1
		local x = wallX - s * 0.075
		decor(
			Kit.part(
				model,
				"PegBoard",
				Vector3.new(0.15, 2.4, len),
				CFrame.new(x, y, (z0 + z1) / 2),
				Palette.WeatheredPlank,
				PLANKS
			),
			false
		)
		local n = math.max(2, math.floor(len / 1.6))
		for i = 1, n do
			local color = STOCK[((i + (if s < 0 then 0 else 3)) % #STOCK) + 1]
			decor(
				Kit.part(
					model,
					"PegTag",
					Vector3.new(0.12, 0.9, 0.7),
					CFrame.new(x - s * 0.135, y, z0 + len * (i - 0.5) / n),
					color,
					PLANKS
				),
				false
			)
		end
	end
end

local function doorFinish(model: Model, opening: BasePart)
	local w, h = opening.Size.X, opening.Size.Y
	local frame = opening.CFrame
	local front = -opening.Size.Z / 2 - 0.2
	-- A flush slate sill across the doorway.
	local sill = decor(
		Kit.part(
			model,
			"DoorThreshold",
			Vector3.new(w, 0.12, 0.8),
			frame * CFrame.new(0, -h / 2 + 0.06, 0),
			SLATE,
			Enum.Material.Slate
		),
		false
	)
	sill.CastShadow = false
	-- Plank jambs and a lintel on the outer face of the wall, beside the opening.
	for _, s in ipairs({ -1, 1 }) do
		decor(
			Kit.part(
				model,
				"DoorFrame",
				Vector3.new(0.4, h, 0.24),
				frame * CFrame.new(s * (w / 2 + 0.35), 0, front),
				Palette.TimberBrown,
				PLANKS
			),
			false
		)
	end
	decor(
		Kit.part(
			model,
			"DoorFrame",
			Vector3.new(w + 1.1, 0.5, 0.24),
			frame * CFrame.new(0, h / 2 + 0.25, front),
			Palette.TimberBrown,
			PLANKS
		),
		false
	)
end

-- The town stores' own door finish: slate threshold, plank frame posts.
local function townDoor(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "DoorThreshold" then
				d.Color = SLATE
				d.Material = Enum.Material.Slate
			elseif d.Name == "DoorPost" or d.Name == "DoorFrame" then
				d.Material = PLANKS
			end
		end
	end
end

local BOOTH: { [string]: boolean } = {
	CoatKiosk = true,
	HeatBoots = true,
	OddsAndEnds = true,
	SecretShop = true,
}

function ShopFinish.Apply(model: Model, kind: string)
	if not BOOTH[kind] then
		townDoor(model)
		return
	end
	local opening = findPart(model, "DoorOpening")
	local counter = model:FindFirstChild("Counter")
	if opening == nil or counter == nil or not counter:IsA("BasePart") then
		return
	end
	local room = roomOf(model, opening)
	if room == nil then
		return
	end
	doorFinish(model, opening)
	ceiling(model, room)
	hangSign(model, room, counter, SIGN_TEXT[kind] or kind)
	runner(model, room)
	-- Keep the shelves off the back-room door when the shop has one.
	local gap = { 0, 0 }
	local back = findPart(model, "BackRoomDoor")
	if back then
		local bx = back.CFrame.Position.X
		if bx < 0 then
			gap[1] = bx + back.Size.X / 2 - room.x0 + 0.4
		else
			gap[2] = room.x1 - (bx - back.Size.X / 2) + 0.4
		end
	end
	shelves(model, room, gap)
	-- Peg boards on the side walls, from the door's inside to the shelves.
	pegboards(model, room, room.z0 + 0.5, room.z1 - 1.2)
end

return ShopFinish
