--!strict
-- HoverTag: item prices appear when you AIM at an item, not all the time
-- (Connor, 7 October 2026: "not lose prices, just show prices when hovering
-- over an item"). Pure rules, so the client (HoverTagUI) and the specs agree.
--
--   * Marking: shop art and boxes stamp a few attributes on the thing a
--     player can aim at (HoverTag.Mark): HoverKind and HoverId say WHAT it is
--     (an ItemCatalog / PlotData item), HoverShop which shop's hours apply,
--     HoverName its name. Nothing prints a price on the world any more.
--   * The price is never stored: Price() asks StoreStock.UnitPrice, the same
--     function the server charges with (which goes through ShopLogic.Price:
--     the tier, sale and loop rules). A Robux item carries its R$ text
--     (RobuxShelf.Tag) in HoverRobux, because only Roblox knows that price.
--   * Choose: which item is the target, by device. A mouse: the item under
--     the cursor. A gamepad: the item under the screen-centre aim (the grab's
--     ray) within GamepadRange studs. A touch screen: the item last tapped
--     (for TouchSeconds), else the nearest item within TouchRange studs in
--     front of you.
--   * Lines: the tag's text, with the states a shelf has: Closed (the shop's
--     hours), You already own this, Out of stock.
--   * Step: one tag at a time, with a short hold so the tag does not flicker
--     as the aim crosses a gap, and a cooldown after a dismissal.

local OreData = require(script.Parent.Mining.OreData)
local PickaxeData = require(script.Parent.Mining.PickaxeData)
local ShopHoursLogic = require(script.Parent.ShopHoursLogic)
local StoreStock = require(script.Parent.StoreStock)
local Util = require(script.Parent.Util)

local HoverTag = {}

HoverTag.Tag = "HoverItem" -- CollectionService tag on everything that can show a tag

HoverTag.MouseRange = 60 -- studs, you to the item under the cursor
HoverTag.GamepadRange = 12 -- the grab's aim distance
HoverTag.TouchRange = 6 -- the nearest item in front of you
HoverTag.TouchFront = 0.25 -- "in front": the dot of your facing with the way to it, at least
HoverTag.TouchSeconds = 4 -- how long a tapped item keeps its tag
HoverTag.SwitchDelay = 0.08 -- a new target must hold this long before the tag moves
HoverTag.HideDelay = 0.3 -- a tag stays this long after the aim leaves
HoverTag.DismissCooldown = 1.5 -- a dismissed item does not come back for this long
HoverTag.OreWidth = 220 -- px, the ore card, so two lines stay on screen

export type Device = "mouse" | "gamepad" | "touch"

-- The device from UITheme.Device()'s answer ("phone" is a touch screen,
-- "console" a gamepad, anything else a mouse and keyboard).
function HoverTag.DeviceOf(name: unknown): Device
	if name == "phone" or name == "touch" then
		return "touch"
	elseif name == "console" or name == "pad" or name == "gamepad" then
		return "gamepad"
	end
	return "mouse"
end

---------------------------------------------------------------------------
-- What an aimable thing says about itself
---------------------------------------------------------------------------

export type Spec = {
	key: string, -- unique per thing ("Box:<uid>", "Rack:SteelAxe", "Offer:Gear:Lantern", "Vehicle:Truck:Rustbucket")
	name: string,
	kind: string, -- StoreStock kind: Axe, Gear, Sawmill, Machine, Blueprint, Truck, Trailer, Cosmetic
	itemId: string,
	shop: string?, -- ShopHoursLogic id: its hours decide Closed
	limited: boolean?,
	robux: string?, -- a Robux item's price text; the cash price is then not shown
	anchor: boolean?, -- of several things marked with one key, the one the tag sits over
	tier: number?, -- ore rocks: the mine tier
	need: number?, -- ore rocks: the pick level required (the same for everyone)
}

