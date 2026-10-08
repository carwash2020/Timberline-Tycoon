--!strict
-- MiningLogic: hit math, tier access, bombs, danger, selling and smelting
-- values, stash limits, and the $/h check against wood. No instances.

local GameConfig = require(script.Parent.Parent.GameConfig)
local OreData = require(script.Parent.OreData)
local PickaxeData = require(script.Parent.PickaxeData)

local MiningLogic = {}

MiningLogic.SwingReach = 10
MiningLogic.BombReach = 8
MiningLogic.BaseSwing = 0.8
MiningLogic.FuseSec = 3
MiningLogic.SealSec = 600
MiningLogic.WarnSec = 20
MiningLogic.RockWarn = 1.5
MiningLogic.RockGap = 20
MiningLogic.Damage = { [2] = 15, [3] = 25 }
MiningLogic.SmeltSec = 3
MiningLogic.CoalBatch = 4
MiningLogic.NoCoalFee = 2
MiningLogic.ChargeCap = 99
MiningLogic.StashCap = 80
MiningLogic.LiveChunks = 40
MiningLogic.CfLen = 12
MiningLogic.StageCap = 0.8
MiningLogic.WalkSpeed = 16
MiningLogic.HitDamage = 2
MiningLogic.DarkLine = "Too dark to mine, bring a light"
MiningLogic.HaulStuds = { [1] = 40, [2] = 70, [3] = 110 }

-- One chamber, the mix the economy model mines. Heartstone is one node.
MiningLogic.Mix = {
	[1] = { { id = "Coal", n = 3 }, { id = "Copper", n = 3 }, { id = "Iron", n = 2 } },
	[2] = { { id = "Silver", n = 3 }, { id = "Gold", n = 2 } },
	[3] = { { id = "TimberOpal", n = 3 }, { id = "Heartstone", n = 1 } },
}

-- Best wood $/h at the stage, from ECONOMY.md's "$/h cap a player" column.
-- Hills: Pine. Snow/volcano: Frostwood (higher than Emberwood). Gloam: Gloamwood.
MiningLogic.WoodIncome = {
	hills = 15232,
	snow = 28677,
	gloam = 7262,
}

local STAGES = {
	{ stage = "hills", tier = 1, wood = "hills" },
	{ stage = "snow", tier = 2, wood = "snow" },
	{ stage = "gloam", tier = 3, wood = "gloam" },
}

export type Node = {
	hp: number,
	broken: boolean,
}

export type StashRow = {
	kind: string,
	ore: string,
	uid: string,
	value: number,
	cf: { number },
}

function MiningLogic.BombPrice(): number
	return GameConfig.DynamitePrice
end

function MiningLogic.WeakLine(pickName: string): string
	local first = string.sub(pickName, 1, 1)
	local article = if string.find("AEIOU", first, 1, true) then "an" else "a"
	return "Needs " .. article .. " " .. pickName
end

function MiningLogic.HasMineLight(lamp: boolean, gear: { string }?): boolean
	if lamp then
		return true
	end
	for _, id in ipairs(gear or {}) do
		if id == "Lantern" then
			return true
		end
	end
	return false
end

-- Why a swing does nothing, or nil when the hit lands.
function MiningLogic.BlockReason(pickLevel: number, hardness: number, tier: number, light: boolean): string?
	if tier >= 3 and not light then
		return MiningLogic.DarkLine
	end
	if pickLevel < hardness then
		return MiningLogic.WeakLine(PickaxeData.NameForLevel(hardness))
	end
	return nil
end

-- One swing. A second call after the node is already broken does not
-- report another break (same-frame double hit).
function MiningLogic.Hit(node: Node, damage: number): string
	if node.broken or node.hp <= 0 then
		return "spent"
	end
	node.hp -= damage
	if node.hp <= 0 then
		node.broken = true
		return "break"
	end
	return "hit"
end

function MiningLogic.SwingReady(last: number, now: number, speed: number): boolean
	local gap = MiningLogic.BaseSwing / math.max(speed, 0.1)
	return now - last >= gap - 1e-6
end

-- First sink wins. A chunk in the chute and the furnace is paid or
-- smelted once, never both.
function MiningLogic.Claim(book: { [string]: string }, uid: string, sink: string): boolean
	if book[uid] ~= nil then
		return false
	end
	book[uid] = sink
	return true
end

function MiningLogic.SellValue(stored: number): number
	if stored ~= stored or stored < 0 then
		return 0
	end
	return math.floor(stored)
end

