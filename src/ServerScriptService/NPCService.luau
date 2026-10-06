--!strict
-- NPCService: the townsfolk (Shared/NPCData; models from Art/CharacterArt).
-- Init(mapFolder) runs once the whole world is built, so it can find the
-- shop Counters, the sell zone and the gondola station to stand beside.
--
--   * Murph: a Persistent Model "Murph" directly under TimberlineMap
--     (QuestUI clones his Head, Beard, Beanie, Torso, LeftArm, RightArm
--     for its portrait; QuestUI.luau waits on map:WaitForChild("Murph")).
--   * Everyone else: Atomic models in a Folder "Townsfolk" under
--     TimberlineMap (each streams in whole, so a client never sees half a
--     person).
--   * Every NPC model is tagged "NPC" with attributes NPCId (and, from
--     CharacterArt, RootHeight). NPCController animates them on each
--     client (breathing, blinking, looking at you, waving, speech bubbles).
--   * Walkers: the server never moves them. They start at their route's
--     first waypoint; attributes Route (NPCData.EncodeRoute), Speed and
--     RouteOffset let every client place them from the shared server clock
--     (NPCData.RouteState), so all players see the same stroll for free.
--     Walkers don't collide (they'd shove players about); the others
--     block like a person would.
--   * Every NPC carries a Talk prompt on the model (E / ButtonX, clickable,
--     no line-of-sight check) so it arrives with the Atomic or Persistent
--     model. The client never WaitForChilds it. Animation and bubbles stay
--     on the client. Shop hours are applied here: a closed keeper lies
--     behind the counter, the door leaf changes colour, and the hours
--     sign is rewritten. The server decides the lock.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BuildingArt = require(ReplicatedStorage.Shared.Art.BuildingArt)
local CharacterArt = require(ReplicatedStorage.Shared.Art.CharacterArt)
local DialogueData = require(ReplicatedStorage.Shared.DialogueData)
local InputKit = require(ReplicatedStorage.Shared.InputKit)
local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local NPCData = require(ReplicatedStorage.Shared.NPCData)
local ShopDoorLogic = require(ReplicatedStorage.Shared.ShopDoorLogic)
local ShopHoursLogic = require(ReplicatedStorage.Shared.ShopHoursLogic)
local TerrainGen = require(ReplicatedStorage.Shared.World.TerrainGen)
local TerrainBuilder = require(script.Parent.TerrainBuilder)

local NPCService = {}

-- A part's CFrame and Size, looked up by model name (anywhere under the
-- map) and part name (a direct child of that model).
local function finder(map: Instance): (string, string) -> (CFrame?, Vector3?)
	return function(modelName: string, partName: string): (CFrame?, Vector3?)
		local model = map:FindFirstChild(modelName) or map:FindFirstChild(modelName, true)
		local part = if model then model:FindFirstChild(partName) else nil
		if part and part:IsA("BasePart") then
			return part.CFrame, part.Size
		end
		return nil, nil
	end
end

