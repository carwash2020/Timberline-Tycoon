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

-- A visible-nothing aisle the booth specs can measure. The town stores
-- use ShopBounds.Walk instead, so they grow no invisible part.
local function ensureAisle(model: Model, door: BasePart, counter: BasePart)
	if ShopBounds.Marked(model) then
		return
	end
	local doorAt, counterAt = door.CFrame.Position, counter.CFrame.Position
	local dir = if counterAt.Z >= doorAt.Z then 1 else -1
	local z0 = doorAt.Z + dir * (door.Size.Z / 2 + 0.01)
	local beside = math.abs(counterAt.X - doorAt.X) > door.Size.X * 0.5
	local z1 = if beside then z0 + dir * 10 else counterAt.Z - dir * (counter.Size.Z / 2 + 0.01)
	local length = (z1 - z0) * dir
	if length < ShopBounds.WalkMin then
		length = ShopBounds.WalkMin
		z1 = z0 + dir * length
	end
	local aisle = Kit.part(
		model,
		"AisleClear",
		Vector3.new(ShopBounds.AisleMin, 3.2, length),
		CFrame.new(doorAt.X, 3.6, (z0 + z1) / 2),
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
