--!strict
-- TreeCosmetics: a gentle seasonal tint on canopies, and on high quality
-- one slow mote on maple and frostwood. The crown is built on the server
-- (TreeArt's crystal cuts). The tint never adds a part. A gloamwood's
-- mushroom ring and a lanternwood's night pods are client dressing, and
-- on low (phones, Shared/QualityBudgets) this adds nothing at all.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NatureArt = require(ReplicatedStorage.Shared.Art.NatureArt)
local TreeArt = require(ReplicatedStorage.Shared.Art.TreeArt)
local QualityBudgets = require(ReplicatedStorage.Shared.QualityBudgets)
local Quality = require(script.Parent.Quality)

local TreeCosmetics = {}

local CANOPY: { [string]: boolean } = { Leaves = true, Frond = true, Facet = true }

-- Weak keys: a tree and its parts leave the world when they stream out, and a
-- strong table kept every one of them (and every canopy part's colour) for
-- the whole session, which is memory a phone does not have.
local function weak(): any
	return setmetatable({}, { __mode = "k" })
end
local baseColor: { [BasePart]: Color3 } = weak()
local remembered: { [BasePart]: boolean } = weak()
local paintedSeason: { [Model]: number } = weak()
local paintedTint: { [Model]: number } = weak()
local accented: { [Model]: boolean } = weak() -- true: it has been looked at, and may carry a SeasonAccent

-- Trees dressed (painted, accented, ringed) in one pass, at most: a season
-- change, or the spawn area's trees arriving, used to repaint every tree
-- in one frame. The rest wait for the next pass (a few a second).
TreeCosmetics.PerPass = 24
local searched: { [Model]: number } = weak() -- passes that found no crown to hang an accent on
local ACCENT_SEARCHES = 5

local function remember(part: BasePart)
	if not remembered[part] then
		baseColor[part] = part.Color
		remembered[part] = true
	end
end

local function paint(tree: Model, season: number, tint: number)
	local woodId = tree:GetAttribute("WoodId")
	if type(woodId) ~= "string" then
		return
	end
	for _, d in ipairs(tree:GetDescendants()) do
		if
			d:IsA("BasePart")
			and CANOPY[d.Name]
			and d.Material ~= Enum.Material.Neon
			and d.Material ~= Enum.Material.Snow
			and d.Material ~= Enum.Material.Wood
		then
			-- Wood facets are the oak's sap knot: leave that heartwood colour.
			remember(d)
			local base = baseColor[d]
			if base then
				d.Color = TreeArt.TintLeaf(base, woodId, season, tint)
			end
		end
	end
end

local function clearAccent(tree: Model)
	-- Only a tree that was looked at can carry one (ensureAccent is the only
	-- maker). This ran GetDescendants on every tree on every pass on phones,
	-- where the accents are off and there is nothing to clear.
	if not accented[tree] then
		return
	end
	for _, d in ipairs(tree:GetDescendants()) do
		if d:IsA("ParticleEmitter") and d.Name == "SeasonAccent" and d:GetAttribute("Cosmetic") == true then
			d:Destroy()
		end
	end
	accented[tree] = nil
end

local function ensureAccent(tree: Model)
	if accented[tree] then
		return
	end
	local woodId = tree:GetAttribute("WoodId")
	local color = if type(woodId) == "string" then TreeArt.AccentColor(woodId) else nil
	if not color then
		accented[tree] = true
		return
	end
	local host: BasePart? = nil
	for _, d in ipairs(tree:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "Leaves" or d.Name == "Facet") and d.Material ~= Enum.Material.Neon then
			host = d
			break
		end
	end
	if not host then
		-- No crown to hang it on (a stump, a dead tree, a crown still streaming
		-- in): look again a few passes, then give up rather than walking this
		-- tree's descendants on every pass for good.
		local tries = (searched[tree] or 0) + 1
		searched[tree] = tries
		if tries >= ACCENT_SEARCHES then
			accented[tree] = true
		end
		return
	end
	local e = Instance.new("ParticleEmitter")
	e.Name = "SeasonAccent"
	e:SetAttribute("Cosmetic", true)
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.55
	e.LightInfluence = 0.4
	e.Rate = 1
	e.Lifetime = NumberRange.new(2.2, 3.6)
	e.Speed = NumberRange.new(0.15, 0.55)
	e.SpreadAngle = Vector2.new(18, 18)
	e.Acceleration = Vector3.new(0, 0.35, 0)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.25, 0.16),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new(0.4)
	e.Parent = host
	accented[tree] = true
end

local function clearNature(tree: Model)
	local ring = tree:FindFirstChild("MushroomRing")
	if ring then
		ring:Destroy()
	end
	local pods = tree:FindFirstChild("LanternPods")
	if pods then
		pods:Destroy()
	end
end

local function dressNature(tree: Model)
	local woodId = tree:GetAttribute("WoodId")
	if woodId == "phantomwood" and not tree:FindFirstChild("MushroomRing") then
		local ring = NatureArt.MushroomRing(tonumber(tree:GetAttribute("Seed")) or 1)
		ring.Name = "MushroomRing"
		ring:PivotTo(tree:GetPivot())
		ring.Parent = tree
	end
	local night = Lighting.ClockTime < 6 or Lighting.ClockTime > 18
	local pods = tree:FindFirstChild("LanternPods")
	if woodId == "lanternwood" and night and not pods then
		local made = NatureArt.LanternPods(tonumber(tree:GetAttribute("Seed")) or 1)
		made.Name = "LanternPods"
		made:PivotTo(tree:GetPivot() * CFrame.new(0, 8, 0))
		made.Parent = tree
	elseif pods and (woodId ~= "lanternwood" or not night) then
		pods:Destroy()
	end
end

-- How many trees it has painted or accented (tests: a tree that has left the
-- world must not be counted, or held, for good).
function TreeCosmetics.Tracked(): number
	local n = 0
	for _ in pairs(paintedSeason) do
		n += 1
	end
	return n
end

-- One pass over the trees streamed in: dresses at most PerPass of them and
-- leaves the rest for the next pass. Returns how many it dressed.
function TreeCosmetics.Pass(trees: { Instance }, look: TreeArt.Cosmetics, season: number): number
	local worked = 0
	for _, inst in ipairs(trees) do
		if worked >= TreeCosmetics.PerPass then
			break
		end
		if inst:IsA("Model") then
			local tree = inst
			local did = false
			if look.tint > 0 then
				if paintedSeason[tree] ~= season or paintedTint[tree] ~= look.tint then
					paint(tree, season, look.tint)
					paintedSeason[tree] = season
					paintedTint[tree] = look.tint
					did = true
				end
			elseif paintedSeason[tree] ~= nil then
				paint(tree, 1, 0)
				paintedSeason[tree] = nil
				paintedTint[tree] = nil
				did = true
			end
			if look.accents then
				if not accented[tree] then
					ensureAccent(tree)
					did = did or accented[tree] == true
				end
			else
				if accented[tree] then
					did = true
				end
				clearAccent(tree)
			end
			if look.tint > 0 then
				dressNature(tree)
			else
				clearNature(tree)
			end
			if did then
				worked += 1
			end
		end
	end
	return worked
end

function TreeCosmetics.Start()
	local since = math.huge
	RunService.Heartbeat:Connect(function(dt: number)
		since += dt
		-- A few times a second. High's cosmetic rate is every frame, and
		-- this is a recolor, not a pose.
		local hz = math.min(Quality.Budget().CosmeticHz, 4)
		if not QualityBudgets.CosmeticDue(hz, since) then
			return
		end
		since = 0
		TreeCosmetics.Pass(
			CollectionService:GetTagged("Tree"),
			TreeArt.Cosmetics(Quality.Budget().Tier),
			TreeArt.SeasonIndex(os.time())
		)
	end)
end

return TreeCosmetics
