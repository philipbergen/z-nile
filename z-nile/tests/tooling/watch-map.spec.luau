--!strict
-- Capture, upkeep and the net, each driven through ./zn in a throwaway fixture.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local NEXT = "issue 1 fixture\nraft 1 fixture\n"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "RC1: fixture" true\nfinish\n'
local SPEC = "--!strict\nreturn {}\n"

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function zn(f: trackerfix.Fixture, args: { string }, env: { [string]: string }?)
	local r = trackerfix.tr(f, f.main, args, env)
	if not r.ok then
		error(`zn {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

return t.spec("the watch map is captured, rewritten and repaired", function(it)
	it("done writes a watch.txt of exactly the source files that issue changed", function()
		local f = trackerfix.new("watchmap-done", { ["z-nile/next"] = NEXT })
		fixture.git(f.main, { "remote", "remove", "origin" })
		write(
			f.main,
			"z-nile/check.sh",
			'#!/usr/bin/env bash\necho "args: $*" >> "$GATE_LOG"\nexit "${GATE_EXIT:-0}"\n'
		)
		process.exec("chmod", { "+x", `{f.main}/z-nile/check.sh` })
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-qm", "stub gate" })
		local issue =
			string.match(zn(f, { "new", "issue", "f", "alpha", "--project", "pickman" }), "(f%d%d%d%d)")
		t.expect(issue ~= nil).toBe(true)
		local id = issue :: string
		local raft = string.match(
			zn(f, { "new", "raft", "feature", "demo", id, "--single", "--project", "pickman" }),
			"(R%d%d%d%d)"
		) :: string
		local root = "pickman/.tracker"
		for _, doc in { `{root}/issues/{id}/{id}.md`, `{root}/rafts/{raft}/{raft}.md` } do
			local text = string.gsub(fs.readFile(`{f.main}/{doc}`), "design: draft", "design: ready")
			fs.writeFile(`{f.main}/{doc}`, text)
		end
		write(f.main, `{root}/issues/{id}/acceptance/alpha.spec.luau`, SPEC)
		write(f.main, `{root}/issues/{id}/check.sh`, CHECK)
		write(f.main, `{root}/rafts/{raft}/check.sh`, CHECK)
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-qm", "prep" })
		zn(f, { "start", raft })
		write(f.main, "pickman/src/shared/Logic/Maze/init.luau", "return {}\n")
		zn(f, { "commit", "-m", "maze", "--issue", id, "--time", "1" })
		write(f.main, `{root}/rafts/active/{raft}/review-001.md`, "# Review 001\n\nVerdict: approve\n")
		zn(f, { "commit", "-m", "review", "--time", "1" })
		zn(f, { "done", raft }, { PICKMAN_DONE_GATE = "1", GATE_LOG = `{f.base}/gate.log`, GATE_EXIT = "0" })
		local watch = fs.readFile(`{f.main}/pickman/tests/acceptance/{id}/watch.txt`)
		t.expect(watch).toBe("pickman/src/shared/Logic/Maze/init.luau\n")
	end)

	it("a rename rewrites the watch file in the same commit", function()
		local f = trackerfix.new("watchmap-rename", {
			["z-nile/next"] = NEXT,
			["pickman/src/Old.luau"] = "return {}\n",
			["pickman/tests/unit/old.spec.luau"] = SPEC,
			["pickman/tests/unit/old.watch.txt"] = "pickman/src/Old.luau\n",
		})
		fixture.git(f.main, { "remote", "remove", "origin" })
		local issue = string.match(
			zn(f, { "new", "issue", "f", "move", "--project", "pickman" }),
			"(f%d%d%d%d)"
		) :: string
		local raft = string.match(
			zn(f, { "new", "raft", "feature", "move", issue, "--single", "--project", "pickman" }),
			"(R%d%d%d%d)"
		) :: string
		local root = "pickman/.tracker"
		for _, doc in { `{root}/issues/{issue}/{issue}.md`, `{root}/rafts/{raft}/{raft}.md` } do
			fs.writeFile(
				`{f.main}/{doc}`,
				(string.gsub(fs.readFile(`{f.main}/{doc}`), "design: draft", "design: ready"))
			)
		end
		write(f.main, `{root}/issues/{issue}/check.sh`, CHECK)
		write(f.main, `{root}/rafts/{raft}/check.sh`, CHECK)
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-qm", "prep" })
		zn(f, { "start", raft })
		fixture.git(f.main, { "mv", "pickman/src/Old.luau", "pickman/src/New.luau" })
		zn(f, { "commit", "-m", "rename", "--issue", issue, "--time", "1" })
		local shown = fixture.git(f.main, { "show", "HEAD:pickman/tests/unit/old.watch.txt" })
		t.expect(shown).toBe("pickman/src/New.luau")
		local names = fixture.git(f.main, { "show", "--name-only", "--pretty=format:", "HEAD" })
		t.expect(has(names, "pickman/tests/unit/old.watch.txt")).toBe(true)
		t.expect(has(names, "New.luau")).toBe(true)
	end)

	it("watch-net extends the watch file onto main, and a second run finds nothing to do", function()
		local f = trackerfix.new("watchmap-net", {
			["z-nile/next"] = NEXT,
			["pickman/src/Other.luau"] = "return {}\n",
			["pickman/tests/unit/miss.spec.luau"] = SPEC,
			["pickman/tests/unit/miss.watch.txt"] = "pickman/src/Other.luau\n",
		})
		write(
			f.main,
			"z-nile/check.sh",
			'#!/usr/bin/env bash\necho "FAIL pickman/tests/unit/miss.spec.luau :: holds"\nexit 1\n'
		)
		process.exec("chmod", { "+x", `{f.main}/z-nile/check.sh` })
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-qm", "stub the suite" })
		local marked = fixture.git(f.main, { "rev-parse", "HEAD" })
		write(f.main, "z-nile/watch-passed", marked .. "\n")
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-qm", "the suite passed here" })
		write(f.main, "pickman/src/Plant.luau", "return {}\n")
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-qm", "plant a source the map misses" })
		write(f.main, "pickman/src/Second.luau", "return {}\n")
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-qm", "a second source since the last pass" })
		fixture.git(f.main, { "push", "-q", "origin", "HEAD:main" })
		local first = zn(f, { "watch-net" })
		t.expect(has(first, "pushed main")).toBe(true)
		fixture.git(f.main, { "fetch", "-q", "origin", "main" })
		local onMain = fixture.git(f.main, { "show", "origin/main:pickman/tests/unit/miss.watch.txt" })
		t.expect(onMain).toBe("pickman/src/Other.luau\npickman/src/Plant.luau\npickman/src/Second.luau")
		local listed =
			fixture.git(f.main, { "grep", "-l", "pickman/tests/unit/miss.spec.luau", "origin/main" })
		t.expect(has(listed, ".md")).toBe(true)
		local second = zn(f, { "watch-net" })
		t.expect(has(second, "nothing to do")).toBe(true)
	end)

	it("done writes a sidecar for a unit spec, and a later edit of its source selects it", function()
		local f = trackerfix.new("watchmap-unit", { ["z-nile/next"] = NEXT })
		fixture.git(f.main, { "remote", "remove", "origin" })
		write(
			f.main,
			"z-nile/check.sh",
			'#!/usr/bin/env bash\necho "args: $*" >> "$GATE_LOG"\nexit "${GATE_EXIT:-0}"\n'
		)
		process.exec("chmod", { "+x", `{f.main}/z-nile/check.sh` })
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-qm", "stub gate" })
		local issue =
			string.match(zn(f, { "new", "issue", "f", "unit", "--project", "pickman" }), "(f%d%d%d%d)")
		local id = issue :: string
		local raft = string.match(
			zn(f, { "new", "raft", "feature", "unit", id, "--single", "--project", "pickman" }),
			"(R%d%d%d%d)"
		) :: string
		local root = "pickman/.tracker"
		for _, doc in { `{root}/issues/{id}/{id}.md`, `{root}/rafts/{raft}/{raft}.md` } do
			fs.writeFile(
				`{f.main}/{doc}`,
				(string.gsub(fs.readFile(`{f.main}/{doc}`), "design: draft", "design: ready"))
			)
		end
		write(f.main, `{root}/issues/{id}/acceptance/alpha.spec.luau`, SPEC)
		write(f.main, `{root}/issues/{id}/check.sh`, CHECK)
		write(f.main, `{root}/rafts/{raft}/check.sh`, CHECK)
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-qm", "prep" })
		zn(f, { "start", raft })
		write(f.main, "pickman/src/shared/Logic/Maze/init.luau", "return {}\n")
		write(f.main, "pickman/tests/unit/added.spec.luau", SPEC)
		zn(f, { "commit", "-m", "maze", "--issue", id, "--time", "1" })
		write(f.main, `{root}/rafts/active/{raft}/review-001.md`, "# Review 001\n\nVerdict: approve\n")
		zn(f, { "commit", "-m", "review", "--time", "1" })
		zn(f, { "done", raft }, { PICKMAN_DONE_GATE = "1", GATE_LOG = `{f.base}/gate.log`, GATE_EXIT = "0" })
		local watch = fs.readFile(`{f.main}/pickman/tests/unit/added.watch.txt`)
		t.expect(has(watch, "pickman/src/shared/Logic/Maze/init.luau")).toBe(true)
		local selected = fixture.exec(
			f.main,
			"lune",
			{ "run", "z-nile/affected", "--", "pickman/src/shared/Logic/Maze/init.luau" }
		)
		if not selected.ok then
			error(`affected failed ({selected.code}): {selected.stderr}{selected.stdout}`, 0)
		end
		t.expect(has(selected.stdout, "pickman/tests/unit/added.spec.luau")).toBe(true)
	end)

	it("watch-check names a spec with no watch file and an empty one", function()
		local f = trackerfix.new("watchmap-check", { ["z-nile/next"] = NEXT })
		write(f.main, "pickman/tests/unit/bare.spec.luau", SPEC)
		local missing = fixture.exec(f.main, "lune", { "run", "z-nile/watch-check" })
		t.expect(missing.ok).toBe(false)
		t.expect(has(missing.stderr, "pickman/tests/unit/bare.spec.luau has no watch file")).toBe(true)
		write(f.main, "pickman/tests/unit/bare.watch.txt", "")
		local empty = fixture.exec(f.main, "lune", { "run", "z-nile/watch-check" })
		t.expect(empty.ok).toBe(false)
		t.expect(has(empty.stderr, "pickman/tests/unit/bare.watch.txt is empty")).toBe(true)
	end)

	it("a landing starts the net, and the repair is on main", function()
		local f = trackerfix.new("watchmap-land", {
			["z-nile/next"] = NEXT,
			["pickman/src/Other.luau"] = "return {}\n",
			["pickman/tests/unit/miss.spec.luau"] = SPEC,
			["pickman/tests/unit/miss.watch.txt"] = "pickman/src/Other.luau\n",
		})
		write(
			f.main,
			"z-nile/check.sh",
			'#!/usr/bin/env bash\necho "FAIL pickman/tests/unit/miss.spec.luau :: holds"\nexit 1\n'
		)
		process.exec("chmod", { "+x", `{f.main}/z-nile/check.sh` })
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-qm", "stub the suite" })
		local marked = fixture.git(f.main, { "rev-parse", "HEAD" })
		write(f.main, "z-nile/watch-passed", marked .. "\n")
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-qm", "the suite passed here" })
		write(f.main, "pickman/src/Plant.luau", "return {}\n")
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-qm", "plant a source the map misses" })
		fixture.git(f.main, { "push", "-q", "origin", "HEAD:main" })
		local printed = zn(f, { "worktree", "capture-net" })
		local wt = printed
		for line in string.gmatch(printed, "[^\n]+") do
			wt = line
		end
		fixture.git(wt, { "config", "user.name", "watchmap-land" })
		fixture.git(wt, { "config", "user.email", "watchmap-land@example.invalid" })
		local made = trackerfix.tr(f, wt, {
			"new",
			"issue",
			"c",
			"landed",
			"--desc",
			"First line.",
			"--project",
			"pickman",
		})
		if not made.ok then
			error(`new failed ({made.code}): {made.stderr}{made.stdout}`, 0)
		end
		local id = string.match(made.stdout, "(c%d%d%d%d)") :: string
		local doc = `{wt}/pickman/.tracker/issues/{id}/{id}.md`
		fs.writeFile(doc, fs.readFile(doc) .. "\nMore about landed.\n")
		fixture.git(wt, { "add", "pickman/.tracker" })
		fixture.git(wt, { "commit", "-qm", "capture the issue" })
		local landed = trackerfix.tr(f, wt, { "land" }, {
			PICKMAN_LAND_GATE = "true",
			PICKMAN_WATCH_NET = "on",
		})
		if not landed.ok then
			error(`land failed ({landed.code}): {landed.stderr}{landed.stdout}`, 0)
		end
		t.expect(has(landed.stdout, "watch-net: started, log at .cache/watch-net.log")).toBe(true)
		local onMain = ""
		for _ = 1, 40 do
			process.exec("sleep", { "1" })
			fixture.git(f.main, { "fetch", "-q", "origin", "main" })
			local show = process.exec(
				"git",
				{ "show", "origin/main:pickman/tests/unit/miss.watch.txt" },
				{ cwd = f.main }
			)
			if show.ok and string.find(show.stdout, "pickman/src/Plant.luau", 1, true) then
				onMain = show.stdout
				break
			end
		end
		if onMain == "" then
			local log = ""
			local logPath = `{wt}/.cache/watch-net.log`
			if fs.isFile(logPath) then
				log = fs.readFile(logPath)
			end
			error(`the landing's net did not repair main\n{log}`, 0)
		end
		t.expect(has(onMain, "pickman/src/Plant.luau")).toBe(true)
	end)
end)
