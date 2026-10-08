--!strict
-- HermitService: the carved marks, the cave box, the Carved Totem and the
-- Hermit's Maul. The server owns every step:
--   * Five carved marks and the cave box are server-built ProximityPrompts.
--     A press is rate limited, checked against the mark's own position, and
--     sets secretsFound[key] once. The client never sends a key.
--   * All five marks set: secretsFound.CarvedTotem (decor only; no stats,
--     no price, never sold). Checked on every press, on every Hermit talk,
--     and every few seconds, so a profile that loads with five marks and no
--     totem is granted it without another visit.
--   * Talking to the Hermit (the NPC "Talk" prompt NPCService builds) picks a
--     stage from HermitLogic and speaks a card line over the Dialogue
--     remote. With every mark found he gives the Hermit's Maul, once per
--     save slot (profile.questAxe.step 2). A lost Maul is given back.
-- No cash, no Robux, no badge is paid by anything here.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DialogueData = require(ReplicatedStorage.Shared.DialogueData)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local HazardLogic = require(ReplicatedStorage.Shared.HazardLogic)
local HermitLogic = require(ReplicatedStorage.Shared.HermitLogic)
local InputKit = require(ReplicatedStorage.Shared.InputKit)
local NPCData = require(ReplicatedStorage.Shared.NPCData)
local TerrainGen = require(ReplicatedStorage.Shared.World.TerrainGen)
local WorldLayout = require(ReplicatedStorage.Shared.World.WorldLayout)
local RateLimiter = require(script.Parent.RateLimiter)

local HermitService = {}

export type Deps = {
	profile: (Player) -> any,
	notify: (Player, string) -> (),
	say: (Player, string) -> (), -- a card line over the Dialogue remote
	grantAxe: (Player, string) -> (),
	ownsAxe: (Player, string) -> boolean,
}

local SYNC_SEC = 5
local PRESS_SLACK = 4 -- studs past the prompt's reach the server still allows

local deps: Deps? = nil
local started = false
local hooked: { [Instance]: boolean } = {}

function HermitService.SetDeps(value: Deps?)
	deps = value
end

local function rootOf(player: Player): BasePart?
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function secretsOf(profile: any): { [string]: boolean }?
	if type(profile) ~= "table" then
		return nil
	end
	if type(profile.secretsFound) ~= "table" then
		profile.secretsFound = {}
	end
	return profile.secretsFound
end

local function questOf(profile: any): { step: number }
	if type(profile.questAxe) ~= "table" or type(profile.questAxe.step) ~= "number" then
		profile.questAxe = { step = 0 }
	end
	return profile.questAxe
end

-- The Totem: all five marks and no totem yet. Idempotent. Returns whether
-- it was granted just now.
function HermitService.SyncTotem(player: Player): boolean
	local d = deps
	if d == nil then
		return false
	end
	local profile = d.profile(player)
	local secrets = secretsOf(profile)
	if secrets == nil then
		return false
	end
	if HermitLogic.HasAllMarks(secrets) and not HermitLogic.HasTotem(secrets) then
		secrets[HermitLogic.TotemKey] = true
		d.notify(player, DialogueData.HermitLine("totem"))
		return true
	end
	return false
end

-- A press on a mark or the cave box. `key` comes from the prompt's own part,
-- never from a client; the position check is the server's.
function HermitService.Press(player: Player, key: string): boolean
	local d = deps
	if d == nil or not RateLimiter.Allow(player, "SecretPress") then
		return false
	end
	local mark = HermitLogic.MarkByKey(key)
	local spot: { x: number, z: number }? = mark
	if mark == nil and key == HermitLogic.CaveBox.key then
		spot = HermitLogic.CaveBox
	end
	local root = rootOf(player)
	if spot == nil or root == nil then
		return false
	end
	local p = root.CFrame.Position
	if not HermitLogic.Near(p.X, p.Z, spot.x, spot.z, HermitLogic.MarkRadius + PRESS_SLACK) then
		return false
	end
	local profile = d.profile(player)
	local secrets = secretsOf(profile)
	if secrets == nil then
		return false
	end
	if secrets[key] == true then
		d.notify(player, "You've already found this one.")
		return false
	end
	secrets[key] = true
	if mark then
		d.notify(player, DialogueData.HermitLine("mark", HermitLogic.MarkCount(secrets), GameConfig.CarvedMarkCount))
		HermitService.SyncTotem(player)
	else
		d.notify(player, DialogueData.HermitLine("box"))
	end
	return true
end

