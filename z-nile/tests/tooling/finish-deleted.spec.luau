--!strict
-- d0410: `./zn finish` captures the watch map from the paths the layer changed, and a path the layer deleted is
-- not one to watch: a deleted spec gets no watch file (its folder is not made again), and a deleted source is in
-- no list it writes. A layer with no deletion writes what it always wrote. Driven through ./zn in a fixture.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local NEXT = "issue 1 fixture\nraft 1 fixture\n"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "RC1: fixture" true\nfinish\n'
local SPEC = "--!strict\nreturn {}\n"
local OLD = "pickman/src/shared/Logic/Old/init.luau"
local KEEP = "pickman/src/shared/Logic/Keep/init.luau"
local MAZE = "pickman/src/shared/Logic/Maze/init.luau"

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

local function zn(f: trackerfix.Fixture, args: { string })
	local r = trackerfix.tr(f, f.main, args)
	if not r.ok then
		error(`zn {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

type Layer = { f: trackerfix.Fixture, dir: string }

-- A raft of one issue whose layer adds a source and edits a unit spec (keep.spec, watching Keep and Old), and,
-- when `deletes`, also deletes the source Old and the unit spec old.spec with its watch file; then finish.
local function finished(name: string, deletes: boolean): Layer
	local f = trackerfix.new(name, {
		["z-nile/next"] = NEXT,
		[OLD] = "return { old = true }\n",
		[KEEP] = "return { keep = true }\n",
		["pickman/tests/unit/Old/old.spec.luau"] = SPEC,
		["pickman/tests/unit/Old/old.watch.txt"] = OLD .. "\n",
		["pickman/tests/unit/keep.spec.luau"] = SPEC,
		["pickman/tests/unit/keep.watch.txt"] = KEEP .. "\n" .. OLD .. "\n",
	})
	fixture.git(f.main, { "remote", "remove", "origin" })
	local id =
		string.match(zn(f, { "new", "issue", "d", "gone", "--project", "pickman" }), "(d%d%d%d%d)") :: string
	local raft = string.match(
		zn(f, { "new", "raft", "defect", "gone", id, "--single", "--project", "pickman" }),
		"(R%d%d%d%d)"
	) :: string
	local root = "pickman/.tracker"
	for _, doc in { `{root}/issues/{id}/{id}.md`, `{root}/rafts/{raft}/{raft}.md` } do
		fs.writeFile(
			`{f.main}/{doc}`,
			(string.gsub(fs.readFile(`{f.main}/{doc}`), "design: draft", "design: ready"))
		)
	end
	write(f.main, `{root}/issues/{id}/acceptance/gone.spec.luau`, SPEC)
	write(f.main, `{root}/issues/{id}/check.sh`, CHECK)
	write(f.main, `{root}/rafts/{raft}/check.sh`, CHECK)
	seal.prep(f.main)
	fixture.git(f.main, { "add", "-A" })
	fixture.git(f.main, { "commit", "-qm", "prep" })
	zn(f, { "start", raft })
	write(f.main, MAZE, "return { maze = true }\n")
	write(f.main, "pickman/tests/unit/keep.spec.luau", "--!strict\n-- edited\nreturn {}\n")
	if deletes then
		fs.removeFile(`{f.main}/{OLD}`)
		fs.removeFile(`{f.main}/pickman/tests/unit/Old/old.spec.luau`)
		fs.removeFile(`{f.main}/pickman/tests/unit/Old/old.watch.txt`)
		fs.removeDir(`{f.main}/pickman/tests/unit/Old`)
		fs.removeDir(`{f.main}/pickman/src/shared/Logic/Old`)
	end
	zn(f, { "commit", "-m", "the layer", "--issue", id })
	zn(f, { "finish", id })
	return { f = f, dir = `{f.main}/{root}/issues/active/{id}` }
end

local cache: { [string]: Layer } = {}
local function layer(deletes: boolean): Layer
	local key = if deletes then "deletes" else "keeps"
	local got = cache[key]
	if got == nil then
		got = finished(`finish-deleted-{key}`, deletes)
		cache[key] = got
	end
	return got :: Layer
end

local function tracked(l: Layer, path: string): boolean
	return process.exec("git", { "ls-files", "--error-unmatch", "--", path }, { cwd = l.f.main }).ok
end

return t.spec("finish captures no deleted path (d0410)", function(it)
	it(
		"a layer that deletes a spec writes no watch file for it and does not make its folder again",
		function()
			local l = layer(true)
			t.expect(fs.isFile(`{l.f.main}/pickman/tests/unit/Old/old.watch.txt`)).toBe(false)
			t.expect(fs.isDir(`{l.f.main}/pickman/tests/unit/Old`)).toBe(false)
			t.expect(tracked(l, "pickman/tests/unit/Old/old.watch.txt")).toBe(false)
		end
	)

	it(
		"a layer that deletes a source lists it in neither the ticket's watch.txt nor a changed spec's",
		function()
			local l = layer(true)
			t.expect(fs.readFile(`{l.dir}/acceptance/watch.txt`)).toBe(MAZE .. "\n")
			t.expect(fs.readFile(`{l.f.main}/pickman/tests/unit/keep.watch.txt`))
				.toBe(KEEP .. "\n" .. MAZE .. "\n")
			local checked = fixture.exec(l.f.main, "lune", { "run", "z-nile/watch-check" })
			if not checked.ok then
				error(`watch-check failed ({checked.code}): {checked.stderr}{checked.stdout}`, 0)
			end
		end
	)

	it("a layer with no deletion captures what it always did", function()
		local l = layer(false)
		t.expect(fs.readFile(`{l.dir}/acceptance/watch.txt`)).toBe(MAZE .. "\n")
		t.expect(fs.readFile(`{l.f.main}/pickman/tests/unit/keep.watch.txt`))
			.toBe(KEEP .. "\n" .. MAZE .. "\n" .. OLD .. "\n")
		t.expect(fs.isFile(`{l.f.main}/pickman/tests/unit/Old/old.watch.txt`)).toBe(true)
	end)
end)
