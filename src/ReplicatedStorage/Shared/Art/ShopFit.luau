--!strict
-- ShopFit: one warm hero, a honey shelf with seated stock, a timber counter
-- nosing, and (for the booths) an aisle marker. The four town stores get the
-- shelf on the counter they already have. Land Office and Sparkworks are
-- left alone.

local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)
local ShopBounds = require(script.Parent.Parent.World.ShopBounds)
local ShopCounter = require(script.Parent.ShopCounter)
local ShopShelf = require(script.Parent.ShopShelf)

local ShopFit = {}

local DRESS: { [string]: boolean } = {
	ToolShed = true,
	HearthAndHome = true,
	Dealership = true,
	CoatKiosk = true,
	HeatBoots = true,
	OddsAndEnds = true,
	SecretShop = true,
}

local MARK: { [string]: boolean } = {
	CoatKiosk = true,
	HeatBoots = true,
	OddsAndEnds = true,
	SecretShop = true,
}

local function findPart(model: Model, name: string): BasePart?
	local inst = model:FindFirstChild(name, true)
	if inst and inst:IsA("BasePart") then
		return inst
	end
	return nil
end

local function warm(part: BasePart)
	local light = part:FindFirstChildOfClass("PointLight")
	if light == nil then
		local made = Instance.new("PointLight")
		made.Parent = part
		light = made
	end
	assert(light, "hero light")
	light.Color = Palette.LumenGlow
	light.Brightness = 0.9
	light.Range = 12
	light.Shadows = false
end

local function ensureHero(model: Model, counter: BasePart)
	local hero = findPart(model, "Hero")
	if hero == nil then
		local size = Vector3.new(0.5, 1.05, 0.26)
		hero = Kit.decor(
			Kit.part(
				model,
				"Hero",
				size,
				counter.CFrame * CFrame.new(-counter.Size.X / 2 - 0.5, counter.Size.Y / 2 + size.Y / 2, 0),
				Palette.CoinGold,
				Enum.Material.SmoothPlastic
			),
			false
		)
	end
	assert(hero, "hero")
	warm(hero)
end

local function ensureShelf(model: Model, counter: BasePart)
	if model:FindFirstChild("ShopShelf", true) then
		return
	end
	-- Beside the counter, not on its top: the counter's middle stays clear for the sale.
	local wide, deep = 2.2, 0.8
	local top = counter.CFrame * CFrame.new(counter.Size.X / 2 + wide / 2 + 0.3, counter.Size.Y / 2, 0)
	local shelf, board = ShopShelf.Add(model, top, wide, deep)
	local seats: { ShopShelf.Seat } = {
		{
			x = -0.48,
			z = 0,
			size = Vector3.new(0.42, 0.32, 0.36),
			color = Palette.TimberBrown,
			price = "$12",
		},
		{
			x = 0.48,
			z = 0,
			size = Vector3.new(0.42, 0.28, 0.36),
			color = Palette.PlankHoney,
			price = "$8",
		},
	}
	for _, seat in ipairs(seats) do
		ShopShelf.Seat(shelf, board, seat)
	end
end

local function ensureCounter(model: Model, counter: BasePart)
	if model:FindFirstChild("ShopCounter", true) then
		return
	end
	ShopCounter.Add(model, counter)
end

-- AisleClear runs in the door's frame from the inside face to the counter's
-- near face. It does not collide. The town stores have no marker; their
-- walk is ShopBounds.Walk.
local function ensureAisle(model: Model, door: BasePart, counter: BasePart)
	if model:FindFirstChild("AisleClear", true) then
		return
	end
	local rel = door.CFrame:ToObjectSpace(counter.CFrame)
	local sign = if rel.Position.Z >= 0 then 1 else -1
	local zHat = -rel.LookVector
	local half = math.abs(rel.RightVector.Z) * counter.Size.X / 2
		+ math.abs(rel.UpVector.Z) * counter.Size.Y / 2
		+ math.abs(zHat.Z) * counter.Size.Z / 2
	local inside = sign * (door.Size.Z / 2)
	local farZ = rel.Position.Z - sign * half
	local zMid = (inside + farZ) / 2
	local length = math.abs(farZ - inside)
	local y0 = -door.Size.Y / 2 + 0.05
	local y1 = door.Size.Y / 2
	local aisle = Kit.part(
		model,
		"AisleClear",
		Vector3.new(ShopBounds.AisleMin, y1 - y0, length),
		door.CFrame * CFrame.new(0, (y0 + y1) / 2, zMid),
		Palette.SignCream,
		Enum.Material.SmoothPlastic
	)
	aisle.Transparency = 1
	aisle.CanCollide = false
	aisle.CanQuery = false
	aisle.CanTouch = false
	aisle.CastShadow = false
end

function ShopFit.Dress(model: Model, kind: string)
	if not DRESS[kind] then
		return
	end
	local counter = model:FindFirstChild("Counter")
	if counter == nil or not counter:IsA("BasePart") then
		return
	end
	ensureCounter(model, counter)
	ensureShelf(model, counter)
	ensureHero(model, counter)
	if MARK[kind] then
		local door = findPart(model, "DoorBlock") or findPart(model, "DoorOpening")
		if door then
			ensureAisle(model, door, counter)
		end
	end
end

return ShopFit
