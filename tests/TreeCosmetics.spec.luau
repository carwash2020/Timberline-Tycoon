--!nocheck
-- TreeCosmetics (StarterPlayerScripts/TreeCosmetics): the seasonal tint and the
-- high tier's mote, as the real module runs it against fake trees.
--   * On a phone (low) there is nothing to add, and nothing to clear: the pass
--     used to walk every streamed-in tree's descendants (GetDescendants) on
--     every pass to look for accents that were never made;
--   * a pass dresses at most PerPass trees (a season change used to repaint
--     every tree in the world in one frame), and the rest follow on the next;
--   * trees and parts that stream out are not held for good (weak tables).
return function(t)
	local QualityBudgets = t.shared("QualityBudgets")
	local roblox = t.roblox
	local Color3, CFrame, Enum = roblox.Color3, roblox.CFrame, roblox.Enum

	-- A fake tree: the few calls the module makes, each counted.
	local function fakeTree(woodId, withCrown)
		local tree = { descendants = 0, attrs = { WoodId = woodId }, children = {} }
		local crown = {
			Name = "Leaves",
			Color = Color3.new(0.2, 0.5, 0.2),
			Material = Enum.Material.Grass,
			IsA = function(_, class)
				return class == "BasePart" or class == "Instance"
			end,
		}
		function tree:IsA(class)
			return class == "Model" or class == "Instance"
		end
		function tree:GetAttribute(name)
			return self.attrs[name]
		end
		function tree:GetDescendants()
			self.descendants += 1
			return if withCrown then { crown } else {}
		end
		function tree:FindFirstChild()
			return nil
		end
		function tree:GetPivot()
			return CFrame.new()
		end
		tree.crown = crown
		return tree
	end

	local function module(tier)
		local heartbeat = {}
		local tagged = {}
		local loader = t.loader({
			services = {
				CollectionService = {
					GetTagged = function()
						return tagged
					end,
				},
				Lighting = { ClockTime = 12 },
				RunService = {
					Heartbeat = {
						Connect = function(_, fn)
							table.insert(heartbeat, fn)
						end,
					},
				},
			},
			mocks = {
				Quality = {
					Budget = function()
						return QualityBudgets.For(tier)
					end,
				},
			},
		})
		local TreeCosmetics = loader:load("StarterPlayer/StarterPlayerScripts/TreeCosmetics")
		local TreeArt = loader:load("ReplicatedStorage/Shared/Art/TreeArt")
		return TreeCosmetics, TreeArt, tagged, heartbeat
	end

	t.test("low (phones): a pass never walks a tree's descendants, however many passes", function()
		local TreeCosmetics, TreeArt, tagged = module("low")
		for i = 1, 300 do
			table.insert(tagged, fakeTree(if i % 2 == 0 then "oak" else "maple", true))
		end
		local look = TreeArt.Cosmetics("low")
		for _ = 1, 20 do
			t.eq(TreeCosmetics.Pass(tagged, look, 2), 0, "nothing to dress on low")
		end
		local walked = 0
		for _, tree in ipairs(tagged) do
			walked += tree.descendants
		end
		t.eq(walked, 0, "no GetDescendants on a low tier tree")
	end)

	t.test("high: a pass dresses at most PerPass trees, and the next passes finish the rest", function()
		local TreeCosmetics, TreeArt, tagged = module("high")
		local count = TreeCosmetics.PerPass * 3 + 5
		for _ = 1, count do
			table.insert(tagged, fakeTree("oak", true))
		end
		local look = TreeArt.Cosmetics("high")
		local first = TreeCosmetics.Pass(tagged, look, 2)
		t.eq(first, TreeCosmetics.PerPass, "one pass: at most PerPass trees")
		local painted = 0
		for _, tree in ipairs(tagged) do
			if tree.crown.Color ~= Color3.new(0.2, 0.5, 0.2) then
				painted += 1
			end
		end
		t.ok(painted <= TreeCosmetics.PerPass, painted .. " painted in one pass")
		local passes = 1
		while TreeCosmetics.Pass(tagged, look, 2) > 0 and passes < 50 do
			passes += 1
		end
		t.ok(passes <= 6, "all " .. count .. " trees are dressed in " .. passes .. " passes")
		t.eq(TreeCosmetics.Tracked(), count, "every tree was painted")
		t.eq(TreeCosmetics.Pass(tagged, look, 2), 0, "and a settled pass does nothing")
	end)

	t.test("a season change repaints gradually, not in one frame", function()
		local TreeCosmetics, TreeArt, tagged = module("medium")
		for _ = 1, TreeCosmetics.PerPass * 2 do
			table.insert(tagged, fakeTree("maple", true))
		end
		local look = TreeArt.Cosmetics("medium")
		while TreeCosmetics.Pass(tagged, look, 1) > 0 do
		end
		local worked = TreeCosmetics.Pass(tagged, look, 3)
		t.eq(worked, TreeCosmetics.PerPass, "a new season: one pass repaints PerPass trees")
	end)

	t.test("trees that stream out are not held: the tables are weak", function()
		local TreeCosmetics, TreeArt, tagged = module("high")
		for _ = 1, 40 do
			table.insert(tagged, fakeTree("oak", true))
		end
		local look = TreeArt.Cosmetics("high")
		while TreeCosmetics.Pass(tagged, look, 1) > 0 do
		end
		t.eq(TreeCosmetics.Tracked(), 40)
		table.clear(tagged) -- they streamed out: nothing else refers to them
		-- Lune does not allow collectgarbage("collect"): make garbage until the
		-- collector has run its cycle. The bound is generous: after a big spec run
		-- the heap is large and one cycle takes many allocations.
		for _ = 1, 5000 do
			if TreeCosmetics.Tracked() == 0 then
				break
			end
			local junk = {}
			for i = 1, 20000 do
				junk[i] = { i }
			end
		end
		t.eq(TreeCosmetics.Tracked(), 0, "a tree that has left the world is not kept")
	end)

	t.test("high: a tree with no crown stops being searched after a few passes", function()
		local TreeCosmetics, TreeArt, tagged = module("high")
		local stump = fakeTree("maple", false)
		table.insert(tagged, stump)
		local look = TreeArt.Cosmetics("high")
		for _ = 1, 40 do
			TreeCosmetics.Pass(tagged, look, 1)
		end
		t.ok(
			stump.descendants <= 12,
			"a stump's descendants were walked " .. stump.descendants .. " times in 40 passes"
		)
	end)
end
