--!strict
-- c0460: setup.sh's argument check and gate stage, run for real against a stub gate. The tools-only mode must skip
-- the gate only for `--tools`; every other way of running setup.sh must run `scripts/check.sh --full` and fail with it.
-- (tests/acceptance/c0140/tools.spec only reads the text; an extra skip condition would pass it.)
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local CASE_START = [[case "${1:-}" in]]
local STAGE_START = "if [[ ${1:-} == --tools ]]; then"
local GATE_CALL = "scripts/check.sh --full"

local function setupLines(): { string }
	local out = {}
	for line in string.gmatch(fs.readFile("scripts/setup.sh"), "[^\n]*") do
		table.insert(out, line)
	end
	return out
end

local function find(ls: { string }, text: string, from: number?): number
	for i = from or 1, #ls do
		if ls[i] == text then
			return i
		end
	end
	return 0
end

-- the argument check: from `case "${1:-}" in` to the next line that is exactly `esac`
local function argCheck(): string
	local ls = setupLines()
	local from = find(ls, CASE_START)
	local to = find(ls, "esac", from)
	t.expect(from > 0 and to > from).toBe(true)
	return table.concat(ls, "\n", from, to)
end

-- the gate stage: from the `--tools` test to the gate call
local function stage(): (string, number, number)
	local ls = setupLines()
	local from = find(ls, STAGE_START)
	local to = find(ls, GATE_CALL, from)
	t.expect(from > 0 and to > from).toBe(true)
	return table.concat(ls, "\n", from, to), from, to
end

-- runs `body` the way setup.sh does (set -euo pipefail, its `say`) with the given positional args and env, in a dir
-- holding a stub scripts/check.sh that prints GATE-RAN with its arguments and exits with `gateExit`
local function run(body: string, args: string, env: string, gateExit: number?): (boolean, number, string)
	local script = table.concat({
		"set -euo pipefail",
		[[say() { printf '\n== %s\n' "$1"; }]],
		[[d=$(mktemp -d); mkdir "$d/scripts"]],
		`printf '#!/usr/bin/env bash\necho "GATE-RAN $*"\nexit {gateExit or 0}\n' > "$d/scripts/check.sh"; chmod +x "$d/scripts/check.sh"`,
		[[cd "$d"]],
		"unset CI PICKMAN_SKIP_GATE",
		env,
		`set -- {args}`,
		body,
	}, "\n")
	local r = process.exec("bash", { "-c", script })
	return r.ok, r.code, r.stdout .. r.stderr
end

local function has(text: string, token: string): boolean
	return string.find(text, token, 1, true) ~= nil
end

return t.spec("c0460 setup.sh tools-only mode", function(it)
	it("no argument runs the gate with --full", function()
		local ok, _, out = run(stage(), "", "")
		t.expect(ok).toBe(true)
		t.expect(has(out, "GATE-RAN --full")).toBe(true)
	end)

	it("--tools skips the gate and says so", function()
		local ok, _, out = run(stage(), "--tools", "")
		t.expect(ok).toBe(true)
		t.expect(has(out, "GATE-RAN")).toBe(false)
		t.expect(has(out, "tools only: gate skipped")).toBe(true)
	end)

	it("only --tools skips it: CI, and a PICKMAN_SKIP_GATE variable, do not", function()
		for _, env in
			{ "export CI=true", "export CI=1", "export PICKMAN_SKIP_GATE=1", "export GITHUB_ACTIONS=true" }
		do
			local ok, _, out = run(stage(), "", env)
			t.expect(ok).toBe(true)
			t.expect(has(out, "GATE-RAN --full")).toBe(true)
		end
	end)

	it("a failing gate fails the run", function()
		local ok, _, out = run(stage(), "", "", 3)
		t.expect(has(out, "GATE-RAN --full")).toBe(true)
		t.expect(ok).toBe(false)
	end)

	it("an unknown argument is refused with exit 2 before anything runs", function()
		local ok, code, out = run(argCheck(), "--bogus", "")
		t.expect(ok).toBe(false)
		t.expect(code).toBe(2)
		t.expect(has(out, "unknown argument")).toBe(true)
		local ok2 = run(argCheck(), "--tools", "")
		t.expect(ok2).toBe(true)
		local ok3 = run(argCheck(), "", "")
		t.expect(ok3).toBe(true)
	end)

	it(
		"the gate is called once, after the --tools test, and nothing else exits or changes shell options",
		function()
			local ls = setupLines()
			local _, from, to = stage()
			local calls = 0
			for i, l in ls do
				if string.find(l, "scripts/check.sh", 1, true) then
					calls += 1
					t.expect(i).toBe(to)
				end
				if string.sub(l, 1, 4) == "set " and l ~= "set -euo pipefail" then
					error(`setup.sh line {i} changes shell options: {l}`)
				end
				if string.find(l, "^%s*trap%s") then
					error(`setup.sh line {i} installs a trap: {l}`)
				end
				if string.find(l, "exit", 1, true) then
					-- die() (exit 1), the argument check (exit 2) and the tools-only branch (exit 0, inside the stage)
					local allowed = string.sub(l, 1, 4) == "die("
						or string.find(l, "exit 2", 1, true) ~= nil
						or (i > from and i < to and string.find(l, "exit 0", 1, true) ~= nil)
					if not allowed then
						error(`setup.sh line {i} exits somewhere unexpected: {l}`)
					end
				end
			end
			t.expect(calls).toBe(1)
		end
	)
end)
