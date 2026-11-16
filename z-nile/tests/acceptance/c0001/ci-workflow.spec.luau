--!strict
-- c0010 AC2: CI bootstraps exactly like a new host (z-nile/setup.sh), can be dispatched by an
-- agent, and skips only draft pull_request events.
local fs = require("@lune/fs")
-- c0120 override: the spec runs from its project's home after the move
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
-- c0120 override: specs run from their project's home; the repository files live at the checkout's top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local text = fs.readFile(`{TOP}/.github/workflows/deploy.yml`)
local wf = serde.decode("yaml", text)
-- YAML 1.1 parsers may read the bare key `on` as boolean true
local on = wf.on or wf[true]
local job = wf.jobs and wf.jobs.deploy

return t.spec("ci workflow", function(it)
	it("bootstraps via exactly `run: z-nile/setup.sh --tools` with GH_TOKEN", function()
		t.expect(job ~= nil).toBe(true)
		-- c0172 override: the only job publishes. It still bootstraps with the tools-only setup.
		local found = false
		for _, step in job.steps do
			local run = if type(step.run) == "string"
				then (string.gsub(string.gsub(step.run, "^%s+", ""), "%s+$", ""))
				else ""
			if run == "z-nile/setup.sh --tools" then
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
		-- `workflow_dispatch:` (null) decodes to an absent key, so also accept the raw text form
		local dispatchable = on.workflow_dispatch ~= nil
			or string.find(text, "\n%s+workflow_dispatch:%s*[\n{]") ~= nil
		t.expect(dispatchable).toBe(true)
		t.expect(on.push and on.push.branches and on.push.branches[1]).toBe("main")
		local types = on.pull_request and on.pull_request.types or {}
		t.expect(table.find(types, "ready_for_review") ~= nil).toBe(true)
	end)

	it("never ignores failures (no continue-on-error anywhere)", function()
		t.expect(job["continue-on-error"] == nil or job["continue-on-error"] == false).toBe(true)
		for _, step in job.steps do
			t.expect(step["continue-on-error"] == nil or step["continue-on-error"] == false).toBe(true)
			local run = if type(step.run) == "string" then step.run else ""
			t.expect((string.find(run, "|| true", 1, true))).toBe(nil)
		end
	end)
end)
