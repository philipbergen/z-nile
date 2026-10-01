--!strict
-- c0140 AC4: the CI side, checked on the parsed workflow, not on its text (text matches can't tell a condition
-- from a comment, or && from ||). A PR that is ready for review is published to Beta after the gate is
-- green, from branches of this repo only, one publish at a time, with the Roblox secrets named only in the
-- env of the step that needs them, and no way for them to reach a log or a fork.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local text = fs.readFile(".github/workflows/check.yml")
local wf: any = serde.decode("yaml" :: "yaml", text)
local beta: any = wf.jobs.beta
local gate: any = wf.jobs.gate

local function collapse(s: string): string
	return (string.gsub(string.gsub(s, "%s+", " "), "^ ", ""):gsub(" $", ""))
end

-- the first step satisfying `pred`, and its index
local function find(job: any, pred: (any) -> boolean): (any, number)
	for i, step in job.steps do
		if pred(step) then
			return step, i
		end
	end
	error("no such step")
end

local function count(haystack: string, needle: string): number
	local n, i = 0, 1
	while true do
		local s, e = string.find(haystack, needle, i, true)
		if not s then
			return n
		end
		n += 1
		i = (e :: number) + 1
	end
end

-- the sorted keys of a table, ignoring `name` (a label, harmless)
local function keysOf(tbl: any): { string }
	local out = {}
	for k in tbl do
		if k ~= "name" then
			table.insert(out, tostring(k))
		end
	end
	table.sort(out)
	return out
end

local KEY = "${{ secrets.ROBLOX_API_KEY }}"
local UNIVERSE = "${{ vars.ROBLOX_BETA_UNIVERSE_ID }}"
local PLACE = "${{ vars.ROBLOX_BETA_PLACE_ID }}"

local function has(s: any, needle: string): boolean
	return type(s) == "string" and string.find(s, needle, 1, true) ~= nil
end