local function build(npc: NPCData.NPC, find: (string, string) -> (CFrame?, Vector3?)): Model
	local model = CharacterArt.Build(npc.look)
	model.Name = npc.id
	model:SetAttribute("NPCId", npc.id)
	local spot = npc.spot
	if spot.kind == "counter" or spot.kind == "beside" then
		local partName = if spot.kind == "counter" then "Counter" else spot.part or ""
		if not find(spot.model or "", partName) then
			warn(
				string.format(
					"[NPCService] %s: no %s.%s, standing at the fallback spot",
					npc.id,
					spot.model or "?",
					partName
				)
			)
		end
	end
	local feet = NPCData.SpotFor(npc, find)
	-- Out in the world (the toll booth, the ferry dock) the ground is not
	-- y = 0: stand on the terrain at the spot, plus the booth floor or dock
	-- deck the spot says it stands on.
	local rise = spot.ground
	if rise then
		local at = feet.Position
		feet += Vector3.new(0, TerrainGen.HeightAt(at.X, at.Z) + rise - at.Y, 0)
	end
	-- Never buried: if the ground is drawn above their feet, stand on it.
	local p = feet.Position
	local lifted = TerrainBuilder.LiftOnto(p.X, p.Y, p.Z)
	if lifted ~= p.Y then
		feet += Vector3.new(0, lifted - p.Y, 0)
	end
	Kit.placeAt(model, feet)
	local root = model.PrimaryPart
	if npc.route and root then
		model:SetAttribute("Route", NPCData.EncodeRoute(npc.route))
		model:SetAttribute("Speed", npc.speed or 4)
		model:SetAttribute("RouteOffset", NPCData.RouteOffset(npc.id))
		root.CanCollide = false
	end
	if npc.work then
		model:SetAttribute("Work", npc.work)
	end
	-- On the model, not the Torso: QuestUI clones the Torso for Murph's
	-- portrait, and a prompt in that clone would talk from a ViewportFrame.
	-- PromptUI adorns the PrimaryPart when the parent is a Model.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Talk"
	prompt.ActionText = "Talk"
	prompt.ObjectText = npc.name
	prompt.MaxActivationDistance = NPCData.TalkDistance
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true
	prompt.KeyboardKeyCode = NPCData.TalkKeyboard
	prompt.GamepadKeyCode = NPCData.TalkGamepad
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	local lift = npc.promptLift
	if lift and lift ~= 0 then
		prompt.UIOffset = Vector2.new(0, lift)
	end
	prompt.Parent = model
	CollectionService:AddTag(model, "NPC")
	return model
end

-- Standing CFrame, remembered before the first time a keeper lies down.
local homes: { [Model]: CFrame? } = {}
local doorHooked: { [Instance]: boolean } = {}

local function findNpc(map: Instance, id: string): Model?
	local direct = map:FindFirstChild(id)
	if direct and direct:IsA("Model") then
		return direct
	end
	local folder = map:FindFirstChild("Townsfolk")
	local nested = if folder then folder:FindFirstChild(id) else nil
	if nested and nested:IsA("Model") then
		return nested
	end
	return nil
end

local function frontAlong(model: Instance, counter: BasePart): number
	local look = counter.CFrame.LookVector
	local origin = counter.CFrame.Position
	local doorAt = -math.huge
	local function consider(part: BasePart)
		-- Looks-only dressing out front (awnings, planters, signs, the doormat)
		-- is not the front face; the door's own block still counts.
		if not part.CanCollide and part.Name ~= "DoorBlock" and part ~= counter then
			return
		end
		local along = (part.CFrame.Position - origin):Dot(look)
		local extent = math.abs(part.CFrame.RightVector:Dot(look)) * part.Size.X / 2
			+ math.abs(part.CFrame.UpVector:Dot(look)) * part.Size.Y / 2
			+ math.abs(part.CFrame.LookVector:Dot(look)) * part.Size.Z / 2
		local far = along + extent
		if far > doorAt then
			doorAt = far
		end
	end
	consider(counter)
	if type((model :: any).GetDescendants) == "function" then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				consider(d)
			end
		end
	end
	if doorAt == -math.huge then
		return counter.Size.Z / 2
	end
	return doorAt
end

local function rootOf(player: Player): BasePart?
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

-- The shop's real door (ShopDoor art): the blocker collides only while the
-- shop is locked, the closed sign shows the opening time, and the model
-- carries DoorLocked / DoorOpen for the clients to tween the leaves from.
local function playerPoints(): { Vector3 }
	local out: { Vector3 } = {}
	local ok, list = pcall(function()
		return game:GetService("Players"):GetPlayers()
	end)
	if not ok or type(list) ~= "table" then
		return out
	end
	for _, player in ipairs(list) do
		local hrp = rootOf(player)
		if hrp then
			table.insert(out, hrp.CFrame.Position)
		end
	end
	return out
end

