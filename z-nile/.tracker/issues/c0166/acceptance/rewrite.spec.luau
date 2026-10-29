--!strict
-- c0166 AC4: a later source with an unchanged check is refused; metrics lists recurrence.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local lessons = require("@znile/engine/lessons")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local api = lessons :: any
local f: any
local PIN = "z-nile/skills/zz-test/lessons/pin.md"
local FRESH = "z-nile/skills/zz-test/lessons/fresh.md"
local HARVEST = "z-nile/.tracker/issues/active/c0001/harvest.md"

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function lesson(check: string): string
	return `---\ntitle: A lesson\nwhen: build\ntags: [wiring]\ncheck: {check}\nfrom: user 2026-10-26: said so\n---\nBody.\n`
end

local function item(id: string, kind: string, slug: string, raftId: string): string
	local issues = if kind == "raft" then "issues: [c0001]\n" else ""
	local raft = if kind == "raft" then "" else `raft: {raftId}\n`
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {slug}\n{raft}{issues}depends_on: []\nemergent: false\n`
		.. `design: ready\ncreated: 2026-10-26\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n`
end

local function run(args: { string })
	return trackerfix.tr(f, f.main, args)
end

local function commit(message: string)
	return run({ "commit", "-m", message, "--time", "1" })
end

return t.spec("c0166 rewrite", function(it)
	it("needsRewrite and laterCount", function()
		t.expect(api.staleSource ~= nil).toBe(true)
		t.expect(api.staleSource(true, true, false)).toBe(true)
		t.expect(api.staleSource(false, true, false)).toBe(false)
		t.expect(api.staleSource(true, false, false)).toBe(false)
		t.expect(api.staleSource(true, true, true)).toBe(false)
		t.expect(api.recurred(true, false)).toBe(true)
		t.expect(api.recurred(false, false)).toBe(false)
		t.expect(api.recurred(true, true)).toBe(false)
		t.expect(api.laterCount(0)).toBe(0)
		t.expect(api.laterCount(1)).toBe(0)
		t.expect(api.laterCount(2)).toBe(1)
	end)

	it("sets up an active raft whose lesson already has its first source", function()
		f = trackerfix.new("c0166-rewrite", {
			[PIN] = lesson("Is the old check specific?"),
			["z-nile/.tracker/rafts/active/R0001/R0001.md"] = item("R0001", "raft", "lessons", ""),
			["z-nile/.tracker/issues/active/c0001/c0001.md"] = item("c0001", "issue", "c0001", "R0001"),
			["z-nile/lesson-areas.md"] = "core: review\nwiring: @skill\n",
		}, { noLessons = true })
		fixture.git(f.main, { "checkout", "-q", "-b", "R0001-lessons" })
	end)

	it("second source", function()
		fs.writeFile(`{f.main}/{HARVEST}`, "- design-review-001 F1: zz-test/pin\n")
		local r = commit("second source")
		t.expect(r.code).toBe(1)
		t.expect(has(r.stderr, "commit: zz-test/pin gained a source and its check line did not change"))
			.toBe(true)
		t.expect(fixture.git(f.main, { "log", "-1", "--format=%s" })).toBe("seed")
	end)

	it("a changed check line commits", function()
		local path = `{f.main}/{PIN}`
		local text = fs.readFile(path)
		fs.writeFile(path, (string.gsub(text, "Is the old check specific%?", "Is the new check specific?")))
		local r = commit("rewrite the check")
		if r.code ~= 0 then
			error(`exit {r.code}\n{r.stderr}{r.stdout}`, 0)
		end
		t.expect(fixture.git(f.main, { "log", "-1", "--format=%s" })).toBe("rewrite the check")
	end)

	it("metrics since check", function()
		local r = run({ "metrics" })
		if r.code ~= 0 then
			error(`exit {r.code}\n{r.stderr}{r.stdout}`, 0)
		end
		t.expect(has(r.stdout, "zz-test/pin: later 1, since check 0")).toBe(true)
	end)

	it("a one-off does not refuse", function()
		local path = `{f.main}/{HARVEST}`
		fs.writeFile(path, fs.readFile(path) .. "- review-001 F2: one-off: a typo in the plan\n")
		local r = commit("one-off")
		if r.code ~= 0 then
			error(`exit {r.code}\n{r.stderr}{r.stdout}`, 0)
		end
	end)

	it("uncovered reports a plain commit", function()
		local path = `{f.main}/{HARVEST}`
		fs.writeFile(path, fs.readFile(path) .. "- design-review-002 F1: zz-test/pin\n")
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-q", "-m", "plain later source" })
		local r = run({ "lessons", "--uncovered", "c0001" })
		t.expect(r.code).toBe(1)
		t.expect(has(r.stdout .. r.stderr, "zz-test/pin gained a source and its check line did not change"))
			.toBe(true)
		local metrics = run({ "metrics" })
		t.expect(has(metrics.stdout, "zz-test/pin: later 2, since check 1")).toBe(true)
	end)

	it("recurrence sorts by later then id", function()
		local function add(id: string, check: string)
			fs.writeFile(`{f.main}/z-nile/skills/zz-test/lessons/{id}.md`, lesson(check))
		end
		add("aaa", "Is the aaa check specific?")
		add("zzz", "Is the zzz check specific?")
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-q", "-m", "introduce aaa and zzz" })
		local path = `{f.main}/{HARVEST}`
		fs.writeFile(
			path,
			fs.readFile(path) .. "- design-review-003 F1: zz-test/aaa\n- design-review-003 F2: zz-test/zzz\n"
		)
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-q", "-m", "two later ones" })
		local metrics = run({ "metrics" })
		local section = metrics.stdout
		local pinAt = string.find(section, "zz-test/pin: later 2, since check 1", 1, true)
		local aaaAt = string.find(section, "zz-test/aaa: later 1, since check 1", 1, true)
		local zzzAt = string.find(section, "zz-test/zzz: later 1, since check 1", 1, true)
		t.expect(pinAt ~= nil and aaaAt ~= nil and zzzAt ~= nil and pinAt < aaaAt and aaaAt < zzzAt)
			.toBe(true)
	end)

	it("a lesson that does not parse", function()
		local g = trackerfix.new("c0166-rewrite-bad", {
			["z-nile/lesson-areas.md"] = "core: review\nwiring: @skill\n",
			["z-nile/.tracker/rafts/active/R0001/R0001.md"] = item("R0001", "raft", "lessons", ""),
			["z-nile/.tracker/issues/active/c0001/c0001.md"] = item("c0001", "issue", "c0001", "R0001"),
		}, { noLessons = true })
		fixture.git(g.main, { "checkout", "-q", "-b", "R0001-lessons" })
		fs.writeDir(`{g.main}/z-nile/skills/zz-test/lessons`)
		fs.writeFile(
			`{g.main}/z-nile/skills/zz-test/lessons/bad.md`,
			"---\ntitle: Bad\nwhen: never\ntags: [wiring]\ncheck: Is the bad check specific?\n---\nBody.\n"
		)
		fixture.git(g.main, { "add", "-A" })
		fixture.git(g.main, { "commit", "-q", "-m", "bad lesson" })
		local stale = trackerfix.tr(g, g.main, { "lessons", "--stale" })
		t.expect(stale.code).toBe(1)
		t.expect(has(stale.stdout .. stale.stderr, "zz-test/bad does not parse")).toBe(true)
		local refused = trackerfix.tr(g, g.main, { "commit", "-m", "bad stays", "--time", "1" })
		t.expect(refused.code).toBe(1)
		t.expect(has(refused.stderr, "commit: zz-test/bad does not parse")).toBe(true)
	end)

	it("a merged main source is not stale", function()
		local g = trackerfix.new("c0166-rewrite-merge", {
			[PIN] = lesson("Is the old check specific?"),
			["z-nile/.tracker/issues/c0001/c0001.md"] = item("c0001", "issue", "c0001", ""),
			["z-nile/.tracker/issues/c0001/harvest.md"] = "- design-review-001 F1: zz-test/pin\n",
			["z-nile/lesson-areas.md"] = "core: review\nwiring: @skill\n",
		}, { noLessons = true })
		local doc = `{g.main}/z-nile/.tracker/issues/c0001/c0001.md`
		fs.writeFile(doc, fs.readFile(doc) .. "\nA local note.\n")
		fixture.git(g.main, { "add", "-A" })
		fixture.git(g.main, { "commit", "-q", "-m", "local note" })
		local harvest = fs.readFile(`{g.main}/z-nile/.tracker/issues/c0001/harvest.md`)
		trackerfix.elsewhere(g, {
			["z-nile/.tracker/issues/c0001/harvest.md"] = harvest .. "- design-review-002 F1: zz-test/pin\n",
		}, "main adds a source")
		fixture.git(g.main, { "fetch", "-q", "origin" })
		fixture.git(g.main, { "merge", "-q", "origin/main" })
		local merged = fs.readFile(`{g.main}/z-nile/.tracker/issues/c0001/harvest.md`)
		t.expect(has(merged, "design-review-002 F1")).toBe(true)
		local parents = fixture.git(g.main, { "log", "-1", "--format=%P" })
		t.expect(string.find(parents, " ", 1, true) ~= nil).toBe(true)
		local r = trackerfix.tr(g, g.main, { "lessons", "--uncovered", "c0001" })
		t.expect(has(r.stdout .. r.stderr, "gained a source")).toBe(false)
		t.expect(r.code).toBe(0)
	end)

	it("introducing commit", function()
		local g = trackerfix.new("c0166-rewrite-fresh", {
			["z-nile/lesson-areas.md"] = "core: review\nwiring: @skill\n",
			["z-nile/.tracker/rafts/active/R0001/R0001.md"] = item("R0001", "raft", "lessons", ""),
			["z-nile/.tracker/issues/active/c0001/c0001.md"] = item("c0001", "issue", "c0001", "R0001"),
			["z-nile/.tracker/issues/active/c0001/harvest.md"] = "",
		}, { noLessons = true })
		fixture.git(g.main, { "checkout", "-q", "-b", "R0001-lessons" })
		fs.writeDir(`{g.main}/z-nile/skills/zz-test/lessons`)
		fs.writeFile(`{g.main}/{FRESH}`, lesson("Is the fresh check specific?"))
		fs.writeFile(`{g.main}/{HARVEST}`, "- design-review-001 F3: zz-test/fresh\n")
		local r = trackerfix.tr(g, g.main, { "commit", "-m", "introduce fresh", "--time", "1" })
		if r.code ~= 0 then
			error(`exit {r.code}\n{r.stderr}{r.stdout}`, 0)
		end
	end)

	it("no origin skips the stale check", function()
		local g = trackerfix.new("c0166-rewrite-noremote", {
			[PIN] = lesson("Is the old check specific?"),
			["z-nile/lesson-areas.md"] = "core: review\nwiring: @skill\n",
			["z-nile/.tracker/rafts/active/R0001/R0001.md"] = item("R0001", "raft", "lessons", ""),
			["z-nile/.tracker/issues/active/c0001/c0001.md"] = item("c0001", "issue", "c0001", "R0001"),
		}, { noLessons = true })
		fixture.git(g.main, { "checkout", "-q", "-b", "R0001-lessons" })
		fixture.git(g.main, { "remote", "remove", "origin" })
		fs.writeFile(`{g.main}/{HARVEST}`, "- design-review-001 F1: zz-test/pin\n")
		local r = trackerfix.tr(g, g.main, { "commit", "-m", "no remote", "--time", "1" })
		if r.code ~= 0 then
			error(`exit {r.code}\n{r.stderr}{r.stdout}`, 0)
		end
		t.expect(has(r.stderr, "warning: no origin; stale check skipped")).toBe(true)
	end)

	it("a missing merge base fails closed", function()
		fixture.git(f.main, { "update-ref", "-d", "refs/remotes/origin/main" })
		local stale = run({ "lessons", "--stale" })
		t.expect(stale.code).toBe(1)
		t.expect(has(stale.stderr, "no merge base origin/main")).toBe(true)
		local refused = commit("no base")
		t.expect(refused.code).toBe(1)
		t.expect(has(refused.stderr, "no merge base origin/main")).toBe(true)
	end)

	it("a source from before the area file", function()
		local g = trackerfix.new("c0166-rewrite-before", {
			[PIN] = lesson("Is the old check specific?"),
			["z-nile/.tracker/issues/c0001/c0001.md"] = item("c0001", "issue", "c0001", ""),
		}, { noLessons = true })
		local areas = `{g.main}/z-nile/lesson-areas.md`
		if fs.isFile(areas) then
			fixture.git(g.main, { "rm", "-q", "--", "z-nile/lesson-areas.md" })
			fixture.git(g.main, { "commit", "-q", "-m", "drop copied areas" })
			fixture.git(g.main, { "push", "-q", "origin", "HEAD:main" })
		end
		t.expect(fixture.git(g.main, { "ls-tree", "origin/main", "z-nile/lesson-areas.md" })).toBe("")
		fs.writeFile(
			`{g.main}/z-nile/.tracker/issues/c0001/harvest.md`,
			"- design-review-001 F1: zz-test/pin\n"
		)
		fixture.git(g.main, { "add", "-A" })
		fixture.git(g.main, { "commit", "-q", "-m", "harvest before the file" })
		local early = trackerfix.tr(g, g.main, { "lessons", "--stale" })
		if early.code ~= 0 then
			error(early.stderr .. early.stdout, 0)
		end
		fs.writeFile(`{g.main}/z-nile/lesson-areas.md`, "core: review\nwiring: @skill\n")
		fixture.git(g.main, { "add", "-A" })
		fixture.git(g.main, { "commit", "-q", "-m", "areas file" })
		fs.writeFile(
			`{g.main}/z-nile/.tracker/issues/c0001/harvest.md`,
			fs.readFile(`{g.main}/z-nile/.tracker/issues/c0001/harvest.md`)
				.. "- design-review-002 F1: zz-test/pin\n"
		)
		fixture.git(g.main, { "add", "-A" })
		fixture.git(g.main, { "commit", "-q", "-m", "harvest after the file" })
		local later = trackerfix.tr(g, g.main, { "lessons", "--stale" })
		t.expect(later.code).toBe(1)
		t.expect(has(later.stdout .. later.stderr, "gained a source")).toBe(true)
	end)

	it("first source without from is the earliest commit, not the lowest item id", function()
		local nofrom = "z-nile/skills/zz-test/lessons/nofrom.md"
		local g = trackerfix.new("c0166-rewrite-order", {
			[nofrom] = "---\ntitle: No from\nwhen: build\ntags: [wiring]\ncheck: Is the check specific?\n---\nBody.\n",
			["z-nile/lesson-areas.md"] = "core: review\nwiring: @skill\n",
			["z-nile/.tracker/issues/c0009/c0009.md"] = item("c0009", "issue", "c0009", ""),
			["z-nile/.tracker/issues/c0009/harvest.md"] = "- design-review-001 F1: zz-test/nofrom\n",
			["z-nile/.tracker/rafts/active/R0001/R0001.md"] = item("R0001", "raft", "lessons", ""),
			["z-nile/.tracker/issues/active/c0001/c0001.md"] = item("c0001", "issue", "c0001", "R0001"),
		}, { noLessons = true })
		fixture.git(g.main, { "checkout", "-q", "-b", "R0001-lessons" })
		fs.writeFile(`{g.main}/{HARVEST}`, "- design-review-001 F1: zz-test/nofrom\n")
		local r = trackerfix.tr(g, g.main, { "commit", "-m", "lower id source", "--time", "1" })
		t.expect(r.code).toBe(1)
		t.expect(has(r.stderr, "commit: zz-test/nofrom gained a source and its check line did not change"))
			.toBe(true)
	end)

	it("a check change merged from main concurrent with a branch source is not stale", function()
		local g = trackerfix.new("c0166-rewrite-concurrent", {
			[PIN] = lesson("Is the old check specific?"),
			["z-nile/lesson-areas.md"] = "core: review\nwiring: @skill\n",
			["z-nile/.tracker/issues/c0001/c0001.md"] = item("c0001", "issue", "c0001", ""),
		}, { noLessons = true })
		fs.writeFile(
			`{g.main}/z-nile/.tracker/issues/c0001/harvest.md`,
			"- design-review-001 F1: zz-test/pin\n"
		)
		fixture.git(g.main, { "add", "-A" })
		fixture.git(g.main, { "commit", "-q", "-m", "branch adds a source" })
		local beforeMerge = trackerfix.tr(g, g.main, { "lessons", "--stale" })
		t.expect(beforeMerge.code).toBe(1)
		trackerfix.elsewhere(g, {
			[PIN] = lesson("Is the main check specific?"),
		}, "main rewrites the check")
		fixture.git(g.main, { "fetch", "-q", "origin" })
		fixture.git(g.main, { "merge", "-q", "origin/main" })
		local afterMerge = trackerfix.tr(g, g.main, { "lessons", "--stale" })
		if afterMerge.code ~= 0 then
			error(afterMerge.stderr .. afterMerge.stdout, 0)
		end
		local metrics = trackerfix.tr(g, g.main, { "metrics" })
		t.expect(has(metrics.stdout, "zz-test/pin: later 1, since check 0")).toBe(true)
	end)
end)
