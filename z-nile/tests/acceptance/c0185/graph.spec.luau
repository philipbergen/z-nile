--!strict
-- c0185 AC1, AC2, AC3: the graph library follows code shared across homes. `@game/ServerStorage/` is allowed from a server
-- root only; a home's place specs depend on every folder its project files map, another home's included, and on each
-- project file; a unit spec that reaches the library through the `arcade` alias is selected by a change there. Fixtures
-- under .cache/c0185-graph (this home's): a game `snake`, the library `arcade`, and their project files, as the repository
-- spells them. The graph is seen from z-nile/, as the selector's callers see a home (paths into another home start with
-- ../ only from inside a home; here the fixture lies below the current folder).
local fs = require("@lune/fs")
local graph = require("@znile/lib/graph")
local t = require("@tests/lib/t")

local base = ".cache/c0185-graph"
local R = "req" .. "uire" -- keeps literal require text out of this file (the graph scanner)

local function write(rel: string, text: string)
	local path = `{base}/{rel}`
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end
local function isSpec(f: string): boolean
	return string.match(f, "%.spec%.luau$") ~= nil
end
local function literal(text: string): string -- a Lua pattern that matches `text` only
	return (string.gsub(text, "%p", "%%%0"))
end
local function has(list: { string }, item: string): boolean
	return table.find(list, item) ~= nil
end

local GAME = [[{ "name": "snake", "tree": { "$className": "DataModel",
  "ReplicatedStorage": { "Shared": { "$path": "src/shared" }, "Arcade": { "$path": "../arcade/src/shared" } },
  "ServerStorage": { "Arcade": { "$path": "../arcade/src/server" } },
  "ServerScriptService": { "Server": { "$path": "src/server" } },
  "StarterPlayer": { "StarterPlayerScripts": { "Client": { "$path": "src/client" } } } } }]]

local function roots(prefix: string): { graph.GameRoot }
	return {
		{ instance = "ServerStorage/Arcade", path = `{prefix}../arcade/src/server` },
		{ instance = "ServerScriptService/Server", path = `{prefix}src/server` },
		{ instance = "StarterPlayer/StarterPlayerScripts/Client", path = `{prefix}src/client` },
		{ instance = "ReplicatedStorage/Shared", path = `{prefix}src/shared` },
		{ instance = "ReplicatedStorage/Arcade", path = `{prefix}../arcade/src/shared` },
	}
end

