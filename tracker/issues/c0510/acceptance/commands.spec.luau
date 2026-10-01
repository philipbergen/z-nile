--!strict
-- c0510: the tracker CLI publishes state to origin/main. A bare origin and clones in .cache, driven
-- through `scripts/tracker.sh` in a worktree, exactly as a terminal would. Cases share one fixture
-- and run in order.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local base = `{root}/.cache/c0510-commands`
local origin, main, other = `{base}/origin.git`, `{base}/main`, `{base}/other`

-- git never looks for a repository above .cache: a fixture that loses its own .git fails instead of
-- falling through to the real repository (the incident c0640 and R0200 describe)
local function fenced(env: { [string]: string }?): { [string]: string }
	local out = { GIT_CEILING_DIRECTORIES = `{root}/.cache` }
	for k, v in env or {} do
		out[k] = v
	end
	return out
end

local function run(cwd: string, cmd: string, args: { string }, env: { [string]: string }?): Result
	return process.exec(cmd, args, { cwd = cwd, env = fenced(env) })
end
local function git(cwd: string, args: { string }): string
	local r = run(cwd, "git", args)
	if not r.ok then
		error(`git {table.concat(args, " ")} failed: {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end
local function tr(cwd: string, args: { string }, env: { [string]: string }?): Result
	return run(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) }, env)
end
local function trOk(cwd: string, args: { string }): string
	local r = tr(cwd, args)
	if not r.ok then
		error(`tracker.sh {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end
local function identity(cwd: string)
	git(cwd, { "config", "user.name", "t" })
	git(cwd, { "config", "user.email", "t@example.invalid" })
end
local function onOrigin(path: string): string? -- the file's text on origin's main, or nil
	local r = run(origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else nil
end
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
-- another terminal pushes a commit straight to origin's main
local function elsewhere(files: { [string]: string }, message: string)
	git(other, { "pull", "-q", "origin", "main" })
	for path, text in files do
		local parent = string.match(path, "^(.*)/[^/]+$")
		if parent then
			fs.writeDir(`{other}/{parent}`)
		end
		fs.writeFile(`{other}/{path}`, text)
	end
	git(other, { "add", "-A" })
	git(other, { "commit", "-q", "-m", message })
	git(other, { "push", "-q", "origin", "HEAD:main" })
end
local function setHook(body: string?)
	local path = `{main}/.git/hooks/pre-push`
	if body == nil then
		if fs.isFile(path) then
			fs.removeFile(path)
		end
		return
	end
	fs.writeFile(path, "#!/bin/bash\nunset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE\n" .. body)
	process.exec("chmod", { "+x", path })
end

-- a valid item document, as another terminal's `new` would have pushed it
local function stub(id: string, title: string, status: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {title}\nslug: {title}\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-01-01\nstatus: {status}\n---\n\n# {id}\n`
end

local cap = "" -- the capture worktree
local zeta, rz = "", "" -- the issue and raft of the "abandons prep" case
local offlineId = "" -- the issue the PICKMAN_PUBLISH=0 case creates

return t.spec("tracker commands publish state to origin/main", function(it)
	it("sets up a bare origin, a main checkout and a second terminal", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(`{base}/seed/tracker`)
		local seed = `{base}/seed`
		git(seed, { "init", "-q", "-b", "main" })
		identity(seed)
		process.exec("cp", { "-R", `{root}/scripts`, `{seed}/scripts` })
		process.exec("cp", { "-R", `{root}/tracker/templates`, `{seed}/tracker/templates` })
		fs.writeFile(`{seed}/.gitignore`, ".cache/\n.worktree/\n")
		for _, dir in { "issues/active", "issues/done", "rafts/active", "rafts/done" } do
			fs.writeDir(`{seed}/tracker/{dir}`)
			fs.writeFile(`{seed}/tracker/{dir}/.gitkeep`, "")
		end
		git(seed, { "add", "-A" })
		git(seed, { "commit", "-q", "-m", "seed" })
		git(base, { "clone", "-q", "--bare", seed, origin })
		git(base, { "clone", "-q", origin, main })
		git(base, { "clone", "-q", origin, other })
		identity(main)
		identity(other)
		cap = trOk(main, { "worktree", "cap-a" })
		t.expect(git(cap, { "branch", "--show-current" })).toBe("cap-a")
	end)

	it("new issue publishes the stub to origin/main and syncs the worktree to it", function()
		local out = trOk(cap, { "new", "issue", "c", "alpha", "--desc", "First line of alpha." })
		t.expect(out).toBe("tracker/issues/c0010/c0010.md")
		local doc = onOrigin("tracker/issues/c0010/c0010.md")
		t.expect(has(doc, "status: new")).toBe(true)
		t.expect(has(doc, "First line of alpha.")).toBe(true)
		t.expect(onOrigin("tracker/issues/c0010/check.sh") ~= nil).toBe(true)
		t.expect(string.sub(git(origin, { "ls-tree", "main", "tracker/issues/c0010/check.sh" }), 1, 6))
			.toBe("100755")
		t.expect(fs.isFile(`{cap}/tracker/issues/c0010/c0010.md`)).toBe(true)
		t.expect(git(cap, { "status", "--porcelain" })).toBe("") -- tracked and clean, not an untracked stub
		t.expect(git(cap, { "rev-parse", "HEAD" })).toBe(git(origin, { "rev-parse", "main" }))
	end)

	it("a local edit of the stub merges with origin/main without an add/add conflict", function()
		local doc = `{cap}/tracker/issues/c0010/c0010.md`
		fs.writeFile(doc, fs.readFile(doc) .. "\nMore detail.\n")
		git(cap, { "add", "-A" })
		git(cap, { "commit", "-q", "-m", "fill c0010" })
		elsewhere({ ["tracker/issues/f0100/f0100.md"] = stub("f0100", "remote-a", "new") }, "other f0100")
		trOk(cap, { "sync" })
		t.expect(fs.isFile(`{cap}/tracker/issues/f0100/f0100.md`)).toBe(true)
		t.expect(has(fs.readFile(doc), "More detail.")).toBe(true)
	end)

	it("ids are allocated above the highest id on origin, not only in the local tree", function()
		elsewhere({ ["tracker/issues/f0200/f0200.md"] = stub("f0200", "remote-b", "new") }, "other f0200")
		-- cap has not fetched f0200
		t.expect(fs.isFile(`{cap}/tracker/issues/f0200/f0200.md`)).toBe(false)
		t.expect(trOk(cap, { "new", "issue", "c", "beta" })).toBe("tracker/issues/c0210/c0210.md")
	end)

	it(
		"an id taken by another terminal during the push is never overwritten: the next one is used",
		function()
			setHook(
				`marker={base}/raced\n[ -e "$marker" ] && exit 0\ntouch "$marker"\ncd {other} && git pull -q origin main && mkdir -p tracker/issues/c0220 && printf -- '---\\nid: c0220\\ntype: chore\\ntitle: theirs\\nslug: theirs\\nraft: \\ndepends_on: []\\nstatus: new\\n---\\n' > tracker/issues/c0220/c0220.md && git add -A && git commit -qm theirs && git push -q origin HEAD:main\n`
			)
			local out = trOk(cap, { "new", "issue", "c", "gamma" })
			setHook(nil)
			t.expect(out).toBe("tracker/issues/c0230/c0230.md")
			t.expect(has(onOrigin("tracker/issues/c0220/c0220.md"), "title: theirs")).toBe(true)
			t.expect(onOrigin("tracker/issues/c0230/c0230.md") ~= nil).toBe(true)
		end
	)

	it("new raft claims its members in one commit, or none of them", function()
		trOk(cap, { "new", "issue", "c", "delta" }) -- c0240
		trOk(cap, { "new", "issue", "c", "epsilon" }) -- c0250
		-- another terminal claims c0250 first
		elsewhere({
			["tracker/issues/c0250/c0250.md"] = (onOrigin("tracker/issues/c0250/c0250.md") :: string):gsub(
				"status: new",
				"status: preparing"
			),
		}, "other claims c0250")
		local before = git(origin, { "rev-parse", "main" })
		local r = tr(cap, { "new", "raft", "chore", "demo", "c0240", "c0250" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "c0250")).toBe(true)
		t.expect(has(r.stderr, "preparing")).toBe(true)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(before)
		t.expect(has(onOrigin("tracker/issues/c0240/c0240.md"), "status: new")).toBe(true)
		t.expect(onOrigin("tracker/rafts/R0010/R0010.md")).toBe(nil)
		trOk(cap, { "new", "raft", "chore", "demo", "c0240", "--single" })
		local raft = onOrigin("tracker/rafts/R0010/R0010.md")
		t.expect(has(raft, "status: preparing")).toBe(true)
		t.expect(has(raft, "issues: [c0240]")).toBe(true)
		local member = onOrigin("tracker/issues/c0240/c0240.md")
		t.expect(has(member, "status: preparing")).toBe(true)
		t.expect(has(member, "raft: R0010")).toBe(false) -- origin never carries `raft:`: it sits beside depends_on
		t.expect(has(fs.readFile(`{cap}/tracker/issues/c0240/c0240.md`), "raft: R0010")).toBe(true)
		t.expect(git(cap, { "log", "-1", "--format=%s" })).toBe("tracker: R0010 members")
		t.expect(git(cap, { "status", "--porcelain" })).toBe("")
	end)

	it("status lists what origin says, even when this checkout is stale", function()
		elsewhere({ ["tracker/issues/f0300/f0300.md"] = stub("f0300", "remote-only", "new") }, "other f0300")
		t.expect(fs.isFile(`{cap}/tracker/issues/f0300/f0300.md`)).toBe(false)
		local list = trOk(cap, { "status" })
		t.expect(has(list, "f0300 new remote-only")).toBe(true)
		t.expect(has(list, "c0240 preparing")).toBe(true)
		t.expect(has(list, "R0010 preparing")).toBe(true)
		t.expect(trOk(cap, { "status", "c0240" })).toBe("preparing")
	end)

	it("a status move refuses to run in the main checkout, which is never edited", function()
		local r = tr(main, { "status", "c0240", "prepared" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "worktree")).toBe(true)
		t.expect(git(main, { "status", "--porcelain" })).toBe("")
	end)

	it("a move to prepared is carried by the PR: local edit only, nothing published", function()
		local before = git(origin, { "rev-parse", "main" })
		-- it refuses while the design is not ready: the two fields move together
		local early = tr(cap, { "status", "c0240", "prepared" })
		t.expect(early.ok).toBe(false)
		t.expect(has(early.stderr, "design: ready")).toBe(true)
		t.expect(has(fs.readFile(`{cap}/tracker/issues/c0240/c0240.md`), "status: prepared")).toBe(false)
		local c0240 = `{cap}/tracker/issues/c0240/c0240.md`
		fs.writeFile(c0240, (string.gsub(fs.readFile(c0240), "design: draft", "design: ready")))
		trOk(cap, { "status", "c0240", "prepared" })
		t.expect(has(fs.readFile(`{cap}/tracker/issues/c0240/c0240.md`), "status: prepared")).toBe(true)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(before)
		t.expect(has(onOrigin("tracker/issues/c0240/c0240.md"), "status: preparing")).toBe(true)
	end)

	it("a move is checked against origin, not the local file; invalid moves change nothing", function()
		-- locally c0240 says prepared (prepared>preparing would be legal), origin says preparing (it would not)
		local before = git(origin, { "rev-parse", "main" })
		local r = tr(cap, { "status", "c0240", "preparing" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "is preparing on origin/main")).toBe(true)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(before)
		local bad = tr(cap, { "status", "c0240", "done" })
		t.expect(bad.ok).toBe(false)
		t.expect(has(bad.stderr, "prepared")).toBe(false) -- names the origin status, not the local one
		local unknown = tr(cap, { "status", "c0240", "ready" })
		t.expect(unknown.ok).toBe(false)
	end)

	it("a prepared raft starts once: the second terminal is refused and nothing moves", function()
		-- prep lands: designs ready, statuses prepared, as a merged prep PR would
		for _, path in { "tracker/issues/c0240/c0240.md", "tracker/rafts/R0010/R0010.md" } do
			local text = fs.readFile(`{cap}/{path}`):gsub("design: draft", "design: ready")
			fs.writeFile(`{cap}/{path}`, text)
		end
		trOk(cap, { "status", "R0010", "prepared" })
		git(cap, { "add", "-A" })
		git(cap, { "commit", "-q", "-m", "tracker: prep R0010" })
		trOk(cap, { "sync" })
		git(cap, { "push", "-q", "origin", "HEAD:main" }) -- the prep PR merges
		git(other, { "pull", "-q", "origin", "main" })
		git(other, { "switch", "-q", "-c", "R0010-demo" })
		trOk(main, { "sync" })
		-- run in the main checkout, start is refused before it claims anything
		local tipBefore = git(origin, { "rev-parse", "main" })
		local refused = tr(main, { "start", "R0010" })
		t.expect(refused.ok).toBe(false)
		t.expect(has(refused.stderr, "worktree")).toBe(true)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(tipBefore)
		t.expect(git(main, { "status", "--porcelain" })).toBe("")
		local ws = trOk(main, { "worktree", "R0010" })
		local out = trOk(ws, { "start", "R0010" })
		t.expect(has(out, "R0010")).toBe(true)
		-- the claim is remembered in the worktree, so this terminal can resume it
		local saved = trim(fs.readFile(`{ws}/.cache/tracker-claim-R0010`))
		t.expect(has(onOrigin("tracker/rafts/R0010/R0010.md"), `status: {saved}`)).toBe(true)
		t.expect(string.match(saved, "^active%-%a+%-%a+%-%a+$") ~= nil).toBe(true)
		-- origin shows active at the backlog path, for the raft and its member, in one commit
		t.expect(has(onOrigin("tracker/rafts/R0010/R0010.md"), "status: active")).toBe(true)
		t.expect(has(onOrigin("tracker/issues/c0240/c0240.md"), "status: active")).toBe(true)
		t.expect(fs.isDir(`{ws}/tracker/rafts/active/R0010`)).toBe(true)
		t.expect(has(fs.readFile(`{ws}/tracker/rafts/active/R0010/R0010.md`), "status: active")).toBe(true)
		-- the second terminal still sees prepared locally
		local head, tip = git(other, { "rev-parse", "HEAD" }), git(origin, { "rev-parse", "main" })
		local r = tr(other, { "start", "R0010" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "active")).toBe(true)
		t.expect(git(other, { "rev-parse", "HEAD" })).toBe(head)
		t.expect(git(other, { "status", "--porcelain" })).toBe("")
		t.expect(fs.isDir(`{other}/tracker/rafts/active/R0010`)).toBe(false)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(tip)
	end)

	it("sync brings a worktree and the main checkout up to date", function()
		elsewhere({ ["tracker/issues/f0400/f0400.md"] = stub("f0400", "remote-c", "new") }, "other f0400")
		trOk(cap, { "sync" })
		t.expect(fs.isFile(`{cap}/tracker/issues/f0400/f0400.md`)).toBe(true)
		trOk(main, { "sync" })
		t.expect(git(main, { "rev-parse", "HEAD" })).toBe(git(origin, { "rev-parse", "main" }))
	end)

	it("a published move abandons prep for a raft and its members in one commit", function()
		trOk(cap, { "sync" })
		trOk(cap, { "new", "issue", "c", "zeta", "--desc", "Zeta." })
		zeta =
			string.match(trOk(cap, { "list", "backlog" }), "(c%d+)%s+backlog%s+chore%s+%S*%s+Zeta") :: string
		local raftDoc = trOk(cap, { "new", "raft", "chore", "zraft", zeta, "--single" })
		rz = string.match(raftDoc, "(R%d+)") :: string
		t.expect(trOk(cap, { "status", rz })).toBe("preparing")
		local before = git(origin, { "rev-parse", "main" })
		trOk(cap, { "status", rz, "new" })
		local files = git(origin, { "diff", "--name-only", before, "main" })
		t.expect(has(files, `tracker/rafts/{rz}/{rz}.md`)).toBe(true)
		t.expect(has(files, `tracker/issues/{zeta}/{zeta}.md`)).toBe(true)
		t.expect(#string.split(files, "\n")).toBe(2)
		t.expect(git(origin, { "rev-list", "--count", `{before}..main` })).toBe("1")
		t.expect(trOk(cap, { "status", rz })).toBe("new")
		t.expect(trOk(cap, { "status", zeta })).toBe("new")
		t.expect(
			run(cap, "git", { "merge-base", "--is-ancestor", git(origin, { "rev-parse", "main" }), "HEAD" }).ok
		)
			.toBe(true)
		t.expect(git(cap, { "status", "--porcelain" })).toBe("")
		-- and prep can be reopened
		trOk(cap, { "status", rz, "preparing" })
		t.expect(trOk(cap, { "status", rz })).toBe("preparing")
		-- the status line is a fresh stamp each time, so a double move is a git conflict, not a silent merge
		local a = onOrigin(`tracker/rafts/{rz}/{rz}.md`)
		t.expect(string.match(a or "", "\nstatus: preparing%-%a+%-%a+%-%a+\n") ~= nil).toBe(true)
	end)

	it(
		"a raft move follows the local member list: unclaimed members refuse, dropped members are untouched",
		function()
			local cnew =
				string.match(trOk(cap, { "new", "issue", "c", "iota", "--desc", "Iota." }), "(c%d+)") :: string
			-- prep adds cnew to the raft locally (the document the prep PR will carry)
			local doc = `{cap}/tracker/rafts/{rz}/{rz}.md`
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
			ready(`{cap}/tracker/issues/{zeta}/{zeta}.md`)
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
			ready(`{cap}/tracker/issues/{cnew}/{cnew}.md`)
			fs.writeFile(doc, (string.gsub(original, "issues: %[(%S+)%]", `issues: [{cnew}]`)))
			local zetaDoc = `{cap}/tracker/issues/{zeta}/{zeta}.md`
			local zetaBefore = fs.readFile(zetaDoc)
			trOk(cap, { "status", rz, "prepared" })
			t.expect(has(fs.readFile(doc), "status: prepared")).toBe(true)
			t.expect(has(fs.readFile(`{cap}/tracker/issues/{cnew}/{cnew}.md`), "status: prepared")).toBe(true)
			t.expect(fs.readFile(zetaDoc)).toBe(zetaBefore)
			git(cap, { "checkout", "-q", "--", "." })
		end
	)

	it("new issue refuses --raft for a backlog raft, and new raft refuses an unclean tree", function()
		local r = tr(cap, { "new", "issue", "c", "kappa", "--raft", rz })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "--raft")).toBe(true)
		local id = string.match(trOk(cap, { "new", "issue", "c", "lambda" }), "(c%d+)") :: string
		fs.writeFile(`{cap}/stray.txt`, "x")
		local mid = git(origin, { "rev-parse", "main" })
		local dirty = tr(cap, { "new", "raft", "chore", "dirty", id, "--single" })
		fs.removeFile(`{cap}/stray.txt`)
		t.expect(dirty.ok).toBe(false)
		t.expect(has(dirty.stderr, "clean")).toBe(true)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(mid)
	end)

	it(
		"an existing draft raft is claimed with status preparing, once; an issue in a raft is not stolen",
		function()
			local legacyRaft =
				"---\nid: R0800\ntype: chore\ntitle: Legacy\nslug: legacy\nsingle: false\nissues: [c0801]\ndesign: draft\ncreated: 2026-01-01\n---\n"
			local legacyIssue =
				"---\nid: c0801\ntype: chore\ntitle: Legacy issue\nslug: legacy-issue\nraft: R0800\ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-01-01\n---\n"
			elsewhere({
				["tracker/rafts/R0800/R0800.md"] = legacyRaft,
				["tracker/issues/c0801/c0801.md"] = legacyIssue,
			}, "other legacy raft")
			trOk(cap, { "sync" })
			-- nothing stored, but the status is derived from the raft membership
			t.expect(trOk(cap, { "status", "R0800" })).toBe("preparing")
			t.expect(trOk(cap, { "status", "c0801" })).toBe("preparing")
			-- an issue that names a raft cannot be taken into another raft
			local before = git(origin, { "rev-parse", "main" })
			local steal = tr(cap, { "new", "raft", "chore", "steal", "c0801", "--single" })
			t.expect(steal.ok).toBe(false)
			t.expect(has(steal.stderr, "R0800")).toBe(true)
			t.expect(git(origin, { "rev-parse", "main" })).toBe(before)
			-- claim it: the raft and its members get a stored stamp
			trOk(cap, { "status", "R0800", "preparing" })
			t.expect(has(onOrigin("tracker/rafts/R0800/R0800.md"), "status: preparing-")).toBe(true)
			t.expect(has(onOrigin("tracker/issues/c0801/c0801.md"), "status: preparing-")).toBe(true)
			-- a second terminal is refused: it is stamped now
			local again = tr(cap, { "status", "R0800", "preparing" })
			t.expect(again.ok).toBe(false)
			t.expect(has(again.stderr, "cannot move")).toBe(true)
		end
	)

	it(
		"a tracker command in a directory that lost its .git refuses instead of using the enclosing repository",
		function()
			-- the incident: a fixture's .git vanished and git walked up to the real repository, with its origin
			local outer = `{base}/outer`
			if fs.isDir(outer) then
				fs.removeDir(outer)
			end
			fs.writeDir(`{outer}/seed`)
			git(`{outer}/seed`, { "init", "-q", "-b", "main" })
			identity(`{outer}/seed`)
			fs.writeFile(`{outer}/seed/readme`, "x")
			git(`{outer}/seed`, { "add", "-A" })
			git(`{outer}/seed`, { "commit", "-q", "-m", "seed" })
			git(outer, { "clone", "-q", "--bare", `{outer}/seed`, `{outer}/origin.git` })
			git(outer, { "clone", "-q", `{outer}/origin.git`, `{outer}/repo` })
			identity(`{outer}/repo`)
			-- a directory with a copy of the tracker but no .git, inside the outer repository
			git(`{outer}/repo`, { "worktree", "add", "-q", "-b", "w", `{outer}/wt` })
			local lost = `{outer}/wt/lost`
			fs.writeDir(`{lost}/tracker`)
			process.exec("cp", { "-R", `{root}/scripts`, `{lost}/scripts` })
			process.exec("cp", { "-R", `{root}/tracker/templates`, `{lost}/tracker/templates` })
			local before = git(`{outer}/origin.git`, { "rev-parse", "main" })
			-- every command that is not read-only is refused, not just the ones that publish
			local writing = {
				{ "new", "issue", "c", "x" },
				{ "new", "raft", "chore", "r", "c0010", "--single" },
				{ "renumber", "c0010", "c0011" },
				{ "migrate" },
				{ "start", "R0010" },
				{ "focus", "c0010" },
				{ "commit", "-m", "x" },
				{ "done", "R0010" },
				{ "check", "c0010" },
				{ "status" },
				{ "sync" },
				{ "worktree", "zz" },
				{ "worktree-prune" },
				{ "prompt", "c0010", "--stdout" },
			}
			for _, args in writing do
				local r = tr(lost, args)
				t.expect(r.ok).toBe(false)
				t.expect(has(r.stderr, "repository root")).toBe(true)
			end
			-- the read-only commands are exempt (other specs run them in sandboxes without a .git)
			for _, args in
				{
					{ "list" },
					{ "find", "c0010" },
					{ "members", "R0010" },
					{ "metrics" },
					{ "board", "--out", `{lost}/board.html` },
					{ "workstreams", "R0010" },
					{ "promote-check", "R0010" },
					{ "stamp", "new" },
				}
			do
				t.expect(has(tr(lost, args).stderr, "repository root")).toBe(false)
			end
			-- turning publishing off does not switch the guard off
			local offline = tr(lost, { "new", "issue", "c", "y" }, { PICKMAN_PUBLISH = "0" })
			t.expect(offline.ok).toBe(false)
			t.expect(has(offline.stderr, "repository root")).toBe(true)
			t.expect(has(git(`{outer}/repo`, { "worktree", "list" }), "zz")).toBe(false)
			t.expect(git(`{outer}/origin.git`, { "rev-parse", "main" })).toBe(before)
			t.expect(fs.isDir(`{lost}/tracker/issues`)).toBe(false)
		end
	)

	it(
		"a started raft goes back to prepared on origin, and the branch that already moved it merges cleanly",
		function()
			local ws = `{base}/main/.worktree/R0010`
			local before = git(origin, { "rev-parse", "main" })
			trOk(ws, { "status", "R0010", "prepared" })
			t.expect(trOk(ws, { "status", "R0010" })).toBe("prepared")
			t.expect(trOk(ws, { "status", "c0240" })).toBe("prepared")
			t.expect(git(origin, { "rev-list", "--count", `{before}..main` })).toBe("1")
			t.expect(has(fs.readFile(`{ws}/tracker/rafts/active/R0010/R0010.md`), "status: prepared"))
				.toBe(true)
			t.expect(git(ws, { "status", "--porcelain" })).toBe("")
		end
	)

	it("a start that dies after its claim is resumed by this terminal and refused to every other", function()
		-- the earlier worktree and branch go away: the raft is prepared on origin again
		git(main, { "worktree", "remove", "--force", `{base}/main/.worktree/R0010` })
		git(main, { "branch", "-D", "R0010-demo" })
		git(origin, { "branch", "-D", "R0010-demo" })
		trOk(main, { "sync" })
		local wt = trOk(main, { "worktree", "resume-r" })
		-- a local commit edits the raft's status line, so merging origin's claim conflicts and start dies after it
		local doc = `{wt}/tracker/rafts/R0010/R0010.md`
		fs.writeFile(doc, (string.gsub(fs.readFile(doc), "\nstatus: [^\n]*", "\nstatus: prepared-zz-zz-zz")))
		git(wt, { "commit", "-q", "-am", "local edit of the status line" })
		local died = tr(wt, { "start", "R0010" })
		t.expect(died.ok).toBe(false)
		t.expect(has(died.stderr, "merge")).toBe(true)
		local claim = trim(fs.readFile(`{wt}/.cache/tracker-claim-R0010`))
		t.expect(has(onOrigin("tracker/rafts/R0010/R0010.md"), `status: {claim}`)).toBe(true)
		t.expect(fs.isDir(`{wt}/tracker/rafts/active/R0010`)).toBe(false) -- nothing moved locally
		-- another terminal has no claim file and is refused
		local wt2 = trOk(main, { "worktree", "resume-r2" })
		trOk(wt2, { "sync" })
		local other2 = tr(wt2, { "start", "R0010" })
		t.expect(other2.ok).toBe(false)
		t.expect(has(other2.stderr, "active")).toBe(true)
		-- this terminal resolves the conflict and runs start again: it continues without publishing anything
		git(wt, { "reset", "-q", "--hard", "HEAD~1" })
		local tip = git(origin, { "rev-parse", "main" })
		local ok = tr(wt, { "start", "R0010" })
		t.expect(ok.stderr).toBe("")
		t.expect(ok.ok).toBe(true)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(tip)
		t.expect(fs.isDir(`{wt}/tracker/rafts/active/R0010`)).toBe(true)
		-- `status <id> active` is not a way to take the lock: only start claims
		local direct = tr(wt2, { "status", "R0010", "active" })
		t.expect(direct.ok).toBe(false)
		t.expect(has(direct.stderr, "only tracker.sh start")).toBe(true)
		-- giving the claim back ends this worktree's ownership: its claim file goes
		t.expect(fs.isFile(`{wt}/.cache/tracker-claim-R0010`)).toBe(true)
		trOk(wt, { "status", "R0010", "prepared" })
		t.expect(fs.isFile(`{wt}/.cache/tracker-claim-R0010`)).toBe(false)
		t.expect(trOk(wt, { "status", "R0010" })).toBe("prepared")
	end)

	it(
		"sync --fetch updates origin/main and leaves HEAD alone; new issue in a raft worktree does not merge",
		function()
			local ws = `{base}/main/.worktree/resume-r`
			elsewhere({ ["tracker/issues/f0500/f0500.md"] = stub("f0500", "remote-d", "new") }, "other f0500")
			local head = git(ws, { "rev-parse", "HEAD" })
			trOk(ws, { "sync", "--fetch" })
			t.expect(git(ws, { "rev-parse", "HEAD" })).toBe(head)
			t.expect(git(ws, { "rev-parse", "origin/main" })).toBe(git(origin, { "rev-parse", "main" }))
			t.expect(fs.isFile(`{ws}/tracker/issues/f0500/f0500.md`)).toBe(false)
			-- an active raft is on this branch: the new stub is published but the branch is not touched
			local out = trOk(ws, { "new", "issue", "c", "postponed" })
			t.expect(git(ws, { "rev-parse", "HEAD" })).toBe(head)
			t.expect(fs.isFile(`{ws}/{out}`)).toBe(false)
			t.expect(onOrigin(out) ~= nil).toBe(true)
			-- the full sync brings both in
			trOk(ws, { "sync" })
			t.expect(fs.isFile(`{ws}/{out}`)).toBe(true)
		end
	)

	it("PICKMAN_PUBLISH=0 keeps a command local: ids step by 10 and nothing is pushed", function()
		trOk(cap, { "sync" })
		local tip = git(origin, { "rev-parse", "main" })
		local r = tr(cap, { "new", "issue", "c", "offline" }, { PICKMAN_PUBLISH = "0" })
		t.expect(r.ok).toBe(true)
		offlineId = string.match(trim(r.stdout), "tracker/issues/(c%d+)/") :: string
		t.expect(trim(r.stdout)).toBe(`tracker/issues/{offlineId}/{offlineId}.md`)
		t.expect(git(origin, { "rev-parse", "main" })).toBe(tip)
		t.expect(fs.isFile(`{cap}/tracker/issues/{offlineId}/{offlineId}.md`)).toBe(true)
		t.expect(git(cap, { "status", "--porcelain" })).toBe(`?? tracker/issues/{offlineId}/`)
	end)

	it(
		"raft ids come from the union of the local tree and origin, and an item made ready offline can start",
		function()
			trOk(cap, { "sync" })
			-- the offline issue from the previous case; make it a local-only raft and ready it the old way
			local local1 = tr(
				cap,
				{ "new", "raft", "chore", "offline-raft", offlineId, "--single" },
				{ PICKMAN_PUBLISH = "0" }
			)
			t.expect(local1.ok).toBe(true)
			local localRaft = string.match(trim(local1.stdout), "(R%d+)") :: string
			for _, path in
				{ `tracker/issues/{offlineId}/{offlineId}.md`, `tracker/rafts/{localRaft}/{localRaft}.md` }
			do
				fs.writeFile(
					`{cap}/{path}`,
					(fs.readFile(`{cap}/{path}`):gsub("design: draft", "design: ready"))
				)
			end
			git(cap, { "add", "-A" })
			git(cap, { "commit", "-q", "-m", "offline prep" })
			trOk(cap, { "new", "issue", "c", "theta" })
			local theta = string.match(
				trOk(cap, { "list", "backlog" }),
				"(c%d+)%s+backlog%s+chore%s+%S*%s+Theta"
			) :: string
			local made = trOk(cap, { "new", "raft", "chore", "published-raft", theta, "--single" })
			local made_id = tonumber(string.match(made, "R(%d+)") :: string) :: number
			local local_id = tonumber(string.sub(localRaft, 2)) :: number
			t.expect(made_id > local_id).toBe(true) -- not reusing the local-only raft's number
			-- the offline raft reaches origin through a PR, then starts: its items derive `prepared` from design: ready
			git(cap, { "push", "-q", "origin", "HEAD:main" })
			trOk(main, { "sync" })
			local wt = trOk(main, { "worktree", localRaft })
			local started = tr(wt, { "start", localRaft })
			t.expect(started.ok).toBe(true)
			t.expect(has(onOrigin(`tracker/rafts/{localRaft}/{localRaft}.md`), "status: active")).toBe(true)
		end
	)

	it("stamps from processes started together differ, so identical moves conflict in git", function()
		-- three terminals stamp at the same moment: a time-based seed would give them one phrase
		local out = process.exec("bash", {
			"-c",
			`cd {cap} && (bash scripts/tracker.sh stamp new & bash scripts/tracker.sh stamp new & bash scripts/tracker.sh stamp new & wait)`,
		}, { env = fenced() })
		t.expect(out.ok).toBe(true)
		local stamps: { string } = {}
		for line in string.gmatch(out.stdout, "[^\n]+") do
			t.expect(string.match(line, "^new%-%a+%-%a+%-%a+$") ~= nil).toBe(true)
			table.insert(stamps, line)
		end
		t.expect(#stamps).toBe(3)
		t.expect(stamps[1] == stamps[2] or stamps[1] == stamps[3] or stamps[2] == stamps[3]).toBe(false)
		-- the stubs the CLI publishes carry such stamps too
		local doc = onOrigin("tracker/issues/c0010/c0010.md") or ""
		t.expect(string.match(doc, "\nstatus: new%-%a+%-%a+%-%a+\n") ~= nil).toBe(true)
	end)
end)