-- Writes the spec on `inst` as attributes and tags it. (Server and art code;
-- the client reads them with SpecOf.)
function HoverTag.Mark(inst: Instance, spec: Spec)
	inst:SetAttribute("HoverKey", spec.key)
	inst:SetAttribute("HoverName", spec.name)
	inst:SetAttribute("HoverKind", spec.kind)
	inst:SetAttribute("HoverId", spec.itemId)
	inst:SetAttribute("HoverShop", spec.shop)
	inst:SetAttribute("HoverLimited", if spec.limited == true then true else nil)
	inst:SetAttribute("HoverRobux", spec.robux)
	inst:SetAttribute("HoverAnchor", if spec.anchor == true then true else nil)
	if spec.tier ~= nil then
		inst:SetAttribute("HoverTier", spec.tier)
	end
	if spec.need ~= nil then
		inst:SetAttribute("HoverNeed", spec.need)
	end
	pcall(function()
		game:GetService("CollectionService"):AddTag(inst, HoverTag.Tag)
	end)
end

-- Drops the mark so a broken node cannot keep a label. The tag goes too.
function HoverTag.Clear(inst: Instance)
	inst:SetAttribute("HoverKey", nil)
	inst:SetAttribute("HoverName", nil)
	inst:SetAttribute("HoverKind", nil)
	inst:SetAttribute("HoverId", nil)
	inst:SetAttribute("HoverShop", nil)
	inst:SetAttribute("HoverLimited", nil)
	inst:SetAttribute("HoverRobux", nil)
	inst:SetAttribute("HoverAnchor", nil)
	inst:SetAttribute("HoverTier", nil)
	inst:SetAttribute("HoverNeed", nil)
	pcall(function()
		game:GetService("CollectionService"):RemoveTag(inst, HoverTag.Tag)
	end)
end

-- Reads a spec back from an instance's attributes, nil when it has none.
function HoverTag.SpecOf(inst: Instance): Spec?
	local key = inst:GetAttribute("HoverKey")
	local name = inst:GetAttribute("HoverName")
	local kind = inst:GetAttribute("HoverKind")
	local itemId = inst:GetAttribute("HoverId")
	if type(key) ~= "string" or type(name) ~= "string" or type(kind) ~= "string" or type(itemId) ~= "string" then
		return nil
	end
	local shop = inst:GetAttribute("HoverShop")
	local robux = inst:GetAttribute("HoverRobux")
	local tier = inst:GetAttribute("HoverTier")
	local need = inst:GetAttribute("HoverNeed")
	return {
		key = key,
		name = name,
		kind = kind,
		itemId = itemId,
		shop = if type(shop) == "string" then shop else nil,
		limited = inst:GetAttribute("HoverLimited") == true,
		robux = if type(robux) == "string" then robux else nil,
		anchor = inst:GetAttribute("HoverAnchor") == true,
		tier = if type(tier) == "number" then tier else nil,
		need = if type(need) == "number" then need else nil,
	}
end

-- Where a ray first meets a box (a CFrame and a size), as a distance along
-- the ray, or nil when it misses. `pad` grows the box on every side so thin
-- things (a name board, an axe) are easy to aim at. The client aims at
-- things whose parts cannot be queried (decor), so it tests their bounding
-- boxes itself instead of using workspace:Raycast.
function HoverTag.RayBox(origin: Vector3, dir: Vector3, cf: CFrame, size: Vector3, pad: number): number?
	local o = cf:PointToObjectSpace(origin)
	local d = cf:VectorToObjectSpace(dir)
	local half = size / 2 + Vector3.new(pad, pad, pad)
	local tmin, tmax = 0, math.huge
	for _, axis in ipairs({ "X", "Y", "Z" }) do
		local oa = (o :: any)[axis] :: number
		local da = (d :: any)[axis] :: number
		local ha = (half :: any)[axis] :: number
		if math.abs(da) < 1e-9 then
			if oa < -ha or oa > ha then
				return nil
			end
		else
			local t1, t2 = (-ha - oa) / da, (ha - oa) / da
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tmin = math.max(tmin, t1)
			tmax = math.min(tmax, t2)
			if tmin > tmax then
				return nil
			end
		end
	end
	return tmin
