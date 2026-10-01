--!nocheck
-- LeftLoad (PLAY-14): a rejoin puts back at most MaxLeftLogs (72) saved
-- left-behind logs, each its own log model and prompt, even from a save
-- made under the old cap of 150. The restore runs the real VehicleService
-- and TreeService; the world (map, physics, prompts, timers) is faked.
return function(t)
	local roblox = t.roblox

	local LeftLoad = t.server("LeftLoad")
	local GameConfig = t.shared("GameConfig")
	local ItemCatalog = t.shared("ItemCatalog")

	-- `count` saved left-behind oak logs in a row along X (profile.leftLoad).
	local function saves(count)
		local list = {}
		for i = 1, count do
			table.insert(list, { woodId = "oak", value = 7, x = i * 4, y = 5, z = 30 })
		end
		return list
	end

	-- Real VehicleService + TreeService over a fake map: returns
	-- restore(saved) -> (restored, log models, prompts).
	local function world()
		local map = roblox.Instance.new("Folder")
		map.Name = "TimberlineMap"
		local prompts = 0
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
					GetPlayerByUserId = function()
						return nil
					end,
				},
				CollectionService = {
					AddTag = function(_, inst, tag)
						inst:AddTag(tag)
					end,
					GetTagged = function()
						return {}
					end,
				},
			},
			globals = {
				workspace = {
					WaitForChild = function(_, name)
						return if name == "TimberlineMap" then map else nil
					end,
					Raycast = function()
						return nil
					end,
					GetPartBoundsInBox = function()
						return {}
					end,
				},
				task = {
					delay = function() end, -- despawn timers never run here
					spawn = function(fn, ...)
						fn(...)
					end,
				},
				-- @lune/roblox instances have no events: a stand-in prompt.
				Instance = {
					new = function(class)
						if class == "ProximityPrompt" then
							prompts += 1
							return { Triggered = { Connect = function() end } }
						end
						return roblox.Instance.new(class)
					end,
				},
				RaycastParams = {
					new = function()
						return {}
					end,
				},
				OverlapParams = {
					new = function()
						return {}
					end,
				},
			},
		})
		local VehicleService = loader:server("VehicleService")
		local player = { UserId = 7, Name = "Ada" }
		return function(saved)
			local restored = VehicleService.RestoreLeftLoad(player, saved)
			local logs = map:FindFirstChild("Logs")
			return restored, if logs then logs:GetChildren() else {}, prompts
		end
	end

	t.test("MaxLeftLogs is the biggest load: a Logging Rig's 48 plus a Heavy Hauler's 24", function()
		t.eq(ItemCatalog.GetTruck("LoggingRig").bedCapacity, 48)
		t.eq(ItemCatalog.GetTrailer("HeavyHauler").extraCapacity, 24)
		local bed, trailer = 0, 0
		for _, truck in ipairs(ItemCatalog.TruckList()) do
			bed = math.max(bed, truck.bedCapacity)
		end
		for _, def in ipairs(ItemCatalog.TrailerList()) do
			trailer = math.max(trailer, def.extraCapacity)
		end
		t.eq(GameConfig.MaxLeftLogs, 72)
		t.eq(GameConfig.MaxLeftLogs, bed + trailer, "a full rig fits in the save")
	end)

	t.test("an old save of 150 gives back its first 72 entries, in saved order", function()
		local saved = saves(150)
		local kept = LeftLoad.ToRestore(saved)
		t.eq(#kept, GameConfig.MaxLeftLogs)
		for i = 1, #kept do
			t.ok(kept[i] == saved[i], "entry " .. i .. " is the saved one")
		end
		t.eq(#saved, 150, "the save's own list isn't changed")
	end)

	t.test("a save under the cap comes back whole", function()
		local saved = saves(10)
		t.eq(LeftLoad.ToRestore(saved), saved)
		t.eq(LeftLoad.ToRestore(saves(72)), saves(72))
		t.eq(LeftLoad.ToRestore({}), {})
	end)

	t.test("restoring 150 saved logs creates 72 log models at most, each with one prompt", function()
		local restore = world()
		local restored, models, prompts = restore(LeftLoad.ToRestore(saves(150)))
		t.eq(restored, 72)
		t.eq(#models, 72)
		t.eq(prompts, 72)
		for _, model in ipairs(models) do
			t.ok(model.PrimaryPart.CFrame.Position.X <= 72 * 4 + 1, "one of the first 72 saved")
			t.eq(model:GetAttribute("Value"), 7, "keeps its saved worth")
		end
	end)
end
