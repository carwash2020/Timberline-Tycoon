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

	-- v2 (M1.6): the loose wood on the bed, saved in profile.truckLoad.
	local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
	local function isWood(id)
		return id == "oak" or id == "pine"
	end
	local function near(a, b, eps)
		return (a.Position - b.Position).Magnitude < (eps or 0.002)
			and (a.LookVector - b.LookVector).Magnitude < 0.001
			and (a.UpVector - b.UpVector).Magnitude < 0.001
	end
	-- A saved piece with `sections` sections.
	local function piece(sections, over)
		local s = {}
		for i = 1, sections do
			table.insert(s, LeftLoad.EncodeSection(Vector3.new(2, 9, 2), CFrame.new(0, (i - 1) * 9, 0), 3))
		end
		local p = { w = "oak", k = "log", bed = "BedFloor", at = LeftLoad.EncodeCFrame(CFrame.new(0, 1.25, 0)), s = s }
		for k, v in pairs(over or {}) do
			p[k] = v
		end
		return p
	end

	t.test("a place on the bed round-trips through 6 saved numbers", function()
		local cf = CFrame.new(1.234, 2.5, -7.75) * CFrame.fromEulerAnglesXYZ(0.3, -1.2, 2.5)
		local saved = LeftLoad.EncodeCFrame(cf)
		t.eq(#saved, 6)
		t.ok(near(LeftLoad.DecodeCFrame(saved), cf), "same place, same turn")
		t.eq(LeftLoad.DecodeCFrame({ 1, 2, 3 }), nil, "too few numbers")
		t.eq(LeftLoad.DecodeCFrame({ 0 / 0, 0, 0, 0, 0, 0 }), nil, "NaN")
		t.eq(LeftLoad.DecodeCFrame({ 1e6, 0, 0, 0, 0, 0 }), nil, "miles from its bed")
		t.eq(LeftLoad.DecodeCFrame("junk"), nil)
		local size, rel, faces = LeftLoad.DecodeSection(LeftLoad.EncodeSection(Vector3.new(2, 9, 2), cf, 2))
		t.eq(size, Vector3.new(2, 9, 2))
		t.ok(near(rel, cf), "section place")
		t.eq(faces, 2)
		t.eq(LeftLoad.DecodeSection({ 0, 9, 2, 0, 0, 0, 0, 0, 0, 0 }), nil, "a flat section is junk")
	end)

	t.test("CleanPiece keeps a sane piece and drops junk", function()
		local good = piece(2, { f = "burl", x = 2 })
		local clean = LeftLoad.CleanPiece(good, isWood)
		t.ok(clean, "kept")
		t.eq(clean.w, "oak")
		t.eq(clean.f, "burl")
		t.eq(clean.x, 2)
		t.eq(LeftLoad.CleanPiece(piece(1, { l = true }), isWood).l, true, "the Lux tag survives a save")
		t.eq(LeftLoad.CleanPiece(piece(1, { l = false }), isWood).l, nil)
		t.eq(#clean.s, 2)
		t.ok(clean ~= good and clean.s ~= good.s, "a new table")
		t.eq(LeftLoad.CleanPiece(piece(1, { k = "weird" }), isWood).k, "log", "an odd kind reads as a log")
		t.eq(LeftLoad.CleanPiece(piece(1, { k = "plank" }), isWood).k, "plank")
		t.eq(LeftLoad.CleanPiece(piece(1, { x = 1 }), isWood).x, nil, "boost 1 is no boost")
		t.eq(LeftLoad.CleanPiece(piece(1, { x = 50 }), isWood).x, LeftLoad.MaxBoost, "boost capped")
		t.eq(LeftLoad.CleanPiece(piece(1, { w = "unobtainium" }), isWood), nil, "unknown wood")
		t.eq(LeftLoad.CleanPiece(piece(1, { bed = "Roof" }), isWood), nil, "unknown bed")
		t.eq(LeftLoad.CleanPiece(piece(1, { at = { 1, 2 } }), isWood), nil, "no place")
		t.eq(LeftLoad.CleanPiece(piece(0), isWood), nil, "no sections")
		local broken = piece(2)
		broken.s[2] = { "x" }
		t.eq(LeftLoad.CleanPiece(broken, isWood), nil, "a broken section")
		t.eq(LeftLoad.CleanPiece(5, isWood), nil)
	end)

	t.test("the save holds MaxSavedPieces pieces and MaxSavedSections sections, most valuable first", function()
		t.eq(GameConfig.MaxSavedPieces, 40)
		t.eq(GameConfig.MaxSavedSections, 300)
		local many = {}
		for i = 1, 60 do
			table.insert(many, piece(1, { f = tostring(i) }))
		end
		local kept, dropped = LeftLoad.Fit(many)
		t.eq(#kept, 40)
		t.eq(dropped, 20)
		for i = 1, 40 do
			t.ok(kept[i] == many[i], "kept in the order given: " .. i)
		end
		-- Sections: a big piece that doesn't fit is skipped, a smaller one
		-- after it still goes in.
		local list = { piece(250), piece(60), piece(50) }
		local fit, over = LeftLoad.Fit(list)
		t.eq(#fit, 2)
		t.eq(over, 1)
		t.ok(fit[1] == list[1] and fit[2] == list[3], "the 60-section piece is skipped")
		local total = 0
		for _, p in ipairs(fit) do
			total += #p.s
		end
		t.ok(total <= GameConfig.MaxSavedSections, "sections capped")
	end)

	t.test("PiecesToRestore cleans then caps a saved truckLoad", function()
		local saved = { piece(1), "junk", piece(1, { w = "gone" }) }
		for _ = 1, 45 do
			table.insert(saved, piece(1, { w = "pine" }))
		end
		local kept, dropped = LeftLoad.PiecesToRestore(saved, isWood)
		t.eq(#kept, 40)
		t.eq(dropped, 2 + 6)
		t.eq(kept[1].w, "oak")
		t.eq(LeftLoad.PiecesToRestore(nil, isWood), {})
		t.eq(LeftLoad.PiecesToRestore({}, isWood), {})
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
