--!strict
-- HoverTagUI: the price tag over the item you aim at (Connor, 7 October 2026:
-- "just show prices when hovering over an item"). Nothing in the world prints
-- a price any more (box labels, the axe rack, the offer boards and the
-- showroom signs carry names); this draws ONE small tag (name, price, or
-- "Closed" / "You already own this" / "Out of stock") over the item you aim at.
--   * Mouse: the item under the cursor.
--   * Gamepad: the item under the screen-centre aim, the grab's ray, within
--     about 12 studs.
--   * Touch: the item you last tapped, for a few seconds; else the nearest item
--     within about 6 studs in front of you.
-- The rules (which item, the text, one at a time, the cooldown) are Shared/
-- HoverTag and are tested; this file asks Roblox the questions (rays, the
-- camera, the player's attributes) and draws the answer. The tag is a
-- BillboardGui that is depth-tested, never AlwaysOnTop, and follows
-- Shared/TextAnchor: a ray from the camera hides it when a wall is in front of
-- it, and a low ceiling lowers it. Items are anything tagged HoverTag.Tag.
-- Their parts are mostly "decor" (not queryable), so the aim tests their
-- bounding boxes (HoverTag.RayBox) and then asks a real ray whether a wall
-- stands in front: aiming never goes through a wall.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local HoverTag = require(ReplicatedStorage.Shared.HoverTag)
local ShopHoursLogic = require(ReplicatedStorage.Shared.ShopHoursLogic)
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)
local TextAnchor = require(ReplicatedStorage.Shared.TextAnchor)
local UITheme = require(script.Parent.UITheme)

local HoverTagUI = {}

local C = UITheme.Colors
local F = UITheme.Fonts

local player = Players.LocalPlayer

local TICK = 0.1 -- seconds between aim checks (10 a second)
local WIDTH, HEIGHT = 260, 130 -- the billboard; the card sits in its lower middle
local CARD_PX = 64 -- about how tall the card is, for the ceiling check
local PROMPT_CLEAR_PX = 52 -- a Buy / Open card is drawn over the item's middle: keep above it
local AIM_PAD = 0.35 -- studs a bounding box is grown by for aiming
local LIFT = 0.6 -- studs of air between the item's top and the card's tail
local FAR_SKIP = 40 -- studs past the longest aim range: items farther than this are not tested

-- The items, by tagged instance. A model's bounding box is cached unless it
-- is a shop box (they are carried about).
local items: { [Instance]: boolean } = {}
local boxCache: { [Instance]: { cf: CFrame, size: Vector3 } } = {}

local mem = HoverTag.New()
local tapped: { key: string, at: number }? = nil
local shownKey: string? = nil
local shownRoot: Instance? = nil

local gui: BillboardGui? = nil
local nameLabel: TextLabel? = nil
local lineLabel: TextLabel? = nil
local card: Frame? = nil
local hidden = false
local clearChecks = 0
local sinceCheck = 0
local sinceTick = 0
local rayParams: RaycastParams? = nil

local function params(): RaycastParams
	local p = rayParams or RaycastParams.new()
	rayParams = p
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.RespectCanCollide = false
	local skip: { Instance } = {}
	if player.Character then
		table.insert(skip, player.Character)
	end
	if gui then
		table.insert(skip, gui)
	end
	p.FilterDescendantsInstances = skip
	return p
end

---------------------------------------------------------------------------
-- The items
---------------------------------------------------------------------------

local function track(inst: Instance)
	if inst:GetAttribute("HoverKey") ~= nil then
		items[inst] = true
	end
end

local function untrack(inst: Instance)
	items[inst] = nil
	boxCache[inst] = nil
end

-- An item's box in the world: its CFrame and size.
local function boxOf(inst: Instance): (CFrame?, Vector3?)
	if inst:IsA("BasePart") then
		return inst.CFrame, inst.Size
	elseif inst:IsA("Model") then
		local shopBox = CollectionService:HasTag(inst, "ShopBox")
		local cached = boxCache[inst]
		if cached and not shopBox then
			return cached.cf, cached.size
		end
		local ok, cf, size = pcall(function()
			return (inst :: Model):GetBoundingBox()
		end)
		if ok then
			if not shopBox then
				boxCache[inst] = { cf = cf, size = size }
			end
			return cf, size
		end
	end
	return nil, nil
end

-- Items that may show a tag right now (a box already paid for or opened has
-- no price to show).
local function aimable(inst: Instance): boolean
	return inst.Parent ~= nil and inst:GetAttribute("ForSale") ~= false
