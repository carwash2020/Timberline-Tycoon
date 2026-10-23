--!nocheck
-- run_task (T409): the cloud test's runner script. Its python tests (tools/cloud/test_run_task.py: argument
-- parsing, the target pin to the TEST place, a missing key SKIPPED and never PASSED, 401/403/409 failing with
-- the code, one task per run, a polled 3 s) run here so the CI test shards run them, and the missing-key dry run
-- is run for real, as CI runs it with no secret.
return function(t)
	local process = require("@lune/process")

	local function py(args, env)
		local list = { "-i", "PATH=/usr/bin:/bin:/usr/local/bin" }
		for k, v in pairs(env or {}) do
			table.insert(list, k .. "=" .. v)
		end
		table.insert(list, "python3")
		for _, a in ipairs(args) do
			table.insert(list, a)
		end
		return process.exec("env", list)
	end

	t.test("the runner's python tests pass", function()
		local r = py({ "tools/cloud/test_run_task.py" })
		t.ok(r.ok, r.stderr .. r.stdout)
		t.ok(string.find(r.stderr, "OK", 1, true), r.stderr)
	end)

	t.test("no key: SKIPPED, exit 0, never PASSED, and the summary line says SKIPPED", function()
		local summary = "/tmp/runtask-spec-summary.md"
		local r = py({ "tools/cloud/run_task.py", "--dry-run" }, { GITHUB_STEP_SUMMARY = summary })
		t.eq(r.code, 0)
		t.eq(r.stdout, "cloud-test SKIPPED: missing ROBLOX_API_KEY\n")
		t.ok(not string.find(r.stdout, "PASSED", 1, true))
		local fs = require("@lune/fs")
		t.ok(string.find(fs.readFile(summary), "SKIPPED", 1, true), "the run summary shows SKIPPED")
		fs.removeFile(summary)
	end)

	t.test("no key and CLOUD_TEST_REQUIRED=1: FAILED, exit 1", function()
		local r = py({ "tools/cloud/run_task.py", "--dry-run" }, { CLOUD_TEST_REQUIRED = "1" })
		t.eq(r.code, 1)
		t.ok(string.find(r.stdout, "cloud-test FAILED: missing ROBLOX_API_KEY", 1, true), r.stdout)
	end)

	t.test("CLOUD_TEST_REQUIRED=0 or anything but 1 still skips", function()
		local r = py({ "tools/cloud/run_task.py", "--dry-run" }, { CLOUD_TEST_REQUIRED = "0" })
		t.eq(r.code, 0)
		t.ok(string.find(r.stdout, "SKIPPED", 1, true), r.stdout)
	end)

	t.test("any other place id is refused, exit 2, before a key is even looked at", function()
		local r = py(
			{ "tools/cloud/run_task.py", "--dry-run" },
			{ TEST_PLACE_ID = "12345", ROBLOX_API_KEY = "not-a-real-key" }
		)
		t.eq(r.code, 2)
		t.ok(string.find(r.stdout, "is not the TEST place 109062394774073", 1, true), r.stdout)
		t.ok(not string.find(r.stdout .. r.stderr, "not-a-real-key", 1, true), "the key is never printed")
	end)

	t.test("with a key and the TEST ids a dry run names the target and sends nothing", function()
		local r = py({ "tools/cloud/run_task.py", "--dry-run" }, { ROBLOX_API_KEY = "not-a-real-key" })
		t.eq(r.code, 0)
		t.ok(string.find(r.stdout, "universe 10772436908, place 109062394774073", 1, true), r.stdout)
		t.ok(not string.find(r.stdout .. r.stderr, "not-a-real-key", 1, true))
	end)
end
