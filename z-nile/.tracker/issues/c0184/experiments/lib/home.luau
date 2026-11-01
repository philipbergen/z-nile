--!strict
-- The home rule (c0184): what every project with code has in its home, pickman's included. A pure check over a tree on
-- disk: `problems` reads the files of the registry's projects and returns every difference, one string each. Two callers:
-- tests/lib/homespec.luau, which each home's tests/meta/home.spec.luau runs from the home it judges (so an edit to a home
-- selects its own check, zz-test lesson specs-pin-only-their-own-project), and the promoted homes.spec, which runs it on
-- fixture homes to prove the rule reads the registry and not a list of names.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local home = {}

-- The registry as this rule needs it (z-nile/engine/projects.luau's `Registry`, structurally): no engine file is
-- required, because c0120 keeps a z-nile engine change from selecting any other project's specs, and each home runs
-- this rule from its own folder.
export type Project = { name: string, root: string, home: string }
export type Registry = { projects: { Project } }

-- The `name:` of a SKILL.md's frontmatter, or nil (the reader of skill folders is engine/skills.luau, which the engine's
-- own specs run; a name that differs from the folder's is also refused by `./zn skills --check`).
local function frontName(text: string): string?
	local front = string.match(text, "^%-%-%-\n(.-)\n%-%-%-")
	if not front then
		return nil
	end
	for line in string.gmatch(front, "[^\n]+") do
		local v = string.match(line, "^name:%s*(.-)%s*$")
		if v then
			return v
		end
	end
	return nil
end

local R = "req" .. "uire" -- keeps literal require text out of this file (the graph scanner)
-- The home whose tests/meta/architecture.spec.luau holds the structural rules; every other home runs it from its folder.
home.RULES_HOME = "pickman"
local RULES_HOME = home.RULES_HOME

-- Whether `path`, relative to a home, stays inside it once its `..` and `.` segments are applied.
local function inside(path: string): boolean
	local depth = 0
	for seg in string.gmatch(path, "[^/]+") do
		if seg == ".." then
			depth -= 1
			if depth < 0 then
				return false
			end
		elseif seg ~= "." then
			depth += 1
		end
	end
	return true
end

-- Whether `folder`, with its links followed, lies under `root`, with its links followed.
local function physicallyInside(root: string, folder: string): boolean
	local a, b = process.exec("realpath", { root }), process.exec("realpath", { folder })
	if not a.ok or not b.ok then
		return false
	end
	local rootPath = string.gsub(a.stdout, "%s+$", "") .. "/"
	return string.sub(string.gsub(b.stdout, "%s+$", "") .. "/", 1, #rootPath) == rootPath
end

local function read(path: string): string?
	if fs.isFile(path) then
		return fs.readFile(path)
	end
	return nil
end

-- Every way the homes of `reg` (a registry whose tree is at `top`) differ from the scaffold, one string each, and the
-- names of the projects it checked: all of them but z-nile (the tooling, whose home holds the engine), or `only` that one.
function home.problems(top: string, reg: Registry, only: string?): ({ string }, { string })
	local out: { string } = {}
	local checked: { string } = {}
	local function bad(owner: string, what: string)
		table.insert(out, `{owner}: {what}`)
	end
	local function has(owner: string, rel: string, needle: string)
		local text = read(`{top}/{owner}/{rel}`)
		if not text then
			bad(owner, `missing {rel}`)
		elseif not string.find(text, needle, 1, true) then
			bad(owner, `{rel} lacks {needle}`)
		end
	end
	-- A wrapper is what is left once its comment and blank lines are gone (`--!strict` stays): exactly `lines`, so a
	-- require kept in a comment, or after an early return, is no wrapper (review 002 F3)
	local function wrapper(owner: string, rel: string, lines: { string })
		local text = read(`{top}/{owner}/{rel}`)
		if not text then
			bad(owner, `missing {rel}`)
			return
		end
		local kept: { string } = {}
		for l in string.gmatch(text, "[^\n]+") do
			if not string.match(l, "^%s*$") and (l == "--!strict" or not string.match(l, "^%s*%-%-")) then
				table.insert(kept, l)
			end
		end
		if table.concat(kept, "\n") ~= table.concat(lines, "\n") then
			bad(owner, `{rel} is not exactly: {table.concat(lines, " / ")}`)
		end
	end
	local function paths(node: any, into: { string })
		if type(node) ~= "table" then
			return
		end
		for key, value in node :: { [string]: any } do
			if key == "$path" and type(value) == "string" then
				table.insert(into, value)
			else
				paths(value, into)
			end
		end
	end
	for _, p in reg.projects do
		if p.name == "z-nile" or p.home == "." or (only and p.name ~= only) then
			continue
		end
		local h = p.home
		table.insert(checked, p.name)
		-- the gate
		has(h, "check.sh", `exec bash "$(dirname "$0")/../z-nile/check.sh" --project {p.name} "$@"`)
		if
			fs.isFile(`{top}/{h}/check.sh`) and not process.exec("test", { "-x", `{top}/{h}/check.sh` }).ok
		then
			bad(h, "check.sh is not executable")
		end
		-- the aliases and the root's formatter and linter configuration
		local luaurc = read(`{top}/{h}/.luaurc`)
		if not luaurc then
			bad(h, "missing .luaurc")
		else
			local cfg: any = serde.decode("json", luaurc)
			local want = {
				logic = "./src/shared/Logic",
				shared = "./src/shared",
				tests = "./tests",
				znile = "../z-nile",
			}
			for alias, target in want do
				if not cfg.aliases or cfg.aliases[alias] ~= target then
					bad(h, `.luaurc alias {alias} is not {target}`)
				end
			end
			if cfg.languageMode ~= "strict" then
				bad(h, ".luaurc is not strict")
			end
		end
		for _, file in { "stylua.toml", "selene.toml" } do
			local own, root = read(`{top}/{h}/{file}`), read(`{top}/{file}`)
			if own == nil then
				bad(h, `missing {file}`)
			elseif own ~= root then
				bad(h, `{file} is not the root's`)
			end
		end
		-- the places: a default one, and every $path of every project file a folder of the home
		local files: { string } = {}
		if fs.isDir(`{top}/{h}`) then
			for _, name in fs.readDir(`{top}/{h}`) do
				if string.match(name, "%.project%.json$") then
					table.insert(files, name)
				end
			end
		end
		if not table.find(files, "default.project.json") then
			bad(h, "missing default.project.json")
		end
		for _, name in files do
			local found: { string } = {}
			paths(serde.decode("json", fs.readFile(`{top}/{h}/{name}`)), found)
			if #found == 0 then
				bad(h, `{name} maps no $path`)
			end
			for _, path in found do
				if not inside(path) then
					bad(h, `{name} maps $path {path}, which is outside the home`)
				elseif not fs.isDir(`{top}/{h}/{path}`) then
					bad(h, `{name} maps $path {path}, which is no folder of the home`)
				elseif not physicallyInside(`{top}/{h}`, `{top}/{h}/{path}`) then
					bad(h, `{name} maps $path {path}, which is a link out of the home`)
				else
					-- a link inside the mapped folder that leaves the home is followed by Rojo too
					local links = process.exec("find", { `{top}/{h}/{path}`, "-type", "l" })
					for link in string.gmatch(links.stdout, "[^\n]+") do
						if not physicallyInside(`{top}/{h}`, link) then
							bad(h, `{name} maps $path {path}, which holds a link out of the home`)
							break
						end
					end
				end
			end
		end
		for _, dir in { "src/shared/Logic", "src/server" } do
			if not fs.isDir(`{top}/{h}/{dir}`) then
				bad(h, `missing {dir}`)
			end
		end
		-- the specs' side: the shared runner and the re-exports, and the two meta specs
		wrapper(h, "tests/run.luau", { "--!strict", `return {R}("../../z-nile/tests/run")` })
		wrapper(h, "tests/lib/t.luau", {
			"--!strict",
			`local t = {R}("../../../z-nile/tests/lib/t")`,
			"export type Case = t.Case",
			"export type Spec = t.Spec",
			"return t",
		})
		wrapper(
			h,
			"tests/lib/renamed.luau",
			{ "--!strict", `return {R}("../../../z-nile/tests/lib/renamed")` }
		)
		wrapper(
			h,
			"tests/meta/fence.spec.luau",
			{ "--!strict", `return {R}("../../../z-nile/tests/tooling/repo-fence.spec")` }
		)
		wrapper(
			h,
			"tests/meta/home.spec.luau",
			{ "--!strict", `return {R}("../../../z-nile/tests/lib/homespec")` }
		)
		if p.name == RULES_HOME then
			has(h, "tests/meta/architecture.spec.luau", 't.spec("architecture"')
		else
			wrapper(h, "tests/meta/architecture.spec.luau", {
				"--!strict",
				`return {R}("../../../{RULES_HOME}/tests/meta/architecture.spec")`,
			})
		end
		-- the skills, and the architecture map in the root
		for _, kind in { "arch", "test" } do
			local name = `{p.name}-{kind}`
			local text = read(`{top}/{h}/skills/{name}/SKILL.md`)
			if not text then
				bad(h, `missing skills/{name}/SKILL.md`)
			elseif frontName(text) ~= name then
				bad(h, `skills/{name}/SKILL.md does not name itself {name}`)
			end
		end
		-- the root's architecture map holds exactly one closed deps block, which pickman's meta spec reads: a map
		-- without one is an error to the fail-closed reader (c0163)
		local map = read(`{top}/{p.root}/architecture.md`)
		if not map then
			bad(h, `missing {p.root}/architecture.md`)
		else
			local text = "\n" .. map
			local _, opened = string.gsub(text, "\n```deps\n", "")
			local _, closed = string.gsub(text, "\n```deps\n.-\n```", "")
			if opened == 0 then
				bad(h, `{p.root}/architecture.md has no deps block`)
			elseif opened > 1 then
				bad(h, `{p.root}/architecture.md has {opened} deps blocks`)
			elseif closed == 0 then
				bad(h, `{p.root}/architecture.md has a deps block that is not closed`)
			end
		end
	end
	return out, checked
end

return home