return t.spec("c0185 the graph follows code shared across homes", function(it)
	it(
		"AC1: @game/ServerStorage/ is allowed from a server root only; the other services stay refused",
		function()
			local spec = "@game/ServerStorage/Arcade/Receipts"
			t.expect(graph.srcAliasAllowed(spec)).toBe(false) -- the caller named no server root
			t.expect(graph.srcAliasAllowed(spec, false)).toBe(false)
			t.expect(graph.srcAliasAllowed(spec, true)).toBe(true)
			for _, other in
				{
					"@game/ServerScriptService/Server/Sessions",
					"@game/StarterPlayer/StarterPlayerScripts/Client/Camera",
					"@game/ServerStorageX/Arcade/Receipts",
					"@game/ServerStorage",
					"@Game/ServerStorage/Arcade/Receipts",
					"@arcade/Info",
				}
			do
				t.expect(graph.srcAliasAllowed(other, true)).toBe(false)
			end
			for _, always in { "./A", "../B", "@self/C", "@game/ReplicatedStorage/Arcade/Logic/Rng" } do
				t.expect(graph.srcAliasAllowed(always, false)).toBe(true)
				t.expect(graph.srcAliasAllowed(always, true)).toBe(true)
			end
		end
	)

	it("AC1: a file is a server file by the node that maps it: the longest mapped path owns it", function()
		local r = roots("")
		table.insert(r, { instance = "ReplicatedStorage/Shared/Net", path = "src/server/net" }) -- a nested client-visible node
		table.insert(r, { instance = "ReplicatedStorage/ServerThings", path = "src/things" }) -- "Server" in a name is no service
		t.expect(graph.serverFile("src/server/Main.server.luau", { r })).toBe(true)
		t.expect(graph.serverFile("src/server/deep/x.luau", { r })).toBe(true)
		t.expect(graph.serverFile("src/server/net/x.luau", { r })).toBe(false) -- the nested node is ReplicatedStorage's
		t.expect(graph.serverFile("src/client/Main.client.luau", { r })).toBe(false)
		t.expect(graph.serverFile("src/shared/Logic/X.luau", { r })).toBe(false)
		t.expect(graph.serverFile("src/serverx/x.luau", { r })).toBe(false) -- a prefix is not a folder
		t.expect(graph.serverFile("src/things/x.luau", { r })).toBe(false)
		t.expect(graph.serverFile("src/elsewhere/x.luau", { r })).toBe(false) -- no node maps it
		t.expect(graph.serverFile("../arcade/src/server/Receipts.luau", { r })).toBe(true) -- the library's server folder
		t.expect(graph.serverFile("src/server/x.luau", {})).toBe(false)
		local direct = { { instance = "ServerStorage", path = "src/store" } }
		t.expect(graph.serverFile("src/store/x.luau", { direct })).toBe(true) -- a service mapped as a whole
	end)

	it("AC1: a file is a server file in every place that maps it, and in at least one", function()
		local main = { { instance = "ServerScriptService/Server", path = "src/server" } }
		local lobby = { { instance = "ServerScriptService/Lobby", path = "src/lobby/server" } }
		local both = { main, lobby }
		t.expect(graph.serverFile("src/lobby/server/Boards.luau", both)).toBe(true) -- mapped by the second place alone
		t.expect(graph.serverFile("src/server/Main.server.luau", both)).toBe(true)
		-- one place replicates what another keeps on the server: a ServerStorage require would fail there
		local third = { { instance = "ReplicatedStorage/X", path = "src/lobby/server" } }
		t.expect(graph.serverFile("src/lobby/server/Boards.luau", { main, lobby, third })).toBe(false)
		t.expect(graph.serverFile("src/nowhere/x.luau", both)).toBe(false) -- no place maps it
		-- a node that is itself a file
		local solo = { { instance = "ServerScriptService/Main", path = "src/server/Main.server.luau" } }
		t.expect(graph.serverFile("src/server/Main.server.luau", { solo })).toBe(true)
		t.expect(graph.serverFile("src/server/Other.luau", { solo })).toBe(false)
	end)

	it(
		"AC1: srcAliasViolations applies the rule per file: ServerStorage in a server file passes, elsewhere not",
		function()
			if fs.isDir(base) then
				fs.removeDir(base)
			end
			local want = `{R}("@game/ServerStorage/Arcade/Receipts")\n`
			write("snake/src/server/Main.server.luau", `local A = {want}`)
			write("snake/src/client/Main.client.luau", `local A = {want}`)
			write("snake/src/shared/Logic/X.luau", `local A = {want}local B = {R}("./Y")\n`)
			write("snake/src/server/Bad.luau", `local A = {R}("@game/ServerScriptService/Server/Secret")\n`)
			local got = graph.srcAliasViolations(`{base}/snake/src`, { roots(`{base}/snake/`) })
			t.expect(got).toEqual({
				{
					file = `{base}/snake/src/client/Main.client.luau`,
					spec = "@game/ServerStorage/Arcade/Receipts",
				},
				{
					file = `{base}/snake/src/server/Bad.luau`,
					spec = "@game/ServerScriptService/Server/Secret",
				},
				{
					file = `{base}/snake/src/shared/Logic/X.luau`,
					spec = "@game/ServerStorage/Arcade/Receipts",
				},
			})
			fs.removeDir(base)
		end
	)

	it(
		"AC2: placeInputs lists a home's project files and every folder they map, another home's collapsed",
		function()
			if fs.isDir(base) then
				fs.removeDir(base)
			end
			write("snake/default.project.json", GAME)
			write(
				"snake/lobby.project.json",
				'{ "name": "l", "tree": { "A": { "$path": "src/lobby" }, "B": { "$path": { "optional": "src/maybe" } }, "C": { "$properties": { "X": 1 } }, "D": { "$path": "/opt/x" } } }'
			)
			local inputs = graph.placeInputs(`{base}/snake/`)
			for _, want in
				{
					`{base}/snake/default.project.json`,
					`{base}/snake/lobby.project.json`,
					`{base}/snake/src/shared`,
					`{base}/snake/src/server`,
					`{base}/snake/src/client`,
					`{base}/snake/src/lobby`,
					`{base}/snake/src/maybe`,
					`{base}/arcade/src/shared`,
					`{base}/arcade/src/server`,
					"/opt/x", -- an absolute path is kept as it is, not read under the home
				}
			do
				t.expect(has(inputs, want)).toBe(true)
			end
			t.expect(#inputs).toBe(10)
			fs.removeDir(base)
		end
	)

	it(
		"AC2: one reader of a project's mappings: both forms of a $path, the tree node, and what stays in a folder",
		function()
			local project = {
				tree = {
					["$path"] = "src/tree",
					A = { ["$path"] = "src/a", B = { ["$path"] = { optional = "../lib/b" } } },
					C = { ["$properties"] = { X = 1 } },
				},
			}
			t.expect(graph.mappings(project)).toEqual({
				{ instance = "", path = "src/tree" },
				{ instance = "A", path = "src/a" },
				{ instance = "A/B", path = "../lib/b" },
			})
			t.expect(graph.mappings({})).toEqual({})
			-- an absolute path (Rojo accepts one) stays absolute: it is not under any home
			t.expect(graph.mappings({ tree = { A = { ["$path"] = "/opt/x" } } }))
				.toEqual({ { instance = "A", path = "/opt/x" } })
			-- gameRoots answers from the same walker (longest instance first), without the tree node
			local gameRoots = graph.gameRoots(project)
			t.expect(#gameRoots).toBe(2)
			t.expect(gameRoots[1]).toEqual({ instance = "A/B", path = "../lib/b" })
			local cases: { [string]: boolean } = {
				["src/shared"] = true,
				["./src"] = true,
				["a/../b"] = true,
				[".."] = false,
				["../arcade/src/shared"] = false,
				["src/../../arcade/src/shared"] = false,
				["src/../.."] = false,
				["/opt/x"] = false,
			}
			for path, inside in cases do
				t.expect(graph.insideFolder(path)).toBe(inside)
			end
		end
	)

	it(
		"AC2: a home with no project file gets the legacy answer; a project file that is not JSON is an error",
		function()
			if fs.isDir(base) then
				fs.removeDir(base)
			end
			write("bare/src/x.luau", "return 1\n")
			t.expect(graph.placeInputs(`{base}/bare/`)).toEqual({
				`{base}/bare/src`,
				`{base}/bare/default.project.json`,
				`{base}/bare/lobby.project.json`,
			})
			write("broken/default.project.json", "{ not json")
			t.expect(function()
				graph.placeInputs(`{base}/broken/`)
			end).toThrow(literal(`{base}/broken/default.project.json is not a Rojo project`))
			write("array/default.project.json", "[1, 2]")
			t.expect(function()
				graph.placeInputs(`{base}/array/`)
			end).toThrow(literal(`{base}/array/default.project.json is not a Rojo project`))
			fs.removeDir(base)
		end
	)

	it(
		"AC2: a change to the library or a project file selects that home's place specs, not its unit specs",
		function()
			if fs.isDir(base) then
				fs.removeDir(base)
			end
			write("snake/default.project.json", GAME)
			write("snake/other.project.json", '{ "name": "o", "tree": { "Z": { "$path": "src/other" } } }')
			write("snake/tests/lib/place.luau", "return nil\n")
			write("snake/tests/place/p.spec.luau", `local place = {R}("../lib/place")\n`)
			write("snake/tests/unit/u.spec.luau", "return nil\n")
			write(
				"pong/default.project.json",
				'{ "name": "pong", "tree": { "A": { "$path": "src/shared" } } }'
			)
			write("pong/tests/lib/place.luau", "return nil\n")
			write("pong/tests/place/q.spec.luau", `local place = {R}("../lib/place")\n`)
			local g = graph.build({ `{base}/snake/tests`, `{base}/pong/tests` })
			local function sel(change: string): { string }
				return graph.affectedSpecs(g, { `{base}/{change}` }, isSpec)
			end
			local P, Q = `{base}/snake/tests/place/p.spec.luau`, `{base}/pong/tests/place/q.spec.luau`
			t.expect(sel("arcade/src/shared/Logic/Rng/init.luau")).toEqual({ P }) -- mapped by snake, not by pong
			t.expect(sel("arcade/src/server/Receipts.luau")).toEqual({ P })
			t.expect(sel("snake/src/shared/Logic/X/init.luau")).toEqual({ P })
			t.expect(sel("snake/default.project.json")).toEqual({ P })
			t.expect(sel("snake/other.project.json")).toEqual({ P })
			t.expect(sel("snake/src/other/Y.luau")).toEqual({ P }) -- mapped by a second project file
			t.expect(sel("pong/src/shared/Z.luau")).toEqual({ Q })
			t.expect(sel("arcade/src/shared")).toEqual({ P }) -- the folder itself
			t.expect(sel("snake/src/unmapped/W.luau")).toEqual({}) -- in no place
			t.expect(sel("arcade/srcx/Info.luau")).toEqual({}) -- a look-alike prefix
			t.expect(sel("arcade/src/sharedx/X.luau")).toEqual({}) -- a mapped folder's name is a prefix of this one
			t.expect(sel("snake/src/shared2/Y.luau")).toEqual({})
			t.expect(sel("arcade/tests/unit/x.spec.luau")).toEqual({}) -- the library's tests are not in the place
			t.expect(sel("snake/README.md")).toEqual({})
			fs.removeDir(base)
		end
	)

	it("AC2: inputs can be injected, and a home's inputs are its own", function()
		local g: graph.Graph = {
			files = {
				"a/tests/place/p.spec.luau",
				"a/tests/lib/place.luau",
				"b/tests/place/q.spec.luau",
				"b/tests/lib/place.luau",
			},
			deps = {
				["a/tests/place/p.spec.luau"] = { "a/tests/lib/place.luau" },
				["b/tests/place/q.spec.luau"] = { "b/tests/lib/place.luau" },
				["a/tests/lib/place.luau"] = {},
				["b/tests/lib/place.luau"] = {},
			},
			unresolved = {},
			dynamic = {},
		}
		local function inputs(home: string): { string }
			return if home == "a/" then { "lib", "a/x.project.json" } else { "b/src" }
		end
		local function sel(change: string): { string }
			return graph.affectedSpecs(g, { change }, isSpec, inputs)
		end
		t.expect(sel("lib/Y.luau")).toEqual({ "a/tests/place/p.spec.luau" })
		t.expect(sel("a/x.project.json")).toEqual({ "a/tests/place/p.spec.luau" })
		t.expect(sel("b/src/Z.luau")).toEqual({ "b/tests/place/q.spec.luau" })
		t.expect(sel("a/src/Z.luau")).toEqual({})
	end)

	it(
		"AC3: a unit spec that reaches the library through the arcade alias is selected by a change there",
		function()
			if fs.isDir(base) then
				fs.removeDir(base)
			end
			write("snake/.luaurc", '{ "aliases": { "arcade": "../arcade/src/shared", "tests": "./tests" } }')
			write("snake/tests/unit/Rng/rng.spec.luau", `local Rng = {R}("@arcade/Logic/Rng")\nreturn Rng\n`)
			write("snake/tests/unit/Other/other.spec.luau", "return nil\n")
			write("arcade/src/shared/Logic/Rng/init.luau", "return {}\n")
			write("arcade/src/shared/Logic/Other/init.luau", "return {}\n")
			local g = graph.build({ `{base}/snake/tests`, `{base}/arcade/src` })
			t.expect(#g.unresolved).toBe(0)
			local U = `{base}/snake/tests/unit/Rng/rng.spec.luau`
			t.expect(g.deps[U]).toEqual({ `{base}/arcade/src/shared/Logic/Rng/init.luau` })
			t.expect(graph.affectedSpecs(g, { `{base}/arcade/src/shared/Logic/Rng/init.luau` }, isSpec))
				.toEqual({ U })
			t.expect(graph.affectedSpecs(g, { `{base}/arcade/src/shared/Logic/Other/init.luau` }, isSpec))
				.toEqual({})
			fs.removeDir(base)
		end
	)
end)
