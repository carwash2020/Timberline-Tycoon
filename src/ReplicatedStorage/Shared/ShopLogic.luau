--!strict
-- ShopLogic: what the shop shows and allows, shared by the server (which
-- enforces it) and the client (which draws it). Pure: no Roblox services,
-- so tests can run it outside Studio.
--
-- The v2 core loop (V2_PLAN.md §2c-§2d, Shared/CoreLoop) has its own
-- prices (Price) and texts (DamageTextV2, CutSummary, the *Detail*For
-- pickers); the ladder rules (StatusOf, WhyNot) are the same in both.

local BiomeData = require(script.Parent.BiomeData)
local FieldGuide = require(script.Parent.FieldGuide)
local GameConfig = require(script.Parent.GameConfig)
local ItemCatalog = require(script.Parent.ItemCatalog)
local Util = require(script.Parent.Util)
local WoodData = require(script.Parent.WoodData)

type AxeDef = ItemCatalog.AxeDef
type TruckDef = ItemCatalog.TruckDef
type GearDef = ItemCatalog.GearDef
type TrailerDef = ItemCatalog.TrailerDef

local ShopLogic = {}

-- "buy": the next new axe. "rebuy": owned, can buy another (collections,
-- displays). "starter": the free Rusty Axe. "locked": buy the one before it
-- first. "forged": never sold (the Starfall Axe). "robux": a game pass
-- (the Lux Axe). "full": the player owns GameConfig.MaxOwnedAxes axes already.
export type AxeStatus = "buy" | "rebuy" | "starter" | "locked" | "forged" | "robux" | "full"

-- `owned` is how many of this axe the player has; `ownedTotal` how many
-- axes of any kind.
function ShopLogic.StatusOf(axe: AxeDef, bestTier: number, owned: number, ownedTotal: number): AxeStatus
	if axe.robux then
		return "robux"
	end
	if axe.sold == false then
		return "forged"
	end
	if axe.priceCash <= 0 then
		return "starter"
	end
	if not ItemCatalog.CanBuyAxe(axe.id, bestTier) then
		return "locked"
	end
	if ownedTotal >= GameConfig.MaxOwnedAxes then
		return "full"
	end
	return if owned > 0 then "rebuy" else "buy"
end

-- True if the shop should take the player's money for this status.
function ShopLogic.CanPurchase(status: AxeStatus): boolean
	return status == "buy" or status == "rebuy"
end

-- Why an axe with this status can't be bought (for toasts and the shop
-- screen). Empty for statuses that can be bought.
function ShopLogic.WhyNot(status: AxeStatus, axe: AxeDef, bestTier: number): string
	if status == "locked" then
		local nextAxe = ItemCatalog.NextAxe(bestTier)
		return if nextAxe
			then string.format("Axes are sold in order. Buy the %s first.", nextAxe.displayName)
			else "Axes are sold in order."
	elseif status == "forged" then
		return string.format("The %s is forged in the Aether Isles, not sold.", axe.displayName)
	elseif status == "robux" then
		return string.format("The %s is a Robux exclusive. Open the Store.", axe.displayName)
	elseif status == "starter" then
		return string.format("Everyone starts with the %s. It isn't sold.", axe.displayName)
	elseif status == "full" then
		return string.format("You own %d axes, the most you can carry.", GameConfig.MaxOwnedAxes)
	end
	return ""
end

-- "Fells oak in 3 · birch in 5 · pine in 13": how the axe does on the
-- toughest woods it cuts at a useful pace (at most `maxHits` hits, default
-- 30), up to `count` of them (default 3), weakest wood first.
function ShopLogic.FellSummary(axe: AxeDef, maxHits: number?, count: number?): string
	local limit = maxHits or 30
	local parts: { string } = {}
	local woods = WoodData.All()
	for i = #woods, 1, -1 do
		local wood = woods[i]
		local damage = ItemCatalog.AxeDamage(axe, wood)
		if damage > 0 then
			local hits = math.ceil(wood.treeHP / damage)
			if hits <= limit then
				table.insert(parts, 1, string.format("%s in %d", string.lower(wood.displayName), hits))
				if #parts >= (count or 3) then
					break
				end
			end
		end
	end
	if #parts == 0 then
		return "Too weak for any tree"
	end
	return "Fells " .. table.concat(parts, " · ")
end

-- "150 damage (200 vs. emberwood)": biome bonuses named by the woods that
-- grow there, which is what players see.
function ShopLogic.DamageText(axe: AxeDef): string
	local text = string.format("%d damage", axe.damage)
	local extras: { string } = {}
	for biome, damage in pairs(axe.biomeDamage or {}) do
		local names: { string } = {}
		for _, wood in ipairs(WoodData.All()) do
			if wood.biome == biome then
				table.insert(names, string.lower(wood.displayName))
			end
		end
		table.insert(extras, string.format("%d vs. %s", damage, table.concat(names, "/")))
	end
	table.sort(extras)
	if #extras > 0 then
		text ..= " (" .. table.concat(extras, ", ") .. ")"
	end
	return text
end

---------------------------------------------------------------------------
-- Trucks (the Dealership)
---------------------------------------------------------------------------

