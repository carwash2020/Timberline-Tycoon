--!nocheck
-- Plots on the server: claiming, placing, moving, selling back, growing,
-- and rebuilding a saved layout on whichever slot you get.
return function(t)
	local Vector2, Vector3 = t.roblox.Vector2, t.roblox.Vector3
	local spendDuring: (() -> ())? = nil
	local explode = false

	-- Just enough of Roblox's Instance for PlotService: properties, children,
	-- attributes, and events that record their handler.
	local function fakeInstances()
		local Instance = {}
		local methods = {}
		function methods:SetAttribute(key, value)
			self._attrs[key] = value
		end
		function methods:GetAttribute(key)
			return self._attrs[key]
		end
		function methods:GetChildren()
			return table.clone(self._children)
		end
		function methods:FindFirstChild(name)
			for _, child in ipairs(self._children) do
				if child.Name == name then
					return child
				end
			end
			return nil
		end
		function methods:ClearAllChildren()
			for _, child in ipairs(self:GetChildren()) do
				child.Parent = nil
			end
		end
		function methods:Destroy()
			self.Parent = nil
			self.destroyed = true
		end
		function methods:IsA(class)
			return class == self.ClassName or (class == "BasePart" and self.ClassName == "Part")
		end
		function methods:PivotTo(cframe)
			self.pivot = cframe
		end
		function Instance.new(className)
			local props = { ClassName = className, Name = className, _children = {}, _attrs = {} }
			local inst = {}
			return setmetatable(inst, {
				__index = function(_, key)
					if props[key] ~= nil then
						return props[key]
					end
					if key == "Triggered" or key == "OnServerEvent" then
						local signal = {}
						function signal:Connect(fn)
							self.fn = fn
						end
						props[key] = signal
						return signal
					end
					return methods[key]
				end,
				__newindex = function(_, key, value)
					if key == "Parent" then
						local old = props.Parent
						if old then
							local list = old._children
							table.remove(list, table.find(list, inst))
						end
						if value then
							table.insert(value._children, inst)
						end
					end
					props[key] = value
				end,
			})
		end
		return Instance
	end

	local function setup(options)
		options = options or {}
		local Instance = fakeInstances()
		local clock = 0
		local toasts, tags, questEvents = {}, {}, {}
		local base = t.loader()
		local Schema = base:server("ProfileSchema")
		local Util = base:shared("Util")
		local PlotData = base:shared("PlotData")

		local players, profiles = {}, {}
		local function newPlayer(userId, name)
			local profile = Util.deepCopy(Schema.Template)
			profile.cash = options.cash or 100000
			local root = { Position = Vector3.new(0, 3, 0) }
			local player = {
				UserId = userId,
				Name = name,
				DisplayName = name,
				attrs = {},
				Character = {
					FindFirstChild = function(_, child)
						return if child == "HumanoidRootPart" then root else nil
					end,
				},
				SetAttribute = function(self, key, value)
					self.attrs[key] = value
				end,
			}
			profiles[player] = profile
			table.insert(players, player)
			-- Stand on plot `i` (or far away when nil).
			function player.standOn(i)
				local c = if i then PlotData.Slots[i] else Vector2.new(-2000, -2000)
				root.Position = Vector3.new(c.X, 3, c.Y)
			end
			player.root = root
			-- At the unclaimed sign. The board's height follows the shelf,
			-- so the spot is the sign itself, not a guess from y = 3.
			function player.standAtSign(i)
				root.Position = Vector3.new(PlotData.Slots[i].X, 3, PlotData.Slots[i].Y)
			end
			return player, profile
		end

		local loader = t.loader({
			globals = {
				Instance = Instance,
				task = {
					spawn = options.spawn or function(fn)
						fn()
					end,
				},
				os = {
					clock = function()
						return clock
					end,
					time = os.time,
				},
			},
			services = {
				Players = {
					GetPlayers = function()
						return players
					end,
				},
				CollectionService = {
					AddTag = function(_, inst, tag)
						tags[inst] = tag
					end,
				},
			},
			mocks = {
				ProfileService = {
					GetProfile = function(player)
						return profiles[player]
					end,
				},
				RateLimiter = {
					Allow = function()
						return options.rate ~= false
					end,
				},
				QuestService = {
					Event = function(_player, event)
						table.insert(questEvents, event)
					end,
				},
				EconomyService = {
					GetCash = function(player)
						return profiles[player].cash
					end,
					SpendCash = function(player, amount)
						local profile = profiles[player]
						if profile.cash < amount then
							return false
						end
						profile.cash -= amount
						if spendDuring then
							spendDuring()
						end
						return true
					end,
					Refund = function(player, amount)
						profiles[player].cash += amount
						return amount, 0
					end,
				},
				BlueprintModels = {
					Build = function(bp)
						if explode then
							error("the plot would not build")
						end
						local model = Instance.new("Model")
						model.Name = bp.id
						return model
					end,
					Place = function(model, plotCFrame, x, z, rot)
						model.placedAt = { x, z, rot }
						-- World pose: the pad's origin, then the plot-local offset.
						local world = plotCFrame * t.roblox.CFrame.new(x, 0, z)
						model.placedWorld = world.Position
					end,
				},
				MachineArt = {
					Build = function(id)
						local model = Instance.new("Model")
						model.Name = id
						local root = Instance.new("Part")
						root.Name = "Root"
						root.Parent = model
						model.PrimaryPart = root
						return model
					end,
					BuildChopSaw = function()
						local model = Instance.new("Model")
						model.Name = "ChopSaw"
						return model
					end,
					BuildSkyBin = function()
						local model = Instance.new("Model")
						model.Name = "SkyBin"
						return model
					end,
					BuildPlaner = function(id)
						local model = Instance.new("Model")
						model.Name = id
						return model
					end,
					BuildBelt = function(id)
						local model = Instance.new("Model")
						model.Name = id
						return model
					end,
					SetCut = function(model, x, y)
						model:SetAttribute("CutShown", string.format("%.1f %.1f", x, y))
					end,
					SetLength = function(model, cut)
						model:SetAttribute("LengthShown", cut)
					end,
				},
				WoodService = options.wood,
				-- Lane F: the loose wood a base keeps when it is unloaded. The
				-- default finds nothing; the loose-wood tests pass their own.
				LooseService = options.loose or {
					Scan = function()
						return { pieces = 0, sections = 0, unsaveable = 0 }
					end,
					Collect = function()
						return true
					end,
					Restore = function()
						return 0, 0
					end,
					RestoreStranded = function()
						return 0, 0
					end,
				},
				PlotFill = options.plotFill,
				BuildMaterials = options.materials,
				ItemMeshes = options.itemMeshes,
			},
		})
		local PlotService = loader:server("PlotService")
		local map = Instance.new("Folder")
		local remotes = {}
		for _, name in ipairs({
			"PlaceBlueprint",
			"MoveBlueprint",
			"SellPlaced",
			"UpgradePlot",
			"VisitPlot",
			"WorldFX",
			"PlotShown",
			"BaseAction",
		}) do
			remotes[name] = Instance.new("RemoteEvent")
		end
		-- The hammer's knock, as told to each nearby player.
		local fx = {}
		remotes.WorldFX.FireClient = function(_, target, kind, payload)
			table.insert(fx, { to = target, kind = kind, payload = payload })
		end
		PlotService.Init(map, remotes, function(_, message)
			table.insert(toasts, message)
		end, if options.gates then { gates = options.gates } else nil)
		local plots = map:FindFirstChild("Plots")

		local function plot(i)
			return plots:FindFirstChild("Plot_" .. i)
		end
		local office = map:FindFirstChild("LandOffice")
		local counter = office:FindFirstChild("Counter")
		local prompt = counter:FindFirstChild("LandOfficePrompt")
		local function atOffice(player)
			player.root.Position = counter.CFrame.Position
		end
		-- Buys plot i the real way (stand at the Land Office, ClaimPlot). The
		-- price is topped up first, so a test's cash arithmetic is its own;
		-- the charge itself is tested where cash is the point.
		local function claim(player, i)
			local profile = profiles[player]
			if profile.plot.claimed ~= true then
				profile.cash += loader:shared("GameConfig").PlotPrice
			end
			atOffice(player)
			PlotService.Claim(player, i)
		end
		-- Placed models live beside the plot shell (PlotItems_N), not inside it.
		local function itemFolder(i)
			return plots:FindFirstChild("PlotItems_" .. i)
		end
		local function items(i)
			return itemFolder(i):GetChildren()
		end
		return {
			P = PlotService,
			config = loader:shared("GameConfig"),
			PlotData = PlotData,
			newPlayer = newPlayer,
			plot = plot,
			claim = claim,
			atOffice = atOffice,
			spendDuring = function(fn)
				spendDuring = fn
			end,
			explodeOnBuild = function(on)
				explode = on
			end,
			prompt = prompt,
			counter = counter,
			profiles = profiles,
			items = items,
			itemFolder = itemFolder,
			toasts = toasts,
			fx = fx,
			questEvents = questEvents,
			tags = tags,
			remotes = remotes,
			lastToast = function()
				return toasts[#toasts]
			end,
			advance = function(seconds)
				clock += seconds
			end,
		}
	end

	-- LOAD-02: the plot kit's meshes load in the background. Studio's log of
	-- 7 October 2026 had PlotService.Init take 10.7 s, one mesh load after
	-- another. Init never waits on an asset fetch: it gives the meshes a short
	-- bounded wait, builds the pads part-built if they are late and dresses
	-- them when the meshes land.
	t.test("the plot kit's meshes in time: the pads are drawn once, with the meshes, and the gate opens", function()
		local ReadyGates = t.shared("ReadyGates")
		local gates = ReadyGates.new()
		local attached = 0
		setup({
			gates = gates,
			itemMeshes = {
				LoadAsync = function() end,
				AttachTo = function()
					attached += 1
					return false
				end,
				Attach = function()
					return 0
				end,
				Template = function()
					return nil
				end,
			},
		})
		t.eq(gates.IsReady("itemMeshes"), true, "the gate is open once the meshes are loaded")
		local perPad = attached / #t.shared("PlotData").Slots
		t.eq(perPad, 9, "one sign, four rails and four corners: drawn once per pad")
	end)

	t.test(
		"the plot kit's meshes late: Init does not wait for them, then the pads are dressed when they land",
		function()
			local ReadyGates = t.shared("ReadyGates")
			local now = 0
			local gates = ReadyGates.new({
				clock = function()
					now += 1 -- every look at the clock is a second: the 3 s wait runs out at once
					return now
				end,
				wait = function() end,
			})
			local threads = {}
			local attached = 0
			local env = setup({
				gates = gates,
				spawn = function(fn)
					local co = coroutine.create(fn)
					table.insert(threads, co)
					assert(coroutine.resume(co))
				end,
				itemMeshes = {
					LoadAsync = function()
						coroutine.yield() -- the mesh fetch: nothing lands until the test says so
					end,
					AttachTo = function()
						attached += 1
						return false
					end,
					Attach = function()
						return 0
					end,
					Template = function()
						return nil
					end,
				},
			})
			t.eq(gates.IsReady("itemMeshes"), false, "Init returned with the meshes still loading")
			local drawnBefore = attached
			t.ok(drawnBefore > 0, "the pads were built (part-built) without waiting")
			t.ok(env.plot(1), "plot 1 is there")
			-- The meshes land.
			assert(coroutine.resume(threads[1]))
			t.eq(gates.IsReady("itemMeshes"), true)
			t.eq(attached, drawnBefore * 2, "every pad was drawn again, now with the meshes")
		end
	)

	t.test("the district has an open plot per slot, each with a sign, and one Land Office that sells them", function()
		local s = setup()
		t.ok(s.prompt ~= nil, "the Land Office has its prompt")
		t.eq(s.prompt.ActionText, "Buy a plot")
		for i = 1, #s.PlotData.Slots do
			local sign = s.plot(i):FindFirstChild("Sign")
			t.eq(sign:FindFirstChild("ProximityPrompt"), nil, "no plot is claimable at its own sign: nothing is free")
			t.eq(s.plot(i):GetAttribute("OwnerId"), nil)
			for _, gui in ipairs(sign:GetChildren()) do
				if gui.ClassName == "SurfaceGui" then -- sized to the board, so its text isn't stretched
					t.eq(gui.SizingMode, t.roblox.Enum.SurfaceGuiSizingMode.PixelsPerStud)
				end
			end
		end
		t.ok(s.remotes.PlaceBlueprint.OnServerEvent.fn ~= nil)
		t.ok(s.remotes.MoveBlueprint.OnServerEvent.fn ~= nil)
		t.ok(s.remotes.SellPlaced.OnServerEvent.fn ~= nil)
		t.ok(s.remotes.UpgradePlot.OnServerEvent.fn ~= nil)
	end)

	t.test("claiming a plot makes it yours, once", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 3)
		t.ok(profile.plot.claimed)
		t.eq(s.questEvents, { "plotClaimed" })
		t.eq(ann.attrs.PlotSlot, 3)
		t.eq(ann.attrs.PlotTier, 1)
		t.eq(s.plot(3):GetAttribute("OwnerId"), 1)
		s.claim(ann, 4)
		t.eq(s.lastToast(), "You already have a plot here.")
		t.eq(s.plot(4):GetAttribute("OwnerId"), nil)
		local bob = s.newPlayer(2, "Bob")
		s.claim(bob, 3) -- taken: nothing happens
		t.eq(s.plot(3):GetAttribute("OwnerId"), 1)
	end)

	t.test("placing: on your plot, snapped, paid for, saved and built", function()
		local s = setup({ cash = 1000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(nil)
		s.P.Place(ann, "Bench", 10.6, -3.4, 1)
		t.eq(s.lastToast(), "Stand on your plot to build.")
		t.eq(#profile.plot.placed, 0)

		ann.standOn(1)
		s.P.Place(ann, "Bench", 10.6, -3.4, 1)
		t.eq(profile.cash, 1000 - 80)
		t.eq(#profile.plot.placed, 1)
		local item = profile.plot.placed[1]
		t.eq({ item.blueprintId, item.x, item.z, item.rot }, { "Bench", 10, -4, 1 })
		local models = s.items(1)
		t.eq(#models, 1)
		t.eq(models[1].Name, item.uid)
		t.eq(models[1]:GetAttribute("OwnerId"), 1)
		t.eq(models[1]:GetAttribute("X"), 10)
		t.eq(s.tags[models[1]], "PlacedItem")
	end)

	t.test("placing is refused (and free) when it doesn't fit", function()
		local s = setup({ cash = 1000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Place(ann, "Bench", 0, 0, 0)
		s.P.Place(ann, "Bench", 1, 0, 0)
		t.eq(s.lastToast(), "Something's in the way.")
		s.P.Place(ann, "Fence", 80, 0, 0)
		t.eq(s.lastToast(), "Outside your plot.")
		s.P.Place(ann, "Warehouse", 20, 20, 0)
		t.eq(s.lastToast(), "Needs a Homestead plot.")
		s.P.Place(ann, "Cabin", 30, 30, 0)
		t.eq(s.lastToast(), "You need $1,080 more for the Cabin.")
		for _, junk in ipairs({
			{ "Nope", 0, 0, 0 },
			{ "Flag", "x", 0, 0 },
			{ "Flag", 0 / 0, 0, 0 },
			{ "Flag", 0, 0, 7 },
		}) do
			s.P.Place(ann, table.unpack(junk))
		end
		t.eq(#profile.plot.placed, 1)
		t.eq(profile.cash, 1000 - 80)
	end)

	t.test("moving is free and checked like placing", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		profile.furnitureBlueprints = { Fence = true }
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Place(ann, "Fence", 0, 0, 0)
		s.P.Place(ann, "Fence", 0, 10, 0)
		local cash = profile.cash
		local first = profile.plot.placed[1]
		s.P.Move(ann, first.uid, 0, 10, 0)
		t.eq(s.lastToast(), "Something's in the way.")
		s.P.Move(ann, first.uid, 20.9, -5, 1)
		t.eq({ first.x, first.z, first.rot }, { 20, -4, 1 })
		t.eq(profile.cash, cash)
		local model = s.itemFolder(1):FindFirstChild(first.uid)
		t.eq(model.placedAt, { 20, -4, 1 })
		t.eq(model:GetAttribute("Rot"), 1)
		s.P.Move(ann, "someone-else", 0, 0, 0) -- not yours: nothing happens
		t.eq(#profile.plot.placed, 2)
	end)

	t.test("selling back: all of it within a minute, half after", function()
		local s = setup({ cash = 5000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Place(ann, "Cabin", 0, 0, 0)
		s.P.Place(ann, "Cabin", 0, 20, 0)
		t.eq(profile.cash, 1000)
		s.P.Sell(ann, profile.plot.placed[1].uid)
		t.eq(profile.cash, 3000)
		t.eq(s.lastToast(), "Took back the Cabin: $2,000 refunded.")
		s.advance(s.P.UndoSeconds + 1)
		s.P.Sell(ann, profile.plot.placed[1].uid)
		t.eq(profile.cash, 4000)
		t.eq(s.lastToast(), "Sold the Cabin for $1,000.")
		t.eq(#profile.plot.placed, 0)
		t.eq(#s.items(1), 0)
	end)

	t.test("selling won't overflow a full wallet", function()
		local s = setup({ cash = 2000000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Place(ann, "Flag", 0, 0, 0)
		profile.cash = 2000000
		s.P.Sell(ann, profile.plot.placed[1].uid)
		t.eq(#profile.plot.placed, 1)
		t.eq(s.lastToast(), "Your wallet is too full to sell that. Spend some first.")
	end)

	t.test("growing the plot through its tiers", function()
		local s = setup({ cash = 3000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Upgrade(ann)
		t.eq(profile.plot.tier, 2)
		t.eq(profile.cash, 500)
		t.eq(ann.attrs.PlotTier, 2)
		t.eq(s.plot(1):GetAttribute("Tier"), 2)
		t.eq(s.plot(1):FindFirstChild("Pad").Size.X, 110)
		s.P.Upgrade(ann)
		t.eq(profile.plot.tier, 2)
		t.eq(s.lastToast(), "You need $9,500 more for a Lumber Yard.")
		profile.plot.tier = #s.PlotData.Tiers
		s.P.Upgrade(ann)
		t.eq(s.lastToast(), "Your plot size is already the biggest.")
	end)

	t.test(
		"the build platform: a collidable slab 1 stud over the grass that grows with the tier and squares",
		function()
			local PlotPlatform = t.shared("PlotPlatform")
			local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
			local s = setup({ cash = 20000 })
			local center = s.PlotData.Slots[1]
			local ground = TerrainGen.HeightAt(center.X, center.Y)
			local function count(folder, name)
				local n = 0
				for _, child in ipairs(folder:GetChildren()) do
					if child.Name == name then
						n += 1
					end
				end
				return n
			end
			-- An open plot already shows its platform: the Campsite's 80 studs, opaque.
			local plot = s.plot(1)
			local pad = plot:FindFirstChild("Pad")
			t.eq(pad.Size.X, 80)
			t.eq(pad.Size.Y, s.PlotData.PlatformThick)
			t.eq(pad.CanCollide, true, "you stand on it")
			t.ok(pad.Transparency == nil or pad.Transparency == 0, "a solid slab, never a faint paint")
			t.ok(
				math.abs(pad.CFrame.Position.Y + pad.Size.Y / 2 - (ground + 1)) < 1e-6,
				"its top is 1 stud over the grass"
			)
			t.eq(plot.PrimaryPart, pad)
			local folder = plot:FindFirstChild("Platform")
			t.eq(count(folder, "Ramp"), 4)
			t.eq(count(folder, "Land"), 0)
			for _, ramp in ipairs(folder:GetChildren()) do
				t.eq(ramp.ClassName, "WedgePart")
				t.eq(ramp.CanCollide, true)
			end
			-- Plot-local y = 0 is the platform's top: a saved piece at (0, 0) stands on it.
			local ann, profile = s.newPlayer(1, "Ann")
			s.claim(ann, 1)
			ann.standOn(1)
			s.P.Place(ann, "Flag", 0, 0, 0)
			t.ok(
				math.abs(s.items(1)[1].placedWorld.Y - (ground + 1)) < 1e-6,
				"a piece at plot-local y 0 is on the platform top"
			)
			-- A bought square past the tier is a Land slab and its own ramps.
			s.P.Expand(ann, 1, 0, 0) -- square "1,0": x 20..60, 20 studs of it past the Campsite's edge at 40
			local squares = profile.plot.squares
			t.eq(squares, { "1,0" })
			local layout = PlotPlatform.Layout(80, squares)
			t.eq(#layout.land, 1)
			t.eq(count(folder, "Land"), 1)
			t.eq(count(folder, "Ramp"), #layout.ramps)
			-- The tier grows the slab; the square's slab shrinks to what the tier leaves.
			profile.cash = 20000
			s.P.Upgrade(ann)
			t.eq(plot:FindFirstChild("Pad").Size.X, 110)
			t.ok(math.abs(pad.CFrame.Position.Y + pad.Size.Y / 2 - (ground + 1)) < 1e-6, "still 1 stud up")
			layout = PlotPlatform.Layout(110, squares)
			t.eq(count(folder, "Land"), #layout.land)
			t.eq(count(folder, "Ramp"), #layout.ramps)
			-- The sign stands on the grass past the ramps, nothing flat shares a plane with the platform.
			local top = ground + 1
			for _, marker in ipairs(plot:FindFirstChild("Border"):GetChildren()) do
				t.ok(marker.Name ~= "Square" and marker.Name ~= "Apron", "no old paint pads: the platform is the yard")
				local bottom = marker.CFrame.Position.Y - marker.Size.Y / 2
				t.ok(
					math.abs(bottom - top) >= s.PlotData.PlatformEdgeClear,
					marker.Name .. " is not coplanar with the top"
				)
			end
			local sign = plot:FindFirstChild("Sign")
			t.ok(
				sign.CFrame.Position.Z - center.Y >= layout.extent / 2 + s.PlotData.PlatformRamp,
				"the sign is past the ramps"
			)
		end
	)

	t.test("your layout comes back on whichever plot is free when you rejoin", function()
		local s = setup()
		local bob = s.newPlayer(2, "Bob")
		s.claim(bob, 1)
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.claimed = true
		profile.plot.placed = {
			{ uid = "a", blueprintId = "Bench", x = 4, z = 4, rot = 0 },
			{ uid = "b", blueprintId = "Retired", x = 0, z = 0, rot = 0 }, -- a blueprint that no longer exists
		}
		s.P.PlayerJoined(ann, profile)
		t.eq(ann.attrs.PlotSlot, nil, "joining opens the picker, it doesn't assign")
		s.P.Pass(ann)
		t.eq(ann.attrs.PlotSlot, 2)
		t.eq(#s.items(2), 1)
		t.eq(s.items(2)[1].Name, "a")
		-- P6: the bench is the pad 2 origin plus the saved (4, 4), plot-local.
		local slot = s.PlotData.Slots[2]
		local bench = s.items(2)[1]
		t.eq(bench.placedAt, { 4, 4, 0 })
		t.eq(bench.placedWorld.X, slot.X + 4)
		t.eq(bench.placedWorld.Z, slot.Y + 4)
		s.P.PlayerRemoving(ann)
		t.eq(#s.items(2), 0)
		t.eq(s.plot(2):GetAttribute("OwnerId"), nil)
		t.eq(#profile.plot.placed, 2, "leaving keeps the save")

		local cara, fresh = s.newPlayer(3, "Cara")
		s.P.PlayerJoined(cara, fresh) -- never bought: no plot, and no picker either
		t.eq(cara.attrs.PlotSlot, nil)
		t.eq(cara.attrs.Picking, nil)
	end)

	t.test("a sawmill from stock places free; one you don't own is a box at the Tool Shed", function()
		local s = setup({ cash = 200 })
		local ann, profile = s.newPlayer(1, "Ann")
		profile.sawmillStock = { "SawmillRickety" }
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Place(ann, "SawmillRickety", 0, 0, 0)
		t.eq(profile.cash, 200)
		t.eq(profile.sawmillStock, {})
		t.eq(ann.attrs.SawmillStock, "")
		t.eq(profile.plot.placed[1].data, { x = 1, y = 0.6 })
		t.eq(s.items(1)[1]:GetAttribute("CutX"), 1)
		t.eq(s.tags[s.items(1)[1]], "PlacedItem")
		-- The palette is not a shop: with none in stock, nothing is charged
		-- or placed, and the toast says where the box is.
		s.P.Place(ann, "SawmillRickety", 0, 20, 0)
		t.eq(profile.cash, 200)
		t.eq(#profile.plot.placed, 1)
		t.eq(s.lastToast(), "Buy the Rickety Sawmill at the Tool Shed first.")
	end)

	t.test("the chop saw is the same: stock places it free, none in stock is refused", function()
		local s = setup({ cash = 20000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Place(ann, "ChopSaw", 0, 0, 0)
		t.eq(profile.cash, 20000, "no charge at the palette")
		t.eq(#profile.plot.placed, 0)
		t.eq(s.lastToast(), "Buy the Chop Saw at the Tool Shed first.")
		profile.sawmillStock = { "ChopSaw" }
		s.P.Place(ann, "ChopSaw", 0, 0, 0)
		t.eq(profile.cash, 20000)
		t.eq(#profile.plot.placed, 1)
		t.eq(profile.sawmillStock, {})
		t.eq(ann.attrs.SawmillStock, "")
	end)

	t.test("the Sky Bin: bought boxed, placed from stock on your plot, one per plot", function()
		local s = setup({ cash = 1000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Place(ann, "SkyBin", 0, 0, 0)
		t.eq(#profile.plot.placed, 0, "none in stock: refused")
		t.eq(s.lastToast(), "Buy the Sky Bin at the Tool Shed first.")
		profile.sawmillStock = { "SkyBin" }
		s.P.Place(ann, "SkyBin", 0, 0, 0)
		t.eq(#profile.plot.placed, 1)
		t.eq(profile.cash, 1000, "bought at the counter, free to place")
		t.eq(profile.sawmillStock, {})
		t.eq(profile.plot.placed[1].blueprintId, "SkyBin")
		-- A second one (a gift, a bug, a hacked client) has no room.
		profile.sawmillStock = { "SkyBin" }
		s.P.Place(ann, "SkyBin", 20, 0, 0)
		t.eq(#profile.plot.placed, 1, "one per plot")
		t.eq(s.lastToast(), "You already have a Sky Bin on your plot. There's only room for one.")
		t.eq(profile.sawmillStock, { "SkyBin" }, "and the box is not spent")
	end)

	t.test("the Sky Bin is the owner's: a visitor with build rights can't put theirs on your plot", function()
		local s = setup({ cash = 1000 })
		local ann, profile = s.newPlayer(1, "Ann")
		local bob, bobProfile = s.newPlayer(2, "Bob")
		s.claim(ann, 1)
		ann.standOn(1)
		profile.permissions = { anyone = { build = true } }
		bobProfile.sawmillStock = { "SkyBin" }
		bob.standOn(1)
		s.P.Place(bob, "SkyBin", 0, 0, 0)
		t.eq(#profile.plot.placed, 0)
		t.eq(s.lastToast(), "Only the plot's owner can put a Sky Bin down.")
		t.eq(bobProfile.sawmillStock, { "SkyBin" }, "Bob keeps his box")
	end)

	t.test("the Sky Bin sells back for half like a mill; no stock, no re-boxing, no free copy later", function()
		local s = setup({ cash = 1000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		profile.sawmillStock = { "SkyBin" }
		s.P.Place(ann, "SkyBin", 0, 0, 0)
		t.eq(profile.skyBinOwned, true)
		local uid = profile.plot.placed[1].uid
		s.P.SkyBinPayout = function()
			return true -- empty bin
		end
		s.advance(120) -- past the one-minute undo window
		s.P.Sell(ann, uid)
		t.eq(#profile.plot.placed, 0)
		t.eq(profile.sawmillStock, {}, "not back in stock")
		t.eq(profile.cash, 1200, "half of $400")
		t.eq(profile.skyBinOwned, false, "gone for good: the next load will not hand one over")
		t.eq(#s.items(1), 0)
	end)

	t.test("selling a Sky Bin with wood in it pays the wood out first, then removes the bin", function()
		local s = setup({ cash = 1000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		profile.sawmillStock = { "SkyBin" }
		profile.skyWood = { { w = "oak", v = 10 } }
		s.P.Place(ann, "SkyBin", 0, 0, 0)
		local uid = profile.plot.placed[1].uid
		s.advance(120)
		local order = {}
		s.P.SkyBinPayout = function(owner, extra)
			table.insert(order, "payout")
			t.eq(owner, ann)
			t.eq(extra, 200, "the wallet must also have room for the sell-back")
			t.eq(#profile.plot.placed, 1, "the bin is still there while the wood is paid")
			profile.skyWood = {}
			profile.cash += 77
			return true
		end
		s.P.Sell(ann, uid)
		t.eq(order, { "payout" })
		t.eq(#profile.plot.placed, 0)
		t.eq(profile.skyWood, {})
		t.eq(profile.cash, 1000 + 77 + 200)
	end)

	t.test("if the wood can't be paid out the Sky Bin stays and nothing is lost", function()
		local s = setup({ cash = 1000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		profile.sawmillStock = { "SkyBin" }
		profile.skyWood = { { w = "oak", v = 10 } }
		s.P.Place(ann, "SkyBin", 0, 0, 0)
		local uid = profile.plot.placed[1].uid
		s.advance(120)
		s.P.SkyBinPayout = function()
			return false
		end
		s.P.Sell(ann, uid)
		t.eq(#profile.plot.placed, 1, "still placed")
		t.eq(profile.skyWood, { { w = "oak", v = 10 } }, "the wood is untouched")
		t.eq(profile.cash, 1000)
		t.eq(profile.skyBinOwned, true)
		t.eq(s.lastToast(), t.shared("SkyBinLogic").WoodStaysLine)
	end)

	t.test("only the owner sells the Sky Bin, even a visitor with destroy rights", function()
		local s = setup({ cash = 1000 })
		local ann, profile = s.newPlayer(1, "Ann")
		local bob = s.newPlayer(2, "Bob")
		s.claim(ann, 1)
		ann.standOn(1)
		profile.sawmillStock = { "SkyBin" }
		s.P.Place(ann, "SkyBin", 0, 0, 0)
		profile.permissions = { anyone = { build = true, destroy = true } }
		bob.standOn(1)
		s.P.SkyBinPayout = function()
			error("must not be asked")
		end
		s.P.Sell(bob, profile.plot.placed[1].uid)
		t.eq(#profile.plot.placed, 1)
		t.eq(s.lastToast(), t.shared("SkyBinLogic").OnlyOwnerSellLine)
	end)

	t.test("hammer build: a store unlock is placed only once its blueprint has been used", function()
		local s = setup({ cash = 1000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Place(ann, "Shed", 0, 0, 0)
		t.eq(s.lastToast(), "Buy the Small Shed at the General Store first.")
		t.eq(#profile.plot.placed, 0)
		t.eq(profile.cash, 1000)
		-- Using the physical blueprint adds it to the book (BlueprintService).
		table.insert(profile.blueprintBook, "Shed")
		s.P.Place(ann, "Shed", 0, 0, 0)
		t.eq(#profile.plot.placed, 1)
		t.eq(profile.cash, 1000, "an unlock you own places free, as before")
		-- And every copy after that is free too.
		s.P.Place(ann, "Shed", 0, 20, 0)
		t.eq(#profile.plot.placed, 2)
	end)

	t.test("hammer build: a plan that is not in your book is refused, with the reason, and costs nothing", function()
		local s = setup({ cash = 1000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		profile.blueprintBook = {}
		s.P.Place(ann, "Bench", 0, 0, 0)
		t.eq(s.lastToast(), "You haven't learned the Bench yet. Use its blueprint with your hammer.")
		t.eq(#profile.plot.placed, 0)
		t.eq(profile.cash, 1000)
		table.insert(profile.blueprintBook, "Bench")
		s.P.Place(ann, "Bench", 0, 0, 0)
		t.eq(#profile.plot.placed, 1)
		t.eq(profile.cash, 1000 - 80, "the price is what it was")
	end)

	t.test("hammer build: a save that has not migrated yet still places what it bought (the legacy set)", function()
		local s = setup({ cash = 1000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		profile.blueprintBook = {}
		profile.furnitureBlueprints = { Shed = true }
		s.P.Place(ann, "Shed", 0, 0, 0)
		t.eq(#profile.plot.placed, 1)
	end)

	t.test("hammer build: a kit piece still charges its fee and starts as an empty ghost", function()
		local s = setup({ cash = 1000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Place(ann, "Wall", 0, 0, 0)
		t.eq(profile.cash, 1000 - 32)
		local item = profile.plot.placed[1]
		t.eq(item.paid, 32)
		t.eq(item.fill, { units = 0 })
	end)

	t.test("hammer build: a placed piece is told to nearby players as a knock, not to the placer", function()
		local s = setup({ cash = 1000 })
		local ann, _ = s.newPlayer(1, "Ann")
		local bob = s.newPlayer(2, "Bob")
		local far = s.newPlayer(3, "Far")
		s.claim(ann, 1)
		ann.standOn(1)
		bob.standOn(1)
		far.standOn(nil)
		s.P.Place(ann, "Bench", 10, 0, 0)
		t.eq(#s.fx, 1, "one knock, to Bob")
		t.eq(s.fx[1].to, bob)
		t.eq(s.fx[1].kind, "Hammer")
		t.eq(s.fx[1].payload.by, 1)
		t.ok(s.fx[1].payload.pos ~= nil)
		-- A refused place makes no sound.
		s.P.Place(ann, "Bench", 10, 0, 0)
		t.eq(#s.fx, 1)
		-- Moving it knocks again.
		local uid = s.profiles[ann].plot.placed[1].uid
		s.P.Move(ann, uid, 20, 0, 1)
		t.eq(#s.fx, 2)
	end)

	t.test(
		"hammer build: turning a piece in place is a move with the next rot, and a filled kit piece will not turn",
		function()
			local s = setup({ cash = 1000 })
			local ann, profile = s.newPlayer(1, "Ann")
			s.claim(ann, 1)
			ann.standOn(1)
			s.P.Place(ann, "Bench", 10, 0, 0)
			local bench = profile.plot.placed[1]
			s.P.Move(ann, bench.uid, bench.x, bench.z, 1)
			t.eq(bench.rot, 1)
			s.P.Place(ann, "Wall", 0, 20, 0)
			local wall = profile.plot.placed[2]
			wall.fill = { units = 3 }
			s.P.Move(ann, wall.uid, wall.x, wall.z, 1)
			t.eq(wall.rot, 0, "wood is in it: it stays put")
			t.eq(s.lastToast(), "This piece already has wood in it.")
		end
	)

	t.test("with boxed stores off, the old pay-as-you-place comes back (the rollback)", function()
		local s = setup({ cash = 200 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		s.config.BoxedStores = false
		s.P.Place(ann, "SawmillRickety", 0, 20, 0)
		s.config.BoxedStores = nil
		t.eq(profile.cash, 70)
		t.eq(#profile.plot.placed, 1)
	end)

	t.test("a saved cut comes back on the mill", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.claimed = true
		profile.plot.placed = {
			{ uid = "mill", blueprintId = "SawmillRickety", x = 0, z = 0, rot = 0, data = { x = 1.4, y = 0.8 } },
		}
		s.P.PlayerJoined(ann, profile)
		s.P.Pass(ann)
		local model = s.items(1)[1]
		t.eq(model:GetAttribute("CutX"), 1.4)
		t.eq(model:GetAttribute("CutY"), 0.8)
		t.eq(model:GetAttribute("CutShown"), "1.4 0.8")
		t.eq(profile.plot.placed[1].data, { x = 1.4, y = 0.8 })
	end)

	t.test("a saved chop saw length comes back, and the mill beside it keeps its cut", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.claimed = true
		profile.plot.placed = {
			{ uid = "saw", blueprintId = "ChopSaw", x = 0, z = 0, rot = 0, data = { x = 12, y = 0 } },
			{ uid = "mill", blueprintId = "SawmillRickety", x = 8, z = 0, rot = 0, data = { x = 1.4, y = 0.8 } },
		}
		s.P.PlayerJoined(ann, profile)
		s.P.Pass(ann)
		local saw, mill
		for _, item in ipairs(s.items(1)) do
			if item.Name == "saw" then
				saw = item
			elseif item.Name == "mill" then
				mill = item
			end
		end
		t.eq(saw:GetAttribute("CutU"), 12)
		t.eq(saw:GetAttribute("LengthShown"), 12)
		t.eq(profile.plot.placed[1].data, { x = 12, y = 0 })
		t.eq(mill:GetAttribute("CutX"), 1.4)
		t.eq(mill:GetAttribute("CutY"), 0.8)
		t.eq(profile.plot.placed[2].data, { x = 1.4, y = 0.8 })
	end)

	t.test("a sawmill on someone else's plot stays in stock", function()
		local s = setup({ cash = 200 })
		local ann, profile = s.newPlayer(1, "Ann")
		local bob = s.newPlayer(2, "Bob")
		profile.sawmillStock = { "SawmillRickety" }
		s.claim(ann, 1)
		s.claim(bob, 2)
		ann.standOn(2)
		s.P.Place(ann, "SawmillRickety", 0, 0, 0)
		t.eq(profile.sawmillStock, { "SawmillRickety" })
		t.eq(profile.cash, 200)
		t.eq(#profile.plot.placed, 0)
		t.eq(s.lastToast(), "You can't build on this plot.")
	end)

	t.test("buying only works at the Land Office", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		ann.standOn(nil)
		local cash = profile.cash
		s.prompt.Triggered.fn(ann)
		t.eq(ann.attrs.Picking, nil, "the prompt from across the map opens nothing")
		t.eq(s.lastToast(), "Walk up to the Land Office counter to buy a plot.")
		s.P.Claim(ann, 1)
		t.eq(profile.plot.claimed, false)
		t.eq(ann.attrs.PlotSlot, nil)
		t.eq(profile.cash, cash, "out of range: nothing charged")
		t.eq(s.lastToast(), "Walk up to the Land Office in town to buy a plot.")
		s.atOffice(ann)
		s.P.Claim(ann, 1)
		t.eq(ann.attrs.PlotSlot, 1)
		t.eq(profile.cash, cash - s.config.PlotPrice)
	end)

	t.test("growing only works while you stand on your plot", function()
		local s = setup({ cash = 3000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(nil)
		s.P.Upgrade(ann)
		t.eq(profile.plot.tier, 1)
		t.eq(profile.cash, 3000)
		t.eq(s.lastToast(), "Stand on your plot to raise its size.")
	end)

	t.test("you can only build on your own plot", function()
		local s = setup({ cash = 1000 })
		local ann, annProfile = s.newPlayer(1, "Ann")
		local bob, bobProfile = s.newPlayer(2, "Bob")
		s.claim(ann, 1)
		s.claim(bob, 2)
		ann.standOn(2)
		s.P.Place(ann, "Bench", 0, 0, 0)
		t.eq(#annProfile.plot.placed, 0)
		t.eq(annProfile.cash, 1000)
		t.eq(s.lastToast(), "You can't build on this plot.")
		t.eq(#bobProfile.plot.placed, 0)
	end)

	t.test("a plot and what you place on it stream as whole models, beside the shell", function()
		local s = setup()
		local ann = s.newPlayer(1, "Ann")
		local Atomic = t.roblox.Enum.ModelStreamingMode.Atomic
		for i = 1, #s.PlotData.Slots do
			t.eq(s.plot(i).ModelStreamingMode, Atomic, "plot " .. i)
		end
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Place(ann, "Bench", 0, 0, 0)
		local models = s.items(1)
		t.eq(#models, 1)
		t.eq(models[1].ModelStreamingMode, Atomic)
		t.eq(models[1].Parent.Name, "PlotItems_1")
		t.ok(models[1].Parent.Parent == s.plot(1).Parent, "placed items sit in the Plots folder")
		t.ok(models[1].Parent ~= s.plot(1), "placed items are not children of the plot model")
	end)

	t.test("joining twice does not hand out a second plot", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.claimed = true
		profile.plot.placed = { { uid = "a", blueprintId = "Bench", x = 4, z = 4, rot = 0 } }
		s.P.PlayerJoined(ann, profile)
		s.P.Pass(ann)
		t.eq(ann.attrs.PlotSlot, 1)
		t.eq(#s.items(1), 1)
		s.P.PlayerJoined(ann, profile)
		t.eq(ann.attrs.PlotSlot, 1)
		t.eq(s.plot(2):GetAttribute("OwnerId"), nil)
		t.eq(#s.items(1), 1)
	end)

	t.test("a full district keeps a saved layout until a slot frees", function()
		local s = setup()
		local owners = {}
		for i = 1, #s.PlotData.Slots do
			local player = s.newPlayer(i, "P" .. i)
			s.claim(player, i)
			table.insert(owners, player)
			t.eq(player.attrs.PlotSlot, i)
		end
		local extra, profile = s.newPlayer(99, "Extra")
		profile.plot.claimed = true
		profile.plot.placed = { { uid = "bench", blueprintId = "Bench", x = 2, z = 2, rot = 0 } }
		s.P.PlayerJoined(extra, profile)
		t.eq(extra.attrs.PlotSlot, nil)
		t.eq(#profile.plot.placed, 1)
		t.eq(s.lastToast(), "This server's plot district is full, so your plot isn't out today. Try another server!")
		s.P.PlayerRemoving(owners[1])
		t.eq(owners[1].attrs.PlotSlot, nil)
		t.eq(s.plot(1):GetAttribute("OwnerId"), nil)
		s.P.PlayerJoined(extra, profile)
		s.P.Pass(extra)
		t.eq(extra.attrs.PlotSlot, 1)
		t.eq(#s.items(1), 1)
		t.eq(s.items(1)[1].Name, "bench")
		s.P.PlayerJoined(extra, profile)
		t.eq(extra.attrs.PlotSlot, 1)
		local taken = 0
		for i = 1, #s.PlotData.Slots do
			if s.plot(i):GetAttribute("OwnerId") ~= nil then
				taken += 1
			end
		end
		t.eq(taken, #s.PlotData.Slots)
	end)

	t.test("twelve players each get a plot, and two pads stay open", function()
		local s = setup()
		local lastOffer
		for i = 1, 12 do
			local player, profile = s.newPlayer(i, "P" .. i)
			s.P.PlayerJoined(player, profile)
			s.atOffice(player)
			s.prompt.Triggered.fn(player)
			if i == 12 then
				lastOffer = s.P.OfferOf(player)
				local free = 0
				for _, plot in ipairs(lastOffer.plots) do
					if not plot.taken then
						free += 1
					end
				end
				t.eq(free, 3, "the last player still has a choice")
			end
			s.claim(player, i)
			t.eq(player.attrs.PlotSlot, i)
		end
		local free = 0
		for i = 1, #s.PlotData.Slots do
			if s.plot(i):GetAttribute("OwnerId") == nil then
				free += 1
			end
		end
		t.eq(free, #s.PlotData.Slots - 12)
	end)

	t.test("two claims of one plot in the same breath: one wins, the other is told to pick again", function()
		local s = setup()
		local ann, annProfile = s.newPlayer(1, "Ann")
		local bob, bobProfile = s.newPlayer(2, "Bob")
		annProfile.plot.placed = { { uid = "ann", blueprintId = "Bench", x = 2, z = 2, rot = 0 } }
		bobProfile.plot.placed = { { uid = "bob", blueprintId = "Flag", x = 4, z = 4, rot = 0 } }
		s.P.PlayerJoined(ann, annProfile)
		s.P.PlayerJoined(bob, bobProfile)
		for _, who in ipairs({ ann, bob }) do
			s.atOffice(who)
			s.prompt.Triggered.fn(who)
		end
		s.claim(ann, 4)
		s.claim(bob, 4)
		t.eq(ann.attrs.PlotSlot, 4)
		t.eq(bob.attrs.PlotSlot, nil)
		t.eq(s.plot(4):GetAttribute("OwnerId"), 1)
		t.eq(#s.items(4), 1)
		t.eq(s.items(4)[1].Name, "ann")
		t.eq(s.lastToast(), "Someone else claimed that plot. Pick another.")
		local offer = s.P.OfferOf(bob)
		t.eq(offer.notice, "taken")
		t.eq(offer.plots[4].taken, true)
		local jump = t.shared("PlotPickerLogic").NextOpen(offer.plots, 4)
		t.ok(jump ~= 4 and offer.plots[jump].taken ~= true, "the picker moves on")
		s.claim(bob, jump)
		t.eq(bob.attrs.PlotSlot, jump)
		t.eq(#s.items(jump), 1)
		t.eq(s.items(jump)[1].Name, "bob")
	end)

	t.test("a returning owner's picker: closing it or letting it time out takes a free pad, free", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.claimed = true
		local cash = profile.cash
		profile.plot.placed = { { uid = "a", blueprintId = "Bench", x = 2, z = 2, rot = 0 } }
		s.P.PlayerJoined(ann, profile)
		t.eq(ann.attrs.PlotSlot, nil)
		t.eq(ann.attrs.Picking, true)
		s.advance(500)
		s.P.Sweep()
		t.eq(ann.attrs.PlotSlot, nil, "the picker is not on the screen yet: no timer runs")
		s.P.Shown(ann)
		s.P.Shown(ann) -- a second ask never restarts it
		s.advance(59)
		s.P.Sweep()
		t.eq(ann.attrs.PlotSlot, nil, "the timer has not run out")
		s.advance(1)
		s.P.Sweep()
		t.eq(ann.attrs.PlotSlot, 1)
		t.eq(#s.items(1), 1)
		t.eq(ann.attrs.Picking, nil)

		local bob, bobProfile = s.newPlayer(2, "Bob")
		bobProfile.plot.claimed = true
		s.P.PlayerJoined(bob, bobProfile)
		s.P.Pass(bob)
		t.eq(bob.attrs.PlotSlot, 2)
		t.eq(s.lastToast(), "It's yours! This pad is your spawn. Take out your hammer to start building.")
		t.eq(profile.cash, cash, "a plot you already own is never charged again")
	end)

	t.test("leaving while the picker is open reserves nothing", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.claimed = true
		s.P.PlayerJoined(ann, profile)
		t.eq(ann.attrs.Picking, true)
		s.P.PlayerRemoving(ann)
		t.eq(ann.attrs.PlotSlot, nil)
		t.eq(s.plot(1):GetAttribute("OwnerId"), nil)
		s.advance(120)
		s.P.Sweep()
		t.eq(s.plot(1):GetAttribute("OwnerId"), nil, "the timer was cancelled")
		for i = 1, #s.PlotData.Slots do
			t.eq(s.plot(i):GetAttribute("OwnerId"), nil)
		end
	end)

	t.test("looking through the picker does not reserve a pad", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.claimed = true
		s.P.PlayerJoined(ann, profile)
		local offer = s.P.OfferOf(ann)
		t.eq(offer.price, 0, "a save that owns a plot sees no price")
		t.eq(#offer.plots, #s.PlotData.Slots)
		t.eq(offer.plots[1].name, "Birch Side")
		t.eq(offer.plots[1].region, "Starter Forest")
		for _, plot in ipairs(offer.plots) do
			t.eq(plot.taken, false)
		end
		t.eq(s.plot(1):GetAttribute("OwnerId"), nil)
	end)

	t.test("a claimed plot is the spawn; before that, town", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		local landed = nil
		ann.Character.PivotTo = function(_, cf)
			landed = cf
		end
		ann.CharacterAdded = {
			Connect = function(self, fn)
				self.fn = fn
			end,
		}
		s.P.PlayerJoined(ann, profile)
		t.eq(ann.RespawnLocation, nil)
		if ann.CharacterAdded.fn then
			ann.CharacterAdded.fn()
		end
		t.eq(landed, nil, "still the town spawn")
		s.claim(ann, 3)
		t.ok(ann.RespawnLocation == s.plot(3):FindFirstChild("PlotSpawn"))
		t.eq(ann.attrs.PlotSlot, 3)
		landed = nil
		ann.CharacterAdded.fn()
		t.ok(landed ~= nil, "death and rejoin put them on the pad")
	end)

	t.test("loading another save keeps the pad you already stand on", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.tier = 1
		profile.plot.placed = { { uid = "old", blueprintId = "Bench", x = 2, z = 2, rot = 0 } }
		s.P.PlayerJoined(ann, profile)
		s.claim(ann, 5)
		local other = {
			plot = {
				claimed = true,
				tier = 3,
				placed = { { uid = "new", blueprintId = "Flag", x = 6, z = 6, rot = 1 } },
			},
		}
		t.eq(s.P.Reload(ann, other), true)
		t.eq(ann.attrs.PlotSlot, 5)
		t.eq(ann.attrs.Picking, nil)
		t.eq(ann.attrs.PlotTier, 3)
		t.eq(#s.items(5), 1)
		t.eq(s.items(5)[1].Name, "new")
		t.eq(s.plot(5):GetAttribute("OwnerId"), 1)
	end)

	t.test("a bad saved spot moves onto the plot", function()
		local s = setup()
		local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
		local ann, profile = s.newPlayer(1, "Ann")
		local lake = WorldLayout.Lake
		local pad = s.PlotData.Slots[2]
		profile.truckAt = { x = lake.x, y = 4, z = lake.z }
		profile.leftLoad = { { woodId = "oak", value = 8, x = pad.X, y = 3, z = pad.Y } }
		profile.groundLoad = { { g = { pad.X, -40, pad.Y } } }
		profile.truckAt = profile.truckAt
		local town = { x = 0, y = 4, z = 40 }
		-- A second log that is fine stays put: checked after, on a fresh profile field.
		s.P.PlayerJoined(ann, profile)
		s.claim(ann, 1)
		-- There is no road-edge delivery pad any more: a stray spot goes to the
		-- middle of the plot that was claimed.
		t.eq(s.P.GetDeliveryPad, nil, "no delivery pad API")
		t.eq(s.P.DeliveryCFrame, nil, "no delivery pad API")
		local claimed = s.PlotData.Slots[1]
		local function nearDrop(x, z)
			return math.abs(x - claimed.X) < 0.01 and math.abs(z - claimed.Y) < 0.01
		end
		t.ok(nearDrop(profile.truckAt.x, profile.truckAt.z), "truckAt left the lake")
		t.ok(nearDrop(profile.leftLoad[1].x, profile.leftLoad[1].z), "leftLoad left the pad")
		t.ok(nearDrop(profile.groundLoad[1].g[1], profile.groundLoad[1].g[3]), "groundLoad left the hole")
		-- A dry town spot is not a pad and not under the ground.
		local kept = { x = town.x, y = town.y, z = town.z }
		profile.truckAt = kept
		s.P.Reload(ann, profile)
		t.eq(profile.truckAt.x, town.x)
		t.eq(profile.truckAt.z, town.z)
	end)

	t.test("a saved truckAt that sits on a new pad must spawn elsewhere on join", function()
		local s = setup()
		local _, profile = s.newPlayer(1, "Ann")
		local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
		local pad = s.PlotData.Slots[1]
		profile.truckAt = { x = pad.X, y = 3, z = pad.Y }
		profile.leftLoad = { { woodId = "oak", value = 4, x = pad.X, y = 3, z = pad.Y } }
		profile.groundLoad = { { g = { pad.X, 3, pad.Y } } }
		local server = require("@lune/fs").readFile("src/ServerScriptService/GameServer.server.luau")
		local parkAt = string.find(server, "PlotService.ParkStrays", 1, true)
		local padsAt = string.find(server, "ShopService.PlayerJoined(player, profile)", 1, true)
		t.ok(parkAt ~= nil and padsAt ~= nil and parkAt < padsAt, "the lot pass runs before the pads come back")
		t.eq(string.find(server, "VehicleService.SpawnTruck", 1, true), nil, "joining builds no truck: only a pad does")
		s.P.ParkStrays(profile)
		t.eq(WorldLayout.OnPlotPad(profile.truckAt.x, profile.truckAt.z), false)
		local lot = WorldLayout.ParkingLot
		t.ok(profile.truckAt.x > lot.x0 and profile.truckAt.x < lot.x1, "truckAt is in the town lot")
		t.ok(profile.truckAt.z > lot.z0 and profile.truckAt.z < lot.z1, "truckAt is in the town lot")
		t.eq(WorldLayout.OnPlotPad(profile.leftLoad[1].x, profile.leftLoad[1].z), false)
		t.eq(WorldLayout.OnPlotPad(profile.groundLoad[1].g[1], profile.groundLoad[1].g[3]), false)
	end)

	t.test("a build saved on one pad loads at the same spot on the pad you claim next", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.placed = {
			{ uid = "bench", blueprintId = "Bench", x = 12, z = -6, rot = 1 },
			{ uid = "flag", blueprintId = "Flag", x = -4, z = 8, rot = 2 },
		}
		s.P.PlayerJoined(ann, profile)
		s.claim(ann, 2)
		t.eq(#s.items(2), 2)
		s.P.PlayerRemoving(ann)
		t.eq(#s.items(2), 0, "the old pad is clear")
		t.eq(s.plot(2):GetAttribute("OwnerId"), nil)
		s.P.PlayerJoined(ann, profile)
		s.claim(ann, 5)
		t.eq(#s.items(2), 0, "nothing left on the first pad")
		t.eq(#s.items(5), 2)
		local found = {}
		for _, model in ipairs(s.items(5)) do
			found[model.Name] = model.placedAt
		end
		t.eq(found.bench, { 12, -6, 1 })
		t.eq(found.flag, { -4, 8, 2 })
	end)

	t.test("a claim has to be a whole slot you don't already own", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		s.P.PlayerJoined(ann, profile)
		s.claim(ann, 1.5)
		s.claim(ann, 0)
		s.claim(ann, #s.PlotData.Slots + 1)
		s.claim(ann, "nope")
		t.eq(ann.attrs.PlotSlot, nil)
		s.claim(ann, 2)
		s.claim(ann, 3)
		t.eq(ann.attrs.PlotSlot, 2)
		t.eq(s.plot(3):GetAttribute("OwnerId"), nil)
		t.eq(s.lastToast(), "You already have a plot here.")
	end)

	-- Loose wood for FillStep. One real part: every record can share it, and
	-- FillStep still sees each record (typeof Instance, a BasePart).
	local function loose(origin, uid, opts)
		opts = opts or {}
		local CFrame = t.roblox.CFrame
		local model = t.roblox.Instance.new("Model")
		model.Name = uid
		local root = t.roblox.Instance.new("Part")
		root.Name = "Root"
		root.Size = Vector3.new(1.6, 4, 1.6)
		local at = origin + (opts.offset or Vector3.zero)
		root.CFrame = CFrame.new(at)
		root.Position = at
		root.Anchored = true
		root.Parent = model
		model.PrimaryPart = root
		model:SetAttribute("HeldBy", opts.heldBy or 0)
		return {
			uid = uid,
			kind = opts.kind or "plank",
			woodId = opts.woodId or "birch",
			volume = if opts.volume == nil then 2 else opts.volume,
			ownerId = if opts.ownerId == nil then 1 else opts.ownerId,
			root = root,
			model = model,
			figure = nil,
			boost = 0,
			lux = false,
		}
	end

	local function plotOrigin(data, index)
		local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
		local c = data.Slots[index]
		return Vector3.new(c.X, TerrainGen.HeightAt(c.X, c.Y), c.Y)
	end

	local function woodApi(pieces)
		return {
			All = function()
				return pieces
			end,
			Get = function(id)
				return pieces[id]
			end,
			Remove = function(piece)
				pieces[piece.uid] = nil
			end,
			SpawnPlank = function()
				return { uid = "left" }
			end,
		}
	end

	t.test("200 built pieces and 2500 planks give zero PlotFill.Apply calls", function()
		local applies = 0
		local pieces = {}
		local s = setup({
			wood = woodApi(pieces),
			plotFill = {
				Apply = function()
					applies += 1
					return false, "built"
				end,
			},
		})
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		local origin = plotOrigin(s.PlotData, 1)
		local placed = {}
		for i = 1, 200 do
			placed[i] = {
				uid = "w" .. i,
				blueprintId = "Wall",
				x = 0,
				z = 0,
				rot = 0,
				fill = { units = 8 },
				wood = "birch",
			}
		end
		profile.plot.placed = placed
		for i = 1, 2500 do
			pieces["p" .. i] = loose(origin, "p" .. i)
		end
		s.P.FillStep()
		t.eq(applies, 0)
		t.eq(placed[1].fill.units, 8, "a built piece keeps the wood it already has")
		t.eq(placed[#placed].fill.units, 8)
	end)

	t.test("a plank on the plot is offered; one past the plot plus reach is not", function()
		local applies = 0
		local pieces = {}
		local s = setup({
			wood = woodApi(pieces),
			plotFill = {
				Apply = function()
					applies += 1
					return false, "busy"
				end,
			},
		})
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		local origin = plotOrigin(s.PlotData, 1)
		profile.plot.placed = {
			{ uid = "wall", blueprintId = "Wall", x = 0, z = 0, rot = 0, fill = { units = 0 } },
		}
		pieces.near = loose(origin, "near")
		pieces.far = loose(origin, "far", { offset = Vector3.new(0, 0, 500) })
		s.P.FillStep()
		t.eq(applies, 1, "only the plank inside the plot plus reach")
		t.eq(profile.plot.placed[1].fill.units, 0, "the plank past reach did not fill it")
	end)

	local function clearPieces(pieces)
		for key in pairs(pieces) do
			pieces[key] = nil
		end
	end

	t.test("a plank resting near a built wall, and a held plank near a blueprint, each give zero notifies", function()
		local pieces = {}
		local s = setup({ wood = woodApi(pieces) })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		local origin = plotOrigin(s.PlotData, 1)

		profile.plot.placed = {
			{
				uid = "built",
				blueprintId = "Wall",
				x = 0,
				z = 0,
				rot = 0,
				fill = { units = 8 },
				wood = "birch",
			},
		}
		pieces.resting = loose(origin, "resting")
		local n = #s.toasts
		s.P.FillStep()
		t.eq(#s.toasts, n, "a plank resting near a built wall")
		t.eq(profile.plot.placed[1].fill.units, 8, "a built wall takes no more wood")

		s.advance(1)
		clearPieces(pieces)
		profile.plot.placed = {
			{ uid = "ghost", blueprintId = "Wall", x = 0, z = 0, rot = 0, fill = { units = 0 } },
		}
		pieces.held = loose(origin, "held", { heldBy = 1 })
		s.P.NoteRelease(ann, pieces.held)
		s.P.FillStep()
		t.eq(#s.toasts, n, "a held plank near a blueprint")
		t.eq(profile.plot.placed[1].fill.units, 0, "a held plank does not fill")

		-- The same blueprint, wood that isn't yours, and a log left sitting.
		s.advance(1)
		clearPieces(pieces)
		pieces.theirs = loose(origin, "theirs", { ownerId = 2 })
		pieces.log = loose(origin, "log", { kind = "log" })
		s.P.NoteRelease(ann, pieces.theirs)
		s.P.FillStep()
		t.eq(#s.toasts, n, "someone else's wood, and a log left sitting, never toast")
		t.eq(profile.plot.placed[1].fill.units, 0)
	end)

	t.test("a just-dropped log or the wrong wood toasts once, and leaving forgets that", function()
		local pieces = {}
		local s = setup({ wood = woodApi(pieces) })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		local origin = plotOrigin(s.PlotData, 1)
		profile.plot.placed = {
			{
				uid = "ghost",
				blueprintId = "Wall",
				x = 0,
				z = 0,
				rot = 0,
				fill = { units = 0 },
				wood = "birch",
			},
		}
		pieces.oak = loose(origin, "oak", { woodId = "oak" })
		local n = #s.toasts
		s.advance(10)
		s.P.FillStep()
		t.eq(#s.toasts, n, "resting on the blueprint: no toast")
		t.eq(profile.plot.placed[1].fill.units, 0, "wrong wood left sitting does not fill")

		s.advance(1)
		s.P.NoteRelease(ann, pieces.oak)
		s.P.FillStep()
		t.eq(s.lastToast(), "This Wall is being built with Birch.")
		t.eq(#s.toasts, n + 1)
		t.eq(profile.plot.placed[1].fill.units, 0, "wrong wood does not fill")

		-- Still inside the two seconds, so the same refusal stays quiet.
		s.advance(0.2)
		s.P.NoteRelease(ann, pieces.oak)
		s.P.FillStep()
		t.eq(#s.toasts, n + 1, "told already")

		s.P.PlayerRemoving(ann)
		s.claim(ann, 1)
		s.advance(0.2)
		s.P.NoteRelease(ann, pieces.oak)
		s.P.FillStep()
		t.eq(s.lastToast(), "This Wall is being built with Birch.")
		t.eq(#s.toasts, n + 3, "leaving cleared the toast memory")

		clearPieces(pieces)
		profile.plot.placed = {
			{ uid = "open", blueprintId = "Wall", x = 0, z = 0, rot = 0, fill = { units = 0 } },
		}
		pieces.log = loose(origin, "log", { kind = "log" })
		s.advance(1)
		s.P.NoteRelease(ann, pieces.log)
		s.P.FillStep()
		t.eq(s.lastToast(), "Saw logs into planks first.")
		t.eq(profile.plot.placed[1].fill.units, 0, "a log does not fill")
	end)

	t.test("the land office uses the interact button and opens once the plot is claimed", function()
		local s = setup()
		local sign = s.plot(1):FindFirstChild("Sign")
		local office = sign:FindFirstChild("LandOffice")
		t.eq(office.Name, "LandOffice")
		t.eq(office.GamepadKeyCode, t.roblox.Enum.KeyCode.ButtonX)
		t.eq(office.KeyboardKeyCode, t.roblox.Enum.KeyCode.E)
		t.eq(office.Enabled, false)
		t.eq(sign:FindFirstChild("ProximityPrompt"), nil, "the sign no longer claims anything")
		local ann = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		t.eq(office.Enabled, true)
	end)

	t.test("expanding deducts the shown price, and too little cash buys nothing", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		profile.cash = 100
		s.P.Expand(ann, 2, 2, 0)
		t.eq(s.lastToast(), "Expand onto a square that touches your plot.")
		t.eq(profile.plot.squares, {})
		t.eq(profile.cash, 100)
		local GameConfig = t.shared("GameConfig")
		local Util = t.shared("Util")
		local step = GameConfig.ExpansionPriceStep
		s.P.Expand(ann, 1, 0, 0)
		t.eq(profile.cash, 0)
		t.eq(profile.plot.squares, { "1,0" })
		t.eq(s.lastToast(), "You expanded your plot for $100. The next square is " .. Util.formatCash(step) .. ".")
		t.eq(ann.attrs.PlotSquares, "1,0")
		s.P.Expand(ann, 1, 1, 1)
		t.eq(s.lastToast(), "You don't have enough to expand there.")
		t.eq(profile.cash, 0)
		t.eq(#profile.plot.squares, 1)
		profile.cash = step
		s.P.Expand(ann, 1, 1, 1)
		t.eq(profile.cash, 0)
		t.eq(#profile.plot.squares, 2)
		t.eq(
			s.lastToast(),
			"You expanded your plot for "
				.. Util.formatCash(step)
				.. ". The next square is "
				.. Util.formatCash(step * 2)
				.. "."
		)
		ann.standOn(nil)
		profile.cash = 6000
		s.P.Expand(ann, 0, 2, 2)
		t.eq(s.lastToast(), "Stand on your plot to expand it.")
		t.eq(#profile.plot.squares, 2)
		t.eq(profile.cash, 6000)
	end)

	t.test("two rapid expands charge once and add one square", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		profile.cash = 10000
		local nested = 0
		spendDuring = function()
			nested += 1
			if nested == 1 then
				-- Still inside the first spend: same count, a second square.
				s.P.Expand(ann, 1, 1, 0)
			end
		end
		local ran, err = pcall(function()
			s.P.Expand(ann, 1, 0, 0)
		end)
		spendDuring = nil
		if not ran then
			error(err)
		end
		t.eq(nested, 1)
		t.eq(profile.plot.squares, { "1,0" })
		t.eq(profile.cash, 9900)
		-- The tap after that still quotes the old count.
		s.P.Expand(ann, 2, 1, 0)
		t.eq(s.lastToast(), "The price changed. The Land panel shows the new one.")
		t.eq(profile.plot.squares, { "1,0" })
		t.eq(profile.cash, 9900)
	end)

	t.test("a friend cannot build until build is ticked, and a stranger with visit off is moved off", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		local bob, bobProfile = s.newPlayer(2, "Bob")
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Place(ann, "Bench", 0, 0, 0)
		local first = profile.plot.placed[1]
		local annCash = profile.cash
		bob.standOn(1)
		s.P.Place(bob, "Bench", 20, 0, 0)
		t.eq(s.lastToast(), "You can't build on this plot.")
		s.P.Move(bob, first.uid, 10, 0, 0)
		t.eq(s.lastToast(), "You can't build on this plot.")
		t.eq(first.x, 0)
		s.P.Sell(bob, first.uid)
		t.eq(s.lastToast(), "You can't take that apart.")
		t.eq(#profile.plot.placed, 1)
		t.eq(profile.cash, annCash)
		t.eq(bobProfile.cash, 100000)

		profile.permissions = { anyone = { build = true } }
		s.P.Place(bob, "Bench", 20, 0, 0)
		t.eq(#profile.plot.placed, 2)
		t.eq(profile.cash, annCash, "the host does not pay")
		t.eq(bobProfile.cash, 100000 - 80)
		local second = profile.plot.placed[2]
		t.eq(s.itemFolder(1):FindFirstChild(second.uid):GetAttribute("OwnerId"), 1)
		s.P.Move(bob, first.uid, 10, 0, 1)
		t.eq({ first.x, first.z, first.rot }, { 10, 0, 1 })
		s.P.Sell(bob, first.uid)
		t.eq(#profile.plot.placed, 1)
		t.eq(profile.cash, annCash + 80, "the refund goes to the owner")
		t.eq(bobProfile.cash, 100000 - 80)

		profile.permissions = { anyone = { visit = false } }
		local center = s.PlotData.Slots[1]
		bob.standOn(1)
		s.P.VisitStep({ bob, ann })
		t.eq(bob.root.Position.X, center.X)
		t.eq(bob.root.Position.Z, center.Y + 48)
		t.eq(ann.root.Position.X, center.X)
		t.eq(ann.root.Position.Z, center.Y)
	end)

	-- Plot visits: Settings > Visitors lists the people whose plot lets you
	-- in, and PlotService.Visit puts you on a safe spot of their plot.
	local function onPlot(s, spot, i)
		local c = s.PlotData.Slots[i]
		return math.abs(spot.X - c.X) <= 56 and math.abs(spot.Z - c.Y) <= 56
	end

	t.test("a visit lands on the owner's plot, on dry ground off the roads, and costs nothing", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		local bob, bobProfile = s.newPlayer(2, "Bob")
		s.claim(ann, 1)
		bob.standOn(nil)
		local cash = bobProfile.cash
		t.ok(s.P.Visit(bob, 1))
		t.ok(onPlot(s, bob.root.Position, 1), "inside the plot")
		local PlotLogic = t.shared("PlotLogic")
		t.ok(not PlotLogic.InWater(bob.root.Position.X, bob.root.Position.Z), "not in water")
		t.ok(not PlotLogic.OnRoad(bob.root.Position.X, bob.root.Position.Z), "not on a road")
		t.eq(s.lastToast(), "Visiting Ann's plot.")
		t.eq(bobProfile.cash, cash)
		t.eq(profile.cash, 100000)
		-- The bound remote does the same thing.
		bob.standOn(nil)
		s.remotes.VisitPlot.OnServerEvent.fn(bob, 1)
		t.ok(onPlot(s, bob.root.Position, 1))
	end)

	t.test("a visit is refused: visit off, you in particular, yourself, no plot, junk, or too fast", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		local bob = s.newPlayer(2, "Bob")
		local cat = s.newPlayer(3, "Cat")
		s.newPlayer(4, "Dan") -- in the server with no plot
		s.claim(ann, 1)
		local function away(p)
			p.standOn(nil)
			return p.root.Position
		end
		profile.permissions = { anyone = { visit = false } }
		local start = away(bob)
		t.eq(s.P.Visit(bob, 1), false)
		t.eq(bob.root.Position, start, "nobody moved")
		t.eq(s.lastToast(), "That plot isn't open to visitors.")
		-- One named friend is let in over the closed door.
		profile.permissions = { anyone = { visit = false }, ["3"] = { visit = true } }
		t.ok(s.P.Visit(cat, 1))
		t.eq(s.P.Visit(bob, 1), false)
		-- A stranger turned away by name.
		profile.permissions = { ["2"] = { visit = false } }
		t.eq(s.P.Visit(bob, 1), false)
		profile.permissions = {}
		t.eq(s.P.Visit(ann, 1), false, "not your own plot")
		t.eq(s.P.Visit(bob, 4), false, "Dan has no plot")
		t.eq(s.lastToast(), "That player has no plot to visit right now.")
		t.eq(s.P.Visit(bob, 99), false, "not in the server")
		for _, junk in ipairs({ "1", -1, 0, 1.5, 0 / 0, math.huge, {}, true }) do
			t.eq(s.P.Visit(bob, junk), false, tostring(junk))
		end
		t.eq(bob.root.Position, start)
		t.ok(s.P.Visit(bob, 1), "and a plain visit still works")
	end)

	t.test("a visit is rate limited by the RateLimiter and a visitor with no character goes nowhere", function()
		local s = setup({ rate = false })
		local ann = s.newPlayer(1, "Ann")
		local bob = s.newPlayer(2, "Bob")
		s.claim(ann, 1)
		bob.standOn(nil)
		local start = bob.root.Position
		t.eq(s.P.Visit(bob, 1), false)
		t.eq(bob.root.Position, start)
		local s2 = setup()
		local ann2 = s2.newPlayer(1, "Ann")
		local bob2 = s2.newPlayer(2, "Bob")
		s2.claim(ann2, 1)
		bob2.Character = nil
		t.eq(s2.P.Visit(bob2, 1), false)
	end)

	---------------------------------------------------------------------------
	-- Nobody is given a plot: the Land Office sells the first (GameConfig.PlotPrice)
	---------------------------------------------------------------------------

	t.test("the plot price is real, and the picker shows the price the server charges", function()
		local s = setup({ cash = 1000 })
		local ann, profile = s.newPlayer(1, "Ann")
		t.ok(s.config.PlotPrice >= 100, "a plot costs real money")
		s.atOffice(ann)
		s.prompt.Triggered.fn(ann)
		t.eq(ann.attrs.Picking, true)
		local offer = s.P.OfferOf(ann)
		t.eq(offer.price, s.config.PlotPrice)
		s.P.Claim(ann, 2)
		t.eq(profile.cash, 1000 - offer.price, "exactly the shown price")
		t.eq(ann.attrs.PlotSlot, 2)
		t.eq(ann.attrs.Picking, nil)
		t.eq(s.questEvents, { "plotClaimed" })
	end)

	t.test("buying with enough cash assigns and charges exactly once, even ten rapid fires", function()
		local s = setup({ cash = 5000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.atOffice(ann)
		for _ = 1, 10 do
			s.P.Claim(ann, 1)
		end
		t.eq(profile.cash, 5000 - s.config.PlotPrice)
		t.eq(ann.attrs.PlotSlot, 1)
		t.eq(s.questEvents, { "plotClaimed" })
		-- Ten more, naming other pads: still one plot, one charge.
		for i = 2, 11 do
			s.P.Claim(ann, i)
		end
		t.eq(profile.cash, 5000 - s.config.PlotPrice)
		for i = 2, 11 do
			t.eq(s.plot(i):GetAttribute("OwnerId"), nil)
		end
		t.eq(s.lastToast(), "You already have a plot here.")
	end)

	t.test("a fire that lands while the charge is going through cannot buy a second plot", function()
		local s = setup({ cash = 5000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.atOffice(ann)
		local again = 0
		-- The purse call is the one place the claim could be re-entered.
		s.spendDuring(function()
			again += 1
			s.P.Claim(ann, 2)
		end)
		s.P.Claim(ann, 1)
		s.spendDuring(nil)
		t.eq(again, 1)
		t.eq(profile.cash, 5000 - s.config.PlotPrice)
		t.eq(ann.attrs.PlotSlot, 1)
		t.eq(s.plot(2):GetAttribute("OwnerId"), nil)
	end)

	t.test("too little cash refuses, charges nothing and says how much is missing", function()
		local s = setup({ cash = 100 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.atOffice(ann)
		s.P.Claim(ann, 1)
		t.eq(profile.cash, 100)
		t.eq(ann.attrs.PlotSlot, nil)
		t.eq(profile.plot.claimed, false)
		t.eq(s.plot(1):GetAttribute("OwnerId"), nil)
		t.eq(s.lastToast(), string.format("You need $%d more for a plot.", s.config.PlotPrice - 100))
		t.eq(s.questEvents, {})
		-- One dollar short is still short; the exact price is enough.
		profile.cash = s.config.PlotPrice - 1
		s.P.Claim(ann, 1)
		t.eq(s.lastToast(), "You need $1 more for a plot.")
		t.eq(ann.attrs.PlotSlot, nil)
		profile.cash = s.config.PlotPrice
		s.P.Claim(ann, 1)
		t.eq(ann.attrs.PlotSlot, 1)
		t.eq(profile.cash, 0)
	end)

	t.test("out of range of the Land Office refuses with nothing charged", function()
		local s = setup({ cash = 5000 })
		local ann, profile = s.newPlayer(1, "Ann")
		ann.standOn(nil)
		s.P.Claim(ann, 1)
		t.eq(profile.cash, 5000)
		t.eq(ann.attrs.PlotSlot, nil)
		-- Standing on a plot's own sign is not the Land Office either.
		ann.standAtSign(1)
		s.P.Claim(ann, 1)
		t.eq(profile.cash, 5000)
		t.eq(ann.attrs.PlotSlot, nil)
	end)

	t.test("an owner cannot buy twice, and a junk index buys nothing", function()
		local s = setup({ cash = 5000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.atOffice(ann)
		for _, junk in ipairs({ "1", 0, -1, 1.5, 0 / 0, math.huge, {}, true, 9999 }) do
			s.P.Claim(ann, junk)
			t.eq(profile.cash, 5000, tostring(junk))
			t.eq(ann.attrs.PlotSlot, nil)
		end
		s.P.Claim(ann, 3)
		local after = profile.cash
		s.prompt.Triggered.fn(ann)
		t.eq(s.lastToast(), "You already have a plot. Plots are bought here, one each.")
		s.P.Claim(ann, 4)
		t.eq(profile.cash, after)
		t.eq(ann.attrs.PlotSlot, 3)
		t.eq(s.plot(4):GetAttribute("OwnerId"), nil)
	end)

	t.test("a taken pad refuses before any charge", function()
		local s = setup({ cash = 5000 })
		local ann = s.newPlayer(1, "Ann")
		local bob, bobProfile = s.newPlayer(2, "Bob")
		s.claim(ann, 3)
		s.atOffice(bob)
		s.P.Claim(bob, 3)
		t.eq(bobProfile.cash, 5000)
		t.eq(bob.attrs.PlotSlot, nil)
		t.eq(s.lastToast(), "Someone else claimed that plot. Pick another.")
	end)

	t.test("the claim is rate limited", function()
		local s = setup({ cash = 5000, rate = false })
		local ann, profile = s.newPlayer(1, "Ann")
		s.atOffice(ann)
		s.P.Claim(ann, 1)
		t.eq(profile.cash, 5000)
		t.eq(ann.attrs.PlotSlot, nil)
	end)

	t.test("no free plot at join or on a timeout, for a save that never bought one", function()
		local s = setup()
		local ann, profile = s.newPlayer(1, "Ann")
		s.P.PlayerJoined(ann, profile)
		t.eq(ann.attrs.PlotSlot, nil)
		t.eq(ann.attrs.Picking, nil, "no picker at join")
		t.eq(s.P.OfferOf(ann), nil)
		s.advance(600)
		s.P.Sweep()
		s.P.Pass(ann)
		t.eq(ann.attrs.PlotSlot, nil)
		t.eq(profile.plot.claimed, false)
		for i = 1, #s.PlotData.Slots do
			t.eq(s.plot(i):GetAttribute("OwnerId"), nil)
		end
		-- The Land Office's picker has no timer and Close hands nothing out.
		s.atOffice(ann)
		s.prompt.Triggered.fn(ann)
		t.eq(ann.attrs.Picking, true)
		s.advance(600)
		s.P.Sweep()
		t.eq(ann.attrs.PlotSlot, nil)
		s.P.Pass(ann)
		t.eq(ann.attrs.Picking, nil)
		t.eq(ann.attrs.PlotSlot, nil, "closing the picker is not a free plot")
		t.eq(profile.cash, 100000)
	end)

	t.test("returning players are unaffected: their pad comes back free, saved layout and all", function()
		local s = setup({ cash = 40 })
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.claimed = true
		profile.plot.placed = { { uid = "a", blueprintId = "Bench", x = 4, z = 4, rot = 0 } }
		s.P.PlayerJoined(ann, profile)
		t.eq(ann.attrs.Picking, true)
		t.eq(s.P.OfferOf(ann).price, 0)
		-- Even broke and far from the office, they pick a pad from the join picker.
		ann.standOn(nil)
		s.P.Claim(ann, 2)
		t.eq(ann.attrs.PlotSlot, 2)
		t.eq(profile.cash, 40, "nothing charged")
		t.eq(#s.items(2), 1)
	end)

	t.test("a returning owner is never charged, at the Land Office either", function()
		local s = setup({ cash = 5000 })
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.claimed = true
		s.atOffice(ann)
		s.P.Claim(ann, 4)
		t.eq(ann.attrs.PlotSlot, 4)
		t.eq(profile.cash, 5000)
	end)

	t.test("another save that never bought a plot does not inherit the pad", function()
		local s = setup()
		local ann = s.newPlayer(1, "Ann")
		s.claim(ann, 5)
		local fresh = { plot = { claimed = false, tier = 1, placed = {} } }
		t.eq(s.P.Reload(ann, fresh), false)
		t.eq(ann.attrs.PlotSlot, nil)
		t.eq(s.plot(5):GetAttribute("OwnerId"), nil)
	end)

	t.test("a purchase that fails to build the plot is refunded and the pad stays free", function()
		local s = setup({ cash = 1000 })
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.placed = { { uid = "x", blueprintId = "Bench", x = 1, z = 1, rot = 0 } }
		s.atOffice(ann)
		s.explodeOnBuild(true)
		local ok = pcall(s.P.Claim, ann, 1)
		s.explodeOnBuild(false)
		t.eq(ok, false)
		t.eq(profile.cash, 1000, "refunded")
		t.eq(s.plot(1):GetAttribute("OwnerId"), nil)
		t.eq(ann.attrs.PlotSlot, nil)
	end)
	---------------------------------------------------------------------------
	-- Old Hank, the plot salesman: his Talk prompt runs the same purchase flow
	---------------------------------------------------------------------------

	-- NPCService builds him after PlotService.Init; fake just his Talk prompt.
	local function withHank(s)
		local Instance = fakeInstances()
		local map = Instance.new("Folder")
		local folder = Instance.new("Folder")
		folder.Name = "Townsfolk"
		folder.Parent = map
		local hank = Instance.new("Model")
		hank.Name = "OldHank"
		hank.Parent = folder
		local talk = Instance.new("ProximityPrompt")
		talk.Name = "Talk"
		talk.Parent = hank
		s.P.HookSalesman(map)
		return talk
	end

	t.test("talking to Old Hank at the counter opens the same picker, with the server's price", function()
		local s = setup({ cash = 1000 })
		local talk = withHank(s)
		local ann, profile = s.newPlayer(1, "Ann")
		s.atOffice(ann)
		talk.Triggered.fn(ann)
		t.eq(ann.attrs.Picking, true)
		t.eq(s.P.OfferOf(ann).price, s.config.PlotPrice)
		t.eq(profile.cash, 1000, "talking charges nothing")
		s.P.Claim(ann, 3)
		t.eq(ann.attrs.PlotSlot, 3)
		t.eq(profile.cash, 1000 - s.config.PlotPrice, "charged once, at the one price")
	end)

	t.test("Old Hank from across the map opens nothing; an owner is told so, nothing opens", function()
		local s = setup({ cash = 1000 })
		local talk = withHank(s)
		local ann, profile = s.newPlayer(1, "Ann")
		ann.standOn(nil)
		talk.Triggered.fn(ann)
		t.eq(ann.attrs.Picking, nil)
		t.eq(profile.cash, 1000)
		s.claim(ann, 1)
		local cash = profile.cash
		s.atOffice(ann)
		talk.Triggered.fn(ann)
		t.eq(ann.attrs.Picking, nil)
		t.eq(s.lastToast(), t.shared("PlotSalesmanData").OwnsLine)
		t.eq(profile.cash, cash)
	end)

	t.test("with the dialogue box wired, Old Hank's replies are the box, not toasts", function()
		local s = setup({ cash = 1000 })
		local talk = withHank(s)
		local said = {}
		s.P.Speak = function(who, text)
			table.insert(said, { who = who, text = text })
		end
		local ann = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		s.atOffice(ann)
		local toasts = #s.toasts
		talk.Triggered.fn(ann)
		t.eq(#said, 1, "one line, in the box")
		t.eq(said[1].who, ann)
		t.eq(said[1].text, t.shared("PlotSalesmanData").OwnsLine)
		t.eq(#s.toasts, toasts, "no toast on top of it")
		local far = s.newPlayer(2, "Bob")
		far.standOn(nil)
		talk.Triggered.fn(far)
		t.eq(#said, 2, "a visitor too far from the counter is told so, in the box too")
		t.eq(said[2].text, t.shared("PlotSalesmanData").FarLine)
		t.eq(far.attrs.Picking, nil, "and nothing opens")
	end)

	t.test("the counter's own Buy a plot prompt still works beside Old Hank", function()
		local s = setup({ cash = 1000 })
		withHank(s)
		local ann = s.newPlayer(1, "Ann")
		s.atOffice(ann)
		s.prompt.Triggered.fn(ann)
		t.eq(ann.attrs.Picking, true)
		t.eq(s.prompt.ActionText, "Buy a plot")
	end)

	-- Boxes, as BoxService would answer: a box is ready for one itemId and one buyer, once.
	local function fakeBoxes(s, boxes)
		s.P.Boxes = {
			ready = function(player, uid, itemId)
				local box = boxes[uid]
				return box ~= nil and not box.spent and box.buyer == player.UserId and box.itemId == itemId
			end,
			spend = function(player, uid, itemId)
				local box = boxes[uid]
				if box == nil or box.spent or box.buyer ~= player.UserId or box.itemId ~= itemId then
					return false
				end
				box.spent = true
				return true
			end,
		}
	end

	t.test("a box: opened, placed and spent in one go: no stock, no cash, the box is gone", function()
		local s = setup({ cash = 500 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		local boxes = {
			["box-mill"] = { buyer = 1, itemId = "Millmaster100" },
			["box-planer"] = { buyer = 1, itemId = "PlanerBench" },
			["box-belt"] = { buyer = 1, itemId = "ConveyorStraight" },
		}
		fakeBoxes(s, boxes)
		-- No box uid: it is a box at the Tool Shed, nothing is placed or charged.
		s.P.Place(ann, "Millmaster100", 0, 0, 0)
		t.eq(#profile.plot.placed, 0)
		t.eq(s.lastToast(), "Buy the Millmaster 100 at the Tool Shed first.")
		-- A box for a different item doesn't do.
		s.P.Place(ann, "Millmaster100", 0, 0, 0, nil, "box-planer")
		t.eq(#profile.plot.placed, 0, "the wrong box")
		t.eq(boxes["box-planer"].spent, nil)
		-- The right box places it, free, and is spent.
		s.P.Place(ann, "Millmaster100", 0, 0, 0, nil, "box-mill")
		t.eq(#profile.plot.placed, 1)
		t.eq(profile.plot.placed[1].blueprintId, "Millmaster100")
		t.eq(profile.cash, 500, "already paid at the counter")
		t.eq(boxes["box-mill"].spent, true)
		t.eq(profile.plot.placed[1].data, { x = 1, y = 0.6 })
		t.eq(profile.sawmillStock, {}, "no stock list involved")
		-- The same box again is gone: one use.
		s.P.Place(ann, "Millmaster100", 0, 20, 0, nil, "box-mill")
		t.eq(#profile.plot.placed, 1)
		-- A planer and a belt, the same way, each with their own box.
		s.P.Place(ann, "PlanerBench", 0, 20, 0, nil, "box-planer")
		s.P.Place(ann, "ConveyorStraight", 30, 0, 0, nil, "box-belt")
		t.eq(#profile.plot.placed, 3)
		t.eq(profile.cash, 500)
		local planer = profile.plot.placed[2]
		t.eq(planer.data, { x = 1, y = 0.6 }, "a planer starts at the default setting")
		t.eq(#s.items(1), 3)
	end)

	t.test("the Sky Bin: open and place from its box once; cancelling keeps the box; one per plot", function()
		local s = setup({ cash = 500 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		local boxes = { ["bin-1"] = { buyer = 1, itemId = "SkyBin" }, ["bin-2"] = { buyer = 1, itemId = "SkyBin" } }
		fakeBoxes(s, boxes)
		s.P.Place(ann, "SkyBin", 0, 0, 0)
		t.eq(#profile.plot.placed, 0, "no box, no stock: refused")
		s.P.Place(ann, "SkyBin", 400, 0, 0, nil, "bin-1")
		t.eq(boxes["bin-1"].spent, nil, "off the plot keeps the box")
		s.P.Place(ann, "SkyBin", 0, 0, 0, nil, "bin-1")
		t.eq(#profile.plot.placed, 1)
		t.eq(profile.cash, 500)
		t.eq(boxes["bin-1"].spent, true)
		t.eq(profile.sawmillStock, {})
		t.eq(profile.skyBinOwned, true)
		s.P.Place(ann, "SkyBin", 20, 0, 0, nil, "bin-2")
		t.eq(#profile.plot.placed, 1)
		t.eq(boxes["bin-2"].spent, nil, "a second bin is refused and its box kept")
		t.eq(s.lastToast(), "You already have a Sky Bin on your plot. There's only room for one.")
	end)

	t.test("a refused placing keeps the box: cancelling and blocked spots cost nothing", function()
		local s = setup({ cash = 500 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		local boxes =
			{ ["box-1"] = { buyer = 1, itemId = "PlanerHand" }, ["box-2"] = { buyer = 1, itemId = "PlanerHand" } }
		fakeBoxes(s, boxes)
		s.P.Place(ann, "PlanerHand", 0, 0, 0, nil, "box-1")
		t.eq(#profile.plot.placed, 1)
		-- Right on top of it: refused, the second box is not spent.
		s.P.Place(ann, "PlanerHand", 0, 0, 0, nil, "box-2")
		t.eq(#profile.plot.placed, 1)
		t.eq(s.lastToast(), "Something's in the way.")
		t.eq(boxes["box-2"].spent, nil)
		-- Off the plot: refused, not spent.
		s.P.Place(ann, "PlanerHand", 400, 0, 0, nil, "box-2")
		t.eq(boxes["box-2"].spent, nil)
		-- Somewhere free: placed, spent.
		s.P.Place(ann, "PlanerHand", 0, 12, 0, nil, "box-2")
		t.eq(boxes["box-2"].spent, true)
	end)

	t.test("planers: two to a plot, the owner's only; the third box is refused and kept", function()
		local s = setup({ cash = 500 })
		local ann, profile = s.newPlayer(1, "Ann")
		local bob, bobProfile = s.newPlayer(2, "Bob")
		s.claim(ann, 1)
		ann.standOn(1)
		local boxes = {}
		for i = 1, 4 do
			boxes["a" .. i] = { buyer = 1, itemId = "PlanerHand" }
		end
		boxes.bob = { buyer = 2, itemId = "PlanerHand" }
		fakeBoxes(s, boxes)
		s.P.Place(ann, "PlanerHand", 0, 0, 0, nil, "a1")
		s.P.Place(ann, "PlanerHand", 0, 12, 0, nil, "a2")
		t.eq(#profile.plot.placed, 2)
		s.P.Place(ann, "PlanerHand", 0, 24, 0, nil, "a3")
		t.eq(#profile.plot.placed, 2, "a plot has room for two planers")
		t.eq(s.lastToast(), "A plot has room for 2 planers. Take one apart first.")
		t.eq(boxes.a3.spent, nil, "and the box is kept")
		-- A visitor with build rights can't put a planer on your plot.
		profile.permissions = { anyone = { build = true } }
		bob.standOn(1)
		s.P.Place(bob, "PlanerHand", 30, 0, 0, nil, "bob")
		t.eq(#profile.plot.placed, 2)
		t.eq(s.lastToast(), "Only the plot's owner can put a planer down.")
		t.eq(boxes.bob.spent, nil)
		-- Someone else's box id is no good to you.
		s.P.Place(ann, "PlanerHand", 30, 0, 0, nil, "bob")
		t.eq(boxes.bob.spent, nil)
		t.ok(bobProfile ~= nil)
		-- Taking one apart (selling it back for half) frees the room.
		local uid = profile.plot.placed[1].uid
		s.P.Sell(ann, uid)
		t.eq(#profile.plot.placed, 1)
		s.P.Place(ann, "PlanerHand", 0, 24, 0, nil, "a3")
		t.eq(#profile.plot.placed, 2)
		t.eq(profile.sawmillStock, {}, "a planer never goes back to stock: the box was one use")
	end)

	t.test("belts: owner only, one box to a piece, capped at MaxConveyorsPerPlot", function()
		local s = setup({ cash = 500 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		local boxes = { b1 = { buyer = 1, itemId = "ConveyorStraight" }, b2 = { buyer = 1, itemId = "ConveyorTurn" } }
		fakeBoxes(s, boxes)
		-- A plot already holding the cap's worth of belts takes no more (and keeps the box).
		for i = 1, s.config.MaxConveyorsPerPlot do
			table.insert(
				profile.plot.placed,
				{ uid = "belt" .. i, blueprintId = "ConveyorStraight", x = -1000, z = 0, rot = 0 }
			)
		end
		s.P.Place(ann, "ConveyorTurn", 0, 0, 0, nil, "b2")
		t.eq(s.lastToast(), "A plot has room for 150 belt pieces.")
		t.eq(boxes.b2.spent, nil)
		t.eq(#profile.plot.placed, s.config.MaxConveyorsPerPlot)
	end)

	t.test(
		"an old save with a sawmill in stock still places it from stock (the legacy path), and keeps its cut",
		function()
			local s = setup({ cash = 200 })
			local ann, profile = s.newPlayer(1, "Ann")
			profile.sawmillStock = { "Millmaster200" }
			s.claim(ann, 1)
			ann.standOn(1)
			fakeBoxes(s, {})
			s.P.Place(ann, "Millmaster200", 0, 0, 0)
			t.eq(#profile.plot.placed, 1, "no box needed: the stock is honoured")
			t.eq(profile.sawmillStock, {})
			-- A saved cut from before finer steps is kept; a planer's saved setting is clamped to its tier.
			local old = setup()
			local bob, bobProfile = old.newPlayer(2, "Bob")
			bobProfile.plot.claimed = true
			bobProfile.plot.placed = {
				{ uid = "m", blueprintId = "Millmaster100", x = 0, z = 0, rot = 0, data = { x = 1.2, y = 0.8 } },
				{ uid = "p", blueprintId = "PlanerHand", x = 20, z = 0, rot = 0, data = { x = 99, y = -4 } },
				{ uid = "q", blueprintId = "PlanerBench", x = 40, z = 0, rot = 0 },
			}
			old.P.PlayerJoined(bob, bobProfile)
			old.P.Pass(bob)
			t.eq(bobProfile.plot.placed[1].data, { x = 1.2, y = 0.8 }, "a placed mill keeps its cut")
			t.eq(bobProfile.plot.placed[2].data, { x = 1.8, y = 0.4 }, "clamped to the Hand Planer's range")
			t.eq(bobProfile.plot.placed[3].data, { x = 1, y = 0.6 }, "none saved: the default")
		end
	)

	-- Paint and the sample buildings (modern kit).
	local function placeWall(s, ann, profile)
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Place(ann, "Wall", 0, 0, 0)
		return profile.plot.placed[1]
	end

	t.test("paint: free, saved on the piece, rebuilt from it, and the fee and sell value stay", function()
		local s = setup({ cash = 1000 })
		local ann, profile = s.newPlayer(1, "Ann")
		local item = placeWall(s, ann, profile)
		local cash = profile.cash
		t.eq(item.paint, nil)
		s.P.Paint(ann, item.uid, "charcoal")
		t.eq(item.paint, "charcoal")
		t.eq(profile.cash, cash, "painting is free")
		t.eq(item.paid, 32, "the fee paid is untouched")
		t.eq(item.fill, { units = 0 })
		local models = s.items(1)
		t.eq(#models, 1, "rebuilt: one model, not two")
		t.eq(models[1].Name, item.uid)
		t.eq(models[1]:GetAttribute("Paint"), "charcoal")
		s.P.Paint(ann, item.uid, "natural")
		t.eq(item.paint, nil, "natural brings the wood back")
		t.eq(s.items(1)[1]:GetAttribute("Paint"), nil)
		s.P.Paint(ann, item.uid, "white")
		s.P.Sell(ann, item.uid)
		t.eq(profile.cash, cash + 32, "an empty painted piece still returns the whole fee")
	end)

	t.test(
		"paint: a bad colour, a prebuilt piece, a stranger, too far, a missing piece and the rate limit do nothing",
		function()
			local s = setup({ cash = 1000 })
			local ann, profile = s.newPlayer(1, "Ann")
			local item = placeWall(s, ann, profile)
			s.P.Paint(ann, item.uid, "hot-pink")
			s.P.Paint(ann, item.uid, 5)
			s.P.Paint(ann, 7, "white")
			s.P.Paint(ann, "nope", "white")
			t.eq(item.paint, nil)
			s.P.Place(ann, "Bench", 20, 20, 0)
			local bench = profile.plot.placed[2]
			s.P.Paint(ann, bench.uid, "white")
			t.eq(bench.paint, nil, "a Bench is not painted")
			t.ok(s.lastToast() ~= nil)
			-- A stranger on the plot without the build permission.
			local bob = s.newPlayer(2, "Bob")
			bob.standOn(1)
			s.P.Paint(bob, item.uid, "white")
			t.eq(item.paint, nil, "not Bob's plot")
			t.eq(s.lastToast(), "You can't build on this plot.")
			-- Allowed with the permission.
			profile.permissions = { anyone = { build = true } }
			s.P.Paint(bob, item.uid, "white")
			t.eq(item.paint, "white", "a visitor who may build may paint")
			profile.permissions = {}
			-- Too far from the piece (still on the plot).
			ann.standOn(1)
			ann.root.Position = ann.root.Position + Vector3.new(60, 0, 0)
			s.P.Paint(ann, item.uid, "black")
			t.eq(item.paint, "white", "out of the brush's reach")
			-- Off the plot entirely.
			ann.standOn(nil)
			s.P.Paint(ann, item.uid, "black")
			t.eq(item.paint, "white")
		end
	)

	t.test("paint: the rate limit applies", function()
		local s = setup({ cash = 1000, rate = false })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		profile.plot.placed = { { uid = "w", blueprintId = "Wall", x = 0, z = 0, rot = 0, paid = 32 } }
		s.P.Paint(ann, "w", "white")
		t.eq(profile.plot.placed[1].paint, nil)
	end)

	t.test(
		"sample: a free test building on the owner's plot, all or nothing, and /sample clear takes it down",
		function()
			local s = setup({ cash = 1000 })
			local ann, profile = s.newPlayer(1, "Ann")
			s.claim(ann, 1)
			t.eq(({ s.P.PlaceSample(ann, "castle") })[1], false)
			ann.standOn(nil)
			local ok, text = s.P.PlaceSample(ann, "shop")
			t.eq(ok, false)
			t.eq(text, "Stand on your own plot.")
			ann.standOn(1)
			ann.root.CFrame = t.roblox.CFrame.new(ann.root.Position)
			local cash = profile.cash
			local good, line = s.P.PlaceSample(ann, "shop")
			t.ok(good, tostring(line))
			t.eq(profile.cash, cash, "free")
			t.eq(#profile.plot.placed, 10)
			for _, item in ipairs(profile.plot.placed) do
				t.eq(string.sub(item.uid, 1, 7), "sample-")
				if item.paid ~= nil then
					t.eq(item.paid, 0)
					t.eq(item.fill, nil)
				end
			end
			t.eq(#s.items(1), 10, "built in the world")
			-- A second one on top of the first finds another spot or refuses; never a half building.
			local before = #profile.plot.placed
			local again = s.P.PlaceSample(ann, "shop")
			t.ok(#profile.plot.placed == before or #profile.plot.placed == before + 10, "all or nothing")
			-- A plain piece is not touched by clear.
			s.P.Place(ann, "Bench", -30, -30, 0)
			local removed = s.P.ClearSamples(ann)
			t.ok(removed >= 10)
			t.eq(#profile.plot.placed, 1)
			t.eq(profile.plot.placed[1].blueprintId, "Bench")
			t.eq(#s.items(1), 1)
			t.eq(s.P.ClearSamples(ann), 0)
			_ = again
		end
	)

	t.test("sample: not on someone else's plot", function()
		local s = setup({ cash = 1000 })
		local ann = s.newPlayer(1, "Ann")
		local bob = s.newPlayer(2, "Bob")
		s.claim(ann, 1)
		s.claim(bob, 2)
		bob.standOn(1)
		bob.root.CFrame = t.roblox.CFrame.new(bob.root.Position)
		local ok, text = s.P.PlaceSample(bob, "modern")
		t.eq(ok, false)
		t.eq(text, "Stand on your own plot.")
		t.eq(#s.items(1), 0)
	end)

	-- Unload base / load base (Shared/BaseLogic). The cooldown reads os.time(),
	-- so a test that unloads twice clears it in between.
	local function baseWorld(opts)
		local s = setup(opts or { cash = 100000 })
		local calls = { commit = 0, despawn = 0, cleared = {}, assigned = 0 }
		s.P.Hooks.commit = function()
			calls.commit += 1
		end
		s.P.Hooks.despawn = function()
			calls.despawn += 1
		end
		s.P.Hooks.clearPads = function(plot)
			table.insert(calls.cleared, plot)
		end
		s.P.Hooks.assigned = function()
			calls.assigned += 1
		end
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Place(ann, "Bench", 4, 4, 1)
		s.P.Place(ann, "Bench", -8, 6, 0)
		profile.plot.pads = { { uid = "pad-a", id = "Rustbucket", kind = "Truck", x = 12, z = -12 } }
		local Base = t.shared("BaseLogic")
		return s, ann, profile, calls, Base
	end

	t.test("unload: the pad is free and clean, the save keeps the base untouched, nothing is charged", function()
		local s, ann, profile, calls, Base = baseWorld()
		local before = Base.Uids(profile)
		local record = profile.plot
		local snapshot = require("@lune/serde").encode("json", record)
		local cash = profile.cash
		t.eq(#before, 3, "two benches and a pad")
		s.P.BaseAction(ann, "unload")
		t.eq(ann.attrs.PlotSlot, nil, "no pad")
		t.eq(s.plot(1):GetAttribute("OwnerId"), nil, "the pad is free for the next player")
		t.eq(#s.items(1), 0, "no model is left standing on it")
		t.ok(profile.plot == record, "the same record, still the save's plot")
		t.eq(require("@lune/serde").encode("json", record), snapshot, "not one field changed")
		t.eq(Base.Uids(profile), before, "every piece and pad exactly once")
		t.eq(profile.plot.claimed, true, "the plot is still owned, so a pad can be picked again for free")
		t.eq(profile.cash, cash, "no money moves")
		t.eq(calls.commit, 1, "carried wood and the truck's load were put in the save first")
		t.eq(calls.despawn, 1)
		t.ok(calls.cleared[1] == record, "the pad models were taken down")
		t.ok(profile.baseCooldownUntil > os.time(), "the cooldown is on the profile")
		t.eq(ann.attrs.BaseCooldownUntil, profile.baseCooldownUntil)
		t.eq(ann.attrs.Picking, nil, "and the player is left in the world, no picker forced")
		t.eq(s.lastToast(), t.shared("BaseLogic").UnloadedToast)
	end)

	t.test("the cooldown holds a second unload, and survives a rejoin because it is on the profile", function()
		local s, ann, profile = baseWorld()
		s.P.BaseAction(ann, "unload")
		s.P.BaseAction(ann, "load")
		s.P.Claim(ann, 2)
		t.eq(ann.attrs.PlotSlot, 2, "loading it back is never cooled")
		s.P.BaseAction(ann, "unload")
		t.ok(string.find(s.lastToast(), "more seconds before unloading again", 1, true) ~= nil, s.lastToast())
		t.eq(ann.attrs.PlotSlot, 2, "nothing happened")
		profile.baseCooldownUntil = 0
		s.P.BaseAction(ann, "unload")
		t.eq(ann.attrs.PlotSlot, nil)
	end)

	t.test("load base: the free picker opens, and the base lands laid out the same on the pad you choose", function()
		local s, ann, profile, calls, Base = baseWorld()
		local before = Base.Uids(profile)
		local cash = profile.cash
		s.P.BaseAction(ann, "unload")
		local assignedBefore = calls.assigned
		ann.standOn(nil) -- the SAVES panel works from anywhere
		s.P.BaseAction(ann, "load")
		t.eq(ann.attrs.Picking, true, "the plot picker (its camera, map and pillar) opens")
		t.eq(s.P.OfferOf(ann).price, 0, "free: the plot was bought once")
		t.eq(#s.items(1), 0, "nothing is built until a pad is chosen")
		s.P.Claim(ann, 3)
		t.eq(ann.attrs.PlotSlot, 3)
		t.eq(#s.items(3), 2)
		local at = {}
		for _, model in ipairs(s.items(3)) do
			at[model.Name] = model.placedAt
		end
		for _, item in ipairs(profile.plot.placed) do
			t.eq(at[item.uid], { item.x, item.z, item.rot }, "plot-local coordinates carry over to any pad")
		end
		t.eq(Base.Uids(profile), before)
		t.ok(calls.assigned > assignedBefore, "its vehicle pads stand up on the new pad")
		t.eq(profile.cash, cash, "no second charge for the plot")
	end)

	t.test(
		"load base: the join picker's timer applies (starts when shown, then takes a free pad), and a second press only re-shows it",
		function()
			local s, ann, profile = baseWorld()
			s.P.BaseAction(ann, "unload")
			s.P.BaseAction(ann, "load")
			s.P.BaseAction(ann, "load")
			local offers = 0
			t.ok(s.P.OfferOf(ann) ~= nil)
			s.advance(500)
			s.P.Sweep()
			t.eq(ann.attrs.PlotSlot, nil, "not on screen yet: no timer")
			s.P.Shown(ann)
			s.advance(61)
			s.P.Sweep()
			t.eq(ann.attrs.PlotSlot, 1, "auto-assigned after the timeout")
			t.eq(#s.items(1), 2, "with the base on it")
			t.eq(#profile.plot.placed, 2)
			_ = offers
		end
	)

	t.test("load base does nothing for a save with no plot, or while the base is on a pad", function()
		local s, ann = baseWorld()
		s.P.BaseAction(ann, "load")
		t.eq(ann.attrs.Picking, nil, "the base is already on a pad")
		local bob = s.newPlayer(2, "Bob")
		s.P.BaseAction(bob, "load")
		s.P.BaseAction(bob, "unload")
		t.eq(bob.attrs.Picking, nil)
		t.eq(bob.attrs.PlotSlot, nil)
	end)

	t.test("loose wood on the plot does not block the unload: it is saved with the base and comes back", function()
		local collected, restored = 0, 0
		local found = { pieces = 12, sections = 30, unsaveable = 0 }
		local saved = {}
		local s, ann, profile, calls = baseWorld({
			cash = 100000,
			loose = {
				Scan = function()
					return found
				end,
				Collect = function(_, _, prof, withIngots)
					collected += 1
					t.eq(withIngots, true, "an unload takes the ingots too")
					prof.plot.loose = saved
					return true
				end,
				Restore = function(_, _, prof)
					restored += 1
					return #prof.plot.loose, 0
				end,
				RestoreStranded = function()
					return 0, 0
				end,
			},
		})
		saved[1] = { w = "oak", k = "log", bed = "Plot", at = { 1, 2, 3, 0, 0, 0 }, s = { { 1, 1, 1 } } }
		local restoredAtJoin = restored -- the first claim also asks for a restore (an empty one)
		s.P.BaseAction(ann, "unload")
		t.eq(collected, 1, "the loose things were collected into the save")
		t.eq(ann.attrs.PlotSlot, nil, "and the base came off the pad")
		t.eq(calls.commit, 1)
		t.eq(profile.plot.loose, saved)
		s.P.BaseAction(ann, "load")
		s.P.Claim(ann, 2)
		t.eq(restored, restoredAtJoin + 1, "loading the base on a pad puts them back")
		local told = false
		for _, line in ipairs(s.toasts) do
			if string.find(line, "back on your plot", 1, true) ~= nil then
				told = true
			end
		end
		t.ok(told, "the player is told what came back")
	end)

	t.test(
		"refused with nothing changed: too much loose to save, a base with no pad, another change in flight",
		function()
			local found = { pieces = 160, sections = 90, unsaveable = 0 }
			local collected = 0
			local s, ann, profile, calls = baseWorld({
				cash = 100000,
				loose = {
					Scan = function()
						return found
					end,
					Collect = function()
						collected += 1
						return true
					end,
					Restore = function()
						return 0, 0
					end,
					RestoreStranded = function()
						return 0, 0
					end,
				},
			})
			s.P.BaseAction(ann, "unload")
			t.ok(
				string.find(s.lastToast(), "160", 1, true) ~= nil
					and string.find(s.lastToast(), "10 first", 1, true) ~= nil,
				s.lastToast()
			)
			t.eq(ann.attrs.PlotSlot, 1)
			t.eq(#s.items(1), 2)
			t.eq(calls.commit, 0, "the world was not touched either")
			t.eq(collected, 0)
			t.eq(profile.baseCooldownUntil, 0)
			found = { pieces = 5, sections = 9, unsaveable = 0 }
			s.P.BaseAction(ann, "unload")
			t.eq(ann.attrs.PlotSlot, nil, "then it goes")
			profile.baseCooldownUntil = 0
			s.P.BaseAction(ann, "unload")
			t.eq(s.lastToast(), "Your base is not on a pad right now.")
		end
	)

	t.test("visitors on the plot are set down outside it before it comes down", function()
		local s, ann = baseWorld()
		local bob = s.newPlayer(2, "Bob")
		bob.standOn(1)
		local start = bob.root.Position
		s.P.BaseAction(ann, "unload")
		t.ok(bob.root.Position ~= start, "Bob was moved off the yard")
		t.eq(s.plot(1):GetAttribute("OwnerId"), nil)
	end)

	t.test(
		"a release that throws puts the base back on its pad: nothing doubled, no cooldown spent, the player told",
		function()
			local s, ann, profile, _, Base = baseWorld()
			local uids = Base.Uids(profile)
			local record = profile.plot
			local realSet = ann.SetAttribute
			local failures = 1
			ann.SetAttribute = function(self, key, value)
				if key == "PlotSlot" and value == nil and failures > 0 then
					failures -= 1
					error("the pad would not let go")
				end
				realSet(self, key, value)
			end
			s.P.BaseAction(ann, "unload")
			t.ok(profile.plot == record)
			t.eq(Base.Uids(profile), uids)
			t.eq(profile.baseCooldownUntil, 0, "an unload that did not happen costs no cooldown")
			t.eq(s.lastToast(), "Something went wrong and your base is still on its pad. Try again.")
			t.eq(ann.attrs.PlotSlot, 1)
			t.eq(#s.items(1), 2, "the pieces are standing once each, none doubled")
		end
	)

	t.test("leaving mid-unload changes nothing: the save is whole before or after, never half", function()
		local s, ann, profile, calls, Base = baseWorld()
		local before = Base.Uids(profile)
		local record = profile.plot
		s.P.Hooks.commit = function()
			calls.commit += 1
			s.profiles[ann] = nil -- they disconnected while the hand-over was in the air
		end
		s.P.BaseAction(ann, "unload")
		t.ok(profile.plot == record)
		t.eq(Base.Uids(profile), before)
		t.eq(profile.baseCooldownUntil, 0)
		t.eq(ann.attrs.PlotSlot, 1, "the pad is not half released")
	end)

	t.test("the intents are validated and rate limited: junk does nothing", function()
		local s, ann, profile, calls, Base = baseWorld()
		local before = Base.Uids(profile)
		for _, junk in ipairs({ 1, true, {}, "pack", "", "UNLOAD", "bring" }) do
			s.P.BaseAction(ann, junk)
		end
		t.eq(calls.commit, 0)
		t.eq(Base.Uids(profile), before)
		t.eq(ann.attrs.PlotSlot, 1)
		local s2, ann2, _, calls2 = baseWorld({ cash = 100000, rate = false })
		s2.P.BaseAction(ann2, "unload")
		t.eq(calls2.commit, 0)
	end)

	t.test("Old Hank is as he was: no bases offer, a plot owner just hears the owner line", function()
		local s = setup({ cash = 1000 })
		local talk = withHank(s)
		t.eq(s.P.Ask, nil)
		t.eq(s.P.HankPick, nil)
		local said = {}
		s.P.Speak = function(_, text)
			table.insert(said, text)
		end
		local ann = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		s.atOffice(ann)
		talk.Triggered.fn(ann)
		t.eq(said[1], t.shared("PlotSalesmanData").OwnsLine)
	end)
	-- Lane F: crafted furniture. PlotService.GrantPiece puts one placeable piece
	-- in stock; it places once for nothing and never enters the book.
	t.test(
		"GrantPiece: a crafted piece waits in stock, places free once, is never learned, sells for nothing",
		function()
			local s = setup({ cash = 100000 })
			local ann, profile = s.newPlayer(1, "Ann")
			s.claim(ann, 1)
			ann.standOn(1)
			t.eq({ s.P.GrantPiece(ann, "CopperLampPost", "craft") }, { true, nil })
			t.eq(profile.sawmillStock, { "CopperLampPost" })
			t.eq(ann.attrs.SawmillStock, "CopperLampPost", "the client reads the stock")
			t.eq(table.find(profile.blueprintBook, "CopperLampPost"), nil, "a crafted piece is stock, not a plan")
			local cash = profile.cash
			s.P.Place(ann, "CopperLampPost", 4, 4, 0)
			t.eq(#profile.plot.placed, 1)
			t.eq(profile.plot.placed[1].blueprintId, "CopperLampPost")
			t.eq(profile.cash, cash, "placing it is free")
			t.eq(#profile.sawmillStock, 0, "and spends the piece")
			t.eq(ann.attrs.SawmillStock, "")
			s.P.Place(ann, "CopperLampPost", 12, 4, 0)
			t.eq(#profile.plot.placed, 1, "no second one without another craft")
			t.ok(string.find(s.lastToast(), "Craft the Copper Lamp Post", 1, true) ~= nil, s.lastToast())
			s.advance(120) -- past the undo window
			s.P.Sell(ann, profile.plot.placed[1].uid)
			t.eq(profile.cash, cash, "furniture a craft made never turns into cash")
			t.eq(#profile.plot.placed, 0)
		end
	)

	t.test("GrantPiece: only the two furniture pieces, and a full stock refuses", function()
		local s = setup({ cash = 1000 })
		local ann, profile = s.newPlayer(1, "Ann")
		t.eq({ s.P.GrantPiece(ann, "Wall4", "craft") }, { false, "unknown" })
		t.eq({ s.P.GrantPiece(ann, "SawmillRickety", "craft") }, { false, "unknown" })
		t.eq({ s.P.GrantPiece(ann, 5, "craft") }, { false, "unknown" })
		t.eq({ s.P.GrantPiece(ann, "GoldChest", "craft") }, { true, nil })
		local max = t.shared("FurnitureData").MaxStock
		for _ = 2, max do
			t.eq(s.P.GrantPiece(ann, "GoldChest", "craft"), true)
		end
		t.eq({ s.P.GrantPiece(ann, "GoldChest", "craft") }, { false, "full" })
		t.eq({ s.P.CanGrant(ann, "GoldChest") }, { false, "full" })
		t.eq(#profile.sawmillStock, max, "nothing was added past the cap")
	end)
	-- Lane F: where fallen wood, slabs and trucks come back to.
	t.test("RecoverSpot: a spot above the owner's own plot, a new one each time, nothing without a pad", function()
		local s = setup({ cash = 100000 })
		local ann = s.newPlayer(1, "Ann")
		t.eq(s.P.RecoverSpot(ann), nil, "no pad, nowhere to come back to")
		s.claim(ann, 1)
		local centre = t.roblox.Vector3.new(s.PlotData.Slots[1].X, 0, s.PlotData.Slots[1].Y)
		local seen = {}
		for _ = 1, 16 do
			local cf = s.P.RecoverSpot(ann)
			t.ok(cf ~= nil)
			local at = cf.Position
			t.ok(math.abs(at.X - centre.X) < 30 and math.abs(at.Z - centre.Z) < 30, "over the plot")
			t.ok(at.Y > 4, "in the air above the platform")
			seen[string.format("%.1f,%.1f", at.X, at.Z)] = true
		end
		local count = 0
		for _ in pairs(seen) do
			count += 1
		end
		t.eq(count, 16, "sixteen different spots")
		s.P.BaseAction(ann, "unload")
		t.eq(s.P.RecoverSpot(ann), nil, "an unloaded base has no pad")
	end)
	-----------------------------------------------------------------------
	-- Lane F: sandstone and copper pieces, the undo, and building with friends
	-----------------------------------------------------------------------

	-- A fake world of slabs and ingots (BuildMaterials): parts by uid, takes and
	-- returns counted, the room for returns set by the test.
	local function materialsWorld(origin)
		local world = { parts = {}, taken = {}, slabsBack = {}, ingotsBack = {}, slabRoom = 24, ingotRoom = 40 }
		function world.add(uid, kind, ownerId, ore, offset)
			table.insert(world.parts, {
				uid = uid,
				kind = kind,
				ore = ore,
				ownerId = ownerId,
				held = false,
				position = origin + (offset or Vector3.zero),
			})
		end
		world.api = {
			Of = function(userId)
				local out = {}
				for _, part in ipairs(world.parts) do
					if part.ownerId == userId and not world.taken[part.uid] then
						table.insert(out, part)
					end
				end
				return out
			end,
			Take = function(uid)
				if world.taken[uid] then
					return false
				end
				world.taken[uid] = true
				return true
			end,
			SlabRoom = function()
				return world.slabRoom
			end,
			IngotRoom = function()
				return world.ingotRoom
			end,
			ReturnSlab = function(userId, cf)
				table.insert(world.slabsBack, { userId = userId, cf = cf })
				return true
			end,
			ReturnIngot = function(_, ore, cf)
				table.insert(world.ingotsBack, { ore = ore, cf = cf })
				return true
			end,
		}
		return world
	end

	t.test("sandstone: a ghost takes slabs from the owner's parts within reach, one part once", function()
		local pieces = {}
		local world = materialsWorld(Vector3.zero)
		local s = setup({ cash = 100000, wood = woodApi(pieces), materials = world.api })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		local origin = plotOrigin(s.PlotData, 1)
		profile.blueprintBook = { "SandWall4" }
		local cash = profile.cash
		s.P.Place(ann, "SandWall4", 4, 4, 0)
		t.eq(#profile.plot.placed, 1)
		local item = profile.plot.placed[1]
		t.eq(item.fill, { units = 0 }, "an empty ghost")
		t.eq(profile.cash, cash - 8, "the fee is charged once, on placing")
		world.parts = {}
		world.add("s1", "slab", 1, nil, Vector3.new(4, 3, 4) + Vector3.new(0, 0, 0))
		world.add("s2", "slab", 1, nil, Vector3.new(4, 3, 4))
		world.add("s3", "slab", 1, nil, Vector3.new(4, 3, 4))
		world.add("far", "slab", 1, nil, Vector3.new(0, 0, 400))
		world.add("theirs", "slab", 2, nil, Vector3.new(4, 3, 4))
		for _, part in ipairs(world.parts) do
			part.position = origin + part.position
		end
		s.advance(1)
		s.P.FillStep()
		t.eq(item.fill, nil, "two slabs finished it (a built piece keeps no fill)")
		local taken = 0
		for _ in pairs(world.taken) do
			taken += 1
		end
		t.eq(taken, 2, "exactly two slabs were destroyed")
		t.eq(world.taken.far, nil, "a slab past reach was not used")
		t.eq(world.taken.theirs, nil, "someone else's slab was not used")
		local third = world.taken.s1 and world.taken.s2 and world.taken.s3
		t.ok(not third, "the third slab stays a slab")
		local model = s.items(1)[1]
		t.eq(model:GetAttribute("Needs"), "Built")
	end)

	t.test("sandstone: a friend with Build adds their own slab; a stranger's is refused and stays", function()
		local pieces = {}
		local world = materialsWorld(Vector3.zero)
		local s = setup({ cash = 100000, wood = woodApi(pieces), materials = world.api })
		local ann, profile = s.newPlayer(1, "Ann")
		local bob = s.newPlayer(2, "Bob")
		local cal = s.newPlayer(3, "Cal")
		s.claim(ann, 1)
		ann.standOn(1)
		bob.standOn(1)
		cal.standOn(1)
		local origin = plotOrigin(s.PlotData, 1)
		profile.blueprintBook = { "SandWall4" }
		s.P.Place(ann, "SandWall4", 4, 4, 0)
		local item = profile.plot.placed[1]
		profile.permissions = { ["2"] = { build = true } }
		world.add("bobs", "slab", 2, nil, origin + Vector3.new(4, 3, 4))
		world.add("cals", "slab", 3, nil, origin + Vector3.new(4, 3, 4))
		s.advance(1)
		s.P.FillStep()
		t.eq(item.fill, { units = 0, slabs = 1 }, "Bob's slab went in, nobody else's")
		t.eq(world.taken.bobs, true)
		t.eq(world.taken.cals, nil, "Cal has no Build permission: his slab is untouched")
		profile.permissions = {}
		world.add("bobs2", "slab", 2, nil, origin + Vector3.new(4, 3, 4))
		s.advance(1)
		s.P.FillStep()
		t.eq(world.taken.bobs2, nil, "with the permission gone Bob's slab no longer fills it")
	end)

	t.test(
		"undo (BL3): within 60 s a finished sandstone wall gives its fee and both slabs back; after, half the fee only",
		function()
			local pieces = {}
			local world = materialsWorld(Vector3.zero)
			local s = setup({ cash = 100000, wood = woodApi(pieces), materials = world.api })
			local ann, profile = s.newPlayer(1, "Ann")
			s.claim(ann, 1)
			ann.standOn(1)
			local origin = plotOrigin(s.PlotData, 1)
			profile.blueprintBook = { "SandWall4" }
			local function build()
				s.P.Place(ann, "SandWall4", 4, 4, 0)
				local item = profile.plot.placed[#profile.plot.placed]
				world.parts = {}
				world.taken = {}
				world.add("a" .. item.uid, "slab", 1, nil, origin + Vector3.new(4, 3, 4))
				world.add("b" .. item.uid, "slab", 1, nil, origin + Vector3.new(4, 3, 4))
				s.advance(1)
				s.P.FillStep()
				t.eq(item.fill, nil)
				return item
			end
			local before = profile.cash
			local item = build()
			t.eq(profile.cash, before - 8)
			s.P.Sell(ann, item.uid)
			t.eq(profile.cash, before, "the whole fee came back")
			t.eq(#world.slabsBack, 2, "both slabs are on the ground again")
			t.eq(#profile.plot.placed, 0)
			-- After the window: SellBack on the fee, and the stone is gone for good.
			world.slabsBack = {}
			item = build()
			s.advance(61)
			local cash = profile.cash
			s.P.Sell(ann, item.uid)
			t.eq(profile.cash, cash + 4, "half the fee: sandstone never turns into cash")
			t.eq(#world.slabsBack, 0, "and no slab comes back")
		end
	)

	t.test(
		"undo (BL3): a half-filled ghost gives back its slabs and the whole fee; no room means it refuses and takes nothing",
		function()
			local pieces = {}
			local world = materialsWorld(Vector3.zero)
			local s = setup({ cash = 100000, wood = woodApi(pieces), materials = world.api })
			local ann, profile = s.newPlayer(1, "Ann")
			s.claim(ann, 1)
			ann.standOn(1)
			profile.blueprintBook = { "SandArch8" }
			local before = profile.cash
			s.P.Place(ann, "SandArch8", 4, 4, 0)
			local item = profile.plot.placed[1]
			item.fill = { units = 0, slabs = 3 }
			world.slabRoom = 2
			s.P.Sell(ann, item.uid)
			t.eq(#profile.plot.placed, 1, "refused: three slabs would not fit")
			t.ok(string.find(s.lastToast(), "loose slab", 1, true) ~= nil, s.lastToast())
			t.eq(profile.cash, before - 16, "nothing was refunded")
			t.eq(#world.slabsBack, 0)
			world.slabRoom = 24
			s.P.Sell(ann, item.uid)
			t.eq(#profile.plot.placed, 0)
			t.eq(#world.slabsBack, 3)
			t.eq(profile.cash, before, "the fee, in full, because it was within 60 s")
		end
	)

	t.test("copper: an ingot fills the trim, and undo gives it back as an ingot", function()
		local pieces = {}
		local world = materialsWorld(Vector3.zero)
		local s = setup({ cash = 100000, wood = woodApi(pieces), materials = world.api })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		local origin = plotOrigin(s.PlotData, 1)
		profile.blueprintBook = { "CopperTrim4" }
		s.P.Place(ann, "CopperTrim4", 4, 4, 0)
		local item = profile.plot.placed[1]
		world.add("iron", "ingot", 1, "Iron", origin + Vector3.new(4, 3, 4))
		world.add("cu", "ingot", 1, "Copper", origin + Vector3.new(4, 3, 4))
		s.advance(1)
		s.P.FillStep()
		t.eq(item.fill, nil, "the Copper ingot finished it")
		t.eq(world.taken.cu, true)
		t.eq(world.taken.iron, nil, "an Iron ingot is not taken")
		s.P.Sell(ann, item.uid)
		t.eq(#world.ingotsBack, 1)
		t.eq(world.ingotsBack[1].ore, "Copper")
	end)

	t.test("the 1,200 kit part cap refuses a new piece with a clear line and never deletes a build", function()
		local s = setup({ cash = 1000000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		local placed = {}
		for i = 1, 300 do
			placed[i] = {
				uid = "w" .. i,
				blueprintId = "WindowWall8",
				x = -90 + (i % 30) * 6,
				z = -90 + (i // 30) * 6,
				rot = 0,
			}
		end
		profile.plot.placed = placed
		s.P.Place(ann, "Wall4", 0, 0, 0)
		t.eq(#profile.plot.placed, 300, "the 301st piece (1,204 parts) is refused")
		t.ok(string.find(s.lastToast(), "1200 kit parts", 1, true) ~= nil, s.lastToast())
	end)
	-- Lane F: paint all of this type.
	t.test("PaintAllType: every piece of that type on the owner's plot, one undo step, others untouched", function()
		local s = setup({ cash = 100000 })
		local ann, profile = s.newPlayer(1, "Ann")
		s.claim(ann, 1)
		ann.standOn(1)
		for i = 1, 3 do
			s.P.Place(ann, "Wall4", -10 + i * 6, 4, 0)
		end
		s.P.Place(ann, "Floor4", 20, 20, 0)
		profile.plot.placed[2].paint = "brick"
		local cash = profile.cash
		s.P.PaintAllType(ann, "Wall4", "charcoal")
		for i = 1, 3 do
			t.eq(profile.plot.placed[i].paint, "charcoal", "wall " .. i)
		end
		t.eq(profile.plot.placed[4].paint, nil, "the floor is another type")
		t.eq(profile.cash, cash, "paint is free")
		t.eq(s.lastToast(), "Painted 3 Short Walls.")
		-- The model was rebuilt painted.
		local model = s.items(1)[1]
		t.ok(model ~= nil)
		-- One undo step puts all three back.
		s.P.Edit(ann, { op = "undo" })
		t.eq(
			{ profile.plot.placed[1].paint, profile.plot.placed[2].paint, profile.plot.placed[3].paint },
			{ nil, "brick", nil }
		)
		s.P.PaintAllType(ann, "Wall4", "charcoal")
		s.P.PaintAllType(ann, "Wall4", "charcoal")
		t.eq(s.lastToast(), "Every Short Wall already wears that colour.", "a second press is a no-op with a line")
	end)

	t.test("PaintAllType: a friend with Build may, a stranger may not, and junk does nothing", function()
		local s = setup({ cash = 100000 })
		local ann, profile = s.newPlayer(1, "Ann")
		local bob = s.newPlayer(2, "Bob")
		local cal = s.newPlayer(3, "Cal")
		s.claim(ann, 1)
		ann.standOn(1)
		bob.standOn(1)
		cal.standOn(1)
		s.P.Place(ann, "Wall4", -4, 4, 0)
		s.P.Place(ann, "Wall4", 4, 4, 0)
		profile.permissions = { ["2"] = { build = true } }
		s.P.PaintAllType(cal, "Wall4", "white")
		t.eq(
			{ profile.plot.placed[1].paint, profile.plot.placed[2].paint },
			{ nil, nil },
			"Cal has no Build permission"
		)
		t.eq(s.lastToast(), "You can't paint on this plot.")
		s.P.PaintAllType(bob, "Wall4", "white")
		t.eq({ profile.plot.placed[1].paint, profile.plot.placed[2].paint }, { "white", "white" }, "Bob may")
		for _, junk in ipairs({ 5, true, {}, "Nope", "Table" }) do
			s.P.PaintAllType(ann, junk, "tan")
			s.P.PaintAllType(ann, "Wall4", junk)
		end
		t.eq({ profile.plot.placed[1].paint, profile.plot.placed[2].paint }, { "white", "white" }, "nothing changed")
		profile.permissions = {}
		local limited = setup({ cash = 1000, rate = false })
		local dan, dprofile = limited.newPlayer(4, "Dan")
		limited.claim(dan, 1)
		dan.standOn(1)
		limited.P.Place(dan, "Wall4", 4, 4, 0)
		limited.P.PaintAllType(dan, "Wall4", "tan")
		t.eq(dprofile.plot.placed[1], nil, "a rate-limited player cannot even place")
	end)
end
