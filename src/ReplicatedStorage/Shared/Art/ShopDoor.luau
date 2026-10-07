--!strict
-- ShopDoor: the real front door of a shop. Pure art code. Added by
-- BuildingArt.Shop after the shop is scaled, in final studs, as a child
-- Model named "ShopDoor" holding:
--   leaf parts   looks only (Kit.decor); each carries ClosedCFrame and
--                OpenCFrame attributes, relative to the shop's Counter, and
--                DoorLeaf = true. They are BUILT in the open pose; the client
--                (ShopDoorAnim) snaps them to the shop's DoorOpen attribute
--                and tweens them when it changes.
--   DoorBlock    invisible, anchored; it is what actually stops a player.
--                Its CanCollide is false (open); the server turns it on
--                while the shop is closed (ShopDoorLogic.Locked).
--   DoorSensor   invisible, touch-only, just inside the doorway: a player
--                inside who walks up to a closed door touches it and the
--                server holds the door open (nobody is shut in).
--   DoorClosedSign   a small board over the door; the server writes
--                "Closed - opens at 7 AM" on it while the door is shut.
-- Three styles: "slide" (two barn leaves), "swing" (two hinged leaves) and
-- "roll" (a roll-up shutter of slats).

local Kit = require(script.Parent.Kit)
local ShopDoorLogic = require(script.Parent.Parent.ShopDoorLogic)

local ShopDoor = {}

export type Spec = {
	style: string, -- "slide" | "swing" | "roll"
	x0: number, -- the opening, west and east edge
	x1: number,
	y0: number, -- floor and top of the opening
	y1: number,
	z: number, -- the door plane
	color: Color3, -- the leaves
	trim: Color3,
}

ShopDoor.BlockThick = 1.4
ShopDoor.LeafStep = 0.16 -- studs: the east barn leaf stands this much further out than the west one
ShopDoor.LeafHeightCut = 0.08 -- studs: the west barn leaf is this much shorter

local V3, CF = Vector3.new, CFrame.new
local MAT = Enum.Material

type PartDef = { name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material }

local function addLeaf(parent: Model, reference: CFrame, defs: { PartDef }, closed: CFrame, open: CFrame)
	for _, def in ipairs(defs) do
		local p = Kit.part(parent, def.name, def.size, open * def.offset, def.color, def.material)
		Kit.decor(p, false)
		p:SetAttribute("DoorLeaf", true)
		p:SetAttribute("ClosedCFrame", reference:ToObjectSpace(closed * def.offset))
		p:SetAttribute("OpenCFrame", reference:ToObjectSpace(open * def.offset))
	end
end

-- Faces that look the same way are at least ShopDoor.FaceStep apart, so the
-- engine never has two textures to pick between on one plane (the specs
-- scan for it): the trim is one ring of four pieces that only touch edge to
-- edge, and the two braces stand proud of it at different depths.
ShopDoor.FaceStep = 0.03

local function slideDefs(w: number, h: number, color: Color3, trim: Color3): { PartDef }
	local bar = 0.45
	local defs: { PartDef } = {
		{ name = "BarnDoor", size = V3(w, h, 0.4), offset = CF(), color = color, material = MAT.WoodPlanks },
		{
			name = "DoorTrim",
			size = V3(w - 2 * bar, bar, 0.2),
			offset = CF(0, h / 2 - bar / 2, -0.3),
			color = trim,
			material = MAT.Wood,
		},
		{
			name = "DoorTrim",
			size = V3(w - 2 * bar, bar, 0.2),
			offset = CF(0, -h / 2 + bar / 2, -0.3),
			color = trim,
			material = MAT.Wood,
		},
		{
			name = "DoorTrim",
			size = V3(bar, h, 0.2),
			offset = CF(-w / 2 + bar / 2, 0, -0.3),
			color = trim,
			material = MAT.Wood,
		},
		{
			name = "DoorTrim",
			size = V3(bar, h, 0.2),
			offset = CF(w / 2 - bar / 2, 0, -0.3),
			color = trim,
			material = MAT.Wood,
		},
	}
	local diag = math.sqrt((w - 0.9) ^ 2 + (h - 0.9) ^ 2)
	local tilt = math.atan2(h - 0.9, w - 0.9)
	for i, k in ipairs({ -1, 1 }) do
		-- Each brace is a layer deeper than the last: its face stands proud
		-- of the trim's (-0.4) by FaceStep, then twice that, and its back
		-- sinks into the board on a plane of its own.
		local front = 0.4 + i * ShopDoor.FaceStep
		local back = 0.17 - (i - 1) * ShopDoor.FaceStep
		table.insert(defs, {
			name = "DoorBrace",
			size = V3(diag, 0.4, front - back),
			offset = CF(0, 0, -(front + back) / 2) * CFrame.Angles(0, 0, k * tilt),
			color = trim,
			material = MAT.Wood,
		})
	end
	return defs
end

local function swingDefs(w: number, h: number, color: Color3, trim: Color3, sign: number): { PartDef }
	-- `sign` +1: the hinge is on this leaf's -X edge, -1: on its +X edge.
	return {
		{ name = "DoorLeaf", size = V3(w, h, 0.4), offset = CF(), color = color, material = MAT.WoodPlanks },
		{
			name = "DoorBrace",
			size = V3(w - 0.5, 0.45, 0.2),
			offset = CF(0, h * 0.28, -0.3),
			color = trim,
			material = MAT.Wood,
		},
		{
			name = "DoorBrace",
			size = V3(w - 0.5, 0.45, 0.2),
			offset = CF(0, -h * 0.28, -0.3),
			color = trim,
			material = MAT.Wood,
		},
		{
			name = "DoorKnob",
			size = V3(0.4, 0.4, 0.4),
			offset = CF(sign * (w / 2 - 0.7), 0, -0.4),
			color = Color3.fromRGB(201, 162, 74),
			material = MAT.Metal,
		},
	}
