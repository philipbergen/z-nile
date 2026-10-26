--!strict
-- c0139: a tool that rewrites tracked files refuses to run over a merge conflict, and names each path to resolve:
-- every `./zn` command outside the read-only list, and c0115's two rewriting scripts (rename-lesson-ids and
-- rewrite-finished). A conflict is git's unmerged paths, or a tracked file under a project root or a skills folder
-- holding a whole conflict (a `<<<<<<< ` line, then a `>>>>>>> ` line, at the starts of lines). The read-only
-- commands (`find`, `list`) keep working, so a script can still locate an item mid-merge. Fixture under
-- .cache/c0139-conflicts (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
local DOC = "z-nile/.tracker/issues/c0001/c0001.md"
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

return t.spec("c0139 tools that rewrite tracked files refuse to run over a merge conflict", function(it)
	it("with unmerged paths a writing command refuses and names them; read-only ones still work", function()
		f = trackerfix.new("c0139-conflicts", {
			["z-nile/projects.toml"] = REGISTRY,
			[DOC] = trackerfix.stub("c0001", "demo", "new-a-b-c"),
		})
		-- a merge that stops on c0001's document
		fixture.git(f.main, { "checkout", "-q", "-b", "side" })
		fs.writeFile(`{f.main}/{DOC}`, trackerfix.stub("c0001", "side title", "new-a-b-c"))
		commitAll(f.main, "side")
		fixture.git(f.main, { "checkout", "-q", "main" })
		fs.writeFile(`{f.main}/{DOC}`, trackerfix.stub("c0001", "main title", "new-a-b-c"))
		commitAll(f.main, "main")
		local m = fixture.exec(f.main, "git", { "merge", "-q", "side" })
		t.expect(m.ok).toBe(false)
		local before = originMain()
		local r = trackerfix.tr(f, f.main, { "sync" })
		t.expect(r.code ~= 0).toBe(true)
		t.expect(has(r.stderr .. r.stdout, "unmerged paths")).toBe(true)
		t.expect(has(r.stderr .. r.stdout, DOC)).toBe(true)
		t.expect(originMain()).toBe(before) -- nothing published
		t.expect(has(fs.readFile(`{f.main}/{DOC}`), "<<<<<<< ")).toBe(true) -- nothing rewritten
		t.expect(trackerfix.tr(f, f.main, { "find", "c0001" }).ok).toBe(true)
		t.expect(trackerfix.tr(f, f.main, { "list" }).ok).toBe(true)
	end)

	it("c0115's two rewriting scripts refuse too, before writing", function()
		local src = `{fixture.physical(".")}/.tracker/issues/done/c0115/experiments`
		local alt = `{fixture.physical("..")}/z-nile/.tracker/issues/done/c0115/experiments`
		local from = if fs.isDir(src) then src else alt
		local to = `{f.main}/z-nile/.tracker/issues/done/c0115/experiments`
		fs.writeDir(to)
		for _, name in { "rename-lesson-ids.luau", "rewrite-finished.luau", "trusted-base.luau" } do
			fs.writeFile(`{to}/{name}`, fs.readFile(`{from}/{name}`))
		end
		-- rewrite-finished requires c0120's promoted rewrites module from the harness
		local rw = "z-nile/tests/acceptance/c0120/rewrites.luau"
		if not fs.isFile(`{f.main}/{rw}`) then
			fs.writeDir(`{f.main}/z-nile/tests/acceptance/c0120`)
			fs.writeFile(`{f.main}/{rw}`, fs.readFile(`{fixture.physical(".")}/tests/acceptance/c0120/rewrites.luau`))
		end
		for _, name in { "rename-lesson-ids", "rewrite-finished" } do
			local r = fixture.exec(f.main, "lune", { "run", `{to}/{name}`, "--", "--check" })
			t.expect(r.code).toBe(2)
			t.expect(has(r.stderr, `{name}: refusing to run while the checkout has unmerged paths`)).toBe(true)
			t.expect(has(r.stderr, DOC)).toBe(true)
		end
		fs.removeDir(to)
	end)

	it("once resolved the command runs; a committed conflict refuses it again, naming the file and line", function()
		fixture.git(f.main, { "checkout", "--theirs", DOC })
		commitAll(f.main, "resolved")
		fixture.git(f.main, { "push", "-q", "origin", "main" })
		fixture.git(f.main, { "fetch", "-q", "origin" })
		t.expect(trackerfix.tr(f, f.main, { "sync" }).ok).toBe(true)
		-- a whole conflict committed by mistake into a lesson-like file under the skills folder
		local lesson = "z-nile/skills/zz-rules/lessons/demo-conflict.md"
		fs.writeDir(`{f.main}/z-nile/skills/zz-rules/lessons`)
		fs.writeFile(`{f.main}/{lesson}`, "---\ntitle: x\n---\n<<<<<<< HEAD\na\n=======\nb\n>>>>>>> side\n")
		commitAll(f.main, "a conflict committed by mistake")
		local r = trackerfix.tr(f, f.main, { "sync" })
		t.expect(r.code ~= 0).toBe(true)
		t.expect(has(r.stderr .. r.stdout, "hold merge-conflict markers")).toBe(true)
		t.expect(has(r.stderr .. r.stdout, `{lesson}:4`)).toBe(true)
		-- a document that only quotes markers inline is no conflict
		fs.writeFile(`{f.main}/{lesson}`, "---\ntitle: x\n---\nQuote `<<<<<<< ` and `>>>>>>> ` inline.\n")
		commitAll(f.main, "fixed")
		t.expect(trackerfix.tr(f, f.main, { "sync" }).ok).toBe(true)
		fs.removeDir(f.base)
	end)
end)
