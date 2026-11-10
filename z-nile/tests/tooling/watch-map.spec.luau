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

	it("watch-net extends the watch file, captures a defect, and a second run finds nothing to do", function()
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
		write(f.main, "pickman/src/Plant.luau", "return {}\n")
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-qm", "plant a source the map misses" })
		fixture.git(f.main, { "push", "-q", "origin", "HEAD:main" })
		local first = zn(f, { "watch-net" })
		t.expect(has(first, "pushed watch-net")).toBe(true)
		local watch = fs.readFile(`{f.base}/main/.worktree/watch-net/pickman/tests/unit/miss.watch.txt`)
		t.expect(watch).toBe("pickman/src/Other.luau\npickman/src/Plant.luau\n")
		local listed = fixture.git(f.main, { "grep", "-l", "pickman/tests/unit/miss.spec.luau", "watch-net" })
		t.expect(has(listed, ".md")).toBe(true)
		local second = zn(f, { "watch-net" })
		t.expect(has(second, "nothing to do")).toBe(true)
	end)
end)
