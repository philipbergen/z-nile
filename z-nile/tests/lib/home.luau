--!strict
-- The home rule (c0184): what every project with code has in its home, pickman's included. A pure check over a tree on
-- disk: `problems` reads the files of the registry's projects and returns every difference, one string each. Two callers:
-- tests/lib/homespec.luau, which each home's tests/meta/home.spec.luau runs from the home it judges (so an edit to a home
-- selects its own check, zz-test lesson specs-pin-only-their-own-project), and the promoted homes.spec, which runs it on
-- fixture homes to prove the rule reads the registry and not a list of names.
local fs = require("@lune/fs")
local graph = require("../../lib/graph")
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
-- The library every place shares (c0185): its home, and the two folders a place maps from it. Every home's default place
-- maps them under ReplicatedStorage.Arcade and ServerStorage.Arcade (the library's own from inside its home), and every home's
-- .luaurc names the shared one `arcade` for its specs.
home.LIBRARY_HOME = "arcade"
local LIBRARY_HOME = home.LIBRARY_HOME
local LIBRARY_SHARED, LIBRARY_SERVER = `{LIBRARY_HOME}/src/shared`, `{LIBRARY_HOME}/src/server`

-- `path` with its "." and ".." segments applied ("snake/../arcade/src" is "arcade/src"); a ".." that climbs out stays.
local function collapse(path: string): string
	local parts: { string } = {}
	for seg in string.gmatch(path, "[^/]+") do
		if seg == ".." and #parts > 0 and parts[#parts] ~= ".." then
			table.remove(parts)
		elseif seg ~= "." then
			table.insert(parts, seg)
		end
	end
	return table.concat(parts, "/")
end

-- Where a "$path" written in a project file of home `h` points, repo-relative and collapsed; an absolute one is itself (Rojo
-- reads "/../arcade/src/shared" as "/arcade/src/shared", never as a folder of the home).
local function resolveIn(h: string, path: string): string
	return if string.sub(path, 1, 1) == "/" then path else collapse(`{h}/{path}`)
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

-- Every file Rojo reads for the project file `dir/name` (`rojo sourcemap --include-non-scripts`; the path relative to `dir`
-- and the instance path below the root node, "/"-joined), or nil and why: nil with no reason when Rojo refuses the file
-- (its build refuses it too, so nothing is read; "rojo cannot be run" is told apart by `rojo --version` in `problems`),
-- nil with a reason when its answer cannot be read (c0246: the rule then fails closed).
type Read = { file: string, instance: string }
local function rojoReads(dir: string, name: string): ({ Read }?, string?)
	local ran, res = pcall(process.exec, "rojo", { "sourcemap", "--include-non-scripts", `{dir}/{name}` })
	if not ran or not res.ok then
		return nil, nil
	end
	local decoded, map: any = pcall(serde.decode, "json" :: "json", res.stdout)
	if not decoded or type(map) ~= "table" then
		return nil, "rojo sourcemap printed no JSON"
	end
	local reads: { Read } = {}
	local function collect(node: any, path: string)
		for _, file in node.filePaths or {} do
			table.insert(reads, { file = file, instance = path })
		end
		for _, child in node.children or {} do
			collect(child, if path == "" then child.name else `{path}/{child.name}`)
		end
	end
	collect(map, "")
	return reads, nil
end

-- The real path of each of `paths`, in order; nil when any cannot be resolved.
local function realPaths(paths: { string }): { string }?
	if #paths == 0 then
		return {}
	end
	local res = process.exec("realpath", paths)
	local out: { string } = {}
	for line in string.gmatch(res.stdout, "[^\n]+") do
		table.insert(out, line)
	end
	return if res.ok and #out == #paths then out else nil
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
	-- whether Rojo can be run at all: a refused file exits non-zero, and so does a shim whose pinned Rojo is not installed
	local probe, version = pcall(process.exec, "rojo", { "--version" })
	local rojoRuns = probe and version.ok
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
				arcade = `../{LIBRARY_SHARED}`,
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
		-- the library's two folders, and the one node each may sit at
		local libraryNode =
			{ [LIBRARY_SHARED] = "ReplicatedStorage/Arcade", [LIBRARY_SERVER] = "ServerStorage/Arcade" }
		local mapped: { [string]: { graph.GameRoot } } = {} -- project file -> its mappings
		local saidNoRojo = false
		for _, name in files do
			local ok, decoded: any = pcall(serde.decode, "json" :: "json", fs.readFile(`{top}/{h}/{name}`))
			local found: { graph.GameRoot } = if ok then graph.mappings(decoded) else {}
			mapped[name] = found
			local unreadable: { graph.Unreadable } = if ok then graph.unreadable(decoded) else {}
			for _, u in unreadable do
				if u.dollar then
					bad(h, `{name} has a node named {u.instance} ({u.what}), whose mappings are not read`)
				else
					local where = if u.instance == "" then "the tree root" else `node {u.instance}`
					bad(
						h,
						`{name} has a $path that is {u.what} at {where}: only a string or \{"optional": string} is read`
					)
				end
			end
			if #found == 0 and #unreadable == 0 then
				bad(h, `{name} maps no $path`)
			end
			for _, m in found do
				local path = m.path
				local target = resolveIn(h, path)
				if not graph.insideFolder(path) and libraryNode[target] then
					-- the library's two folders are the one place a project file may map from another home, each at its node
					if m.instance ~= libraryNode[target] then
						bad(
							h,
							`{name} maps the library's {target} at {m.instance}, which is not its node ({libraryNode[target]})`
						)
					elseif not fs.isDir(`{top}/{h}/{path}`) then
						bad(h, `{name} maps $path {path}, which is no folder of the library`)
					elseif not physicallyInside(`{top}/{LIBRARY_HOME}`, `{top}/{h}/{path}`) then
						bad(h, `{name} maps $path {path}, which is a link out of the library`)
					end
				elseif not graph.insideFolder(path) then
					bad(h, `{name} maps $path {path}, which is outside the home`)
				elseif not fs.isDir(`{top}/{h}/{path}`) then
					bad(h, `{name} maps $path {path}, which is no folder of the home`)
				elseif not physicallyInside(`{top}/{h}`, `{top}/{h}/{path}`) then
					bad(h, `{name} maps $path {path}, which is a link out of the home`)
				elseif fs.isFile(`{top}/{h}/{path}/default.project.json`) then
					bad(h, `{name} maps $path {path}, a nested project (Rojo would follow its own mappings)`)
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
			-- what Rojo itself reads (c0246): the net under the readers above, which closes by construction what they model
			-- (links at any depth, project files in any casing or loaded by syncRules, a format Lune cannot decode)
			local reads, why = nil, nil
			if rojoRuns then
				reads, why = rojoReads(`{top}/{h}`, name)
			elseif not saidNoRojo then
				saidNoRojo = true
				bad(h, "rojo cannot be run (rojo --version fails), so what Rojo reads is not judged")
			end
			if why then
				bad(h, `{name}: {why}`)
			elseif reads then
				local abs: { string } = {}
				for _, r in reads do
					table.insert(abs, `{top}/{h}/{r.file}`)
				end
				local real = realPaths(abs)
				local base = realPaths({ `{top}/{h}` })
				if not real or not base then
					bad(h, `{name}: the files Rojo reads cannot be resolved`)
				else
					-- the library's two folders (by real path, when present) and the one node each may sit at
					local libs: { { root: string, node: string } } = {}
					for lib, node in libraryNode do
						local at = realPaths({ `{top}/{lib}` })
						if at then
							table.insert(libs, { root = at[1] .. "/", node = node })
						end
					end
					local outside, misplaced = 0, 0
					for i, r in reads do
						local lib: { root: string, node: string }? = nil
						for _, l in libs do
							if string.sub(real[i], 1, #l.root) == l.root then
								lib = l
							end
						end
						if lib then
							-- a library file is judged by where Rojo puts it, not only where it comes from: the server folder
							-- must never reach a client, however a link or a syncRules project got it into the place
							local at = lib.node
							if r.instance ~= at and string.sub(r.instance, 1, #at + 1) ~= at .. "/" then
								misplaced += 1
								if misplaced == 1 then
									bad(
										h,
										`{name} makes Rojo put {r.file} at {r.instance}, which is not the library's node ({at})`
									)
								end
							end
						elseif string.sub(real[i], 1, #base[1] + 1) ~= base[1] .. "/" then
							outside += 1
							if outside == 1 then
								bad(
									h,
									`{name} makes Rojo read {r.file}, which is outside the home (and the library's two folders)`
								)
							end
						end
						if
							string.match(r.file, "%.project%.jsonc?$")
							and real[i] ~= base[1] .. "/" .. name
						then
							bad(
								h,
								`{name} loads {r.file} as a nested project (Rojo would follow its own mappings)`
							)
						end
					end
				end
			end
		end
		-- the library in the default place: ReplicatedStorage.Arcade and ServerStorage.Arcade map its two folders
		for target, node in libraryNode do
			local found = false
			local defaults: { graph.GameRoot } = mapped["default.project.json"] or {}
			for _, m in defaults do
				found = found or (m.instance == node and resolveIn(h, m.path) == target)
			end
			if mapped["default.project.json"] and not found then
				bad(h, `default.project.json does not map {(string.gsub(node, "/", "."))} to {target}`)
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
		wrapper(h, "tests/lib/place.luau", { "--!strict", `return {R}("../../../z-nile/tests/lib/place")` })
		wrapper(h, "tests/place/library.spec.luau", {
			"--!strict",
			`local place = {R}("@tests/lib/place")`,
			`return {R}("../../../z-nile/tests/lib/placespec")(place)`,
		})
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
