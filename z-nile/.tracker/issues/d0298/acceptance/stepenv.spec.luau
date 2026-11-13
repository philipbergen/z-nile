--!strict
-- d0298 (E1): specs never run in a dispatched step's environment. `./zn dispatch` gives a model step its run state
-- (ZN_DISPATCH*, the publish broker, the real git and gh), the agent's credential and the z-nile/bin wrapper first on
-- PATH; a spec run started inside the step (an executor's gate, a check.sh, the post-landing net) inherited all of it,
-- so a fixture's `git push origin HEAD:main` hit the wrapper and a fixture's `./zn new` published through the real
-- broker. The runner's fence (`z-nile/tests/lib/fence.luau`) now unsets `fence.STEP_VARS` and drops every z-nile/bin
-- entry from PATH (`fence.stepPath`) before any spec starts; the gh credential was already fence.sh's to remove. The "this run" case is the end-to-end proof: d0298's
-- check.sh runs this file with a dispatched step's variables set. Reads only, except one folder under
-- .cache/d0298-stepenv (credential.agentEnv's empty gh configuration folder).
local credential = require("@znile/engine/credential")
local fence = require("@tests/lib/fence")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- this runs from z-nile's home; the checkout is its parent
local home = fixture.physical(".") :: string
local root = string.match(home, "^(.*)/[^/]+$") :: string

-- set on a step and handled without the list: fence.sh (pickman_fence) already unsets the gh tokens and the ssh agent,
-- points gh at an empty configuration folder, turns prompts off and replaces the git configuration entries; PATH is
-- fence.stepPath's; GH_PROMPT_DISABLED only turns prompts off
local FENCED: { [string]: boolean } = {
	PATH = true,
	GH_PROMPT_DISABLED = true,
	GH_TOKEN = true,
	GITHUB_TOKEN = true,
	GH_CONFIG_DIR = true,
	GIT_TERMINAL_PROMPT = true,
	SSH_AUTH_SOCK = true,
}
local function kept(name: string): boolean
	return FENCED[name] == true or string.match(name, "^GIT_CONFIG_") ~= nil
end

local function listed(): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, name in fence.STEP_VARS do
		out[name] = true
	end
	return out
end

-- the names the dispatcher's step environment table sets (`local env: { [string]: string } = {` in dispatcher.luau)
local function dispatcherNames(): { string }
	local text = fs.readFile(`{root}/z-nile/engine/dispatcher.luau`)
	local a = string.find(text, "local env: { [string]: string } = {\n", 1, true)
	assert(a, "the step environment table is not in dispatcher.luau")
	local body = string.match(text, "^(.-)\n\t}\n", a) :: string
	local names: { string } = {}
	for name in string.gmatch(body, "\n%s+([A-Z][A-Z0-9_]*) = ") do
		table.insert(names, name)
	end
	return names
end

return t.spec("d0298 a spec run never inherits a dispatched step's environment", function(it)
	it(
		"STEP_VARS names every variable a step's environment sets, that the fence does not already handle",
		function()
			local names = dispatcherNames()
			t.expect(#names >= 9).toBe(true) -- the reading found the table, not a stray brace
			local dir = `{home}/.cache/d0298-stepenv/gh`
			for name in credential.agentEnv({}, "not-a-token", dir) do
				table.insert(names, name)
			end
			local have = listed()
			local missing: { string } = {}
			for _, name in names do
				if not have[name] and not kept(name) then
					table.insert(missing, name)
				end
			end
			table.sort(missing)
			t.expect(table.concat(missing, " ")).toBe("")
			for _, name in
				{
					"ZN_DISPATCH",
					"ZN_PUBLISH_BROKER",
					"ZN_PUBLISH_TOKEN",
					"ZN_REAL_GIT",
					"ZN_REAL_GH",
					"ZN_AGENT_GH_TOKEN",
				}
			do
				t.expect(have[name]).toBe(true)
			end
		end
	)

	it("STEP_VARS spares what the runner and a fixture's ./zn need", function()
		for _, name in fence.STEP_VARS do
			t.expect(name == "ZN_TOP" or name == "ZN_CWD" or name == "PATH").toBe(false)
			t.expect(string.match(name, "^ZN_MEASURE") == nil).toBe(true)
			t.expect(string.match(name, "^GIT_") == nil).toBe(true)
			t.expect(FENCED[name] == nil).toBe(true) -- the fence's own handling stays its own
		end
	end)

	it("stepPath drops every z-nile/bin entry, from any checkout, and keeps the rest in order", function()
		t.expect(fence.stepPath("/a/z-nile/bin:/usr/bin:/b/w/z-nile/bin/:/c/z-nile/binx:/d/bin"))
			.toBe("/usr/bin:/c/z-nile/binx:/d/bin")
		t.expect(fence.stepPath("/usr/bin:/bin")).toBe("/usr/bin:/bin")
		t.expect(fence.stepPath("/x/z-nile/bin")).toBe("")
		t.expect(fence.stepPath("")).toBe("")
	end)

	it("this run carries none of a step's variables and no wrapper on PATH", function()
		for _, name in fence.STEP_VARS do
			t.expect(`{name}={process.env[name] or "<unset>"}`).toBe(`{name}=<unset>`)
		end
		-- and what the fence handles: no gh token, gh's configuration its empty folder
		for _, name in { "GH_TOKEN", "GITHUB_TOKEN" } do
			t.expect(`{name}={process.env[name] or "<unset>"}`).toBe(`{name}=<unset>`)
		end
		t.expect(string.match(process.env.GH_CONFIG_DIR or "", "/%.cache/gh%-none$") ~= nil).toBe(true)
		for entry in string.gmatch(process.env.PATH or "", "[^:]+") do
			t.expect(string.match(entry, "/z%-nile/bin/?$") == nil).toBe(true)
		end
	end)

	it("zz-test says the runner removes a dispatched step's environment", function()
		local text = fs.readFile(`{root}/z-nile/skills/zz-test/SKILL.md`)
		local section = string.match(text, "\n## Specs never touch the real repository\n(.-)\n## ") :: string
		t.expect(section ~= nil).toBe(true)
		t.expect(string.find(section, "dispatched step", 1, true) ~= nil).toBe(true)
		t.expect(string.find(section, "`fence.STEP_VARS`", 1, true) ~= nil).toBe(true)
		t.expect(string.find(section, "`z-nile/bin`", 1, true) ~= nil).toBe(true)
	end)
end)