local function setDoor(shopModel: Model, shopId: string, locked: boolean, hour: number)
	shopModel:SetAttribute("DoorLocked", locked)
	shopModel:SetAttribute("DoorOpen", not locked)
	local door = shopModel:FindFirstChild("ShopDoor")
	if door == nil then
		return
	end
	local block = door:FindFirstChild("DoorBlock")
	if block and block:IsA("BasePart") then
		block.CanCollide = locked
	end
	local sign = door:FindFirstChild("DoorClosedSign")
	if sign and sign:IsA("BasePart") then
		sign.Transparency = if locked then 0 else 1
		local gui = sign:FindFirstChild("ClosedGui")
		if gui and gui:IsA("SurfaceGui") then
			gui.Enabled = locked
			local label = gui:FindFirstChild("ClosedText")
			if label and label:IsA("TextLabel") then
				label.Text = ShopDoorLogic.ClosedText(shopId, hour)
			end
		end
	end
end

local function doorwayOccupied(shopModel: Model): boolean
	local door = shopModel:FindFirstChild("ShopDoor")
	local block = if door then door:FindFirstChild("DoorBlock") else nil
	if block == nil or not block:IsA("BasePart") then
		return false
	end
	return ShopDoorLogic.Occupied(playerPoints(), block.CFrame, block.Size)
end

-- A player inside who walks up to a closed door touches the inside sensor:
-- the same hold as the F prompt, so nobody is shut in.
local function hookSensor(shopModel: Model, shopId: string)
	local door = shopModel:FindFirstChild("ShopDoor")
	local sensor = if door then door:FindFirstChild("DoorSensor") else nil
	if sensor == nil or not sensor:IsA("BasePart") or doorHooked[sensor] then
		return
	end
	doorHooked[sensor] = true
	pcall(function()
		sensor.Touched:Connect(function(hit: BasePart)
			local ok, player = pcall(function()
				return game:GetService("Players"):GetPlayerFromCharacter(hit.Parent)
			end)
			if ok and player then
				NPCService.OnDoor(player, shopModel, shopId, ShopHoursLogic.Now())
			end
		end)
	end)
end

function NPCService.OnDoor(player: Player, shopModel: Model, shopId: string, hour: number)
	local counter = shopModel:FindFirstChild("Counter")
	if not (counter and counter:IsA("BasePart")) then
		return
	end
	local open = ShopHoursLogic.IsOpen(shopId, hour)
	local hrp = rootOf(player)
	local along = if hrp
		then (hrp.CFrame.Position - counter.CFrame.Position):Dot(counter.CFrame.LookVector)
		else math.huge
	local outside = ShopHoursLogic.IsOutside(along, frontAlong(shopModel, counter))
	if not ShopHoursLogic.MayOpenDoor(open, outside) then
		return
	end
	if not open then
		shopModel:SetAttribute("DoorHeldUntil", os.clock() + ShopHoursLogic.ExitHold)
		setDoor(shopModel, shopId, false, hour)
		BuildingArt.PaintDoor(shopModel, false)
	end
end

local function ensureDoorPrompt(shopModel: Model, counter: BasePart, shopId: string)
	local existing = counter:FindFirstChild("ShopDoor")
	if existing and existing:IsA("ProximityPrompt") then
		return existing
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopDoor"
	prompt.ActionText = "Open"
	prompt.ObjectText = shopId
	prompt.HoldDuration = 0
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	InputKit.PromptDefaults(prompt, "Open")
	prompt.MaxActivationDistance = InputKit.OpenRange
	prompt.Parent = counter
	if not doorHooked[prompt] then
		doorHooked[prompt] = true
		pcall(function()
			prompt.Triggered:Connect(function(who: Player)
				NPCService.OnDoor(who, shopModel, shopId, ShopHoursLogic.Now())
			end)
		end)
	end
	return prompt
end