return t.spec("c0140 beta job in check.yml", function(it)
	it(
		"the workflow and the beta job have exactly the keys designed, so nothing can change what green means",
		function()
			-- a key nobody named is a hole: continue-on-error, defaults, container, strategy, services, env ...
			t.expect(keysOf(wf)).toEqual({ "jobs", "on", "permissions" })
			t.expect(keysOf(beta)).toEqual({
				"concurrency",
				"if",
				"needs",
				"permissions",
				"runs-on",
				"steps",
				"timeout-minutes",
			})
			t.expect(beta["runs-on"]).toBe("ubuntu-latest")
		end
	)

	it(
		"every step has exactly the keys designed: no with, shell, working-directory, continue-on-error or extra if",
		function()
			local steps: any = beta.steps
			t.expect(#steps == 4 or #steps == 5).toBe(true) -- 5 once c0030 adds the runtime step
			t.expect(keysOf(steps[1])).toEqual({ "uses" })
			t.expect(steps[1].uses).toBe("actions/checkout@v4")
			t.expect(keysOf(steps[2])).toEqual({ "env", "run" })
			t.expect(steps[2].run).toBe("scripts/setup.sh --tools")
			t.expect(steps[2].env).toEqual({ GH_TOKEN = "${{ github.token }}" })
			t.expect(keysOf(steps[3])).toEqual({ "env", "id", "run" })
			t.expect(keysOf(steps[4])).toEqual({ "env", "if", "run" })
			t.expect(steps[4].env).toEqual({
				GH_TOKEN = "${{ github.token }}",
				PR = "${{ github.event.pull_request.number }}",
				VERSION = "${{ steps.deploy.outputs.version }}",
				SHA = "${{ github.event.pull_request.head.sha }}",
			})
			if #steps == 5 then
				-- exactly the runtime step c0030 adds, and nothing else
				t.expect(keysOf(steps[5])).toEqual({ "env", "if", "run" })
				t.expect(steps[5].run).toBe('lune run scripts/runtime-test -- "$VERSION"')
				t.expect(steps[5]["if"]).toBe("steps.deploy.outputs.version != ''")
			end
		end
	)

	it("runs after the gate, and only for a PR that is ready for review and from this repo", function()
		t.expect(beta.needs).toBe("gate")
		t.expect(collapse(beta["if"])).toBe(
			"github.event_name == 'pull_request' && github.event.pull_request.draft == false && github.event.pull_request.head.repo.full_name == github.repository"
		)
	end)

	it("the workflow's triggers and the gate job are unchanged, and nothing runs on pull_request_target", function()
		local on: any = wf["on"]
		t.expect(on.push).toEqual({ branches = { "main" } })
		t.expect(on.pull_request).toEqual({ types = { "opened", "synchronize", "reopened", "ready_for_review" } })
		t.expect(on.workflow_dispatch ~= nil).toBe(true)
		t.expect(on.pull_request_target).toBe(nil)
		t.expect(gate["if"]).toBe("github.event_name != 'pull_request' || github.event.pull_request.draft == false")
		t.expect(gate["runs-on"]).toBe("ubuntu-latest")
	end)

	it("publishes one at a time, never aborting a publish in flight", function()
		t.expect(beta.concurrency).toEqual({ group = "beta-deploy", ["cancel-in-progress"] = false })
	end)

	it("can't hold the shared lock for hours: the job has a timeout of at most 30 minutes", function()
		t.expect(type(beta["timeout-minutes"])).toBe("number")
		t.expect(beta["timeout-minutes"] > 0 and beta["timeout-minutes"] <= 30).toBe(true)
	end)

	it("keeps the workflow read-only and gives write on pull requests only to the beta job", function()
		t.expect(wf.permissions).toEqual({ contents = "read" })
		t.expect(beta.permissions).toEqual({ contents = "read", ["pull-requests"] = "write" })
		t.expect(gate.permissions).toBe(nil)
	end)

	it("names the secret only in the env of the deploy step (c0030 adds the runtime step's)", function()
		local deploy = find(beta, function(s: any)
			return s.id == "deploy"
		end)
		t.expect(deploy.run).toBe("lune run scripts/deploy-beta")
		t.expect(deploy.env).toEqual({
			ROBLOX_API_KEY = KEY,
			ROBLOX_BETA_UNIVERSE_ID = UNIVERSE,
			ROBLOX_BETA_PLACE_ID = PLACE,
		})
		-- nowhere else: not the job, not the gate, not the other steps of the beta job (but the runtime step)
		t.expect(beta.env).toBe(nil)
		t.expect(has(serde.encode("json" :: "json", gate), "secrets.")).toBe(false)
		for i, step in beta.steps do
			local isRuntime = i == 5 and step.run == 'lune run scripts/runtime-test -- "$VERSION"'
			if step.id ~= "deploy" and not isRuntime then
				t.expect(has(serde.encode("json" :: "json", step), "ROBLOX")).toBe(false)
			end
		end
		t.expect(count(text, "secrets.ROBLOX_API_KEY") <= 2).toBe(true)
		t.expect(has(text, 'echo "$ROBLOX_API_KEY')).toBe(false)
		t.expect(has(text, "set -x")).toBe(false)
	end)

	it("installs the tools without running the gate again, before it deploys, with no Roblox secret", function()
		local setup, setupAt = find(beta, function(s: any)
			return has(s.run, "scripts/setup.sh")
		end)
		local _, deployAt = find(beta, function(s: any)
			return s.id == "deploy"
		end)
		t.expect(setup.run).toBe("scripts/setup.sh --tools")
		t.expect(setupAt < deployAt).toBe(true)
		t.expect(beta.steps[1].uses).toBe("actions/checkout@v4")
	end)

	it("comments the published version after the deploy, only when something was published, in place", function()
		local comment, commentAt = find(beta, function(s: any)
			return has(s.run, "gh pr comment")
		end)
		local _, deployAt = find(beta, function(s: any)
			return s.id == "deploy"
		end)
		t.expect(commentAt > deployAt).toBe(true)
		t.expect(comment["if"]).toBe("steps.deploy.outputs.version != ''")
		t.expect(has(comment.run, "--edit-last --create-if-none")).toBe(true)
		t.expect(comment.env.VERSION).toBe("${{ steps.deploy.outputs.version }}")
	end)

	it("never lets a `${{ }}` expression or untrusted PR text into a command line", function()
		for _, job in { gate, beta } do
			for _, step in job.steps do
				if step.run then
					t.expect((string.find(step.run, "${{", 1, true))).toBe(nil)
				end
			end
		end
		for _, bad in { "pull_request.title", "pull_request.body", "head_ref", "head.ref", "github.event.comment" } do
			t.expect(has(text, bad)).toBe(false)
		end
	end)
end)
