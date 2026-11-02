--!strict
-- c0184 AC1: the home rule reads the registry, so a project added later is held to it. The rule itself is
-- z-nile/tests/lib/home.luau, which each home's own tests/meta/home.spec.luau runs from the home it judges (an edit to a
-- home selects its own check). This spec is z-nile's: it runs the rule on fixture homes, to show that it names every
-- missing or wrong file of a project nobody listed, and that every registered project but z-nile has the wrapper that
-- runs it. Promoted, so it pins the rule and not today's set of projects (zz-test lesson promoted-specs-pin-rules-not-sets).
-- Fixtures under .cache/c0184-homes (this home's .cache); the real tree is read from its top.
local fs = require("@lune/fs")
local home = require("@tests/lib/home")
local process = require("@lune/process")
local projects = require("@znile/engine/projects")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local HERE = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local BASE = `{HERE}/.cache/c0184-homes`
local R = "req" .. "uire" -- keeps literal require text out of this file (the graph scanner)
local problems = home.problems

local function registry(text: string): projects.Registry
	local reg, err = projects.parse(text)
	t.expect(err).toBe(nil)
	return reg :: projects.Registry
end

local function put(rel: string, text: string)
	local path = `{BASE}/{rel}`
	fs.writeDir(string.match(path, "^(.*)/[^/]+$") :: string)
	fs.writeFile(path, text)
end

return t.spec("c0184 every project's home is scaffolded", function(it)
	it(
		"AC1: every registered project but z-nile has the wrapper that runs the home rule, pickman among them",
		function()
			local names: { string } = {}
			for _, p in projects.load(TOP).projects do
				if p.name ~= "z-nile" then
					table.insert(names, p.name)
					t.expect(fs.isFile(`{TOP}/{p.home}/tests/meta/home.spec.luau`)).toBe(true)
				end
			end
			t.expect(table.find(names, "pickman") ~= nil).toBe(true)
		end
	)

	it(
		"AC1: the rule holds on the real tree for every registered project but z-nile, pickman among them",
		function()
			-- the net under the per-home specs: a home whose own runner or home.spec was neutered runs nothing, so z-nile
			-- judges the homes too (an edit to one is not selected by this spec; the merge's full gate runs it)
			local reg = projects.load(TOP)
			local found, checked = problems(TOP, reg)
			t.expect(table.concat(found, "\n")).toBe("")
			local want: { string } = {}
			for _, p in reg.projects do
				if p.name ~= "z-nile" then
					table.insert(want, p.name)
				end
			end
			t.expect(checked).toEqual(want)
			t.expect(table.find(checked, "pickman") ~= nil).toBe(true)
		end
	)

	it("AC1: a root map with two deps blocks, or one never closed, is reported", function()
		if fs.isDir(BASE) then
			fs.removeDir(BASE)
		end
		put("stylua.toml", 'indent_type = "Tabs"\n')
		put("selene.toml", 'std = "roblox"\n')
		put("two/.tracker/architecture.md", "# x\n\n```deps\n# a\n```\n\n```deps\n# b\n```\n")
		put("open/.tracker/architecture.md", "# x\n\n```deps\n# never closed\n")
		local reg = registry(
			'[[project]]\nname = "two"\nroot = "two/.tracker"\n\n[[project]]\nname = "open"\nroot = "open/.tracker"\n'
		)
		local found = problems(BASE, reg)
		local text = "\n" .. table.concat(found, "\n") .. "\n"
		-- only the prefix and the map's path are pinned: the wording is the deps reader's once c0163 lands
		t.expect(string.find(text, "\ntwo: two/.tracker/architecture.md ", 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, "\nopen: open/.tracker/architecture.md ", 1, true) ~= nil).toBe(true)
		fs.removeDir(BASE)
	end)

	it(
		"AC1: a project the registry lists is held to it: a home with nothing but its root reports every file",
		function()
			if fs.isDir(BASE) then
				fs.removeDir(BASE)
			end
			put("z-nile/projects.toml", "")
			put("pong/.tracker/issues/active/.gitkeep", "")
			put("stylua.toml", 'indent_type = "Tabs"\n')
			put("selene.toml", 'std = "roblox"\n')
			local reg = registry(
				'[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n\n[[project]]\nname = "pong"\nroot = "pong/.tracker"\n'
			)
			local found, checked = problems(BASE, reg)
			t.expect(checked).toEqual({ "pong" })
			local text = "\n" .. table.concat(found, "\n") .. "\n"
			for _, what in
				{
					"missing check.sh",
					"missing .luaurc",
					"missing stylua.toml",
					"missing selene.toml",
					"missing default.project.json",
					"missing src/shared/Logic",
					"missing src/server",
					"missing tests/run.luau",
					"missing tests/lib/t.luau",
					"missing tests/lib/renamed.luau",
					"missing tests/meta/fence.spec.luau",
					"missing tests/meta/home.spec.luau",
					"missing tests/meta/architecture.spec.luau",
					"missing skills/pong-arch/SKILL.md",
					"missing skills/pong-test/SKILL.md",
					"missing pong/.tracker/architecture.md",
				}
			do
				t.expect(string.find(text, `\npong: {what}\n`, 1, true) ~= nil).toBe(true)
			end
			fs.removeDir(BASE)
		end
	)

	it("AC1: a home whose files are there but wrong is reported for each", function()
		if fs.isDir(BASE) then
			fs.removeDir(BASE)
		end
		put("stylua.toml", 'indent_type = "Tabs"\n')
		put("selene.toml", 'std = "roblox"\n')
		put("ping/stylua.toml", 'indent_type = "Spaces"\n')
		put("ping/selene.toml", 'std = "roblox"\n')
		put(
			"ping/check.sh",
			'#!/usr/bin/env bash\nexec bash "$(dirname "$0")/../z-nile/check.sh" --project other "$@"\n'
		)
		put(
			"ping/.luaurc",
			'{ "languageMode": "nonstrict", "aliases": { "logic": "./src/Logic", "tests": "./tests" } }'
		)
		put("ping/default.project.json", '{ "name": "ping", "tree": { "A": { "$path": "src/nowhere" } } }')
		put("ping/other.project.json", '{ "name": "x", "tree": {} }')
		put("ping/third.project.json", '{ "name": "y", "tree": { "B": { "$path": "../other/src" } } }')
		put("other/src/.gitkeep", "")
		put("ping/src/.gitkeep", "")
		put("ping/fifth.project.json", '{ "name": "w", "tree": { "D": { "$path": "src/shared" } } }')
		put("ping/fourth.project.json", '{ "name": "z", "tree": { "C": { "$path": "src/link" } } }')
		put("ping/src/shared/Logic/.gitkeep", "")
		put("ping/src/server/.gitkeep", "")
		put("ping/tests/run.luau", "--!strict\nreturn nil\n")
		put("ping/tests/lib/t.luau", "--!strict\nreturn nil\n")
		put("ping/tests/lib/renamed.luau", "--!strict\nreturn nil\n")
		put(
			"ping/tests/meta/fence.spec.luau",
			`--!strict\n-- disabled: return {R}("../../../z-nile/tests/tooling/repo-fence.spec")\nreturn nil\n`
		)
		put("ping/tests/meta/home.spec.luau", "--!strict\nreturn nil\n")
		put("ping/tests/meta/architecture.spec.luau", "--!strict\nreturn nil\n")
		put("ping/skills/ping-arch/SKILL.md", "---\nname: pong-arch\n---\n")
		put("ping/skills/ping-test/SKILL.md", "---\nname: ping-test\n---\n")
		put("ping/.tracker/architecture.md", "# x\n")
		process.exec("chmod", { "-x", `{BASE}/ping/check.sh` })
		t.expect(process.exec("ln", { "-s", `{BASE}/other/src`, `{BASE}/ping/src/link` }).ok).toBe(true)
		t.expect(process.exec("ln", { "-s", `{BASE}/other/src`, `{BASE}/ping/src/shared/lnk` }).ok).toBe(true)
		local reg = registry('[[project]]\nname = "ping"\nroot = "ping/.tracker"\n')
		local found = problems(BASE, reg)
		local text = "\n" .. table.concat(found, "\n") .. "\n"
		for _, what in
			{
				`check.sh lacks exec bash "$(dirname "$0")/../z-nile/check.sh" --project ping "$@"`,
				"check.sh is not executable",
				"stylua.toml is not the root's",
				".luaurc is not strict",
				".luaurc alias logic is not ./src/shared/Logic",
				".luaurc alias shared is not ./src/shared",
				".luaurc alias znile is not ../z-nile",
				"default.project.json maps $path src/nowhere, which is no folder of the home",
				"other.project.json maps no $path",
				"third.project.json maps $path ../other/src, which is outside the home",
				"fourth.project.json maps $path src/link, which is a link out of the home",
				"fifth.project.json maps $path src/shared, which holds a link out of the home",
				`tests/run.luau is not exactly: --!strict / return {R}("../../z-nile/tests/run")`,
				`tests/lib/t.luau is not exactly: --!strict / local t = {R}("../../../z-nile/tests/lib/t") / export type Case = t.Case / export type Spec = t.Spec / return t`,
				`tests/lib/renamed.luau is not exactly: --!strict / return {R}("../../../z-nile/tests/lib/renamed")`,
				`tests/meta/fence.spec.luau is not exactly: --!strict / return {R}("../../../z-nile/tests/tooling/repo-fence.spec")`,
				`tests/meta/home.spec.luau is not exactly: --!strict / return {R}("../../../z-nile/tests/lib/homespec")`,
				`tests/meta/architecture.spec.luau is not exactly: --!strict / return {R}("../../../pickman/tests/meta/architecture.spec")`,
				"skills/ping-arch/SKILL.md does not name itself ping-arch",
			}
		do
			t.expect(string.find(text, `\nping: {what}\n`, 1, true) ~= nil).toBe(true)
		end
		-- the deps-block check stands in for c0163's reader: only its prefix and the map's path are pinned
		t.expect(string.find(text, "\nping: ping/.tracker/architecture.md", 1, true) ~= nil).toBe(true)
		t.expect(string.find(text, "tests alias", 1, true) == nil).toBe(true) -- the one alias it has right is not reported
		t.expect(string.find(text, "selene.toml is not", 1, true) == nil).toBe(true)
		t.expect(string.find(text, "ping-test", 1, true) == nil).toBe(true)
		fs.removeDir(BASE)
	end)
end)