end

-- The instance the tag sits over, for a key: the one marked as the anchor,
-- else the first found.
local function anchorFor(key: string): Instance?
	local first: Instance? = nil
	for inst in pairs(items) do
		if inst:GetAttribute("HoverKey") == key then
			if inst:GetAttribute("HoverAnchor") == true then
				return inst
			end
			first = first or inst
		end
	end
	return first
end

-- Whether `part` belongs to something carrying `key`.
local function belongsTo(part: Instance, key: string): boolean
	for inst in pairs(items) do
		if inst:GetAttribute("HoverKey") == key and (part == inst or part:IsDescendantOf(inst)) then
			return true
		end
	end
	return false
end

-- Whether a wall (or anything solid that is not the item) lies between `from`
-- and `distance` studs along `dir`.
local function blocked(from: Vector3, dir: Vector3, distance: number, key: string): boolean
	local hit = workspace:Raycast(from, dir.Unit * distance, params())
	if hit == nil then
		return false
	end
	if hit.Distance >= distance - 0.3 then
		return false
	end
	return not belongsTo(hit.Instance, key)
end

---------------------------------------------------------------------------
-- Aiming
---------------------------------------------------------------------------

local function rootPart(): BasePart?
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	return if hrp and hrp:IsA("BasePart") then hrp else nil
end

-- The nearest item along a ray that no wall hides: its key, and the distance
-- from the player to the point on it.
local function aimAlong(ray: Ray, hrp: BasePart?): HoverTag.Candidate?
	local best: HoverTag.Candidate? = nil
	local bestAlong = math.huge
	local reach = HoverTag.MouseRange + FAR_SKIP
	for inst in pairs(items) do
		if not aimable(inst) then
			continue
		end
		local cf, size = boxOf(inst)
		if cf == nil or size == nil then
			continue
		end
		if (cf.Position - ray.Origin).Magnitude > reach + size.Magnitude then
			continue
		end
		local along = HoverTag.RayBox(ray.Origin, ray.Direction.Unit, cf, size, AIM_PAD)
		if along ~= nil and along < bestAlong and along <= reach then
			local key = inst:GetAttribute("HoverKey")
			if type(key) == "string" and not blocked(ray.Origin, ray.Direction, along, key) then
				bestAlong = along
				local point = ray.Origin + ray.Direction.Unit * along
				best = {
					key = key,
					distance = if hrp then (point - hrp.Position).Magnitude else along,
				}
			end
		end
	end
	return best
end

-- Touch: the items about you that nothing hides, with how far in front each is.
local function itemsNear(hrp: BasePart): { HoverTag.Candidate }
	local out: { HoverTag.Candidate } = {}
	local head = hrp.Position + Vector3.new(0, 1.5, 0)
	local look = hrp.CFrame.LookVector
	local seen: { [string]: boolean } = {}
	for inst in pairs(items) do
		if not aimable(inst) then
			continue
		end
		local cf, size = boxOf(inst)
		local key = inst:GetAttribute("HoverKey")
		if cf == nil or size == nil or type(key) ~= "string" or seen[key] then
			continue
		end
		-- The nearest point of the item's box to you, so a wide item counts from its edge.
		local local_ = cf:PointToObjectSpace(hrp.Position)
		local half = size / 2
		local inside = Vector3.new(
			math.clamp(local_.X, -half.X, half.X),
			math.clamp(local_.Y, -half.Y, half.Y),
			math.clamp(local_.Z, -half.Z, half.Z)
		)
		local nearest = cf:PointToWorldSpace(inside)
		local offset = nearest - hrp.Position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local distance = offset.Magnitude
		if distance > HoverTag.TouchRange then
			continue
		end
		local front = if flat.Magnitude < 0.05 then 1 else flat.Unit:Dot(Vector3.new(look.X, 0, look.Z).Unit)
		local toward = cf.Position - head
		if blocked(head, toward, math.max(toward.Magnitude - 0.2, 0.1), key) then
			continue
		end
		seen[key] = true
		table.insert(out, { key = key, distance = distance, front = front })
	end
	return out
end

local function viewerHidden(): boolean
	return player:GetAttribute("TalkOpen") == true
end

---------------------------------------------------------------------------
-- The tag
---------------------------------------------------------------------------

