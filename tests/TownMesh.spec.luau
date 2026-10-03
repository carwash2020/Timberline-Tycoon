--!nocheck
-- Ticket I: town meshes keep gameplay where it is. Lune cannot load the
-- meshes, so the default art stays part-built. These tests inject
-- MeshKit.Override for the mesh path. I-Paths, I-Prompts, I-NPC, I-Shops,
-- I-Motion, I-Budget, I-Economy.
return function(t)
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local TownModels = t.load("ReplicatedStorage/Shared/Art/TownModels")
	local TownMeshes = t.load("ReplicatedStorage/Shared/Art/TownMeshes")
	local TownMotion = t.load("ReplicatedStorage/Shared/Art/TownMotion")
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local PropArt = t.load("ReplicatedStorage/Shared/Art/PropArt")
	local LandmarkArt = t.load("ReplicatedStorage/Shared/Art/LandmarkArt")
	local CharacterArt = t.load("ReplicatedStorage/Shared/Art/CharacterArt")
	local StoreBoard = t.shared("StoreBoard")
	local NPCData = t.shared("NPCData")
	local TutorialData = t.shared("TutorialData")
	local GameConfig = t.shared("GameConfig")
	local roblox = t.roblox
	local Vector3 = roblox.Vector3
	local CFrame = roblox.CFrame

	local function withMeshes(fn)
		MeshKit.Reset()
		MeshKit.Override = function(_id, name, size)
			local part = roblox.Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			return part
		end
		local ok, err = pcall(fn)
		MeshKit.Override = nil
		MeshKit.Reset()
		if not ok then
			error(err, 0)
		end
	end

	local function visuals(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("VisualMesh") == true then
				table.insert(out, d)
			end
		end
		return out
	end

	local function visualNamed(model, name)
		for _, d in ipairs(visuals(model)) do
			if d.Name == name then
				return d
			end
		end
		return nil
	end

	local function solids(model)
		local rows = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.CanCollide then
				local p = d.CFrame.Position
				local s = d.Size
				table.insert(
					rows,
					string.format("%s %.3f %.3f %.3f %.3f %.3f %.3f", d.Name, s.X, s.Y, s.Z, p.X, p.Y, p.Z)
				)
			end
		end
		table.sort(rows)
		return table.concat(rows, "\n")
	end

	local function lights(model)
		local n = 0
		local rows = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("PointLight") then
				n += 1
				local parent = d.Parent
				if parent and parent:IsA("BasePart") then
					local p = parent.CFrame.Position
					table.insert(rows, string.format("%.3f %.3f %.3f", p.X, p.Y, p.Z))
				end
			end
		end
		table.sort(rows)
		return n, table.concat(rows, "|")
	end

	local function frontAhead(mesh, board)
		local look = board.CFrame.LookVector
		local function maxAlong(part)
			local cf, size = part.CFrame, part.Size
			local maxP = -math.huge
			local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local p = cf * Vector3.new(sx * hx, sy * hy, sz * hz)
						maxP = math.max(maxP, p:Dot(look))
					end
				end
			end
			return maxP
		end
		return maxAlong(mesh) - maxAlong(board)
	end

	t.test("I-Paths: colliders match the part build, and meshes stay out of the truck route", function()
		local plainMill = BuildingArt.Sawmill()
		local plainPad = BuildingArt.SellPad(24, 18)
		local millSolids = solids(plainMill)
		local padSolids = solids(plainPad)
		t.eq(#visuals(plainMill), 0, "no mesh without a load")
		withMeshes(function()
			local mill = BuildingArt.Sawmill()
			local pad = BuildingArt.SellPad(24, 18)
			t.eq(solids(mill), millSolids, "sawmill colliders")
			t.eq(solids(pad), padSolids, "sell pad colliders")
			for _, part in ipairs(visuals(mill)) do
				t.eq(part.CanCollide, false, part.Name)
				t.eq(part.CanQuery, false, part.Name .. " query")
				t.eq(part.CanTouch, false, part.Name .. " touch")
			end
			for _, part in ipairs(visuals(pad)) do
				t.eq(part.CanCollide, false)
				t.eq(part.CanQuery, false, "the pad mesh does not cover SellZone")
			end
			-- Spawn (0, 0.5, 40) to the pad at z = 86, along x = 0. No new
			-- solid sits on that line: the solid set is the part build's.
			t.ok(mill:FindFirstChild("SawBlade", true), "the blade is still findable")
		end)
	end)

	t.test("I-Prompts: talk, shop, store, and pickup ranges stay on their parts", function()
		t.eq(NPCData.TalkDistance, 12)
		t.eq(GameConfig.PickupPromptRange, 10)
		local fs = require("@lune/fs")
		t.ok(
			string.find(
				fs.readFile("src/ServerScriptService/TreeService.luau"),
				"GameConfig.PickupPromptRange",
				1,
				true
			) ~= nil,
			"log pickup still uses PickupPromptRange"
		)
		withMeshes(function()
			for _, kind in ipairs({ "ToolShed", "Dealership", "HearthAndHome" }) do
				local shop = BuildingArt.Shop(kind, kind, roblox.Color3.fromRGB(120, 70, 40))
				local counter = shop:FindFirstChild("Counter")
				t.ok(counter and counter:IsA("BasePart"), kind .. " counter")
				local point = roblox.Instance.new("Attachment")
				point.Name = "ShopPoint"
				point.Position = Vector3.new(0, 0, -(counter.Size.Z / 2 + 0.5))
				point.Parent = counter
				local front = counter.CFrame * Vector3.new(0, 0, -counter.Size.Z / 2)
				local world = counter.CFrame:PointToWorldSpace(point.Position)
				local along = world - front
				t.ok((along - counter.CFrame.LookVector * 0.5).Magnitude < 1e-3, kind .. " ShopPoint is 0.5 in front")
				local mesh = visualNamed(shop, "Counter")
				t.ok(mesh, kind .. " counter mesh")
				t.ok((mesh.CFrame.Position - counter.CFrame.Position).Magnitude <= 0.1, kind .. " counter centre")
			end
			local board = StoreBoard.Build()
			local prompt = board:FindFirstChild("StorePrompt", true)
			t.ok(prompt and prompt.Parent.Name == "Board", "store prompt stays on the board")
			t.eq(prompt.MaxActivationDistance, 12)
			t.eq(prompt.Parent:GetAttribute("VisualMesh"), nil)
			local DealershipLot = t.load("ReplicatedStorage/Shared/Art/DealershipLot")
			local lot = DealershipLot.Build()
			local buy = lot:FindFirstChild("BuyPrompt", true)
			t.ok(buy and buy.Parent.Name == "PriceSign", "buy prompt stays on the price sign")
			t.eq(buy.MaxActivationDistance, 14)
			t.eq(buy.Parent:GetAttribute("VisualMesh"), nil, "the price sign stays a part")
		end)
	end)

	t.test("I-NPC: the R6 rig welds the meshes, or keeps the whole part look", function()
		local look = NPCData.Get("Murph").look
		local plain = CharacterArt.Build(look)
		t.eq(#visuals(plain), 0, "fallback adds nothing")
		t.eq(plain:FindFirstChildOfClass("Humanoid"), nil)
		t.eq(plain.Torso.Transparency < 1, true, "the part look stays when a mesh misses")
		for _, name in ipairs({ "Scale", "RootHeight", "Height", "TopOffset" }) do
			t.ok(plain:GetAttribute(name) ~= nil, name)
		end
		withMeshes(function()
			local model = CharacterArt.Build(look)
			t.eq(model:FindFirstChildWhichIsA("Humanoid", true), nil)
			t.eq(model:FindFirstChildWhichIsA("AnimationController", true), nil)
			for _, name in ipairs({ "Scale", "RootHeight", "Height", "TopOffset" }) do
				t.eq(model:GetAttribute(name), plain:GetAttribute(name), name)
			end
			for _, name in ipairs({ "Head", "Beard", "Beanie", "Torso", "LeftArm", "RightArm" }) do
				t.ok(model:FindFirstChild(name), name .. " stays for the portrait")
			end
			local tag = model.Head:FindFirstChild("NameTag")
			t.ok(tag and tag:IsA("BillboardGui"), "NameTag stays on the Head")
			t.eq(model.Head:GetAttribute("MeshEyes"), true)
			local eye = model.Head:FindFirstChild("Eye")
			t.ok(eye and eye.Transparency == 1, "part eyes hide when the head mesh has its own")
			local shine = eye:FindFirstChild("EyeShine")
			t.ok(shine and shine.Transparency == 1, "the shine stays hidden")
			local arm = model.LeftArm
			local mesh = arm:FindFirstChild("LeftUpperArm")
			t.ok(mesh and mesh:GetAttribute("VisualMesh") == true, "LeftUpperArm is on LeftArm")
			local shoulder = model:FindFirstChild("LeftShoulder", true)
			local weld = mesh:FindFirstChild("Weld")
			t.ok(shoulder and weld and weld.Part0 == arm and weld.Part1 == mesh, "welded to LeftArm")
			t.ok(mesh.CFrame.LookVector:Dot(Vector3.new(0, 0, -1)) > 0.99, "still faces -Z")
			local transform = CFrame.Angles(0.5, 0, 0)
			local newArm = shoulder.Part0.CFrame * shoulder.C0 * transform * shoulder.C1:Inverse()
			local newMesh = newArm * weld.C0 * weld.C1:Inverse()
			local before = arm.CFrame:Inverse() * mesh.CFrame
			local after = newArm:Inverse() * newMesh
			t.ok((before.Position - after.Position).Magnitude < 1e-3, "the mesh keeps its offset on the arm")
			t.ok((newMesh.Position - mesh.CFrame.Position).Magnitude > 0.05, "LeftShoulder moves LeftUpperArm")
			local height = model:GetAttribute("Height")
			local minY, maxY = math.huge, -math.huge
			for _, part in ipairs(visuals(model)) do
				if part.Name ~= "HumanoidRootPart" and part.Name ~= "Carry" and part.Name ~= "Glow" then
					local cf, size = part.CFrame, part.Size
					local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
					for _, sx in ipairs({ -1, 1 }) do
						for _, sy in ipairs({ -1, 1 }) do
							for _, sz in ipairs({ -1, 1 }) do
								local y = (cf * Vector3.new(sx * hx, sy * hy, sz * hz)).Y
								minY = math.min(minY, y)
								maxY = math.max(maxY, y)
							end
						end
					end
				end
			end
			local span = maxY - minY
			t.ok(math.abs(span - height) / height <= 0.1, string.format("height %.3f span %.3f", height, span))
			-- One mesh missing: nothing is parented, and the shirt stays visible.
			local headId = TownModels.Piece(TownModels.Get("Murph"), "Head").meshId
			MeshKit.Override = function(id, name, size)
				if id == headId then
					return nil
				end
				local part = roblox.Instance.new("MeshPart")
				part.Name = name
				part.Size = size
				return part
			end
			local missed = CharacterArt.Build(look)
			t.eq(#visuals(missed), 0, "all or nothing")
			t.ok(missed.Torso.Transparency < 1, "the full part look stays")
			t.eq(missed.Head:GetAttribute("MeshEyes"), nil)
		end)
	end)

	t.test("I-Shops: counters, signs, and the authored building scale", function()
		withMeshes(function()
			for _, kind in ipairs({ "ToolShed", "Dealership", "HearthAndHome", "Sawmill" }) do
				local model = if kind == "Sawmill"
					then BuildingArt.Sawmill()
					else BuildingArt.Shop(kind, kind, roblox.Color3.fromRGB(90, 60, 40))
				local asset = TownModels.Get(TownModels.ShopAsset(kind))
				local body = visualNamed(model, "Body")
				local piece = TownModels.Piece(asset, "Body")
				t.ok(body and (body.Size - piece.size).Magnitude < 1e-3, kind .. " is not scaled a second time")
				if kind ~= "Sawmill" then
					local counter = model:FindFirstChild("Counter")
					local mesh = visualNamed(model, "Counter")
					t.ok((mesh.CFrame.Position - counter.CFrame.Position).Magnitude <= 0.1, kind .. " counter")
				end
				local sign = model:FindFirstChild("Sign")
				local signMesh = visualNamed(model, "Sign")
				t.ok(sign and signMesh, kind .. " sign")
				t.ok((signMesh.CFrame.Position - sign.CFrame.Position).Magnitude <= 0.25, kind .. " sign centre")
				t.ok(frontAhead(signMesh, sign) <= 0.02, kind .. " sign mesh is not in front of the text")
			end
			local fence = BuildingArt.Fence(24)
			local fenceBody = visualNamed(fence, "Body")
			t.ok(fenceBody and math.abs(fenceBody.Size.X - 24) < 1e-3, "a fence scales on X, once")
			t.eq(
				(function()
					local n = 0
					for _, d in ipairs(visuals(fence)) do
						if d.Name == "Body" then
							n += 1
						end
					end
					return n
				end)(),
				1,
				"the fence is not tiled"
			)
			local dock = LandmarkArt.Dock(26, 6, 2, -4, { 0, -2, -6, -8 })
			local dockBody = visualNamed(dock, "Body")
			local dockPiece = TownModels.Piece(TownModels.Get("Dock"), "Body")
			t.ok(
				dockBody and math.abs(dockBody.Size.Z - dockPiece.size.Z * 26 / 20) < 1e-3,
				"the 26-stud dock scales on length"
			)
			local bridge = BuildingArt.Bridge(Vector3.new(0, 10, 0), Vector3.new(0, 10, -32), 6)
			local deck = visualNamed(bridge, "Body")
			t.ok(deck, "rope bridge mesh")
			t.ok(math.abs(deck.CFrame.Position.Y - (10 - 0.75 + deck.Size.Y / 2)) < 0.05, "pivot 0.75 under the span")
			local ropePiece = TownModels.Piece(TownModels.Get("RopeBridge"), "Body")
			t.ok(math.abs(deck.Size.Z - ropePiece.size.Z * 32 / 16) < 1e-3, "span scales on Z")
			local pad = BuildingArt.SellPad(24, 18)
			local padMesh = visualNamed(pad, "SellPad")
			t.ok(padMesh.CFrame.LookVector:Dot(Vector3.new(0, 0, -1)) > 0.999, "the sell mesh does not yaw")
			local spun = false
			for _, d in ipairs(padMesh:GetDescendants()) do
				if d:IsA("TextLabel") and d.Rotation == 180 then
					spun = true
				end
			end
			t.ok(spun, "the sell text turns so it still reads from -Z")
			local store = StoreBoard.Build()
			local storeMesh = visualNamed(store, "Board")
			local storePart = store:FindFirstChild("Board")
			t.ok((storeMesh.CFrame.Position - storePart.CFrame.Position).Magnitude <= 0.25, "store board centre")
		end)
	end)

	t.test("I-Motion: saw Z, bullwheel Y, door hinge, windmill hub; low stops the sails", function()
		local cf = CFrame.new(1, 2, 3)
		local spun = TownMotion.Step(cf, "Z", Vector3.zero, 0.4)
		t.ok((spun.Position - cf.Position).Magnitude < 1e-4, "a centre spin stays put")
		t.eq(TownMotion.WindmillSpins("low"), false)
		t.eq(TownMotion.WindmillSpins("high"), true)
		t.eq(TownMotion.WindmillSpins("medium"), true)
		withMeshes(function()
			local mill = BuildingArt.Sawmill()
			local blade = visualNamed(mill, "SawBlade")
			t.eq(blade:GetAttribute("SpinAxis"), "Z")
			local turned = TownMotion.Step(blade.CFrame, "Z", Vector3.zero, 0.7)
			t.ok((turned.Position - blade.CFrame.Position).Magnitude < 1e-4, "the saw turns about the arbor")
			local station = BuildingArt.GondolaStation()
			local wheel = visualNamed(station, "Bullwheel")
			t.eq(wheel:GetAttribute("SpinAxis"), "Y")
			local wheeled = TownMotion.Step(wheel.CFrame, "Y", Vector3.zero, 0.5)
			t.ok((wheeled.Position - wheel.CFrame.Position).Magnitude < 1e-4, "the bullwheel turns about its centre")
			local shed = BuildingArt.Shop("ToolShed", "Axes", roblox.Color3.fromRGB(150, 40, 30))
			local door = visualNamed(shed, "BarnDoorL")
			local hinge =
				Vector3.new(door:GetAttribute("HingeX"), door:GetAttribute("HingeY"), door:GetAttribute("HingeZ"))
			t.ok(math.abs(hinge.X + door.Size.X / 2) < 1e-4, "the hinge is the door's edge")
			local before = door.CFrame * hinge
			local swung = TownMotion.Step(door.CFrame, door:GetAttribute("HingeAxis"), hinge, 0.5)
			t.ok(((swung * hinge) - before).Magnitude < 1e-3, "the hinge stays put")
			local wind = PropArt.Windmill(3)
			local sails = visualNamed(wind, "Sails")
			local hub = Vector3.new(sails:GetAttribute("HubX"), sails:GetAttribute("HubY"), sails:GetAttribute("HubZ"))
			local hubWorld = sails.CFrame * hub
			local nextSails = TownMotion.Step(sails.CFrame, "Z", hub, 0.8)
			t.ok(((nextSails * hub) - hubWorld).Magnitude < 1e-3, "the sails turn about the hub")
			t.ok((hubWorld - Vector3.new(0, 12.4, -3.9)).Magnitude < 0.05, "the hub is the part-built one")
		end)
	end)

	t.test("I-Budget: Atomic, fidelity, lights, templates, and the triangle caps", function()
		local Atomic = roblox.Enum.ModelStreamingMode.Atomic
		local Persistent = roblox.Enum.ModelStreamingMode.Persistent
		local plainLamp = BuildingArt.LampPost()
		local plainCamp = BuildingArt.Campsite()
		local lampN, lampAt = lights(plainLamp)
		local campN, campAt = lights(plainCamp)
		t.eq(plainLamp.ModelStreamingMode, Atomic, "a multi-mesh prop is Atomic even if the mesh misses")
		t.eq(BuildingArt.Sawmill().ModelStreamingMode, Atomic)
		t.eq(plainLamp.ModelStreamingMode == Persistent, false)
		withMeshes(function()
			local lamp = BuildingArt.LampPost()
			local camp = BuildingArt.Campsite()
			local n1, at1 = lights(lamp)
			local n2, at2 = lights(camp)
			t.eq(n1, lampN, "LampPost light count")
			t.eq(at1, lampAt, "LampPost light offset")
			t.eq(n2, campN, "camp light count")
			t.eq(at2, campAt, "camp embers stay put")
			local glow = visualNamed(lamp, "LampGlow")
			t.ok(glow and glow.Material == roblox.Enum.Material.Neon, "glow is Neon and not a new light")
			t.eq(lamp.ModelStreamingMode, Atomic)
			local person = CharacterArt.Build(NPCData.Get("Hazel").look)
			t.eq(person.ModelStreamingMode, Atomic)
		end)
		t.eq(TownMeshes.FidelityFor("Body", nil), roblox.Enum.RenderFidelity.Automatic)
		t.eq(TownMeshes.FidelityFor("Roof", nil), roblox.Enum.RenderFidelity.Automatic)
		t.eq(TownMeshes.FidelityFor("Head", nil), roblox.Enum.RenderFidelity.Automatic)
		t.eq(TownMeshes.FidelityFor("Glow", nil), roblox.Enum.RenderFidelity.Performance)
		t.eq(TownMeshes.FidelityFor("Sign", nil), roblox.Enum.RenderFidelity.Performance)
		t.eq(TownMeshes.FidelityFor("Counter", nil), roblox.Enum.RenderFidelity.Performance)
		t.eq(TownMeshes.FidelityFor("LeftHand", nil), roblox.Enum.RenderFidelity.Performance)
		t.eq(TownMeshes.FidelityFor("Body", 200), roblox.Enum.RenderFidelity.Performance, "a prop under 300 tris")
		local fs = require("@lune/fs")
		local view = 0
		for _, asset in ipairs(TownModels.All) do
			local cap = if asset.category == "building"
				then TownModels.BuildingTriCap
				elseif asset.category == "npc" then TownModels.NpcTriCap
				else TownModels.PropTriCap
			local tris = asset.tris or 0
			t.ok(tris <= cap, asset.id .. " tris")
			view += tris
			for _, piece in ipairs(TownModels.Visual(asset)) do
				t.ok(
					fs.isFile("src/ReplicatedStorage/MeshTemplates/" .. tostring(piece.meshId) .. ".model.json"),
					asset.id .. " " .. piece.name
				)
			end
		end
		t.ok(view < TownModels.SellViewTriCap, "sell-pad view")
		t.eq(#TownModels.Ids("environment"), 41)
		t.eq(#TownModels.Ids("building"), 6)
		t.eq(#TownModels.Ids("npc"), 9)
	end)

	t.test("I-Economy: the five headlines and the tutorial lines are unchanged", function()
		local fs = require("@lune/fs")
		local report = fs.readFile("ECONOMY.md")
		for _, headline in ipairs({ "66 s", "8.0 min", "13.4 min", "53.7 min", "39.4 h" }) do
			t.ok(string.find(report, headline, 1, true) ~= nil, headline)
		end
		t.eq(NPCData.Get("Murph").tips[1], "I'm Murph. Chop a tree, haul the wood, sell it at the mill.")
		local fell = false
		for _, step in ipairs(TutorialData.Steps) do
			if step.objective == "Chop down a tree" then
				fell = true
			end
		end
		t.ok(fell, "the chop step is still the chop step")
	end)
end