-- Coal covers CoalBatch chunks. The rest cost NoCoalFee each.
function MiningLogic.SmeltCost(chunks: number, coal: number): (number, number)
	local n = math.max(0, math.floor(chunks))
	local have = math.max(0, math.floor(coal))
	local need = math.ceil(n / MiningLogic.CoalBatch)
	local use = math.min(need, have)
	local covered = use * MiningLogic.CoalBatch
	local pay = math.max(0, n - covered) * MiningLogic.NoCoalFee
	return use, pay
end

export type FuseMem = { [string]: number }

-- Same frame (the token) spends one charge for that player, once.
function MiningLogic.TryFuse(mem: FuseMem, playerKey: string, frame: number, charges: number): boolean
	if charges < 1 then
		return false
	end
	if mem[playerKey] == frame then
		return false
	end
	mem[playerKey] = frame
	return true
end

function MiningLogic.BuyBombs(have: number, cash: number, price: number, n: number): (number, number)
	local ask = math.clamp(math.floor(n), 1, 10)
	local room = MiningLogic.ChargeCap - math.clamp(math.floor(have), 0, MiningLogic.ChargeCap)
	if room <= 0 or price <= 0 or cash < price then
		return 0, 0
	end
	local afford = math.floor(cash / price)
	local bought = math.min(ask, room, afford)
	if bought < 1 then
		return 0, 0
	end
	return bought, bought * price
end

function MiningLogic.RockDamage(tier: number, hardhat: boolean, last: number, now: number): number
	if hardhat or tier < 2 then
		return 0
	end
	if now - last < MiningLogic.RockGap then
		return 0
	end
	return MiningLogic.Damage[tier] or 0
end

export type Carried = { kind: string, uid: string }

-- Death drops carried ore only. Tools stay.
function MiningLogic.DeathDrop(carried: { Carried }): { string }
	local drop: { string } = {}
	for _, item in ipairs(carried) do
		if item.kind == "chunk" or item.kind == "ingot" then
			table.insert(drop, item.uid)
		end
	end
	return drop
end

function MiningLogic.BestFreeLevel(owned: { [string]: boolean }): number
	local best = 1
	for _, pick in ipairs(PickaxeData.Shop()) do
		if owned[pick.id] and pick.level > best then
			best = pick.level
		end
	end
	return best
end

function MiningLogic.BestOwnedLevel(owned: { [string]: boolean }, lux: boolean): number
	local best = MiningLogic.BestFreeLevel(owned)
	local luxPick = PickaxeData.Get(PickaxeData.LuxId)
	if lux and luxPick and luxPick.level > best then
		return luxPick.level
	end
	return best
end

function MiningLogic.BestFreeId(owned: { [string]: boolean }): string
	local id = "RustyPick"
	local level = 0
	for _, pick in ipairs(PickaxeData.Shop()) do
		if owned[pick.id] and pick.level >= level then
			id = pick.id
			level = pick.level
		end
	end
	return id
end

export type PackResult = { kept: { StashRow }, refused: number }

-- Newest rows are the tail. Past the cap is refused with a count.
function MiningLogic.PackStash(rows: { StashRow }, cap: number?): PackResult
	local limit = cap or MiningLogic.StashCap
	local clean: { StashRow } = {}
	for _, row in ipairs(rows) do
		if MiningLogic.RowOk(row) then
			table.insert(clean, row)
		end
	end
	local refused = 0
	if #clean > limit then
		refused = #clean - limit
		local tail: { StashRow } = {}
		for i = refused + 1, #clean do
			table.insert(tail, clean[i])
		end
		clean = tail
	end
	return { kept = clean, refused = refused }
end

function MiningLogic.RowOk(row: StashRow): boolean
	if row.kind ~= "chunk" and row.kind ~= "ingot" then
		return false
	end
	if not OreData.Known(row.ore) then
		return false
	end
	if type(row.uid) ~= "string" or row.uid == "" then
		return false
	end
	if type(row.value) ~= "number" or row.value ~= row.value then
		return false
	end
	if type(row.cf) ~= "table" or #row.cf ~= MiningLogic.CfLen then
		return false
	end
	for _, n in ipairs(row.cf) do
		if type(n) ~= "number" or n ~= n then
			return false
		end
	end
	return true
end

function MiningLogic.FitPlot(incoming: number, placed: number, plotCap: number): (number, number)
	local room = math.max(0, plotCap - math.max(0, placed))
	local allowed = math.min(math.max(0, incoming), room)
	return allowed, math.max(0, incoming) - allowed
end