local function build(): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HoverTag"
	billboard.AlwaysOnTop = false -- depth-tested: walls and shelves hide it
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	billboard.Active = false
	billboard.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	billboard.MaxDistance = HoverTag.MouseRange + 20
	billboard.Enabled = false
	local face = UITheme.Card(C.Bark, C.Ink, 3, 12, true)
	face.outer.Name = "Card"
	face.outer.AnchorPoint = Vector2.new(0.5, 1)
	face.outer.Position = UDim2.fromScale(0.5, 1)
	UITheme.padding(face.face, 8, 14, 8, 14)
	UITheme.list(face.face, 2)
	face.outer.Parent = billboard
	local name = UITheme.label(face.face, "", F.Heading, 20, C.Cream)
	name.Name = "Name"
	name.LayoutOrder = 1
	name.Size = UDim2.new()
	name.AutomaticSize = Enum.AutomaticSize.XY
	local line = UITheme.label(face.face, "", F.Black, 18, C.Amber)
	line.Name = "Line"
	line.LayoutOrder = 2
	line.Size = UDim2.new()
	line.AutomaticSize = Enum.AutomaticSize.XY
	nameLabel, lineLabel, card = name, line, face.outer
	billboard.Parent = UITheme.PlayerGui()
	return billboard
end

local function ensureGui(): BillboardGui
	local g = gui
	if g ~= nil and g.Parent ~= nil then
		return g
	end
	local made = build()
	gui = made
	return made
end

local function hide()
	shownKey = nil
	shownRoot = nil
	hidden = false
	clearChecks = 0
	if gui then
		gui.Enabled = false
	end
end

-- What the player already has, for "You already own this".
local function ownedFacts(spec: HoverTag.Spec): boolean
	if spec.kind == "Gear" then
		return ShopLogic.DecodeSet((player:GetAttribute("OwnedGear") :: string?) or "")[spec.itemId] == true
	elseif spec.kind == "Blueprint" then
		return ShopLogic.DecodeSet((player:GetAttribute("Blueprints") :: string?) or "")[spec.itemId] == true
	elseif spec.kind == "Machine" and spec.itemId == "SkyBin" then
		return player:GetAttribute("SkyBinOwned") == true
	end
	return false
end

-- Whether a vehicle's box is on its shelf spot: false when its box exists but
-- is off the plinth (a customer has it), nil when no box is known.
local function vehicleInStock(spec: HoverTag.Spec): boolean?
	if spec.kind ~= "Truck" and spec.kind ~= "Trailer" then
		return nil
	end
	local found: boolean? = nil
	for _, box in ipairs(CollectionService:GetTagged("ShopBox")) do
		if box:GetAttribute("HoverKind") == spec.kind and box:GetAttribute("HoverId") == spec.itemId then
			if box:GetAttribute("OnShelf") == true then
				return true
			end
			found = false
		end
	end
	return found
end

local function hasPrompt(root: Instance): boolean
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("ProximityPrompt") and d.Enabled then
			return true
		end
	end
	return false
end

local function show(key: string)
	local root = anchorFor(key)
	if root == nil then
		hide()
		return
	end
	local spec = HoverTag.SpecOf(root)
	if spec == nil then
		hide()
		return
	end
	local g = ensureGui()
	local facts: HoverTag.Facts = {
		hour = ShopHoursLogic.Now(),
		loop = CoreLoop.Active(),
		owned = ownedFacts(spec),
		inStock = vehicleInStock(spec),
	}
	local name, line = HoverTag.Lines(spec, facts)
	local state = HoverTag.StateOf(spec, facts)
	if nameLabel then
		nameLabel.Text = name
	end
	if lineLabel then
		lineLabel.Text = line
		lineLabel.Visible = line ~= ""
		lineLabel.TextColor3 = if state == "price" then C.Amber else C.Cream
	end
	if shownKey ~= key then
		hidden = false
		clearChecks = 0
	end
	shownKey = key
	shownRoot = root
	local target: BasePart? = nil
	if root:IsA("BasePart") then
		target = root
	elseif root:IsA("Model") then
		-- A model with no primary part: hang the tag on its first part.
		target = root.PrimaryPart or root:FindFirstChildWhichIsA("BasePart", true)
	end
	if target == nil then
		hide()
		return
	end
	g.Adornee = target
	g.Enabled = not hidden
end