-- "buy": not owned yet. "use": owned, switch to it. "inUse": the one you
-- drive now. Nothing is free: a truck you haven't bought is "buy", even
-- when an old price row is 0.
export type TruckStatus = "buy" | "use" | "inUse"

function ShopLogic.TruckStatusOf(truck: TruckDef, owned: { [string]: boolean }, equipped: string): TruckStatus
	if truck.id == equipped and owned[truck.id] then
		return "inUse"
	end
	if owned[truck.id] then
		return "use"
	end
	return "buy"
end

-- Bringing a stuck truck back: 2% of its price in this loop, at least $2.
-- The Rustbucket is free.
function ShopLogic.RespawnFee(truck: TruckDef, loop: number): number
	if truck.id == "Rustbucket" then
		return 0
	end
	return math.max(2, math.floor(ShopLogic.Price(truck, loop) * 0.02))
end

-- "Bed: 12 logs · top speed 30" (plus the catalog note, if any).
function ShopLogic.TruckDetail(truck: TruckDef): string
	local parts = {
		if truck.bedCapacity > 0 then string.format("Bed: %d logs", truck.bedCapacity) else "No bed",
		string.format("top speed %d", truck.topSpeed),
	}
	if truck.note then
		table.insert(parts, truck.note)
	end
	return table.concat(parts, " · ")
end

-- "buy": not owned yet. "hitch": owned, not behind the truck. "hitched":
-- towing now (a second press unhitches it).
export type TrailerStatus = "buy" | "hitch" | "hitched"

function ShopLogic.TrailerStatusOf(trailer: TrailerDef, owned: { [string]: boolean }, hitched: string): TrailerStatus
	if trailer.id == hitched then
		return "hitched"
	end
	return if owned[trailer.id] then "hitch" else "buy"
end

-- "+12 bed space · tows behind any truck with a bed"
function ShopLogic.TrailerDetail(trailer: TrailerDef): string
	return string.format("+%d bed space · tows behind any truck with a bed", trailer.extraCapacity)
end

-- Sets of ids on player attributes: { Pickup = true, Rustbucket = true }
-- <-> "Pickup,Rustbucket".
function ShopLogic.EncodeSet(ids: { string }): string
	local sorted = table.clone(ids)
	table.sort(sorted)
	return table.concat(sorted, ",")
end

function ShopLogic.DecodeSet(text: string): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for id in string.gmatch(text, "%w+") do
		set[id] = true
	end
	return set
end

---------------------------------------------------------------------------
-- Gear (Hearth & Home)
---------------------------------------------------------------------------

-- "buy": not owned yet. "owned": yours for good. "soon": its biome isn't in
-- the world yet, so it isn't sold.
export type GearStatus = "buy" | "owned" | "soon"

function ShopLogic.GearStatusOf(gear: GearDef, owned: { [string]: boolean }): GearStatus
	if owned[gear.id] then
		return "owned"
	end
	if not BiomeData.IsOpen(gear.biome) then
		return "soon"
	end
	return "buy"
end

-- "Walk and chop on the Volcano without burning · for The Volcano"
function ShopLogic.GearDetail(gear: GearDef): string
	local biome = BiomeData.Get(gear.biome)
	local where = if biome then biome.displayName else gear.biome
	if not BiomeData.IsOpen(gear.biome) then
		return string.format("%s · %s is coming soon", gear.effect, where)
	end
	return string.format("%s · for %s", gear.effect, where)
end

---------------------------------------------------------------------------
-- Attributes
---------------------------------------------------------------------------

