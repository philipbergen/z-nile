--!strict
-- c0116 AC2: `recombine <keeper> <other> [<issue>...]` moves the named members of the other backlog raft, or all of
-- them, into the keeper. It claims both rafts with one fresh stamp (status lines only, published), writes the moves in
-- the worktree, and retires the other raft (deletes its folder in the branch) only when it ends up empty. The shared
-- stamp is what lets the carried `status <keeper> prepared` take a member whose raft: on origin still names the other
-- raft; a raft with a different stamp is refused. It never crosses projects or types, never takes an active, done or
-- claimed raft, never moves an unprepared issue, and keeps a solo issue alone. After the PR merges both rafts are
-- readyable. Driven through scripts/tracker.sh in a fixture under .cache/c0116-recombine (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

local function issue(id: string, kind: string, raft: string, extra: string?): string
	return `---\nid: {id}\ntype: {kind}\ntitle: {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-20\nsize: 200\n{extra or ""}status: {PREPARED}\n---\n\n# {id}\n`
end
local function raftDoc(id: string, kind: string, issues: string, status: string?): string
	return `---\nid: {id}\ntype: {kind}\ntitle: {id}\nslug: {string.lower(id)}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-10-20\nstatus: {status or PREPARED}\n---\n\n# {id}\n\n## Theme\nSeeded.\n\n## Order & dependencies\nBy id.\n\n## Risks & rollback\n`
end

local f: trackerfix.Fixture
local W, X = "", "" -- rafting worktrees

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function tip(): string
	return fixture.git(f.origin, { "rev-parse", "main" })
end
local function onOrigin(path: string): string?
	local r = fixture.exec(f.origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else nil
end
local function originStatus(path: string): string
	return string.match(onOrigin(path) or "", "\nstatus: (%S+)\n") or ""
end
local function tr(cwd: string, args: { string }): fixture.Result
	return trackerfix.tr(f, cwd, args)
end
local function trOk(cwd: string, args: { string }): string
	return trackerfix.trOk(f, cwd, args)
end
local function refused(cwd: string, args: { string }, ...: string)
	local before = tip()
	local r = tr(cwd, args)
	t.expect(r.ok).toBe(false)
	for _, needle in { ... } do
		if not has(r.stderr, needle) then
			error(`{table.concat(args, " ")}: stderr lacks {needle}: {r.stderr}`, 2)
		end
	end
	t.expect(tip()).toBe(before)
end
local function front(path: string, key: string): string?
	return string.match(fs.readFile(path), `\n{key}: ([^\n]*)\n`)
end
local function land(wt: string)
	fixture.git(wt, { "fetch", "-q", "origin" })
	fixture.git(wt, { "merge", "-q", "--no-edit", "origin/main" })
	fixture.git(wt, { "push", "-q", "origin", "HEAD:main" })
	fixture.git(f.main, { "pull", "-q", "origin", "main" })
end

return t.spec("c0116 recombine moves members between backlog rafts and retires an emptied one", function(it)
	it("sets up prepared rafts in two projects, an active raft, a feature raft and a solo member", function()
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(".gitignore"),
			["tracker/architecture.md"] = "# Architecture\n",
		}
		local function add(path: string, text: string)
			seed[path] = text
			seed[string.gsub(path, "/[^/]+$", "/check.sh")] = CHECK
		end
		-- pickman's root in the fixtures is tracker/, z-nile's is z-nile/.tracker
		add("tracker/rafts/R0010/R0010.md", raftDoc("R0010", "chore", "c0011, c0012"))
		add("tracker/issues/c0011/c0011.md", issue("c0011", "chore", "R0010"))
		add("tracker/issues/c0012/c0012.md", issue("c0012", "chore", "R0010"))
		add("tracker/rafts/R0020/R0020.md", raftDoc("R0020", "chore", "c0021, c0022"))
		add("tracker/issues/c0021/c0021.md", issue("c0021", "chore", "R0020"))
		add("tracker/issues/c0022/c0022.md", issue("c0022", "chore", "R0020"))
		add("tracker/rafts/R0030/R0030.md", raftDoc("R0030", "chore", "c0031"))
		add("tracker/issues/c0031/c0031.md", issue("c0031", "chore", "R0030"))
		add("tracker/rafts/R0040/R0040.md", raftDoc("R0040", "chore", "c0041"))
		add("tracker/issues/c0041/c0041.md", issue("c0041", "chore", "R0040"))
		add("z-nile/.tracker/rafts/R0050/R0050.md", raftDoc("R0050", "chore", "c0051"))
		add("z-nile/.tracker/issues/c0051/c0051.md", issue("c0051", "chore", "R0050"))
		add(
			"tracker/rafts/active/R0060/R0060.md",
			raftDoc("R0060", "chore", "c0061", "active-jolly-silver-walrus")
		)
		add(
			"tracker/issues/active/c0061/c0061.md",
			(string.gsub(issue("c0061", "chore", "R0060"), PREPARED, "active-jolly-silver-walrus"))
		)
		add("tracker/rafts/R0070/R0070.md", raftDoc("R0070", "feature", "f0071"))
		add("tracker/issues/f0071/f0071.md", issue("f0071", "feature", "R0070"))
		-- a given-back feature raft with no member (an orphan)
		add("tracker/rafts/R0075/R0075.md", raftDoc("R0075", "feature", "", "new-amber-otter-lynx"))
		add("tracker/rafts/R0080/R0080.md", raftDoc("R0080", "chore", "c0081"))
		add("tracker/issues/c0081/c0081.md", issue("c0081", "chore", "R0080", "solo: true\n"))
		add("tracker/rafts/R0090/R0090.md", raftDoc("R0090", "chore", "c0091"))
		add("tracker/issues/c0091/c0091.md", issue("c0091", "chore", "R0090"))
		add("tracker/rafts/R0100/R0100.md", raftDoc("R0100", "chore", "c0101"))
		add("tracker/issues/c0101/c0101.md", issue("c0101", "chore", "R0100"))
		f = trackerfix.new("c0116-recombine", seed)
		W = trOk(f.main, { "worktree", "raft-w" })
		X = trOk(f.main, { "worktree", "raft-x" })
	end)

	it(
		"refuses across projects and types, an active raft, a non-member and a solo issue, publishing nothing",
		function()
			refused(W, { "recombine", "R0010", "R0050" }, "projects", "tracker", "z-nile/.tracker")
			refused(W, { "recombine", "R0010", "R0070" }, "feature")
			refused(W, { "recombine", "R0010", "R0075" }, "R0075", "feature") -- an empty raft of another type too
			refused(W, { "recombine", "R0010", "R0060" }, "R0060", "backlog")
			refused(W, { "recombine", "R0060", "R0010" }, "R0060", "backlog")
			refused(W, { "recombine", "R0010", "R0020", "c0031" }, "c0031 is not a member of R0020")
			refused(W, { "recombine", "R0010", "R0080" }, "c0081", "solo")
			refused(W, { "recombine", "R0010", "R0010" }, "two different")
		end
	)

	it("a partial move claims both rafts with one stamp and leaves the members' status alone", function()
		local before = tip()
		local texts = { onOrigin("tracker/issues/c0021/c0021.md"), onOrigin("tracker/issues/c0022/c0022.md") }
		trOk(W, { "recombine", "R0010", "R0020", "c0021" })
		t.expect(fixture.git(f.origin, { "rev-list", "--count", `{before}..main` })).toBe("1")
		local changed = string.split(fixture.git(f.origin, { "diff", "--name-only", before, "main" }), "\n")
		t.expect(changed).toEqual({ "tracker/rafts/R0010/R0010.md", "tracker/rafts/R0020/R0020.md" })
		local s1 = originStatus("tracker/rafts/R0010/R0010.md")
		t.expect(string.match(s1, "^preparing%-%a+%-%a+%-%a+$") ~= nil).toBe(true)
		t.expect(originStatus("tracker/rafts/R0020/R0020.md")).toBe(s1)
		t.expect(onOrigin("tracker/issues/c0021/c0021.md")).toBe(texts[1])
		t.expect(onOrigin("tracker/issues/c0022/c0022.md")).toBe(texts[2])
		-- the moves are the worktree's
		t.expect(front(`{W}/tracker/issues/c0021/c0021.md`, "raft")).toBe("R0010")
		t.expect(front(`{W}/tracker/issues/c0021/c0021.md`, "status")).toBe(PREPARED)
		t.expect(front(`{W}/tracker/rafts/R0010/R0010.md`, "issues")).toBe("[c0011, c0012, c0021]")
		t.expect(fs.isDir(`{W}/tracker/rafts/R0020`)).toBe(true)
		t.expect(front(`{W}/tracker/rafts/R0020/R0020.md`, "issues")).toBe("[c0022]")
		t.expect(fixture.git(W, { "status", "--porcelain" })).toBe("")
		-- neither raft can be readied, claimed again or recombined while the claim stands
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		refused(f.main, { "ready", "R0010" }, "preparing")
		refused(X, { "recombine", "R0030", "R0020" }, "R0020", "preparing")
	end)

	it(
		"the carried move takes the moved member through the shared stamp, and both rafts are readyable after the merge",
		function()
			fs.writeFile(`{W}/tracker/rafts/R0010/design-review-001.md`, "# Review 001\n\nVerdict: approve\n")
			local before = tip()
			trOk(W, { "status", "R0010", "prepared" })
			trOk(W, { "status", "R0020", "prepared" })
			t.expect(tip()).toBe(before)
			fixture.git(W, { "add", "-A" })
			fixture.git(W, { "commit", "-q", "-m", "tracker: raft R0010 R0020" })
			land(W)
			trOk(f.main, { "ready", "R0010" })
			trOk(f.main, { "ready", "R0020" })
			t.expect(onOrigin("tracker/issues/active/c0021/c0021.md") ~= nil).toBe(true)
			t.expect(front(`{f.main}/tracker/rafts/active/R0010/R0010.md`, "issues"))
				.toBe("[c0011, c0012, c0021]")
			t.expect(front(`{f.main}/tracker/rafts/active/R0020/R0020.md`, "issues")).toBe("[c0022]")
		end
	)

	it(
		"moving every member retires the other raft in the branch, and the keeper readies after the merge",
		function()
			fixture.git(X, { "reset", "-q", "--hard", "origin/main" })
			local out = trOk(X, { "recombine", "R0030", "R0040" })
			t.expect(has(out, "retired R0040")).toBe(true)
			t.expect(fs.isDir(`{X}/tracker/rafts/R0040`)).toBe(false)
			t.expect(onOrigin("tracker/rafts/R0040/R0040.md") ~= nil).toBe(true) -- publish never deletes: the PR does
			fs.writeFile(`{X}/tracker/rafts/R0030/design-review-001.md`, "# Review 001\n\nVerdict: approve\n")
			trOk(X, { "status", "R0030", "prepared" })
			fixture.git(X, { "add", "-A" })
			fixture.git(X, { "commit", "-q", "-m", "tracker: raft R0030" })
			land(X)
			t.expect(onOrigin("tracker/rafts/R0040/R0040.md")).toBe(nil)
			trOk(f.main, { "ready", "R0030" })
			t.expect(front(`{f.main}/tracker/rafts/active/R0030/R0030.md`, "issues")).toBe("[c0031, c0041]")
		end
	)

	it("the carried move refuses a member held by a raft with another stamp, naming it", function()
		fixture.git(X, { "reset", "-q", "--hard", "origin/main" })
		-- another terminal claims R0090; this one claims R0100 and takes R0090's c0091 into it locally
		trOk(W, { "status", "R0090", "preparing" })
		fixture.git(X, { "fetch", "-q", "origin" })
		fixture.git(X, { "merge", "-q", "--no-edit", "origin/main" })
		trOk(X, { "status", "R0100", "preparing" })
		local doc = `{X}/tracker/rafts/R0100/R0100.md`
		local text = fs.readFile(doc)
		local s, e = string.find(text, "\nissues: [c0101]\n", 1, true)
		assert(s and e, "R0100's issues: line")
		fs.writeFile(doc, string.sub(text, 1, s) .. "issues: [c0101, c0091]\n" .. string.sub(text, e + 1))
		local idoc = `{X}/tracker/issues/c0091/c0091.md`
		local itext = fs.readFile(idoc)
		local a, b = string.find(itext, "\nraft: R0090\n", 1, true)
		assert(a and b, "c0091's raft: line")
		fs.writeFile(idoc, string.sub(itext, 1, a) .. "raft: R0100\n" .. string.sub(itext, b + 1))
		refused(X, { "status", "R0100", "prepared" }, "c0091", "R0090")
		fixture.git(X, { "checkout", "-q", "--", "." })
	end)

	it("release gives both recombined rafts back to prepared", function()
		trOk(W, { "release", "R0090", "--force" })
		trOk(X, { "release", "R0100", "--force" })
		fixture.git(X, { "fetch", "-q", "origin" })
		fixture.git(X, { "reset", "-q", "--hard", "origin/main" })
		trOk(X, { "recombine", "R0090", "R0100" })
		local stamp = originStatus("tracker/rafts/R0090/R0090.md")
		t.expect(originStatus("tracker/rafts/R0100/R0100.md")).toBe(stamp)
		local before = tip()
		trOk(X, { "release", "R0090" })
		local changed = string.split(fixture.git(f.origin, { "diff", "--name-only", before, "main" }), "\n")
		t.expect(changed).toEqual({ "tracker/rafts/R0090/R0090.md", "tracker/rafts/R0100/R0100.md" })
		t.expect(string.match(originStatus("tracker/rafts/R0090/R0090.md"), "^prepared%-") ~= nil).toBe(true)
		t.expect(string.match(originStatus("tracker/rafts/R0100/R0100.md"), "^prepared%-") ~= nil).toBe(true)
	end)
end)
