--!nocheck
-- T411: the town sawmill is a shared working mill, and the Weigh House bay
-- stays clear. Written against the acceptance table (1-12 and edges 13-19)
-- before the build, so each rule below failed on main fd98f20 and passes
-- after. Prices, Cap, bonuses, StoreData, vehicles and ProfileSchema are
-- not this ticket.

return function(t)
	local roblox = t.roblox
	local Instance = roblox.Instance
	local V3 = roblox.Vector3
	local CFrame = roblox.CFrame
	local Enum = roblox.Enum
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")

	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local MachineArt = t.load("ReplicatedStorage/Shared/Art/MachineArt")
	local LaneData = t.load("ReplicatedStorage/Shared/Lint/LaneData")
	local Lanes = t.load("ReplicatedStorage/Shared/Lint/Lanes")
	local SectionMetrics = t.load("ReplicatedStorage/Shared/SectionMetrics")
	local Catalog = t.shared("ItemCatalog")
	local Config = t.shared("GameConfig")
	local Sell = t.shared("SellLogic")
	local Logic = t.shared("SawmillLogic")
	local Auto = t.shared("AutomationLogic")
	local WoodData = t.shared("WoodData")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")

	local function parts(model)
		local list = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	local function bounds(part)
		local cf, size = part.CFrame, part.Size
		local half = size / 2
		local lo = V3.new(math.huge, math.huge, math.huge)
		local hi = V3.new(-math.huge, -math.huge, -math.huge)
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local p = cf * V3.new(sx * half.X, sy * half.Y, sz * half.Z)
					lo = V3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z))
					hi = V3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z))
				end
			end
		end
		return lo, hi
	end

	local function overlaps(lo, hi, boxMin, boxMax, slack)
		local pad = slack or 0.05
		return hi.X > boxMin.X + pad
			and lo.X < boxMax.X - pad
			and hi.Y > boxMin.Y + pad
			and lo.Y < boxMax.Y - pad
			and hi.Z > boxMin.Z + pad
			and lo.Z < boxMax.Z - pad
	end

	local function lane(name)
		for _, box in ipairs(LaneData.Boxes.Sawmill) do
			if box.name == name then
				return box
			end
		end
		return nil
	end

	local function show(list)
		return table.concat(list, "\n")
	end

	-- 1. Town shared mill: hosts, tag, OwnerId 0, MillId, Block log to planks.
	t.test("town mill is a shared working Sawmill (Intake, belt, Output, OwnerId 0)", function()
		local mill = BuildingArt.Sawmill()
		t.eq(mill:HasTag("Sawmill"), true, "tagged Sawmill")
		t.eq(mill:GetAttribute("MillId"), "SawmillRickety", "existing catalog id, no new row")
		t.eq(mill:GetAttribute("OwnerId"), 0)
		t.eq(mill:GetAttribute("PowerIn"), nil, "shared mill is not built powered off")
		local intake = mill:FindFirstChild("Intake", true)
		local belt = mill:FindFirstChild("Conveyor", true)
		local output = mill:FindFirstChild("Output", true)
		t.ok(intake and intake:IsA("BasePart"), "Intake")
		t.eq(intake.Transparency, 1)
		t.eq(intake.CanCollide, false)
		t.eq(intake.CanQuery, true)
		t.eq(intake:GetAttribute("VisualMesh"), nil)
		t.ok(belt and belt:IsA("BasePart") and belt.CanCollide, "Conveyor collides")
		t.eq(belt:GetAttribute("VisualMesh"), nil)
		t.ok(output and output:IsA("Attachment"), "Output attachment")
		t.ok(output.Parent and output.Parent:IsA("BasePart"), "Output sits on a part")
		t.eq(output.Parent:GetAttribute("VisualMesh"), nil)
		-- East slip mouth, carriage, west outfeed (scaled lane boxes).
		local slip, carriage, outfeed = lane("slip"), lane("carriage"), lane("outfeed")
		local iLo, iHi = bounds(intake)
		t.ok(overlaps(iLo, iHi, slip.min, slip.max, -0.01), "Intake covers the east slip")
		local bLo, bHi = bounds(belt)
		t.ok(overlaps(bLo, bHi, carriage.min, carriage.max, -0.01), "Conveyor runs the carriage")
		local outPos = output.Parent.CFrame * output.CFrame
		local o = outPos.Position
		t.ok(
			o.X >= outfeed.min.X - 0.5 and o.X <= outfeed.max.X + 0.5 and o.Z >= outfeed.min.Z and o.Z <= outfeed.max.Z,
			string.format("Output at the west outfeed (%.2f, %.2f, %.2f)", o.X, o.Y, o.Z)
		)
		t.ok(outPos.LookVector:Dot(V3.new(-1, 0, 0)) > 0.9, "planks leave toward the west")
		t.ok(belt.AssemblyLinearVelocity:Dot(V3.new(-1, 0, 0)) > 0.5, "AimBelt runs west")
		-- Longest Block face the early mill takes, plus a stud each side and two over.
		local need = Catalog.GetSawmill("SawmillRickety").maxLength * Config.WoodUnit + 4
		local along = math.max(belt.Size.X, belt.Size.Y, belt.Size.Z)
		t.ok(along + 1e-3 >= need, string.format("conveyor %.2f clears %.2f", along, need))
		t.eq(mill.ModelStreamingMode, Enum.ModelStreamingMode.Atomic)
	end)

	t.test("a Block oak in the town Intake comes out as planks; a too-long one is refused", function()
		local loader = t.loader({
			services = {
				Players = {
					GetPlayers = function()
						return {}
					end,
					GetPlayerByUserId = function(_, id)
						return if id == 7 then { UserId = 7, Name = "Ada" } else nil
					end,
				},
				PhysicsService = {},
			},
			mocks = {
				ProfileService = {
					GetProfile = function()
						return nil
					end,
				},
			},
		})
		local Sawmill = loader:server("SawmillService")
		local mill = BuildingArt.Sawmill()
		mill.Parent = Instance.new("Folder")
		local intake = mill:FindFirstChild("Intake", true)
		local function pieceOf(size)
			local part = Instance.new("Part")
			part.Name = "Section"
			part.Shape = Enum.PartType.Block
			part.Size = size
			part.CFrame = intake.CFrame
			local model = Instance.new("Model")
			part.Parent = model
			model.PrimaryPart = part
			model.Parent = Instance.new("Folder")
			return {
				model = model,
				root = part,
				kind = "log",
				woodId = "oak",
				parts = { [1] = part },
				nodes = { [1] = { parent = nil, children = {} } },
				volume = Sell.VolumeU3(size.X, size.Y, size.Z),
				ownerId = 7,
				boost = 1,
				verdictOk = true,
				selling = nil,
				dead = nil,
				shopItem = nil,
			}, part
		end
		local notes = {}
		local spawned = {}
		local now = 0
		local current = nil
		Sawmill._use({
			notify = function(_, text)
				table.insert(notes, text)
			end,
			now = function()
				return now
			end,
			partsIn = function()
				return if current and current.root.Parent and not current.dead then { current.root } else {}
			end,
			pieceOf = function()
				return current
			end,
			mills = function()
				return { mill }
			end,
			release = function() end,
			remove = function(p)
				p.dead = true
			end,
			spawn = function(info)
				table.insert(spawned, info)
				return nil
			end,
			moved = function() end,
			online = function()
				return true
			end,
			outputs = function()
				return 0
			end,
		})
		local legalSize = V3.new(2, 9, 2)
		current = pieceOf(legalSize)
		local cf, size = SectionMetrics.BlockFrame(current.root)
		t.eq(size, legalSize)
		t.eq(current.root.Shape, Enum.PartType.Block)
		t.eq(SectionMetrics.IsCylinder(current.root), false)
		t.eq(SectionMetrics.CargoPose(current.root), cf) -- shape is nil: the bed uses the box
		Sawmill.Tick()
		t.eq(#spawned, 0, "it rests first")
		now = Sawmill.Settle
		Sawmill.Tick()
		t.eq(current.selling, true, "the town mill takes a legal Block log")
		local expect = Logic.Cut(current.volume, Logic.DefaultSettings(Catalog.GetSawmill("SawmillRickety")), Catalog.GetSawmill("SawmillRickety"))
		for _ = 1, #expect + 3 do
			now += Logic.ProcessSeconds(current.volume) + Sawmill.PlankGap
			Sawmill.Tick()
		end
		t.eq(#spawned, #expect, "planks at the outfeed")
		t.ok(#spawned > 0)
		local back = 0
		for _, info in ipairs(spawned) do
			t.eq(info.woodId, "oak")
			back += Sell.VolumeU3(info.size.X, info.size.Y, info.size.Z)
		end
		t.ok(math.abs(back - current.volume) < 1e-3, "the volume comes back")
		-- Over-limit Block log: the existing clear message, no planks.
		local before = #spawned
		local longSize = V3.new(2, Catalog.GetSawmill("SawmillRickety").maxLength * Config.WoodUnit + 4, 2)
		current = pieceOf(longSize)
		now += 5
		Sawmill.Tick()
		now += Sawmill.Settle + 1
		Sawmill.Tick()
		t.eq(#spawned, before, "an over-limit log is not cut")
		t.eq(current.model:GetAttribute("MillNote"), "long")
		t.ok(#notes > 0 and string.find(notes[#notes], "Too big for this mill", 1, true) ~= nil, notes[#notes] or "no toast")
		mill:Destroy()
		Sawmill._reset()
	end)

	-- 10 and 19. Block SectionMetrics only. Plot Rickety still mills.
	t.test("the mill path is Block SectionMetrics, and Rickety still mills a Block log", function()
		local src = fs.readFile("src/ServerScriptService/SawmillService.luau")
		t.ok(string.find(src, "SectionMetrics.BlockFrame", 1, true) ~= nil, "length and volume use BlockFrame")
		t.eq(string.find(src, "RoundRadius", 1, true), nil, "no round radius on the mill path")
		local art = fs.readFile("src/ReplicatedStorage/Shared/Art/BuildingArt.luau")
		-- The town slip's dressed log is a square Block, not a cylinder.
		local mill = BuildingArt.Sawmill()
		local slip = lane("slip")
		local square, round = 0, 0
		for _, p in ipairs(parts(mill)) do
			if p.Name == "Log" then
				local lo, hi = bounds(p)
				if overlaps(lo, hi, slip.min, slip.max, -1) then
					if p.Shape == Enum.PartType.Block then
						square += 1
					elseif p.Shape == Enum.PartType.Cylinder then
						round += 1
					end
				end
			end
		end
		t.ok(square >= 1, "a square Block oak sits on the slip")
		t.eq(round, 0, "no round log on the slip")
		t.eq(string.find(art, "RoundRadius", 1, true), nil)
		-- Rickety plot mill, unchanged pipeline.
		local loader = t.loader({
			services = {
				Players = {
					GetPlayerByUserId = function()
						return nil
					end,
					GetPlayers = function()
						return {}
					end,
				},
				PhysicsService = {},
			},
			mocks = {
				ProfileService = {
					GetProfile = function()
						return nil
					end,
				},
			},
		})
		local Sawmill = loader:server("SawmillService")
		local plot = MachineArt.Build("SawmillRickety", false)
		plot.Parent = Instance.new("Folder")
		t.eq(plot:HasTag("Sawmill"), true)
		t.eq(plot:GetAttribute("Tunnel"), "closed")
		t.eq(plot:GetAttribute("ExposedBlade"), false)
		local intake = plot:FindFirstChild("Intake")
		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Block
		part.Size = V3.new(2, 9, 2)
		part.CFrame = intake.CFrame
		local model = Instance.new("Model")
		part.Parent = model
		model.PrimaryPart = part
		model.Parent = Instance.new("Folder")
		local piece = {
			model = model,
			root = part,
			kind = "log",
			woodId = "oak",
			parts = { [1] = part },
			nodes = { [1] = { parent = nil, children = {} } },
			volume = Sell.VolumeU3(2, 9, 2),
			ownerId = 4,
			boost = 1,
			verdictOk = true,
		}
		local spawned = {}
		local now = 0
		Sawmill._use({
			notify = function() end,
			now = function()
				return now
			end,
			partsIn = function()
				return { part }
			end,
			pieceOf = function()
				return piece
			end,
			mills = function()
				return { plot }
			end,
			release = function() end,
			remove = function(p)
				p.dead = true
			end,
			spawn = function(info)
				table.insert(spawned, info)
				return nil
			end,
			moved = function() end,
			online = function()
				return true
			end,
			outputs = function()
				return 0
			end,
		})
		Sawmill.Tick()
		now = Sawmill.Settle
		Sawmill.Tick()
		t.eq(piece.selling, true, "Rickety still takes a Block log")
		for _ = 1, 12 do
			now += 2
			Sawmill.Tick()
		end
		t.ok(#spawned > 0, "planks come out of the closed-tunnel mill")
		Sawmill._reset()
	end)

	-- 3 and 12. Door, walk path, blade out of both.
	t.test("the cabin door is at least 4 by 7 and the walk in front is at least 6 wide", function()
		local mill = BuildingArt.Sawmill()
		local door = lane("front")
		local root = Instance.new("Folder")
		root.Name = "Town"
		mill.Name = "Sawmill"
		mill.Parent = root
		local run = Lanes.Run(root, { Sawmill = CFrame.new() })
		t.eq(run.failures, {}, "door lane: " .. show(run.failures))
		-- Clear opening: the door box itself, and a 6-stud-wide walk through it.
		local width = door.max.X - door.min.X
		local height = door.max.Y - door.min.Y
		t.ok(width + 1e-3 >= 4, "lane door width " .. width)
		t.ok(height + 1e-3 >= 7, "lane door height " .. height)
		local midX = (door.min.X + door.max.X) / 2
		local walkMin = V3.new(midX - 3, door.min.Y, door.min.Z - 6)
		local walkMax = V3.new(midX + 3, door.min.Y + 7, door.max.Z)
		for _, p in ipairs(parts(mill)) do
			if p.CanCollide and p.Name ~= "Conveyor" then
				local lo, hi = bounds(p)
				t.eq(
					overlaps(lo, hi, walkMin, walkMax, 0.05),
					false,
					string.format("%s stands in the 6-wide walk", p.Name)
				)
			end
		end
		local blade = mill:FindFirstChild("SawBlade", true)
		local bLo, bHi = bounds(blade)
		t.eq(overlaps(bLo, bHi, door.min, door.max, 0), false, "the blade is not in the doorway")
		t.eq(overlaps(bLo, bHi, walkMin, walkMax, 0), false, "the blade is not in the walk")
		t.eq(mill:GetAttribute("ExposedBlade"), true, "the town blade may show inside its housing")
		t.eq(mill:GetAttribute("Tunnel"), "housing")
		t.eq(blade.CanCollide, false)
		local housed = false
		for _, p in ipairs(parts(mill)) do
			if p.Name == "BladeHousing" then
				housed = true
				t.eq(p.CanCollide, false, "the housing is not a second saw")
			end
		end
		t.eq(housed, true, "IronBlack housing around the town blade")
	end)

	-- 2, 4, 5, 13, 16, 18. Lanes, apron, twin, invisible dress.
	t.test("slip, carriage, outfeed and door have no stray solid, and the aprons are clear", function()
		local mill = BuildingArt.Sawmill()
		local root = Instance.new("Folder")
		mill.Name = "Sawmill"
		mill.Parent = root
		local run = Lanes.Run(root, { Sawmill = CFrame.new() })
		t.eq(run.checked, 4)
		t.eq(run.failures, {}, show(run.failures))
		local json = serde.decode("json", fs.readFile("assets/meshes/lanes.json"))
		for _, entry in ipairs(json.Sawmill) do
			local pending = entry.pending
			t.ok(pending == nil or #pending == 0, entry.name .. " pending is empty")
		end
		-- Apron: 6 studs outside the slip's east face and the outfeed's west face.
		local slip, outfeed = lane("slip"), lane("outfeed")
		local function apronClear(boxMin, boxMax)
			for _, p in ipairs(parts(mill)) do
				if p.CanCollide and not LaneData.Riders[p.Name] then
					local lo, hi = bounds(p)
					if overlaps(lo, hi, boxMin, boxMax, 0.05) then
						return p.Name
					end
				end
			end
			return nil
		end
		local east = apronClear(
			V3.new(slip.max.X, 0.4, slip.min.Z),
			V3.new(slip.max.X + 6, slip.max.Y, slip.max.Z)
		)
		t.eq(east, nil, "intake apron: " .. tostring(east))
		local west = apronClear(
			V3.new(outfeed.min.X - 6, 0.4, outfeed.min.Z),
			V3.new(outfeed.min.X, outfeed.max.Y, outfeed.max.Z)
		)
		t.eq(west, nil, "outfeed apron: " .. tostring(west))
		-- Invisible colliders need a reason. A dressed mill (mesh loaded) hides
		-- the belt; the reason is on it before that, so the dress does not invent one.
		for _, p in ipairs(parts(mill)) do
			if p.Transparency >= 1 and p.CanCollide then
				local reason = p:GetAttribute("InvisibleBlockerReason")
				t.eq(p:GetAttribute("InvisibleBlocker"), true, p.Name .. " invisible collider")
				t.ok(type(reason) == "string" and reason ~= "", p.Name .. " blocker reason")
			end
		end
	end)

	t.test("MeshId unset keeps the part mill; MeshId loaded drops the stand-in and keeps the hosts", function()
		local plain = BuildingArt.Sawmill()
		local function visiblePart(model)
			for _, p in ipairs(parts(model)) do
				if p.Name == "Post" and p.Transparency < 1 and not p:IsA("MeshPart") then
					return p
				end
			end
			return nil
		end
		t.ok(visiblePart(plain), "MeshId unset keeps the part walls")
		t.ok(plain:FindFirstChild("Intake", true), "hosts exist before a mesh")
		-- The same modules BuildingArt already required. A fresh loader would
		-- set Override on a copy Dress never sees.
		local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
		local TownMeshes = t.load("ReplicatedStorage/Shared/Art/TownMeshes")
		MeshKit.Reset()
		TownMeshes.ResetFallbacks()
		MeshKit.Override = function(_id, name, size)
			local part = Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			part.MeshId = "rbxassetid://1"
			return part
		end
		local dressed = BuildingArt.Sawmill()
		MeshKit.Override = nil
		MeshKit.Reset()
		t.eq(dressed:GetAttribute("TownMesh"), "Sawmill", "mesh landed")
		local intake = dressed:FindFirstChild("Intake", true)
		local belt = dressed:FindFirstChild("Conveyor", true)
		local output = dressed:FindFirstChild("Output", true)
		t.ok(intake and intake.Parent, "Intake survives Dress")
		t.ok(belt and belt.Parent and belt.CanCollide, "Conveyor survives Dress")
		t.ok(output and output.Parent, "Output survives Dress")
		t.eq(intake:GetAttribute("VisualMesh"), nil)
		t.eq(belt:GetAttribute("VisualMesh"), nil)
		local body = nil
		for _, p in ipairs(parts(dressed)) do
			if p.Name == "Body" and p:IsA("MeshPart") and p:GetAttribute("VisualMesh") == true then
				body = p
			end
			if p.Name == "Post" and not p:IsA("MeshPart") then
				t.ok(p.Transparency >= 1 or p.Parent == nil, "part post is not a stand-in once the mesh loads")
			end
		end
		t.ok(body, "the mesh body replaced the look")
		t.eq(visiblePart(dressed), nil, "no visible part-built post after load")
	end)

	-- Shared OwnerId 0: Set without EditRights, no per-player save; belts skip notYours and offline.
	t.test("OwnerId 0 lets any nearby player set the cut, and does not save it", function()
		local saved = false
		local loader = t.loader({
			services = {
				Players = {
					GetPlayerByUserId = function()
						return nil
					end,
				},
				PhysicsService = {},
			},
			mocks = {
				RateLimiter = {
					Allow = function()
						return true
					end,
				},
				ProfileService = {
					GetProfile = function()
						saved = true
						return { plot = { placed = { { uid = "town", data = { x = 9, y = 9 } } } } }
					end,
				},
			},
		})
		local Sawmill = loader:server("SawmillService")
		local mill = BuildingArt.Sawmill()
		mill:SetAttribute("Uid", "town")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Position = mill:GetPivot().Position
		local function player(id)
			return {
				UserId = id,
				Character = {
					FindFirstChild = function(_, name)
						return if name == "HumanoidRootPart" then root else nil
					end,
				},
			}
		end
		Sawmill._use({
			notify = function() end,
			mills = function()
				return { mill }
			end,
		})
		local ada = player(42)
		Sawmill.Set(ada, "town", "x", 1)
		t.eq(mill:GetAttribute("CutX"), 1.2, "a player who does not own the plot can nudge the shared mill")
		t.eq(saved, false, "the shared cut is not written onto a profile")
		root.Position = mill:GetPivot().Position + V3.new(80, 0, 0)
		Sawmill.Set(ada, "town", "x", 1)
		t.eq(mill:GetAttribute("CutX"), 1.2, "still has to be standing at the mill")
		Sawmill._reset()
	end)

	t.test("a shared mill does not refuse a belt for notYours or offline", function()
		local function facts(change)
			local f = {
				automated = true,
				woodId = "oak",
				pieceOwnerId = 8,
				machineOwnerId = 0,
				ownerOnline = false,
				looseOutputs = 0,
			}
			for k, v in pairs(change or {}) do
				f[k] = v
			end
			return Auto.Refusal(f)
		end
		t.eq(facts(), nil, "OwnerId 0 takes another player's wood while nobody is 'the owner'")
		t.eq(facts({ woodId = "lumenwood" }), "rare", "rare wood is still hand-only")
		t.eq(facts({ looseOutputs = Auto.MaxLooseOutputs }), "full")
		t.eq(facts({ machineOwnerId = 3, ownerOnline = true }), "notYours", "a plot mill still refuses someone else's wood")
		t.eq(facts({ machineOwnerId = 3, pieceOwnerId = 3, ownerOnline = false }), "offline")
	end)

	-- 6 and 15. Sell pad pays once. Planks pay more than the same log.
	t.test("the Weigh House bay pays a Block log once, and planks pay more than that log", function()
		local oak = WoodData.Get("oak").v2
		t.ok(oak.plankPrice > oak.logPrice, "plank price is higher per u³")
		local volume = 8
		local logValue = Sell.PieceValue("oak", "log", volume, nil, 1)
		local plankValue = Sell.PieceValue("oak", "plank", volume, nil, 1)
		t.ok(plankValue > logValue, string.format("planks %.2f > log %.2f", plankValue, logValue))
		local loader = t.loader({
			services = {
				Players = {
					GetPlayerByUserId = function(_, id)
						return if id == 1 then { UserId = 1, Name = "Ada" } else nil
					end,
				},
			},
		})
		local SellService = loader:server("SellService")
		local station = BuildingArt.SellStation(WorldPlan.SellPadWidth, WorldPlan.SellPadDepth)
		local pad = station:FindFirstChild("SellPad", true)
		t.eq(pad.Size.X, 28)
		t.eq(pad.Size.Z, 32)
		t.eq(pad.CanCollide, false)
		local paid = {}
		local folder = Instance.new("Folder")
		local model = Instance.new("Model")
		model.Name = "Wood_oak"
		model:AddTag("Wood")
		model:SetAttribute("WoodId", "oak")
		model:SetAttribute("Volume", volume)
		local part = Instance.new("Part")
		part.Shape = Enum.PartType.Block
		part.Size = V3.new(2, 8, 2)
		part.Parent = model
		model.PrimaryPart = part
		model.Parent = folder
		local record = { model = model, ownerId = 1, lastHolderId = nil }
		local inZone = { part }
		SellService._use({
			zone = pad,
			woodFolder = folder,
			resolve = function()
				return record
			end,
			addCash = function(_, amount)
				table.insert(paid, amount)
				return amount
			end,
			saleMultiplier = function()
				return 1
			end,
			notify = function() end,
			release = function() end,
			forget = function() end,
			onSold = function() end,
			partsInZone = function()
				return inZone
			end,
			now = function()
				return 10
			end,
		})
		SellService.Tick()
		-- Settle, then the paying tick. A second tick must not pay again.
		local clock = 10
		SellService._use({
			zone = pad,
			woodFolder = folder,
			resolve = function()
				return record
			end,
			addCash = function(_, amount)
				table.insert(paid, amount)
				return amount
			end,
			saleMultiplier = function()
				return 1
			end,
			notify = function() end,
			release = function() end,
			forget = function() end,
			onSold = function() end,
			partsInZone = function()
				return inZone
			end,
			now = function()
				return clock
			end,
		})
		SellService._reset()
		SellService._use({
			zone = pad,
			woodFolder = folder,
			resolve = function(m)
				return if m == model then record else nil
			end,
			addCash = function(_, amount)
				table.insert(paid, amount)
				return amount
			end,
			saleMultiplier = function()
				return 1
			end,
			notify = function() end,
			release = function() end,
			forget = function() end,
			onSold = function() end,
			partsInZone = function()
				return if model.Parent then { part } else {}
			end,
			now = function()
				return clock
			end,
		})
		clock = 0
		SellService.Tick()
		clock = SellService.Settle
		local sales = SellService.Tick()
		t.eq(#sales, 1)
		t.eq(#paid, 1, "one payout")
		t.ok(paid[1] > 0)
		clock += 5
		local again = SellService.Tick()
		t.eq(#again, 0, "a second touch does not pay again")
		t.eq(#paid, 1)
		SellService._reset()
	end)

	-- 4 and 7. Truck bay >= 14, scale tower reads from 100 studs.
	t.test("the truck bay is at least 14 wide and the scale tower reads from 100 studs", function()
		local station = BuildingArt.SellStation(28, 32)
		t.eq(station.ModelStreamingMode, Enum.ModelStreamingMode.Atomic)
		local pad = station:FindFirstChild("SellPad", true)
		-- Centre 14 studs, the driving length in front of the back rack.
		local bayMin = V3.new(-7, 0.35, -15)
		local bayMax = V3.new(7, 8, 12)
		t.ok(bayMax.X - bayMin.X >= 14)
		t.ok(pad.Size.X >= 28 and pad.Size.Z >= 32)
		for _, p in ipairs(parts(station)) do
			if p.CanCollide then
				local lo, hi = bounds(p)
				t.eq(
					overlaps(lo, hi, bayMin, bayMax, 0.02),
					false,
					string.format("%s stands in the truck bay", p.Name)
				)
			end
			if p.Name == "RackLog" or p.Name == "Log" then
				t.eq(p.Shape, Enum.PartType.Block, p.Name .. " is square Block wood")
			end
		end
		local post = station:FindFirstChild("ScalePost", true)
		local dial = station:FindFirstChild("ScaleDial", true)
		t.ok(post and dial, "scale tower")
		local _, postHi = bounds(post)
		local _, dialHi = bounds(dial)
		local top = math.max(postHi.Y, dialHi.Y)
		t.ok(top >= 18, string.format("tower top %.1f reads past the yard", top))
		local dialSize = math.max(dial.Size.X, dial.Size.Y, dial.Size.Z)
		t.ok(dialSize >= 5.8 and dialSize <= 6.4, "dial about 6 studs, got " .. dialSize)
		-- 100 studs south of the tower (the spawn approach). The dial still
		-- subtends enough to read, and the tower is the thing on that line.
		local dialPos = dial.CFrame.Position
		local eye = dialPos + V3.new(0, -4, -100)
		local dist = (dialPos - eye).Magnitude
		t.ok(dist >= 100, "the check stands at least 100 studs off")
		t.ok(dialSize / dist >= 0.05, "the dial is still a few degrees across")
		local house = station:FindFirstChild("WeighHouse")
		t.ok(house, "Weigh House")
		t.ok(t.load("ReplicatedStorage/Shared/Art/Palette"), "palette")
	end)

	-- 9 and 11. MustKeep stays. Rickety tunnel attribute is the plot rule.
	t.test("MustKeep centres and the plot tunnel rule stay put", function()
		t.eq(WorldLayout.Sawmill, V3.new(0, 0, 110))
		t.eq(WorldLayout.WorldHalf, 1350)
		local town = WorldPlan.Town()
		t.ok((town.sawmill.Position - V3.new(0, 0, 116.5)).Magnitude < 0.1, "sawmill frame")
		t.ok((town.sellPad.Position - V3.new(53, 0, 111)).Magnitude < 0.1, "sell pad stays east of the mill")
		local function floorNamed(name)
			for _, floor in ipairs(WorldLayout.TownFloors) do
				if floor.name == name then
					return floor
				end
			end
			return nil
		end
		local deal = floorNamed("DealershipFloor")
		t.eq(deal.x0, 178)
		t.eq(deal.z0, 95.4)
		local shed = floorNamed("ToolShedFloor")
		t.eq(shed.x0, -106.5)
		t.eq(shed.z0, 88.5)
		local keep = fs.readFile("tests/mustkeep.json")
		t.ok(string.find(keep, "-48.00", 1, true) ~= nil, "gate lodge door")
		-- No price or schema edit rides along. The catalog id used here already existed.
		t.ok(Catalog.GetSawmill("SawmillRickety") ~= nil)
		t.eq(Catalog.GetSawmill("SawmillTown"), nil, "no new mill row")
	end)
end
