--!nocheck
-- T414d-2 names: what other systems find by name must still be there after the greenery and critters landed.
return function(t)
	local fs = require("@lune/fs")
	local function read(path)
		return fs.readFile("src/" .. path)
	end
	local function has(source, text, why)
		t.ok(string.find(source, text, 1, true) ~= nil, why or text)
	end

	t.test("TreeService still tags a stump and a tree, and the boot stump meshes check is there", function()
		local tree = read("ServerScriptService/TreeService.luau")
		has(tree, 'CollectionService:AddTag(stump, "Stump")', "Stump tag")
		has(tree, "CollectionService:AddTag(model, TREE_TAG)", "tree tag")
		t.ok(
			fs.isFile("src/ServerScriptService/StumpMeshes.server.luau")
				or fs.isFile("src/ServerScriptService/StumpMeshes.luau")
		)
	end)

	t.test("ForestService still sets the elder clue attributes and the aura's TreeUid", function()
		local forest = read("ServerScriptService/ForestService.luau")
		for _, name in ipairs({ "ElderUid", "ElderWood", "ElderBiome", "ElderPos", "TreeUid", "SkyrootBloom" }) do
			has(forest, '"' .. name .. '"', name)
		end
		local art = t.load("ReplicatedStorage/Shared/Art/ForestArt")
		for _, fn in ipairs({ "BarkClue", "StormGlow", "SectionClue", "ClueSection" }) do
			t.ok(type(art[fn]) == "function", "ForestArt." .. fn)
		end
	end)

	t.test("AmbientLife still starts and still owns the critters and the decoration", function()
		local life = read("StarterPlayer/StarterPlayerScripts/AmbientLife.luau")
		has(life, "function AmbientLife.Start()")
		has(life, "CritterArt")
		has(life, "DecorSpots")
	end)

	t.test("BuildingArt.Greenery is a one-line delegate and the town still gets its four kinds", function()
		local building = read("ReplicatedStorage/Shared/Art/BuildingArt.luau")
		local body = string.match(building, "function BuildingArt%.Greenery%b()[^\n]*\n(.-)\nend")
		t.ok(body and not string.find(body, "\n"), "one line in the body")
		has(body, "Greenery.Build(")
		local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
		for _, kind in ipairs({ "tree", "bush", "flowers", "rock" }) do
			local model = BuildingArt.Greenery(kind, 4, 3, "birch")
			t.ok(model:IsA("Model") and #model:GetDescendants() > 0, kind)
		end
	end)
end
