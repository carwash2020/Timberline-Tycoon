--!nocheck
-- The BuyItem remote: range, order and cash are checked on the server.
return function(t)
	local Vector3 = t.roblox.Vector3
	local COUNTER = Vector3.new(-45, 2.5, 99.5)

	local function node(children, props)
		local n = props or {}
		function n:FindFirstChild(name)
			return children[name]
		end
		return n
	end

	local function setup(options)
		local profile = { cash = options.cash or 0, totalEarned = 0, bestAxeTier = options.bestTier or 1 }
		local toasts, granted, equipped = {}, {}, {}
		local humanoid = {
			EquipTool = function(_, tool)
				table.insert(equipped, tool)
			end,
		}
		local hrp = { Position = options.at or (COUNTER + Vector3.new(0, 0, -4)) }
		local character = node({ HumanoidRootPart = hrp })
		function character:FindFirstChildOfClass(class)
			return if class == "Humanoid" then humanoid else nil
		end
		local player = {
			Name = "Tester",
			Character = character,
			SetAttribute = function() end,
		}
		local point = {
			WorldPosition = COUNTER,
			IsA = function(_, class)
				return class == "Attachment"
			end,
		}
		local map = node({ ToolShed = node({ Counter = node({ ShopPoint = point }) }) })

		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
				},
				AxeService = {
					OwnedCounts = function()
						return options.owned or { RustyAxe = 1 }, options.ownedTotal or 1
					end,
					Grant = function(_, axeId)
						table.insert(granted, axeId)
						return { uid = "new", id = axeId }, { Name = axeId .. "Tool" }
					end,
				},
				MilestoneService = { Mark = function() end },
			},
		})
		local ShopService = loader:server("ShopService")
		local handler
		ShopService.Init(map, {
			OnServerEvent = {
				Connect = function(_, fn)
					handler = fn
				end,
			},
		}, function(_, message)
			table.insert(toasts, message)
		end)
		return {
			buy = function(category, itemId)
				handler(player, category, itemId)
			end,
			profile = profile,
			toasts = toasts,
			granted = granted,
			equipped = equipped,
		}
	end

	t.test("buys the next axe: takes the cash, grants it and puts it in hand", function()
		local s = setup({ cash = 200 })
		s.buy("Axe", "SteelAxe")
		t.eq(s.profile.cash, 50)
		t.eq(s.granted, { "SteelAxe" })
		t.eq(s.equipped[1].Name, "SteelAxeTool")
		t.eq(s.toasts, { "Bought the Steel Axe! It's in your hotbar." })
	end)

	t.test("too far from the counter: nothing happens but a hint", function()
		local s = setup({ cash = 200, at = COUNTER + Vector3.new(0, 0, -40) })
		s.buy("Axe", "SteelAxe")
		t.eq(s.profile.cash, 200)
		t.eq(s.granted, {})
		t.eq(s.toasts, { "Walk up to the counter to buy." })
	end)

	t.test("skipping a rung is refused", function()
		local s = setup({ cash = 5000 })
		s.buy("Axe", "SilverAxe")
		t.eq(s.profile.cash, 5000)
		t.eq(s.granted, {})
		t.eq(s.toasts, { "Axes are sold in order. Buy the Steel Axe first." })
	end)

	t.test("short on cash: says how much more", function()
		local s = setup({ cash = 120 })
		s.buy("Axe", "SteelAxe")
		t.eq(s.profile.cash, 120)
		t.eq(s.granted, {})
		t.eq(s.toasts, { "You need $30 more for the Steel Axe." })
	end)

	t.test("forged axes and the starter axe are never sold", function()
		local s = setup({ cash = 100000, bestTier = 8 })
		s.buy("Axe", "StarfallAxe")
		s.buy("Axe", "RustyAxe")
		t.eq(s.profile.cash, 100000)
		t.eq(s.granted, {})
		t.eq(#s.toasts, 2)
	end)

	t.test("a full inventory is refused", function()
		local s = setup({ cash = 1000, bestTier = 2, owned = { SteelAxe = 20 }, ownedTotal = 20 })
		s.buy("Axe", "SteelAxe")
		t.eq(s.granted, {})
		t.eq(s.profile.cash, 1000)
	end)

	t.test("junk requests are ignored silently", function()
		-- A fresh setup each, so BuyItem's rate limit (3/s) isn't what stops them.
		for _, args in ipairs({
			{ 42, "SteelAxe" },
			{ "Axe", { "SteelAxe" } },
			{ "Truck", "Pickup" },
			{ "Axe", "NoSuchAxe" },
		}) do
			local s = setup({ cash = 1000 })
			s.buy(args[1], args[2])
			t.eq(s.granted, {})
			t.eq(s.toasts, {})
			t.eq(s.profile.cash, 1000)
		end
	end)

	t.test("BuyItem is rate-limited", function()
		local s = setup({ cash = 100000, bestTier = 3, owned = { SteelAxe = 1 }, ownedTotal = 2 })
		for _ = 1, 10 do
			s.buy("Axe", "SteelAxe")
		end
		t.eq(#s.granted, 3)
	end)
end
