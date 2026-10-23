-- What the Luau Execution task runs (tools/cloud/run_task.py sends this file as the task's script).
-- tests/cloud/entry is mapped into ServerStorage by tools/cloud/make_project.py. It prints its findings
-- and calls error() if anything failed, which fails the task.
local ServerStorage = game:GetService("ServerStorage")
return require(ServerStorage.CloudTests.entry)()
