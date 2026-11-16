--!strict
-- c0185 AC4: the home rule (z-nile/tests/lib/home.luau) holds every home to the library's wiring, on fixture homes: the
-- `arcade` alias, the two library folders as the only `$path`s that leave a home, the default place mapping them under
-- ReplicatedStorage.Arcade and ServerStorage.Arcade, and the place tier's two wrappers. A fixture home that has all of it is
-- clean, so each case below breaks exactly one thing. Fixtures under .cache/c0185-library (this home's). Promoted, so it pins
-- the rule and not today's set of projects: the real tree is judged by c0184's homes.spec for every registered project.
local fs = require("@lune/fs")
local home = require("@tests/lib/home")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local t = require("@tests/lib/t")

local BASE = ".cache/c0185-library"
local R = "req" .. "uire" -- keeps literal require text out of this file (the graph scanner)

local function put(rel: string, text: string)
	local path = `{BASE}/{rel}`
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end

local PLACE_WRAPPER = `--!strict\nreturn {R}("../../../z-nile/tests/lib/place")\n`
local SPEC_WRAPPER =
	`--!strict\nlocal place = {R}("@tests/lib/place")\nreturn {R}("../../../z-nile/tests/lib/placespec")(place)\n`
local LUAURC =
	[[{ "languageMode": "strict", "aliases": { "logic": "./src/shared/Logic", "shared": "./src/shared",
  "arcade": "../arcade/src/shared", "tests": "./tests", "znile": "../z-nile" } }]]
local PROJECT = [[{ "name": "ping", "tree": { "$className": "DataModel",
  "ReplicatedStorage": { "Shared": { "$path": "src/shared" }, "Arcade": { "$path": "../arcade/src/shared" } },
  "ServerStorage": { "Arcade": { "$path": "../arcade/src/server" } } } }]]

-- a home `ping` that meets the rule, next to a library home `arcade`, under BASE; `fix` rewrites a file after it is written
local function build(fix: { [string]: string }?)
	if fs.isDir(BASE) then
		fs.removeDir(BASE)
	end
	local over: { [string]: string } = fix or {}
	local used: { [string]: boolean } = {}
	local function file(rel: string, text: string)
		used[rel] = true
		put(rel, over[rel] or text)
	end
	put("stylua.toml", 'indent_type = "Tabs"\n')
	put("selene.toml", 'std = "roblox"\n')
	put("arcade/src/shared/Info.luau", "--!strict\nreturn { name = 'arcade' }\n")
	put("arcade/src/server/.gitkeep", "")
	file("ping/.luaurc", LUAURC)
	file("ping/default.project.json", PROJECT)
	file("ping/stylua.toml", 'indent_type = "Tabs"\n')
	file("ping/selene.toml", 'std = "roblox"\n')
	file(
		"ping/check.sh",
		'#!/usr/bin/env bash\nexec bash "$(dirname "$0")/../z-nile/check.sh" --project ping "$@"\n'
	)
	process.exec("chmod", { "+x", `{BASE}/ping/check.sh` })
	put("ping/src/shared/Logic/.gitkeep", "")
	put("ping/src/server/.gitkeep", "")
	file("ping/tests/run.luau", `--!strict\nreturn {R}("../../z-nile/tests/run")\n`)
	file(
		"ping/tests/lib/t.luau",
		`--!strict\nlocal t = {R}("../../../z-nile/tests/lib/t")\nexport type Case = t.Case\nexport type Spec = t.Spec\nreturn t\n`
	)
	file("ping/tests/lib/renamed.luau", `--!strict\nreturn {R}("../../../z-nile/tests/lib/renamed")\n`)
	file("ping/tests/lib/place.luau", PLACE_WRAPPER)
	file(
		"ping/tests/meta/fence.spec.luau",
		`--!strict\nreturn {R}("../../../z-nile/tests/tooling/repo-fence.spec")\n`
	)
	file("ping/tests/meta/home.spec.luau", `--!strict\nreturn {R}("../../../z-nile/tests/lib/homespec")\n`)
	file(
		"ping/tests/meta/architecture.spec.luau",
		`--!strict\nreturn {R}("../../../pickman/tests/meta/architecture.spec")\n`
	)
	file("ping/tests/place/library.spec.luau", SPEC_WRAPPER)
	put("ping/skills/ping-arch/SKILL.md", "---\nname: ping-arch\n---\n")
	put("ping/skills/ping-test/SKILL.md", "---\nname: ping-test\n---\n")
	put("ping/.tracker/architecture.md", "# x\n\n```deps\n# none\n```\n")
	for rel, text in over do -- a file the home does not have by default (another project file)
		if not used[rel] then
			put(rel, text)
		end
	end
end

local function report(): string
	local reg, err = projects.parse('[[project]]\nname = "ping"\nroot = "ping/.tracker"\n')
	t.expect(err).toBe(nil)
	local found, checked = home.problems(BASE, reg :: projects.Registry)
	t.expect(checked).toEqual({ "ping" })
	return "\n" .. table.concat(found, "\n") .. "\n"
end

-- the library's own home: ping's files under the name `arcade`, its project file mapping its two folders from inside
local function libraryHome()
	local function copy(rel: string)
		local from = `{BASE}/ping/{rel}`
		if fs.isDir(from) then
			for _, name in fs.readDir(from) do
				copy(if rel == "" then name else `{rel}/{name}`)
			end
		else
			local text = string.gsub(fs.readFile(from), "ping", "arcade")
			put(`arcade/{(string.gsub(rel, "ping", "arcade"))}`, text)
		end
	end
	copy("")
	process.exec("chmod", { "+x", `{BASE}/arcade/check.sh` })
	put(
		"arcade/default.project.json",
		[[{ "name": "arcade", "tree": { "$className": "DataModel",
  "ReplicatedStorage": { "Arcade": { "$path": "src/shared" } }, "ServerStorage": { "Arcade": { "$path": "src/server" } } } }]]
	)
end

local function reportOf(name: string): string
	local reg, err = projects.parse(`[[project]]\nname = "{name}"\nroot = "{name}/.tracker"\n`)
	t.expect(err).toBe(nil)
	local found, checked = home.problems(BASE, reg :: projects.Registry)
	t.expect(checked).toEqual({ name })
	return "\n" .. table.concat(found, "\n") .. "\n"
end

local function reports(text: string, what: string): boolean
	return string.find(text, `\nping: {what}\n`, 1, true) ~= nil
end

return t.spec("c0185 the home rule holds the library's wiring", function(it)
	it(
		"AC4: a home with the alias, the mapping and the place tier is clean, and the library's own paths are fine",
		function()
			build()
			t.expect(report()).toBe("\n\n")
			-- the library's own home maps its folders from inside it
			libraryHome()
			t.expect(reportOf("arcade")).toBe("\n\n")
			-- a second place of the home maps the library at the same two nodes
			build({
				["ping/lobby.project.json"] = [[{ "name": "l", "tree": { "ReplicatedStorage": { "Arcade": { "$path": "../arcade/src/shared" } },
  "ServerStorage": { "Arcade": { "$path": "../arcade/src/server" } } } }]],
			})
			t.expect(report()).toBe("\n\n")
			fs.removeDir(BASE)
		end
	)

	it(
		"AC4: the default place is the one that maps the library; another project file's mapping is not enough",
		function()
			local lib =
				[[{ "name": "l", "tree": { "ReplicatedStorage": { "Arcade": { "$path": "../arcade/src/shared" } },
  "ServerStorage": { "Arcade": { "$path": "../arcade/src/server" } } } }]]
			build({
				["ping/default.project.json"] = '{ "name": "ping", "tree": { "ReplicatedStorage": { "Shared": { "$path": "src/shared" } } } }',
				["ping/lobby.project.json"] = lib,
			})
			local text = report()
			t.expect(
				reports(
					text,
					"default.project.json does not map ReplicatedStorage.Arcade to arcade/src/shared"
				)
			)
				.toBe(true)
			t.expect(
				reports(text, "default.project.json does not map ServerStorage.Arcade to arcade/src/server")
			)
				.toBe(true)
			fs.removeDir(BASE)
		end
	)

	it("AC4: an absolute $path is outside the home, whatever it collapses to", function()
		local abs =
			[[{ "name": "ping", "tree": { "ReplicatedStorage": { "Shared": { "$path": "src/shared" }, "Arcade": { "$path": "/../arcade/src/shared" } },
  "ServerStorage": { "Arcade": { "$path": "/../arcade/src/server" } } } }]]
		build({ ["ping/default.project.json"] = abs })
		local text = report()
		t.expect(
			reports(text, "default.project.json maps $path /../arcade/src/shared, which is outside the home")
		)
			.toBe(true)
		t.expect(
			reports(text, "default.project.json does not map ReplicatedStorage.Arcade to arcade/src/shared")
		)
			.toBe(true)
		fs.removeDir(BASE)
	end)

	it("AC4: the arcade alias is required, with its one target", function()
		local without =
			[[{ "languageMode": "strict", "aliases": { "logic": "./src/shared/Logic", "shared": "./src/shared",
  "tests": "./tests", "znile": "../z-nile" } }]]
		build({ ["ping/.luaurc"] = without })
		t.expect(reports(report(), ".luaurc alias arcade is not ../arcade/src/shared")).toBe(true)
		build({ ["ping/.luaurc"] = string.gsub(LUAURC, "../arcade/src/shared", "../arcade/src/server") })
		t.expect(reports(report(), ".luaurc alias arcade is not ../arcade/src/shared")).toBe(true)
		fs.removeDir(BASE)
	end)

	it(
		"AC4: the default place maps the library's two folders under their two services, and nothing else will do",
		function()
			local none =
				'{ "name": "ping", "tree": { "ReplicatedStorage": { "Shared": { "$path": "src/shared" } } } }'
			build({ ["ping/default.project.json"] = none })
			local text = report()
			t.expect(
				reports(
					text,
					"default.project.json does not map ReplicatedStorage.Arcade to arcade/src/shared"
				)
			)
				.toBe(true)
			t.expect(
				reports(text, "default.project.json does not map ServerStorage.Arcade to arcade/src/server")
			)
				.toBe(true)
			-- swapped: the server folder under ReplicatedStorage (it would replicate to every client)
			local swapped = string.gsub(
				string.gsub(PROJECT, "%.%./arcade/src/server", "@@"),
				"%.%./arcade/src/shared",
				"../arcade/src/server"
			)
			build({ ["ping/default.project.json"] = string.gsub(swapped, "@@", "../arcade/src/shared") })
			text = report()
			t.expect(
				reports(
					text,
					"default.project.json does not map ReplicatedStorage.Arcade to arcade/src/shared"
				)
			)
				.toBe(true)
			t.expect(
				reports(text, "default.project.json does not map ServerStorage.Arcade to arcade/src/server")
			)
				.toBe(true)
			-- the same folder spelled another way is the same mapping
			build({
				["ping/default.project.json"] = string.gsub(
					PROJECT,
					"%.%./arcade/src/shared",
					"../ping/../arcade/src/shared"
				),
			})
			t.expect(report()).toBe("\n\n")
			fs.removeDir(BASE)
		end
	)

	it(
		"AC4: the library's two folders are the one $path that may leave a home; no other folder of it, nor of another home",
		function()
			-- the library's server folder at any other node is reported (it would replicate to every client), in any project file
			for _, node in
				{
					'"ReplicatedStorage": { "Leak": { "$path": "../arcade/src/server" } }',
					'"StarterPlayer": { "StarterPlayerScripts": { "S": { "$path": "../arcade/src/server" } } }',
					'"ServerStorage": { "Arcade": { "$path": "../arcade/src/shared" } }',
					'"ReplicatedStorage": { "Arcade": { "$path": { "optional": "../arcade/src/server" } } }',
				}
			do
				build({ ["ping/other.project.json"] = '{ "name": "o", "tree": { ' .. node .. " } }" })
				t.expect(string.find(report(), "which is not its node", 1, true) ~= nil).toBe(true)
			end
			-- the optional form of a $path is read like the string form
			build({
				["ping/other.project.json"] = '{ "name": "o", "tree": { "A": { "$path": { "optional": "../pong/src" } } } }',
			})
			t.expect(
				reports(report(), "other.project.json maps $path ../pong/src, which is outside the home")
			)
				.toBe(true)
			-- a folder that holds a project of its own is followed by Rojo through that project's mappings
			build({
				["ping/other.project.json"] = '{ "name": "o", "tree": { "A": { "$path": "src/nested" } } }',
				["ping/src/nested/default.project.json"] = '{ "name": "n", "tree": {} }',
			})
			t.expect(string.find(report(), "a nested project", 1, true) ~= nil).toBe(true)
			build({
				["ping/other.project.json"] = '{ "name": "o", "tree": { "A": { "$path": "../arcade/tests" } } }',
			})
			t.expect(
				reports(report(), "other.project.json maps $path ../arcade/tests, which is outside the home")
			)
				.toBe(true)
			build({
				["ping/other.project.json"] = '{ "name": "o", "tree": { "A": { "$path": "../arcade/src" } } }',
			})
			t.expect(
				reports(report(), "other.project.json maps $path ../arcade/src, which is outside the home")
			)
				.toBe(true)
			build({
				["ping/other.project.json"] = '{ "name": "o", "tree": { "A": { "$path": "../pong/src/shared" } } }',
			})
			t.expect(
				reports(
					report(),
					"other.project.json maps $path ../pong/src/shared, which is outside the home"
				)
			)
				.toBe(true)
			-- a library folder that is a link out of the library is still reported
			build({
				["ping/other.project.json"] = '{ "name": "o", "tree": { "ServerStorage": { "Arcade": { "$path": "../arcade/src/server" } } } }',
			})
			put("pong/src/.gitkeep", "")
			fs.removeDir(`{BASE}/arcade/src/server`)
			t.expect(process.exec("ln", { "-s", `../../pong/src`, `{BASE}/arcade/src/server` }).ok).toBe(true)
			t.expect(string.find(report(), "which is a link out of the library", 1, true) ~= nil).toBe(true)
			build({
				["ping/other.project.json"] = '{ "name": "o", "tree": { "ServerStorage": { "Arcade": { "$path": "../arcade/src/server" } } } }',
			})
			fs.removeDir(`{BASE}/arcade/src/server`)
			t.expect(string.find(report(), "which is no folder of the library", 1, true) ~= nil).toBe(true)
			fs.removeDir(BASE)
		end
	)

	it("AC4: the place tier's two wrappers are exactly their lines", function()
		build({ ["ping/tests/lib/place.luau"] = "--!strict\nreturn nil\n" })
		local text = report()
		t.expect(
			reports(
				text,
				`tests/lib/place.luau is not exactly: --!strict / return {R}("../../../z-nile/tests/lib/place")`
			)
		).toBe(true)
		-- a spec that does not hand over the home's own place, so its closure would not name the home
		build({
			["ping/tests/place/library.spec.luau"] = `--!strict\nreturn {R}("../../../z-nile/tests/lib/placespec")({R}("../../../z-nile/tests/lib/place"))\n`,
		})
		t.expect(
			string.find(report(), "\nping: tests/place/library.spec.luau is not exactly: ", 1, true) ~= nil
		)
			.toBe(true)
		-- a missing wrapper is a missing file
		build()
		fs.removeFile(`{BASE}/ping/tests/place/library.spec.luau`)
		fs.removeFile(`{BASE}/ping/tests/lib/place.luau`)
		text = report()
		t.expect(reports(text, "missing tests/place/library.spec.luau")).toBe(true)
		t.expect(reports(text, "missing tests/lib/place.luau")).toBe(true)
		fs.removeDir(BASE)
	end)
end)
