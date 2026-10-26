--!strict
-- c0139 AC2: a writing `./zn` command refuses over a merge conflict and writes nothing: unmerged paths, or a file under
-- a project root or a skills folder whose working copy (tracked or untracked, what `git add -A` commits) holds a whole
-- conflict, each named with how to recover. The commands that only read (READ_ONLY plus busy, capture, prompt,
-- lessons, status without a target status, raft-plan without --apply, skills --check) still run. A registry that
-- can't be read refuses too. Fixture under .cache/c0139-conflicts (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
local DOC = "z-nile/.tracker/issues/c0001/c0001.md"
local CONFLICT = "---\ntitle: x\n---\n<<<<<<< HEAD\na\n=======\nb\n>>>>>>> side\n"
local f: trackerfix.Fixture

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function commitAll(dir: string, msg: string)
	fixture.git(dir, { "add", "-A" })
	fixture.git(dir, { "commit", "-qm", msg })
end
local function originMain(): string
	return (string.gsub(fixture.git(f.main, { "rev-parse", "refs/remotes/origin/main" }), "%s+$", ""))
end
local function refused(r: fixture.Result, needle: string)
	t.expect(r.code ~= 0).toBe(true)
	t.expect(has(r.stderr .. r.stdout, needle)).toBe(true)
	t.expect(has(r.stderr .. r.stdout, "resolve with plain git")).toBe(true)