-- Talk to the Hermit (`model` is his NPC model). Returns the stage spoken.
function HermitService.Talk(player: Player, model: Model): HermitLogic.Stage?
	local d = deps
	if d == nil or not RateLimiter.Allow(player, "HermitTalk") then
		return nil
	end
	local root = rootOf(player)
	local anchor = model.PrimaryPart
	if root == nil or anchor == nil then
		return nil
	end
	local reach = NPCData.TalkDistance + HermitLogic.TalkSlack
	if (root.CFrame.Position - anchor.CFrame.Position).Magnitude > reach then
		d.say(player, DialogueData.HermitLine("far"))
		return nil
	end
	local profile = d.profile(player)
	local secrets = secretsOf(profile)
	if secrets == nil then
		return nil
	end
	HermitService.SyncTotem(player)
	local quest = questOf(profile)
	local stage: HermitLogic.Stage = HermitLogic.StageOf(secrets, quest.step)
	local axeId = GameConfig.QuestAxeId
	if stage == "ready" then
		if not d.ownsAxe(player, axeId) then
			d.grantAxe(player, axeId)
		end
		quest.step = HermitLogic.StepAfter(stage, quest.step)
		d.say(player, DialogueData.HermitLine("ready"))
	elseif stage == "done" then
		if d.ownsAxe(player, axeId) then
			d.say(player, DialogueData.HermitLine("done"))
		else
			d.grantAxe(player, axeId)
			d.say(player, DialogueData.HermitLine("regift"))
		end
	else
		quest.step = HermitLogic.StepAfter(stage, quest.step)
		d.say(
			player,
			if stage == "intro"
				then DialogueData.HermitLine("intro")
				else DialogueData.HermitLine("seeking", HermitLogic.MarkCount(secrets), GameConfig.CarvedMarkCount)
		)
	end
	return stage
end

-- A prompt on an invisible, anchored, non-colliding stone. Part names carry
-- the key; the press handler never trusts a name the client could send.
local function secretPrompt(parent: Instance, key: string, x: number, y: number, z: number, action: string)
	local part = Instance.new("Part")
	part.Name = "Secret_" .. key
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(2, 3, 1)
	part.CFrame = CFrame.new(x, y + 1.5, z)
	part:SetAttribute("SecretKey", key)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Secret"
	prompt.ActionText = action
	prompt.ObjectText = ""
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 8
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.ClickablePrompt = true
	InputKit.PromptDefaults(prompt, "Interact")
	prompt.Parent = part
	pcall(function()
		prompt.Triggered:Connect(function(who: Player)
			HermitService.Press(who, key)
		end)
	end)
	part.Parent = parent
end

function HermitService.BuildSecrets(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Secrets"
	for _, mark in ipairs(HermitLogic.Marks) do
		secretPrompt(folder, mark.key, mark.x, TerrainGen.HeightAt(mark.x, mark.z), mark.z, "Read the carving")
	end
	local box = HermitLogic.CaveBox
	local floorY = TerrainGen.HeightAt(WorldLayout.SecretCave.x, WorldLayout.SecretCave.z) + HazardLogic.CaveFloorTop
	secretPrompt(folder, box.key, box.x, floorY, box.z, "Open the tin")
	folder.Parent = parent
end

-- Put his feet on the cave floor (NPCService stands him on the terrain,
-- which is inside the 2 stud slab) and hook his Talk prompt.
local function hookHermit(model: Model)
	if hooked[model] then
		return
	end
	hooked[model] = true
	local rh = model:GetAttribute("RootHeight")
	local height = if type(rh) == "number" then rh else 3
	local cave = WorldLayout.SecretCave
	local floorY = TerrainGen.HeightAt(cave.x, cave.z) + HazardLogic.CaveFloorTop
	local feetY = model:GetPivot().Position.Y - height
	model:PivotTo(model:GetPivot() + Vector3.new(0, floorY - feetY, 0))
	local talk = model:FindFirstChild("Talk")
	if talk and talk:IsA("ProximityPrompt") then
		pcall(function()
			talk.Triggered:Connect(function(who: Player)
				HermitService.Talk(who, model)
			end)
		end)
	end
end

local function considerNpc(inst: Instance)
	if inst:IsA("Model") and inst:GetAttribute("NPCId") == "Hermit" then
		hookHermit(inst)
	end
end

local function sweepSync()
	for _, player in ipairs(Players:GetPlayers()) do
		HermitService.SyncTotem(player)
	end
end

-- `map` is the TimberlineMap folder. The deps come from GameServer.
function HermitService.Init(value: Deps, map: Instance?)
	if started then
		return
	end
	started = true
	deps = value
	local ok, err = pcall(function()
		if map then
			HermitService.BuildSecrets(map)
		end
		for _, inst in ipairs(CollectionService:GetTagged("NPC")) do
			considerNpc(inst)
		end
		CollectionService:GetInstanceAddedSignal("NPC"):Connect(considerNpc)
	end)
	if not ok then
		warn("[HermitService] " .. tostring(err))
	end
	if type(RunService.IsRunning) == "function" and RunService:IsRunning() then
		task.spawn(function()
			while RunService:IsRunning() do
				task.wait(SYNC_SEC)
				pcall(sweepSync)
			end
		end)
	end
end

return HermitService
