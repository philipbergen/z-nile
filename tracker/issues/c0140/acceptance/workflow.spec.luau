--!strict
-- c0140 AC4: the CI side. A PR that is ready for review is published to Beta after the gate is green,
-- from branches of this repo only, one publish at a time, with the Roblox secrets named in exactly one
-- place (the beta job's env) and no way for them to reach a log or a fork.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local text = fs.readFile(".github/workflows/check.yml")

-- the text of one job: from `  name:` to the next job (two-space indent) or the end
local function job(name: string): string
	local from = string.find(text, `\n  {name}:\n`, 1, true)
	t.expect(from ~= nil).toBe(true)
	local start = (from :: number) + 1
	local nextJob = string.find(text, "\n  [%w_%-]+:\n", start + 1)
	return string.sub(text, start, if nextJob then nextJob else #text)
end

local function has(haystack: string, needle: string): boolean
	return string.find(haystack, needle, 1, true) ~= nil
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

return t.spec("c0140 beta job in check.yml", function(it)
	local beta = job("beta")
	local gate = job("gate")

	it("runs only after the gate, and only for a PR that is ready and from this repo", function()
		t.expect(has(beta, "needs: gate")).toBe(true)
		t.expect(has(beta, "github.event_name == 'pull_request'")).toBe(true)
		t.expect(has(beta, "github.event.pull_request.draft == false")).toBe(true)
		t.expect(has(beta, "github.event.pull_request.head.repo.full_name == github.repository")).toBe(true)
	end)

	it("never publishes from a dispatched run or a push to main", function()
		t.expect(has(beta, "github.event_name == 'pull_request'")).toBe(true) -- the only event it accepts
		t.expect(has(beta, "workflow_dispatch")).toBe(false)
		t.expect(has(beta, "refs/heads/main")).toBe(false)
	end)

	it("publishes one at a time, never aborting a publish in flight, newest waiting wins", function()
		t.expect(has(beta, "group: beta-deploy")).toBe(true)
		t.expect(has(beta, "cancel-in-progress: false")).toBe(true)
	end)

	it("names the secrets only in the beta job's env, and never in a command", function()
		t.expect(count(text, "secrets.ROBLOX_API_KEY")).toBe(1)
		t.expect(has(beta, "ROBLOX_API_KEY: ${{ secrets.ROBLOX_API_KEY }}")).toBe(true)
		t.expect(count(text, "vars.ROBLOX_BETA_UNIVERSE_ID")).toBe(1)
		t.expect(count(text, "vars.ROBLOX_BETA_PLACE_ID")).toBe(1)
		t.expect(has(gate, "secrets.")).toBe(false)
		t.expect(has(text, 'echo "$ROBLOX_API_KEY')).toBe(false)
		t.expect(has(text, "set -x")).toBe(false)
	end)

	it(
		"keeps the workflow's permissions read-only and gives only the beta job write on pull requests",
		function()
			local head = string.sub(text, 1, string.find(text, "\njobs:", 1, true) :: number)
			t.expect(has(head, "contents: read")).toBe(true)
			t.expect(has(head, "pull-requests")).toBe(false)
			t.expect(has(beta, "pull-requests: write")).toBe(true)
			t.expect(has(gate, "pull-requests")).toBe(false)
			t.expect(has(text, "pull_request_target")).toBe(false)
		end
	)

	it("installs the tools without running the gate again, then deploys and comments the version", function()
		t.expect(has(beta, "scripts/setup.sh --tools")).toBe(true)
		t.expect(has(beta, "id: deploy")).toBe(true)
		t.expect(has(beta, "lune run scripts/deploy-beta")).toBe(true)
		t.expect(has(beta, "gh pr comment")).toBe(true)
		t.expect(has(beta, "steps.deploy.outputs.version")).toBe(true)
		local setup = string.find(beta, "scripts/setup.sh --tools", 1, true) :: number
		local deploy = string.find(beta, "lune run scripts/deploy-beta", 1, true) :: number
		local comment = string.find(beta, "gh pr comment", 1, true) :: number
		t.expect(setup < deploy).toBe(true)
		t.expect(deploy < comment).toBe(true)
	end)

	it(
		"comments only when something was published, and updates its own comment rather than adding one",
		function()
			-- the nearest `if:` above the comment command is the publish guard
			local comment = string.find(beta, "gh pr comment", 1, true) :: number
			local guard: number? = nil
			local pos = 1
			while true do
				local s, e = string.find(
					string.sub(beta, 1, comment),
					"if: steps.deploy.outputs.version != ''",
					pos,
					true
				)
				if not s then
					break
				end
				guard = s
				pos = (e :: number) + 1
			end
			t.expect(guard ~= nil).toBe(true)
			t.expect(comment - (guard :: number) < 120).toBe(true)
			t.expect(has(beta, "--edit-last")).toBe(true)
			t.expect(has(beta, "--create-if-none")).toBe(true)
		end
	)

	it("passes untrusted PR text only through env, never into a command line", function()
		for _, bad in
			{ "pull_request.title", "pull_request.body", "head_ref", "head.ref", "github.event.comment" }
		do
			t.expect(has(text, bad)).toBe(false)
		end
	end)

	it("the gate job is unchanged in what it triggers on", function()
		t.expect(
			has(text, "if: github.event_name != 'pull_request' || github.event.pull_request.draft == false")
		)
			.toBe(true)
		t.expect(has(text, "fetch-depth: 0")).toBe(true)
	end)
end)
