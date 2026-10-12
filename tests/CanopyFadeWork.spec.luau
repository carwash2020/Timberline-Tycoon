--!nocheck
-- CanopyFade's look at forest size (client audit leftover, 11 October 2026):
-- it used to ask every tree under TimberlineMap.Trees for its HomePivot ten
-- times a second. With the grid (Shared/TreeIndex) a steady look asks only
-- the few trees near the lines of sight, and a flood of new trees is learned
-- a budget at a time. Counted in attribute reads (Lune work counters).
return function(t)
	local roblox = t.roblox
	local Vector3, CFrame = roblox.Vector3, roblox.CFrame

	local function stage(count)
		local reads = 0
		local trees = {}
		local folder = {
			GetChildren = function()
				return trees
			end,
		}
		for i = 1, count do
			local x = ((i * 37) % 1000) * 2.2 - 1100
			local z = ((i * 91) % 1000) * 2.2 - 1100
			local tree = {}
			function tree.IsA(_, kind)
				return kind == "Model"
			end
			function tree.GetAttribute(_, name)
				reads += 1
				if name == "HomePivot" then
					return CFrame.new(x, 0, z)
				end
				return nil
			end
			tree.Parent = folder
			trees[i] = tree
		end
		local camera = { CFrame = CFrame.new(0, 20, 20) }
		local function part(at)
			return {
				CFrame = CFrame.new(at),
				IsA = function()
					return true
				end,
			}
		end
		local character = {}
		local parts = { Head = part(Vector3.new(0, 3, 0)), HumanoidRootPart = part(Vector3.new(0, 1.5, 0)) }
		function character.FindFirstChild(_, name)
			return parts[name]
		end
		local map = {
			FindFirstChild = function()
				return folder
			end,
		}
		local heartbeat
		local clock = 0
		local workspace = {
			CurrentCamera = camera,
			FindFirstChild = function()
				return map
			end,
			Raycast = function()
				return nil
			end,
			GetPartBoundsInRadius = function()
				return {}
			end,
		}
		local loader = t.loader({
			services = {
				Players = { LocalPlayer = { Character = character } },
				RunService = {
					Heartbeat = {
						Connect = function(_, fn)
							heartbeat = fn
							return { Disconnect = function() end }
						end,
					},
				},
			},
			mocks = { TreeFX = {
				IsBusy = function()
					return false
				end,
			} },
			globals = {
				workspace = workspace,
				os = {
					clock = function()
						return clock
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
		local CanopyFade = loader:load("StarterPlayer/StarterPlayerScripts/CanopyFade")
		CanopyFade.Start()
		return {
			look = function()
				clock += 0.1
				heartbeat(0.1)
			end,
			reads = function()
				return reads
			end,
			trees = trees,
			folder = folder,
		}
	end

	t.test("a steady look at 1,500 trees reads only the trees near the line, not the forest", function()
		local s = stage(1500)
		-- Warm-up: the index learns the forest 150 trees a look.
		local firstReads
		for i = 1, 11 do
			local before = s.reads()
			s.look()
			local spent = s.reads() - before
			if i == 1 then
				firstReads = spent
			end
			t.ok(spent <= 150 + 60, "look " .. i .. " read " .. spent)
		end
		t.ok(firstReads >= 100, "the first look learns trees: " .. firstReads)
		local before = s.reads()
		for _ = 1, 10 do
			s.look()
		end
		local perLook = (s.reads() - before) / 10
		print(string.format("canopy look with 1500 trees: %.1f attribute reads a look (a scan read 1500)", perLook))
		t.ok(perLook < 30, "steady look reads " .. perLook)
	end)

	t.test("a tree that streams in is found within a look, and one that leaves is dropped", function()
		local s = stage(50)
		for _ = 1, 3 do
			s.look()
		end
		local before = s.reads()
		s.look()
		local steady = s.reads() - before
		t.ok(steady < 30)
		-- Remove all but one: a look afterwards reads nothing for the gone ones.
		for i = #s.trees, 2, -1 do
			table.remove(s.trees, i)
		end
		s.look()
		before = s.reads()
		s.look()
		t.ok(s.reads() - before <= 3, "only what is left is asked: " .. (s.reads() - before))
	end)
end
