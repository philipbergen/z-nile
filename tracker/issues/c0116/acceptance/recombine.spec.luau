--!strict
-- c0116: recombine edits a worktree, new raft accepts prepared members, z-design does not create a raft.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local PREPARED = "prepared-quiet-copper-falcon"
local ACTIVE = "active-quiet-copper-falcon"
local CHECK = 'check "AC1: ok" true\n'

local function idOf(out: string): string
	return string.match(out, "([fcdR]%d%d%d%d)") :: string
end

local function front(text: string, key: string): string
	return string.match(text, key .. ": ([^\n]+)") :: string
end

local function swap(text: string, old: string, new: string): string
	local out = ""
	local rest = text
	while true do
		local at = string.find(rest, old, 1, true)
		if not at then
			return out .. rest
		end
		out ..= string.sub(rest, 1, at - 1) .. new
		rest = string.sub(rest, at + #old)
	end
end

local function notUsage(r: { ok: boolean, stdout: string, stderr: string })
	local said = r.stderr .. r.stdout
	t.expect(r.ok).toBe(false)
	t.expect(string.find(said, "usage: scripts/tracker.sh", 1, true) ~= nil).toBe(false)
	return said
end

local function issueDoc(id: string, status: string, project: string, raft: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-01-01\nstatus: {status}\nproject: {project}\n---\n\n# {id}\n`
end

local function raftDoc(id: string, issues: string, status: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-01-01\nstatus: {status}\n---\n\n# {id}\n`
end

return t.spec("z-raft recombine", function(it)
	it("members move", function()
		local seed: { [string]: string } = {
			["tracker/next"] = "issue 3 seed-phrase\nraft 3 seed-phrase\n",
			["tracker/issues/c0001/c0001.md"] = issueDoc("c0001", PREPARED, "pickman", "R0001"),
			["tracker/issues/c0001/check.sh"] = CHECK,
			["tracker/rafts/R0001/R0001.md"] = raftDoc("R0001", "c0001", PREPARED),
			["tracker/rafts/R0001/check.sh"] = CHECK,
			["tracker/issues/c0002/c0002.md"] = issueDoc(
				"c0002",
				"prepared-brisk-amber-otter",
				"pickman",
				"R0002"
			),
			["tracker/issues/c0002/check.sh"] = CHECK,
			["tracker/rafts/R0002/R0002.md"] = raftDoc("R0002", "c0002", "prepared-brisk-amber-otter"),
			["tracker/rafts/R0002/check.sh"] = CHECK,
		}
		local f = trackerfix.new("c0116-recombine", seed)
		local wt = trackerfix.trOk(f, f.main, { "worktree", "cap-recombine" })
		local tip = fixture.git(f.origin, { "rev-parse", "main" })
		local r = trackerfix.tr(f, wt, { "recombine", "R0001", "R0002" })
		t.expect(r.ok).toBe(true)
		t.expect(fixture.git(f.origin, { "rev-list", "--count", `{tip}..main` })).toBe("1")
		local keepOrigin = fixture.git(f.origin, { "show", "main:tracker/rafts/R0001/R0001.md" })
		local dropOrigin = fixture.git(f.origin, { "show", "main:tracker/rafts/R0002/R0002.md" })
		local claim = front(keepOrigin, "status")
		t.expect(string.sub(claim, 1, 10)).toBe("preparing-")
		t.expect(front(dropOrigin, "status")).toBe(claim)
		t.expect(front(fixture.git(f.origin, { "show", "main:tracker/issues/c0001/c0001.md" }), "status"))
			.toBe(PREPARED)
		t.expect(front(fixture.git(f.origin, { "show", "main:tracker/issues/c0002/c0002.md" }), "status"))
			.toBe("prepared-brisk-amber-otter")
		t.expect(trackerfix.tr(f, f.main, { "ready", "R0001" }).ok).toBe(false)
		t.expect(fs.isDir(`{wt}/tracker/rafts/R0002`)).toBe(false)
		local keepDoc = fs.readFile(`{wt}/tracker/rafts/R0001/R0001.md`)
		local listed = string.match(keepDoc, "issues: %[([^%]]*)%]") or ""
		t.expect(string.find(listed, "c0001", 1, true) ~= nil).toBe(true)
		t.expect(string.find(listed, "c0002", 1, true) ~= nil).toBe(true)
		local moved = fs.readFile(`{wt}/tracker/issues/c0002/c0002.md`)
		t.expect(front(moved, "raft")).toBe("R0001")
		t.expect(front(moved, "status")).toBe("prepared-brisk-amber-otter")
	end)

	it("mixed types are refused", function()
		local feat = swap(issueDoc("f0001", PREPARED, "pickman", "R0002"), "type: chore", "type: feature")
		local featRaft = swap(raftDoc("R0002", "f0001", PREPARED), "type: chore", "type: feature")
		local seed: { [string]: string } = {
			["tracker/next"] = "issue 3 seed-phrase\nraft 3 seed-phrase\n",
			["tracker/issues/c0001/c0001.md"] = issueDoc("c0001", PREPARED, "pickman", "R0001"),
			["tracker/issues/c0001/check.sh"] = CHECK,
			["tracker/rafts/R0001/R0001.md"] = raftDoc("R0001", "c0001", PREPARED),
			["tracker/rafts/R0001/check.sh"] = CHECK,
			["tracker/issues/f0001/f0001.md"] = feat,
			["tracker/issues/f0001/check.sh"] = CHECK,
			["tracker/rafts/R0002/R0002.md"] = featRaft,
			["tracker/rafts/R0002/check.sh"] = CHECK,
		}
		local f = trackerfix.new("c0116-mixed", seed)
		local wt = trackerfix.trOk(f, f.main, { "worktree", "cap-mixed" })
		local said = notUsage(trackerfix.tr(f, wt, { "recombine", "R0001", "R0002" }))
		t.expect(string.find(said, "feature", 1, true) ~= nil).toBe(true)
		t.expect(fs.isDir(`{wt}/tracker/rafts/R0002`)).toBe(true)
	end)

	it("design does not create a raft", function()
		local path = `{root}/.claude/skills/z-design/SKILL.md`
		t.expect(fs.isFile(path)).toBe(true)
		local design = fs.readFile(path)
		t.expect(string.find(design, "new raft", 1, true) ~= nil).toBe(false)
		local desc = string.match(design, "description: ([^\n]+)") or ""
		t.expect(string.find(desc, "execution-ready raft", 1, true) ~= nil).toBe(false)
		local rules = fs.readFile(`{root}/.claude/skills/zz-rules/SKILL.md`)
		t.expect(string.find(rules, "z-raft", 1, true) ~= nil).toBe(true)
		t.expect(string.find(rules, "recombine", 1, true) ~= nil).toBe(true)
		t.expect(string.find(rules, "pinned old path", 1, true) ~= nil).toBe(false)
		t.expect(
			string.find(fs.readFile(`{root}/.claude/skills/tracker/SKILL.md`), "zz-rules", 1, true) ~= nil
		)
			.toBe(true)
	end)

	it("prepared issues raft", function()
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(`{root}/.gitignore`),
			["tracker/architecture.md"] = fs.readFile(`{root}/tracker/architecture.md`),
			["tracker/next"] = "issue 3 seed-phrase\nraft 1 seed-phrase\n",
			["tracker/issues/c0001/c0001.md"] = issueDoc("c0001", PREPARED, "pickman", ""),
			["tracker/issues/c0001/check.sh"] = CHECK,
			["tracker/issues/c0002/c0002.md"] = issueDoc("c0002", PREPARED, "pickman", ""),
			["tracker/issues/c0002/check.sh"] = CHECK,
		}
		for _, s in { "execute-raft", "tracker", "architecture", "testing", "review" } do
			seed[`.claude/skills/{s}/SKILL.md`] = fs.readFile(`{root}/.claude/skills/{s}/SKILL.md`)
		end
		local f = trackerfix.new("c0116-prepared", seed)
		local wt = trackerfix.trOk(f, f.main, { "worktree", "cap-prepared" })
		local made = trackerfix.tr(f, wt, { "new", "raft", "chore", "grouped", "c0001", "c0002" })
		t.expect(made.ok).toBe(true)
		local rid = idOf(made.stdout)
		local raftOnOrigin = fixture.git(f.origin, { "show", `main:tracker/rafts/{rid}/{rid}.md` })
		t.expect(front(raftOnOrigin, "design")).toBe("draft")
		local stamp = front(raftOnOrigin, "status")
		t.expect(string.sub(stamp, 1, 10)).toBe("preparing-")
		for _, id in { "c0001", "c0002" } do
			local doc = fixture.git(f.origin, { "show", `main:tracker/issues/{id}/{id}.md` })
			t.expect(front(doc, "status")).toBe(PREPARED)
		end
		local tip = fixture.git(f.origin, { "rev-parse", "main" })
		local wt2 = trackerfix.trOk(f, f.main, { "worktree", "cap-prepared-2" })
		local again = notUsage(trackerfix.tr(f, wt2, { "new", "raft", "chore", "again", "c0001" }))
		t.expect(string.find(again, rid, 1, true) ~= nil).toBe(true)
		t.expect(fixture.git(f.origin, { "rev-parse", "main" })).toBe(tip)
		t.expect(trackerfix.tr(f, f.main, { "ready", rid }).ok).toBe(false)
		local raftPath = `{wt}/tracker/rafts/{rid}/{rid}.md`
		fs.writeFile(raftPath, swap(fs.readFile(raftPath), "design: draft", "design: ready"))
		local moved = trackerfix.tr(f, wt, { "status", rid, "prepared" })
		t.expect(moved.ok).toBe(true)
		fixture.git(wt, { "add", "-A" })
		fixture.git(wt, { "commit", "-q", "-m", "prepared" })
		fixture.git(wt, { "push", "origin", "HEAD:main" })
		t.expect(trackerfix.tr(f, f.main, { "ready", rid }).ok).toBe(true)
	end)

	it("active issue refused", function()
		local seed: { [string]: string } = {
			["tracker/next"] = "issue 2 seed-phrase\nraft 1 seed-phrase\n",
			["tracker/issues/active/c0001/c0001.md"] = issueDoc("c0001", ACTIVE, "pickman", ""),
			["tracker/issues/active/c0001/check.sh"] = CHECK,
		}
		local f = trackerfix.new("c0116-active-issue", seed)
		local wt = trackerfix.trOk(f, f.main, { "worktree", "cap-active-issue" })
		local said = notUsage(trackerfix.tr(f, wt, { "new", "raft", "chore", "nope", "c0001" }))
		t.expect(string.find(said, "active", 1, true) ~= nil).toBe(true)
		local doc = fs.readFile(`{wt}/tracker/issues/active/c0001/c0001.md`)
		t.expect(string.match(doc, "raft: ([^\n]*)")).toBe("")
	end)

	it("active raft refused", function()
		local seed: { [string]: string } = {
			["tracker/next"] = "issue 3 seed-phrase\nraft 3 seed-phrase\n",
			["tracker/issues/c0001/c0001.md"] = issueDoc("c0001", PREPARED, "pickman", "R0001"),
			["tracker/issues/c0001/check.sh"] = CHECK,
			["tracker/rafts/R0001/R0001.md"] = raftDoc("R0001", "c0001", PREPARED),
			["tracker/rafts/R0001/check.sh"] = CHECK,
			["tracker/issues/active/c0002/c0002.md"] = issueDoc("c0002", ACTIVE, "pickman", "R0002"),
			["tracker/issues/active/c0002/check.sh"] = CHECK,
			["tracker/rafts/active/R0002/R0002.md"] = raftDoc("R0002", "c0002", ACTIVE),
			["tracker/rafts/active/R0002/check.sh"] = CHECK,
		}
		local f = trackerfix.new("c0116-active-raft", seed)
		local wt = trackerfix.trOk(f, f.main, { "worktree", "cap-active-raft" })
		local tip = fixture.git(f.origin, { "rev-parse", "main" })
		notUsage(trackerfix.tr(f, wt, { "recombine", "R0001", "R0002" }))
		t.expect(fixture.git(f.origin, { "rev-parse", "main" })).toBe(tip)
		t.expect(fs.isDir(`{wt}/tracker/rafts/active/R0002`)).toBe(true)
		t.expect(front(fs.readFile(`{wt}/tracker/issues/active/c0002/c0002.md`), "raft")).toBe("R0002")
	end)

	it("project differs", function()
		local held = "preparing-quiet-copper-falcon"
		local seed: { [string]: string } = {
			["tracker/next"] = "issue 5 seed-phrase\nraft 5 seed-phrase\n",
			["tracker/issues/c0001/c0001.md"] = issueDoc("c0001", PREPARED, "pickman", "R0001"),
			["tracker/issues/c0001/check.sh"] = CHECK,
			["tracker/rafts/R0001/R0001.md"] = raftDoc("R0001", "c0001", PREPARED),
			["tracker/rafts/R0001/check.sh"] = CHECK,
			["tracker/issues/c0002/c0002.md"] = issueDoc("c0002", PREPARED, "z-nile", "R0002"),
			["tracker/issues/c0002/check.sh"] = CHECK,
			["tracker/rafts/R0002/R0002.md"] = raftDoc("R0002", "c0002", PREPARED),
			["tracker/rafts/R0002/check.sh"] = CHECK,
			["tracker/issues/c0003/c0003.md"] = issueDoc("c0003", held, "pickman", "R0003"),
			["tracker/issues/c0003/check.sh"] = CHECK,
			["tracker/rafts/R0003/R0003.md"] = raftDoc("R0003", "c0003", held),
			["tracker/rafts/R0003/check.sh"] = CHECK,
		}
		local f = trackerfix.new("c0116-project", seed)
		local wt = trackerfix.trOk(f, f.main, { "worktree", "cap-project" })
		local tip = fixture.git(f.origin, { "rev-parse", "main" })
		local said = notUsage(trackerfix.tr(f, wt, { "recombine", "R0001", "R0002" }))
		t.expect(string.find(said, "project", 1, true) ~= nil).toBe(true)
		t.expect(fixture.git(f.origin, { "rev-parse", "main" })).toBe(tip)
		t.expect(front(fs.readFile(`{wt}/tracker/issues/c0002/c0002.md`), "raft")).toBe("R0002")
		local heldSaid = notUsage(trackerfix.tr(f, wt, { "recombine", "R0001", "R0003" }))
		t.expect(string.find(heldSaid, "preparing", 1, true) ~= nil).toBe(true)
		t.expect(fixture.git(f.origin, { "rev-parse", "main" })).toBe(tip)
		t.expect(front(fs.readFile(`{wt}/tracker/rafts/R0003/R0003.md`), "status")).toBe(held)
	end)

	it("review files move", function()
		local seed: { [string]: string } = {
			["tracker/next"] = "issue 3 seed-phrase\nraft 3 seed-phrase\n",
			["tracker/issues/c0001/c0001.md"] = issueDoc("c0001", PREPARED, "pickman", "R0001"),
			["tracker/issues/c0001/check.sh"] = CHECK,
			["tracker/rafts/R0001/R0001.md"] = raftDoc("R0001", "c0001", PREPARED),
			["tracker/rafts/R0001/check.sh"] = CHECK,
			["tracker/issues/c0002/c0002.md"] = issueDoc("c0002", PREPARED, "pickman", "R0002"),
			["tracker/issues/c0002/check.sh"] = CHECK,
			["tracker/rafts/R0002/R0002.md"] = raftDoc("R0002", "c0002", PREPARED),
			["tracker/rafts/R0002/check.sh"] = CHECK,
			["tracker/rafts/R0002/design-review-001.md"] = "# Review 001\n",
		}
		local f = trackerfix.new("c0116-reviews", seed)
		local wt = trackerfix.trOk(f, f.main, { "worktree", "cap-reviews" })
		local r = trackerfix.tr(f, wt, { "recombine", "R0001", "R0002" })
		t.expect(r.ok).toBe(true)
		t.expect(fs.isFile(`{wt}/tracker/rafts/R0001/design-review-001.md`)).toBe(true)
		t.expect(fs.isDir(`{wt}/tracker/rafts/R0002`)).toBe(false)
	end)

	it("cross project raft refused", function()
		local seed: { [string]: string } = {
			["tracker/next"] = "issue 3 seed-phrase\nraft 1 seed-phrase\n",
			["tracker/issues/c0001/c0001.md"] = issueDoc("c0001", PREPARED, "pickman", ""),
			["tracker/issues/c0001/check.sh"] = CHECK,
			["tracker/issues/c0002/c0002.md"] = issueDoc("c0002", PREPARED, "z-nile", ""),
			["tracker/issues/c0002/check.sh"] = CHECK,
		}
		local f = trackerfix.new("c0116-cross-new", seed)
		local wt = trackerfix.trOk(f, f.main, { "worktree", "cap-cross-new" })
		local tip = fixture.git(f.origin, { "rev-parse", "main" })
		local said = notUsage(trackerfix.tr(f, wt, { "new", "raft", "chore", "split", "c0001", "c0002" }))
		t.expect(string.find(said, "project", 1, true) ~= nil).toBe(true)
		t.expect(fixture.git(f.origin, { "rev-parse", "main" })).toBe(tip)
	end)

	it("mixed status refused", function()
		local seed: { [string]: string } = {
			["tracker/next"] = "issue 3 seed-phrase\nraft 1 seed-phrase\n",
			["tracker/issues/c0001/c0001.md"] = issueDoc("c0001", "new-quiet-copper-falcon", "pickman", ""),
			["tracker/issues/c0001/check.sh"] = CHECK,
			["tracker/issues/c0002/c0002.md"] = issueDoc("c0002", PREPARED, "pickman", ""),
			["tracker/issues/c0002/check.sh"] = CHECK,
		}
		local f = trackerfix.new("c0116-mix-status", seed)
		local wt = trackerfix.trOk(f, f.main, { "worktree", "cap-mix-status" })
		local tip = fixture.git(f.origin, { "rev-parse", "main" })
		local said = notUsage(trackerfix.tr(f, wt, { "new", "raft", "chore", "mixed", "c0001", "c0002" }))
		t.expect(string.find(said, "c0001", 1, true) ~= nil).toBe(true)
		t.expect(string.find(said, "c0002", 1, true) ~= nil).toBe(true)
		t.expect(fixture.git(f.origin, { "rev-parse", "main" })).toBe(tip)
	end)

	it("prepared give-back", function()
		local seed: { [string]: string } = {
			["tracker/next"] = "issue 3 seed-phrase\nraft 1 seed-phrase\n",
			["tracker/issues/c0001/c0001.md"] = issueDoc("c0001", PREPARED, "pickman", ""),
			["tracker/issues/c0001/check.sh"] = CHECK,
			["tracker/issues/c0002/c0002.md"] = issueDoc("c0002", PREPARED, "pickman", ""),
			["tracker/issues/c0002/check.sh"] = CHECK,
		}
		local f = trackerfix.new("c0116-giveback", seed)
		local wt = trackerfix.trOk(f, f.main, { "worktree", "cap-giveback" })
		local made = trackerfix.tr(f, wt, { "new", "raft", "chore", "grouped", "c0001", "c0002" })
		t.expect(made.ok).toBe(true)
		local rid = idOf(made.stdout)
		local before = fixture.git(f.origin, { "rev-parse", "main" })
		local gave = trackerfix.tr(f, wt, { "status", rid, "new" })
		t.expect(gave.ok).toBe(true)
		t.expect(fixture.git(f.origin, { "rev-list", "--count", `{before}..main` })).toBe("1")
		local files = fixture.git(f.origin, { "diff", "--name-only", before, "main" })
		t.expect(files).toBe(`tracker/rafts/{rid}/{rid}.md`)
		for _, id in { "c0001", "c0002" } do
			local doc = fixture.git(f.origin, { "show", `main:tracker/issues/{id}/{id}.md` })
			t.expect(front(doc, "status")).toBe(PREPARED)
		end
		t.expect(trackerfix.tr(f, wt, { "new", "raft", "chore", "again", "c0001" }).ok).toBe(true)
	end)

	it("held issue cannot be claimed", function()
		local seed: { [string]: string } = {
			["tracker/next"] = "issue 2 seed-phrase\nraft 1 seed-phrase\n",
			["tracker/issues/c0001/c0001.md"] = issueDoc("c0001", PREPARED, "pickman", ""),
			["tracker/issues/c0001/check.sh"] = CHECK,
		}
		local f = trackerfix.new("c0116-held", seed)
		local wt = trackerfix.trOk(f, f.main, { "worktree", "cap-held" })
		local made = trackerfix.tr(f, wt, { "new", "raft", "chore", "holds", "c0001" })
		t.expect(made.ok).toBe(true)
		local rid = idOf(made.stdout)
		local said = notUsage(trackerfix.tr(f, wt, { "status", "c0001", "preparing" }))
		t.expect(string.find(said, rid, 1, true) ~= nil).toBe(true)
	end)

	it("foreign hold refused", function()
		local other = raftDoc("R0002", "c0002", "preparing-quiet-copper-falcon")
		local seed: { [string]: string } = {
			["tracker/next"] = "issue 3 seed-phrase\nraft 3 seed-phrase\n",
			["tracker/issues/c0001/c0001.md"] = issueDoc("c0001", PREPARED, "pickman", "R0001"),
			["tracker/issues/c0001/check.sh"] = CHECK,
			["tracker/rafts/R0001/R0001.md"] = raftDoc("R0001", "c0001", "preparing-brisk-amber-otter"),
			["tracker/rafts/R0001/check.sh"] = CHECK,
			["tracker/issues/c0002/c0002.md"] = issueDoc("c0002", PREPARED, "pickman", "R0002"),
			["tracker/issues/c0002/check.sh"] = CHECK,
			["tracker/rafts/R0002/R0002.md"] = other,
			["tracker/rafts/R0002/check.sh"] = CHECK,
		}
		local f = trackerfix.new("c0116-foreign", seed)
		local wt = trackerfix.trOk(f, f.main, { "worktree", "cap-foreign" })
		local path = `{wt}/tracker/rafts/R0002/R0002.md`
		fs.writeFile(path, swap(fs.readFile(path), "issues: [c0002]", "issues: [c0002, c0001]"))
		local said = notUsage(trackerfix.tr(f, wt, { "status", "R0002", "prepared" }))
		t.expect(string.find(said, "R0001", 1, true) ~= nil).toBe(true)
	end)

	it("new issue rafted again", function()
		local f = trackerfix.new("c0116-reraft")
		local wt = trackerfix.trOk(f, f.main, { "worktree", "cap-reraft" })
		local issue = idOf(trackerfix.trOk(f, wt, { "new", "issue", "c", "once", "--desc", "Once." }))
		local first = idOf(trackerfix.trOk(f, wt, { "new", "raft", "chore", "first", issue }))
		t.expect(trackerfix.tr(f, wt, { "status", first, "new" }).ok).toBe(true)
		t.expect(trackerfix.tr(f, wt, { "new", "raft", "chore", "second", issue }).ok).toBe(true)
	end)
end)
