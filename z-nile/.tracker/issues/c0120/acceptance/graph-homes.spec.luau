--!strict
-- c0120 AC5: the require graph resolves each file's aliases the way Lune and luau-lsp do (U2): every .luaurc from the
-- filesystem root down to the file's folder, a nearer alias replacing a farther one, targets relative to their own
-- .luaurc and kept above the current folder ("../"). @game resolves through the project file of the file's own
-- project, and each home's place library stands for its src/ and project files. The selector picks per project
-- (`--project <name>`, paths relative to the home): shared tooling forces every project's full run, a project's own
-- harness its own, an old root (tracker/, src/) the root project's, and a .tracker/ document nothing.
-- Fixtures under .cache/c0120-graph.
local fs = require("@lune/fs")
local graph = require("@znile/lib/graph")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = ".cache/c0120-graph"
local R = "req" .. "uire" -- keeps literal require text out of this file (the graph scanner)

local function write(rel: string, text: string)
	local path = `{base}/{rel}`
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function affected(args: { string }): (boolean, string)
	local argv = { "run", "z-nile/affected", "--" }
	for _, a in args do
		table.insert(argv, a)
	end
	local r = process.exec("lune", argv)
	return r.ok, r.stdout .. (if r.ok then "" else r.stderr)
end
local function lines(text: string): { string }
	local out: { string } = {}
	for line in string.gmatch(text, "[^\n]+") do
		table.insert(out, line)
	end
	return out
end

