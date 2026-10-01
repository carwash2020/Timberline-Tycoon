--!nocheck
-- TreeService on the server: who a felling counts for, trees coming back
-- as ghosts while something's in their way, the Phantom Grove's stumps by
-- day, and where logs land on a slope. The physics queries (Raycast,
-- GetPartBoundsInBox), the players, the trucks and the timers are faked.
return function(t)
	local roblox = t.roblox
	local Vector3, CFrame = roblox.Vector3, roblox.CFrame

	local function setup()
		local s = {
			delays = {},
			clock = 100,
			blocked = false, -- what GetPartBoundsInBox finds in a trunk's way
			queries = 0,
			rays = {},
			byId = {},
			trucks = {},
		}

		local map = roblox.Instance.new("Folder")
		map.Name = "TimberlineMap"
		local TerrainGen -- loaded below, for the fake ground
		local workspace = {
			WaitForChild = function(_, name)
				return if name == "TimberlineMap" then map else nil
			end,
			GetServerTimeNow = function()
				return 0
			end,
			Raycast = function(_, origin, direction)
				table.insert(s.rays, { origin = origin, direction = direction })
				-- The ground is TerrainGen's, if the ray reaches it.
				local h = TerrainGen.HeightAt(origin.X, origin.Z)
				if origin.Y >= h and origin.Y + direction.Y <= h then
					return { Position = Vector3.new(origin.X, h, origin.Z) }
				end
				return nil
			end,
			GetPartBoundsInBox = function()
				s.queries += 1
				return if s.blocked then { "a truck" } else {}
			end,
		}

		local Players = {
			GetPlayers = function()
				local list = {}
				for _, p in pairs(s.byId) do
					table.insert(list, p)
				end
				return list
			end,
			GetPlayerByUserId = function(_, id)
				return s.byId[id]
			end,
		}
		local CollectionService = {
			AddTag = function(_, inst, tag)
				inst:AddTag(tag)
			end,
			GetTagged = function(_, tag)
				return if tag == "Truck" then s.trucks else {}
			end,
		}
		local fakeTask = {
			delay = function(seconds, fn, ...)
				table.insert(s.delays, { seconds = seconds, fn = fn, args = table.pack(...) })
			end,
			spawn = function(fn, ...)
				fn(...)
			end,
		}
		-- @lune/roblox instances have no events: a stand-in pickup prompt.
		local Instance = {
			new = function(class)
				if class == "ProximityPrompt" then
					return { Triggered = { Connect = function() end } }
				end
				return roblox.Instance.new(class)
			end,
		}
		local function params()
			return {
				new = function()
					return {}
				end,
			}
		end

		local loader = t.loader({
			services = { Players = Players, CollectionService = CollectionService },
			globals = {
				workspace = workspace,
				task = fakeTask,
				Instance = Instance,
				RaycastParams = params(),
				OverlapParams = params(),
				os = setmetatable({
					clock = function()
						return s.clock
					end,
				}, { __index = os }),
			},
		})
		TerrainGen = loader:load("ReplicatedStorage/Shared/World/TerrainGen")
		s.TerrainGen = TerrainGen
		s.Trees = loader:server("TreeService")
		s.ItemCatalog = loader:shared("ItemCatalog")
		s.TreeLogic = loader:shared("TreeLogic")
		s.map = map

		function s.player(userId, pos)
			local root = { Position = pos or Vector3.new(4, 0, 0) }
			local p = {
				UserId = userId,
				Character = {
					FindFirstChild = function(_, child)
						return if child == "HumanoidRootPart" then root else nil
					end,
				},
			}
			p.root = root
			s.byId[userId] = p
			return p
		end

		-- A normal-size tree of `woodId` standing at `pos`; returns its record.
		function s.tree(woodId, pos)
			local model = s.Trees.SpawnTree(woodId, CFrame.new(pos or Vector3.new(0, 0, 0)), {
				seed = 7,
				size = s.TreeLogic.Sizes[2],
			})
			return s.Trees.GetTree(model:GetAttribute("Uid"))
		end

		-- Runs the timers due within `seconds` (all of them by default).
		function s.run(seconds)
			local due, later = {}, {}
			for _, d in ipairs(s.delays) do
				table.insert(if seconds == nil or d.seconds <= seconds then due else later, d)
			end
			s.delays = later
			for _, d in ipairs(due) do
				d.fn(table.unpack(d.args, 1, d.args.n))
			end
		end

		-- Up to `times` swings (the Rusty Axe, or the best axe for hard
		-- woods), stopping when the tree is down.
		function s.chop(p, rec, times)
			local axe = s.ItemCatalog.GetAxe("RustyAxe")
			if s.ItemCatalog.AxeDamage(axe, rec.def) <= 0 then
				local ladder = s.ItemCatalog.AxeLadder()
				axe = ladder[#ladder]
			end
			local hp, why, feller
			for _ = 1, times or 1 do
				hp, why, feller = s.Trees.ApplyChop(p, rec.uid, axe)
				if hp == nil or hp <= 0 then
					break
				end
			end
			return hp, why, feller
		end

		-- Timers waiting, of this many seconds.
		function s.pending(seconds)
			local n = 0
			for _, d in ipairs(s.delays) do
				if d.seconds == seconds then
					n += 1
				end
			end
			return n
		end

		function s.trunk(rec)
			return rec.model.PrimaryPart
		end
		return s
	end

	t.test("the felling counts for whoever chopped the most, not the last swing", function()
		local s = setup()
		local rec = s.tree("oak")
		local a = s.player(1)
		local b = s.player(2, Vector3.new(-4, 0, 0))
		local felledFor, multiplierFor
		s.Trees.OnFelled = function(p)
			felledFor = p
		end
		s.Trees.LogMultiplier = function(p)
			multiplierFor = p
			return 1
		end
		local hits = math.ceil(rec.maxHp / s.ItemCatalog.GetAxe("RustyAxe").damage)
		local hp, _, feller = s.chop(a, rec, hits - 1)
		t.ok(hp > 0 and feller == nil, "still standing")
		hp, _, feller = s.chop(b, rec)
		t.eq(hp, 0)
		t.eq(feller, a, "Ada chopped the most")
		t.ok(rec.model:GetAttribute("FallDir").X > 0, "it falls away from Bo, who swung last")
		s.run(s.TreeLogic.FallTime + 1)
		t.eq(felledFor, a)
		t.eq(multiplierFor, a)
		local logs = s.map.Logs:GetChildren()
		t.eq(#logs, 3)
		for _, model in ipairs(logs) do
			t.eq(s.Trees.GetLog(model:GetAttribute("Uid")).ownerId, 1, "Ada's pickup grace")
		end
	end)

	t.test("a felling goes to the swinger when the top chopper has left", function()
		local s = setup()
		local rec = s.tree("oak")
		local a = s.player(1)
		local b = s.player(2)
		s.chop(a, rec, 3)
		s.byId[1] = nil -- Ada left
		local _, _, feller = s.chop(b, rec, 10)
		t.eq(feller, b)
	end)

	t.test("logs laid uphill land on the slope, not inside it", function()
		local s = setup()
		-- A stump far below the ground around it: every log spot is uphill.
		local rec = s.tree("oak", Vector3.new(0, -60, 0))
		local a = s.player(1, Vector3.new(4, -60, 0))
		s.chop(a, rec, 20)
		s.run(s.TreeLogic.FallTime + 1)
		t.eq(#s.rays, 3)
		for _, ray in ipairs(s.rays) do
			local h = s.TerrainGen.HeightAt(ray.origin.X, ray.origin.Z)
			t.ok(math.abs(ray.origin.Y - (h + 10)) < 1e-3, "starts above the terrain at the log")
			t.ok(ray.origin.Y + ray.direction.Y <= -90 + 1e-3, "and searches down past the stump")
		end
		for _, model in ipairs(s.map.Logs:GetChildren()) do
			local p = model.PrimaryPart.CFrame.Position
			local h = s.TerrainGen.HeightAt(p.X, p.Z)
			t.ok(math.abs(p.Y - (h + s.Trees.LogDiameter / 2)) < 1e-3, "resting on the ground") -- Vector3 is 32-bit
		end
	end)

	t.test("a tree regrowing into a parked truck stands as a ghost until the truck moves", function()
		local s = setup()
		local rec = s.tree("oak")
		local a = s.player(1)
		s.chop(a, rec, 20)
		s.run(s.TreeLogic.FallTime + 1) -- landed
		t.ok(s.Trees.RegrowsIn(rec.uid) == rec.def.respawnSec, "regrows on its own in 45 s")
		s.clock += 10
		t.eq(s.Trees.RegrowsIn(rec.uid), rec.def.respawnSec - 10)
		s.trucks = { roblox.Instance.new("Model") }
		s.blocked = true
		s.run(rec.def.respawnSec) -- regrows
		t.ok(rec.alive and not rec.felled, "standing (and choppable)")
		t.eq(s.trunk(rec).Transparency, 0, "seen")
		t.eq(s.trunk(rec).CanCollide, false, "but not solid: the truck is in it")
		t.ok(rec.ghost)
		t.eq(s.Trees.RegrowsIn(rec.uid), nil)
		t.eq(s.pending(2), 1, "it checks again")
		s.run(2) -- still there
		t.eq(s.trunk(rec).CanCollide, false)
		t.eq(s.pending(2), 1)
		s.blocked = false
		s.run(2)
		t.eq(s.trunk(rec).CanCollide, true, "solid once the truck has gone")
		t.ok(not rec.ghost)
		t.eq(s.pending(2), 0)
	end)

	t.test("a held stump (Murph's plant step) outlasts the wood's regrowth, then the tree comes back", function()
		local s = setup()
		local rec = s.tree("oak")
		local a = s.player(1)
		local asked
		s.Trees.StumpHold = function(p)
			asked = p
			return 240
		end
		s.chop(a, rec, 20)
		t.eq(asked, a, "asked about the feller")
		s.run(s.TreeLogic.FallTime + 1) -- landed
		t.ok(rec.stump ~= nil)
		t.eq(s.Trees.RegrowsIn(rec.uid), 240)
		s.clock += rec.def.respawnSec
		s.run(rec.def.respawnSec) -- the oak's own 45 s are up
		t.ok(rec.felled and rec.stump ~= nil, "still a stump")
		t.eq(s.pending(240 - rec.def.respawnSec), 1, "it waits out the rest of the hold")
		s.clock += 120 - rec.def.respawnSec
		t.ok(rec.felled and rec.stump ~= nil and rec.stump.Parent ~= nil, "two minutes on, the stump is still there")
		t.eq(s.Trees.RegrowsIn(rec.uid), 120)
		s.clock += 120
		s.run()
		t.ok(rec.alive and not rec.felled, "the hold over, it regrows on its own")
		t.eq(rec.stump, nil)
		t.eq(s.Trees.RegrowsIn(rec.uid), nil)
		t.eq(#s.delays, 0)
	end)

	t.test("no hold, or a hook that fails: the usual regrowth", function()
		local s = setup()
		local rec = s.tree("oak")
		local a = s.player(1)
		s.Trees.StumpHold = function()
			return 0
		end
		s.chop(a, rec, 20)
		s.run(s.TreeLogic.FallTime + 1)
		t.eq(s.Trees.RegrowsIn(rec.uid), rec.def.respawnSec)
		s.run(rec.def.respawnSec)
		t.ok(rec.alive and not rec.felled, "back after 45 s")
		s.Trees.StumpHold = function()
			error("no profile")
		end
		s.chop(a, rec, 20)
		t.eq(s.Trees.RegrowsIn(rec.uid), rec.def.respawnSec)
		s.run()
		t.ok(rec.alive and not rec.felled)
	end)

	t.test("HoldRegrow: at most 4 minutes from now, never sooner, not for standing trees or Elders", function()
		local s = setup()
		local rec = s.tree("oak")
		local a = s.player(1)
		s.Trees.HoldRegrow(rec.uid, 100) -- standing: nothing to hold
		s.chop(a, rec, 20)
		t.eq(s.Trees.RegrowsIn(rec.uid), 45)
		s.Trees.HoldRegrow(rec.uid, 10)
		t.eq(s.Trees.RegrowsIn(rec.uid), 45, "a short hold never brings it back sooner")
		s.Trees.HoldRegrow(rec.uid, 10000)
		t.eq(s.Trees.RegrowsIn(rec.uid), 240, "capped")
		s.Trees.HoldRegrow(rec.uid, 0 / 0)
		t.eq(s.Trees.RegrowsIn(rec.uid), 240)
		s.Trees.HoldRegrow("no-such-tree", 60)
		local elder = s.Trees.GetTree(s.Trees
			.SpawnTree("oak", CFrame.new(40, 0, 0), {
				seed = 3,
				size = s.TreeLogic.Sizes[2],
				temporary = true,
			})
			:GetAttribute("Uid"))
		a.root.Position = Vector3.new(44, 0, 0)
		s.chop(a, elder, 40)
		t.ok(elder.felled, "the Elder is down")
		s.Trees.HoldRegrow(elder.uid, 100)
		t.eq(s.Trees.RegrowsIn(elder.uid), nil, "an Elder's stump goes as usual")
	end)

	t.test("a held stump planted early stands at once; the hold's timer leaves the new tree alone", function()
		local s = setup()
		local rec = s.tree("oak")
		local a = s.player(1)
		s.Trees.StumpHold = function()
			return 240
		end
		s.chop(a, rec, 20)
		s.run(s.TreeLogic.FallTime + 1)
		s.clock += 120
		s.Trees.Regrow(rec.uid, 1) -- a Heartseed sprouted
		t.ok(rec.alive and not rec.felled)
		t.eq(rec.planterId, 1)
		s.clock += 200
		s.run()
		t.ok(rec.alive and not rec.felled, "still standing")
		t.eq(rec.planterId, 1, "and still the planter's")
		t.eq(#s.delays, 0)
	end)

	t.test("felling a ghost ends its wait; with nothing around, no query at all", function()
		local s = setup()
		local rec = s.tree("oak")
		t.eq(s.queries, 0, "no players or trucks: nothing to check")
		local a = s.player(1)
		s.chop(a, rec, 20)
		s.run(s.TreeLogic.FallTime + 1)
		s.blocked = true
		s.run(rec.def.respawnSec)
		t.ok(rec.ghost)
		s.chop(a, rec, 20) -- felled again while a ghost
		t.ok(not rec.ghost)
		s.blocked = false
		s.run(2)
		t.ok(rec.felled)
		t.eq(s.trunk(rec).CanCollide, false, "the retry didn't make the felled tree solid")
	end)

	t.test("the Phantom Grove by day: trees and stumps hidden and walk-through, solid again at night", function()
		local s = setup()
		local standing = s.tree("phantomwood", Vector3.new(0, 0, 0))
		local cut = s.tree("phantomwood", Vector3.new(40, 0, 0))
		local falling = s.tree("phantomwood", Vector3.new(80, 0, 0))
		local a = s.player(1, Vector3.new(44, 0, 0))
		s.chop(a, cut, 40)
		s.run(s.TreeLogic.FallTime + 1)
		local stump = cut.stump.PrimaryPart
		t.eq(stump.CanCollide, true)
		a.root.Position = Vector3.new(84, 0, 0)
		s.chop(a, falling, 40)
		s.Trees.SetBiomeDormant("grove", true) -- dawn, mid-fall
		t.eq(stump.Transparency, 1)
		t.eq(stump.CanCollide, false, "no invisible stump to trip over")
		t.eq(s.trunk(standing).CanCollide, false)
		s.run(s.TreeLogic.FallTime + 1) -- the falling one lands by day
		local late = falling.stump.PrimaryPart
		t.eq(late.Transparency, 1, "its stump is hidden with the grove")
		t.eq(late.CanCollide, false)
		-- Dusk: a truck parked by day where a tree stands.
		s.trucks = { roblox.Instance.new("Model") }
		s.blocked = true
		s.Trees.SetBiomeDormant("grove", false)
		t.eq(stump.Transparency, 0)
		t.eq(stump.CanCollide, false, "stumps are ghosts too while something's in the way")
		t.eq(late.CanCollide, false)
		t.eq(cut.stump:FindFirstChild("StumpTop").CanCollide, false, "decor stays decor")
		t.ok(standing.alive)
		t.eq(s.trunk(standing).Transparency, 0)
		t.eq(s.trunk(standing).CanCollide, false, "a ghost until the truck goes")
		s.blocked = false
		s.run(2)
		t.eq(s.trunk(standing).CanCollide, true)
		t.eq(stump.CanCollide, true, "solid once the spot is clear")
		t.eq(late.CanCollide, true)
		t.eq(cut.stump:FindFirstChild("StumpTop").CanCollide, false, "decor still decor")
	end)

	t.test("a half-chopped Phantom tree is whole tomorrow night, its chopping forgotten", function()
		local s = setup()
		local rec = s.tree("phantomwood")
		local a = s.player(1)
		s.chop(a, rec, 2)
		t.ok(rec.damageBy[1] > 0)
		s.Trees.SetBiomeDormant("grove", true)
		t.eq(rec.hp, rec.maxHp)
		t.eq(rec.damageBy, {})
	end)

	t.test("a load left behind stays its owner's longer and lies longer", function()
		local s = setup()
		local GameConfig = t.shared("GameConfig")
		local oak = t.shared("WoodData").Get("oak")
		local _, plainUid = s.Trees.SpawnLog(oak, CFrame.new(0, 1, 0), 7)
		local plain = s.Trees.GetLog(plainUid)
		t.eq(plain.graceUntil, nil, "a felled log keeps the short grace")
		t.eq(s.pending(GameConfig.LogDespawnSec), 1)
		local _, leftUid = s.Trees.SpawnLog(oak, CFrame.new(0, 1, 6), 7, {
			graceSec = GameConfig.LeftLoadGraceSec,
			despawnSec = GameConfig.LeftLoadDespawnSec,
		})
		local left = s.Trees.GetLog(leftUid)
		t.ok(left.graceUntil and left.graceUntil >= os.time() + GameConfig.LeftLoadGraceSec - 1, "the long window")
		t.eq(s.pending(GameConfig.LeftLoadDespawnSec), 1, "and the long life")
		t.ok(GameConfig.LeftLoadGraceSec > GameConfig.PickupGraceSec)
	end)

	t.test("left-behind logs still lying out are taken for the save; others aren't", function()
		local s = setup()
		local oak = t.shared("WoodData").Get("oak")
		local _, leftUid = s.Trees.SpawnLog(oak, CFrame.new(10, 2, 20), 7)
		local left = s.Trees.GetLog(leftUid)
		left.tags.leftBehind = true
		left.tags.figure = "curly"
		left.value = 6
		s.Trees.SpawnLog(oak, CFrame.new(0, 1, 0), 7) -- an ordinary felled log
		local _, theirsUid = s.Trees.SpawnLog(oak, CFrame.new(5, 1, 5), 8)
		s.Trees.GetLog(theirsUid).tags.leftBehind = true -- someone else's
		local taken = s.Trees.TakeLeftBehind(7)
		t.eq(#taken, 1)
		t.eq(taken[1].woodId, "oak")
		t.eq(taken[1].value, 6)
		t.eq(taken[1].figure, "curly")
		t.eq({ taken[1].x, taken[1].z }, { 10, 20 })
		t.eq(s.Trees.GetLog(leftUid), nil, "gone from the world")
		t.ok(s.Trees.GetLog(theirsUid) ~= nil)
		t.eq(#s.Trees.TakeLeftBehind(7), 0, "taken once")
	end)
end
