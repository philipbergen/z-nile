--!strict
-- c0273 AC1-AC4: a home's `*.project.jsonc` is a project file. Rojo 7.7.1 builds `<name>.project.jsonc` as it builds
-- `<name>.project.json`, comments and trailing commas included (prep E1), and Lune's JSON decoder refuses a comment (E2). So
-- every reader that lists a home's project files by name (the home rule's lister, graph's one lister behind the selector
-- and the server-file rule, the selector's forcing pattern) matches both names, and a file the decoder refuses fails
-- closed: the home rule reports it as mapping no $path (c0246's line) and still judges what Rojo reads of it, and graph's
-- lister raises an error naming it. Fixtures under .cache/c0273-jsonc (this home's .cache).
local fs = require("@lune/fs")
local graph = require("@znile/lib/graph")
local home = require("@tests/lib/home")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local sel = require("@znile/lib/select")
local t = require("@tests/lib/t")

local BASE = ".cache/c0273-jsonc"
local CWD = (string.gsub(process.cwd, "/+$", "")) .. "/"

local function put(rel: string, text: string)
	local path = `{BASE}/{rel}`
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function fresh()
	if fs.isDir(BASE) then
		fs.removeDir(BASE)
	end
	put("stylua.toml", 'indent_type = "Tabs"\n')
	put("selene.toml", 'std = "roblox"\n')
	put("out/o.luau", "return 2\n")
	put("pong/src/shared/a.luau", "return 1\n")
end
local function lines(found: { string }, needle: string): { string }
	local out: { string } = {}
	for _, l in found do
		if string.find(l, needle, 1, true) then
			table.insert(out, l)
		end
	end
	return out
end
local function pong(): { string }
	local reg, err = projects.parse('[[project]]\nname = "pong"\nroot = "pong/.tracker"\n')
	t.expect(err).toBe(nil)
	return (home.problems(BASE, reg :: projects.Registry))
end
-- a place mapping `path` at ReplicatedStorage/<node>, as JSON text
local function place(name: string, node: string, path: string): string
	return `\{ "name": "{name}", "tree": \{ "$className": "DataModel", "ReplicatedStorage": \{ "{node}": \{ "$path": "{path}" \} \} \} \}`
end
local DEFAULT = place("pong", "A", "src/shared")
-- Rojo 7.7.1 builds this (prep E1); Lune's decoder refuses the comment (E2)
local COMMENTED =
	'{\n  // a comment\n  "name": "n",\n  "tree": { "$className": "DataModel", "ReplicatedStorage": { "C": { "$path": "../out" } } },\n}\n'

return t.spec("c0273 a home's *.project.jsonc is a project file", function(it)
	it("AC1: the home rule lists a *.project.jsonc and reads it as it reads a *.project.json", function()
		fresh()
		put("pong/default.project.json", DEFAULT)
		put("pong/plain.project.jsonc", place("p", "B", "../out"))
		-- names that are not a project file's are not listed, though each maps a folder outside the home
		for _, other in { "bak.project.json.bak", "x.jsonc", "y.project.jsonx", "z.project.jsoncc" } do
			put(`pong/{other}`, place("o", "B", "../out"))
		end
		local found = pong()
		t.expect(#lines(found, "pong: plain.project.jsonc maps $path ../out, which is outside the home"))
			.toBe(1)
		-- the Rojo-driven net (c0246) runs on it too, and does not take the file itself for a nested project
		t.expect(#lines(found, "pong: plain.project.jsonc makes Rojo read ")).toBe(1)
		t.expect(#lines(found, "loads plain.project.jsonc as a nested project")).toBe(0)
		for _, other in { "bak.project.json.bak", "x.jsonc", "y.project.jsonx", "z.project.jsoncc" } do
			t.expect(#lines(found, other)).toBe(0)
		end
		fs.removeDir(BASE)
	end)

	it(
		"AC1: a commented *.project.jsonc fails closed as mapping no $path, is named as not JSON to Lune, and what Rojo reads of it is still judged",
		function()
			fresh()
			put("pong/default.project.json", DEFAULT)
			put("pong/notes.project.jsonc", COMMENTED)
			local found = pong()
			t.expect(#lines(found, "pong: notes.project.jsonc maps no $path")).toBe(1)
			t.expect(
				#lines(
					found,
					"pong: notes.project.jsonc is not JSON to Lune's decoder (a comment or a trailing comma, which Rojo builds): only what Rojo reads of it is judged"
				)
			).toBe(1)
			t.expect(#lines(found, "pong: notes.project.jsonc makes Rojo read ")).toBe(1)
			t.expect(#lines(found, "loads notes.project.jsonc as a nested project")).toBe(0)
			fs.removeDir(BASE)
		end
	)

	it("AC1: a default.project.jsonc is read, but it is not the default place", function()
		fresh()
		put("pong/default.project.jsonc", place("pong", "A", "../out"))
		local found = pong()
		t.expect(#lines(found, "pong: missing default.project.json")).toBe(1)
		t.expect(#lines(found, "pong: default.project.jsonc maps $path ../out, which is outside the home"))
			.toBe(1)
		fs.removeDir(BASE)
	end)

	it("AC2: <name>.project.json beside <name>.project.jsonc is reported once per place", function()
		fresh()
		put("pong/default.project.json", DEFAULT)
		put("pong/default.project.jsonc", DEFAULT)
		put("pong/lobby.project.json", place("l", "L", "src/shared"))
		put("pong/lobby.project.jsonc", place("l", "L", "src/shared"))
		put("pong/solo.project.jsonc", place("s", "S", "src/shared"))
		put("pong/lone.project.json", place("s", "S", "src/shared"))
		local found = pong()
		local twice = lines(found, "both build the place")
		table.sort(twice) -- the directory's order is not defined
		t.expect(twice).toEqual({
			"pong: default.project.json and default.project.jsonc both build the place default: keep one",
			"pong: lobby.project.json and lobby.project.jsonc both build the place lobby: keep one",
		})
		fs.removeDir(BASE)
	end)

	it("AC3: graph names a project file by both suffixes and nothing else", function()
		local named: { [string]: string } = {
			["default.project.json"] = "default",
			["lobby.project.jsonc"] = "lobby",
			["a.b.project.jsonc"] = "a.b",
		}
		for name, stem in named do
			t.expect(graph.isProjectFile(name)).toBe(true)
			t.expect(graph.projectStem(name)).toBe(stem)
		end
		for _, name in
			{
				"x.json",
				"x.jsonc",
				"x.project.json.bak",
				"x.project.jsonx",
				"x.project.jsoncc",
				"project.json",
			}
		do
			t.expect(graph.isProjectFile(name)).toBe(false)
			t.expect(graph.projectStem(name)).toBe(nil)
		end
	end)

	it("AC3: graph.placeInputs lists a home's *.project.jsonc and every folder it maps", function()
		fresh()
		put("pi/default.project.json", place("g", "A", "src/a"))
		put("pi/lobby.project.jsonc", place("l", "B", "src/b"))
		local inputs = graph.placeInputs(`{BASE}/pi/`)
		t.expect(table.find(inputs, `{BASE}/pi/lobby.project.jsonc`) ~= nil).toBe(true)
		t.expect(table.find(inputs, `{BASE}/pi/src/b`) ~= nil).toBe(true)
		t.expect(table.find(inputs, `{BASE}/pi/src/a`) ~= nil).toBe(true)
		fs.removeDir(BASE)
	end)

	it(
		"AC3: a commented *.project.jsonc stops graph's lister with an error naming it and saying why",
		function()
			fresh()
			put("pi/default.project.json", place("g", "A", "src/a"))
			put("pi/notes.project.jsonc", COMMENTED)
			local ok, err = pcall(graph.placeInputs, `{BASE}/pi/`)
			t.expect(ok).toBe(false)
			t.expect(string.find(tostring(err), "notes.project.jsonc is not a Rojo project", 1, true) ~= nil)
				.toBe(true)
			local why = "(a comment or a trailing comma, which Rojo builds, is not JSON to Lune's decoder)"
			t.expect(string.find(tostring(err), why, 1, true) ~= nil).toBe(true)
			fs.removeDir(BASE)
		end
	)

	it(
		"AC3: the server-file rule reads the places of every *.project.jsonc of the current folder, and stops on a commented one",
		function()
			fresh()
			-- the default place keeps src/server on the server; a *.project.jsonc place replicates it, so it is no server file
			put(
				"both/default.project.json",
				'{ "name": "g", "tree": { "$className": "DataModel", "ServerStorage": { "S": { "$path": "src/server" } } } }'
			)
			put("both/lobby.project.jsonc", place("l", "S", "src/server"))
			-- a commented *.project.jsonc stops the server-file rule too, naming the file (it never skips the place)
			put(
				"bad/default.project.json",
				'{ "name": "g", "tree": { "$className": "DataModel", "ServerStorage": { "S": { "$path": "src/server" } } } }'
			)
			put("bad/notes.project.jsonc", COMMENTED)
			put(
				"one/default.project.json",
				'{ "name": "g", "tree": { "$className": "DataModel", "ServerStorage": { "S": { "$path": "src/server" } } } }'
			)
			-- graph.serverFile's default places are the current folder's project files: a probe run there answers
			local R = "req" .. "uire" -- keeps literal require text out of this spec (the graph scanner)
			put(
				"probe.luau",
				`local graph = {R}("../../lib/graph")\nprint(graph.serverFile("src/server/x.luau"))\n`
			)
			local probe = CWD .. BASE .. "/probe.luau"
			local function run(dir: string): process.ExecResult
				return process.exec("lune", { "run", probe }, { cwd = CWD .. BASE .. "/" .. dir })
			end
			local function answer(dir: string): string
				local r = run(dir)
				t.expect(r.ok).toBe(true)
				return (string.gsub(r.stdout, "%s+$", ""))
			end
			t.expect(answer("one")).toBe("true") -- the probe tells a server file at all
			t.expect(answer("both")).toBe("false")
			local refused = run("bad")
			t.expect(refused.ok).toBe(false)
			t.expect(string.find(refused.stderr, "notes.project.jsonc is not a Rojo project", 1, true) ~= nil)
				.toBe(true)
			fs.removeDir(BASE)
		end
	)

	it("AC4: a change to a home's *.project.jsonc forces that project's static run", function()
		local reg, err = projects.parse(
			'[[project]]\nname = "pong"\nroot = "pong/.tracker"\n\n[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
		)
		t.expect(err).toBe(nil)
		local rules = sel.rules(reg :: projects.Registry)
		t.expect(sel.forces(rules, "pong/lobby.project.jsonc")).toBe("pong")
		t.expect(sel.forces(rules, "pong/lobby.project.json")).toBe("pong")
		t.expect(sel.forces(rules, "pong/lobby.project.jsonx")).toBe(nil)
		t.expect(sel.forces(rules, "pong/src/n.project.jsonc")).toBe(nil) -- a nested one is no place of the home
		t.expect(sel.staticProjects(rules, { "pong/lobby.project.jsonc" })).toEqual({ "pong" })
	end)
end)
