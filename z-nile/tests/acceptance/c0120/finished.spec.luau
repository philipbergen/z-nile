--!strict
-- c0120 AC11 (finished half): every literal path in a finished item's check.sh that resolved from the repository root
-- before the move resolves from the item's home after it (decided with the user, 2026-10-21: "Rewrite them too"). The
-- rewrite (rewrites.luau) is proved on a fixture with a real move commit: a moved path is rewritten from the home, a
-- path that still resolves is kept, a path stale before the move is kept, a root file becomes ../, prose and comments
-- stay, and a second run changes nothing. Then the rule is checked on the repository itself: every finished check.sh,
-- each path either resolves from its home or was already stale before the move. These specs run from z-nile/.
-- Fixture under .cache/c0120-finished (this home's).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local paths = require("@znile/engine/paths")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local rewrites = require("./rewrites")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local FX = `{here}/.cache/c0120-finished`

local function put(rel: string, text: string)
	fs.writeDir(string.match(`{FX}/{rel}`, "^(.*)/[^/]+$") :: string)
	fs.writeFile(`{FX}/{rel}`, text)
end

local PICKMAN_DONE = table.concat({
	"#!/usr/bin/env bash",
	"# tracker/architecture.md in a comment stays",
	'check "AC1: tracker/architecture.md is prose" grep -q deps tracker/architecture.md',
	'check "AC2: the server is untouched" git diff --quiet -- src/server',
	'check "AC3: the gate" z-nile/check.sh --full',
	'for dir in $(./zn members R0001); do check "x" bash "$dir/check.sh"; done',
	'check "AC4: gone before the move" test -f tests/gone.luau',
	"check \"AC5: a glob\" bash -c 'ls tracker/issues/done/*/check.sh'",
	"check \"AC6: a folder find searches\" bash -c 'find tracker -name x.md'",
	"",
}, "\n")
local ZNILE_DONE = table.concat({
	"#!/usr/bin/env bash",
	'check "AC1: ci" scripts/ci-verify.sh',
	'check "AC2: specs" lune run tests/run -- tests/tooling/x.spec.luau',
	'check "AC3: a pickman spec" test -f tests/acceptance/f0001/a.spec.luau',
	'check "AC4: the gate" z-nile/check.sh --full',
	'check "AC5: a folder most of whose files stayed" test -d scripts/lib',
	'f=.claude/skills/x.md; grep -q rule "$f" AGENTS.md',
	[[check "AC6: a quoted root file stays" bash -c 'grep -qF "x = default.project.json" AGENTS.md || echo "AGENTS.md"']],
	[[for f in skills; do grep -qF "./zn worktree" ".claude/skills/$f/x.md"; done]],
	[[p='zn sync'; grep -q "$p" zn]],
	[[for s in "./zn board"; do grep -qF "$s" "$(./zn find f0001)/f0001.md"; done]],
	"",
}, "\n")

-- one of c0120's own scripts, wherever its folder is: the backlog (prep), active/ (readied), or promoted (done)
local function ownScript(name: string): string
	for _, dir in
		{
			"z-nile/.tracker/issues/c0120/acceptance",
			"z-nile/.tracker/issues/active/c0120/acceptance",
			"z-nile/tests/acceptance/c0120",
		}
	do
		if fs.isFile(`{TOP}/{dir}/{name}`) then
			return `{TOP}/{dir}/{name}`
		end
	end
	return `{TOP}/z-nile/tests/acceptance/c0120/{name}`
end
local function git(args: { string }): string
	return fixture.git(FX, args)
end

return t.spec("c0120 finished check.sh files still name paths that resolve from their home", function(it)
	it("rewrites a finished check.sh's moved paths from its home, and nothing else", function()
		if fs.isDir(FX) then
			fs.removeDir(FX)
		end
		fs.writeDir(FX)
		t.expect(process.exec("git", { "init", "-q", "-b", "main", FX }).ok).toBe(true)
		git({ "config", "user.name", "c0120" })
		git({ "config", "user.email", "c0120@example.invalid" })
		-- before the move: c0114's tree, pickman at tracker/, the tooling at the root
		put("zn", "#!/usr/bin/env bash\n")
		put("z-nile/check.sh", "#!/usr/bin/env bash\n")
		put("scripts/ci-verify.sh", "#!/usr/bin/env bash\n")
		put("scripts/lib/a.luau", "--!strict\nreturn 1\n")
		put("scripts/lib/b.luau", "--!strict\nreturn 1\n")
		put("scripts/lib/beta.luau", "--!strict\nreturn 1\n")
		put("src/server/Main.server.luau", "--!strict\nreturn nil\n")
		put("tests/run.luau", "--!strict\nreturn nil\n")
		put("AGENTS.md", "rule\n")
		put("default.project.json", "{}\n")
		put(".claude/skills/x.md", "rule\n")
		put("tests/tooling/x.spec.luau", "--!strict\nreturn nil\n")
		put("tests/acceptance/f0001/a.spec.luau", "--!strict\nreturn nil\n")
		put("tracker/architecture.md", "deps\n")
		put("tracker/issues/done/f0001/f0001.md", "---\nid: f0001\n---\n")
		put("tracker/issues/done/f0001/check.sh", "#!/usr/bin/env bash\n")
		put(rewrites.MARK, PICKMAN_DONE)
		put("z-nile/.tracker/issues/done/c0001/check.sh", ZNILE_DONE)
		put(
			"z-nile/projects.toml",
			'[[project]]\nname = "pickman"\nroot = "tracker"\n\n[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
		)
		git({ "add", "-A" })
		git({ "commit", "-qm", "before the move" })
		-- the move: renames only
		for _, pair in
			{
				{ "src", "pickman/src" },
				{ "tests/acceptance/f0001", "pickman/tests/acceptance/f0001" },
				{ "tests/run.luau", "z-nile/tests/run.luau" },
				{ "tests/tooling", "z-nile/tests/tooling" },
				{ "tracker/architecture.md", "pickman/.tracker/architecture.md" },
				{ "tracker/issues", "pickman/.tracker/issues" },
				{ "tracker/rafts", "pickman/.tracker/rafts" },
				{ "scripts/lib/beta.luau", "pickman/scripts/lib/beta.luau" },
			}
		do
			fs.writeDir(string.match(`{FX}/{pair[2]}`, "^(.*)/[^/]+$") :: string)
			git({ "mv", pair[1], pair[2] })
		end
		put(
			"z-nile/projects.toml",
			'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
				.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
		)
		put("pickman/tests/run.luau", "--!strict\nreturn nil\n") -- a home's runner, as c0120 adds
		git({ "add", "-A" })
		git({ "commit", "-qm", "the move" })
		-- later commits (the edits, a merge of main) don't move the base: it is the parent of the move itself
		put("later.md", "after the move\n")
		git({ "add", "-A" })
		git({ "commit", "-qm", "after the move" })
		local pre, why = rewrites.premove(FX)
		t.expect(why).toBe(nil)
		local world = rewrites.world(FX, pre :: string)
		local pickman =
			rewrites.rewrite(fs.readFile(`{FX}/pickman/.tracker/rafts/done/R0001/check.sh`), "pickman", world)
		t.expect(pickman).toBe(table.concat({
			"#!/usr/bin/env bash",
			"# tracker/architecture.md in a comment stays",
			'check "AC1: tracker/architecture.md is prose" grep -q deps .tracker/architecture.md',
			'check "AC2: the server is untouched" git diff --quiet -- src/server',
			'check "AC3: the gate" ../z-nile/check.sh --full',
			'for dir in $(../zn members R0001); do check "x" bash "$dir/check.sh"; done',
			'check "AC4: gone before the move" test -f tests/gone.luau',
			"check \"AC5: a glob\" bash -c 'ls .tracker/issues/done/*/check.sh'",
			"check \"AC6: a folder find searches\" bash -c 'find ./.tracker -name x.md'",
			"",
		}, "\n"))
		-- an untracked file at a rewritten path's home-relative place changes nothing: the rewrite reads HEAD's tree,
		-- never the working tree (code review 007 F3)
		put("z-nile/scripts/ci-verify.sh", "#!/usr/bin/env bash\n")
		local znile =
			rewrites.rewrite(fs.readFile(`{FX}/z-nile/.tracker/issues/done/c0001/check.sh`), "z-nile", world)
		t.expect(znile).toBe(table.concat({
			"#!/usr/bin/env bash",
			'check "AC1: ci" ../scripts/ci-verify.sh',
			'check "AC2: specs" lune run tests/run -- tests/tooling/x.spec.luau',
			'check "AC3: a pickman spec" test -f ../pickman/tests/acceptance/f0001/a.spec.luau',
			'check "AC4: the gate" ./check.sh --full',
			'check "AC5: a folder most of whose files stayed" test -d ../scripts/lib',
			'f=../.claude/skills/x.md; grep -q rule "$f" ../AGENTS.md',
			[[check "AC6: a quoted root file stays" bash -c 'grep -qF "x = default.project.json" ../AGENTS.md || echo "AGENTS.md"']],
			[[for f in skills; do grep -qF "./zn worktree" "../.claude/skills/$f/x.md"; done]],
			[[p='zn sync'; grep -q "$p" ../zn]],
			[[for s in "./zn board"; do grep -qF "$s" "$(../zn find f0001)/f0001.md"; done]],
			"",
		}, "\n"))
		-- written and run again, it changes nothing
		fs.writeFile(`{FX}/pickman/.tracker/rafts/done/R0001/check.sh`, pickman)
		t.expect(rewrites.rewrite(pickman, "pickman", world)).toBe(pickman)
		t.expect(rewrites.rewrite(znile, "z-nile", world)).toBe(znile)
		-- a root path main created after the move's base (c0114's z-nile/next) is rewritten too, when main's tree is
		-- given (code review 010 F3); without it the path stays, naming z-nile/z-nile/next from the home
		put("z-nile/next", "issue 10 a-b-c\n")
		git({ "add", "-A" })
		git({ "commit", "-qm", "main's counter" })
		local counter = 'check "AC13: the counter" git diff --quiet -- z-nile/next\n'
		t.expect(rewrites.rewrite(counter, "z-nile", rewrites.world(FX, pre :: string, nil, "HEAD")))
			.toBe('check "AC13: the counter" git diff --quiet -- ./next\n')
		t.expect(rewrites.rewrite(counter, "z-nile", rewrites.world(FX, pre :: string))).toBe(counter)
		fs.removeDir(FX)
	end)

	it(
		"deletes exactly the named criteria, continuation lines included, and refuses a missing one",
		function()
			local text = table.concat({
				"helper() { true; }",
				'check "AC1: kept" true',
				'check "AC4: gone" \\',
				"  helper",
				'check "AC4a: kept, a longer id" true',
				'check "AC10: gone too" true',
				'check "AC1x: kept" true',
				"finish",
				"",
			}, "\n")
			t.expect((rewrites.deleteCriteria(text, { "AC4", "AC10" }))).toBe(table.concat({
				"helper() { true; }",
				'check "AC1: kept" true',
				'check "AC4a: kept, a longer id" true',
				'check "AC1x: kept" true',
				"finish",
				"",
			}, "\n"))
			local none, why = rewrites.deleteCriteria(text, { "AC9" })
			t.expect(none).toBe(nil)
			t.expect(why).toBe("AC9: 0 check statements")
		end
	)

	-- code review 004 F1 (decided with the user, 2026-10-21: "Reviewer-pinned commit"): c0120's own files are judged
	-- against the prep commit an approved review records, never a branch ref the author can move
	it("AC18 judges c0120's own files against the reviewer-recorded prep commit, never a branch", function()
		local OWNFX = `{here}/.cache/c0120-own`
		if fs.isDir(OWNFX) then
			fs.removeDir(OWNFX)
		end
		fs.writeDir(OWNFX)
		local function g(args: { string }): string
			return fixture.git(OWNFX, args)
		end
		local function w(rel: string, text: string)
			fs.writeDir(string.match(`{OWNFX}/{rel}`, "^(.*)/[^/]+$") :: string)
			fs.writeFile(`{OWNFX}/{rel}`, text)
		end
		local function judge(): (boolean, string)
			local script = ownScript("finished.luau")
			local r = process.exec("lune", { "run", script, "--", OWNFX })
			return r.ok, r.stdout .. r.stderr
		end
		t.expect(process.exec("git", { "init", "-q", "-b", "main", OWNFX }).ok).toBe(true)
		g({ "config", "user.name", "c0120" })
		g({ "config", "user.email", "c0120@example.invalid" })
		w(rewrites.MARK, "#!/usr/bin/env bash\n")
		w("tracker/next", "10\n")
		w(
			"z-nile/projects.toml",
			'[[project]]\nname = "pickman"\nroot = "tracker"\n\n[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
		)
		w("z-nile/.tracker/issues/c0120/check.sh", "check AC18\n")
		-- an unfinished pickman item and a finished z-nile one, each with sequestered files (code review 005 F1)
		w("tracker/issues/active/f0065/check.sh", "check AC1 true\n")
		w("tracker/issues/active/f0065/acceptance/a.spec.luau", "-- a\n")
		w("z-nile/.tracker/issues/done/c0001/check.sh", "check AC1 test -f AGENTS.md\n")
		w("AGENTS.md", "agents\n")
		-- c0114: unfinished before the move, its promoted specs later carry c0120's overrides (c0114-overrides.patch)
		w("z-nile/.tracker/issues/c0114/check.sh", "check AC1 true\n")
		w("z-nile/.tracker/issues/c0114/acceptance/b.spec.luau", "-- b\n")
		w(
			"z-nile/.tracker/issues/c0120/c0114-overrides.patch",
			table.concat({
				"diff --git a/z-nile/tests/acceptance/c0114/b.spec.luau b/z-nile/tests/acceptance/c0114/b.spec.luau",
				"--- a/z-nile/tests/acceptance/c0114/b.spec.luau",
				"+++ b/z-nile/tests/acceptance/c0114/b.spec.luau",
				"@@ -1 +1,2 @@",
				"+-- c0120 override: from its home",
				" -- b",
				"",
			}, "\n")
		)
		g({ "add", "-A" })
		g({ "commit", "-qm", "the prep" })
		local prep = (string.gsub(g({ "rev-parse", "HEAD" }), "%s+$", ""))
		-- main as this branch merged it: here the prep itself, published to a bare origin (code review 007 F1: AC18
		-- judges the branch's own delta; 008 F1: against the published main, read with ls-remote)
		local origin = `{OWNFX}-origin.git`
		if fs.isDir(origin) then
			fs.removeDir(origin)
		end
		t.expect(process.exec("git", { "init", "-q", "--bare", "-b", "main", origin }).ok).toBe(true)
		g({ "remote", "add", "origin", origin })
		g({ "push", "-q", "origin", `{prep}:refs/heads/main` })
		g({ "fetch", "-q", "origin" })
		fs.writeDir(`{OWNFX}/pickman/.tracker`)
		g({ "mv", "tracker/rafts", "pickman/.tracker/rafts" })
		g({ "mv", "tracker/issues", "pickman/.tracker/issues" })
		w(
			"z-nile/projects.toml",
			'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
				.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
		)
		g({ "add", "-A" })
		g({ "commit", "-qm", "the move" })
		local function step(message: string)
			g({ "add", "-A" })
			g({ "commit", "-qm", message })
		end
		-- the user's commit groups after the move: the finished rewrite, the overrides, the hand-written core (AC18 pins
		-- the core's tree by its subject, code review 009 F2)
		w("z-nile/.tracker/issues/done/c0001/check.sh", "check AC1 test -f ../AGENTS.md\n")
		step("c0120: rewrite finished check.sh paths for their homes (the fixture's)")
		g({ "commit", "-q", "--allow-empty", "-m", "c0120: overrides of promoted specs (the fixture's)" })
		g({
			"commit",
			"-q",
			"--allow-empty",
			"-m",
			"c0120: run each project from its home (the fixture's core)",
		})
		-- the anchors the reviewer pins beside the Prep reference (code review 010 F1)
		local function head(n: number): string
			return (string.gsub(g({ "rev-parse", `HEAD~{n}` }), "%s+$", ""))
		end
		local anchors = `Move commit: {head(3)}\nCore commit: {head(0)}\n`
		local function expectRed(needle: string)
			local okR, outR = judge()
			if okR or not string.find(outR, needle, 1, true) then
				print(outR)
			end
			t.expect(okR).toBe(false)
			t.expect(string.find(outR, needle, 1, true) ~= nil).toBe(true)
		end
		local function expectGreen()
			local okG, outG = judge()
			if not okG then
				print(outG)
			end
			t.expect(okG).toBe(true)
		end
		-- no approved review records a reference: refused
		expectRed('records a "Prep reference')
		-- an approved review records the prep commit: c0120's check.sh as the prep has it passes
		w(
			"z-nile/.tracker/issues/c0120/review-001.md",
			`# Review\nPrep reference: {prep}\n{anchors}\nVerdict: approve\n`
		)
		step("review")
		expectGreen()
		-- readied: c0120's folder in active/ still finds its review and its reference
		fs.writeDir(`{OWNFX}/z-nile/.tracker/issues/active`)
		g({ "mv", "z-nile/.tracker/issues/c0120", "z-nile/.tracker/issues/active/c0120" })
		step("ready")
		expectGreen()
		g({ "mv", "z-nile/.tracker/issues/active/c0120", "z-nile/.tracker/issues/c0120" })
		step("unready")
		expectGreen()
		-- a commit the author makes can't choose the rewrite's world (code review 009 F2): a stray z-nile/AGENTS.md
		-- planted with c0001's check.sh un-rewritten, then removed: red; a tracked file left at that place: still green
		w("z-nile/AGENTS.md", "stray\n")
		w("z-nile/.tracker/issues/done/c0001/check.sh", "check AC1 test -f AGENTS.md\n")
		step("plant")
		g({ "rm", "-q", "z-nile/AGENTS.md" })
		step("unplant")
		expectRed("z-nile/.tracker/issues/done/c0001/check.sh: not its text with exactly the rewrite")
		w("z-nile/.tracker/issues/done/c0001/check.sh", "check AC1 test -f ../AGENTS.md\n")
		w("z-nile/AGENTS.md", "an unrelated file\n")
		step("an unrelated file")
		expectGreen()
		g({ "rm", "-q", "z-nile/AGENTS.md" })
		step("undo")
		expectGreen()
		-- c0120's own check.sh removed: deleted
		g({ "rm", "-q", "z-nile/.tracker/issues/c0120/check.sh" })
		step("rm")
		expectRed("z-nile/.tracker/issues/c0120/check.sh: deleted")
		w("z-nile/.tracker/issues/c0120/check.sh", "check AC18\n")
		-- a spec added to c0120's own folder beyond the reviewed one: added
		w("z-nile/.tracker/issues/c0120/acceptance/x.spec.luau", "-- x\n")
		step("add")
		expectRed("z-nile/.tracker/issues/c0120/acceptance/x.spec.luau: added")
		g({ "rm", "-q", "z-nile/.tracker/issues/c0120/acceptance/x.spec.luau" })
		step("unadd")
		expectGreen()
		-- another item's check.sh removed (an unfinished one, and a finished one): deleted
		g({
			"rm",
			"-q",
			"pickman/.tracker/issues/active/f0065/check.sh",
			"z-nile/.tracker/issues/done/c0001/check.sh",
		})
		step("rm others")
		expectRed("tracker/issues/active/f0065/check.sh: deleted")
		expectRed("z-nile/.tracker/issues/done/c0001/check.sh: deleted")
		w("pickman/.tracker/issues/active/f0065/check.sh", "check AC1 true\n")
		w("z-nile/.tracker/issues/done/c0001/check.sh", "check AC1 test -f ../AGENTS.md\n")
		step("restore")
		expectGreen()
		-- done, as the tracker does it (code review 006 F1): acceptance/ to projects.promotedDir, the folder to done/,
		-- its check.sh through paths.rewrite; the promoted spec is the same file in its promoted place
		local reg = projects.load(OWNFX, true)
		local function finish(id: string, root: string, from: string)
			local promoted = projects.promotedDir(reg, root, id)
			fs.writeDir(string.match(`{OWNFX}/{promoted}`, "^(.*)/[^/]+$") :: string)
			g({ "mv", `{from}/acceptance`, promoted })
			local done = `{root}/issues/done/{id}`
			fs.writeDir(`{OWNFX}/{root}/issues/done`)
			g({ "mv", from, done })
			w(`{done}/check.sh`, paths.rewrite(fs.readFile(`{OWNFX}/{done}/check.sh`), { [id] = done }))
			return promoted
		end
		local promoted = finish("f0065", "pickman/.tracker", "pickman/.tracker/issues/active/f0065")
		t.expect(promoted).toBe("pickman/tests/acceptance/f0065")
		step("f0065 done")
		expectGreen()
		-- its promoted spec edited: changed
		w("pickman/tests/acceptance/f0065/a.spec.luau", "-- edited\n")
		step("edit")
		expectRed("pickman/tests/acceptance/f0065/a.spec.luau: changed")
		w("pickman/tests/acceptance/f0065/a.spec.luau", "-- a\n")
		step("unedit")
		-- its promoted spec removed: deleted
		g({ "rm", "-q", "pickman/tests/acceptance/f0065/a.spec.luau" })
		step("rm promoted")
		expectRed("tracker/issues/active/f0065/acceptance/a.spec.luau: deleted")
		w("pickman/tests/acceptance/f0065/a.spec.luau", "-- a\n")
		step("restore promoted")
		expectGreen()
		-- c0114 done, its promoted spec with c0114-overrides.patch applied: green; one hunk beyond the patch: red
		finish("c0114", "z-nile/.tracker", "z-nile/.tracker/issues/c0114")
		w("z-nile/tests/acceptance/c0114/b.spec.luau", "-- c0120 override: from its home\n-- b\n")
		step("c0114 done")
		expectGreen()
		w("z-nile/tests/acceptance/c0114/b.spec.luau", "-- c0120 override: from its home\n-- b\n-- more\n")
		step("beyond the patch")
		expectRed("z-nile/tests/acceptance/c0114/b.spec.luau: changed")
		w("z-nile/tests/acceptance/c0114/b.spec.luau", "-- c0120 override: from its home\n-- b\n")
		step("back to the patch")
		expectGreen()
		-- a duplicate item folder: refused, whichever copy differs (code review 006 F3)
		w("pickman/.tracker/issues/f0065/check.sh", "check AC1 true\n")
		step("duplicate")
		expectRed("duplicate item folders")
		g({ "rm", "-q", "pickman/.tracker/issues/f0065/check.sh" })
		step("unduplicate")
		expectGreen()
		-- a compaction merged in renumbers f0065: refused, never read as deletions (code review 006 F1 (d))
		g({ "mv", "pickman/.tracker/issues/done/f0065", "pickman/.tracker/issues/done/f0066" })
		g({ "mv", "pickman/tests/acceptance/f0065", "pickman/tests/acceptance/f0066" })
		w("z-nile/compaction.txt", "# a compaction\nf0065 f0066\n")
		step("compaction")
		expectRed("f0065 was renumbered to f0066 by a compaction merged in")
		g({ "mv", "pickman/.tracker/issues/done/f0066", "pickman/.tracker/issues/done/f0065" })
		g({ "mv", "pickman/tests/acceptance/f0066", "pickman/tests/acceptance/f0065" })
		g({ "rm", "-q", "z-nile/compaction.txt" })
		step("uncompacted")
		expectGreen()
		-- an edit to its check.sh, with a local prep-c0120 at HEAD carrying it: still red
		w("z-nile/.tracker/issues/c0120/check.sh", "check nothing\n")
		step("an edit")
		g({ "branch", "-f", "prep-c0120", "HEAD" })
		expectRed("z-nile/.tracker/issues/c0120/check.sh: changed")
		-- a recorded commit the branch doesn't hold: refused
		w("z-nile/.tracker/issues/c0120/check.sh", "check AC18\n")
		w(
			"z-nile/.tracker/issues/c0120/review-002.md",
			"Prep reference: 0123456789abcdef\n\nVerdict: approve\n"
		)
		step("a bad reference")
		expectRed("is no commit here")
		-- a review whose last verdict is changes records nothing, though it quotes `Verdict: approve` (code review
		-- 005 F5); its bad reference is not read
		w(
			"z-nile/.tracker/issues/c0120/review-002.md",
			"Prep reference: 0123456789abcdef\nVerdict: approve\n\nVerdict: changes\n"
		)
		step("changes")
		expectGreen()
		-- two Prep reference lines: ambiguous, refused
		w(
			"z-nile/.tracker/issues/c0120/review-003.md",
			`Prep reference: {prep}\nPrep reference: {prep}\n\nVerdict: approve\n`
		)
		step("two references")
		expectRed("records more than one Prep reference")
		g({ "rm", "-q", "z-nile/.tracker/issues/c0120/review-003.md" })
		step("drop the ambiguous review")
		expectGreen()
		-- a review pinning a core that isn't the third commit after the move: refused (code review 010 F1)
		local move3 = string.match(anchors, "Move commit: (%x+)") :: string
		local wrongCore = (string.gsub(g({ "rev-parse", `{move3}~0` }), "%s+$", ""))
		w(
			"z-nile/.tracker/issues/c0120/review-004.md",
			`Prep reference: {prep}\nMove commit: {move3}\nCore commit: {wrongCore}\n\nVerdict: approve\n`
		)
		step("a review pinning the wrong core")
		expectRed("the core is not the one review-004.md pins")
		g({ "rm", "-q", "z-nile/.tracker/issues/c0120/review-004.md" })
		step("drop it")
		expectGreen()
		-- re-anchoring the move (code review 010 F1): the marker file restored and removed again, then three commits,
		-- the last with the core's subject: the search would now find the author's commits; the pinned anchors refuse
		w(rewrites.MARK, "#!/usr/bin/env bash\n")
		step("tidy")
		g({ "rm", "-q", rewrites.MARK })
		step("tidy 2")
		g({ "commit", "-q", "--allow-empty", "-m", "one" })
		g({ "commit", "-q", "--allow-empty", "-m", "two" })
		g({ "commit", "-q", "--allow-empty", "-m", "c0120: run each project from its home (again)" })
		expectRed("the move is not the one review-001.md pins")
		fs.removeDir(OWNFX)
	end)

	-- code review 007 F1: AC18 judges only the branch's own changes, three-way against the main it merged. Main's
	-- reviewed changes after the move (a prep, a ready, a done with its promotion) are main's; the branch editing the
	-- same file is its own; both sides changing one file differently refuses. A fixture with a real main.
	it("AC18 takes main's own changes after the move as main's, and judges only the branch's", function()
		local FX2 = `{here}/.cache/c0120-main-delta`
		if fs.isDir(FX2) then
			fs.removeDir(FX2)
		end
		fs.writeDir(FX2)
		local function g(args: { string }): string
			return fixture.git(FX2, args)
		end
		local function w(rel: string, text: string)
			fs.writeDir(string.match(`{FX2}/{rel}`, "^(.*)/[^/]+$") :: string)
			fs.writeFile(`{FX2}/{rel}`, text)
		end
		local function rm(rel: string)
			g({ "rm", "-q", "-r", rel })
		end
		local function step(message: string)
			g({ "add", "-A" })
			g({ "commit", "-qm", message })
		end
		local function judge(): (boolean, string)
			local script = ownScript("finished.luau")
			local r = process.exec("lune", { "run", script, "--", FX2 })
			return r.ok, r.stdout .. r.stderr
		end
		local function expectGreen()
			local ok, out = judge()
			if not ok then
				print(out)
			end
			t.expect(ok).toBe(true)
		end
		local function expectRed(needle: string)
			local ok, out = judge()
			if ok or not string.find(out, needle, 1, true) then
				print(out)
			end
			t.expect(ok).toBe(false)
			t.expect(string.find(out, needle, 1, true) ~= nil).toBe(true)
		end
		-- main's side: on a detached main, a change, then origin/main moves to it; the branch merges it, placing main's
		-- files where the move put them (tracker/ is pickman/.tracker/, tests/acceptance/ is pickman's)
		local branch = "work"
		-- main is published in a bare origin (code review 008 F1): a change on main is pushed there and fetched
		local origin = `{FX2}-origin.git`
		if fs.isDir(origin) then
			fs.removeDir(origin)
		end
		local function publish(rev: string)
			g({ "push", "-q", "origin", `{rev}:refs/heads/main` })
			g({ "fetch", "-q", "origin" })
		end
		local function onMain(change: () -> (), message: string, unpublished: boolean?)
			g({ "checkout", "-q", "--detach", "refs/remotes/origin/main" })
			change()
			step(message)
			if unpublished then
				-- the author's own ref moved, nothing published (the forged main)
				g({ "update-ref", "refs/remotes/origin/main", "HEAD" })
			else
				publish("HEAD")
			end
			g({ "checkout", "-q", branch })
		end
		local function mergeMain(place: () -> ())
			g({ "merge", "-q", "-s", "ours", "--no-commit", "refs/remotes/origin/main" })
			place()
			g({ "add", "-A" })
			g({ "commit", "-qm", "merge origin/main" })
		end
		t.expect(process.exec("git", { "init", "-q", "-b", "main", FX2 }).ok).toBe(true)
		g({ "config", "user.name", "c0120" })
		g({ "config", "user.email", "c0120@example.invalid" })
		-- main before the branch: pickman's items at tracker/
		w(rewrites.MARK, "#!/usr/bin/env bash\n")
		w("tracker/next", "10\n")
		w("tracker/issues/active/f0070/check.sh", "check AC1 true\n")
		w("tracker/issues/f0071/check.sh", "check AC1 test -d tracker/issues/f0071\n")
		w("tracker/issues/active/f0072/check.sh", "check AC1 true\n")
		w("tracker/issues/active/f0072/acceptance/c.spec.luau", "-- c\n")
		w("tracker/issues/active/f0073/check.sh", "check AC1 true\n")
		w("tracker/issues/active/f0074/check.sh", "check AC1 true\n")
		-- f0075 had an older text on main before its base (code review 010 F2)
		w("tracker/issues/active/f0075/check.sh", "check AC1 old\n")
		step("main, early")
		w("tracker/issues/active/f0075/check.sh", "check AC1 true\n")
		w("tracker/issues/active/f0076/check.sh", "check AC1 true\n")
		w("tracker/issues/active/f0078/check.sh", "check AC1 true\n")
		w("tracker/issues/active/f0079/check.sh", "check AC1 true\n")
		step("main base")
		t.expect(process.exec("git", { "init", "-q", "--bare", "-b", "main", origin }).ok).toBe(true)
		g({ "remote", "add", "origin", origin })
		publish("HEAD")
		-- a look-alike branch whose name ends in /refs/heads/main and sorts first: the real tip is still read (009 F5)
		g({ "push", "-q", "origin", "HEAD:refs/heads/a/refs/heads/main" })
		g({ "checkout", "-q", "-b", branch })
		-- the branch's prep: c0120's folder and the registry, then the move
		w(
			"z-nile/projects.toml",
			'[[project]]\nname = "pickman"\nroot = "tracker"\n\n[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
		)
		w("z-nile/.tracker/issues/c0120/check.sh", "check AC18\n")
		-- the reviewed overrides patch for a spec main will promote during the window (decided with the user,
		-- 2026-10-23: "Reviewed overrides patch")
		w(
			"z-nile/.tracker/issues/c0120/main-overrides.patch",
			table.concat({
				"diff --git a/pickman/tests/acceptance/f0081/t.spec.luau b/pickman/tests/acceptance/f0081/t.spec.luau",
				"--- a/pickman/tests/acceptance/f0081/t.spec.luau",
				"+++ b/pickman/tests/acceptance/f0081/t.spec.luau",
				"@@ -1 +1,2 @@",
				"--- reads {root}/scripts/lib/x",
				"+-- c0120 override: the tooling's files live in z-nile/",
				"+-- reads {root}/z-nile/lib/x",
				"",
			}, "\n")
		)
		-- a change of the stack's below the move (as c0114's build changed items before c0120's base)
		w("tracker/issues/active/f0073/check.sh", "check AC1 stack\n")
		w("tracker/issues/active/f0074/check.sh", "check AC1 stacked\n")
		-- the stack returns f0075 to main's text from before its base, and gives f0076 a text main will put elsewhere
		w("tracker/issues/active/f0075/check.sh", "check AC1 old\n")
		w("tracker/issues/active/f0076/check.sh", "check AC1 elsewhere\n")
		w("tracker/issues/active/f0078/check.sh", "check AC1 stack78\n")
		w("tracker/issues/active/f0079/check.sh", "check AC1 stack79\n")
		step("the prep")
		local prep = (string.gsub(g({ "rev-parse", "HEAD" }), "%s+$", ""))
		fs.writeDir(`{FX2}/pickman/.tracker`)
		g({ "mv", "tracker/rafts", "pickman/.tracker/rafts" })
		g({ "mv", "tracker/issues", "pickman/.tracker/issues" })
		w(
			"z-nile/projects.toml",
			'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
				.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
		)
		step("the move")
		g({
			"commit",
			"-q",
			"--allow-empty",
			"-m",
			"c0120: rewrite finished check.sh paths for their homes (the fixture's)",
		})
		g({ "commit", "-q", "--allow-empty", "-m", "c0120: overrides of promoted specs (the fixture's)" })
		g({
			"commit",
			"-q",
			"--allow-empty",
			"-m",
			"c0120: run each project from its home (the fixture's core)",
		})
		-- the anchors the reviewer pins beside the Prep reference (code review 010 F1)
		local function head(n: number): string
			return (string.gsub(g({ "rev-parse", `HEAD~{n}` }), "%s+$", ""))
		end
		local anchors = `Move commit: {head(3)}\nCore commit: {head(0)}\n`
		w(
			"z-nile/.tracker/issues/c0120/review-001.md",
			`Prep reference: {prep}\n{anchors}\nVerdict: approve\n`
		)
		step("review")
		expectGreen()
		-- a prep on main edits an unfinished item's check.sh and adds a spec: main's, green
		onMain(function()
			w("tracker/issues/active/f0070/check.sh", "check AC1 true\ncheck AC2 true\n")
			w("tracker/issues/active/f0070/acceptance/n.spec.luau", "-- n\n")
		end, "a prep on main")
		mergeMain(function()
			w("pickman/.tracker/issues/active/f0070/check.sh", "check AC1 true\ncheck AC2 true\n")
			w("pickman/.tracker/issues/active/f0070/acceptance/n.spec.luau", "-- n\n")
		end)
		expectGreen()
		-- the branch then edits that same check.sh: its own change, red
		w("pickman/.tracker/issues/active/f0070/check.sh", "check AC1 true\n")
		step("the branch edits f0070")
		expectRed("pickman/.tracker/issues/active/f0070/check.sh: changed")
		w("pickman/.tracker/issues/active/f0070/check.sh", "check AC1 true\ncheck AC2 true\n")
		step("undo")
		expectGreen()
		-- main readies f0071: its folder to active/, its check.sh through ready's own paths.rewrite: main's, green
		onMain(function()
			g({ "mv", "tracker/issues/f0071", "tracker/issues/active/f0071" })
			w("tracker/issues/active/f0071/check.sh", "check AC1 test -d tracker/issues/active/f0071\n")
		end, "ready on main")
		mergeMain(function()
			fs.writeDir(`{FX2}/pickman/.tracker/issues/active`)
			g({ "mv", "pickman/.tracker/issues/f0071", "pickman/.tracker/issues/active/f0071" })
			w(
				"pickman/.tracker/issues/active/f0071/check.sh",
				"check AC1 test -d tracker/issues/active/f0071\n"
			)
		end)
		expectGreen()
		-- main finishes f0072 and promotes its spec: main's, green; the branch then edits the promoted spec: red
		onMain(function()
			fs.writeDir(`{FX2}/tests/acceptance`)
			g({ "mv", "tracker/issues/active/f0072/acceptance", "tests/acceptance/f0072" })
			fs.writeDir(`{FX2}/tracker/issues/done`)
			g({ "mv", "tracker/issues/active/f0072", "tracker/issues/done/f0072" })
		end, "done on main")
		mergeMain(function()
			fs.writeDir(`{FX2}/pickman/tests/acceptance`)
			g({ "mv", "pickman/.tracker/issues/active/f0072/acceptance", "pickman/tests/acceptance/f0072" })
			fs.writeDir(`{FX2}/pickman/.tracker/issues/done`)
			g({ "mv", "pickman/.tracker/issues/active/f0072", "pickman/.tracker/issues/done/f0072" })
		end)
		expectGreen()
		w("pickman/tests/acceptance/f0072/c.spec.luau", "-- weakened\n")
		step("the branch edits a promoted spec")
		expectRed("pickman/tests/acceptance/f0072/c.spec.luau: changed")
		w("pickman/tests/acceptance/f0072/c.spec.luau", "-- c\n")
		step("undo")
		expectGreen()
		-- an item captured and finished on main after the move, its spec promoted there: main's, green, and
		-- override-markers finds nothing of the branch's to mark (code review 007 F2); one unmarked line the branch adds
		-- to it is the branch's own: red, and one unmarked hunk
		local function markers(): (boolean, string)
			local script = ownScript("override-markers.luau")
			local move = (string.gsub(g({ "log", "-1", "--format=%H", "--", rewrites.MARK }), "%s+$", ""))
			local r = process.exec("lune", { "run", script, "--", move }, { cwd = FX2 })
			return r.ok, r.stdout .. r.stderr
		end
		onMain(function()
			w("tracker/issues/done/f0080/check.sh", "check AC1 true\n")
			w("tests/acceptance/f0080/d.spec.luau", "-- d\n")
		end, "capture, prep and done of f0080 on main")
		mergeMain(function()
			w("pickman/.tracker/issues/done/f0080/check.sh", "check AC1 true\n")
			w("pickman/tests/acceptance/f0080/d.spec.luau", "-- d\n")
		end)
		expectGreen()
		local okMk, outMk = markers()
		if not okMk then
			print(outMk)
		end
		t.expect(okMk).toBe(true)
		w("pickman/tests/acceptance/f0080/d.spec.luau", "-- d\n-- the branch's\n")
		step("the branch edits f0080's promoted spec")
		expectRed("pickman/tests/acceptance/f0080/d.spec.luau: changed")
		okMk, outMk = markers()
		t.expect(okMk).toBe(false)
		t.expect(string.find(outMk, "1 of ", 1, true) ~= nil).toBe(true)
		w("pickman/tests/acceptance/f0080/d.spec.luau", "-- d\n")
		step("undo")
		expectGreen()
		-- main promotes a spec written for the old layout; the branch overrides it exactly by main-overrides.patch:
		-- green; one line beyond the patch: red (code review 009 F1)
		onMain(function()
			w("tracker/issues/done/f0081/check.sh", "check AC1 true\n")
			w("tests/acceptance/f0081/t.spec.luau", "-- reads {root}/scripts/lib/x\n")
		end, "capture, prep and done of f0081 on main")
		mergeMain(function()
			w("pickman/.tracker/issues/done/f0081/check.sh", "check AC1 true\n")
			w(
				"pickman/tests/acceptance/f0081/t.spec.luau",
				"-- c0120 override: the tooling's files live in z-nile/\n-- reads {root}/z-nile/lib/x\n"
			)
		end)
		expectGreen()
		w(
			"pickman/tests/acceptance/f0081/t.spec.luau",
			"-- c0120 override: the tooling's files live in z-nile/\n-- reads {root}/z-nile/lib/x\nreturn nil\n"
		)
		step("beyond the patch")
		expectRed("pickman/tests/acceptance/f0081/t.spec.luau: changed")
		w(
			"pickman/tests/acceptance/f0081/t.spec.luau",
			"-- c0120 override: the tooling's files live in z-nile/\n-- reads {root}/z-nile/lib/x\n"
		)
		step("undo")
		expectGreen()
		-- acceptance/ left beside its promoted copy: refused (code review 007 F5)
		w("pickman/.tracker/issues/done/f0072/acceptance/c.spec.luau", "-- c\n")
		step("left beside")
		expectRed("duplicate item folders")
		rm("pickman/.tracker/issues/done/f0072/acceptance")
		step("undo")
		expectGreen()
		-- main removes a spec of an unfinished item; the branch keeps it: red; deletes it too: green (008 F3)
		onMain(function()
			g({ "rm", "-q", "tracker/issues/active/f0070/acceptance/n.spec.luau" })
		end, "main removes a spec")
		mergeMain(function() end)
		expectRed(
			"pickman/.tracker/issues/active/f0070/acceptance/n.spec.luau: kept, though the main it merged removed it"
		)
		rm("pickman/.tracker/issues/active/f0070/acceptance/n.spec.luau")
		step("the branch follows")
		expectGreen()
		-- main renumbers f0071 to f0091 (a compaction): the branch follows: green; edits the renamed check.sh: red;
		-- keeps the old folder too: red (008 F3)
		onMain(function()
			g({ "mv", "tracker/issues/active/f0071", "tracker/issues/active/f0091" })
			w("tracker/compaction.txt", "f0071 f0091\n")
		end, "main renumbers f0071")
		mergeMain(function()
			g({ "mv", "pickman/.tracker/issues/active/f0071", "pickman/.tracker/issues/active/f0091" })
		end)
		expectGreen()
		w("pickman/.tracker/issues/active/f0091/check.sh", "check AC1 true\n")
		step("the branch edits f0091")
		expectRed("pickman/.tracker/issues/active/f0091/check.sh: changed")
		w("pickman/.tracker/issues/active/f0091/check.sh", "check AC1 test -d tracker/issues/active/f0071\n")
		step("undo")
		expectGreen()
		w("pickman/.tracker/issues/active/f0071/check.sh", "check AC1 test -d tracker/issues/active/f0071\n")
		step("the branch keeps the old folder")
		expectRed("pickman/.tracker/issues/active/f0071/check.sh: kept, though the main it merged removed it")
		rm("pickman/.tracker/issues/active/f0071")
		step("undo")
		expectGreen()
		-- an item captured on main after the move and removed there again, kept by the branch: red (008 F5)
		onMain(function()
			w("tracker/issues/f0093/check.sh", "check AC1 true\n")
		end, "capture f0093 on main")
		mergeMain(function()
			w("pickman/.tracker/issues/f0093/check.sh", "check AC1 true\n")
		end)
		expectGreen()
		onMain(function()
			rm("tracker/issues/f0093")
		end, "main removes f0093")
		mergeMain(function() end)
		expectRed("pickman/.tracker/issues/f0093/check.sh: kept, though the main it merged removed it")
		rm("pickman/.tracker/issues/f0093")
		step("the branch follows")
		expectGreen()
		-- an item captured on main after the move and renumbered there, an old copy kept by the branch: red (009 F3)
		onMain(function()
			w("tracker/issues/f0094/check.sh", "check AC1 true\n")
		end, "capture f0094 on main")
		mergeMain(function()
			w("pickman/.tracker/issues/f0094/check.sh", "check AC1 true\n")
		end)
		onMain(function()
			g({ "mv", "tracker/issues/f0094", "tracker/issues/f0095" })
		end, "main renumbers f0094")
		mergeMain(function()
			w("pickman/.tracker/issues/f0095/check.sh", "check AC1 true\n")
		end)
		expectRed("pickman/.tracker/issues/f0094/check.sh: kept, though the main it merged removed it")
		rm("pickman/.tracker/issues/f0094")
		step("the branch follows")
		expectGreen()
		-- a finished item's promoted spec moved back into its done/ folder, unchanged: red (008 F2)
		fs.writeDir(`{FX2}/pickman/.tracker/issues/done/f0072/acceptance`)
		g({
			"mv",
			"pickman/tests/acceptance/f0072/c.spec.luau",
			"pickman/.tracker/issues/done/f0072/acceptance/c.spec.luau",
		})
		step("moved back")
		expectRed("pickman/.tracker/issues/done/f0072/acceptance/c.spec.luau: not promoted")
		g({
			"mv",
			"pickman/.tracker/issues/done/f0072/acceptance/c.spec.luau",
			"pickman/tests/acceptance/f0072/c.spec.luau",
		})
		step("undo")
		expectGreen()
		-- the published main: forged locally, unreadable, or not fetched, each refuses or judges the branch (008 F1)
		onMain(function()
			w("tracker/issues/active/f0070/check.sh", "check AC1 true\n")
		end, "a weakening on an unpublished main", true)
		mergeMain(function()
			w("pickman/.tracker/issues/active/f0070/check.sh", "check AC1 true\n")
		end)
		expectRed("pickman/.tracker/issues/active/f0070/check.sh: changed")
		publish("refs/remotes/origin/main")
		expectGreen()
		local url = g({ "remote", "get-url", "origin" })
		g({ "remote", "set-url", "origin", `{FX2}-nowhere.git` })
		expectRed("cannot read origin's main")
		g({ "remote", "set-url", "origin", (string.gsub(url, "%s+$", "")) })
		-- a commit published by someone else, not fetched here
		local other = `{FX2}-other`
		t.expect(process.exec("git", { "clone", "-q", origin, other }).ok).toBe(true)
		fixture.git(other, {
			"-c",
			"user.name=c0120",
			"-c",
			"user.email=c0120@example.invalid",
			"commit",
			"-q",
			"--allow-empty",
			"-m",
			"elsewhere",
		})
		fixture.git(other, { "push", "-q", "origin", "HEAD:refs/heads/main" })
		expectRed("is not here: run ./zn sync --fetch")
		g({ "fetch", "-q", "origin" })
		expectGreen()
		fs.removeDir(other)
		-- the verdict names the URL origin resolves to, after any insteadOf: AC18 trusts that origin, and a reviewer
		-- checks this line (code review 009 F4)
		local _, said = judge()
		t.expect(string.find(said, `from {origin}`, 1, true) ~= nil).toBe(true)
		g({ "config", `url.{origin}.insteadOf`, "elsewhere:" })
		g({ "remote", "set-url", "origin", "elsewhere:" })
		local okI, saidI = judge()
		t.expect(okI).toBe(true)
		t.expect(string.find(saidI, `from {origin}`, 1, true) ~= nil).toBe(true)
		g({ "remote", "set-url", "origin", origin })
		-- the stack's change landed on main (as c0114's did, merged as R0043) and main changed it again: main's text
		-- is the newest form, green; the stack's text must be in main's own history
		onMain(function()
			w("tracker/issues/active/f0074/check.sh", "check AC1 stacked\n")
		end, "the stack lands on main")
		onMain(function()
			w("tracker/issues/active/f0074/check.sh", "check AC1 stacked, then main\n")
		end, "main changes it again")
		mergeMain(function()
			w("pickman/.tracker/issues/active/f0074/check.sh", "check AC1 stacked, then main\n")
		end)
		expectGreen()
		-- the stack's text reached main at another of the item's places (code review 011 F3: as c0114's reached main in
		-- the old layout): f0078 went back to the backlog with it, then returned to active/ with main's newer text; main
		-- supersedes, green. Its place before the move and on the merged main are the same path, so a search only there
		-- misses it
		onMain(function()
			g({ "mv", "tracker/issues/active/f0078", "tracker/issues/f0078" })
			w("tracker/issues/f0078/check.sh", "check AC1 stack78\n")
		end, "the stack lands f0078 in the backlog")
		onMain(function()
			g({ "mv", "tracker/issues/f0078", "tracker/issues/active/f0078" })
			w("tracker/issues/active/f0078/check.sh", "check AC1 stack78, then main\n")
		end, "main readies f0078 again, changed")
		mergeMain(function()
			w("pickman/.tracker/issues/active/f0078/check.sh", "check AC1 stack78, then main\n")
		end)
		expectGreen()
		-- a sequestered file keeps its reference's mode (code review 011 F4)
		g({ "update-index", "--chmod=+x", "pickman/.tracker/issues/active/f0070/check.sh" })
		g({ "commit", "-qm", "f0070 executable" })
		expectRed("pickman/.tracker/issues/active/f0070/check.sh: mode 100755 (its reference")
		g({ "update-index", "--chmod=-x", "pickman/.tracker/issues/active/f0070/check.sh" })
		g({ "commit", "-qm", "f0070 back" })
		expectGreen()
		-- main and the stack change one file differently: refused, naming both
		onMain(function()
			w("tracker/issues/active/f0073/check.sh", "check AC1 main\n")
		end, "main edits f0073")
		mergeMain(function() end)
		expectRed("f0073's check.sh: changed on main")
		-- the supersede rule is bounded to main's B..M at the item's own places (code review 010 F2): a stack text equal
		-- to a main blob from before the base, or to one at another item's path, still refuses
		onMain(function()
			w("tracker/issues/active/f0075/check.sh", "check AC1 main\n")
			w("tracker/issues/active/f0077/check.sh", "check AC1 elsewhere\n")
			w("tracker/issues/active/f0076/check.sh", "check AC1 main\n")
			-- f0079's stack text at a folder named like the item, outside every root (code review 011 F3: the places are
			-- anchored to the roots)
			w("notes/f0079/check.sh", "check AC1 stack79\n")
			w("tracker/issues/active/f0079/check.sh", "check AC1 main\n")
		end, "main changes f0075 and f0076, and puts f0076's stack text at f0077")
		mergeMain(function()
			w("pickman/.tracker/issues/active/f0077/check.sh", "check AC1 elsewhere\n")
		end)
		expectRed("f0075's check.sh: changed on main")
		expectRed("f0076's check.sh: changed on main")
		expectRed("f0079's check.sh: changed on main")
		-- origin's main moved onto this branch (it then holds the move): refused
		publish("HEAD")
		expectRed("origin's main already holds the move")
		fs.removeDir(FX2)
		fs.removeDir(origin)
	end)

	it("the path from one folder to another", function()
		t.expect(rewrites.relative("pickman", "pickman/.tracker/x")).toBe(".tracker/x")
		t.expect(rewrites.relative("pickman", "z-nile/check.sh")).toBe("../z-nile/check.sh")
		t.expect(rewrites.relative("z-nile", "z-nile/check.sh")).toBe("check.sh")
		t.expect(rewrites.relative("z-nile/sub", "zn")).toBe("../../zn")
	end)

	it(
		"every finished check.sh in the repository names paths that resolve from its home, or were stale before",
		function()
			local pre, why = rewrites.premove(TOP)
			if not pre then
				error(`the tree before the move is not known: {why}`)
			end
			local world = rewrites.world(TOP, pre)
			local reg = projects.load(TOP, true)
			local bad: { string } = {}
			local read = 0
			for _, root in projects.roots(reg) do
				for _, kind in { "issues", "rafts" } do
					local dir = `{TOP}/{root}/{kind}/done`
					if fs.isDir(dir) then
						for _, id in fs.readDir(dir) do
							local file = `{root}/{kind}/done/{id}/check.sh`
							if string.match(id, "^[fdcR]%d%d%d%d$") and fs.isFile(`{TOP}/{file}`) then
								read += 1
								local home = projects.homeOf(reg, file)
								for _, l in rewrites.literals(fs.readFile(`{TOP}/{file}`)) do
									local from = if l.dir == "" then home else `{home}/{l.dir}`
									if not world.now(`{from}/{l.path}`) and world.before(l.dir .. l.path) then
										table.insert(bad, `{file}: {l.word} (from {home})`)
									end
								end
							end
						end
					end
				end
			end
			table.sort(bad)
			t.expect(table.concat(bad, "\n")).toBe("")
			t.expect(read > 0).toBe(true)
		end
	)
end)