end

---------------------------------------------------------------------------
-- The tag's text
---------------------------------------------------------------------------

-- The item's real price: what the server charges (nil for something with no
-- price, which shows its name alone).
function HoverTag.Price(spec: Spec, loop: number): number?
	return StoreStock.UnitPrice(spec.kind, spec.itemId, spec.limited == true, loop)
end

export type Facts = {
	hour: number, -- the clock hour (ShopHoursLogic.Now())
	loop: number, -- the core loop's number (CoreLoop.Active())
	owned: boolean?, -- you already have this item
	inStock: boolean?, -- false: nothing of it is on the shelf right now (nil: unknown, counts as in stock)
	pickLevel: number?, -- best owned pickaxe level (player attribute PickLevel)
}

export type OreStyle = {
	needs: boolean,
	nameColor: Color3?,
}

export type State = "closed" | "owned" | "soldOut" | "price"

HoverTag.OwnedLine = "You already own this"
HoverTag.SoldOutLine = "Out of stock"

function HoverTag.StateOf(spec: Spec, facts: Facts): State
	if spec.shop ~= nil and not ShopHoursLogic.IsOpen(spec.shop, facts.hour) then
		return "closed"
	elseif facts.owned == true then
		return "owned"
	elseif facts.inStock == false then
		return "soldOut"
	end
	return "price"
end

-- Ore rocks: the name, the tier, and the pick the rock requires. "Needs
-- <Pick>" when this player's best owned level is below that. No price.
function HoverTag.OreLines(spec: Spec, facts: Facts): (string, string, OreStyle)
	local ore = OreData.Get(spec.itemId)
	local need = if type(spec.need) == "number" then spec.need else if ore then ore.hardness else 1
	local pickName = PickaxeData.NameForLevel(need)
	local level = if type(facts.pickLevel) == "number" then facts.pickLevel else 0
	local weak = level < need
	-- One second line. "Needs <Pick>" when short. The pick's name (its tier)
	-- when the player can mine it. Never both, and never a price.
	local line = if weak then "Needs " .. pickName else pickName
	return spec.name, line, {
		needs = weak,
		nameColor = if ore then ore.color else nil,
	}
end

-- The tag's two lines: the name, and under it the price or the state.
-- Ore rocks return a third value (colour and the needs flag) and never a price.
function HoverTag.Lines(spec: Spec, facts: Facts): (string, string, OreStyle?)
	if spec.kind == "Ore" then
		return HoverTag.OreLines(spec, facts)
	end
	local state = HoverTag.StateOf(spec, facts)
	if state == "closed" then
		return spec.name, ShopHoursLogic.SignText(spec.shop :: string, facts.hour)
	elseif state == "owned" then
		return spec.name, HoverTag.OwnedLine
	elseif state == "soldOut" then
		return spec.name, HoverTag.SoldOutLine
	end
	if spec.robux ~= nil then
		return spec.name, spec.robux
	end
	local price = HoverTag.Price(spec, facts.loop)
	if price == nil then
		return spec.name, ""
	end
	return spec.name, if price > 0 then Util.formatCash(price) else "FREE"
end

---------------------------------------------------------------------------
-- Which item
---------------------------------------------------------------------------

export type Candidate = {
	key: string,
	distance: number, -- studs from you
	front: number?, -- the dot of your facing with the way to it (touch)
}

export type Aim = {
	device: Device,
	now: number,
	hit: Candidate?, -- the item the cursor / centre aim is on, nil when it is on nothing (or on a wall)
	tapped: { key: string, at: number }?, -- touch: the item last tapped
	near: { Candidate }?, -- touch: the items about you that nothing hides
}

