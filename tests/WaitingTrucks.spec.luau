--!nocheck
-- A truck with no box, and a full storage, is told to wait. Freeing a
-- slot later is ProfileSchema's mint, covered beside this toast.
return function(t)
	t.test("a full storage toasts each truck that is still waiting", function()
		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function()
						return nil
					end,
				},
			},
			services = {
				Players = {
					GetPlayers = function()
						return {}
					end,
				},
			},
		})
		local Schema = loader:server("ProfileSchema")
		local Vehicle = loader:server("VehicleService")
		local toasts = {}
		Vehicle.Hooks.notify = function(_, message)
			table.insert(toasts, message)
		end
		local profile = {
			ownedTrucks = { "Flatbed", "Pickup", "Rustbucket" },
			trucksBoxed = false,
			storage = {},
			plot = { claimed = true, tier = 1, placed = {}, squares = {}, pads = { { uid = "pad-1", id = "Pickup" } } },
		}
		for i = 1, Schema.StorageCap do
			table.insert(profile.storage, { uid = "full-" .. i, itemId = "SteelAxe", shop = "ToolShed" })
		end
		Vehicle.AnnounceWaiting({ Name = "Tester", UserId = 3 }, profile)
		t.eq(toasts, {
			"Your Flatbed is waiting. Free a storage slot to get its box.",
			"Your Rustbucket is waiting. Free a storage slot to get its box.",
		})
		t.eq(#profile.storage, Schema.StorageCap)
		t.eq(profile.trucksBoxed, false)
	end)
end
