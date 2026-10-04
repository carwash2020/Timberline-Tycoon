--!nocheck
-- The server accepts only ChopSawSet(uid, "x", ±1), keeps the wood's owner,
-- and the blade hits a player at most once a second.
return function(t)
	local Vector3 = t.roblox.Vector3
	local Instance = t.roblox.Instance
	local allows = 0
	local loader = t.loader({
		mocks = {
			RateLimiter = {
				Allow = function()
					allows += 1
					return true
				end,
			},
		},
	})
	local Saw = loader:server("ChopSawService")
	local Art = loader:load("ReplicatedStorage/Shared/Art/MachineArt")
	local Logic = loader:shared("ChopSawLogic")
	local Config = loader:shared("GameConfig")
	local fs = require("@lune/fs")

	local function stand(model, userId)
		local hrp = Instance.new("Part")
		hrp.Name = "HumanoidRootPart"
		hrp.CFrame = model:GetPivot()
		local char = Instance.new("Model")
		hrp.Parent = char
		return { UserId = userId, Name = "P" .. tostring(userId), Character = char }
	end

	local function rig()
		allows = 0
		local saw = Art.BuildChopSaw(false)
		saw.Parent = Instance.new("Folder")
		saw:SetAttribute("Uid", "saw-1")
		saw:SetAttribute("OwnerId", 7)
		saw:SetAttribute("CutU", Logic.DefaultCut)
		return saw
	end

	t.test("y is rejected, length clamps, and a stranger without permission is refused", function()
		local saw = rig()
		local owner = stand(saw, 7)
		local stranger = stand(saw, 99)
		local saved = {}
		local now = 0
		Saw._use({
			notify = function() end,
			now = function()
				return now
			end,
			saws = function()
				return { saw }
			end,
			save = function(_player, _uid, cut)
				table.insert(saved, cut)
			end,
		})
		Saw.Set(owner, "saw-1", "y", 1)
		t.eq(allows, 0, "y does not spend the budget")
		t.eq(saw:GetAttribute("CutU"), 8)
		Saw.Set(owner, "saw-1", "x", 2)
		t.eq(allows, 0)
		t.eq(saw:GetAttribute("CutU"), 8)
		Saw.Set(stranger, "saw-1", "x", 1)
		t.eq(allows, 1, "a real press is budgeted")
		t.eq(saw:GetAttribute("CutU"), 8, "a stranger is rejected")
		t.eq(#saved, 0)
		Saw.Set(owner, "saw-1", "x", 1)
		t.eq(saw:GetAttribute("CutU"), 9)
		t.eq(saved[1], 9)
		saw:SetAttribute("CutU", 40)
		now = 5
		Saw.Set(owner, "saw-1", "x", 1)
		t.eq(saw:GetAttribute("CutU"), 32)
		saw:SetAttribute("CutU", 0)
		now = 7
		Saw.Set(owner, "saw-1", "x", -1)
		t.eq(saw:GetAttribute("CutU"), 1)
	end)

	t.test("someone the plot lets interact may step, and one step a second lands", function()
		local saw = rig()
		local friend = stand(saw, 99)
		local now = 10
		Saw._use({
			notify = function() end,
			now = function()
				return now
			end,
			saws = function()
				return { saw }
			end,
			mayUse = function(player, model)
				return Logic.MayUse(player.UserId, model:GetAttribute("OwnerId"), { anyone = { interact = true } })
			end,
		})
		Saw.Set(friend, "saw-1", "x", 1)
		t.eq(saw:GetAttribute("CutU"), 9)
		now = 10.4
		Saw.Set(friend, "saw-1", "x", 1)
		t.eq(saw:GetAttribute("CutU"), 9, "a second press in that second is limited")
		now = 11
		Saw.Set(friend, "saw-1", "x", 1)
		t.eq(saw:GetAttribute("CutU"), 10, "the next second's press lands")
		local src = fs.readFile("src/ServerScriptService/ChopSawService.luau")
		local event = fs.readFile("src/ServerScriptService/EventService.luau")
		local _, here = string.gsub(src, 'RateLimiter.Allow%(player, "ChopSawSet"%)', "")
		local _, there = string.gsub(event, 'RateLimiter.Allow%(player, "ChopSawSet"%)', "")
		t.eq(here, 1)
		t.eq(there, 0)
	end)

	t.test("cut pieces keep the wood's owner and add up, and a bystander is not granted it", function()
		local saw = rig()
		saw:SetAttribute("CutU", 10)
		local u = Config.WoodUnit
		local part = Instance.new("Part")
		part.Size = Vector3.new(2.6, 20 * u, 2.6)
		local beforeY = part.Size.Y
		part.CFrame = saw:GetPivot()
		local model = Instance.new("Model")
		part.Parent = model
		model.PrimaryPart = part
		local piece = {
			model = model,
			root = part,
			kind = "log",
			woodId = "pine",
			parts = { [1] = part },
			nodes = { [1] = { parent = nil, children = {} } },
			ownerId = 7,
		}
		local heights = {}
		local made = {}
		local now = 0
		Saw._use({
			notify = function() end,
			now = function()
				return now
			end,
			saws = function()
				return { saw }
			end,
			partsIn = function()
				return { part }
			end,
			pieceOf = function()
				return piece
			end,
			split = function(current, sid, h)
				table.insert(heights, h)
				local cut = current.parts[sid]
				local remain = cut.Size.Y - h
				cut.Size = Vector3.new(cut.Size.X, h, cut.Size.Z)
				local high = Instance.new("Part")
				high.Size = Vector3.new(cut.Size.X, remain, cut.Size.Z)
				high.CFrame = cut.CFrame
				local otherModel = Instance.new("Model")
				high.Parent = otherModel
				otherModel.PrimaryPart = high
				local other = {
					model = otherModel,
					root = high,
					kind = "chip",
					woodId = current.woodId,
					parts = { [sid + 1] = high },
					nodes = { [sid + 1] = { parent = nil, children = {} } },
					ownerId = 99,
				}
				current.ownerId = 99
				current.kind = "chip"
				table.insert(made, current)
				table.insert(made, other)
				return { current, other }
			end,
		})
		Saw.Tick()
		now = Logic.Settle
		Saw.Tick()
		now = 1000
		Saw.Tick()
		t.eq(#heights, 1)
		t.ok(math.abs(heights[1] - 10 * u) < 1e-4, "cut at 10 u")
		t.eq(#made, 2)
		for _, out in ipairs(made) do
			t.eq(out.ownerId, 7, "the wood's owner, not the bystander")
			t.eq(out.kind, "log")
		end
		t.ok(math.abs(part.Size.Y + made[2].root.Size.Y - beforeY) < 1e-3, "the pieces add up")
	end)

	t.test("a player at 5 HP is left at 1, and two hits inside a second count as one", function()
		local saw = rig()
		local guard = saw:FindFirstChild("BladeGuard", true)
		local root = Instance.new("Part")
		root.CFrame = guard.CFrame
		local health = 5
		local hits = 0
		local now = 0
		local function body()
			return {
				{
					userId = 3,
					health = function()
						return health
					end,
					setHealth = function(n)
						health = n
						hits += 1
					end,
					root = root,
				},
			}
		end
		Saw._use({
			notify = function() end,
			now = function()
				return now
			end,
			saws = function()
				return { saw }
			end,
			bodies = body,
		})
		local before = root.CFrame.Position
		Saw.Tick()
		t.eq(health, 1)
		t.eq(hits, 1)
		t.ok(math.abs((root.CFrame.Position - before).Magnitude - Logic.BladePush) < 1e-3)
		local parked = root.CFrame.Position
		now = 0.5
		Saw.Tick()
		t.eq(health, 1)
		t.eq(hits, 1, "the second hit inside the second does not land")
		t.eq(root.CFrame.Position, parked)

		health = 100
		hits = 0
		now = 20
		Saw.Tick()
		t.eq(health, 90)
		t.eq(hits, 1)
		now = 20.5
		Saw.Tick()
		t.eq(health, 90, "two hits within 1 s count as one")
		t.eq(hits, 1)
		now = 21
		Saw.Tick()
		t.eq(health, 80)
		t.eq(hits, 2)

		saw:SetAttribute("Run", false)
		health = 50
		now = 30
		Saw.Tick()
		t.eq(health, 50, "a stopped saw does not hit")
	end)

	t.test("phantomwood is refused with a message and is not cut", function()
		local saw = rig()
		local part = Instance.new("Part")
		part.Size = Vector3.new(2, 8, 2)
		local model = Instance.new("Model")
		part.Parent = model
		local piece = {
			model = model,
			root = part,
			kind = "log",
			woodId = "phantomwood",
			parts = { [1] = part },
			nodes = { [1] = { parent = nil, children = {} } },
			ownerId = 7,
		}
		local notes = {}
		local splits = 0
		local owner = { UserId = 7 }
		Saw._use({
			notify = function(_who, text)
				table.insert(notes, text)
			end,
			now = function()
				return 0
			end,
			saws = function()
				return { saw }
			end,
			partsIn = function()
				return { part }
			end,
			pieceOf = function()
				return piece
			end,
			byUserId = function(id)
				return if id == 7 then owner else nil
			end,
			split = function()
				splits += 1
				return { piece }
			end,
		})
		Saw.Tick()
		Saw.Tick()
		t.eq(splits, 0)
		t.eq(#notes, 1)
		t.ok(string.find(notes[1], "Gloamwood", 1, true))
	end)
end
