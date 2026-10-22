--!strict
-- c0062: one part of c0510's commands spec, split so that `tests/run` runs the parts concurrently.
-- This part: abandoning prep, the local member list, `--raft`, and claiming an existing draft raft.
-- Driven through `scripts/tracker.sh` in a worktree, exactly as a terminal would. Cases share this part's fixture
-- and run in order.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local git = fixture.git
local f: trackerfix.Fixture = { base = "", origin = "", main = "", other = "" }
local origin, main = "", ""

local function tr(cwd: string, args: { string }, env: { [string]: string }?): fixture.Result
	return trackerfix.tr(f, cwd, args, env)
end
local function trOk(cwd: string, args: { string }): string
	return trackerfix.trOk(f, cwd, args)
end
local function onOrigin(path: string): string? -- the file's text on origin's main, or nil
	local r = fixture.exec(origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else nil
end
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
-- another terminal pushes a commit straight to origin's main
local function elsewhere(files: { [string]: string }, message: string)
	trackerfix.elsewhere(f, files, message)
end

local cap = "" -- the capture worktree
local zeta, rz = "", "" -- the issue and raft of the "abandons prep" case

return t.spec("tracker commands publish state to origin/main (prep)", function(it)
	it("sets up the prep fixture", function()
		f = trackerfix.new("c0053-commands-prep", nil)
		origin, main = f.origin, f.main
		cap = trOk(main, { "worktree", "cap-a" })
		t.expect(git(cap, { "branch", "--show-current" })).toBe("cap-a")
	end)

	it("a published move abandons prep for a raft and its members in one commit", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		trOk(cap, { "sync" })
		trOk(cap, { "new", "issue", "c", "zeta", "--desc", "Zeta.", "--project", "pickman" })
		zeta =
			string.match(trOk(cap, { "list", "backlog" }), "(c%d+)%s+backlog%s+chore%s+%S*%s+Zeta") :: string
		local raftDoc =
			trOk(cap, { "new", "raft", "chore", "zraft", zeta, "--single", "--project", "pickman" })
		rz = string.match(raftDoc, "(R%d+)") :: string
		t.expect(trOk(cap, { "status", rz })).toBe("preparing")
		local before = git(origin, { "rev-parse", "main" })
		trOk(cap, { "status", rz, "new" })
		local files = git(origin, { "diff", "--name-only", before, "main" })
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(has(files, `pickman/.tracker/rafts/{rz}/{rz}.md`)).toBe(true)
		t.expect(has(files, `pickman/.tracker/issues/{zeta}/{zeta}.md`)).toBe(true)
		t.expect(#string.split(files, "\n")).toBe(2)
		t.expect(git(origin, { "rev-list", "--count", `{before}..main` })).toBe("1")
		t.expect(trOk(cap, { "status", rz })).toBe("new")
		t.expect(trOk(cap, { "status", zeta })).toBe("new")
		t.expect(
			fixture.exec(
				cap,
				"git",
				{ "merge-base", "--is-ancestor", git(origin, { "rev-parse", "main" }), "HEAD" }
			).ok
		).toBe(true)
		t.expect(git(cap, { "status", "--porcelain" })).toBe("")
		-- and prep can be reopened
		trOk(cap, { "status", rz, "preparing" })
		t.expect(trOk(cap, { "status", rz })).toBe("preparing")
		-- the status line is a fresh stamp each time, so a double move is a git conflict, not a silent merge
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local a = onOrigin(`pickman/.tracker/rafts/{rz}/{rz}.md`)
		t.expect(string.match(a or "", "\nstatus: preparing%-%a+%-%a+%-%a+\n") ~= nil).toBe(true)
	end)

	-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
	it(
		"a raft move follows the local member list: unclaimed members refuse, dropped members are untouched",
		function()
			local cnew = string.match(
				trOk(cap, { "new", "issue", "c", "iota", "--desc", "Iota.", "--project", "pickman" }),
				"(c%d+)"
			) :: string
			-- prep adds cnew to the raft locally (the document the prep PR will carry)
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			local doc = `{cap}/pickman/.tracker/rafts/{rz}/{rz}.md`
			-- the designs are ready (the move to prepared refuses otherwise)
			local function ready(path: string)
				fs.writeFile(path, (string.gsub(fs.readFile(path), "design: draft", "design: ready")))
			end
			-- the raft's own design counts too: a draft raft cannot be prepared, whatever its members say
			local rawRaft = tr(cap, { "status", rz, "prepared" })
			t.expect(rawRaft.ok).toBe(false)
			t.expect(has(rawRaft.stderr, rz)).toBe(true)
			t.expect(has(rawRaft.stderr, "design: ready")).toBe(true)
			ready(doc)
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			ready(`{cap}/pickman/.tracker/issues/{zeta}/{zeta}.md`)
			local original = fs.readFile(doc)
			fs.writeFile(doc, (string.gsub(original, "issues: %[(%S+)%]", `issues: [%1, {cnew}]`)))
			local before = git(origin, { "rev-parse", "main" })
			local refused = tr(cap, { "status", rz, "prepared" })
			t.expect(refused.ok).toBe(false)
			t.expect(has(refused.stderr, cnew)).toBe(true)
			t.expect(has(refused.stderr, `status {cnew} preparing`)).toBe(true)
			t.expect(git(origin, { "rev-parse", "main" })).toBe(before)
			-- claim it, then drop zeta: the carried move reaches cnew and the raft only
			trOk(cap, { "status", cnew, "preparing" })
			-- claimed, but its design is still a draft: the move refuses, naming it (the raft's own design is ready)
			local early = tr(cap, { "status", rz, "prepared" })
			t.expect(early.ok).toBe(false)
			t.expect(has(early.stderr, cnew)).toBe(true)
			t.expect(has(early.stderr, "design: ready")).toBe(true)
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			ready(`{cap}/pickman/.tracker/issues/{cnew}/{cnew}.md`)
			fs.writeFile(doc, (string.gsub(original, "issues: %[(%S+)%]", `issues: [{cnew}]`)))
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			local zetaDoc = `{cap}/pickman/.tracker/issues/{zeta}/{zeta}.md`
			local zetaBefore = fs.readFile(zetaDoc)
			trOk(cap, { "status", rz, "prepared" })
			t.expect(has(fs.readFile(doc), "status: prepared")).toBe(true)
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			t.expect(has(fs.readFile(`{cap}/pickman/.tracker/issues/{cnew}/{cnew}.md`), "status: prepared"))
				.toBe(true)
			t.expect(fs.readFile(zetaDoc)).toBe(zetaBefore)
			git(cap, { "checkout", "-q", "--", "." })
		end
	)

	it("new issue refuses --raft for a backlog raft, and new raft refuses an unclean tree", function()
		local r = tr(cap, { "new", "issue", "c", "kappa", "--raft", rz })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "--raft")).toBe(true)
		local id = string.match(
			trOk(cap, { "new", "issue", "c", "lambda", "--project", "pickman" }),
			"(c%d+)"
		) :: string
		fs.writeFile(`{cap}/stray.txt`, "x")
		local mid = git(origin, { "rev-parse", "main" })
		local dirty = tr(cap, { "new", "raft", "chore", "dirty", id, "--single", "--project", "pickman" })
		fs.removeFile(`{cap}/stray.txt`)
		t.expect(dirty.ok).toBe(false)
		t.expect(has(dirty.stderr, "clean")).toBe(true)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(mid)
	end)

	-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
	it(
		"an existing draft raft is claimed with status preparing, once; an issue in a raft is not stolen",
		function()
			local legacyRaft =
				"---\nid: R0800\ntype: chore\ntitle: Legacy\nslug: legacy\nsingle: false\nissues: [c0801]\ndesign: draft\ncreated: 2026-01-01\n---\n"
			local legacyIssue =
				"---\nid: c0801\ntype: chore\ntitle: Legacy issue\nslug: legacy-issue\nraft: R0800\ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-01-01\n---\n"
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			elsewhere({
				["pickman/.tracker/rafts/R0800/R0800.md"] = legacyRaft,
				["pickman/.tracker/issues/c0801/c0801.md"] = legacyIssue,
			}, "other legacy raft")
			trOk(cap, { "sync" })
			-- nothing stored, but the status is derived from the raft membership
			t.expect(trOk(cap, { "status", "R0800" })).toBe("preparing")
			t.expect(trOk(cap, { "status", "c0801" })).toBe("preparing")
			-- an issue that names a raft cannot be taken into another raft
			local before = git(origin, { "rev-parse", "main" })
			local steal =
				tr(cap, { "new", "raft", "chore", "steal", "c0801", "--single", "--project", "pickman" })
			t.expect(steal.ok).toBe(false)
			t.expect(has(steal.stderr, "R0800")).toBe(true)
			t.expect(git(origin, { "rev-parse", "main" })).toBe(before)
			-- claim it: the raft and its members get a stored stamp
			trOk(cap, { "status", "R0800", "preparing" })
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			t.expect(has(onOrigin("pickman/.tracker/rafts/R0800/R0800.md"), "status: preparing-")).toBe(true)
			t.expect(has(onOrigin("pickman/.tracker/issues/c0801/c0801.md"), "status: preparing-")).toBe(true)
			-- a second terminal is refused: it is stamped now
			local again = tr(cap, { "status", "R0800", "preparing" })
			t.expect(again.ok).toBe(false)
			t.expect(has(again.stderr, "cannot move")).toBe(true)
		end
	)
end)
