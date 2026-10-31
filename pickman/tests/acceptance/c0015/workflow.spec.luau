--!strict
-- c0140 AC4, overridden by c0172: the deploy job publishes from this repo, one publish at a time is c0172's pin.
-- Secrets stay in the deploy step's env. A draft, a fork and the comment's event are c0172's pins.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

-- c0120 override: the spec runs from its home: the checkout's files are read from the top
local text = fs.readFile("../.github/workflows/deploy.yml")
local wf: any = serde.decode("yaml" :: "yaml", text)
local deploy: any = wf.jobs.deploy

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

return t.spec("c0140 deploy job", function(it)
	it("the first four steps have exactly the keys designed, and the deploy runs from pickman/", function()
		local steps: any = deploy.steps
		t.expect(#steps >= 4).toBe(true)
		t.expect(keysOf(steps[1])).toEqual({ "uses" })
		t.expect(steps[1].uses).toBe("actions/checkout@v4")
		t.expect(keysOf(steps[2])).toEqual({ "env", "run" })
		t.expect(steps[2].run).toBe("z-nile/setup.sh --tools")
		t.expect(steps[2].env).toEqual({ GH_TOKEN = "${{ github.token }}" })
		t.expect(keysOf(steps[3])).toEqual({ "env", "id", "run", "working-directory" })
		t.expect(steps[3]["working-directory"]).toBe("pickman")
		t.expect(keysOf(steps[4])).toEqual({ "env", "if", "run" })
		t.expect(steps[4].env).toEqual({
			GH_TOKEN = "${{ github.token }}",
			PR = "${{ github.event.pull_request.number }}",
			VERSION = "${{ steps.deploy.outputs.version }}",
			SHA = "${{ github.event.pull_request.head.sha }}",
		})
	end)

	it(
		"the workflow lists pushes to main, pull requests and manual dispatch, and nothing runs on pull_request_target",
		function()
			local on: any = wf["on"]
			t.expect(on.push.branches).toEqual({ "main" })
			t.expect(on.push["paths-ignore"])
				.toEqual({ "pickman/.tracker/**", "z-nile/.tracker/**", "z-nile/next" })
			t.expect(on.pull_request)
				.toEqual({ types = { "opened", "synchronize", "reopened", "ready_for_review" } })
			t.expect(on.workflow_dispatch ~= nil).toBe(true)
			t.expect(on.pull_request_target).toBe(nil)
			t.expect(deploy["runs-on"]).toBe("ubuntu-latest")
		end
	)

	it("can't hold the shared lock for hours: the job has a timeout of at most 30 minutes", function()
		t.expect(type(deploy["timeout-minutes"])).toBe("number")
		t.expect(deploy["timeout-minutes"] > 0 and deploy["timeout-minutes"] <= 30).toBe(true)
	end)

	it("keeps the workflow read-only and gives write on pull requests only to the deploy job", function()
		t.expect(wf.permissions).toEqual({ contents = "read" })
		t.expect(deploy.permissions).toEqual({ contents = "read", ["pull-requests"] = "write" })
	end)

	it("names the secret only in the env of the deploy step", function()
		local publish = find(deploy, function(s: any)
			return s.id == "deploy"
		end)
		t.expect(publish.run).toBe("lune run scripts/deploy-beta")
		for name, value in
			{ ROBLOX_API_KEY = KEY, ROBLOX_BETA_UNIVERSE_ID = UNIVERSE, ROBLOX_BETA_PLACE_ID = PLACE }
		do
			t.expect(publish.env[name]).toBe(value)
		end
		t.expect(deploy.env).toBe(nil)
		for _, step in deploy.steps do
			if step.id ~= "deploy" and not has(step.run, "lune run scripts/runtime-test -- ") then
				t.expect(has(serde.encode("json" :: "json", step), "ROBLOX")).toBe(false)
			end
		end
		t.expect(count(text, "secrets.ROBLOX_API_KEY") <= 3).toBe(true)
		t.expect(has(text, 'echo "$ROBLOX_API_KEY')).toBe(false)
		t.expect(has(text, "set -x")).toBe(false)
	end)

	it("installs the tools without a Roblox secret, before it deploys", function()
		local setup, setupAt = find(deploy, function(s: any)
			return has(s.run, "z-nile/setup.sh")
		end)
		local _, deployAt = find(deploy, function(s: any)
			return s.id == "deploy"
		end)
		t.expect(setup.run).toBe("z-nile/setup.sh --tools")
		t.expect(setupAt < deployAt).toBe(true)
		t.expect(deploy.steps[1].uses).toBe("actions/checkout@v4")
	end)

	it("comments the published version after the deploy, in place", function()
		local comment, commentAt = find(deploy, function(s: any)
			return has(s.run, "gh pr comment")
		end)
		local _, deployAt = find(deploy, function(s: any)
			return s.id == "deploy"
		end)
		t.expect(commentAt > deployAt).toBe(true)
		t.expect(collapse(comment.run)).toBe(
			'gh pr comment "$PR" --edit-last --create-if-none \\ --body "Published to Pickman (Beta): version $VERSION (commit $SHA)."'
		)
		t.expect(comment.env.VERSION).toBe("${{ steps.deploy.outputs.version }}")
	end)

	it("never lets a `${{ }}` expression or untrusted PR text into a command line", function()
		for _, step in deploy.steps do
			if step.run then
				t.expect((string.find(step.run, "${{", 1, true))).toBe(nil)
			end
		end
		for _, bad in
			{ "pull_request.title", "pull_request.body", "head_ref", "head.ref", "github.event.comment" }
		do
			t.expect(has(text, bad)).toBe(false)
		end
	end)
end)
