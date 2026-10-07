--!nocheck
-- Gamepad select (R2, screen centre) and a mouse click hit the same piece.
return function(t)
	local Enum = t.roblox.Enum
	local Instance = t.roblox.Instance
	local Vector2 = t.roblox.Vector2
	local Vector3 = t.roblox.Vector3
	local fs = require("@lune/fs")

	local model = Instance.new("Model")
	model:AddTag("PlacedItem")
	model:SetAttribute("Uid", "piece-1")
	model:SetAttribute("Kit", true)
	model:SetAttribute("FillUnits", 0)
	model:SetAttribute("OwnerId", 7)
	local part = Instance.new("Part")
	part.Parent = model

	-- A glass wall in front of things: x 150 has the piece behind the glass, x 160 only the glass.
	local glassModel = Instance.new("Model")
	glassModel:AddTag("PlacedItem")
	glassModel:SetAttribute("Uid", "glass-1")
	glassModel:SetAttribute("OwnerId", 7)
	local pane = Instance.new("Part")
	pane:SetAttribute("Role", "Glass")
	pane.Parent = glassModel

	local seen = {}
	local function raycast(_, origin, _direction, params)
		table.insert(seen, tostring(typeof(origin)) .. ":" .. tostring(origin))
		if origin and origin.X == 100 and origin.Y == 50 then
			return { Instance = part }
		end
		if origin and (origin.X == 150 or origin.X == 160) and origin.Y == 50 then
			local skipped = false
			for _, inst in ipairs(params and params.FilterDescendantsInstances or {}) do
				if inst == pane then
					skipped = true
				end
			end
			if not skipped then
				return { Instance = pane }
			end
			return if origin.X == 150 then { Instance = part } else nil
		end
		return nil
	end

	local camera = {
		ViewportSize = Vector2.new(200, 100),
		ViewportPointToRay = function(_, x, y)
			return { Origin = Vector3.new(x, y, 5), Direction = Vector3.new(0, -1, 0) }
		end,
	}

	local player = { UserId = 7 }
	local loader = t.loader({
		services = {
			Players = { LocalPlayer = player },
			GuiService = {
				IsTenFootInterface = function()
					return false
				end,
				TopbarInset = t.roblox.Rect.new(0, 0, 0, 0),
				GetGuiInset = function()
					return Vector2.zero, Vector2.zero
				end,
			},
			UserInputService = { TouchEnabled = false, KeyboardEnabled = true },
			TextChatService = {},
			ContextActionService = {},
			RunService = {},
		},
		globals = {
			workspace = {
				Raycast = raycast,
				CurrentCamera = camera,
			},
			RaycastParams = {
				new = function()
					return {}
				end,
			},
		},
		mocks = {
			HUD = { Toast = function() end },
			BlueprintPlacer = {
				Active = function()
					return false
				end,
			},
		},
	})
	local Tools = loader:load("StarterPlayer/StarterPlayerScripts/BuilderTools")

	t.test("the centre ray and a click on that point select the same piece", function()
		local cx, cy = Tools.Center(camera.ViewportSize)
		t.eq(cx, 100)
		t.eq(cy, 50)
		local aimed = Tools.Aim(camera, cx, cy)
		if aimed ~= model then
			error("aim " .. tostring(aimed) .. " rays " .. table.concat(seen, " | "))
		end
		t.eq(aimed, model)
		t.eq(Tools.Aim(camera, 100, 50), Tools.Aim(camera, cx, cy))
		t.eq(Tools.Aim(camera, 1, 1), nil)
		t.eq(Tools.OnSelect("BuilderSelect", Enum.UserInputState.Begin), Enum.ContextActionResult.Sink)
		if Tools.PrimarySelected() ~= model then
			error("selected " .. tostring(Tools.PrimarySelected()) .. " rays " .. table.concat(seen, " | "))
		end
		t.eq(Tools.PrimarySelected(), model)
		t.eq(Tools.SelectedCount(), 1)
		camera.ViewportSize = Vector2.new(10, 10)
		t.eq(Tools.OnSelect("BuilderSelect", Enum.UserInputState.Begin), Enum.ContextActionResult.Pass)
		t.eq(Tools.SelectedCount(), 1, "a miss does not change the selection")
		camera.ViewportSize = Vector2.new(200, 100)
		local char = Instance.new("Model")
		local tool = Instance.new("Tool")
		tool.Parent = char
		player.Character = char
		t.eq(Tools.OnSelect("BuilderSelect", Enum.UserInputState.Begin), Enum.ContextActionResult.Pass)
		t.eq(Tools.PrimarySelected(), model, "a tool in hand does not select")
		local src = fs.readFile("src/StarterPlayer/StarterPlayerScripts/BuilderTools.luau")
		t.ok(string.find(src, "Enum.ScreenInsets.CoreUISafeInsets", 1, true))
		t.ok(string.find(src, "UITheme.Bottom()", 1, true))
		t.ok(string.find(src, "BuilderBar.Layout", 1, true))
		t.ok(string.find(src, "Enum.KeyCode.ButtonR2", 1, true))
	end)

	t.test("glass does not block the aim: the piece behind it is aimed at, else the glass wall itself", function()
		player.Character = nil
		t.eq(Tools.Aim(camera, 150, 50), model, "a ghost wall seen through a glass wall")
		t.eq(Tools.Aim(camera, 160, 50), glassModel, "nothing behind it: the glass wall")
	end)

	t.test("a 58 px top inset keeps the build bar's on-screen top at 141 on a 667x375 phone", function()
		local roblox = t.roblox
		local watched = {}
		-- Later specs fire the same ScreenGui signal. The method can only
		-- be registered once, so the events live on this shared table.
		_G.__screenGuiSignals = watched
		pcall(roblox.implementProperty, "TextButton", "Activated", function()
			return {
				Connect = function()
					return { Disconnect = function() end }
				end,
			}
		end)
		pcall(roblox.implementMethod, "ScreenGui", "GetPropertyChangedSignal", function(self, prop)
			local listeners = {}
			local ev = {
				Connect = function(_, fn)
					table.insert(listeners, fn)
					return { Disconnect = function() end }
				end,
				Fire = function()
					for _, fn in ipairs(listeners) do
						fn()
					end
				end,
			}
			watched[self] = watched[self] or {}
			watched[self][prop] = ev
			return ev
		end)
		local function signal()
			return {
				Connect = function()
					return { Disconnect = function() end }
				end,
			}
		end
		local phoneCamera = {
			ViewportSize = Vector2.new(667, 375),
			GetPropertyChangedSignal = function()
				return signal()
			end,
			ViewportPointToRay = function()
				return { Origin = Vector3.zero, Direction = Vector3.new(0, -1, 0) }
			end,
		}
		pcall(roblox.implementProperty, "Folder", "Character", function()
			return nil
		end)
		local phonePlayer = Instance.new("Folder")
		local pg = Instance.new("Folder")
		pg.Name = "PlayerGui"
		pg.Parent = phonePlayer
		local layoutLoader = t.loader({
			services = {
				Players = { LocalPlayer = phonePlayer },
				GuiService = {
					IsTenFootInterface = function()
						return false
					end,
					TopbarInset = t.roblox.Rect.new(0, 0, 0, 0),
					GetGuiInset = function()
						return Vector2.zero, Vector2.zero
					end,
				},
				UserInputService = {
					TouchEnabled = true,
					KeyboardEnabled = false,
					InputBegan = signal(),
					InputChanged = signal(),
					TouchTapInWorld = signal(),
				},
				TextChatService = {},
				ContextActionService = { BindActionAtPriority = function() end },
				RunService = { RenderStepped = signal() },
				CollectionService = {
					GetInstanceRemovedSignal = function()
						return signal()
					end,
				},
			},
			globals = {
				workspace = {
					CurrentCamera = phoneCamera,
					Raycast = function()
						return nil
					end,
					GetPropertyChangedSignal = function()
						return signal()
					end,
				},
				RaycastParams = {
					new = function()
						return {}
					end,
				},
			},
			mocks = {
				HUD = { Toast = function() end },
				BlueprintPlacer = {
					Active = function()
						return false
					end,
				},
			},
		})
		local PhoneTools = layoutLoader:load("StarterPlayer/StarterPlayerScripts/BuilderTools")
		PhoneTools.Start()
		local gui = pg:FindFirstChild("BuilderTools")
		t.ok(gui, "the bar's screen")
		local bar = gui:FindFirstChild("BuildBar")
		t.ok(bar, "the cluster")
		local inset = 58
		gui.AbsolutePosition = Vector2.new(0, inset)
		gui.AbsoluteSize = Vector2.new(667, 375 - inset)
		watched[gui].AbsoluteSize:Fire()
		t.eq(inset + bar.Position.Y.Offset, 141)
	end)

	t.test("the R2 select bind exists only while no tool is held", function()
		local binds = {}
		local function signal()
			return {
				Connect = function()
					return { Disconnect = function() end }
				end,
			}
		end
		for _, event in ipairs({ "ChildAdded", "ChildRemoved" }) do
			pcall(t.roblox.implementProperty, "Model", event, signal)
		end
		local char = Instance.new("Model")
		local owner = { UserId = 7, Character = char, CharacterAdded = signal() }
		local l = t.loader({
			services = {
				Players = { LocalPlayer = owner },
				GuiService = {
					IsTenFootInterface = function()
						return false
					end,
					TopbarInset = t.roblox.Rect.new(0, 0, 0, 0),
					GetGuiInset = function()
						return Vector2.zero, Vector2.zero
					end,
				},
				UserInputService = { TouchEnabled = false, KeyboardEnabled = true },
				TextChatService = {},
				ContextActionService = {
					BindActionAtPriority = function(_, name)
						binds[name] = true
					end,
					UnbindAction = function(_, name)
						binds[name] = nil
					end,
				},
				RunService = {},
			},
			globals = { workspace = { CurrentCamera = camera } },
			mocks = {
				HUD = { Toast = function() end },
				BlueprintPlacer = {
					Active = function()
						return false
					end,
				},
			},
		})
		local B = l:load("StarterPlayer/StarterPlayerScripts/BuilderTools")
		B.WatchTools()
		t.ok(binds.BuilderSelect, "build tools open: R2 selects")
		local tool = Instance.new("Tool")
		tool.Parent = char
		B.WatchTools()
		t.eq(binds.BuilderSelect, nil, "axe in hand: R2 is untouched")
		t.eq(B.SelectBound(), false)
		tool.Parent = nil
		B.WatchTools()
		t.ok(binds.BuilderSelect, "axe away: R2 selects again")
	end)
end
