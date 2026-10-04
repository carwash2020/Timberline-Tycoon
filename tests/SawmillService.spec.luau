--!nocheck
-- A placed mill takes a rested straight log and gives its volume back as planks.
return function(t)
	local V3 = t.roblox.Vector3
	local CFrame = t.roblox.CFrame
	local Instance = t.roblox.Instance
	local owner = nil
	local toastPlayer = nil
	local profile = { plot = { placed = {} } }
	local loader = t.loader({
		services = {
			Players = {
				GetPlayers = function()
					return {}
				end,
				GetPlayerByUserId = function(_, id)
					if toastPlayer and toastPlayer.UserId == id then
						return toastPlayer
					end
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
	local Config = loader:shared("GameConfig")

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

	t.test("a rested oak log becomes planks of the same volume, and those planks mill again", function()
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
			lux = true,
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
			t.eq(info.lux, true, "planks keep the Lux tag, they don't add another")
			t.eq(info.lastHolderId, 4)
			back += Sell.VolumeU3(info.size.X, info.size.Y, info.size.Z)
		end
		t.ok(math.abs(back - volume) < 1e-3, "the planks add up to the log")
		-- Those planks, fed back at a smaller cut, come out thinner. The
		-- volume is the same and they are still planks (the spawn path).
		piece.kind = "plank"
		piece.dead = nil
		piece.selling = nil
		part.Anchored = false
		mill:SetAttribute("CutX", 0.6)
		mill:SetAttribute("CutY", 0.4)
		local before = #spawned
		now += 5
		Sawmill.Tick()
		t.eq(#spawned, before, "a plank rests before the second cut")
		now += 1
		Sawmill.Tick()
		t.eq(piece.selling, true, "the plank is taken")
		now += Logic.ProcessSeconds(volume)
		local again = Logic.Cut(volume, { x = 0.6, y = 0.4 }, Catalog.GetSawmill("SawmillRickety"))
		for _ = 1, #again + 2 do
			Sawmill.Tick()
			now += Sawmill.PlankGap
		end
		t.eq(#spawned, before + #again, "the plank was cut again")
		local back2 = 0
		for i = before + 1, #spawned do
			local info = spawned[i]
			t.eq(info.woodId, "oak")
			t.eq(info.figure, "curly")
			t.eq(info.boost, 1.2)
			t.ok(math.abs(info.size.X - 0.6 * Config.WoodUnit) < 1e-6, "thinner across X")
			t.ok(math.abs(info.size.Z - 0.4 * Config.WoodUnit) < 1e-6, "thinner across Y")
			back2 += Sell.VolumeU3(info.size.X, info.size.Y, info.size.Z)
		end
		t.ok(math.abs(back2 - volume) < 1e-3, "re-milling loses no volume")
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

	local function useMill(mill, piece, part, nowFn)
		local notes = {}
		Sawmill._use({
			notify = function(_, text)
				table.insert(notes, text)
			end,
			now = nowFn,
			partsIn = function()
				return if part.Parent then { part } else {}
			end,
			pieceOf = function()
				return piece
			end,
			mills = function()
				return { mill }
			end,
			release = function() end,
			remove = function(p)
				p.dead = true
			end,
			spawn = function()
				return nil
			end,
			moved = function() end,
		})
		return notes
	end

	t.test("a pine base is refused with the blockage board and a toast that names the width", function()
		local mill = MachineArt.Build("SawmillRickety", false)
		mill.Parent = Instance.new("Folder")
		local intake = mill:FindFirstChild("Intake")
		local size = V3.new(2.6, 9, 2.6)
		local model, part = logPart(size, intake.CFrame)
		model.Parent = Instance.new("Folder")
		local piece = {
			model = model,
			root = part,
			kind = "log",
			woodId = "pine",
			parts = { [1] = part },
			nodes = { [1] = { parent = nil, children = {} } },
			volume = Sell.VolumeU3(size.X, size.Y, size.Z),
			ownerId = 7,
			boost = 1,
			verdictOk = true,
			selling = nil,
			dead = nil,
			shopItem = nil,
		}
		toastPlayer = { UserId = 7 }
		local now = 0
		local notes = useMill(mill, piece, part, function()
			return now
		end)
		local sign = mill:FindFirstChild("Blockage", true)
		t.eq(sign.Transparency, 1, "the board starts hidden")
		Sawmill.Tick()
		t.eq(piece.selling, nil, "a pine base is not taken")
		t.eq(sign.Transparency, 0, "BLOCKAGE shows")
		t.eq(sign:FindFirstChildWhichIsA("SurfaceGui").Enabled, true)
		t.eq(sign:FindFirstChildWhichIsA("TextLabel", true).Text, "BLOCKAGE")
		t.eq(notes, { "Too big for this mill (max 1.4 u wide)" })
		now = 5
		Sawmill.Tick()
		t.eq(#notes, 1, "the toast is once")
		part.Parent = nil
		Sawmill.Tick()
		t.eq(sign.Transparency, 1, "the board drops when the log leaves")
		mill:Destroy()
		toastPlayer = nil
		Sawmill._reset()
	end)

	t.test("a teleported log and a flung log are refused", function()
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
			boost = 1,
			verdictOk = false,
			selling = nil,
			dead = nil,
			shopItem = nil,
			lastGood = intake.CFrame,
			lastGoodAt = 0,
		}
		local spawned = 0
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
				p.dead = true
			end,
			spawn = function()
				spawned += 1
				return nil
			end,
			moved = function() end,
		})
		now = Sawmill.Settle + 1
		Sawmill.Tick()
		Sawmill.Tick()
		t.eq(piece.selling, nil, "WoodWatch said no")
		t.eq(spawned, 0)
		piece.verdictOk = true
		piece.lastGood = CFrame.new(0, 0, 400)
		piece.lastGoodAt = now
		now += 1
		Sawmill.Tick()
		now += 2
		Sawmill.Tick()
		t.eq(piece.selling, nil, "it appeared far from where it was last accepted")
		piece.lastGood = part.CFrame
		piece.lastGoodAt = now
		part.AssemblyLinearVelocity = V3.new(0, 0, 200)
		now += 1
		Sawmill.Tick()
		now += 2
		Sawmill.Tick()
		t.eq(piece.selling, nil, "still flying")
		t.eq(spawned, 0)
		part.AssemblyLinearVelocity = V3.zero
		piece.lastGood = part.CFrame
		piece.lastGoodAt = now
		Sawmill.Tick()
		t.eq(piece.selling, nil, "it has to rest after the fling")
		now += 1
		Sawmill.Tick()
		t.eq(piece.selling, true, "once it has actually rested, the mill takes it")
		mill:Destroy()
		Sawmill._reset()
	end)

	t.test("the mill cuts the parts it measured, not a larger recorded volume", function()
		local mill = MachineArt.Build("SawmillRickety", false)
		mill.Parent = Instance.new("Folder")
		local intake = mill:FindFirstChild("Intake")
		local size = V3.new(2, 9, 2)
		local model, part = logPart(size, intake.CFrame)
		model.Parent = Instance.new("Folder")
		local piece = {
			model = model,
			root = part,
			kind = "log",
			woodId = "oak",
			parts = { [1] = part },
			nodes = { [1] = { parent = nil, children = {} } },
			volume = 80,
			ownerId = 7,
			boost = 1,
			verdictOk = true,
			selling = nil,
			dead = nil,
			shopItem = nil,
		}
		toastPlayer = { UserId = 7 }
		local notes = {}
		local now = 0
		Sawmill._use({
			notify = function(_, text)
				table.insert(notes, text)
			end,
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
			remove = function() end,
			spawn = function()
				return nil
			end,
			moved = function() end,
		})
		now = Sawmill.Settle
		Sawmill.Tick()
		now += 1
		Sawmill.Tick()
		t.eq(piece.selling, nil)
		t.eq(notes, { "That piece isn't the size the mill measured." })
		mill:Destroy()
		toastPlayer = nil
		Sawmill._reset()
	end)
end