export type RestoreFlag = { done: boolean }

function MiningLogic.ClaimRestore(flag: RestoreFlag): boolean
	if flag.done then
		return false
	end
	flag.done = true
	return true
end

-- Inside the sealed tier's inner box (the root, not a hand).
function MiningLogic.InBox(pos: Vector3, cf: CFrame, size: Vector3): boolean
	local localPos = cf:PointToObjectSpace(pos)
	local half = size / 2
	return math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z
end

-- The near side of the rubble: just outside the box, toward +Z of the box.
function MiningLogic.CrawlTarget(cf: CFrame, size: Vector3): Vector3
	return cf.Position + cf.LookVector * (size.Z / 2 + 4)
end

---------------------------------------------------------------------------
-- $/h. Supply of one chamber is the ceiling, so a faster pick cannot
-- outrun the respawn. Net value is the better of the chunk and the ingot
-- after the coal it burns.
---------------------------------------------------------------------------

function MiningLogic.NetValue(oreId: string): number
	local ore = OreData.Get(oreId)
	if ore == nil then
		return 0
	end
	local chunk = ore.chunkValue
	if ore.ingotValue == nil then
		return chunk
	end
	local coal = OreData.Get("Coal")
	local coalEach = if coal then coal.chunkValue / MiningLogic.CoalBatch else MiningLogic.NoCoalFee
	return math.max(chunk, ore.ingotValue - coalEach)
end

local function supplyPerHour(oreId: string, count: number): number
	local ore = OreData.Get(oreId)
	if ore == nil or ore.respawnSec <= 0 then
		return 0
	end
	return count * (3600 / ore.respawnSec) * MiningLogic.NetValue(oreId)
end

local function playerPerHour(oreId: string, speed: number): number
	local ore = OreData.Get(oreId)
	if ore == nil then
		return 0
	end
	local hits = math.ceil(ore.hp / MiningLogic.HitDamage)
	local swing = hits * (MiningLogic.BaseSwing / math.max(speed, 0.1))
	local haul = (MiningLogic.HaulStuds[ore.tier] or 40) / MiningLogic.WalkSpeed
	local smelt = if ore.ingotValue ~= nil then MiningLogic.SmeltSec else 0
	local cycle = swing + haul + smelt
	if cycle <= 0 then
		return 0
	end
	return MiningLogic.NetValue(oreId) / cycle * 3600
end

-- Best mining $/h in a tier with this pick: fill the hour with the
-- best-paying ore the pick can break, then the next, never past respawn.
function MiningLogic.Income(tier: number, pickId: string): number
	local pick = PickaxeData.Get(pickId)
	if pick == nil then
		return 0
	end
	local mix = MiningLogic.Mix[tier]
	if mix == nil then
		return 0
	end
	local options = {}
	for _, slot in ipairs(mix) do
		local ore = OreData.Get(slot.id)
		if ore and pick.level >= ore.hardness then
			local player = playerPerHour(slot.id, pick.speed)
			local supply = supplyPerHour(slot.id, slot.n)
			if player > 0 and supply > 0 then
				table.insert(options, { player = player, supply = supply })
			end
		end
	end
	table.sort(options, function(a, b)
		return a.player > b.player
	end)
	local total, left = 0, 1
	for _, opt in ipairs(options) do
		if left <= 1e-9 then
			break
		end
		local share = math.min(left, opt.supply / opt.player)
		total += share * opt.player
		left -= share
	end
	return total
end

export type StageRow = {
	stage: string,
	tier: number,
	pick: string,
	mining: number,
	wood: number,
	ratio: number,
}

function MiningLogic.StageReport(): { StageRow }
	local rows: { StageRow } = {}
	for _, stage in ipairs(STAGES) do
		local wood = MiningLogic.WoodIncome[stage.wood]
		local bestPick = "RustyPick"
		local best = 0
		for _, pick in ipairs(PickaxeData.All()) do
			local rate = MiningLogic.Income(stage.tier, pick.id)
			if rate > best then
				best = rate
				bestPick = pick.id
			end
		end
		table.insert(rows, {
			stage = stage.stage,
			tier = stage.tier,
			pick = bestPick,
			mining = best,
			wood = wood,
			ratio = if wood > 0 then best / wood else 0,
		})
	end
	return rows
end

function MiningLogic.StagesOk(): boolean
	for _, row in ipairs(MiningLogic.StageReport()) do
		if row.ratio > MiningLogic.StageCap + 1e-9 then
			return false
		end
	end
	return true
end

return MiningLogic
