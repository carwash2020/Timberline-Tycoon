--!strict
-- RelicData: the four Sky Forge relics (data, rules and the plot trophy
-- model; no services). Deterministic: a relic takes
-- one figured log or plank of its wood plus Sky Shards, and pays its cash
-- reward once per save slot (Designer findings, 1.5x: $22.5k, $37.5k,
-- $60k, $90k). Forged relics light their altar socket (Socket_<id> on
-- BuildingArt.StarfallForge) and stand as a trophy on the owner's plot.

local RelicData = {}

export type Relic = {
	id: string,
	displayName: string,
	woodId: string, -- the figured wood it takes (WoodData id)
	woodName: string,
	shards: number,
	pays: number,
	color: string, -- the trophy's glow, matching the socket
}

RelicData.List = {
	{
		id = "FrostRelic",
		displayName = "Frost Relic",
		woodId = "frostwood",
		woodName = "Frostwood",
		shards = 4,
		pays = 22500,
		color = "#BFE3F2",
	},
	{
		id = "EmberRelic",
		displayName = "Ember Relic",
		woodId = "emberwood",
		woodName = "Emberwood",
		shards = 6,
		pays = 37500,
		color = "#FF7A1A",
	},
	{
		id = "GloamRelic",
		displayName = "Gloam Relic",
		woodId = "phantomwood",
		woodName = "Gloamwood",
		shards = 8,
		pays = 60000,
		color = "#9B7BE0",
	},
	{
		id = "LumenRelic",
		displayName = "Lumen Relic",
		woodId = "lumenwood",
		woodName = "Lumenwood",
		shards = 10,
		pays = 90000,
		color = "#FFE9A8",
	},
} :: { Relic }

local byId: { [string]: Relic } = {}
for _, relic in ipairs(RelicData.List) do
	byId[relic.id] = relic
end

function RelicData.Get(id: string): Relic?
	return byId[id]
end

-- Why the relic can't be forged now, or nil when it can.
function RelicData.Refusal(relic: Relic, owned: { [string]: boolean }, shards: number, figuredNear: number): string?
	if owned[relic.id] then
		return "You already forged the " .. relic.displayName .. "."
	end
	if figuredNear < 1 then
		return "Lay a figured " .. relic.woodName .. " log or plank by the anvil first."
	end
	if shards < relic.shards then
		return string.format("%d more Sky Shards needed.", relic.shards - shards)
	end
	return nil
end

-- "Figured Frostwood + 4 Sky Shards"
function RelicData.CostText(relic: Relic): string
	return string.format("Figured %s + %d Sky Shards", relic.woodName, relic.shards)
end

-- The plot trophies for `ids` (forged relics, in list order): a slate
-- stand with a glowing gem each, in a row to the right of the plot's sign
-- post (`post`, `postHeight` tall), 2.6 studs apart, on its foot. Built
-- from parts, anchored, colliding with nothing. Nil for none.
function RelicData.TrophySpot(post: CFrame, postHeight: number, i: number): CFrame
	local foot = post * CFrame.new(0, -postHeight / 2, 0)
	return foot * CFrame.new(2.4 + (i - 1) * 2.6, 0, 0)
end

function RelicData.Trophies(ids: { string }, post: CFrame, postHeight: number): Model?
	local model = Instance.new("Model")
	model.Name = "RelicTrophies"
	local n = 0
	for _, id in ipairs(ids) do
		local relic = byId[id]
		if relic then
			n += 1
			local spot = RelicData.TrophySpot(post, postHeight, n)
			local stand = Instance.new("Part")
			stand.Name = relic.id .. "Stand"
			stand.Size = Vector3.new(1.4, 1.6, 1.4)
			stand.CFrame = spot * CFrame.new(0, 0.8, 0)
			stand.Material = Enum.Material.Slate
			stand.Color = Color3.fromRGB(88, 92, 104)
			stand.Anchored = true
			stand.CanCollide = false
			stand.CanQuery = false
			stand.Parent = model
			local gem = Instance.new("Part")
			gem.Name = relic.id
			gem.Shape = Enum.PartType.Ball
			gem.Size = Vector3.new(1, 1, 1)
			gem.CFrame = spot * CFrame.new(0, 2.1, 0)
			gem.Material = Enum.Material.Neon
			gem.Color = Color3.fromHex(relic.color)
			gem.Anchored = true
			gem.CanCollide = false
			gem.CanQuery = false
			gem.Parent = model
		end
	end
	if n == 0 then
		model:Destroy()
		return nil
	end
	return model
end

return RelicData
