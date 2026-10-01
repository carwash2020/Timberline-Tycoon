--!nocheck
-- Buying a trailer while driving a truck that can't tow (the Scout ATV):
-- the purchase goes through, but it isn't hitched, and the toast says why.
return function(t)
	local Vector3 = t.roblox.Vector3
	local COUNTER = Vector3.new(-45, 2.5, 99.5)

	local function node(children)
		local n = {}
		function n:FindFirstChild(name)
			return children[name]
		end
		return n
	end

	local function setup(equippedTruck)
		local profile = {
			cash = 5000,
			totalEarned = 0,
			bestAxeTier = 1,
			ownedTrucks = { "Rustbucket", "ScoutATV" },
			equippedTruck = equippedTruck,
			ownedTrailers = {},
			equippedTrailer = "",
			gear = {},
		}
		local toasts, switched = {}, {}
		local character = node({ HumanoidRootPart = { Position = COUNTER + Vector3.new(0, 0, -4) } })
		function character:FindFirstChildOfClass()
			return nil
		end
		local player = { Name = "Tester", Character = character, SetAttribute = function() end }
		local point = {
			WorldPosition = COUNTER,
			IsA = function(_, class)
				return class == "Attachment"
			end,
		}
		local map = node({ Dealership = node({ Counter = node({ ShopPoint = point }) }) })
		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
				},
				AxeService = {},
				MilestoneService = { Mark = function() end },
				QuestService = { Event = function() end },
				VehicleService = {
					Equip = function(_, truckId, trailerId)
						table.insert(switched, truckId .. "+" .. (trailerId or ""))
						return true, nil
					end,
				},
			},
		})
		local ShopService = loader:server("ShopService")
		local buy
		local function remote(set)
			return {
				OnServerEvent = {
					Connect = function(_, fn)
						set(fn)
					end,
				},
			}
		end
		ShopService.Init(
			map,
			remote(function(fn)
				buy = fn
			end),
			remote(function() end),
			function(_, message)
				table.insert(toasts, message)
			end
		)
		return {
			buy = function(category, id)
				buy(player, category, id)
			end,
			profile = profile,
			toasts = toasts,
			switched = switched,
		}
	end

	t.test("on the Scout ATV: bought, not hitched, and told why", function()
		local s = setup("ScoutATV")
		s.buy("Trailer", "PonyTrailer")
		t.eq(s.profile.ownedTrailers, { "PonyTrailer" })
		t.eq(s.profile.cash, 4400)
		t.eq(s.profile.equippedTrailer, "", "not hitched to a truck that can't tow")
		t.eq(s.switched, {}, "the rig isn't rebuilt")
		t.eq(s.toasts, {
			"Bought the Pony Trailer! The Scout ATV can't tow, so hitch it here once you drive a truck with a bed.",
		})
	end)

	t.test("on a truck with a bed: bought and hitched as before", function()
		local s = setup("Rustbucket")
		s.buy("Trailer", "PonyTrailer")
		t.eq(s.profile.equippedTrailer, "PonyTrailer")
		t.eq(s.switched, { "Rustbucket+PonyTrailer" })
	end)
end