-- The key of the item to tag, or nil.
function HoverTag.Choose(aim: Aim): string?
	if aim.device == "mouse" then
		local hit = aim.hit
		if hit and hit.distance <= HoverTag.MouseRange then
			return hit.key
		end
		return nil
	elseif aim.device == "gamepad" then
		local hit = aim.hit
		if hit and hit.distance <= HoverTag.GamepadRange then
			return hit.key
		end
		return nil
	end
	local tapped = aim.tapped
	if tapped and aim.now - tapped.at < HoverTag.TouchSeconds then
		return tapped.key
	end
	local best: Candidate? = nil
	for _, c in ipairs(aim.near or {}) do
		if c.distance <= HoverTag.TouchRange and (c.front or 0) >= HoverTag.TouchFront then
			if best == nil or c.distance < best.distance then
				best = c
			end
		end
	end
	return if best then best.key else nil
end

---------------------------------------------------------------------------
-- One tag at a time
---------------------------------------------------------------------------

export type Memory = {
	shown: string?, -- the one tag on screen
	since: number, -- when `shown` appeared
	pending: string?, -- a different target waiting to take over
	pendingSince: number,
	lostAt: number?, -- when the aim left `shown`
	dismissed: { [string]: number }, -- key -> when it may show again
}

function HoverTag.New(): Memory
	return { shown = nil, since = 0, pending = nil, pendingSince = 0, lostAt = nil, dismissed = {} }
end

-- Takes the aim's answer (a key or nil) and says which key to show: at most
-- ONE. A new target takes over after SwitchDelay (at once when nothing is
-- shown), a lost one lingers for HideDelay, a dismissed one is skipped until
-- its cooldown ends. Returns the key to show, or nil.
function HoverTag.Step(mem: Memory, now: number, wanted: string?): string?
	if wanted ~= nil then
		local back = mem.dismissed[wanted]
		if back ~= nil then
			if now < back then
				wanted = nil
			else
				mem.dismissed[wanted] = nil
			end
		end
	end
	if wanted == mem.shown then
		mem.pending = nil
		mem.lostAt = nil
		return mem.shown
	end
	if wanted == nil then
		mem.pending = nil
		if mem.shown ~= nil then
			local lost = mem.lostAt or now
			mem.lostAt = lost
			if now - lost >= HoverTag.HideDelay then
				mem.shown = nil
				mem.lostAt = nil
			end
		end
		return mem.shown
	end
	-- A different target.
	mem.lostAt = nil
	if mem.shown == nil then
		mem.shown, mem.since, mem.pending = wanted, now, nil
		return mem.shown
	end
	if mem.pending ~= wanted then
		mem.pending, mem.pendingSince = wanted, now
	end
	if now - mem.pendingSince >= HoverTag.SwitchDelay then
		mem.shown, mem.since, mem.pending = wanted, now, nil
	end
	return mem.shown
end

-- Pulls a projected card back inside the viewport, including the core inset
-- (GuiService:GetGuiInset, the same inset ScreenInsets.CoreUISafeInsets uses).
function HoverTag.ClampScreen(
	x: number,
	y: number,
	viewW: number,
	viewH: number,
	insetX: number,
	insetY: number,
	cardW: number,
	cardH: number
): (number, number)
	local left = insetX + cardW / 2
	local right = math.max(left, viewW - cardW / 2)
	local top = insetY + cardH
	local bottom = math.max(top, viewH - 8)
	return math.clamp(x, left, right), math.clamp(y, top, bottom)
end

-- Hides the tag now and keeps that item's tag away for DismissCooldown
-- (a press on it, a grab, a tap that closed it).
function HoverTag.Dismiss(mem: Memory, now: number)
	local key = mem.shown
	if key ~= nil then
		mem.dismissed[key] = now + HoverTag.DismissCooldown
	end
	mem.shown, mem.pending, mem.lostAt = nil, nil, nil
end

return HoverTag
