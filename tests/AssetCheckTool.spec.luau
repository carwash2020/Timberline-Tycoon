--!nocheck
-- scripts/check-assets.ps1 is how Connor checks every asset id against Roblox
-- (the sandbox cannot). This pins what can be proven here: the id list the
-- script reads (tools/asset-ids.json) covers every downloadable id in
-- ASSETS.md, the script names the endpoint and the owner id, never writes to
-- a source file, and ASSETS.md tells Connor how to run it.
return function(t)
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")

	local list = serde.decode("json", fs.readFile("tools/asset-ids.json"))
	local script = fs.readFile("scripts/check-assets.ps1")
	local doc = fs.readFile("ASSETS.md")

	local function inList(id)
		for _, a in ipairs(list.assets) do
			if a.id == id then
				return a
			end
		end
		return nil
	end

	t.test("asset-ids.json carries the owner id and a well formed entry per id", function()
		t.eq(list.ownerUserId, 5682024709)
		local seen = {}
		local EXPECT = { mesh = 4, model = 10, image = 1, texture = 1, sound = 3 }
		for _, a in ipairs(list.assets) do
			t.ok(string.match(a.id, "^%d+$") ~= nil, "id is digits: " .. tostring(a.id))
			t.ok(not seen[a.id], "duplicate id " .. a.id)
			seen[a.id] = true
			t.eq(a.expectTypeId, EXPECT[a.kind], a.id .. " expected asset type")
			t.ok(a.priority == 1 or a.priority == 2, a.id .. " priority")
		end
	end)

	t.test("asset-ids.json covers every mesh, model, image, texture and sound id listed in ASSETS.md", function()
		local WANTED = {
			["Meshes"] = "mesh",
			["Model containers"] = "model",
			["Images"] = "image",
			["Material textures"] = "texture",
			["Sounds"] = "sound",
		}
		local kind = nil
		local found = 0
		for line in string.gmatch(doc, "[^\n]+") do
			local heading = string.match(line, "^## (.+)$")
			if heading then
				kind = nil
				for prefix, k in pairs(WANTED) do
					if string.sub(heading, 1, #prefix) == prefix then
						kind = k
					end
				end
			elseif kind then
				local id = string.match(line, "^| (%d+) |")
				if id then
					found += 1
					local a = inList(id)
					t.ok(a ~= nil, "ASSETS.md lists " .. id .. " but tools/asset-ids.json does not")
					if a then
						t.eq(a.kind, kind, id .. " kind")
					end
				end
			end
		end
		t.ok(found > 1200, "parsed the ASSETS.md tables (" .. found .. " ids)")
		t.eq(found, #list.assets, "same number of ids in ASSETS.md and asset-ids.json")
	end)

	t.test("the four machine meshes are priority 1 and nothing else is", function()
		local FIRST = { "124635139968707", "76460785351208", "91355579985009", "87960541936824" }
		for _, id in ipairs(FIRST) do
			local a = inList(id)
			t.ok(a ~= nil and a.priority == 1, id .. " is priority 1")
		end
		local n = 0
		for _, a in ipairs(list.assets) do
			if a.priority == 1 then
				n += 1
			end
		end
		t.eq(n, 4)
	end)

	t.test("the script asks the public endpoint, knows the owner, reads the id list, and is read-only", function()
		t.ok(string.find(script, "https://economy.roblox.com/v2/assets/{0}/details", 1, true), "endpoint")
		t.ok(string.find(script, "5682024709", 1, true), "owner id")
		t.ok(string.find(script, "asset-ids.json", 1, true), "id list")
		t.ok(string.find(script, "429", 1, true), "handles rate limiting")
		t.ok(string.find(script, "ASSETS-CHECK.md", 1, true), "writes the report")
		t.ok(string.find(script, "ASSETS-CHECK.csv", 1, true), "writes the csv")
		for _, banned in ipairs({
			"Remove-Item",
			"Set-Content",
			"Out-File",
			"git ",
			"Invoke-Expression",
			"-Method Post",
		}) do
			t.ok(not string.find(script, banned, 1, true), "script must not use " .. banned)
		end
		-- the only file write is the markdown report (the csv goes through Export-Csv)
		local writes = 0
		for _ in string.gmatch(script, "WriteAllText") do
			writes += 1
		end
		t.eq(writes, 1)
	end)

	t.test("ASSETS.md says how to run the script and every status is not checked yet", function()
		t.ok(string.find(doc, "scripts\\check-assets.ps1", 1, true), "run command")
		t.ok(string.find(doc, "Set-ExecutionPolicy -Scope Process", 1, true), "execution policy line")
		t.ok(string.find(doc, "ASSETS-CHECK.md", 1, true), "names the report")
		t.ok(not string.find(doc, ", unverified |", 1, true), "old status word gone")
		t.ok(string.find(doc, "not checked yet |", 1, true), "status column says not checked yet")
	end)
end
