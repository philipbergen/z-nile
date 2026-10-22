--!strict
-- c0062: one part of c0510's commands spec, split so that `tests/run` runs the parts concurrently.
-- This part: starting a prepared raft once, giving the claim back, resuming a start that died, and `sync --fetch`.
-- Driven through `scripts/tracker.sh` in a worktree, exactly as a terminal would. Cases share this part's fixture
-- and run in order.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local git = fixture.git
local f: trackerfix.Fixture = { base = "", origin = "", main = "", other = "" }
local base, origin, main, other = "", "", "", ""

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
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
local stub = trackerfix.stub

local cap = "" -- the capture worktree

return t.spec("tracker commands publish state to origin/main (start)", function(it)
	it("sets up the start fixture", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		-- R0001 and its member c0240 are claimed on origin, as `new raft` leaves them, with drafts for designs
		local claim = "preparing-quiet-copper-falcon"
		local raft = "---\nid: R0001\ntype: chore\ntitle: Demo\nslug: demo\nsingle: true\nissues: [c0240]\ndesign: draft\ncreated: 2026-01-01\nstatus: "
			.. claim
			.. "\n---\n\n# R0001: Demo\n"
		-- the member names its raft, as the local commit that "new raft claims" leaves in the capture worktree does
		local member = string.gsub(trackerfix.stub("c0240", "member", claim), "\nraft: \n", "\nraft: R0001\n")
		local seed = {
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			["pickman/.tracker/rafts/R0001/R0001.md"] = raft,
			["pickman/.tracker/issues/c0240/c0240.md"] = member,
		}
		f = trackerfix.new("c0053-commands-start", seed)
		base, origin, main, other = f.base, f.origin, f.main, f.other
		cap = trOk(main, { "worktree", "cap-a" })
		t.expect(git(cap, { "branch", "--show-current" })).toBe("cap-a")
	end)

	it("a prepared raft starts once: the second terminal is refused and nothing moves", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		-- prep lands: designs ready, statuses prepared, as a merged prep PR would
		for _, path in { "pickman/.tracker/issues/c0240/c0240.md", "pickman/.tracker/rafts/R0001/R0001.md" } do
			local text = fs.readFile(`{cap}/{path}`):gsub("design: draft", "design: ready")
			fs.writeFile(`{cap}/{path}`, text)
		end
		trOk(cap, { "status", "R0001", "prepared" })
		git(cap, { "add", "-A" })
		git(cap, { "commit", "-q", "-m", "tracker: prep R0001" })
		trOk(cap, { "sync" })
		git(cap, { "push", "-q", "origin", "HEAD:main" }) -- the prep PR merges
		git(other, { "pull", "-q", "origin", "main" })
		git(other, { "switch", "-q", "-c", "R0001-demo" })
		trOk(main, { "sync" })
		-- run in the main checkout, start is refused before it claims anything
		local tipBefore = git(origin, { "rev-parse", "main" })
		local refused = tr(main, { "start", "R0001" })
		t.expect(refused.ok).toBe(false)
		t.expect(has(refused.stderr, "worktree")).toBe(true)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(tipBefore)
		t.expect(git(main, { "status", "--porcelain" })).toBe("")
		local ws = trOk(main, { "worktree", "R0001" })
		local out = trOk(ws, { "start", "R0001" })
		t.expect(has(out, "R0001")).toBe(true)
		-- the claim is remembered in the worktree, so this terminal can resume it
		local saved = trim(fs.readFile(`{ws}/.cache/tracker-claim-R0001`))
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(has(onOrigin("pickman/.tracker/rafts/R0001/R0001.md"), `status: {saved}`)).toBe(true)
		t.expect(string.match(saved, "^active%-%a+%-%a+%-%a+$") ~= nil).toBe(true)
		-- origin shows active at the backlog path, for the raft and its member, in one commit
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(has(onOrigin("pickman/.tracker/rafts/R0001/R0001.md"), "status: active")).toBe(true)
		t.expect(has(onOrigin("pickman/.tracker/issues/c0240/c0240.md"), "status: active")).toBe(true)
		t.expect(fs.isDir(`{ws}/pickman/.tracker/rafts/active/R0001`)).toBe(true)
		t.expect(has(fs.readFile(`{ws}/pickman/.tracker/rafts/active/R0001/R0001.md`), "status: active"))
			.toBe(true)
		-- the second terminal still sees prepared locally
		local head, tip = git(other, { "rev-parse", "HEAD" }), git(origin, { "rev-parse", "main" })
		local r = tr(other, { "start", "R0001" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "active")).toBe(true)
		t.expect(git(other, { "rev-parse", "HEAD" })).toBe(head)
		t.expect(git(other, { "status", "--porcelain" })).toBe("")
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(fs.isDir(`{other}/pickman/.tracker/rafts/active/R0001`)).toBe(false)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(tip)
	end)

	-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
	it(
		"a started raft goes back to prepared on origin, and the branch that already moved it merges cleanly",
		function()
			local ws = `{base}/main/.worktree/R0001`
			local before = git(origin, { "rev-parse", "main" })
			trOk(ws, { "status", "R0001", "prepared" })
			t.expect(trOk(ws, { "status", "R0001" })).toBe("prepared")
			t.expect(trOk(ws, { "status", "c0240" })).toBe("prepared")
			t.expect(git(origin, { "rev-list", "--count", `{before}..main` })).toBe("1")
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			t.expect(
				has(fs.readFile(`{ws}/pickman/.tracker/rafts/active/R0001/R0001.md`), "status: prepared")
			)
				.toBe(true)
			t.expect(git(ws, { "status", "--porcelain" })).toBe("")
		end
	)

	it("a start that dies after its claim is resumed by this terminal and refused to every other", function()
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		-- the earlier worktree and branch go away: the raft is prepared on origin again
		git(main, { "worktree", "remove", "--force", `{base}/main/.worktree/R0001` })
		git(main, { "branch", "-D", "R0001-demo" })
		git(origin, { "branch", "-D", "R0001-demo" })
		trOk(main, { "sync" })
		local wt = trOk(main, { "worktree", "resume-r" })
		-- a local commit edits the raft's status line, so merging origin's claim conflicts and start dies after it
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		local doc = `{wt}/pickman/.tracker/rafts/R0001/R0001.md`
		fs.writeFile(doc, (string.gsub(fs.readFile(doc), "\nstatus: [^\n]*", "\nstatus: prepared-zz-zz-zz")))
		git(wt, { "commit", "-q", "-am", "local edit of the status line" })
		local died = tr(wt, { "start", "R0001" })
		t.expect(died.ok).toBe(false)
		t.expect(has(died.stderr, "merge")).toBe(true)
		local claim = trim(fs.readFile(`{wt}/.cache/tracker-claim-R0001`))
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(has(onOrigin("pickman/.tracker/rafts/R0001/R0001.md"), `status: {claim}`)).toBe(true)
		t.expect(fs.isDir(`{wt}/pickman/.tracker/rafts/active/R0001`)).toBe(false) -- nothing moved locally
		-- another terminal has no claim file and is refused
		local wt2 = trOk(main, { "worktree", "resume-r2" })
		trOk(wt2, { "sync" })
		local other2 = tr(wt2, { "start", "R0001" })
		t.expect(other2.ok).toBe(false)
		t.expect(has(other2.stderr, "active")).toBe(true)
		-- this terminal resolves the conflict and runs start again: it continues without publishing anything
		git(wt, { "reset", "-q", "--hard", "HEAD~1" })
		local tip = git(origin, { "rev-parse", "main" })
		local ok = tr(wt, { "start", "R0001" })
		t.expect(ok.stderr).toBe("")
		t.expect(ok.ok).toBe(true)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(tip)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(fs.isDir(`{wt}/pickman/.tracker/rafts/active/R0001`)).toBe(true)
		-- `status <id> active` is not a way to take the lock: only start claims
		local direct = tr(wt2, { "status", "R0001", "active" })
		t.expect(direct.ok).toBe(false)
		t.expect(has(direct.stderr, "only ./zn start")).toBe(true)
		-- giving the claim back ends this worktree's ownership: its claim file goes
		t.expect(fs.isFile(`{wt}/.cache/tracker-claim-R0001`)).toBe(true)
		trOk(wt, { "status", "R0001", "prepared" })
		t.expect(fs.isFile(`{wt}/.cache/tracker-claim-R0001`)).toBe(false)
		t.expect(trOk(wt, { "status", "R0001" })).toBe("prepared")
	end)

	-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
	it(
		"sync --fetch updates origin/main and leaves HEAD alone; new issue in a raft worktree does not merge",
		function()
			local ws = `{base}/main/.worktree/resume-r`
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			elsewhere(
				{ ["pickman/.tracker/issues/f0500/f0500.md"] = stub("f0500", "remote-d", "new") },
				"other f0500"
			)
			local head = git(ws, { "rev-parse", "HEAD" })
			trOk(ws, { "sync", "--fetch" })
			t.expect(git(ws, { "rev-parse", "HEAD" })).toBe(head)
			t.expect(git(ws, { "rev-parse", "origin/main" })).toBe(git(origin, { "rev-parse", "main" }))
			-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
			t.expect(fs.isFile(`{ws}/pickman/.tracker/issues/f0500/f0500.md`)).toBe(false)
			-- an active raft is on this branch: the new stub is published but the branch is not touched
			local out = trOk(ws, { "new", "issue", "c", "postponed", "--project", "pickman" })
			t.expect(git(ws, { "rev-parse", "HEAD" })).toBe(head)
			t.expect(fs.isFile(`{ws}/{out}`)).toBe(false)
			t.expect(onOrigin(out) ~= nil).toBe(true)
			-- the full sync brings both in
			trOk(ws, { "sync" })
			t.expect(fs.isFile(`{ws}/{out}`)).toBe(true)
		end
	)
end)