-- The OwnedAxes player attribute (attributes can't hold tables):
-- { SteelAxe = 2, RustyAxe = 1 } <-> "RustyAxe=1,SteelAxe=2".
function ShopLogic.EncodeOwned(counts: { [string]: number }): string
	local parts: { string } = {}
	for id, n in pairs(counts) do
		if n > 0 then
			table.insert(parts, string.format("%s=%d", id, n))
		end
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

-- Returns the counts and their total. Ignores anything malformed.
function ShopLogic.DecodeOwned(text: string): ({ [string]: number }, number)
	local counts: { [string]: number } = {}
	local total = 0
	for id, n in string.gmatch(text, "(%w+)=(%d+)") do
		local count = tonumber(n) or 0
		counts[id] = (counts[id] or 0) + count
		total += count
	end
	return counts, total
end

---------------------------------------------------------------------------
-- The v2 loop: its own prices and per-hit stats (ItemCatalog's `v2`
-- rows). Pick with the loop that runs (CoreLoop.Active()).
---------------------------------------------------------------------------

-- What an item the shops sell costs in `loop`: an axe, truck or trailer
-- (AxeDef, TruckDef, TrailerDef) its `v2.price` under the v2 loop, and
-- otherwise (v1, or gear, which has one price) its priceCash.
function ShopLogic.Price(item: { priceCash: number }, loop: number): number
	local v2 = (item :: any).v2
	if loop == 2 and type(v2) == "table" and type(v2.price) == "number" then
		return v2.price
	end
	return item.priceCash
end

-- The wood every axe's cut line starts with: the starter forest's.
ShopLogic.ReferenceWood = "oak"

local short = FieldGuide.ShortNumber

-- "0.55 damage · reach 6 studs · 0.73 s a swing", with a specialist's
-- woods after it: "... · emberwood: 7.5 damage, 0.4 s". "" for an axe
-- without v2 stats.
function ShopLogic.DamageTextV2(axe: AxeDef): string
	local v2 = axe.v2
	if not v2 then
		return ""
	end
	local parts = {
		short(v2.damage, 2) .. " damage",
		string.format("reach %s studs", short(v2.range, 1)),
		string.format("%s s a swing", short(v2.cooldown, 2)),
	}
	for _, wood in ipairs(WoodData.All()) do -- WoodData's order, so it reads the same every time
		local vs = if v2.vs then v2.vs[wood.id] else nil
		if vs then
			local bits: { string } = {}
			if vs.damage then
				table.insert(bits, short(vs.damage, 2) .. " damage")
			end
			if vs.cooldown then
				table.insert(bits, short(vs.cooldown, 2) .. " s")
			end
			table.insert(parts, string.format("%s: %s", string.lower(wood.displayName), table.concat(bits, ", ")))
		end
	end
	return table.concat(parts, " · ")
end

local function hitsText(n: number): string
	return string.format("%d hit%s", n, if n == 1 then "" else "s")
end

-- "Cuts an oak trunk in 6 hits · birch in 13": hits through a typical
-- mature trunk (FieldGuide.TrunkHits) of the reference wood, then the
-- woods the axe is a specialist for (its `vs` woods, at any pace), then
-- the toughest other woods growing in the world that it cuts in at most
-- `maxHits` (default FieldGuide.UsefulHitsV2), up to `count` extras in all
-- (default 2), in WoodData's order. "" without v2 stats.
function ShopLogic.CutSummary(axe: AxeDef, maxHits: number?, count: number?): string
	local v2 = axe.v2
	local reference = WoodData.Get(ShopLogic.ReferenceWood)
	if not v2 or not reference then
		return ""
	end
	local referenceHits = FieldGuide.TrunkHits(axe, reference)
	if referenceHits == math.huge then
		return ""
	end
	local limit = maxHits or FieldGuide.UsefulHitsV2
	local room = count or 2
	local picked: { [string]: boolean } = {}
	local woods = WoodData.All()
	local function pick(wood: WoodData.WoodDef): boolean
		if room <= 0 or picked[wood.id] or wood.id == reference.id or not BiomeData.IsOpen(wood.biome) then
			return false
		end
		picked[wood.id] = true
		room -= 1
		return true
	end
	for _, wood in ipairs(woods) do
		if v2.vs and v2.vs[wood.id] and FieldGuide.TrunkHits(axe, wood) < math.huge then
			pick(wood)
		end
	end
	for i = #woods, 1, -1 do
		local wood = woods[i]
		if FieldGuide.TrunkHits(axe, wood) <= limit then
			pick(wood)
		end
	end
	local parts = {
		string.format(
			"Cuts %s trunk in %s",
			Util.article(string.lower(reference.displayName)),
			hitsText(referenceHits)
		),
	}
	for _, wood in ipairs(woods) do
		if picked[wood.id] then
			table.insert(
				parts,
				string.format("%s in %d", string.lower(wood.displayName), FieldGuide.TrunkHits(axe, wood))
			)
		end
	end
	return table.concat(parts, " · ")
end

-- "Bed 10 studs long · top speed 26" (plus the catalog note): v2 beds
-- carry whatever fits, so their size is what counts.
function ShopLogic.TruckDetailV2(truck: TruckDef): string
	local parts = {
		if truck.look.bedLength > 0
			then string.format("Bed %s studs long", short(truck.look.bedLength, 1))
			else "No bed",
		string.format("top speed %d", truck.topSpeed),
	}
	if truck.note then
		table.insert(parts, truck.note)
	end
	return table.concat(parts, " · ")
end

-- "+7-stud bed · tows behind any truck with a bed"
function ShopLogic.TrailerDetailV2(trailer: TrailerDef): string
	return string.format("+%s-stud bed · tows behind any truck with a bed", short(trailer.look.bedLength, 1))
end

-- An axe's shop card text in `loop`: its damage line, then its cut (or
-- fell) line.
function ShopLogic.AxeDetail(axe: AxeDef, loop: number): string
	if loop == 2 and axe.v2 then
		return ShopLogic.DamageTextV2(axe) .. "\n" .. ShopLogic.CutSummary(axe)
	end
	return ShopLogic.DamageText(axe) .. "\n" .. ShopLogic.FellSummary(axe)
end

function ShopLogic.TruckDetailFor(truck: TruckDef, loop: number): string
	return if loop == 2 then ShopLogic.TruckDetailV2(truck) else ShopLogic.TruckDetail(truck)
end

function ShopLogic.TrailerDetailFor(trailer: TrailerDef, loop: number): string
	return if loop == 2 then ShopLogic.TrailerDetailV2(trailer) else ShopLogic.TrailerDetail(trailer)
end

return ShopLogic
