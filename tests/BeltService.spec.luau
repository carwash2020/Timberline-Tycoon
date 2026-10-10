--!nocheck
-- Belts run while their owner is online and the plot has room, in the
-- direction each belt part faces; a turn piece has three parts, each aimed.
return function(t)
	local V3 = t.roblox.Vector3
	local loader = t.loader({
		services = {
			Players = {
				GetPlayers = function()
					return {}
				end,
				GetPlayerByUserId = function()
					return nil
				end,
			},
			PhysicsService = {},
		},
		mocks = {},
	})
	local Belt = loader:server("BeltService")
	local MachineArt = loader:load("ReplicatedStorage/Shared/Art/MachineArt")
	local Logic = loader:shared("AutomationLogic")
	local Config = loader:shared("GameConfig")

	local function conveyors(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d.Name == "Conveyor" and d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	t.test("each piece of the kit builds with belt parts that carry wood toward its exit", function()
		for _, id in ipairs({ "ConveyorStraight", "ConveyorTurn", "ConveyorFunnel" }) do
			local model = MachineArt.BuildBelt(id, false)
			t.ok(model ~= nil, id)
			t.eq(model:GetAttribute("MachineId"), id)
			t.ok(model:HasTag(Logic.Tag), "tagged for BeltService")
			local belts = conveyors(model)
			t.ok(#belts >= 1, id .. " has belt parts")
			for _, belt in ipairs(belts) do
				t.ok(belt.CanCollide and belt.CollisionGroup == "MillBelt", "wood rides it, players walk through")
				t.eq(belt.Anchored ~= false, true)
				t.eq(belt.CanTouch, false)
			end
			local root = model.PrimaryPart
			t.ok(root ~= nil and root.Transparency == 1, "an invisible pivot slab")
			local count = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					count += 1
				end
			end
			-- 20, was 16: the TLD-1 deck is 8 rollers at the 1.0 pitch plus plate,
			-- pan, rails, caps and collars on a straight (job 15). With the meshes
			-- loaded a straight is 8 (root, band, two rails and four mesh pieces).
			t.ok(count <= 20, id .. " keeps its part budget: " .. count)
		end
		t.eq(#conveyors(MachineArt.BuildBelt("ConveyorTurn", false)), 3, "a turn is entry, corner and exit")
		-- The straight belt runs toward +Z, like a sawmill's.
		local straight = conveyors(MachineArt.BuildBelt("ConveyorStraight", false))[1]
		t.ok(straight.CFrame.LookVector.Z > 0.9)
		MachineArt.AimBelt(MachineArt.BuildBelt("ConveyorStraight", false))
		-- A turn's corner and exit run along +X.
		local turn = MachineArt.BuildBelt("ConveyorTurn", false)
		MachineArt.AimBelt(turn)
		local seenX = 0
		for _, belt in ipairs(conveyors(turn)) do
			if belt.AssemblyLinearVelocity.X > Config.ConveyorSpeed - 0.01 then
				seenX += 1
			end
		end
		t.eq(seenX, 2, "the corner and the exit carry wood to +X")
		t.eq(MachineArt.BuildBelt("Nope", false), nil)
		local ghost = MachineArt.BuildBelt("ConveyorFunnel", true)
		t.ok(not ghost:HasTag(Logic.Tag), "a ghost is not a belt")
		for _, d in ipairs(ghost:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "Root" then
				t.eq(d.CanCollide, false, d.Name)
			end
		end
	end)

	t.test("belts run at ConveyorSpeed while the owner is online and the plot has room, and stop otherwise", function()
		local mine = MachineArt.BuildBelt("ConveyorStraight", false)
		mine:SetAttribute("OwnerId", 1)
		local theirs = MachineArt.BuildBelt("ConveyorStraight", false)
		theirs:SetAttribute("OwnerId", 2)
		local online = { [1] = true, [2] = true }
		local loose = { [1] = 0, [2] = 0 }
		Belt._use({
			belts = function()
				return { mine, theirs }
			end,
			online = function(id)
				return online[id] == true
			end,
			outputs = function(id)
				return loose[id]
			end,
		})
		local function speedOf(model)
			return conveyors(model)[1].AssemblyLinearVelocity.Magnitude
		end
		t.eq(Belt.Tick(), 2)
		t.ok(math.abs(speedOf(mine) - Config.ConveyorSpeed) < 1e-6)
		t.eq(mine:GetAttribute("Running"), true)
		-- Ann leaves: her belt stops, Bob's keeps going (two players, two plots).
		online[1] = false
		t.eq(Belt.Tick(), 1)
		t.eq(speedOf(mine), 0, "no offline production")
		t.ok(speedOf(theirs) > 0)
		t.eq(mine:GetAttribute("Running"), false)
		-- Back online, but the plot is full of planks: stopped until some leave.
		online[1] = true
		loose[1] = Logic.MaxLooseOutputs
		t.eq(Belt.Tick(), 1)
		t.eq(speedOf(mine), 0, "a full plot stops the line")
		loose[1] = Logic.MaxLooseOutputs - 1
		t.eq(Belt.Tick(), 2)
		-- A belt with no owner never runs.
		local orphan = MachineArt.BuildBelt("ConveyorStraight", false)
		Belt._use({
			belts = function()
				return { orphan }
			end,
		})
		t.eq(Belt.Tick(), 0)
		Belt._reset()
		t.eq(Belt.Tick(), 0, "no context, nothing to do")
		mine:Destroy()
		theirs:Destroy()
		orphan:Destroy()
		t.ok(V3 ~= nil)
	end)
end
