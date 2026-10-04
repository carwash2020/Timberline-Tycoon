--!nocheck
-- The toll sample, the setback landing, and the gorge rescue.
return function(t)
	local Instance = t.roblox.Instance
	local CFrame = t.roblox.CFrame
	local Vector3 = t.roblox.Vector3
	local WorldLayout = t.shared("World/WorldLayout")
	local TerrainGen = t.shared("World/TerrainGen")
	local LandmarkArt = t.shared("Art/LandmarkArt")

	local function boot()
		local players = {}
		local service = {
			GetPlayers = function()
				return players
			end,
			GetPlayerFromCharacter = function(_, char)
				for _, p in ipairs(players) do
					if p.Character == char then
						return p
					end
				end
				return nil
			end,
		}
		local loader = t.loader({ services = { Players = service } })
		return loader:server("GateService"), players
	end

	local function person(players, userId)
		local char = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Parent = char
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = char
		char.PrimaryPart = root
		local player = { UserId = userId, Character = char }
		table.insert(players, player)
		return player, root, humanoid, char
	end

	t.test("vehicle samples are weak-keyed", function()
		local Gate = boot()
		t.eq(getmetatable(Gate.VehicleSample).__mode, "k")
	end)

	t.test("a paid driver who exits north after the window expires is not moved", function()
		local Gate, players = boot()
		local player, root, humanoid = person(players, 7)
		local vehicle = Instance.new("Model")
		local chassis = Instance.new("Part")
		chassis.Parent = vehicle
		vehicle.PrimaryPart = chassis
		local seat = Instance.new("VehicleSeat")
		seat.Parent = vehicle

		local function put(z)
			root.CFrame = CFrame.new(0, 40, z)
			chassis.CFrame = CFrame.new(0, 40, z)
		end

		-- On foot, south of the line, so the character sample exists.
		-- SeatPart cannot be cleared to nil here, so a loose part stands in
		-- for "not sitting in this truck".
		local loose = Instance.new("Part")
		humanoid.SeatPart = loose
		put(1560)
		Gate.Step(1000)

		-- Sit, pay, and cross. The sample has to follow them while seated.
		Gate.TollPaidUntil[player.UserId] = 2000
		humanoid.SeatPart = seat
		seat.Occupant = humanoid
		put(1700)
		Gate.Step(1001)
		t.ok(root.CFrame.Position.Z > WorldLayout.TollLineZ, "the paid crossing stands")
		local stayed = root.CFrame.Position.Z

		-- The window expires. They get out, still north. That is not a new crossing.
		Gate.TollPaidUntil[player.UserId] = 1000
		humanoid.SeatPart = loose
		Gate.Step(1010)
		t.ok(math.abs(root.CFrame.Position.Z - stayed) < 1e-3, string.format("moved to z %.1f", root.CFrame.Position.Z))
	end)

	t.test("an unpaid crossing lands above the ground with no velocity", function()
		local Gate, players = boot()
		local _, root = person(players, 7)
		local heard = {}
		Gate.Notify = function(_, message)
			table.insert(heard, message)
		end
		root.CFrame = CFrame.new(4, 80, 1560)
		root.AssemblyLinearVelocity = Vector3.new(0, 12, 90)
		root.AssemblyAngularVelocity = Vector3.new(0, 3, 0)
		Gate.Step(1)
		root.CFrame = CFrame.new(4, 80, 1700)
		Gate.Step(2)
		local land = root.CFrame.Position
		t.ok(land.Z < WorldLayout.TollLineZ, "still north")
		t.eq(land.X, WorldLayout.TollPushX)
		t.eq(land.Z, WorldLayout.TollPushZ)
		t.ok(land.Y > TerrainGen.HeightAt(land.X, land.Z), "inside the ground")
		t.eq(root.AssemblyLinearVelocity, Vector3.zero)
		t.eq(root.AssemblyAngularVelocity, Vector3.zero)
		t.eq(heard[1], "The toll booth opens soon.")
	end)

	t.test("a welded driver who crosses unpaid lands the truck once, on the landing", function()
		local Gate, players = boot()
		local TollLogic = t.shared("TollLogic")
		local _, root, humanoid = person(players, 7)
		local vehicle = Instance.new("Model")
		local chassis = Instance.new("Part")
		chassis.Name = "Chassis"
		chassis.Parent = vehicle
		vehicle.PrimaryPart = chassis
		local seat = Instance.new("VehicleSeat")
		seat.Parent = vehicle
		-- The seat weld lives on the driver. PivotTo of the character
		-- follows it into the truck, and the body weld (under the seat,
		-- outside the character) has to come along too.
		local seatWeld = Instance.new("Weld")
		seatWeld.Name = "SeatWeld"
		seatWeld.Part0 = seat
		seatWeld.Part1 = root
		seatWeld.Parent = root
		local bodyWeld = Instance.new("WeldConstraint")
		bodyWeld.Part0 = chassis
		bodyWeld.Part1 = seat
		bodyWeld.Parent = seat
		humanoid.SeatPart = seat
		seat.Occupant = humanoid

		local function put(z)
			local at = CFrame.new(0, 40, z)
			root.CFrame = at
			chassis.CFrame = at
			seat.CFrame = at
		end

		put(1560)
		Gate.Step(1)
		put(1700)
		Gate.Step(2)
		t.eq(vehicle:GetPivot().Position, TollLogic.Landing())
	end)

	t.test("a loose plank in a pile lands alone and the anchored sibling stays", function()
		local Gate = boot()
		local TollLogic = t.shared("TollLogic")
		local pile = Instance.new("Model")
		pile.Name = "Planks"
		local sibling = Instance.new("Part")
		sibling.Name = "Stack"
		sibling.Anchored = true
		sibling.CFrame = CFrame.new(30, 8, 1400)
		sibling.Parent = pile
		pile.PrimaryPart = sibling
		local stayed = sibling.CFrame
		local plank = Instance.new("Part")
		plank.Name = "Plank"
		plank.Anchored = false
		plank.CFrame = CFrame.new(4, 80, 1700)
		plank.Parent = pile
		plank.AssemblyRootPart = plank
		Gate.RescueHit(plank)
		t.eq(sibling.CFrame, stayed)
		t.eq(plank.CFrame.Position, TollLogic.Landing())
	end)

	t.test("a body dropped on the gorge floor ends up south of the line on solid ground", function()
		local Gate = boot()
		local folder = Instance.new("Folder")
		LandmarkArt.BuildW2(folder)
		local floor = folder:FindFirstChild("GorgeFloor", true)
		t.ok(floor, "the trigger")
		local body = Instance.new("Part")
		body.Name = "Body"
		body.Anchored = false
		body.Size = Vector3.new(2, 5, 2)
		body.CFrame = floor.CFrame
		body.AssemblyLinearVelocity = Vector3.new(3, -40, 20)
		body.AssemblyAngularVelocity = Vector3.new(1, 0, 2)
		local model = Instance.new("Model")
		model.Name = "Dropped"
		body.Parent = model
		model.PrimaryPart = body
		t.ok(WorldLayout.InGorge(body.CFrame.Position.X, body.CFrame.Position.Z), "it starts in the cut")
		Gate.RescueHit(body)
		local at = body.CFrame.Position
		t.ok(at.Z < WorldLayout.TollLineZ, string.format("still in the gorge at z %.1f", at.Z))
		t.ok(at.Y > TerrainGen.HeightAt(at.X, at.Z), "inside the ground")
		t.eq(body.AssemblyLinearVelocity, Vector3.zero)
		t.eq(body.AssemblyAngularVelocity, Vector3.zero)
	end)
end
