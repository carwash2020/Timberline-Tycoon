--!nocheck
-- TownBoardService: builds the board at the plan's anchor on the ground,
-- persistent, and redraws from LeaderboardService's cache when it is read
-- again. It never reads a DataStore (the mock LeaderboardService has only
-- Top, Failed and OnRefresh, so any other call would error).
return function(t)
	local Instance = t.roblox.Instance

	local function boot(options)
		options = options or {}
		local state = { rows = options.rows, failed = options.failed or false }
		local refreshers = {}
		local calls = { top = 0, failed = 0 }
		local loader = t.loader({
			mocks = {
				LeaderboardService = {
					Top = function()
						calls.top += 1
						return state.rows
					end,
					Failed = function()
						calls.failed += 1
						return state.failed
					end,
					OnRefresh = function(fn)
						table.insert(refreshers, fn)
					end,
				},
			},
			globals = {
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
					delay = function() end,
					wait = function() end,
				},
			},
		})
		local Service = loader:server("TownBoardService")
		local parent = Instance.new("Folder")
		Service.Init({
			parent = parent,
			ground = options.ground,
		})
		return {
			Service = Service,
			parent = parent,
			state = state,
			refreshers = refreshers,
			calls = calls,
			text = function(name)
				local board = Service.Board():FindFirstChild("Board")
				return board:FindFirstChild("Face"):FindFirstChild(name).Text
			end,
		}
	end

	t.test("the board stands at the plan's anchor, persistent, front to the street", function()
		local env = boot()
		local model = env.Service.Board()
		t.ok(model ~= nil and model.Parent == env.parent)
		t.eq(model.ModelStreamingMode, t.roblox.Enum.ModelStreamingMode.Persistent)
		local board = model:FindFirstChild("Board")
		t.ok(math.abs(board.CFrame.Position.X - -50) < 0.01)
		t.ok(math.abs(board.CFrame.Position.Z - 92) < 0.01)
		t.ok(board.CFrame.LookVector.Z < -0.9, "its front faces -Z, onto MainStreet")
		local post = model:FindFirstChild("Post")
		t.ok(post.CFrame.Position.Y - post.Size.Y / 2 < 0, "the posts reach into the ground at y = 0")
	end)

	t.test("on a rise the whole board stands up to the highest ground under it", function()
		local env = boot({
			ground = function(x)
				return if x > -50 then 3 else 1
			end,
		})
		local model = env.Service.Board()
		local lowest = math.huge
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "Post" then
				lowest = math.min(lowest, d.CFrame.Position.Y - d.Size.Y / 2)
			end
		end
		-- The plaque hangs 0.4 off the ground, so its foot is at 3.4 on the 3-stud rise.
		t.ok(math.abs(lowest - 3.4) < 0.01, "the board is lifted by the high side: " .. lowest)
	end)

	t.test("a terrain lookup that errors does not stop the board", function()
		local env = boot({
			ground = function()
				error("no terrain yet")
			end,
		})
		t.ok(env.Service.Board() ~= nil)
	end)

	t.test("while the cache is loading it says so, and failed says couldn't load", function()
		local env = boot({ rows = nil })
		t.eq(env.text("Message"), "Loading the board...")
		env.state.failed = true
		env.refreshers[1]()
		t.eq(env.text("Message"), "The board couldn't load. Try again soon.")
	end)

	t.test("an empty list shows the empty line", function()
		local env = boot({ rows = {} })
		t.eq(env.text("Message"), "No one is on the board yet. Turn it on in Settings, Leaderboard.")
		t.eq(env.text("Name1"), "")
	end)

	t.test("each refresh redraws the top ten from the cache and does nothing else", function()
		local env = boot({ rows = { { rank = 1, name = "Ann", score = 5000 } } })
		t.eq(env.text("Name1"), "Ann")
		t.eq(env.text("Cash1"), "$5,000 earned")
		t.eq(env.text("Name2"), "")
		t.eq(#env.refreshers, 1, "it listens to the existing read, no read of its own")
		env.state.rows = {
			{ rank = 1, name = "Bo", score = 9000 },
			{ rank = 2, name = "Ann", score = 5000 },
		}
		local before = env.calls.top
		env.refreshers[1]()
		t.eq(env.calls.top, before + 1, "one cache look per refresh")
		t.eq(env.text("Name1"), "Bo")
		t.eq(env.text("Name2"), "Ann")
		t.eq(env.text("Rank2"), "2")
		t.eq(env.text("Message"), "")
		-- Nothing changed: nothing is rewritten.
		env.Service.Board():FindFirstChild("Board"):FindFirstChild("Face"):FindFirstChild("Name1").Text = "kept"
		env.refreshers[1]()
		t.eq(env.text("Name1"), "kept", "an unchanged list is not redrawn")
	end)

	t.test("a second Init builds no second board", function()
		local env = boot()
		local first = env.Service.Board()
		env.Service.Init({ parent = env.parent })
		t.eq(env.Service.Board(), first)
		local boards = 0
		for _, child in ipairs(env.parent:GetChildren()) do
			if child.Name == "TownBoard" then
				boards += 1
			end
		end
		t.eq(boards, 1)
	end)
end
