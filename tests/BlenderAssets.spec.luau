--!nocheck
-- BlenderAssets: the Lane H registry of Blender-made models. Every row's file
-- is in the repo (or lands with job 17 for backlog rows), every model is
-- under the 20,000-triangle import limit, ids default to 0, and the game is
-- unchanged while they are (MeshManifest adds nothing).
return function(t)
	local fs = require("@lune/fs")
	local BlenderAssets = t.load("ReplicatedStorage/Shared/Art/BlenderAssets")

	t.test("every row has a name, a group, a known status and collision", function()
		local seen = {}
		t.ok(#BlenderAssets.All > 100, "the registry lists the uploaded models")
		for _, entry in ipairs(BlenderAssets.All) do
			t.ok(type(entry.name) == "string" and entry.name:find("/") ~= nil, "name is group/Name")
			t.ok(not seen[entry.name], entry.name .. " listed twice")
			seen[entry.name] = true
			t.eq(entry.name:match("^[^/]+"), entry.group, entry.name .. " group")
			t.ok(
				entry.status == "repo" or entry.status == "backlog" or entry.status == "planned",
				entry.name .. " status"
			)
			t.ok(
				entry.collision == "Box" or entry.collision == "Hull" or entry.collision == "Parts",
				entry.name .. " collision"
			)
			t.eq(BlenderAssets.Get(entry.name), entry)
		end
		t.eq(BlenderAssets.Get("nope/Nothing"), nil)
	end)

	t.test("repo rows: the GLB is in assets/meshes and the id stays 0", function()
		local count = 0
		for _, entry in ipairs(BlenderAssets.All) do
			if entry.status == "repo" then
				count += 1
				t.ok(fs.isFile(entry.file), entry.name .. ": " .. entry.file .. " exists")
				t.eq(entry.meshId, 0, entry.name .. " meshId stays 0 (its wiredBy module owns the live ids)")
				t.ok(entry.wiredBy ~= "", entry.name .. " names its module")
				t.ok(
					fs.isFile("src/ReplicatedStorage/Shared/Art/" .. entry.wiredBy .. ".luau")
						or fs.isFile("src/ReplicatedStorage/Shared/" .. entry.wiredBy .. ".luau"),
					entry.name .. ": " .. entry.wiredBy .. " is a real module"
				)
			end
		end
		t.ok(count >= 140, "every asset folder in assets/meshes")
	end)

	t.test("every model is under the import limit and has a real size", function()
		for _, entry in ipairs(BlenderAssets.All) do
			t.ok(entry.tris <= BlenderAssets.MaxTris, entry.name .. " tris " .. entry.tris)
			if entry.status == "planned" then
				t.eq(entry.tris, 0, entry.name .. " has no model yet")
				t.eq(entry.file, "", entry.name .. " has no file yet")
			else
				t.ok(entry.tris > 0, entry.name .. " has triangles")
				t.ok(entry.size.X > 0 and entry.size.Y > 0 and entry.size.Z > 0, entry.name .. " size")
			end
		end
	end)

	t.test("ids default to 0: only backlog rows carry an uploaded id, and no texture id is set", function()
		for _, entry in ipairs(BlenderAssets.All) do
			if entry.status == "backlog" then
				t.ok(entry.meshId > 0, entry.name .. " backlog id")
				t.eq(entry.wiredBy, "BacklogModels")
			else
				t.eq(entry.meshId, 0, entry.name .. " meshId")
			end
			for key, id in pairs(entry.textures) do
				t.eq(id, 0, entry.name .. " texture " .. key)
			end
		end
	end)

	t.test("the game is unchanged: MeshManifest's blender group is empty while ids are 0", function()
		t.eq(#BlenderAssets.MeshIds(), 0)
		local loader = t.loader()
		local MeshManifest = loader:shared("Art/MeshManifest")
		local found = false
		for _, group in ipairs(MeshManifest.Groups(true)) do
			if group.name == "blender" then
				found = true
				t.eq(#group.entries, 0, "no preload while every id is 0")
			end
		end
		t.ok(found, "MeshManifest reads the registry")
	end)
end