end

function ShopDoor.BlockSize(spec: Spec): Vector3
	return V3(spec.x1 - spec.x0, spec.y1 - spec.y0, ShopDoor.BlockThick)
end

-- Adds the door to `model` (which has a Counter) and returns the Model.
function ShopDoor.Add(model: Model, spec: Spec): Model?
	local counter = model:FindFirstChild("Counter")
	if counter == nil or not counter:IsA("BasePart") then
		return nil
	end
	local reference = counter.CFrame
	local door = Instance.new("Model")
	door.Name = "ShopDoor"
	door:SetAttribute("Style", spec.style)
	local cx = (spec.x0 + spec.x1) / 2
	local width = spec.x1 - spec.x0
	local height = spec.y1 - spec.y0
	local cy = (spec.y0 + spec.y1) / 2
	local z = spec.z

	if spec.style == "slide" then
		local w = width / 2 + 0.3
		local h = height - 0.3
		for _, side in ipairs({ -1, 1 }) do
			-- The two leaves overlap 0.6 stud when shut, so the east one stands
			-- LeafStep further out (never further in: the wall's windows are
			-- behind the open leaves) and the west one is a hair shorter (top
			-- and bottom planes differ too): their boards and trims never
			-- share a plane.
			local lz = if side == 1 then z - ShopDoor.LeafStep else z
			local lh = if side == -1 then h - ShopDoor.LeafHeightCut else h
			local defs = slideDefs(w, lh, spec.color, spec.trim)
			local closed = CF(cx + side * (width / 4 - 0.15), spec.y0 + h / 2 + 0.05, lz)
			local open = CF(cx + side * (width * 3 / 4 + 0.05), spec.y0 + h / 2 + 0.05, lz)
			addLeaf(door, reference, defs, closed, open)
		end
	elseif spec.style == "swing" then
		local w = width / 2
		local h = height - 0.3
		for _, side in ipairs({ -1, 1 }) do
			-- The west leaf (side -1) is hinged at x0, the east at x1; the leaf
			-- extends from its hinge toward the middle.
			local hingeX = if side == -1 then spec.x0 else spec.x1
			local closed = CF(hingeX - side * w / 2, spec.y0 + h / 2 + 0.05, z)
			local about = CF(hingeX, 0, z)
			-- Swung outward (toward -Z): +90 degrees for the west leaf, -90 for the east.
			local open = about * CFrame.Angles(0, -side * math.pi / 2, 0) * about:Inverse() * closed
			addLeaf(door, reference, swingDefs(w, h, spec.color, spec.trim, -side), closed, open)
		end
	else
		-- A roll-up: slats that stack up under the header when it is open.
		local count = 8
		local slat = height / count
		for i = 1, count do
			local closedY = spec.y0 + (i - 0.5) * slat
			local openY = spec.y1 - 0.5 - (count - i) * 0.17
			local defs: { PartDef } = {
				{
					name = "ShutterSlat",
					size = V3(width - 0.3 - 2 * (i - 1) * ShopDoor.FaceStep, slat - 0.06, 0.3), -- each a step narrower: the stack's end caps never share a plane
					offset = CF(),
					color = Kit.shade(spec.color, ((i % 2) - 0.5) * 0.08),
					material = MAT.Metal,
				},
			}
			addLeaf(door, reference, defs, CF(cx, closedY, z), CF(cx, openY, z + (i - 1) * ShopDoor.FaceStep))
		end
	end

	local blockSize = ShopDoor.BlockSize(spec)
	local block = Kit.part(door, "DoorBlock", blockSize, CF(cx, cy, z), spec.trim, MAT.SmoothPlastic)
	block.Transparency = 1
	block.CanCollide = false
	block.CanQuery = false
	block.CanTouch = false
	block.CastShadow = false

	local inset = ShopDoorLogic.SensorInset
	local depth = ShopDoorLogic.SensorDepth
	local sensor = Kit.part(
		door,
		"DoorSensor",
		V3(width - 1, 6, depth),
		CF(cx, spec.y0 + 3, z + ShopDoor.BlockThick / 2 + inset + depth / 2),
		spec.trim,
		MAT.SmoothPlastic
	)
	sensor.Transparency = 1
	sensor.CanCollide = false
	sensor.CanQuery = false
	sensor.CanTouch = true
	sensor.CastShadow = false

	local sign = Kit.part(
		door,
		"DoorClosedSign",
		V3(math.min(5.4, width * 0.4), 1.5, 0.18),
		CF(cx, spec.y0 + 6.6, z - ShopDoor.BlockThick / 2 - 0.15),
		Color3.fromRGB(62, 42, 24),
		MAT.Wood
	)
	Kit.decor(sign, false)
	sign.Transparency = 1
	local labels = Kit.signText(sign, " ", Color3.fromRGB(245, 235, 215), { Enum.NormalId.Front })
	for _, label in ipairs(labels) do
		label.Name = "ClosedText"
		local gui = label.Parent
		if gui and gui:IsA("SurfaceGui") then
			gui.Name = "ClosedGui"
			gui.Enabled = false
		end
	end

	door.Parent = model
	return door
end

return ShopDoor
