--!strict
-- c0010 AC2: CI bootstraps exactly like a new host (scripts/setup.sh), can be dispatched by an
-- agent, and skips only draft pull_request events.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local wf = serde.decode("yaml", fs.readFile(".github/workflows/check.yml"))
-- YAML 1.1 parsers may read the bare key `on` as boolean true
local on = wf.on or wf[true]
local job = wf.jobs and wf.jobs.gate

return t.spec("ci workflow", function(it)
	it("bootstraps via scripts/setup.sh with GH_TOKEN", function()
		t.expect(job ~= nil).toBe(true)
		local found = false
		for _, step in job.steps do
			if type(step.run) == "string" and string.find(step.run, "scripts/setup.sh", 1, true) then
				found = true
				t.expect(step.env and step.env.GH_TOKEN).toBe("${{ github.token }}")
			end
		end
		t.expect(found).toBe(true)
	end)

	it("does not use the setup-rokit action", function()
		for _, step in job.steps do
			t.expect(type(step.uses) == "string" and string.find(step.uses, "setup-rokit", 1, true) ~= nil)
				.toBe(false)
		end
	end)

	it("is dispatchable and runs on main pushes and pull requests", function()
		t.expect(on ~= nil).toBe(true)
		t.expect(on.workflow_dispatch ~= nil).toBe(true)
		t.expect(on.push and on.push.branches and on.push.branches[1]).toBe("main")
		local types = on.pull_request and on.pull_request.types or {}
		t.expect(table.find(types, "ready_for_review") ~= nil).toBe(true)
	end)

	it("skips drafts only for pull_request events", function()
		local cond = string.gsub(job["if"] or "", "%s+", " ")
		t.expect(cond).toBe("github.event_name != 'pull_request' || github.event.pull_request.draft == false")
	end)
end)
