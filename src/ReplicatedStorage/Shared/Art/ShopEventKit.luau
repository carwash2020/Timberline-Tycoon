--!strict
-- ShopEventKit: the event expansion room every store can grow into without a
-- rebuild (EVENTS.md). Pure art code (Kit, Instance.new, datatypes), nothing
-- is scaled again. It builds two things, each its own small model that a
-- store's builder drops into its interior:
--
--   ShopEventKit.BuildZone(parent, kind, anchor, size?)   the roped-off floor area
--   ShopEventKit.BuildBanner(parent, kind, anchor, width?) the blank event sign by the door
--
-- and two switches the server uses (StoreEventService), which a spec can
-- also call:
--
--   ShopEventKit.SetZoneActive(zone, active)
--   ShopEventKit.SetBannerActive(board, active, text?)
--
-- THE ZONE. `anchor` is the middle of the zone's floor footprint, ON the
-- floor surface (the y of the floor top), and its -Z side is the open front
-- (where a customer walks up from the aisle); +Z is the back, normally
-- against a wall or a shelf run. `size` is the footprint (x wide, z deep; y
-- ignored); the default is DefaultSize, the least is MinSize. Inside it:
--   EventMat (+ 4 EventMatTrim)         a floor mat in the store's accent
--   3 stanchions + EventLampPost        posts, in the four corners
--   EventRope x3                        the front and both sides: HIDDEN while
--                                       the event is on, so the zone opens
--   EventTablePad1..3                   a rug where each table stands
--   EventTable1..3                      invisible marker parts, each with an
--                                       Attachment "TableAttachment" at the
--                                       middle of the table's top, where the
--                                       shared display table goes (size =
--                                       the footprint to leave free)
-- The model is named "EventExpansion", tagged "EventExpansion", and carries
-- the attributes Store = <kind> and Active = false. About 26 parts.
--
-- Everything in it is looks only (Kit.decor): nothing collides, so a rope can
-- never trap a player or block an aisle. The rope is a visual "closed" sign.
-- The one light stays under the family's caps (ShopKit.Light, never over
-- ShopKit.MaxLightBrightness / MaxLightRange, a warm colour) and is OFF
-- until the zone is active.
--
-- THE BANNER. `anchor` is the middle of the sign's base on the floor, facing
-- -Z (the way a player walks in). Two posts on feet, a crossbar, a blank board
-- named "EventBanner" with a top and bottom rail. The board is tagged
-- "EventBanner" with the attributes Store = <kind>, Active = false, and its
-- text is empty. Hidden (every part invisible) until active; then it shows
-- "COMING SOON" or the event's own text. About 8 parts.

local CollectionService = game:GetService("CollectionService")

local Kit = require(script.Parent.Kit)
local ShopKit = require(script.Parent.ShopKit)
local StoreEvents = require(script.Parent.Parent.StoreEvents)

local ShopEventKit = {}

local V3, CF = Vector3.new, CFrame.new
local MAT = Enum.Material
local hex = Kit.hex

