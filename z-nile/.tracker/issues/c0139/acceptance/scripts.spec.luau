--!strict
-- c0139 AC3: c0115's rename-lesson-ids and rewrite-finished refuse, before writing, over unmerged paths and over a
-- whole conflict in a working file under a root or a skills folder (exit 2, naming the path). Fixture under
-- .cache/c0139-scripts (tests/lib/trackerfix), with the two scripts and their helpers copied in.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
local DOC = "z-nile/.tracker/issues/c0001/c0001.md"
local EXP = "z-nile/.tracker/issues/done/c0115/experiments"
local f: trackerfix.Fixture

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function commitAll(dir: string, msg: string)
	fixture.git(dir, { "add", "-A" })
	fixture.git(dir, { "commit", "-qm", msg })
end
local function run(name: string): fixture.Result
	return fixture.exec(f.main, "lune", { "run", `{f.main}/{EXP}/{name}`, "--", "--check" })
end

return t.spec("c0139 c0115's two rewriting scripts refuse over a merge conflict", function(it)
	it("over unmerged paths, before writing", function()
		f = trackerfix.new("c0139-scripts", {
			["z-nile/projects.toml"] = REGISTRY,
			[DOC] = trackerfix.stub("c0001", "demo", "new-a-b-c"),
			["pickman/.tracker/issues/.gitkeep"] = "",
		})
		local top = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
		fs.writeDir(`{f.main}/{EXP}`)
		for _, name in { "rename-lesson-ids.luau", "rewrite-finished.luau", "trusted-base.luau" } do
			fs.writeFile(`{f.main}/{EXP}/{name}`, fs.readFile(`{top}/{EXP}/{name}`))
		end
		local rw = "z-nile/tests/acceptance/c0120/rewrites.luau"
		if not fs.isFile(`{f.main}/{rw}`) then
			fs.writeDir(`{f.main}/z-nile/tests/acceptance/c0120`)
			fs.writeFile(`{f.main}/{rw}`, fs.readFile(`{top}/{rw}`))
		end
		commitAll(f.main, "the scripts")
		fixture.git(f.main, { "checkout", "-q", "-b", "side" })
		fs.writeFile(`{f.main}/{DOC}`, trackerfix.stub("c0001", "side", "new-a-b-c"))
		commitAll(f.main, "side")
		fixture.git(f.main, { "checkout", "-q", "main" })
		fs.writeFile(`{f.main}/{DOC}`, trackerfix.stub("c0001", "main", "new-a-b-c"))
		commitAll(f.main, "main")
		t.expect(fixture.exec(f.main, "git", { "merge", "-q", "side" }).ok).toBe(false)
		for _, name in { "rename-lesson-ids", "rewrite-finished" } do
			local r = run(name)
			t.expect(r.code).toBe(2)
			t.expect(has(r.stderr, `{name}: refusing to run while the checkout has unmerged paths`))
				.toBe(true)
			t.expect(has(r.stderr, DOC)).toBe(true)
		end
		fixture.git(f.main, { "checkout", "--theirs", DOC })
		commitAll(f.main, "resolved")
	end)

	it("over a whole conflict in a working file under a root, with no unmerged paths", function()
		local rel = "z-nile/.tracker/issues/c0001/harvest.md"
		fs.writeFile(`{f.main}/{rel}`, "<<<<<<< HEAD\na\n=======\nb\n>>>>>>> side\n")
		for _, name in { "rename-lesson-ids", "rewrite-finished" } do
			local r = run(name)
			t.expect(r.code).toBe(2)
			t.expect(has(r.stderr, `{name}: refusing to run: these files hold merge-conflict markers`))
				.toBe(true)
			t.expect(has(r.stderr, `{rel}:1`)).toBe(true)
		end
		fs.removeDir(f.base)
	end)
end)
