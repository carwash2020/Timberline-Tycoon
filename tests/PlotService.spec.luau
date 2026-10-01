--!nocheck
-- Plots on the server: claiming, placing, moving, selling back, growing,
-- and rebuilding a saved layout on whichever slot you get.
return function(t)
	local Vector2, Vector3 = t.roblox.Vector2, t.roblox.Vector3

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
		local toasts, tags = {}, {}
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
			return player, profile
		end

		local loader = t.loader({
			globals = {
				Instance = Instance,
				os = {
					clock = function()
						return clock
					end,
					time = os.time,
				},
			},
			services = {
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
						return true
					end,
				},
				EconomyService = {
					SpendCash = function(player, amount)
						local profile = profiles[player]
						if profile.cash < amount then
							return false
						end
						profile.cash -= amount
						return true
					end,
					Refund = function(player, amount)
						profiles[player].cash += amount
						return amount, 0
					end,
				},
				BlueprintModels = {
					Build = function(bp)
						local model = Instance.new("Model")
						model.Name = bp.id
						return model
					end,
					Place = function(model, _plotCFrame, x, z, rot)
						model.placedAt = { x, z, rot }
					end,
				},
			},
		})
		local PlotService = loader:server("PlotService")
		local map = Instance.new("Folder")
		local remotes = {}
		for _, name in ipairs({ "PlaceBlueprint", "MoveBlueprint", "SellPlaced", "UpgradePlot" }) do
			remotes[name] = Instance.new("RemoteEvent")
		end
		PlotService.Init(map, remotes, function(_, message)
			table.insert(toasts, message)
		end)
		local plots = map:FindFirstChild("Plots")

		local function plot(i)
			return plots:FindFirstChild("Plot_" .. i)
		end
		local function claim(player, i)
			plot(i):FindFirstChild("Sign"):FindFirstChild("ProximityPrompt").Triggered.fn(player)
		end
		local function items(i)
			return plot(i):FindFirstChild("Items"):GetChildren()
		end
		return {
			P = PlotService,
			PlotData = PlotData,
			newPlayer = newPlayer,
			plot = plot,
			claim = claim,
			items = items,
			toasts = toasts,
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

	t.test("the district has a free plot per slot, each with a claim sign", function()
		local s = setup()
		for i = 1, #s.PlotData.Slots do
			local sign = s.plot(i):FindFirstChild("Sign")
			t.ok(sign:FindFirstChild("ProximityPrompt").Enabled, "plot " .. i .. " can be claimed")
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
		t.eq(ann.attrs.PlotSlot, 3)
		t.eq(ann.attrs.PlotTier, 1)
		t.eq(s.plot(3):GetAttribute("OwnerId"), 1)
		t.ok(not s.plot(3):FindFirstChild("Sign"):FindFirstChild("ProximityPrompt").Enabled)
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
		local model = s.plot(1):FindFirstChild("Items"):FindFirstChild(first.uid)
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
		s.P.Upgrade(ann)
		t.eq(profile.plot.tier, 2)
		t.eq(profile.cash, 500)
		t.eq(ann.attrs.PlotTier, 2)
		t.eq(s.plot(1):GetAttribute("Tier"), 2)
		t.eq(s.plot(1):FindFirstChild("Pad").Size.X, 140)
		s.P.Upgrade(ann)
		t.eq(profile.plot.tier, 2)
		t.eq(s.lastToast(), "You need $9,500 more for a Lumber Yard.")
		profile.plot.tier = #s.PlotData.Tiers
		s.P.Upgrade(ann)
		t.eq(s.lastToast(), "Your plot is as big as it gets.")
	end)

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
		t.eq(ann.attrs.PlotSlot, 2)
		t.eq(#s.items(2), 1)
		t.eq(s.items(2)[1].Name, "a")
		s.P.PlayerRemoving(ann)
		t.eq(#s.items(2), 0)
		t.eq(s.plot(2):GetAttribute("OwnerId"), nil)
		t.ok(s.plot(2):FindFirstChild("Sign"):FindFirstChild("ProximityPrompt").Enabled)
		t.eq(#profile.plot.placed, 2, "leaving keeps the save")

		local cara, fresh = s.newPlayer(3, "Cara")
		s.P.PlayerJoined(cara, fresh) -- never claimed: no plot yet
		t.eq(cara.attrs.PlotSlot, nil)
	end)
end
