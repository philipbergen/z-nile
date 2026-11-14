--!strict
-- c0246 AC1-AC6 (AC5 and AC6 ask Rojo itself, `rojo sourcemap`, round 8): the home rule reports a "$path" it cannot read. Rojo 7.7.1 accepts a string, {"optional": "<string>"}
-- (extra keys ignored) and, as probed at prep, a one-element array of strings (it maps the folder, even one outside the
-- home); every other value fails Rojo's own parse. graph.mappings reads the first two and skips the rest, so the rule must
-- name what is skipped. Shapes come from serde.decode, so they are the ones a project file really decodes to. Fixtures
-- under .cache/c0246-paths (this home's .cache).
local fs = require("@lune/fs")
local graph = require("@znile/lib/graph")
local home = require("@tests/lib/home")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local BASE = ".cache/c0246-paths"

local function decode(json: string): any
	return serde.decode("json", json)
end
-- a project with one node `A` whose "$path" is the JSON text `value`
local function withPath(value: string): any
	return decode(`\{ "name": "p", "tree": \{ "A": \{ "$path": {value} \} \} \}`)
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
local function put(rel: string, text: string)
	local path = `{BASE}/{rel}`
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end

local BAD: { [string]: string } = {
	["5"] = "a number",
	["true"] = "a boolean",
	['["../outside"]'] = "an array",
	["{}"] = "a table without an optional string",
	['{ "optional": 5 }'] = "an optional that is a number",
	['{ "optional": ["a"] }'] = "an optional that is a table",
}
local GOOD = { '"src/a"', '{ "optional": "src/a" }', '{ "optional": "src/a", "x": 1 }', "null" }

return t.spec("c0246 the home rule reports a $path it cannot read", function(it)
	it("AC1: graph.unreadable names every $path that is not a string or an optional string", function()
		for value, what in BAD do
			t.expect(graph.unreadable(withPath(value))).toEqual({ { instance = "A", what = what } })
		end
		for _, value in GOOD do
			t.expect(graph.unreadable(withPath(value))).toEqual({})
		end
		t.expect(graph.unreadable({})).toEqual({})
		t.expect(graph.unreadable({ tree = 5 })).toEqual({})
	end)

	it('AC1: the tree node (instance "") and nested nodes are read, sorted by instance', function()
		local project = decode(
			'{ "name": "p", "tree": { "$path": 7, "Z": { "$path": false }, "A": { "B": { "$path": [] }, "$path": "src" } } }'
		)
		t.expect(graph.unreadable(project)).toEqual({
			{ instance = "", what = "a number" },
			{ instance = "A/B", what = "a table without an optional string" },
			{ instance = "Z", what = "a boolean" },
		})
	end)

	it("AC1: the order is by instance path, not the walk's (a parent-first walk cannot give it)", function()
		-- "A-" sorts before "A/Z" ("-" is 45, "/" is 47) although a parent-first walk visits A, A/Z, then A-
		local project = decode(
			'{ "name": "p", "tree": { "A": { "$path": 5, "Z": { "$path": 5 } }, "A-": { "$path": 5 } } }'
		)
		t.expect(graph.unreadable(project)).toEqual({
			{ instance = "A", what = "a number" },
			{ instance = "A-", what = "a number" },
			{ instance = "A/Z", what = "a number" },
		})
	end)

	it(
		"AC1: a node named with a $ that Rojo does not reserve is reported, the six it reserves are not",
		function()
			-- Rojo 7.7.1 builds "$X" and "$schema" as instances (with a warning), mapping what their "$path" names
			local project = decode(
				'{ "name": "p", "tree": { "$className": "DataModel", "$X": { "$path": "../out" }, "A": { "$schema": { "$path": ["../out"] } }, "B": { "$id": "x", "$ignoreUnknownInstances": true, "$properties": { "P": 1 }, "$attributes": { "Q": 1 } } } }'
			)
			local what = "a node Rojo builds although its key starts with $"
			t.expect(graph.unreadable(project)).toEqual({
				{ instance = "$X", what = what, dollar = true },
				{ instance = "A/$schema", what = what, dollar = true },
			})
			-- the readers still do not walk them
			t.expect(graph.mappings(project)).toEqual({})
		end
	)

	it("AC2: graph.mappings and graph.gameRoots still skip them, and keep the readable ones", function()
		for value in BAD do
			t.expect(graph.mappings(withPath(value))).toEqual({})
			t.expect(graph.gameRoots(withPath(value))).toEqual({})
		end
		local mixed = decode('{ "tree": { "A": { "$path": 5 }, "B": { "$path": { "optional": "src/b" } } } }')
		t.expect(graph.mappings(mixed)).toEqual({ { instance = "B", path = "src/b" } })
	end)

	it("AC3: the rule reports each, with the file, the node and what the value is", function()
		if fs.isDir(BASE) then
			fs.removeDir(BASE)
		end
		put("stylua.toml", 'indent_type = "Tabs"\n')
		put("selene.toml", 'std = "roblox"\n')
		put("pong/default.project.json", '{ "name": "pong", "tree": { "A": { "$path": "src/shared" } } }')
		put(
			"pong/weird.project.json",
			'{ "name": "w", "tree": { "$path": 7, "N": { "$path": true }, "O": { "$path": ["../../pickman/src/shared"] }, "P": { "$path": { "optional": 5 }, "Deep": { "$path": 3 } }, "Q": { "$path": { "optional": "src/shared" } }, "$R": { "$path": "src/shared" } } }'
		)
		put("pong/only.project.json", '{ "name": "o", "tree": { "A": { "$path": 5 } } }')
		local reg, err = projects.parse('[[project]]\nname = "pong"\nroot = "pong/.tracker"\n')
		t.expect(err).toBe(nil)
		local found = home.problems(BASE, reg :: projects.Registry)
		local weird = lines(found, "weird.project.json")
		local function hasLine(list: { string }, node: string, what: string): boolean
			for _, l in list do
				if
					string.find(l, node, 1, true)
					and string.find(l, what, 1, true)
					and string.find(l, "$path", 1, true)
				then
					return true
				end
			end
			return false
		end
		t.expect(#lines(weird, "has a ")).toBe(6) -- five $paths and one $ node, nothing else
		t.expect(#lines(weird, "a node named $R (")).toBe(1)
		t.expect(hasLine(weird, "the tree root", "a number")).toBe(true)
		t.expect(hasLine(weird, "node N", "a boolean")).toBe(true)
		t.expect(hasLine(weird, "node O", "an array")).toBe(true)
		t.expect(hasLine(weird, "node P/Deep", "a number")).toBe(true)
		t.expect(hasLine(weird, "node P", "an optional that is a number")).toBe(true)
		-- the readable optional string at Q is judged as before (outside nothing here: it is a folder that does not exist)
		t.expect(#lines(weird, "which is no folder of the home")).toBe(1)
		fs.removeDir(BASE)
	end)

	it("AC3: a file whose only $path is unreadable is not also reported as mapping no $path", function()
		if fs.isDir(BASE) then
			fs.removeDir(BASE)
		end
		put("stylua.toml", 'indent_type = "Tabs"\n')
		put("selene.toml", 'std = "roblox"\n')
		put("pong/only.project.json", '{ "name": "o", "tree": { "A": { "$path": 5 } } }')
		-- Rojo 7.7.1 builds a project file with a comment; Lune's decoder refuses it: the rule must still say so
		put(
			"pong/commented.project.json",
			'// a comment\n{ "name": "c", "tree": { "A": { "$path": "../../pickman/src/shared" } } }'
		)
		put("pong/empty.project.json", '{ "name": "e", "tree": { "A": { "$className": "Folder" } } }')
		local reg = projects.parse('[[project]]\nname = "pong"\nroot = "pong/.tracker"\n')
		local found = home.problems(BASE, reg :: projects.Registry)
		t.expect(#lines(found, "only.project.json has a $path")).toBe(1)
		t.expect(#lines(found, "only.project.json maps no $path")).toBe(0)
		t.expect(#lines(found, "empty.project.json maps no $path")).toBe(1)
		t.expect(#lines(found, "commented.project.json maps no $path")).toBe(1)
		fs.removeDir(BASE)
	end)

	-- a fixture home `pong` whose default.project.json is `tree`, with the throwaway tree under BASE
	local function pong(tree: string)
		if fs.isDir(BASE) then
			fs.removeDir(BASE)
		end
		put("stylua.toml", 'indent_type = "Tabs"\n')
		put("selene.toml", 'std = "roblox"\n')
		put("pong/default.project.json", `\{ "name": "pong", "tree": \{ "$className": "Folder", {tree} \} \}`)
		put("x/o.luau", "return 1") -- a folder outside the home
	end
	local function problemsOf(): { string }
		local reg = projects.parse('[[project]]\nname = "pong"\nroot = "pong/.tracker"\n')
		return home.problems(BASE, reg :: projects.Registry)
	end
	local function link(target: string, at: string)
		t.expect(process.exec("ln", { "-s", target, `{BASE}/{at}` }).ok).toBe(true)
	end

	it(
		"AC5: a project file Rojo loads from a mapped folder is a nested project, at any depth and in any casing",
		function()
			-- Rojo 7.7.1 loads a *.project.json(c) at any depth of a synced folder, and default.project.json in any casing
			-- (it looks that name up by path; probed in rounds 4, 7 and 8): the rule reads what Rojo reports, not a list of names
			pong(
				'"A": { "$path": "src/one" }, "B": { "$path": "src/two" }, "C": { "$path": "src/three" }, "D": { "$path": "src/four" }, "E": { "$path": "src/five" }, "F": { "$path": "src/clean" }'
			)
			put("pong/src/one/Evil.project.json", '{ "name": "e", "tree": { "$path": ["../../../x"] } }')
			put(
				"pong/src/two/Deep/Deeper/Other.project.json",
				'{ "name": "e", "tree": { "$path": "../../../../../x" } }'
			)
			put("pong/src/three/default.project.json", '{ "name": "e", "tree": { "$className": "Folder" } }')
			put(
				"pong/src/four/Sub/DEFAULT.PROJECT.JSON",
				'{ "name": "e", "tree": { "$path": "../../../../x" } }'
			)
			put("pong/src/five/Sub/N.project.jsonc", '{ "name": "e", "tree": { "$path": "../../../../x" } }')
			put("pong/src/clean/k.luau", "return 1")
			put("pong/src/clean/data.json", "{}")
			local found = problemsOf()
			for _, file in
				{
					"src/one/Evil.project.json",
					"src/two/Deep/Deeper/Other.project.json",
					"src/three/default.project.json",
					"src/four/Sub/default.project.json", -- Rojo reports the name it looked up
					"src/five/Sub/N.project.jsonc",
				}
			do
				t.expect(#lines(found, `default.project.json loads {file} as a nested project`)).toBe(1)
			end
			t.expect(#lines(found, "src/clean")).toBe(0)
			-- the nested projects map a folder outside the home: one line for the project file, however many files
			t.expect(
				#lines(found, "default.project.json makes Rojo read ../x/o.luau, which is outside the home")
			)
				.toBe(1)
			t.expect(#lines(found, "makes Rojo read")).toBe(1)
		end
	)

	it(
		"AC5: a project file reached through a link that stays in the home is a nested project; one outside is not read",
		function()
			-- Rojo follows a link inside a synced folder, and one inside a linked folder (probed in round 5): the files it
			-- lists are judged by their real paths
			pong(
				'"A": { "$path": "src/folder" }, "B": { "$path": "src/chain" }, "C": { "$path": "src/file" }, "D": { "$path": "src/top" }, "E": { "$path": "src/deep" }'
			)
			put("pong/stash/X.project.json", '{ "name": "x", "tree": { "$className": "Folder" } }')
			put("pong/stash2/Y.project.json", '{ "name": "y", "tree": { "$className": "Folder" } }')
			put("pong/elsewhere/Z.project.json", '{ "name": "z", "tree": { "$className": "Folder" } }')
			put("pong/src/folder/k.luau", "return 1")
			put("pong/src/chain/k.luau", "return 1")
			put("pong/src/file/k.luau", "return 1")
			put("pong/src/top/k.luau", "return 1")
			put("pong/src/deep/k.luau", "return 1")
			put("pong/holder/k.luau", "return 1")
			put("outside/Evil.project.json", '{ "name": "e", "tree": { "$className": "Folder" } }')
			link("../../stash", "pong/src/folder/L") -- a linked folder holding a project file
			link("../../holder", "pong/src/chain/L1") -- a link whose folder holds a link to a project folder
			link("../stash2", "pong/holder/L2")
			link("../../elsewhere/Z.project.json", "pong/src/file/F.project.json") -- a linked project file
			link("../../../x", "pong/src/top/o") -- leaves the home directly
			link("../../stash", "pong/src/deep/L") -- inside the home...
			link("../../outside", "pong/stash/o") -- ...and leaving it one folder down the link
			local found = problemsOf()
			for _, file in { "L/X.project.json", "L1/L2/Y.project.json", "F.project.json" } do
				t.expect(#lines(found, `{file} as a nested project`) >= 1).toBe(true)
			end
			-- a file read through a link out of the home is outside it, wherever the link sits
			t.expect(#lines(found, "makes Rojo read")).toBe(1)
			t.expect(#lines(found, "which is outside the home")).toBe(1)
			-- the old per-folder checks still name the link out beside it
			t.expect(#lines(found, "maps $path src/top, which holds a link out of the home")).toBe(1)
			fs.removeDir(BASE)
		end
	)

	it(
		"AC5: a link loop is a build Rojo refuses, so it reads no file and the rule neither crashes nor reports it",
		function()
			pong('"A": { "$path": "src/loop" }')
			put("pong/src/loop/k.luau", "return 1")
			link(".", "pong/src/loop/self")
			local found = problemsOf()
			t.expect(#lines(found, "ojo")).toBe(0) -- no line of the net at all, not a "refused" line either
			t.expect(#lines(found, "nested project")).toBe(0)
			fs.removeDir(BASE)
		end
	)

	it(
		"AC3: a project file that decodes to a number, a boolean or null is still reported, not a crash",
		function()
			if fs.isDir(BASE) then
				fs.removeDir(BASE)
			end
			put("stylua.toml", 'indent_type = "Tabs"\n')
			put("selene.toml", 'std = "roblox"\n')
			local texts: { [string]: string } = { num = "5", flag = "true", null = "null" }
			for name, text in texts do
				put(`pong/{name}.project.json`, text)
			end
			local reg = projects.parse('[[project]]\nname = "pong"\nroot = "pong/.tracker"\n')
			local found = home.problems(BASE, reg :: projects.Registry)
			for _, name in { "num", "flag", "null" } do
				t.expect(#lines(found, `{name}.project.json maps no $path`)).toBe(1)
			end
			fs.removeDir(BASE)
		end
	)

	it(
		"AC6: a project Rojo loads through syncRules is judged by what it reads, a file without the rule is not",
		function()
			-- Rojo 7.7.1 loads a file of any name as a project when a rule says use "project" (probed in round 5): ev.txt then
			-- maps a folder outside the home. Without the rule the same file is a string value and reads nothing
			pong('"A": { "$path": "src/shared" }')
			put(
				"pong/sr.project.json",
				'{ "name": "s", "syncRules": [ { "pattern": "*.txt", "use": "project" } ], "tree": { "$className": "Folder", "A": { "$path": "src/shared" } } }'
			)
			put(
				"pong/plain.project.json",
				'{ "name": "p", "tree": { "$className": "Folder", "A": { "$path": "src/plain" } } }'
			)
			put("pong/src/shared/ev.txt", '{ "name": "t", "tree": { "$path": "../../../x" } }')
			put("pong/src/plain/ev.txt", '{ "name": "t", "tree": { "$path": "../../../x" } }')
			local found = problemsOf()
			t.expect(#lines(found, "sr.project.json makes Rojo read ../x/o.luau, which is outside the home"))
				.toBe(1)
			t.expect(#lines(found, "plain.project.json makes Rojo read")).toBe(0)
			t.expect(#lines(found, "default.project.json makes Rojo read")).toBe(0)
			t.expect(#lines(found, "nested project")).toBe(0) -- a top-level project file is not a nested one
			t.expect(#lines(found, "rojo cannot be run")).toBe(0)
			fs.removeDir(BASE)
		end
	)

	it("AC5: a library folder sits at its node wherever a link or a syncRules project puts it", function()
		-- the server folder must never reach a client: Rojo 7.7.1 puts arcade/src/server into ReplicatedStorage through a
		-- link inside a linked folder, or through a project loaded by syncRules, and the files' real paths are the library's
		-- own (round 8 F1). The instance path is Rojo's own answer
		if fs.isDir(BASE) then
			fs.removeDir(BASE)
		end
		put("stylua.toml", 'indent_type = "Tabs"\n')
		put("selene.toml", 'std = "roblox"\n')
		put("arcade/src/shared/Info.luau", "return 1")
		put("arcade/src/server/Secret.luau", "return 'server secret'")
		local function place(own: string): string
			return `\{ "name": "p", "tree": \{ "$className": "DataModel", "ReplicatedStorage": \{ "$className": "ReplicatedStorage", "Arcade": \{ "$path": "../arcade/src/shared" \}, "Game": \{ "$path": "{own}" \} \}, "ServerStorage": \{ "$className": "ServerStorage", "Arcade": \{ "$path": "../arcade/src/server" \} \} \} \}`
		end
		put("pong/default.project.json", place("src/shared")) -- a chained link puts the server folder under Game
		put("pong/ok.project.json", place("src/clean")) -- the same places, nothing misplaced
		put(
			"pong/off.project.json",
			(
				string.gsub(
					place("src/clean"),
					'"Arcade": { "$path": "../arcade/src/shared" }',
					'"ArcadeX": { "$path": "../arcade/src/shared" }',
					1
				)
			)
		) -- a node that only starts like the library's
		put(
			"pong/sr.project.json",
			(
				string.gsub(
					place("src/rules"),
					'^{ "name": "p",',
					'{ "name": "p", "syncRules": [ { "pattern": "*.txt", "use": "project" } ],',
					1
				)
			)
		)
		put("pong/src/shared/k.luau", "return 1")
		put("pong/src/clean/k.luau", "return 1")
		put("pong/src/rules/ev.txt", '{ "name": "Leak", "tree": { "$path": "../../../arcade/src/server" } }')
		put("pong/stash/k.luau", "return 1")
		link("../../stash", "pong/src/shared/L")
		link("../../arcade/src/server", "pong/stash/S")
		local found = problemsOf()
		t.expect(#lines(found, "default.project.json makes Rojo put")).toBe(1)
		t.expect(#lines(found, "sr.project.json makes Rojo put")).toBe(1)
		t.expect(#lines(found, "ok.project.json makes Rojo")).toBe(0)
		t.expect(#lines(found, "off.project.json makes Rojo put")).toBe(1)
		t.expect(#lines(found, "which is not the library's node (ServerStorage/Arcade)")).toBe(2)
		fs.removeDir(BASE)
	end)

	it(
		"AC5: the inside test is exact: a sibling of the home and the library's other folders are outside",
		function()
			-- reached through a chained link, as in round 8 F2: a prefix test without the slash accepts pong2 (and
			-- arcade/src/shared-x), and one on the library's whole home accepts arcade/tests
			pong('"A": { "$path": "src/a" }')
			put("pong/src/a/k.luau", "return 1")
			put(
				"pong/ok.project.json",
				'{ "name": "o", "tree": { "$className": "Folder", "A": { "$path": "src/a" } } }'
			)
			put("pong2/k.luau", "return 1")
			put("arcade/src/shared/Info.luau", "return 1")
			put("arcade/src/shared-x/k.luau", "return 1")
			put("arcade/tests/t.luau", "return 1")
			put("pong/stash/k.luau", "return 1")
			link("../../stash", "pong/src/a/L")
			local targets = {
				sibling = "../../pong2",
				library = "../../arcade/tests",
				lookalike = "../../arcade/src/shared-x",
			}
			local order = { "sibling", "library", "lookalike" }
			for _, key in order do
				put(
					`pong/{key}.project.json`,
					`\{ "name": "{key}", "tree": \{ "$className": "Folder", "A": \{ "$path": "src/{key}" \} \} \}`
				)
				put(`pong/src/{key}/k.luau`, "return 1")
				put(`pong/stash-{key}/k.luau`, "return 1")
				link(`../../stash-{key}`, `pong/src/{key}/L`)
				link(targets[key], `pong/stash-{key}/S`)
			end
			local found = problemsOf()
			for _, key in order do
				t.expect(#lines(found, `{key}.project.json makes Rojo read`)).toBe(1)
			end
			t.expect(#lines(found, "ok.project.json makes Rojo")).toBe(0)
			fs.removeDir(BASE)
		end
	)

	it("AC6: a rojo that cannot be run is reported, not read as a refusal", function()
		-- behind rokit's shim a missing pinned Rojo exits 1, as a refused file does (round 8 F3): a child lune whose PATH
		-- starts with a stub that exits 1 stands in for it
		pong('"A": { "$path": "src/shared" }')
		put("pong/src/shared/k.luau", "return 1")
		put("bin/rojo", "#!/bin/sh\nexit 1\n")
		t.expect(process.exec("chmod", { "+x", `{BASE}/bin/rojo` }).ok).toBe(true)
		put(
			"probe.luau",
			`--!nolint\nlocal home = require("@tests/lib/home")\nlocal projects = require("@znile/engine/projects")\nlocal reg = projects.parse('[[project]]\\nname = "pong"\\nroot = "pong/.tracker"\\n')\nfor _, line in home.problems("{BASE}", reg :: any) do\n\tprint(line)\nend\n`
		)
		local here = (string.gsub(process.exec("pwd").stdout, "%s+$", ""))
		local res = process.exec("lune", { "run", `{BASE}/probe.luau` }, {
			env = { PATH = `{here}/{BASE}/bin:{process.env.PATH or ""}` },
		})
		local found: { string } = {}
		for line in string.gmatch(res.stdout, "[^\n]+") do
			table.insert(found, line)
		end
		t.expect(res.ok).toBe(true)
		t.expect(#lines(found, "pong: rojo cannot be run")).toBe(1)
		fs.removeDir(BASE)
	end)

	it("AC4: the README states the rule", function()
		local top = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
		local readme = fs.readFile(`{top}/z-nile/README.md`)
		t.expect(string.find(readme, '`{"optional": "<path>"}`', 1, true) ~= nil).toBe(true)
		t.expect(string.find(readme, "any other value is reported", 1, true) ~= nil).toBe(true)
		t.expect(string.find(readme, "asks Rojo itself", 1, true) ~= nil).toBe(true)
	end)
end)
