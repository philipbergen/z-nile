--!strict
-- c0185 AC5, AC6: the shared place harness (z-nile/tests/lib/place.luau). It reads the script roots of a place from its
-- project file: every node the file maps from inside its own folder, and none of another home's (the library's),
-- which that home's own place spec judges. It resolves requires as Roblox does, so `@game/ReplicatedStorage/Arcade/...`
-- and `@game/ServerStorage/Arcade/...` reach the library and a relative path does not; the same two spellings resolve
-- the other way round on disk (E2). Fixtures under .cache/c0185-place (this home's): a library `arcade` and a game
-- `snake` that maps it, built with Rojo from here (a project path is relative to the current folder).
local fs = require("@lune/fs")
local graph = require("@znile/lib/graph")
local place = require("@tests/lib/place")
local placespec = require("@tests/lib/placespec")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local t = require("@tests/lib/t")

local base = ".cache/c0185-place"
local R = "req" .. "uire" -- keeps literal require text out of this file (the graph scanner)

local function write(rel: string, text: string)
	local path = `{base}/{rel}`
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end

local function names(list: { any }): { string }
	local out: { string } = {}
	for _, s in list do
		table.insert(out, s:GetFullName())
	end
	return out
end

local function find(game: any, path: string): any
	local node = game
	for seg in string.gmatch(path, "[^/]+") do
		node = node and node:FindFirstChild(seg)
	end
	return node
end

return t.spec("c0185 the shared place harness", function(it)
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	write("arcade/src/shared/Logic/Rng/init.luau", "--!strict\nreturn { name = 'rng' }\n")
	write("arcade/src/server/Receipts.luau", "--!strict\nreturn { name = 'receipts' }\n")
	write(
		"snake/src/server/Main.server.luau",
		`--!strict\nlocal Rng = {R}("@game/ReplicatedStorage/Arcade/Logic/Rng")\nlocal Receipts = {R}("@game/ServerStorage/Arcade/Receipts")\nprint(Rng, Receipts)\n`
	)
	write("snake/src/client/Main.client.luau", "--!strict\nprint('client')\n")
	write("snake/src/shared/Logic/Info.luau", "--!strict\nreturn { name = 'snake' }\n")
	write("snake/src/extra/E.luau", "--!strict\nreturn { name = 'extra' }\n")
	write("snake/src/lobby/Lobby.server.luau", "--!strict\nprint('lobby')\n")
	write("snake/src/solo/S.luau", "--!strict\nreturn { name = 'solo' }\n")
	write("snake/src/inner/I.luau", "--!strict\nreturn { name = 'inner' }\n")
	write(
		"snake/default.project.json",
		[[{ "name": "snake", "tree": { "$className": "DataModel",
  "ReplicatedStorage": { "Shared": { "$path": "src/shared" }, "Extra": { "$path": "src/extra", "Inner": { "$path": "src/inner" } }, "Solo": { "$path": "src/solo/S.luau" },
    "Sneaky": { "$path": "src/../../arcade/src/shared" }, "Arcade": { "$path": "../arcade/src/shared" } },
  "ServerStorage": { "Arcade": { "$path": "../arcade/src/server" } },
  "ServerScriptService": { "Server": { "$path": "src/server" } },
  "StarterPlayer": { "StarterPlayerScripts": { "Client": { "$path": "src/client" } } } } }]]
	)
	write(
		"snake/lobby.project.json",
		[[{ "name": "lobby", "tree": { "$className": "DataModel",
  "ReplicatedStorage": { "Shared": { "$path": "src/shared" } },
  "ServerScriptService": { "Lobby": { "$path": "src/lobby" } } } }]]
	)
	local game = place.load(`{base}/snake/default.project.json`)

	it(
		"AC5: it lists the scripts of the nodes the project file maps from its own folder, and none of the library's",
		function()
			t.expect(table.concat(names(place.scripts(game)), "\n")).toBe(table.concat({
				"ReplicatedStorage.Extra.E",
				"ReplicatedStorage.Extra.Inner.I",
				"ReplicatedStorage.Shared.Logic.Info",
				"ReplicatedStorage.Solo",
				"ServerScriptService.Server.Main",
				"StarterPlayer.StarterPlayerScripts.Client.Main",
			}, "\n"))
			-- the library is in the place, only not among the scripts this home answers for
			t.expect(find(game, "ReplicatedStorage/Arcade/Logic/Rng") ~= nil).toBe(true)
			t.expect(find(game, "ServerStorage/Arcade/Receipts") ~= nil).toBe(true)
		end
	)

	it("AC5: the roots are those of the project file loaded: a second place has its own", function()
		local lobby = place.load(`{base}/snake/lobby.project.json`)
		t.expect(names(place.scripts(lobby))).toEqual({
			"ReplicatedStorage.Shared.Logic.Info",
			"ServerScriptService.Lobby.Lobby",
		})
		t.expect(place.load(`{base}/snake/lobby.project.json`)).toBe(lobby) -- built once per process
		t.expect(place.load(`{base}/snake/default.project.json`)).toBe(game)
	end)

	it("AC5: a DataModel place.load did not build has no known roots, and the error says so", function()
		t.expect(function()
			place.scripts(roblox.Instance.new("Folder"))
		end).toThrow("place.scripts: the place was not loaded by place.load")
	end)

	it(
		"AC6 (E2): the library is reached by @game, which the place resolves, and a relative path to its files is not",
		function()
			local main = find(game, "ServerScriptService/Server/Main")
			t.expect(place.resolveRequire(main, "@game/ReplicatedStorage/Arcade/Logic/Rng"))
				.toBe(find(game, "ReplicatedStorage/Arcade/Logic/Rng"))
			t.expect(place.resolveRequire(main, "@game/ServerStorage/Arcade/Receipts"))
				.toBe(find(game, "ServerStorage/Arcade/Receipts"))
			-- the way the files lie on disk (home, then library): no such path in the instance tree
			t.expect(place.resolveRequire(main, "../../../../arcade/src/shared/Logic/Rng")).toBe(nil)
			t.expect(place.resolveRequire(main, "../../arcade/src/server/Receipts")).toBe(nil)
			-- every require of the home's scripts resolves, as the place spec of every home asserts
			for _, s in place.scripts(game) do
				for _, spec in place.requireSpecs(s.Source) do
					t.expect(place.resolveRequire(s, spec) ~= nil).toBe(true)
				end
			end
		end
	)

	it(
		"AC6 (E2): the instance-tree spelling of a path to the library resolves in the place and not on disk",
		function()
			local info = find(game, "ReplicatedStorage/Shared/Logic/Info")
			-- siblings under ReplicatedStorage: Roblox finds it, the files do not lie that way
			t.expect(place.resolveRequire(info, "../../Arcade/Logic/Rng"))
				.toBe(find(game, "ReplicatedStorage/Arcade/Logic/Rng"))
			local from = `{base}/snake/src/shared/Logic/Info.luau`
			t.expect(graph.resolve(from, "../../Arcade/Logic/Rng")).toBe(nil)
			-- and the spelling the files do have resolves on disk (the graph follows it out of the home)
			t.expect(graph.resolve(from, "../../../../arcade/src/shared/Logic/Rng"))
				.toBe(`{base}/arcade/src/shared/Logic/Rng/init.luau`)
		end
	)

	it(
		"AC5: the shared place spec of every home fails a require that does not resolve and a place without the library",
		function()
			write(
				"bad1/src/server/Main.server.luau",
				`--!strict\nlocal N = {R}("@game/ServerStorage/Arcade/Nope")\nprint(N)\n`
			)
			write(
				"bad1/default.project.json",
				[[{ "name": "bad1", "tree": { "$className": "DataModel",
  "ReplicatedStorage": { "Arcade": { "$path": "../arcade/src/shared" } },
  "ServerStorage": { "Arcade": { "$path": "../arcade/src/server" } },
  "ServerScriptService": { "Server": { "$path": "src/server" } } } }]]
			)
			write("bad2/src/server/Main.server.luau", "--!strict\nprint('x')\n")
			write(
				"bad2/default.project.json",
				[[{ "name": "bad2", "tree": { "$className": "DataModel",
  "ReplicatedStorage": { "Arcade": { "$path": "../arcade/src/shared" } },
  "ServerScriptService": { "Server": { "$path": "src/server" } } } }]]
			)
			-- placespec takes the home's place re-export; here it gets the shared harness loading each fixture's project file
			local function failing(project: string): string
				local stand: any = table.clone(place)
				stand.load = function()
					return place.load(project)
				end
				local failed: { string } = {}
				for _, case in placespec(stand).cases do
					if not pcall(case.fn) then
						table.insert(failed, case.name)
					end
				end
				return table.concat(failed, "|")
			end
			t.expect(failing(`{base}/snake/default.project.json`)).toBe("")
			t.expect(failing(`{base}/bad1/default.project.json`))
				.toBe("every string require in the home's scripts resolves to a ModuleScript in the DataModel")
			t.expect(failing(`{base}/bad2/default.project.json`))
				.toBe("holds the library: ReplicatedStorage.Arcade and ServerStorage.Arcade are folders")
		end
	)

	it("AC5: an absolute $path is no root of the home, whatever folder it names", function()
		write("abs/A.luau", "--!strict\nreturn { name = 'abs' }\n")
		local root = string.gsub(process.cwd, "/+$", "")
		write(
			"snake/abs.project.json",
			'{ "name": "abs", "tree": { "$className": "DataModel", "ReplicatedStorage": { "Shared": { "$path": "src/shared" }, "Abs": { "$path": "'
				.. `{root}/{base}/abs`
				.. '" } } } }'
		)
		local abs = place.load(`{base}/snake/abs.project.json`)
		t.expect(find(abs, "ReplicatedStorage/Abs/A") ~= nil).toBe(true) -- it is in the place
		t.expect(table.concat(names(place.scripts(abs)), "\n")).toBe("ReplicatedStorage.Shared.Logic.Info") -- not among the home's
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
