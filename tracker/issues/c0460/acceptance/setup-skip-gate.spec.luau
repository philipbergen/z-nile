--!strict
-- c0460: setup.sh runs the full gate by default, and skips it only when PICKMAN_SKIP_GATE is non-empty.
-- The final stage is cut out of setup.sh and run against a stub gate, so an inverted or broken guard fails.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local START = "if [[ -n ${PICKMAN_SKIP_GATE:-} ]]; then"

local function setupLines(): { string }
	local out = {}
	for line in string.gmatch(fs.readFile("scripts/setup.sh"), "[^\n]*") do
		table.insert(out, line)
	end
	return out
end

-- the block from START to the next line that is exactly `fi`, and the line numbers it spans
local function stage(): (string, number, number)
	local ls = setupLines()
	local from, to = 0, 0
	for i, l in ls do
		if from == 0 and l == START then
			from = i
		elseif from > 0 and l == "fi" then
			to = i
			break
		end
	end
	t.expect(from > 0 and to > from).toBe(true)
	return table.concat(ls, "\n", from, to), from, to
end

-- runs the stage the way setup.sh does (set -euo pipefail, its `say`), in a dir holding a stub scripts/check.sh
local function run(assign: string): (boolean, string)
	local script = table.concat({
		"set -euo pipefail",
		[[say() { printf '\n== %s\n' "$1"; }]],
		[[d=$(mktemp -d); mkdir "$d/scripts"]],
		[[printf '#!/usr/bin/env bash\necho GATE-RAN\n' > "$d/scripts/check.sh"; chmod +x "$d/scripts/check.sh"]],
		[[cd "$d"]],
		assign,
		(stage()),
	}, "\n")
	local r = process.exec("bash", { "-c", script })
	return r.ok, r.stdout
end

local function has(text: string, token: string): boolean
	return string.find(text, token, 1, true) ~= nil
end

return t.spec("c0460 setup.sh gate skip", function(it)
	it("the gate runs when the variable is unset", function()
		local ok, out = run("unset PICKMAN_SKIP_GATE")
		t.expect(ok).toBe(true)
		t.expect(has(out, "GATE-RAN")).toBe(true)
	end)

	it("the gate runs when the variable is empty", function()
		local ok, out = run("export PICKMAN_SKIP_GATE=")
		t.expect(ok).toBe(true)
		t.expect(has(out, "GATE-RAN")).toBe(true)
	end)

	it("the gate is skipped, and says so, when the variable is set", function()
		local ok, out = run("export PICKMAN_SKIP_GATE=1")
		t.expect(ok).toBe(true)
		t.expect(has(out, "GATE-RAN")).toBe(false)
		t.expect(has(out, "gate (skipped")).toBe(true)
	end)

	it("no scripts/check.sh call sits outside the guarded stage", function()
		local ls = setupLines()
		local _, from, to = stage()
		for i, l in ls do
			if (i < from or i > to) and string.find(l, "scripts/check.sh", 1, true) then
				error(`setup.sh line {i} calls the gate outside the guard: {l}`)
			end
		end
	end)

	it("no workflow other than board.yml sets PICKMAN_SKIP_GATE", function()
		for _, name in fs.readDir(".github/workflows") do
			if name ~= "board.yml" then
				t.expect(has(fs.readFile(".github/workflows/" .. name), "PICKMAN_SKIP_GATE")).toBe(false)
			end
		end
	end)

	it("documents the variable in SETUP.md", function()
		t.expect(has(fs.readFile("SETUP.md"), "PICKMAN_SKIP_GATE")).toBe(true)
	end)
end)