end
local function write(rel: string, text: string)
	local parent = string.match(rel, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{f.main}/{parent}`)
	end
	fs.writeFile(`{f.main}/{rel}`, text)
end

return t.spec("c0139 a writing command refuses over a merge conflict; reading ones run", function(it)
	it("with unmerged paths a writing command refuses and names them; every read-only command runs", function()
		f = trackerfix.new("c0139-conflicts", {
			["z-nile/projects.toml"] = REGISTRY,
			[DOC] = trackerfix.stub("c0001", "demo", "new-a-b-c"),
			["pickman/.tracker/issues/.gitkeep"] = "",
		})
		fixture.git(f.main, { "checkout", "-q", "-b", "side" })
		write(DOC, trackerfix.stub("c0001", "side title", "new-a-b-c"))
		commitAll(f.main, "side")
		fixture.git(f.main, { "checkout", "-q", "main" })
		write(DOC, trackerfix.stub("c0001", "main title", "new-a-b-c"))
		commitAll(f.main, "main")
		t.expect(fixture.exec(f.main, "git", { "merge", "-q", "side" }).ok).toBe(false)
		local before = originMain()
		refused(trackerfix.tr(f, f.main, { "sync" }), DOC)
		refused(trackerfix.tr(f, f.main, { "status", "c0001", "preparing" }), "unmerged paths")
		t.expect(originMain()).toBe(before) -- nothing published
		t.expect(has(fs.readFile(`{f.main}/{DOC}`), "<<<<<<< ")).toBe(true) -- nothing rewritten
		for _, argv in
			{
				{ "find", "c0001" },
				{ "list" },
				{ "audit" },
				{ "members", "R0001" },
				{ "status" },
				{ "status", "c0001" },
				{ "status", "--project", "z-nile" },
				{ "status", "c0001", "--project", "z-nile" },
				{ "capture", "c0001" },
				{ "lessons" },
				{ "busy" },
				{ "raft-plan" },
				{ "skills", "--check" },
			}
		do
			local r = trackerfix.tr(f, f.main, argv)
			t.expect(has(r.stderr .. r.stdout, "refusing to run")).toBe(false)
		end
		refused(trackerfix.tr(f, f.main, { "raft-plan", "--apply" }), "unmerged paths")
		refused(trackerfix.tr(f, f.main, { "check", "c0001" }), "unmerged paths")
		fixture.git(f.main, { "checkout", "--theirs", DOC })
		commitAll(f.main, "resolved")
		t.expect(trackerfix.tr(f, f.main, { "sync" }).ok).toBe(true)
	end)

	it("a whole conflict in a working file refuses, under either root and a skills folder, staged or not", function()
		for _, rel in
			{
				"z-nile/.tracker/issues/c0001/harvest.md",
				"pickman/.tracker/issues/f0002/f0002.md",
				"z-nile/skills/zz-rules/lessons/demo-conflict.md",
			}
		do
			-- committed by mistake
			write(rel, CONFLICT)
			commitAll(f.main, "a conflict committed by mistake")
			refused(trackerfix.tr(f, f.main, { "sync" }), `{rel}:4`)
			write(rel, "fixed\n")
			commitAll(f.main, "fixed")
			t.expect(trackerfix.tr(f, f.main, { "sync" }).ok).toBe(true)
		end
		-- not staged: the working copy is what a writing command's `git add -A` would commit
		write("z-nile/.tracker/issues/c0001/harvest.md", CONFLICT)
		refused(trackerfix.tr(f, f.main, { "sync" }), "z-nile/.tracker/issues/c0001/harvest.md:4")
		write("z-nile/.tracker/issues/c0001/harvest.md", "fixed\n")
		-- untracked, not ignored
		write("z-nile/skills/zz-rules/lessons/new-conflict.md", CONFLICT)
		refused(trackerfix.tr(f, f.main, { "sync" }), "z-nile/skills/zz-rules/lessons/new-conflict.md:4")
		fs.removeFile(`{f.main}/z-nile/skills/zz-rules/lessons/new-conflict.md`)
		-- markers quoted inline are no conflict
		write("z-nile/skills/zz-rules/lessons/demo-conflict.md", "Quote `<<<<<<< ` and `>>>>>>> ` inline.\n")
		commitAll(f.main, "quoted")
		t.expect(trackerfix.tr(f, f.main, { "sync" }).ok).toBe(true)
	end)

	it("a registry that can't be read, or a failed git read, refuses a writing command (fail closed)", function()
		write("z-nile/projects.toml", "this is not toml [[[\n")
		local r = trackerfix.tr(f, f.main, { "sync" })
		t.expect(r.code ~= 0).toBe(true)
		t.expect(has(r.stderr .. r.stdout, "can't tell whether files hold merge conflicts")).toBe(true)
		write("z-nile/projects.toml", REGISTRY)
		-- design review 002 F2: a git read that fails refuses too (an unreadable index), naming the command
		local index = `{f.main}/.git/index`
		local saved = fs.readFile(index)
		fs.writeFile(index, "DIRC")
		local r2 = trackerfix.tr(f, f.main, { "sync" })
		t.expect(r2.code ~= 0).toBe(true)
		t.expect(has(r2.stderr .. r2.stdout, "can't tell whether files hold merge conflicts")).toBe(true)
		t.expect(has(r2.stderr .. r2.stdout, "git diff --name-only --diff-filter=U failed")).toBe(true)
		fs.writeFile(index, saved)
		t.expect(trackerfix.tr(f, f.main, { "sync" }).ok).toBe(true)
	end)

	it('a broken or redirected checkout refuses; git\'s "not a git repository" waives nothing', function()
		-- design review 003 F1: only a tree with no `.git` entry and no inherited git variable is outside a checkout;
		-- each case below makes git say "not a git repository" and must refuse, writing no item
		local issues = `{f.main}/z-nile/.tracker/issues`
		local function items(): number
			return #fs.readDir(issues)
		end
		local probe = { "new", "issue", "c", "probe-x", "--project", "z-nile" }
		write("z-nile/.tracker/issues/c0001/harvest.md", CONFLICT)
		local n = items()
		-- (a) an inherited GIT_DIR that names no repository
		-- each runs through `bash -c` from the sound fixture checkout: the fixture helper refuses a GIT_DIR handed down, and
		-- checks its folder is a sound fixture repository before it runs anything, so the damage is done inside the command
		local function wrapped(dir: string, setup: string, after: string): fixture.Result
			local argv = {
				"-c",
				`cd "$1" && shift && {setup} bash scripts/tracker.sh "$@"; s=$?; {after} exit $s`,
				"tracker",
				dir,
			}
			table.move(probe, 1, #probe, #argv + 1, argv)
			return fixture.exec(f.main, "bash", argv)
		end
		-- (a) an inherited GIT_DIR that names no repository
		refused(wrapped(f.main, "GIT_DIR=/nonexistent", ""), "refusing to run")
		t.expect(items()).toBe(n)
		-- (b) a corrupt HEAD, restored after
		local saved = fs.readFile(`{f.main}/.git/HEAD`)
		refused(
			wrapped(
				f.main,
				"cp .git/HEAD .git/HEAD.keep && printf 'garbage\\n' > .git/HEAD &&",
				"mv .git/HEAD.keep .git/HEAD;"
			),
			"refusing to run"
		)
		t.expect(fs.readFile(`{f.main}/.git/HEAD`)).toBe(saved)
		t.expect(items()).toBe(n)
		fs.removeFile(`{f.main}/z-nile/.tracker/issues/c0001/harvest.md`)
		-- (c) a linked worktree whose admin folder was removed, a whole conflict in a working file
		local wt = `{f.base}/wt`
		fixture.git(f.main, { "worktree", "add", "-q", "-b", "c0139-wt", wt })
		local wtIssues = `{wt}/z-nile/.tracker/issues`
		fs.writeDir(`{wtIssues}/c0001`)
		fs.writeFile(`{wtIssues}/c0001/harvest.md`, CONFLICT)
		local m = #fs.readDir(wtIssues)
		refused(wrapped(wt, "", ""), "z-nile/.tracker/issues/c0001/harvest.md:4")
		fs.removeDir(`{f.main}/.git/worktrees/wt`)
		refused(wrapped(wt, "", ""), "refusing to run")
		t.expect(#fs.readDir(wtIssues)).toBe(m)
		fs.removeDir(wt)
		fixture.git(f.main, { "worktree", "prune" })
		-- (d) no `.git` entry, but git variables inherited that point at a checkout: still a checkout, so it refuses
		local plain = `{f.base}/plain`
		t.expect(
			fixture.exec(
				f.main,
				"bash",
				{ "-c", `mkdir -p "$1" && tar --exclude=./.git -cf - . | tar -C "$1" -xf -`, "copy", plain }
			).ok
		).toBe(true)
		t.expect(fs.isDir(`{plain}/.git`)).toBe(false)
		fs.writeFile(`{plain}/z-nile/.tracker/issues/c0001/harvest.md`, CONFLICT)
		local k = #fs.readDir(`{plain}/z-nile/.tracker/issues`)
		-- through ./zn the repository-root guard refuses it first (GIT_DIR names another repository's .git); either way
		-- nothing is written
		local viaZn = wrapped(plain, `GIT_DIR="{f.main}/.git" GIT_WORK_TREE="{plain}"`, "")
		t.expect(viaZn.code ~= 0).toBe(true)
		t.expect(has(viaZn.stderr .. viaZn.stdout, "refusing to run")).toBe(true)
		-- and the guard itself, as a script calls it (scripts have no repository-root guard): the inherited variables
		-- make it a checkout, so the conflict is found
		fs.writeFile(
			`{plain}/c0139-probe.luau`,
			'local c = require("./z-nile/engine/conflicts")\nprint(c.refusal(".", "probe") or "none")\n'
		)
		local direct = fixture.exec(f.main, "bash", {
			"-c",
			'cd "$1" && GIT_DIR="$2" GIT_WORK_TREE="$1" lune run c0139-probe.luau',
			"probe",
			plain,
			`{f.main}/.git`,
		})
		t.expect(has(direct.stdout, "z-nile/.tracker/issues/c0001/harvest.md:4")).toBe(true)
		t.expect(#fs.readDir(`{plain}/z-nile/.tracker/issues`)).toBe(k)
		fs.removeDir(f.base)
	end)
end)