local function ensureZzz(counter: BasePart)
	local existing = counter:FindFirstChild("Zzz")
	if existing and existing:IsA("BillboardGui") then
		existing.MaxDistance = ShopHoursLogic.ZzzMaxDistance
		existing.StudsOffset = Vector3.new(0, counter.Size.Y / 2 + ShopHoursLogic.ZzzAbove, 0)
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Zzz"
	gui.Size = UDim2.fromOffset(
		ShopHoursLogic.ZzzTextPx * ShopHoursLogic.ZzzWidthGlyphs,
		ShopHoursLogic.ZzzTextPx + ShopHoursLogic.ZzzPad
	)
	gui.StudsOffset = Vector3.new(0, counter.Size.Y / 2 + ShopHoursLogic.ZzzAbove, 0)
	gui.MaxDistance = ShopHoursLogic.ZzzMaxDistance
	gui.AlwaysOnTop = false
	gui.Parent = counter
	local label = Instance.new("TextLabel")
	label.Name = "ZzzText"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = "Zzz"
	label.TextSize = ShopHoursLogic.ZzzTextPx
	label.TextColor3 = Color3.fromRGB(ShopHoursLogic.ZzzRed, ShopHoursLogic.ZzzGreen, ShopHoursLogic.ZzzBlue)
	label.Parent = gui
end

local function clearZzz(counter: BasePart)
	local existing = counter:FindFirstChild("Zzz")
	if existing then
		existing:Destroy()
	end
end

-- Sleep, lock, and rewrite signs for `hour`. Idempotent. Tests pass the
-- hour; the running game passes ShopHoursLogic.Now().
function NPCService.Apply(mapFolder: Instance, hour: number)
	for _, npc in ipairs(NPCData.All()) do
		local shopId = npc.shop
		if shopId == nil then
			continue
		end
		local shopModel = mapFolder:FindFirstChild(shopId)
		if not (shopModel and shopModel:IsA("Model")) then
			continue
		end
		local counter = shopModel:FindFirstChild("Counter")
		local open = ShopHoursLogic.IsOpen(shopId, hour)
		local held = shopModel:GetAttribute("DoorHeldUntil")
		local holding = type(held) == "number" and held > os.clock()
		-- The door shuts only on an empty doorway (ShopDoorLogic.Locked).
		local locked =
			ShopDoorLogic.Locked(shopId, hour, holding, not open and not holding and doorwayOccupied(shopModel))
		setDoor(shopModel, shopId, locked, hour)
		hookSensor(shopModel, shopId)
		BuildingArt.PaintDoor(shopModel, locked)
		ShopHoursLogic.WriteSigns(shopModel, hour)
		if counter and counter:IsA("BasePart") then
			local prompt = ensureDoorPrompt(shopModel, counter, shopId)
			prompt.Enabled = locked
			if open then
				clearZzz(counter)
			else
				ensureZzz(counter)
			end
		end
		local model = findNpc(mapFolder, npc.id)
		local root = if model then model.PrimaryPart else nil
		if model and root then
			if open then
				local home = homes[model]
				if home and model:GetAttribute("Asleep") == true then
					root.CFrame = home
				end
				model:SetAttribute("Asleep", false)
				model:SetAttribute("SleepLine", "")
			elseif counter and counter:IsA("BasePart") then
				if homes[model] == nil then
					homes[model] = root.CFrame
				end
				root.CFrame = NPCData.SleepCFrame(counter.CFrame, counter.Size)
				model:SetAttribute("Asleep", true)
				model:SetAttribute("SleepLine", DialogueData.Sleepy(shopId, hour))
			end
		end
	end
end

function NPCService.Init(mapFolder: Instance)
	local find = finder(mapFolder)
	local folder = Instance.new("Folder")
	folder.Name = "Townsfolk"
	folder.Parent = mapFolder
	for _, npc in ipairs(NPCData.All()) do
		local ok, err = pcall(function()
			local model = build(npc, find)
			if npc.id == "Murph" then
				model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
				model.Parent = mapFolder
			else
				model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
				model.Parent = folder
			end
		end)
		if not ok then
			warn(string.format("[NPCService] couldn't build %s: %s", npc.id, tostring(err)))
		end
	end
	NPCService.Apply(mapFolder, ShopHoursLogic.Now())
	if type(RunService.IsRunning) == "function" and RunService:IsRunning() then
		task.spawn(function()
			while RunService:IsRunning() do
				task.wait(ShopHoursLogic.PollSeconds)
				NPCService.Apply(mapFolder, ShopHoursLogic.Now())
			end
		end)
	end
end

return NPCService
