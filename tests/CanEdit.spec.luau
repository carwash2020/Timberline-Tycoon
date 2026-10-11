--!nocheck
-- Lane F: PlotLogic.CanEdit, the one edit-rights rule (QA BL4).
return function(t)
	local PlotLogic = t.shared("PlotLogic")
	local PermissionLogic = t.shared("PermissionLogic")

	t.test("the owner may always edit; a stranger may not by default", function()
		local perms = {}
		for _, flag in ipairs({ "build", "destroy", "interact", "paint", "grab" }) do
			t.eq(PlotLogic.CanEdit(perms, 7, 7, flag), true, "owner " .. flag)
			t.eq(PlotLogic.CanEdit(perms, 9, 7, flag), false, "stranger " .. flag)
		end
	end)

	t.test("a friend with build may build, paint and destroy, not grab", function()
		local perms = {}
		t.eq(PermissionLogic.Set(perms, "9", "build", true), true)
		t.eq(PlotLogic.CanEdit(perms, 9, 7, "build"), true)
		t.eq(PlotLogic.CanEdit(perms, 9, 7, "paint"), true, "paint rides on build")
		t.eq(PlotLogic.CanEdit(perms, 9, 7, "destroy"), true, "build implies destroy")
		t.eq(PlotLogic.CanEdit(perms, 9, 7, "grab"), false)
		t.eq(PlotLogic.CanEdit(perms, 10, 7, "build"), false, "only that friend")
	end)

	t.test("junk is refused", function()
		t.eq(PlotLogic.CanEdit({}, 9, 7, "launch"), false)
		t.eq(PlotLogic.CanEdit({}, "9", 7, "build"), false)
		t.eq(PlotLogic.CanEdit({}, 0, 0, "build"), false, "no owner, no rights")
		t.eq(PlotLogic.CanEdit(nil, 9, 7, "build"), false)
	end)
	-- The live twin and its call sites. Every place that decides "may this player
	-- change that player's plot" goes through the same rule (QA BL4).
	local function world()
		local profiles = {}
		local players = {}
		local loader = t.loader({
			services = {
				Players = {
					GetPlayerByUserId = function(_, id)
						return players[id]
					end,
					GetPlayers = function()
						return {}
					end,
				},
			},
			mocks = {
				ProfileService = {
					GetProfile = function(player)
						return profiles[player]
					end,
				},
				RateLimiter = {
					Allow = function()
						return true
					end,
				},
			},
		})
		local function player(id)
			local p = { UserId = id, Name = "P" .. id, attrs = {} }
			function p:SetAttribute(key, value)
				self.attrs[key] = value
			end
			players[id] = p
			return p
		end
		return loader, profiles, player
	end

	t.test("EditRights.Can: the owner, a friend with the flag, a stranger, and a missing owner", function()
		local loader, profiles, player = world()
		local Rights = loader:server("EditRights")
		local owner, friend, stranger = player(7), player(8), player(9)
		profiles[owner] = { permissions = { ["8"] = { build = true, interact = true } } }
		for _, flag in ipairs({ "build", "destroy", "interact", "paint", "grab" }) do
			t.eq(Rights.Can(owner, owner, flag), true, "owner " .. flag)
			t.eq(Rights.Can(stranger, owner, flag), false, "stranger " .. flag)
		end
		t.eq(Rights.Can(friend, owner, "build"), true)
		t.eq(Rights.Can(friend, owner, "paint"), true, "paint rides on build")
		t.eq(Rights.Can(friend, owner, "grab"), false)
		t.eq(Rights.Can(friend, nil, "build"), false, "the owner left the server")
		t.eq(Rights.Can(nil, owner, "build"), false)
		profiles[owner] = nil
		t.eq(Rights.Can(friend, owner, "build"), false, "no profile, no rights")
		t.eq(Rights.Can(owner, owner, "build"), true, "an owner is always their own")
	end)

	t.test("PermissionService.Can (the grab service asks it) follows PlotLogic.CanEdit", function()
		local loader, profiles, player = world()
		local Perms = loader:server("PermissionService")
		local owner, friend, stranger = player(7), player(8), player(9)
		profiles[owner] = { permissions = { ["8"] = { grab = true, build = true } } }
		t.eq(Perms.Can(owner, 7, "build"), true)
		t.eq(Perms.Can(friend, 7, "grab"), true)
		t.eq(Perms.Can(friend, 7, "paint"), true)
		t.eq(Perms.Can(stranger, 7, "grab"), false)
		t.eq(Perms.Can(stranger, 7, "build"), false)
		t.eq(Perms.Can(friend, 99, "grab"), false, "an owner who is not here")
		t.eq(Perms.Can(friend, 7, "launch"), false, "an unknown flag")
	end)

	t.test("PlotService.CanEdit and OwnerAt: the one helper the other services reach", function()
		local fs = require("@lune/fs")
		local plot = fs.readFile("src/ServerScriptService/PlotService.luau")
		t.ok(string.find(plot, "function PlotService.CanEdit", 1, true))
		t.ok(string.find(plot, "return EditRights.Can(player, owner, flag)", 1, true), "one implementation")
		-- Every service named in the brief reaches that rule, not its own copy.
		local sites = {
			{ "ChopSawService", "EditRights.Can(player, owner, ChopSawLogic.UseFlag)" },
			{ "SawmillService", 'EditRights.Can(player, mayOwner, "interact")' },
			{ "LogicService", "PlotLogic.CanEdit(profile.permissions, who.UserId, owner.UserId, flag)" },
			{ "PermissionService", "PlotLogic.CanEdit(profile.permissions, userId, ownerId, flag)" },
			{ "VehicleService", 'PlotLogic.CanEdit(permissions, player.UserId, ownerId, "interact")' },
			{ "BlueprintService", "BlueprintService.Hooks.canEdit" },
		}
		for _, site in ipairs(sites) do
			local src = fs.readFile("src/ServerScriptService/" .. site[1] .. ".luau")
			t.ok(string.find(src, site[2], 1, true) ~= nil, site[1] .. " uses the shared rule")
			t.eq(string.find(src, "PermissionLogic.Allows", 1, true), nil, site[1] .. " has no rule of its own")
		end
	end)
end
