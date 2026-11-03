--!strict
-- c0191 AC6: the rule is written in the same words everywhere it is restated, the call sites that run the reaper are in
-- place, and every exhaustive list a new command joins names it. These read the checkout's own files as text.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(rel: string): string
	local path = `{ROOT}/{rel}`
	if not fs.isFile(path) then
		error(`{rel} is missing`, 0)
	end
	return fs.readFile(path)
end

local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

-- The rule, word for word, in every place that restates it (z-design/restated-rules-move-together)
local RULE =
	"Run every probe, experiment, loop and background command you start yourself (anything that is not the gate, a check, a `./zn` command or the spec runner) through `./zn run --time <seconds> -- <command>`: it stops at its limit, when it ends and when you do."

local PLACES = {
	"AGENTS.md",
	"z-nile/skills/zz-test/SKILL.md",
	"z-nile/skills/z-design/SKILL.md",
	"z-nile/skills/zz-execute/SKILL.md",
	"z-nile/skills/zz-review/SKILL.md",
}

return t.spec("the rule and its call sites", function(it)
	it(
		"AC6: AGENTS.md, zz-test and zz-execute say plainly that a /clear ends the cleared conversation's background commands",
		function()
			local clear =
				"A `/clear` ends the background commands of the conversation it clears (the SessionEnd hook stops its tool shells)."
			for _, rel in
				{ "AGENTS.md", "z-nile/skills/zz-test/SKILL.md", "z-nile/skills/zz-execute/SKILL.md" }
			do
				if not has(read(rel), clear) then
					error(`{rel} does not carry the /clear sentence`, 0)
				end
			end
		end
	)

	it("AC6: AGENTS.md and zz-test say what a subagent's command does", function()
		local sentence =
			"A subagent stays open while its background commands run, and a command it started stops at its own `./zn run` limit (at most an hour) or at the session's end; the session-end reaper catches anything left."
		for _, rel in { "AGENTS.md", "z-nile/skills/zz-test/SKILL.md" } do
			if not has(read(rel), sentence) then
				error(`{rel} does not carry the subagent sentence`, 0)
			end
		end
	end)

	it("AC6: every place that restates the rule says it in the same words", function()
		for _, rel in PLACES do
			if not has(read(rel), RULE) then
				error(`{rel} does not carry the bounded-command rule word for word`, 0)
			end
		end
	end)

	it(
		"AC6: the old recipe is gone: no skill or lesson tells anyone to run a command under an alarm",
		function()
			local lesson = read("z-nile/skills/z-design/lessons/probe-free-cli-lines-in-prep.md")
			t.expect(has(lesson, "under an alarm")).toBe(false)
			t.expect(has(lesson, "./zn run")).toBe(true)
			for _, rel in PLACES do
				t.expect(has(read(rel), "exec @ARGV")).toBe(false)
			end
		end
	)

	it(
		"AC6: zz-test names the runner, the hook, the reaper and the spec runner's CPU limit under one heading",
		function()
			local text = read("z-nile/skills/zz-test/SKILL.md")
			local at = string.find(text, "## Bounded commands", 1, true)
			t.expect(at ~= nil).toBe(true)
			local section = string.sub(text, at :: number)
			for _, part in
				{
					"./zn run",
					"--time",
					"--cpu",
					"z-nile/lib/bounded.pl",
					"scripts/hooks/pre-bash.sh",
					"z-nile/engine/boundcmd.luau",
					"./zn reap",
					"scripts/hooks/session-end.sh",
					"PICKMAN_SPEC_CPU",
					"ulimit -t",
					"SIGXCPU",
					"fails open",
				}
			do
				if not has(section, part) then
					error(`zz-test's Bounded commands section does not mention {part}`, 0)
				end
			end
		end
	)

	it(
		"AC6: zz-review checks that probes and experiments were bounded in design mode and in code mode",
		function()
			local text = read("z-nile/skills/zz-review/SKILL.md")
			local design = string.find(text, "## Design mode", 1, true)
			local stream = string.find(text, "## Stream mode", 1, true)
			local code = string.find(text, "## Code mode", 1, true)
			local lessons = string.find(text, "\n## Lessons", 1, true)
			t.expect(design ~= nil and stream ~= nil and code ~= nil and lessons ~= nil).toBe(true)
			t.expect(has(string.sub(text, design :: number, stream :: number), "**Bounded commands**"))
				.toBe(true)
			t.expect(has(string.sub(text, code :: number, lessons :: number), "**Bounded commands**"))
				.toBe(true)
			t.expect(has(string.sub(text, stream :: number, code :: number), "**Bounded commands**"))
				.toBe(false)
		end
	)

	it(
		"AC6: ./zn reap runs at the start of the gate, before its first stage and never in --plan mode",
		function()
			local gate = read("z-nile/check.sh")
			local reap = string.find(gate, "reap --auto", 1, true)
			local stages = string.find(gate, "source z-nile/lib/par.sh", 1, true)
			t.expect(reap ~= nil and stages ~= nil and (reap :: number) < (stages :: number)).toBe(true)
			local line = string.match(gate, "[^\n]*reap %-%-auto[^\n]*") or ""
			t.expect(string.match(line, "^%s*#")).toBe(nil) -- a commented-out call is no call
			t.expect(has(line, "[[ -n $plan ]] || ")).toBe(true) -- skipped in --plan mode
			t.expect(has(line, "|| true")).toBe(true) -- never a reason for the gate to fail
		end
	)

	it("AC6: ./zn sync runs the reaper, through the same --auto path, before it fetches", function()
		-- the body of the sync command, wherever the engine keeps it: main.luau today, z-nile/engine/cmd/sync.luau after c0180
		local body: string
		if fs.isFile(`{ROOT}/z-nile/engine/cmd/sync.luau`) then
			body = read("z-nile/engine/cmd/sync.luau")
		else
			local main = read("z-nile/engine/main.luau")
			local at = string.find(main, "function cmd.sync(", 1, true)
			t.expect(at ~= nil).toBe(true)
			body = string.sub(main, at :: number, string.find(main, "\nend\n", at :: number, true) or #main)
		end
		body = string.gsub(body, "%-%-[^\n]*", "") -- a commented call is no call
		local call = string.find(body, "reapAuto()", 1, true) or string.find(body, "reap --auto", 1, true)
		local fetch = string.find(body, "fetch", 1, true)
		t.expect(call ~= nil and fetch ~= nil and (call :: number) < (fetch :: number)).toBe(true)
		-- and the call is the --auto one: defined somewhere in the engine, asking the guards quietly
		local engine = ""
		local function walk(rel: string)
			for _, name in fs.readDir(`{ROOT}/{rel}`) do
				if fs.isDir(`{ROOT}/{rel}/{name}`) then
					walk(`{rel}/{name}`)
				elseif string.match(name, "%.luau$") then
					engine ..= fs.readFile(`{ROOT}/{rel}/{name}`) .. "\n"
				end
			end
		end
		walk("z-nile/engine")
		t.expect(has(engine, '["--auto"]')).toBe(true)
		t.expect(has(engine, "guarded(true)")).toBe(true)
		-- the reaper takes its scope from the pure function the spec exercises, not from a copy of it
		t.expect(has(engine, "reapLib.scope(")).toBe(true)
	end)

	it(
		"AC6: the usage text and the lists of commands allowed in the main checkout name both commands",
		function()
			local main = read("z-nile/engine/main.luau")
			t.expect(has(main, "  run [--time S] [--cpu S] -- <command>")).toBe(true)
			t.expect(has(main, "  reap [--dry-run]")).toBe(true)
			-- not in READ_ONLY: it runs the repository guard like every command that is not read-only (tracker-guarded.spec)
			t.expect(has(main, "\treap = true,")).toBe(false)
			local rules = read("z-nile/skills/zz-rules/SKILL.md")
			local main1 = string.match(
				rules,
				"The complete list of commands that may run there:.-\n   The tracker enforces"
			) or ""
			t.expect(has(main1, "`reap`")).toBe(true)
			t.expect(has(main1, "`run`")).toBe(true)
			-- ./zn run may run, in the read-only main checkout, only a command that is allowed there itself
			t.expect(has(main1, "only a command that is itself allowed there")).toBe(true)
			local other = string.match(rules, "## Other commands.-## Sync and claim") or ""
			t.expect(has(other, "./zn run")).toBe(true)
			t.expect(has(other, "./zn reap")).toBe(true)
		end
	)

	it(
		"AC6: a Lune entry the gate runs joins the hook's list, and agents are told to wrap what the hook refuses",
		function()
			local arch = read("z-nile/skills/zz-arch/SKILL.md")
			t.expect(has(arch, "joins `TOOLING` in `z-nile/engine/boundcmd.luau`")).toBe(true)
			local test = read("pickman/skills/pickman-test/SKILL.md")
			t.expect(has(test, "./zn run --time")).toBe(true)
			t.expect(has(test, "lune run scripts/runtime-test")).toBe(true)
			-- the merge's final check runs scripts/cicd, which the hook refuses bare
			t.expect(
				has(read("z-nile/skills/zz-rules/SKILL.md"), "./zn run --time 1800 -- lune run scripts/cicd")
			)
				.toBe(true)
		end
	)

	it("AC6: zz-arch's layout lists the new files, and zz-test's hooks list names both hooks", function()
		local arch = read("z-nile/skills/zz-arch/SKILL.md")
		for _, part in
			{
				"z-nile/lib/bounded.pl",
				"z-nile/lib/cpu.sh",
				"z-nile/engine/reap.luau",
				"z-nile/engine/boundcmd.luau",
				"z-nile/guard-bash.luau",
			}
		do
			if not has(arch, part) then
				error(`zz-arch does not list {part}`, 0)
			end
		end
		local test = read("z-nile/skills/zz-test/SKILL.md")
		local hooks = string.match(test, "## Hooks %(Claude Code only%).-\n## ") or ""
		t.expect(has(hooks, "PreToolUse")).toBe(true)
		t.expect(has(hooks, "SessionEnd")).toBe(true)
	end)
end)