-- The tag's place: above the item's top, lowered under a ceiling, and hidden
-- when a wall is between the camera and it (Shared/TextAnchor).
local function placeTag()
	local g, root = gui, shownRoot
	if g == nil or root == nil or shownKey == nil then
		return
	end
	local camera = workspace.CurrentCamera
	local cf, size = boxOf(root)
	if camera == nil or cf == nil or size == nil then
		return
	end
	local adornee = g.Adornee :: BasePart
	-- The tail sits just over the item's top; a low roof brings it down so the
	-- card is not clipped, never lower than just above the item.
	local base = cf.Position + Vector3.new(0, size.Y / 2, 0)
	local up = workspace:Raycast(base, Vector3.new(0, LIFT + TextAnchor.ProbeExtra, 0), params())
	local distance = (camera.CFrame.Position - base).Magnitude
	local cardStuds = TextAnchor.CardStuds(CARD_PX, distance, camera.ViewportSize.Y)
	local lift = TextAnchor.Lift(0, LIFT, if up then up.Distance else nil, cardStuds)
	local tail = base + Vector3.new(0, lift, 0)
	g.StudsOffsetWorldSpace = tail - adornee.Position
	local pixels = if hasPrompt(root) then PROMPT_CLEAR_PX else 0
	if card then
		card.Position = UDim2.new(0.5, 0, 1, -pixels)
	end
	-- A wall between the camera and the tag hides it at once; it returns after
	-- a couple of clear checks.
	local toTag = tail - camera.CFrame.Position
	local wall = workspace:Raycast(camera.CFrame.Position, toTag.Unit * math.max(toTag.Magnitude - 0.4, 0.1), params())
	local occluded = false
	if wall ~= nil then
		occluded = not belongsTo(wall.Instance, shownKey)
	end
	hidden, clearChecks = TextAnchor.NextHidden(hidden, occluded, clearChecks)
	g.Enabled = not hidden
end

---------------------------------------------------------------------------
-- The loop
---------------------------------------------------------------------------

local function wantedKey(now: number): string?
	local camera = workspace.CurrentCamera
	if camera == nil or viewerHidden() then
		return nil
	end
	local device: HoverTag.Device = HoverTag.DeviceOf(UITheme.Device())
	local hrp = rootPart()
	local aim: HoverTag.Aim = { device = device, now = now }
	if device == "mouse" then
		local m = UserInputService:GetMouseLocation()
		aim.hit = aimAlong(camera:ViewportPointToRay(m.X, m.Y), hrp)
	elseif device == "gamepad" then
		local size = camera.ViewportSize
		aim.hit = aimAlong(camera:ViewportPointToRay(size.X / 2, size.Y / 2), hrp)
	else
		aim.tapped = tapped
		aim.near = if hrp then itemsNear(hrp) else {}
	end
	return HoverTag.Choose(aim)
end

local function step(now: number)
	local key = HoverTag.Step(mem, now, wantedKey(now))
	if key == nil then
		if shownKey ~= nil then
			hide()
		end
		return
	end
	show(key)
end

function HoverTagUI.Start()
	for _, inst in ipairs(CollectionService:GetTagged(HoverTag.Tag)) do
		track(inst)
	end
	CollectionService:GetInstanceAddedSignal(HoverTag.Tag):Connect(function(inst: Instance)
		-- Attributes may land just after the tag: look again on the next tick.
		track(inst)
		task.defer(track, inst)
	end)
	CollectionService:GetInstanceRemovedSignal(HoverTag.Tag):Connect(untrack)

	-- Touch: a tap on an item (in the world, not on the HUD) tags it for a few seconds.
	UserInputService.TouchTapInWorld:Connect(function(position: Vector2, processed: boolean)
		if processed then
			return
		end
		local camera = workspace.CurrentCamera
		if camera == nil then
			return
		end
		local hit = aimAlong(camera:ScreenPointToRay(position.X, position.Y), rootPart())
		if hit and hit.distance <= HoverTag.MouseRange then
			tapped = { key = hit.key, at = os.clock() }
		else
			tapped = nil
		end
	end)

	-- Pressing Buy / Open / grab on the tagged item closes its tag for a moment.
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or shownKey == nil then
			return
		end
		local kind = input.UserInputType
		if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonX then
			HoverTag.Dismiss(mem, os.clock())
			tapped = nil
			hide()
		elseif kind == Enum.UserInputType.MouseButton1 then
			-- (A click grabs a box: its tag steps aside until the cooldown ends.)
			HoverTag.Dismiss(mem, os.clock())
			hide()
		end
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		sinceTick += dt
		sinceCheck += dt
		if sinceTick >= TICK then
			sinceTick = 0
			step(os.clock())
		end
		if shownKey ~= nil and sinceCheck >= TextAnchor.CheckSeconds then
			sinceCheck = 0
			placeTag()
		end
	end)
end

return HoverTagUI
