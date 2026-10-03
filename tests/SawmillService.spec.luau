--!nocheck
-- A placed mill takes a rested straight log and gives its volume back as planks.
return function(t)
	local V3 = t.roblox.Vector3
	local CFrame = t.roblox.CFrame
	local Instance = t.roblox.Instance
	local owner = nil
	local profile = { plot = { placed = {} } }
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
		mocks = {
			RateLimiter = {
				Allow = function()
					return true
				end,
			},
			ProfileService = {
				GetProfile = function(p)
					return if p == owner then profile else nil
				end,
			},
		},
	})
	local Sawmill = loader:server("SawmillService")
	local MachineArt = loader:load("ReplicatedStorage/Shared/Art/MachineArt")
	local Logic = loader:shared("SawmillLogic")
	local Sell = loader:shared("SellLogic")
	local Catalog = loader:shared("ItemCatalog")

	local function logPart(size, cf)
		local part = Instance.new("Part")
		part.Name = "Section"
		part.Size = size
		part.CFrame = cf
		local model = Instance.new("Model")
		part.Parent = model
		model.PrimaryPart = part
		return model, part
	end

	t.test("a rested oak log becomes planks of the same volume, and a plank does not", function()
		local mill = MachineArt.Build("SawmillRickety", false)
		mill.Parent = Instance.new("Folder")
		local intake = mill:FindFirstChild("Intake")
		local size = V3.new(2, 9, 2)
		local model, part = logPart(size, intake.CFrame)
		model.Parent = Instance.new("Folder")
		local volume = Sell.VolumeU3(size.X, size.Y, size.Z)
		local piece = {
			model = model,
			root = part,
			kind = "log",
			woodId = "oak",
			parts = { [1] = part },
			nodes = { [1] = { parent = nil, children = {} } },
			volume = volume,
			ownerId = 7,
			figure = "curly",
			boost = 1.2,
			lastHolderId = 4,
			verdictOk = true,
			selling = nil,
			dead = nil,
			shopItem = nil,
		}
		local spawned = {}
		local removed = 0
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
				return { mill }
			end,
			release = function() end,
			remove = function(p)
				removed += 1
				p.dead = true
			end,
			spawn = function(info)
				table.insert(spawned, info)
				return nil
			end,
			moved = function() end,
		})
		Sawmill.Tick()
		t.eq(#spawned, 0, "it has to rest")
		t.eq(piece.selling, nil)
		now = Sawmill.Settle
		Sawmill.Tick()
		t.eq(piece.selling, true)
		t.eq(part.Anchored, true)
		-- Snapped onto the belt: length along the feed, centred, not still
		-- wherever it was dropped.
		local belt = mill:FindFirstChild("Conveyor")
		t.ok(part.CFrame.UpVector:Dot(belt.CFrame.LookVector) > 0.99, "the log lies along the belt")
		t.ok(math.abs(part.CFrame.X) < 0.2, "centred, clear of the walls")
		t.ok(part.CFrame.Y > belt.CFrame.Position.Y, "sitting on the belt")
		local before = part.CFrame.Position
		now += Logic.ProcessSeconds(volume) / 2
		Sawmill.Tick()
		local moved = part.CFrame.Position - before
		t.ok(moved.Z > 0.2 and math.abs(moved.X) < 1e-3, "it feeds along the belt, not through a wall")
		local expect = Logic.Cut(
			volume,
			Logic.DefaultSettings(Catalog.GetSawmill("SawmillRickety")),
			Catalog.GetSawmill("SawmillRickety")
		)
		now += Logic.ProcessSeconds(volume)
		for _ = 1, #expect + 2 do
			Sawmill.Tick()
			now += Sawmill.PlankGap
		end
		t.eq(removed, 1, "the log is gone once")
		t.eq(#spawned, #expect)
		local back = 0
		for _, info in ipairs(spawned) do
			t.eq(info.woodId, "oak")
			t.eq(info.ownerId, 7)
			t.eq(info.figure, "curly")
			t.eq(info.boost, 1.2)
			t.eq(info.lastHolderId, 4)
			back += Sell.VolumeU3(info.size.X, info.size.Y, info.size.Z)
		end
		t.ok(math.abs(back - volume) < 1e-3, "the planks add up to the log")
		piece.kind = "plank"
		piece.dead = nil
		piece.selling = nil
		now += 5
		Sawmill.Tick()
		now += 5
		Sawmill.Tick()
		t.eq(#spawned, #expect, "a plank is not milled again")
		mill:Destroy()
		Sawmill._reset()
	end)

	t.test("only the owner, standing at the mill, can step the cut", function()
		local mill = MachineArt.Build("SawmillRickety", false)
		mill:SetAttribute("Uid", "mill-1")
		mill:SetAttribute("OwnerId", 1)
		mill:PivotTo(CFrame.new())
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		local function player(userId, at)
			root.Position = at
			return {
				UserId = userId,
				Character = {
					FindFirstChild = function(_, name)
						return if name == "HumanoidRootPart" then root else nil
					end,
				},
			}
		end
		profile.plot.placed = {
			{ uid = "mill-1", blueprintId = "SawmillRickety", x = 0, z = 0, rot = 0 },
		}
		Sawmill._use({
			notify = function() end,
			mills = function()
				return { mill }
			end,
		})
		owner = player(1, V3.zero)
		Sawmill.Set(owner, "mill-1", "x", 1)
		t.eq(mill:GetAttribute("CutX"), 1.2)
		t.eq(mill:GetAttribute("CutY"), 0.6)
		t.eq(profile.plot.placed[1].data, { x = 1.2, y = 0.6 })
		local other = player(2, V3.zero)
		Sawmill.Set(other, "mill-1", "x", 1)
		t.eq(mill:GetAttribute("CutX"), 1.2, "someone else can't change it")
		owner = player(1, V3.new(80, 0, 0))
		Sawmill.Set(owner, "mill-1", "y", 1)
		t.eq(mill:GetAttribute("CutY"), 0.6, "too far away")
		owner = player(1, V3.zero)
		Sawmill.Set(owner, "mill-1", "z", 1)
		Sawmill.Set(owner, "mill-1", "x", 2)
		t.eq(mill:GetAttribute("CutX"), 1.2, "only one step, on x or y")
		mill:Destroy()
		owner = nil
		Sawmill._reset()
	end)
end
