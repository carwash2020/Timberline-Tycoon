--!strict
-- NodeService: gathered-material nodes (ItemCatalog.Materials[..].node),
-- such as the Sky Shard crystals on the Aether Isles. Mined with any axe:
-- `hits` swings break one, it adds `yield` to the player's materials
-- (profile.materials, mirrored on the Materials attribute) and grows back
-- after `respawnSec`. GameServer's MineNode handler checks the swing
-- cooldown and calls Hit. Nodes are tagged "Node" with HP / MaxHP / Uid /
-- Material attributes, so the client aims at them like trees.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)
local Util = require(ReplicatedStorage.Shared.Util)
local ProfileService = require(script.Parent.ProfileService)

local NodeService = {}

local NODE_TAG = "Node"

type NodeRecord = {
	model: Model,
	part: BasePart,
	materialId: string,
	hp: number,
	alive: boolean,
}

local nodes: { [string]: NodeRecord } = {}
local notify: (Player, string) -> () = function(_player: Player, _message: string) end

local function publish(player: Player)
	local profile = ProfileService.GetProfile(player)
	if profile then
		player:SetAttribute("Materials", ShopLogic.EncodeOwned(profile.materials))
	end
end

local function setVisible(rec: NodeRecord, visible: boolean)
	rec.part.Transparency = if visible then 0.1 else 1
	rec.part.CanCollide = visible
	rec.part.CanQuery = visible
end

-- A crystal cluster standing on the ground at `position`, parented to `parent`.
function NodeService.Spawn(materialId: string, position: Vector3, parent: Instance): Model
	local material = ItemCatalog.Materials[materialId]
	assert(material, "[NodeService] Unknown material " .. materialId)
	local uid = Util.guid()
	local model = Instance.new("Model")
	model.Name = "Node_" .. materialId
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local part = Instance.new("Part")
	part.Name = "Crystal"
	part.Size = Vector3.new(2.2, 4, 2.2)
	part.CFrame = CFrame.new(position + Vector3.new(0, 2, 0)) * CFrame.Angles(0, math.random() * math.pi, math.rad(12))
	part.Color = Color3.fromHex(material.node.color)
	part.Material = Enum.Material.Glass
	part.Transparency = 0.1
	part.Anchored = true
	part.Parent = model
	local glow = Instance.new("PointLight")
	glow.Color = part.Color
	glow.Range = 10
	glow.Brightness = 1.5
	glow.Parent = part
	model.PrimaryPart = part
	model:SetAttribute("Material", materialId)
	model:SetAttribute("MaxHP", material.node.hits)
	model:SetAttribute("HP", material.node.hits)
	model:SetAttribute("Uid", uid)
	model:SetAttribute("BarOffset", 3.5) -- TreeUI's HP bar height
	CollectionService:AddTag(model, NODE_TAG)
	model.Parent = parent
	nodes[uid] = { model = model, part = part, materialId = materialId, hp = material.node.hits, alive = true }
	return model
end

-- One swing at a node. Returns "mined" (broke it), "hit", "far" or nil (no
-- such node standing).
function NodeService.Hit(player: Player, uid: string): string?
	local rec = nodes[uid]
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local profile = ProfileService.GetProfile(player)
	if not rec or not rec.alive or not hrp or not profile then
		return nil
	end
	if (hrp.Position - rec.part.Position).Magnitude > GameConfig.ChopRange + GameConfig.RangeTolerance then
		return "far"
	end
	rec.hp -= 1
	rec.model:SetAttribute("HP", rec.hp)
	if rec.hp > 0 then
		return "hit"
	end
	local material = ItemCatalog.Materials[rec.materialId]
	rec.alive = false
	setVisible(rec, false)
	profile.materials[rec.materialId] = (profile.materials[rec.materialId] or 0) + material.node.yield
	publish(player)
	notify(
		player,
		string.format(
			"+%d %s (you have %d)",
			material.node.yield,
			material.displayName,
			profile.materials[rec.materialId]
		)
	)
	task.delay(material.node.respawnSec, function()
		if nodes[uid] == rec then
			rec.hp = material.node.hits
			rec.model:SetAttribute("HP", rec.hp)
			setVisible(rec, true)
			rec.alive = true
		end
	end)
	return "mined"
end

-- Call once the save has loaded, and after materials change elsewhere.
function NodeService.Publish(player: Player)
	publish(player)
end

function NodeService.Init(notifyFn: (Player, string) -> ())
	notify = notifyFn
end

return NodeService
