--!strict
-- c0246 review 001 F1: the home rule's two fail-closed branches on what Rojo prints. The sequestered paths.spec cannot
-- hold them (a file name with a newline and a stub rojo are this spec's fixtures). Fixtures under .cache/c0246-failclosed
-- (this home's .cache); the stub is reached through a child lune's PATH, like paths.spec's "rojo cannot be run" case.
local fs = require("@lune/fs")
local home = require("@tests/lib/home")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local t = require("@tests/lib/t")

local BASE = ".cache/c0246-failclosed"
local REG = '[[project]]\nname = "pong"\nroot = "pong/.tracker"\n'

local function put(rel: string, text: string)
	local path = `{BASE}/{rel}`
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
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
-- a fixture home `pong` mapping src/a, with the stylua and selene files the home rule asks for
local function pong()
	if fs.isDir(BASE) then
		fs.removeDir(BASE)
	end
	put("stylua.toml", 'indent_type = "Tabs"\n')
	put("selene.toml", 'std = "roblox"\n')
	put(
		"pong/default.project.json",
		'{ "name": "pong", "tree": { "$className": "Folder", "A": { "$path": "src/a" } } }'
	)
	put("pong/src/a/k.luau", "return 1")
end

return t.spec("c0246 the home rule fails closed on what Rojo prints", function(it)
	it("a file name Rojo lists with a newline cannot be resolved, and is reported once", function()
		pong()
		put("pong/src/a/we\nird.luau", "return 2")
		local reg = projects.parse(REG)
		local found = home.problems(BASE, reg :: projects.Registry)
		t.expect(#lines(found, "default.project.json: the files Rojo reads cannot be resolved")).toBe(1)
		-- a clean place gets neither failure line
		pong()
		local clean = home.problems(BASE, reg :: projects.Registry)
		t.expect(#lines(clean, "cannot be resolved")).toBe(0)
		t.expect(#lines(clean, "printed no JSON")).toBe(0)
		fs.removeDir(BASE)
	end)

	it("an answer from rojo sourcemap that is not JSON is reported", function()
		pong()
		-- the stub answers `--version` (the probe passes) and the exact sourcemap arguments the rule passes; anything else exits 2
		put(
			"bin/rojo",
			`#!/bin/sh\nif [ "$1" = "--version" ]; then echo "rojo 7.7.1"; exit 0; fi\nif [ "$1" = "sourcemap" ] && [ "$2" = "--include-non-scripts" ] && [ "$3" = "{BASE}/pong/default.project.json" ]; then echo "this is not json"; exit 0; fi\nexit 2\n`
		)
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
		t.expect(#lines(found, "default.project.json: rojo sourcemap printed no JSON")).toBe(1)
		t.expect(#lines(found, "rojo cannot be run")).toBe(0)
		fs.removeDir(BASE)
	end)

	-- the library's server folder mapped by `tree`, in a fixture home `pong`; the problems the home rule reports
	local function serverUnder(tree: string): { string }
		pong()
		put("arcade/src/server/S.luau", "return 1")
		put("pong/default.project.json", `\{ "name": "pong", "tree": {tree} \}`)
		return home.problems(BASE, projects.parse(REG) :: projects.Registry)
	end

	-- a node's identity is its (name, class) path under the root's class, not its joined names (review 002 F1, 003 F1)
	it(
		"the library's server folder is accepted only at a ServerStorage service named Arcade under a DataModel",
		function()
			local SERVICE =
				'"$className": "DataModel", "ServerStorage": { "$className": "ServerStorage", "Arcade": { "$path": "../arcade/src/server" } }'
			t.expect(#lines(serverUnder(`\{ {SERVICE} \}`), "makes Rojo put")).toBe(0)
			-- a ReplicatedFirst named ServerStorage spells the node and replicates the server code to every client
			local first = serverUnder(
				'{ "$className": "DataModel", "ServerStorage": { "$className": "ReplicatedFirst", "Arcade": { "$path": "../arcade/src/server" } } }'
			)
			t.expect(#lines(first, "default.project.json makes Rojo put")).toBe(1)
			t.expect(#lines(first, "its first node is a ReplicatedFirst named ServerStorage")).toBe(1)
			-- a Folder named ServerStorage is not the service either
			local folder = serverUnder(
				'{ "$className": "DataModel", "ServerStorage": { "$className": "Folder", "Arcade": { "$path": "../arcade/src/server" } } }'
			)
			t.expect(#lines(folder, "default.project.json makes Rojo put")).toBe(1)
			t.expect(#lines(folder, "its first node is a Folder named ServerStorage")).toBe(1)
			-- a root that is not the DataModel is not a place's tree
			local root = serverUnder(
				'{ "$className": "Folder", "ServerStorage": { "$className": "ServerStorage", "Arcade": { "$path": "../arcade/src/server" } } }'
			)
			t.expect(#lines(root, "default.project.json makes Rojo put")).toBe(1)
			t.expect(#lines(root, "the root is a Folder, not a DataModel")).toBe(1)
			-- one key spelled "ServerStorage/Arcade" is one node of that name, not a child of the service
			local slash = serverUnder(
				'{ "$className": "DataModel", "ServerStorage/Arcade": { "$path": "../arcade/src/server" } }'
			)
			t.expect(#lines(slash, "default.project.json makes Rojo put")).toBe(1)
			t.expect(#lines(slash, "its first node is a Folder named ServerStorage/Arcade")).toBe(1)
			fs.removeDir(BASE)
		end
	)

	it(
		"a library folder whose own file sits exactly at the library's node is not misplaced (review 002 F3)",
		function()
			pong()
			-- arcade/src/shared/init.luau makes Rojo's ReplicatedStorage/Arcade a module whose file IS the node, not below it
			put("arcade/src/shared/init.luau", "return 1")
			put(
				"pong/default.project.json",
				'{ "name": "pong", "tree": { "$className": "DataModel", "ReplicatedStorage": { "$className": "ReplicatedStorage", "Arcade": { "$path": "../arcade/src/shared" } } } }'
			)
			local reg = projects.parse(REG)
			local found = home.problems(BASE, reg :: projects.Registry)
			t.expect(#lines(found, "makes Rojo put")).toBe(0)
			t.expect(#lines(found, "makes Rojo read")).toBe(0)
			fs.removeDir(BASE)
		end
	)
end)