return t.spec("c0120 the graph and the selector know the homes", function(it)
	it("aliases come from every .luaurc above a folder, the nearest winning, lowercased", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		write("a/.luaurc", '{ "aliases": { "X": "./X", "y": "./Y" } }')
		write("a/b/.luaurc", '{ "aliases": { "x": "./BX" } }')
		local map = graph.aliases(`{base}/a/b`)
		t.expect(map.x).toBe(`{base}/a/b/BX`)
		t.expect(map.y).toBe(`{base}/a/Y`)
		t.expect(map.znile).toBe("z-nile") -- the root's, inherited
		t.expect(graph.aliases(`{base}/a`).x).toBe(`{base}/a/X`)
	end)

	it("a target above the current folder keeps its ../, as a run from a project's home needs", function()
		write("home/.luaurc", '{ "aliases": { "up": "../shared" } }')
		write("shared/thing.luau", "--!strict\nreturn 1\n")
		write("home/tests/x.spec.luau", "--!strict\nreturn 1\n")
		-- the probe runs with the home as its working directory, requiring the graph from the checkout
		local back = string.rep("../", 3) -- .cache/c0120-graph/home -> the checkout
		write(
			"home/probe.luau",
			`local graph = {R}("{back}z-nile/lib/graph")\nprint(graph.resolve("tests/x.spec.luau", "@up/thing"))\n`
				.. `print(graph.resolve("tests/x.spec.luau", "../../shared/thing"))\n`
		)
		local r = process.exec("lune", { "run", "probe.luau" }, { cwd = `{root}/{base}/home` })
		t.expect(r.ok).toBe(true)
		t.expect(r.stdout).toBe("../shared/thing.luau\n../shared/thing.luau\n")
	end)

	it(
		"from the root, pickman's files resolve through pickman/.luaurc and the root's through the root's",
		function()
			t.expect(graph.resolve("pickman/tests/unit/Maze/maze.spec.luau", "@logic/Maze"))
				.toBe("pickman/src/shared/Logic/Maze/init.luau")
			t.expect(graph.resolve("pickman/tests/unit/Maze/maze.spec.luau", "@tests/lib/t"))
				.toBe("pickman/tests/lib/t.luau")
			t.expect(graph.resolve("pickman/tests/acceptance/x.spec.luau", "@znile/lib/graph"))
				.toBe("z-nile/lib/graph.luau")
			t.expect(graph.resolve("tests/tooling/x.spec.luau", "@tests/lib/t")).toBe("tests/lib/t.luau")
			t.expect(graph.resolve("pickman/tests/lib/t.luau", "../../../tests/lib/t"))
				.toBe("tests/lib/t.luau")
		end
	)

	it("@game resolves through the project file of the file's own project", function()
		t.expect(
			graph.resolve("pickman/src/client/Main.client.luau", "@game/ReplicatedStorage/Shared/Logic/Maze")
		)
			.toBe("pickman/src/shared/Logic/Maze/init.luau")
		-- the root has no place of its own any more
		t.expect(#graph.gameRoots()).toBe(0)
	end)

	it("every require in pickman's src/ and tests/ resolves from the root's view too", function()
		local g = graph.build({ "pickman/src", "pickman/tests" })
		local msgs: { string } = {}
		for _, u in g.unresolved do
			table.insert(msgs, `{u.file}: {u.spec}`)
		end
		t.expect(table.concat(msgs, "\n")).toBe("")
		t.expect(#g.files > 100).toBe(true)
	end)

	it("a home's place library stands for that home's src/ and project files, not the root's", function()
		local PLACE = "pickman/tests/lib/place.luau"
		local g: graph.Graph = {
			files = { "pickman/tests/place/p.spec.luau", "pickman/tests/unit/u.spec.luau", PLACE },
			deps = {
				["pickman/tests/place/p.spec.luau"] = { PLACE },
				["pickman/tests/unit/u.spec.luau"] = {},
				[PLACE] = {},
			},
			unresolved = {},
			dynamic = {},
		}
		local function sel(changed: { string }): { string }
			return graph.affectedSpecs(g, changed, function(f)
				return string.match(f, "%.spec%.luau$") ~= nil
			end)
		end
		t.expect(sel({ "pickman/src/shared/X/init.luau" })).toEqual({ "pickman/tests/place/p.spec.luau" })
		t.expect(sel({ "pickman/default.project.json" })).toEqual({ "pickman/tests/place/p.spec.luau" })
		t.expect(sel({ "pickman/lobby.project.json" })).toEqual({ "pickman/tests/place/p.spec.luau" })
		t.expect(sel({ "src/shared/X/init.luau" })).toEqual({})
		t.expect(sel({ "pickman/srcx/y.luau" })).toEqual({})
	end)

	it("--project selects one project's specs, relative to its home", function()
		local ok, out = affected({ "--project", "pickman", "pickman/src/shared/Logic/Maze/init.luau" })
		t.expect(ok).toBe(true)
		local got = lines(out)
		t.expect(table.find(got, "tests/unit/Maze/maze.spec.luau") ~= nil).toBe(true)
		for _, l in got do
			t.expect(string.sub(l, 1, 8) == "pickman/").toBe(false)
			t.expect(fs.isFile(`pickman/{l}`)).toBe(true)
		end
		local _, znile = affected({ "--project", "z-nile", "pickman/src/shared/Logic/Maze/init.luau" })
		t.expect(znile).toBe("")
		local _, all = affected({ "pickman/src/shared/Logic/Maze/init.luau" })
		t.expect(table.find(lines(all), "pickman/tests/unit/Maze/maze.spec.luau") ~= nil).toBe(true)
	end)

	it(
		"shared tooling runs every project; a project's own harness, or an old root, runs that project's",
		function()
			local function both(path: string): string
				local _, p = affected({ "--project", "pickman", path })
				local _, z = affected({ "--project", "z-nile", path })
				return `{p}|{z}`
			end
			t.expect(both("tests/lib/t.luau")).toBe("ALL\n|ALL\n")
			t.expect(both("tests/run.luau")).toBe("ALL\n|ALL\n")
			t.expect(both("z-nile/engine/projects.luau")).toBe("ALL\n|ALL\n")
			t.expect(both("pickman/tests/lib/sim.luau")).toBe("ALL\n|")
			t.expect(both("pickman/.luaurc")).toBe("ALL\n|")
			t.expect(both("pickman/scripts/lib/beta.luau")).toBe("ALL\n|")
			t.expect(both("tests/meta/architecture.spec.luau")).toBe("|ALL\n")
			t.expect(both("tracker/issues/f0001/f0001.md")).toBe("|ALL\n")
			t.expect(both("src/shared/Logic/Maze/init.luau")).toBe("|ALL\n")
			t.expect(both("pickman/.tracker/issues/f0001/f0001.md")).toBe("|")
			t.expect(both("z-nile/.tracker/issues/c0001/c0001.md")).toBe("|")
		end
	)

	it("an unknown project is refused", function()
		local ok, out = affected({ "--project", "nope", "README.md" })
		t.expect(ok).toBe(false)
		t.expect(string.find(out, "no project nope", 1, true) ~= nil).toBe(true)
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