ShopEventKit.ZoneTag = "EventExpansion"
ShopEventKit.BannerTag = "EventBanner"
ShopEventKit.Kinds = StoreEvents.Stores -- ToolShed, HearthAndHome, Sparkworks, Dealership
ShopEventKit.DefaultSize = V3(16, 0, 9) -- the zone's footprint (x, z); y is ignored
ShopEventKit.MinSize = V3(12, 0, 8) -- (the Sparkworks' back corner is 12 wide; its tables come out narrower)
ShopEventKit.TableCount = 3
ShopEventKit.PartBudget = 36 -- the most the zone and banner use together

local MAT_H = 0.1 -- the mat's thickness (everything stands on it)
local EDGE = 0.8 -- how far the corner posts stand in from the footprint edge
local POST_H = 2.4
local ROPE_Y = MAT_H + 2.3
local ROPE_T = 0.12
local TRIM_W = 0.3
local TABLE_MAX_W = 4
local TABLE_D = 2.6

local IRON = hex("#3B3634")
local BRASS = hex("#E3C98A")
local PAD = hex("#F4ECD8")

-- Each store's accent (the mat and rugs), from the family's palette.
local ACCENT: { [string]: Color3 } = {
	ToolShed = hex("#8C6239"),
	HearthAndHome = hex("#9A3D2E"),
	Sparkworks = hex("#2F6B6E"),
	Dealership = hex("#3D4B63"),
}

local function known(kind: string): boolean
	local accent: Color3? = ACCENT[kind]
	return accent ~= nil
end

local function decor(p: Part): Part
	Kit.decor(p, if math.max(p.Size.X, p.Size.Y, p.Size.Z) < 3 then false else nil)
	return p
end

local function box(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): Part
	return decor(Kit.part(parent, name, size, cf, color, mat or MAT.Wood))
end

-- The table footprint (width, depth) and the x of each table's middle, for a
-- zone `sx` wide: three tables in a row against the back, evenly spaced
-- between the side posts.
function ShopEventKit.TableLayout(sx: number, sz: number): { w: number, d: number, xs: { number } }
	local inner = sx - 2 * (EDGE + 0.6)
	local gap = 0.6
	local w = math.min(TABLE_MAX_W, (inner - 4 * gap) / ShopEventKit.TableCount)
	local d = math.min(TABLE_D, sz - 6)
	local spare = (inner - ShopEventKit.TableCount * w) / (ShopEventKit.TableCount + 1)
	local xs: { number } = {}
	for i = 1, ShopEventKit.TableCount do
		xs[i] = -inner / 2 + spare * i + w * (i - 0.5)
	end
	return { w = w, d = d, xs = xs }
end

-- The footprint a zone takes in its anchor's local frame: min and max x and z.
function ShopEventKit.Footprint(size: Vector3?): { minX: number, maxX: number, minZ: number, maxZ: number }
	local s = size or ShopEventKit.DefaultSize
	return { minX = -s.X / 2, maxX = s.X / 2, minZ = -s.Z / 2, maxZ = s.Z / 2 }
end

-- Builds the zone (see the header). Returns the model, which is tagged and
-- inactive. Errors for an unknown store or a footprint under MinSize (or under
-- `minSize`, an optional lower floor for a store whose room has no clear 14 x 8
-- patch: the Tool Shed's tables fill its floor).
function ShopEventKit.BuildZone(
	parent: Instance,
	kind: string,
	anchor: CFrame,
	size: Vector3?,
	minSize: Vector3?
): Model
	assert(known(kind), "ShopEventKit.BuildZone: unknown store " .. tostring(kind))
	local s = size or ShopEventKit.DefaultSize
	local least = minSize or ShopEventKit.MinSize
	assert(s.X >= least.X and s.Z >= least.Z, "ShopEventKit.BuildZone: footprint is under " .. tostring(least))
	local sx, sz = s.X, s.Z
	local accent = ACCENT[kind]
	local model = Kit.model("EventExpansion", parent)
	model:SetAttribute("Store", kind)
	model:SetAttribute("Active", false)
	model:SetAttribute("Footprint", V3(sx, 0, sz))

	local function at(x: number, y: number, z: number): CFrame
		return anchor * CF(x, y, z)
	end

	-- The mat and its edge trim.
	box(model, "EventMat", V3(sx, MAT_H, sz), at(0, MAT_H / 2, 0), accent, MAT.Fabric)
	local trimY = MAT_H + 0.02
	for _, side in ipairs({ -1, 1 }) do
		box(model, "EventMatTrim", V3(sx, 0.04, TRIM_W), at(0, trimY, side * (sz / 2 - TRIM_W / 2)), BRASS, MAT.Fabric)
		box(
			model,
			"EventMatTrim",
			V3(TRIM_W, 0.04, sz - 2 * TRIM_W),
			at(side * (sx / 2 - TRIM_W / 2), trimY, 0),
			BRASS,
			MAT.Fabric
		)
	end

	-- Four corner posts: three stanchions and the lamp post (back right).
	local px, pz = sx / 2 - EDGE, sz / 2 - EDGE
	for _, cx in ipairs({ -1, 1 }) do
		for _, cz in ipairs({ -1, 1 }) do
			local x, z = cx * px, cz * pz
			local lamp = cx == 1 and cz == 1
			local h = if lamp then POST_H + 1.0 else POST_H
			box(model, "EventStanchionBase", V3(0.8, 0.15, 0.8), at(x, MAT_H + 0.075, z), IRON, MAT.Metal)
			box(model, "EventStanchion", V3(0.2, h, 0.2), at(x, MAT_H + 0.15 + h / 2, z), IRON, MAT.Metal)
			if lamp then
				local head = box(
					model,
					"EventLampHead",
					V3(0.6, 0.6, 0.6),
					at(x, MAT_H + 0.15 + h + 0.3, z),
					ShopKit.Light.Color,
					MAT.SmoothPlastic
				)
				local light = Instance.new("PointLight")
				light.Name = "EventLight"
				light.Brightness = math.min(ShopKit.Light.Brightness, ShopKit.MaxLightBrightness)
				light.Range = math.min(ShopKit.Light.Range, ShopKit.MaxLightRange)
				light.Color = ShopKit.Light.Color
				light.Shadows = false
				light.Enabled = false
				light.Parent = head
			else
				box(
					model,
					"EventStanchionCap",
					V3(0.36, 0.3, 0.36),
					at(x, MAT_H + 0.15 + h + 0.15, z),
					BRASS,
					MAT.Metal
				)
			end
		end
	end

	-- The rope: front and both sides, ending flush against the posts.
	local reach = 2 * px - 0.2
	box(model, "EventRope", V3(reach, ROPE_T, ROPE_T), at(0, ROPE_Y, -pz), BRASS, MAT.Fabric)
	local side = 2 * pz - 0.2
	for _, cx in ipairs({ -1, 1 }) do
		box(model, "EventRope", V3(ROPE_T, ROPE_T, side), at(cx * px, ROPE_Y, 0), BRASS, MAT.Fabric)
	end

	-- Three table spots against the back: a rug, an invisible marker, an attachment.
	local layout = ShopEventKit.TableLayout(sx, sz)
	local tz = sz / 2 - 1.5 - layout.d / 2
	for i = 1, ShopEventKit.TableCount do
		local x = layout.xs[i]
		box(
			model,
			"EventTablePad" .. i,
			V3(layout.w + 0.4, 0.04, layout.d + 0.4),
			at(x, MAT_H + 0.02, tz),
			PAD,
			MAT.Fabric
		)
		local marker = decor(
			Kit.part(
				model,
				"EventTable" .. i,
				V3(layout.w, 0.06, layout.d),
				at(x, MAT_H + 0.04 + 0.03, tz),
				accent,
				MAT.SmoothPlastic
			)
		)
		marker.Transparency = 1
		marker:SetAttribute("Slot", i)
		marker:SetAttribute("Store", kind)
		local attach = Instance.new("Attachment")
		attach.Name = "TableAttachment"
		attach.Position = V3(0, 0.03, 0)
		attach.Parent = marker
	end

	pcall(function()
		CollectionService:AddTag(model, ShopEventKit.ZoneTag)
	end)
	ShopEventKit.SetZoneActive(model, false)
	return model
end

-- Opens or closes a zone: the Active attribute, the ropes (hidden while
-- active, so the way in is clear) and the lamp (on while active).
function ShopEventKit.SetZoneActive(zone: Instance, active: boolean)
	zone:SetAttribute("Active", active)
	for _, d in ipairs(zone:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "EventRope" then
			d.Transparency = if active then 1 else 0
		elseif d:IsA("PointLight") and d.Name == "EventLight" then
			d.Enabled = active
		end
	end
end

-- The three table marker parts of a zone, in order (EventTable1..3).
function ShopEventKit.TableMarkers(zone: Instance): { BasePart }
	local out: { BasePart } = {}
	for i = 1, ShopEventKit.TableCount do
		local marker = zone:FindFirstChild("EventTable" .. i)
		if marker and marker:IsA("BasePart") then
			table.insert(out, marker)
		end
	end
	return out
end

-- Builds the banner (see the header). `width` is the board's width (default
-- 4.4, at least 3). Returns the model; the board is its descendant named
-- "EventBanner".
function ShopEventKit.BuildBanner(parent: Instance, kind: string, anchor: CFrame, width: number?): Model
	assert(known(kind), "ShopEventKit.BuildBanner: unknown store " .. tostring(kind))
	local w = math.max(3, width or 4.4)
	local h = 2.0
	local model = Kit.model("EventBannerSign", parent)
	local accent = ACCENT[kind]
	local function at(x: number, y: number, z: number): CFrame
		return anchor * CF(x, y, z)
	end
	local postX = w / 2 + 0.125
	local footH, postTop, boardY = 0.15, 5.9, 4.2
	for _, side in ipairs({ -1, 1 }) do
		box(model, "EventBannerFoot", V3(0.7, footH, 1.6), at(side * postX, footH / 2, 0), IRON, MAT.Metal)
		box(
			model,
			"EventBannerPost",
			V3(0.25, postTop - footH, 0.25),
			at(side * postX, footH + (postTop - footH) / 2, 0),
			ShopKit.Table.timber,
			MAT.Wood
		)
	end
	box(model, "EventBannerCrossbar", V3(w + 0.8, 0.25, 0.3), at(0, postTop + 0.125, 0), ShopKit.Table.timber, MAT.Wood)
	local board = box(model, "EventBanner", V3(w, h, 0.15), at(0, boardY, 0), accent, MAT.Wood)
	box(model, "EventBannerRail", V3(w, 0.15, 0.22), at(0, boardY - h / 2 - 0.075, 0), BRASS, MAT.Metal)
	box(model, "EventBannerRail", V3(w, 0.15, 0.22), at(0, boardY + h / 2 + 0.075, 0), BRASS, MAT.Metal)
	Kit.signText(board, "", hex("#F4ECD8"), { Enum.NormalId.Front })
	board:SetAttribute("Store", kind)
	board:SetAttribute("Active", false)
	board:SetAttribute("Text", "")
	pcall(function()
		CollectionService:AddTag(board, ShopEventKit.BannerTag)
	end)
	ShopEventKit.SetBannerActive(board, false, nil)
	return model
end

-- Shows or hides the banner. Inactive: every part of its sign invisible and
-- the text empty. Active: visible, showing `text` (default "COMING SOON").
function ShopEventKit.SetBannerActive(board: Instance, active: boolean, text: string?)
	local shown = if active then (text or StoreEvents.DefaultBanner) else ""
	if shown == "" and active then
		shown = StoreEvents.DefaultBanner
	end
	board:SetAttribute("Active", active)
	board:SetAttribute("Text", shown)
	local root = board.Parent
	if root then
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") and string.sub(d.Name, 1, 11) == "EventBanner" then
				d.Transparency = if active then 0 else 1
			end
		end
	end
	for _, d in ipairs(board:GetDescendants()) do
		if d:IsA("SurfaceGui") then
			d.Enabled = active
		elseif d:IsA("TextLabel") then
			d.Text = shown
		end
	end
end

return ShopEventKit
