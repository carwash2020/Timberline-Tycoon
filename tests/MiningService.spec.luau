--!nocheck
-- MiningService: NaN bombs, one smelt charge, crawl toward the mouth,
-- the shop's 12-stud reach, and the Obsidian turn-in.

return function(t)
	local Instance = t.roblox.Instance
	local CFrame = t.roblox.CFrame
	local Vector3 = t.roblox.Vector3

	local function signal()
		return {
			Connect = function()
				return { Disconnect = function() end }
			end,
		}
	end
	pcall(t.roblox.implementProperty, "Tool", "Activated", signal)
	pcall(t.roblox.implementProperty, "Tool", "Equipped", signal)
	pcall(t.roblox.implementProperty, "Tool", "Unequipped", signal)
	pcall(t.roblox.implementProperty, "ProximityPrompt", "Triggered", signal)

	local function place(part, pos)
		part.CFrame = CFrame.new(pos)
		part.Position = pos
	end

	local function setup(cash, mining, clockNow)
		local world = Instance.new("Folder")
		world.Name = "Workspace"
		local profile = {
			cash = cash,
			pendingCash = 0,
			totalEarned = 0,
			gear = {},
			passes = {},
			mining = mining,
		}
		local player = {
			UserId = 7,
			Name = "Tester",
			attrs = {},
			SetAttribute = function(self, key, value)
				self.attrs[key] = value
			end,
			GetAttribute = function(self, key)
				return self.attrs[key]
			end,
		}
		local backpack = Instance.new("Folder")
		backpack.Name = "Backpack"
		player.FindFirstChildOfClass = function(_, class)
			if class == "Backpack" then
				return backpack
			end
			return nil
		end
		local players = {
			GetPlayerByUserId = function(_, id)
				return if id == player.UserId then player else nil
			end,
			GetPlayers = function()
				return { player }
			end,
		}
		player.Parent = players
		local function stand(pos)
			local character = Instance.new("Model")
			character.Name = "Character"
			local root = Instance.new("Part")
			root.Name = "HumanoidRootPart"
			root.Size = Vector3.new(2, 2, 1)
			place(root, pos)
			root.Parent = character
			character.PrimaryPart = root
			player.Character = character
			return root
		end
		local clock = { now = clockNow or 0 }
		local globals = nil
		if clockNow ~= nil then
			globals = {
				os = setmetatable({
					clock = function()
						return clock.now
					end,
				}, { __index = os }),
			}
		end
		local loader = t.loader({
			globals = globals,
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
				},
			},
			services = {
				Workspace = world,
				Players = players,
			},
		})
		local Mining = loader:server("MiningService")
		local function miningFolder()
			local folder = world:FindFirstChild("Mining")
			if folder == nil then
				folder = Instance.new("Folder")
				folder.Name = "Mining"
				folder.Parent = world
			end
			return folder
		end
		return {
			Mining = Mining,
			profile = profile,
			player = player,
			world = world,
			stand = stand,
			miningFolder = miningFolder,
			clock = clock,
		}
	end

	local function stall(folder, at)
		local model = Instance.new("Model")
		model.Name = "Prospector"
		local counter = Instance.new("Part")
		counter.Name = "Counter"
		counter.Size = Vector3.new(6, 1, 2)
		place(counter, at)
		counter.Parent = model
		model.PrimaryPart = counter
		model.Parent = folder
		return model
	end

	local function ingot(folder, ownerId, at)
		local model = Instance.new("Model")
		model.Name = "Ingot"
		local part = Instance.new("Part")
		part.Size = Vector3.new(1, 0.4, 2)
		place(part, at)
		part.Parent = model
		model.PrimaryPart = part
		model:SetAttribute("Ore", "TimberOpal")
		model:SetAttribute("OwnerId", ownerId)
		model.Parent = folder
		return model
	end

	local function stillThere(model)
		return model.Parent ~= nil
	end

	t.test("buyBomb with 0/0 leaves cash and bombs unchanged", function()
		local world = setup(500, { bombs = 4, picks = { RustyPick = true }, pick = "RustyPick" })
		stall(world.miningFolder(), Vector3.zero)
		world.stand(Vector3.new(0, 0, 4))
		world.Mining.Handle(world.player, "buyBomb", nil, 0 / 0)
		t.eq(world.profile.cash, 500)
		t.eq(world.profile.mining.bombs, 4)
	end)

	t.test("buyPick, buyBomb and turnIn require the prospector stall", function()
		local far = setup(100000, nil)
		stall(far.miningFolder(), Vector3.zero)
		far.stand(Vector3.new(0, 0, 40))
		far.Mining.Handle(far.player, "buyPick", "CopperPick", nil)
		far.Mining.Handle(far.player, "buyBomb", nil, 1)
		local kept = ingot(far.miningFolder(), far.player.UserId, Vector3.zero)
		far.Mining.Handle(far.player, "turnIn", nil, nil)
		t.eq(far.profile.cash, 100000)
		t.eq(far.profile.mining.picks.CopperPick, nil)
		t.eq(far.profile.mining.bombs, 0)
		t.eq(stillThere(kept), true)
		t.eq(far.profile.mining.crafted.HeartstoneTurnIn, nil)

		local near = setup(100000, nil)
		stall(near.miningFolder(), Vector3.zero)
		near.stand(Vector3.new(0, 0, 4))
		near.Mining.Handle(near.player, "buyPick", "CopperPick", nil)
		near.Mining.Handle(near.player, "buyBomb", nil, 1)
		t.eq(near.profile.mining.picks.CopperPick, true)
		t.eq(near.profile.mining.bombs, 1)
		t.eq(near.profile.cash, 100000 - 450 - 220)
	end)

	t.test("four Timber Opal ingots are refused and none are consumed", function()
		local world = setup(50000, { picks = { RustyPick = true, SteelPick = true }, pick = "SteelPick" })
		stall(world.miningFolder(), Vector3.zero)
		world.stand(Vector3.new(0, 0, 4))
		local owned = {}
		for i = 1, 4 do
			owned[i] = ingot(world.miningFolder(), world.player.UserId, Vector3.new(i, 0, 0))
		end
		local stranger = ingot(world.miningFolder(), 99, Vector3.new(0, 1, 0))
		world.Mining.Handle(world.player, "turnIn", nil, nil)
		for _, model in ipairs(owned) do
			t.eq(stillThere(model), true)
		end
		t.eq(stillThere(stranger), true)
		t.eq(world.profile.mining.crafted.HeartstoneTurnIn, nil)
		t.eq(world.profile.cash, 50000)
		t.eq(world.profile.mining.picks.ObsidianPick, nil)
	end)

	t.test("five Timber Opal ingots grant the Obsidian Pick from a Steel save", function()
		local world = setup(50000, { picks = { RustyPick = true, SteelPick = true }, pick = "SteelPick" })
		stall(world.miningFolder(), Vector3.zero)
		world.stand(Vector3.new(0, 0, 4))
		local owned = {}
		for i = 1, 5 do
			owned[i] = ingot(world.miningFolder(), world.player.UserId, Vector3.new(i, 0, 0))
		end
		local extra = ingot(world.miningFolder(), world.player.UserId, Vector3.new(8, 0, 0))
		world.Mining.Handle(world.player, "turnIn", nil, nil)
		local left = 0
		for _, model in ipairs(owned) do
			if stillThere(model) then
				left += 1
			end
		end
		t.eq(left, 0)
		t.eq(stillThere(extra), true)
		t.eq(world.profile.mining.crafted.HeartstoneTurnIn, 1)
		world.Mining.Handle(world.player, "buyPick", "ObsidianPick", nil)
		t.eq(world.profile.mining.picks.ObsidianPick, true)
		t.eq(world.profile.cash, 0)
		t.eq(world.profile.mining.pick, "ObsidianPick")
	end)

	t.test("a coal-less chunk left 3s in SmeltIntake is charged $2 once", function()
		local world = setup(40, nil, 1000)
		local folder = world.miningFolder()
		local intake = Instance.new("Part")
		intake.Name = "SmeltIntake"
		intake.Size = Vector3.new(20, 20, 20)
		place(intake, Vector3.zero)
		intake.Parent = folder
		local chunk = Instance.new("Model")
		chunk.Name = "OreChunk"
		local part = Instance.new("Part")
		part.Size = Vector3.new(1, 1, 1)
		place(part, Vector3.zero)
		part.Parent = chunk
		chunk.PrimaryPart = part
		chunk:SetAttribute("Uid", "chunk-1")
		chunk:SetAttribute("Ore", "Copper")
		chunk:SetAttribute("OwnerId", world.player.UserId)
		chunk:SetAttribute("Value", 10)
		chunk.Parent = folder
		world.Mining.SettleNow()
		world.Mining.SettleNow()
		t.eq(world.profile.cash, 38)
		world.clock.now = 1004
		world.Mining.SettleNow()
		t.eq(world.profile.cash, 38)
	end)

	t.test("crawl out of mine-mid ends past the wall, and a reseal still lets you out", function()
		local MineSites = t.load("ReplicatedStorage/Shared/Mining/MineSites")
		local sites = MineSites.Fallback()
		local mid = nil
		for _, wall in ipairs(sites.rubble) do
			if wall.id == "mine-mid" then
				mid = wall
			end
		end
		local function wallModel()
			local model = Instance.new("Model")
			model.Name = "Rubble"
			local part = Instance.new("Part")
			part.Name = "Wall"
			part.Size = Vector3.new(16, 12, 6)
			part.CFrame = CFrame.new(mid.x, mid.y, mid.z)
			part.Parent = model
			model.PrimaryPart = part
			return model
		end
		local exit = Vector3.new(mid.ex, 0, mid.ez)

		local open = setup(0, nil)
		local openWall = wallModel()
		open.Mining.TrackRubble("mine-mid", openWall, exit, 1e9)
		local cf, size = openWall:GetBoundingBox()
		local root = open.stand(cf.Position)
		t.eq(open.Mining.Crawl(open.player), true)
		t.ok(root.CFrame.Position.Z > -214, string.format("open z %.2f", root.CFrame.Position.Z))

		local shut = setup(0, nil)
		local shutWall = wallModel()
		shut.Mining.TrackRubble("mine-mid", shutWall, exit, nil)
		local shutCf, shutSize = shutWall:GetBoundingBox()
		local dir = Vector3.new(mid.ex, 0, mid.ez).Unit
		local extent = math.abs(dir.X) * shutSize.X / 2
			+ math.abs(dir.Y) * shutSize.Y / 2
			+ math.abs(dir.Z) * shutSize.Z / 2
		local trapped = shutCf.Position + dir * (-extent - 2)
		local shutRoot = shut.stand(trapped)
		t.eq(shut.Mining.Crawl(shut.player), true)
		t.ok(shutRoot.CFrame.Position.Z > -214, string.format("reseal z %.2f", shutRoot.CFrame.Position.Z))
		t.eq(size ~= nil, true)
	end)
end
