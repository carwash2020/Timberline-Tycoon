--!strict
-- BlastService: blasting charges on the cracked boulders (WORLD_DESIGN §11;
-- the rules are BlastLogic's). MapBuilder tags each boulder part
-- "Breakable". Every one gets a hold-to-confirm prompt. Setting a charge
-- costs GameConfig.DynamitePrice through EconomyService (checked and taken
-- on the server, in range of that boulder), starts a FuseSec fuse, and
-- then the boulder breaks: an Explosion for the look (BlastPressure 0,
-- no joints broken, nobody hurt) and the part goes (no collision, no
-- query, invisible). After GameConfig.BoulderRespawnSec it comes back, but
-- only when no person and no truck is inside its box; if one is, the
-- server waits RetrySec and tries again, so it never appears inside
-- anyone. There is no carried item: ItemCatalog is gated, so the charge is
-- bought at the boulder.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlastLogic = require(ReplicatedStorage.Shared.BlastLogic)
local InputKit = require(ReplicatedStorage.Shared.InputKit)
local EconomyService = require(script.Parent.EconomyService)
local RateLimiter = require(script.Parent.RateLimiter)

local BlastService = {}

local TAG = "Breakable"

type Boulder = {
	part: BasePart,
	prompt: ProximityPrompt,
	size: Vector3,
	transparency: number,
	state: string, -- "standing", "fused" or "broken"
}

local boulders: { [BasePart]: Boulder } = {}
local notify: (Player, string) -> () = function(_player: Player, _message: string) end

-- Who is in a boulder's way: the people's root parts and every part of a
-- tagged truck. A spec swaps this.
BlastService.Blockers = function(): { BlastLogic.Point }
	local out: { BlastLogic.Point } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
		if root and root:IsA("BasePart") then
			local p = root.CFrame.Position
			table.insert(out, { x = p.X, y = p.Y, z = p.Z })
		end
	end
	for _, model in ipairs(CollectionService:GetTagged("Truck")) do
		if model:IsA("Model") then
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					local p = d.CFrame.Position
					table.insert(out, { x = p.X, y = p.Y, z = p.Z })
				end
			end
		end
	end
	return out
end

local function centreOf(boulder: Boulder): BlastLogic.Point
	local p = boulder.part.CFrame.Position
	return { x = p.X, y = p.Y, z = p.Z }
end

local function sizeOf(boulder: Boulder): BlastLogic.Point
	return { x = boulder.size.X, y = boulder.size.Y, z = boulder.size.Z }
end

local function stand(boulder: Boulder)
	local part = boulder.part
	part.Transparency = boulder.transparency
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = true
	boulder.state = "standing"
	boulder.prompt.Enabled = true
	part:SetAttribute("Broken", false)
end

-- Brings a broken boulder back, waiting out anyone standing where it goes.
function BlastService.Respawn(boulder: Boulder, attempt: number?)
	local tries = attempt or 0
	task.delay(BlastLogic.Delay(tries), function()
		if boulder.state ~= "broken" or not boulder.part.Parent then
			return
		end
		if BlastLogic.Blocked(centreOf(boulder), sizeOf(boulder), BlastService.Blockers()) then
			BlastService.Respawn(boulder, tries + 1)
			return
		end
		stand(boulder)
	end)
end

local function explode(boulder: Boulder)
	local part = boulder.part
	local blast = Instance.new("Explosion")
	blast.Position = part.CFrame.Position
	blast.BlastRadius = BlastLogic.BlastRadius
	blast.BlastPressure = 0 -- looks only: nothing is thrown
	blast.DestroyJointRadiusPercent = 0 -- and nobody comes apart
	blast.ExplosionType = Enum.ExplosionType.NoCraters
	blast.Parent = workspace
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	boulder.state = "broken"
	part:SetAttribute("Broken", true)
end

-- Sets a charge on `part` for `player`. Returns "fused", "gone", "far",
-- "busy" or "short" (nothing charged unless "fused"). `after` is how the
-- fuse is waited out, so a spec can run it at once.
function BlastService.Place(player: Player, part: BasePart, after: ((number, () -> ()) -> ())?): string
	local boulder = boulders[part]
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if not boulder or not part.Parent or not (root and root:IsA("BasePart") and humanoid) or humanoid.Health <= 0 then
		return "gone"
	end
	if not BlastLogic.InRange((root.CFrame.Position - part.CFrame.Position).Magnitude) then
		return "far"
	end
	if boulder.state ~= "standing" then
		notify(player, BlastLogic.BusyText())
		return "busy"
	end
	if not EconomyService.SpendCash(player, BlastLogic.Price(), "blasting charge", "BlastingCharge") then
		notify(player, BlastLogic.ShortText())
		return "short"
	end
	boulder.state = "fused"
	boulder.prompt.Enabled = false
	notify(player, BlastLogic.FuseText())
	local wait: (number, () -> ()) -> () = after
		or function(seconds: number, fn: () -> ())
			task.delay(seconds, fn)
		end
	wait(BlastLogic.FuseSec, function()
		explode(boulder)
		BlastService.Respawn(boulder)
	end)
	return "fused"
end

function BlastService.Bind(part: BasePart)
	if boulders[part] then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BlastPrompt"
	prompt.ActionText = BlastLogic.ActionText()
	prompt.ObjectText = "Cracked boulder"
	prompt.MaxActivationDistance = BlastLogic.PromptRange
	prompt.HoldDuration = 1 -- $220: not a stray tap
	InputKit.PromptDefaults(prompt, "Interact")
	prompt.Parent = part
	boulders[part] = {
		part = part,
		prompt = prompt,
		size = part.Size,
		transparency = part.Transparency,
		state = "standing",
	}
	prompt.Triggered:Connect(function(player: Player)
		if RateLimiter.Allow(player, "Blast") then
			BlastService.Place(player, part)
		end
	end)
end

function BlastService.Init(notifyFn: ((Player, string) -> ())?)
	if notifyFn then
		notify = notifyFn
	end
	for _, tagged in ipairs(CollectionService:GetTagged(TAG)) do
		if tagged:IsA("BasePart") then
			BlastService.Bind(tagged)
		end
	end
	pcall(function()
		CollectionService:GetInstanceAddedSignal(TAG):Connect(function(tagged: Instance)
			if tagged:IsA("BasePart") then
				BlastService.Bind(tagged)
			end
		end)
	end)
end

-- For the tests.
BlastService._boulders = boulders

return BlastService
