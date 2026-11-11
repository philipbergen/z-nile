--!strict
-- c0084: `tracker.sh spend` records a phase's spend (capture, prep, design-review, deliver) outside an active raft. It
-- commits one measured row per file under the item's spend.d/ on the current branch and pushes nothing to origin/main.
-- --time and --tokens are accepted and ignored. An existing spend.md is left as it was.
-- Fixture under .cache/c0084-spend: a seed with this tree's tooling, a bare origin, a main clone, a second clone, and
-- a prep worktree made by `tracker.sh worktree`. Ids come from `new issue` and `new raft`, never from literals.
local buffer = require("@znile/engine/buffer")
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ledger = require("@scripts/tracker/ledger")
local process = require("@lune/process")
local publish = require("@scripts/tracker/publish")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
-- c0120 override: fixtures live under the home's .cache (z-nile/.cache); root stays the checkout to copy from
local base = `{trim(process.exec("pwd", { "-P" }).stdout)}/.cache/c0084-spend`
local seed, origin, main, other = `{base}/seed`, `{base}/origin.git`, `{base}/main`, `{base}/other`

local function git(cwd: string, args: { string }): string
	return fixture.git(cwd, args)
end
local function tr(cwd: string, args: { string }): Result
	return fixture.exec(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) })
end
local function trOk(cwd: string, args: { string }): string
	local r = tr(cwd, args)
	if not r.ok then
		error(`tracker.sh {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function tip(): string
	return git(origin, { "rev-parse", "main" })
end
local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function identity(dir: string)
	git(dir, { "config", "user.name", "spend" })
	git(dir, { "config", "user.email", "spend@example.invalid" })
end
-- the ledger of an issue on origin/main, at whatever state directory it is in
local function onOrigin(path: string): any
	local text = git(origin, { "show", `main:{path}` }) .. "\n"
	local l, err = ledger.parse(text)
	if not l then
		error(`{path} on origin does not parse: {err}`, 2)
	end
	return l
end
-- `./zn spend` commits on the branch it runs in. The row is read there, not from origin.
-- Declared before the helpers that close over it: a local's scope starts at its declaration.
local prep = ""
local a, b, raft = "", "", ""
-- spend.md plus every spend.d file, in name order. A measured row is its own file, so two checkouts never edit one.
local function onBranch(path: string): any
	local dir = if string.sub(path, -9) == "/spend.md" then string.sub(path, 1, -10) else path
	local listed = git(prep, { "ls-tree", "-r", "--name-only", "HEAD", "--", dir })
	local files: { string } = {}
	for file in string.gmatch(listed .. "\n", "([^\n]*)\n") do
		local measured = string.find(file, "/spend.d/", 1, true) ~= nil
			and (string.sub(file, -4) == ".tsv" or string.sub(file, -3) == ".md")
		if file == path or measured then
			table.insert(files, file)
		end
	end
	table.sort(files, function(x: string, y: string): boolean
		local function rank(s: string): string
			return if string.sub(s, -9) == "/spend.md" then "0" .. s else "1" .. s
		end
		return rank(x) < rank(y)
	end)
	local rows: { any } = {}
	local id, title = "", ""
	local saw = false
	for _, file in files do
		do
			local text = git(prep, { "show", `HEAD:{file}` }) .. "\n"
			if string.sub(file, -4) == ".tsv" then
				local parsed, err = buffer.parseTsv(text)
				if not parsed then
					error(`{file} on the branch does not parse: {err}`, 2)
				end
				saw = true
				if id == "" then
					id = string.match(file, "/([fdcR]%d%d%d%d)/") or ""
				end
				for _, row in parsed do
					table.insert(rows, row)
				end
			else
				local l, err = ledger.parse(text)
				if not l then
					error(`{file} on the branch does not parse: {err}`, 2)
				end
				saw = true
				if l.id ~= "" and id == "" then
					id, title = l.id, l.title
				end
				for _, row in l.rows do
					table.insert(rows, row)
				end
			end
		end
	end
	if not saw then
		error(`{path} on the branch has no spend rows`, 2)
	end
	return { id = id, title = title, rows = rows }
end
local function last(path: string): any
	local l = onBranch(path)
	return l.rows[#l.rows]
end
local function branchChanged(before: string): string
	return git(prep, { "diff", "--name-only", before, "HEAD" })
end

return t.spec("tracker spend", function(it)
	it("sets up an origin, a main checkout, a second clone and a prep worktree with a raft of two", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(seed)
		process.exec("git", { "init", "-q", "-b", "main", seed }) -- raw: init to a named path
		identity(seed)
		for _, p in { ".claude", ".luaurc", ".gitignore", "rokit.toml" } do
			process.exec("cp", { "-R", `{root}/{p}`, `{seed}/{p}` })
		end
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		fs.writeDir(`{seed}/pickman/.tracker`)
		engine.copy(root, seed) -- c0114 override: ./zn, scripts/ and z-nile/ (the engine, the gate, the templates)
		-- c0120 override: the checkout keeps pickman's architecture.md in pickman/.tracker, the fixtures' pickman root too
		process.exec(
			"cp",
			{ `{root}/pickman/.tracker/architecture.md`, `{seed}/pickman/.tracker/architecture.md` }
		) -- ready's prompt
		for _, d in { "issues/active", "issues/done", "rafts/active", "rafts/done" } do
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			write(`{seed}/pickman/.tracker/{d}/.gitkeep`, "")
		end
		git(seed, { "add", "-A" })
		git(seed, { "commit", "-q", "-m", "seed" })
		process.exec("git", { "clone", "-q", "--bare", seed, origin }) -- raw: clone to a named path
		for _, c in { main, other } do
			process.exec("git", { "clone", "-q", origin, c }) -- raw: clone to a named path
			identity(c)
		end
		prep = trOk(main, { "worktree", "prep-demo" })
		identity(prep)
		a = string.match(
			trOk(prep, { "new", "issue", "c", "alpha", "--desc", "Alpha.", "--project", "pickman" }),
			"(c%d%d%d%d)"
		) :: string
		b = string.match(
			trOk(prep, { "new", "issue", "c", "beta", "--desc", "Beta.", "--project", "pickman" }),
			"(c%d%d%d%d)"
		) :: string
		raft = string.match(
			trOk(prep, { "new", "raft", "chore", "demo", a, b, "--project", "pickman" }),
			"(R%d%d%d%d)"
		) :: string
		t.expect(a ~= b).toBe(true)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(has(git(origin, { "show", `main:pickman/.tracker/rafts/{raft}/{raft}.md` }), a)).toBe(true)
	end)

	it("commits one capture row on the branch and pushes nothing to origin/main", function()
		local before, head = tip(), git(prep, { "rev-parse", "HEAD" })
		local out = trOk(prep, {
			"spend",
			a,
			"--phase",
			"capture",
			"--time",
			"4",
			"--tokens",
			"1200",
			"--note",
			"captured alpha",
		})
		t.expect(has(out, a)).toBe(true)
		t.expect(tip()).toBe(before)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(string.find(branchChanged(head), `pickman/.tracker/issues/{a}/spend.d/`, 1, true) ~= nil)
			.toBe(true)
		local l = onBranch(`pickman/.tracker/issues/{a}/spend.md`)
		t.expect(#l.rows).toBe(1)
		t.expect(l.id).toBe(a)
		t.expect(l.rows[1].phase).toBe("capture")
		t.expect(l.rows[1].minutes).toBe(0) -- the typed 4 is ignored
		t.expect(l.rows[1].tokens).toBe(nil)
		t.expect(l.rows[1].unmeasured).toBe("tokens,ai")
		t.expect(l.rows[1].added).toBe(0)
		t.expect(l.rows[1].subject).toBe("captured alpha")
		local file = string.match(branchChanged(head), "[^\n]+") :: string
		local text = git(prep, { "show", `HEAD:{file}` }) .. "\n"
		local parsed = buffer.parseTsv(text)
		t.expect(parsed ~= nil).toBe(true)
		t.expect((parsed :: { any })[1].phase).toBe("capture")
		t.expect(git(prep, { "rev-parse", "HEAD" }) ~= head).toBe(true)
		t.expect(git(prep, { "status", "--porcelain" })).toBe("")
		t.expect(fs.isDir(`{prep}/pickman/.tracker/issues/{a}/spend.d`)).toBe(true)
	end)

	it("splits a raft's row over its members in one commit: minutes near, tokens exactly", function()
		local before, head = tip(), git(prep, { "rev-parse", "HEAD" })
		trOk(prep, {
			"spend",
			raft,
			"--phase",
			"design-review",
			"--time",
			"9",
			"--tokens",
			"3001",
			"--note",
			"design-review-001",
		})
		t.expect(tip()).toBe(before)
		local changed = branchChanged(head)
		t.expect(string.find(changed, `pickman/.tracker/issues/{a}/spend.d/`, 1, true) ~= nil).toBe(true)
		t.expect(string.find(changed, `pickman/.tracker/issues/{b}/spend.d/`, 1, true) ~= nil).toBe(true)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		local ra, rb =
			last(`pickman/.tracker/issues/{a}/spend.md`), last(`pickman/.tracker/issues/{b}/spend.md`)
		t.expect(ra.phase).toBe("design-review")
		t.expect(rb.phase).toBe("design-review")
		t.expect(ra.minutes + rb.minutes).toBe(0) -- typed minutes are not stored
		t.expect(ra.tokens).toBe(nil)
		t.expect(rb.tokens).toBe(nil)
		t.expect(ra.added + rb.added).toBe(0)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(#onBranch(`pickman/.tracker/issues/{a}/spend.md`).rows).toBe(2) -- the capture row is kept
	end)

	it(
		"prep counts the lines the prep branch wrote in check.sh, acceptance and experiments, by member",
		function()
			trOk(prep, { "sync" })
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			write(`{prep}/pickman/.tracker/issues/{a}/acceptance/x.spec.luau`, "1\n2\n3\n4\n5\n6\n")
			write(`{prep}/pickman/.tracker/issues/{b}/experiments/e1.sh`, "echo 1\necho 2\n")
			local rc = `{prep}/pickman/.tracker/rafts/{raft}/check.sh`
			fs.writeFile(rc, fs.readFile(rc) .. "# one\n# two\n")
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			local doc = `{prep}/pickman/.tracker/issues/{a}/{a}.md`
			fs.writeFile(doc, fs.readFile(doc) .. "\nDesign text that is not counted.\nMore.\n")
			write(`{prep}/notes.txt`, "a\nb\nc\nd\ne\n")
			git(prep, { "add", "-A" })
			git(prep, { "commit", "-q", "-m", "prep" })
			trOk(prep, { "spend", raft, "--phase", "prep", "--time", "10" })
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			local ra, rb =
				last(`pickman/.tracker/issues/{a}/spend.md`), last(`pickman/.tracker/issues/{b}/spend.md`)
			t.expect(ra.phase).toBe("prep")
			t.expect(ra.added).toBe(7) -- six spec lines and half of the raft's two check.sh lines
			t.expect(rb.added).toBe(3) -- two experiment lines and the other half
			t.expect(ra.minutes).toBe(0) -- typed minutes are not stored; the lines are
			t.expect(rb.minutes).toBe(0)
			-- any other phase records no lines, whatever the branch wrote
			trOk(prep, { "spend", b, "--phase", "design-review", "--time", "1" })
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			t.expect(last(`pickman/.tracker/issues/{b}/spend.md`).added).toBe(0)
		end
	)

	it("prep lines are the prep branch's own, also once the prep has been squash-merged into main", function()
		git(prep, { "push", "-q", "origin", "HEAD:refs/heads/prep-demo" })
		git(other, { "pull", "-q", "origin", "main" })
		git(other, { "fetch", "-q", "origin", "prep-demo" })
		git(other, { "merge", "-q", "--squash", "FETCH_HEAD" })
		git(other, { "commit", "-q", "-m", "prep demo (#1)" })
		git(other, { "push", "-q", "origin", "HEAD:main" })
		trOk(prep, { "spend", a, "--phase", "prep", "--time", "2" })
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(last(`pickman/.tracker/issues/{a}/spend.md`).added).toBe(6) -- its own spec lines; the raft's check.sh is not its
	end)

	it("refuses bad input and the main checkout, and pushes nothing", function()
		local before = tip()
		local function refused(cwd: string, args: { string }, needle: string?)
			local r = tr(cwd, args)
			if r.ok then
				error(`accepted: spend {table.concat(args, " ")}`, 2)
			end
			if needle and not has(r.stderr, needle) then
				error(`spend {table.concat(args, " ")}: stderr lacks "{needle}": {r.stderr}`, 2)
			end
		end
		refused(prep, { "spend" })
		refused(prep, { "spend", a, "--time", "1" }) -- no phase
		refused(prep, { "spend", a, "--phase", "build", "--time", "1" }, "./zn commit")
		refused(prep, { "spend", a, "--phase", "code-review", "--time", "1" }, "./zn commit")
		refused(prep, { "spend", a, "--phase", "review", "--time", "1" }, "design-review")
		-- --time and --tokens are accepted and ignored, including values that used to be refused
		local ignored = tr(prep, { "spend", a, "--phase", "capture", "--time", "soon", "--tokens", "12k" })
		t.expect(ignored.ok).toBe(true)
		t.expect(has(ignored.stderr, "ignored")).toBe(true)
		refused(prep, { "spend", "c0989", "--phase", "capture", "--time", "1" })
		refused(main, { "spend", a, "--phase", "capture", "--time", "1" }, "worktree")
		-- a copy of the tooling with no .git of its own: git would find the enclosing repository, so spend refuses
		local lost = `{main}/lost`
		fs.writeDir(lost)
		engine.copy(root, lost) -- c0114 override: ./zn, scripts/ and z-nile/
		process.exec("cp", { `{root}/.luaurc`, `{lost}/.luaurc` })
		local r = fixture.exec(
			main,
			"bash",
			{ "lost/scripts/tracker.sh", "spend", a, "--phase", "capture", "--time", "1" }
		)
		fs.removeDir(lost)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "repository root")).toBe(true)
		t.expect(tip()).toBe(before)
	end)

	it(
		"refuses an item that is active on origin/main, readied or claimed, and names commit --phase",
		function()
			git(other, { "pull", "-q", "origin", "main" })
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			git(other, { "mv", `pickman/.tracker/issues/{b}`, `pickman/.tracker/issues/active/{b}` })
			local bdoc = `{other}/pickman/.tracker/issues/active/{b}/{b}.md`
			fs.writeFile(
				bdoc,
				(string.gsub(fs.readFile(bdoc), "\nstatus: [^\n]*", "\nstatus: active-red-fox-kite"))
			)
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			local adoc = `{other}/pickman/.tracker/issues/{a}/{a}.md`
			fs.writeFile(
				adoc,
				(string.gsub(fs.readFile(adoc), "\nstatus: [^\n]*", "\nstatus: active-blue-owl-reef"))
			)
			git(other, { "add", "-A" })
			git(other, { "commit", "-q", "-m", "readied and claimed" })
			git(other, { "push", "-q", "origin", "HEAD:main" })
			local before = tip()
			for _, id in { b, a, raft } do
				local r = tr(prep, { "spend", id, "--phase", "deliver", "--time", "1" })
				t.expect(r.ok).toBe(false)
				t.expect(has(r.stderr, "commit --phase")).toBe(true)
			end
			-- a raft readied before its prep row was recorded: the prep row can't be recorded any more, and the
			-- refusal says so instead of sending the agent to commit, which refuses prep too
			local late = tr(prep, { "spend", b, "--phase", "prep", "--time", "1" })
			t.expect(late.ok).toBe(false)
			t.expect(has(late.stderr, "readied before")).toBe(true)
			t.expect(tip()).toBe(before)
		end
	)

	it("records deliver on a done item, in its done directory", function()
		-- earlier spends committed ledgers on this branch; origin has since moved those directories.
		-- This case starts from origin's tree.
		git(prep, { "fetch", "-q", "origin", "main" })
		git(prep, { "reset", "--hard", "-q", "origin/main" })
		local g = string.match(
			trOk(prep, { "new", "issue", "c", "gamma", "--desc", "Gamma.", "--project", "pickman" }),
			"(c%d%d%d%d)"
		) :: string
		git(other, { "pull", "-q", "origin", "main" })
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		git(other, { "mv", `pickman/.tracker/issues/{g}`, `pickman/.tracker/issues/done/{g}` })
		git(other, { "commit", "-q", "-m", "gamma done" })
		git(other, { "push", "-q", "origin", "HEAD:main" })
		trOk(prep, { "sync" })
		local before, head = tip(), git(prep, { "rev-parse", "HEAD" })
		trOk(prep, { "spend", g, "--phase", "deliver", "--time", "3" })
		t.expect(tip()).toBe(before)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		t.expect(
			string.find(branchChanged(head), `pickman/.tracker/issues/done/{g}/spend.d/`, 1, true) ~= nil
		)
			.toBe(true)
		t.expect(last(`pickman/.tracker/issues/done/{g}/spend.md`).phase).toBe("deliver")
	end)

	it("keeps an existing ledger's rows and title, reading seven-cell rows as build", function()
		git(prep, { "fetch", "-q", "origin", "main" })
		git(prep, { "reset", "--hard", "-q", "origin/main" })
		local d = string.match(
			trOk(prep, { "new", "issue", "c", "delta", "--desc", "Delta.", "--project", "pickman" }),
			"(c%d%d%d%d)"
		) :: string
		git(other, { "pull", "-q", "origin", "main" })
		local old = `# Spend: {d} Delta as it was\n\n`
			.. "| # | when | commit | +lines | -lines | minutes | attribution |\n|---|---|---|---|---|---|---|\n"
			.. `| 1 | 2026-09-29 03:16 | {d}: old work | 66 | 9 | 20.0 | focus |\n`
			.. "\n**Total:** +66 / -9 lines, 20.0 agent-minutes over 1 commits\n"
			.. "<!-- totals: added=66 removed=9 minutes=20.0 commits=1 -->\n"
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		write(`{other}/pickman/.tracker/issues/{d}/spend.md`, old)
		git(other, { "add", "-A" })
		git(other, { "commit", "-q", "-m", "old ledger" })
		git(other, { "push", "-q", "origin", "HEAD:main" })
		trOk(prep, { "sync" })
		local before = tip()
		trOk(prep, { "spend", d, "--phase", "prep", "--time", "2" })
		t.expect(tip()).toBe(before)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		local l = onBranch(`pickman/.tracker/issues/{d}/spend.md`)
		t.expect(l.title).toBe("Delta as it was")
		t.expect(#l.rows).toBe(2)
		t.expect(l.rows[1].phase).toBe("build")
		t.expect(l.rows[1].added).toBe(66)
		t.expect(l.rows[2].phase).toBe("prep")
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		local text = git(prep, { "show", `HEAD:pickman/.tracker/issues/{d}/spend.md` }) .. "\n"
		t.expect(text).toBe(old) -- the historical file is not rewritten
		local added = string.match(
			git(prep, { "ls-tree", "-r", "--name-only", "HEAD", "--", `pickman/.tracker/issues/{d}/spend.d` }),
			"[^\n]+"
		) :: string
		local addedRows = buffer.parseTsv(git(prep, { "show", `HEAD:{added}` }) .. "\n")
		t.expect(addedRows ~= nil).toBe(true)
		t.expect((addedRows :: { any })[1].phase).toBe("prep")
	end)

	it("the publisher takes only appended rows for an issue's spend.md, and never a raft's", function()
		t.expect(publish.allowed(`tracker/issues/{a}/spend.md`, { "tracker" })).toBe(true)
		t.expect(publish.allowed(`tracker/issues/done/{a}/spend.md`, { "tracker" })).toBe(true)
		t.expect(publish.allowed(`tracker/rafts/{raft}/spend.md`, { "tracker" })).toBe(false)
		t.expect(publish.allowed(`tracker/issues/{a}/acceptance/spend.md`, { "tracker" })).toBe(false)
		git(other, { "pull", "-q", "origin", "main" })
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		local path = `pickman/.tracker/issues/{a}/spend.md`
		write(
			`{other}/{path}`,
			`# Spend: {a} {a}\n\n| # | when | commit | +lines | -lines | minutes | attribution | phase | tokens |\n|---|---|---|---|---|---|---|---|---|\n| 1 | 2026-09-29 03:16 | old | 1 | 0 | 4.0 | spend | capture | |\n`
		)
		git(other, { "add", path })
		git(other, { "commit", "-q", "-m", "seed spend" })
		git(other, { "push", "-q", "origin", "HEAD:main" })
		local current = fs.readFile(`{other}/{path}`)
		local l = ledger.parse(current) :: any
		local before = tip()
		local edited = table.clone(l.rows)
		edited[1] = table.clone(edited[1])
		edited[1].minutes = 0.5
		local rewrite = publish.commit(other, function()
			return { { path = path, content = ledger.render(l.id, l.title, edited) } }
		end, "tracker: rewrite spend")
		t.expect(rewrite.ok).toBe(false)
		t.expect(tip()).toBe(before)
		local raftLedger = publish.commit(other, function()
			return {
				{
					-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
					path = `pickman/.tracker/rafts/{raft}/spend.md`,
					content = ledger.append(nil, raft, "x", l.rows[1]),
				},
			}
		end, "tracker: raft spend")
		t.expect(raftLedger.ok).toBe(false)
		t.expect(tip()).toBe(before)
		-- an old row edited while a row is appended: only the comparison of old rows refuses it
		local both = table.clone(edited)
		both[1] = table.clone(l.rows[1])
		both[1].subject = "rewritten"
		table.insert(both, l.rows[1])
		local sneaky = publish.commit(other, function()
			return { { path = path, content = ledger.render(l.id, l.title, both) } }
		end, "tracker: rewrite and append")
		t.expect(sneaky.ok).toBe(false)
		t.expect(tip()).toBe(before)
		-- no ledger is written beside a missing document, or for an item active on origin/main (b was moved there)
		local orphan = publish.commit(other, function()
			return {
				{
					-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
					path = "pickman/.tracker/issues/c0987/spend.md",
					content = ledger.append(nil, "c0987", "x", l.rows[1]),
				},
			}
		end, "tracker: orphan spend")
		t.expect(orphan.ok).toBe(false)
		local activeLedger = publish.commit(other, function()
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			local p = `pickman/.tracker/issues/active/{b}/spend.md`
			return { { path = p, content = ledger.render(b, b, { l.rows[1] }) } }
		end, "tracker: active spend")
		t.expect(activeLedger.ok).toBe(false)
		t.expect(tip()).toBe(before)
		local row = table.clone(l.rows[1])
		row.subject = "appended by the library"
		local appended = publish.commit(other, function()
			return { { path = path, content = ledger.append(current, a, "", row) } }
		end, "tracker: append spend")
		t.expect(appended.ok).toBe(true)
		t.expect(#onOrigin(path).rows).toBe(#l.rows + 1)
	end)

	it("status lists each item once while spend.md files sit beside the documents", function()
		local out = trOk(prep, { "status" })
		local n = 0
		for line in string.gmatch(out, "[^\n]+") do
			if string.sub(line, 1, #a + 1) == a .. " " then
				n += 1
			end
		end
		t.expect(n).toBe(1)
	end)

	it("ready and stop carry the members' ledgers unchanged, old shapes included", function()
		git(other, { "pull", "-q", "origin", "main" })
		local PREP = "prepared-calm-oak-river"
		local head = '#!/usr/bin/env bash\nsource "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)'
			.. '/scripts/lib/ac.sh"\ncheck "AC1: fixture" true\nfinish\n'
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		write(
			`{other}/pickman/.tracker/rafts/R0961/R0961.md`,
			"---\nid: R0961\ntype: chore\ntitle: Carried\nslug: carried\nsingle: false\nissues: [c0961, c0962]\n"
				.. `design: ready\ncreated: 2026-10-06\nstatus: {PREP}\n---\n\n# R0961: Carried\n`
		)
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		write(`{other}/pickman/.tracker/rafts/R0961/check.sh`, head)
		for _, id in { "c0961", "c0962" } do
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			write(
				`{other}/pickman/.tracker/issues/{id}/{id}.md`,
				`---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: R0961\ndepends_on: []\nemergent: false\n`
					.. `design: ready\ncreated: 2026-10-06\nstatus: {PREP}\n---\n\n# {id}\n`
			)
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			write(`{other}/pickman/.tracker/issues/{id}/check.sh`, head)
		end
		-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
		write(
			`{other}/pickman/.tracker/issues/c0962/spend.md`,
			"# Spend: c0962 c0962\n\n| # | when | commit | +lines | -lines | minutes | attribution |\n"
				.. "|---|---|---|---|---|---|---|\n| 1 | 2026-09-29 03:16 | old | 3 | 0 | 2.0 | focus |\n"
		)
		git(other, { "add", "-A" })
		for _, p in
			{
				-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
				"pickman/.tracker/rafts/R0961/check.sh",
				"pickman/.tracker/issues/c0961/check.sh",
				"pickman/.tracker/issues/c0962/check.sh",
			}
		do
			git(other, { "update-index", "--chmod=+x", p })
		end
		-- c0961's ledger is placed on main here. `./zn spend` commits on a branch and does not publish it.
		write(
			`{other}/pickman/.tracker/issues/c0961/spend.md`,
			"# Spend: c0961 c0961\n\n| # | when | commit | +lines | -lines | minutes | attribution |\n"
				.. "|---|---|---|---|---|---|---|\n| 1 | 2026-09-29 03:16 | old | 1 | 0 | 1.0 | focus |\n"
		)
		git(other, { "add", "-A" })
		git(other, { "commit", "-q", "-m", "prepared R0961" })
		git(other, { "push", "-q", "origin", "HEAD:main" })
		local before: { [string]: string } = {}
		for _, id in { "c0961", "c0962" } do
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			before[id] = git(origin, { "show", `main:pickman/.tracker/issues/{id}/spend.md` })
		end
		git(main, { "pull", "-q", "--ff-only" })
		trOk(main, { "ready", "R0961" }) -- R0025: readied on origin/main, members moved with every file
		for _, id in { "c0961", "c0962" } do
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			t.expect(git(origin, { "show", `main:pickman/.tracker/issues/active/{id}/spend.md` }))
				.toBe(before[id])
		end
		trOk(main, { "stop", "R0961" })
		for _, id in { "c0961", "c0962" } do
			-- c0120 override: pickman's items live under pickman/.tracker (the fixtures' layout)
			t.expect(git(origin, { "show", `main:pickman/.tracker/issues/{id}/spend.md` })).toBe(before[id])
		end
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
