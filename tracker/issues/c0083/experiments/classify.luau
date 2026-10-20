--!strict
-- Scratch classifier for c0083 prep (E1–E3). Not the production module: suites.spec.luau
-- requires @scripts/lib/suites, which this file is not.
local fs = require("@lune/fs")
local graph = require("@scripts/lib/graph")
local process = require("@lune/process")

local SHARED = {
	"^tests/run%.luau$",
	"^tests/lib/t%.luau$",
	"^tests/meta/",
	"^%.luaurc$",
	"^rokit%.toml$",
	"^tests/lib/fence%.luau$",
	"^scripts/lib/fence%.sh$",
	"^scripts/check%.sh$",
	"^scripts/lib/replace%-file%.pl$",
}
local HARNESS = {
	"^scripts/",
	"^tests/lib/fixture%.luau$",
	"^tests/lib/clone%.luau$",
	"^tests/lib/cachepaths%.luau$",
	"^tracker/templates/",
	"^%.claude/",
	"^selene%.toml$",
	"^stylua%.toml$",
}
local GAME = {
	"^default%.project%.json$",
	"^lobby%.project%.json$",
}
local GAME_FOLDERS = {
	"^tests/unit/",
	"^tests/contract/",
	"^tests/integration/",
	"^tests/scenario/",
	"^tests/place/",
	"^tests/runtime/",
}

local function matches(path: string, pats: { string }): boolean
	for _, pat in pats do
		if string.match(path, pat) then
			return true
		end
	end
	return false
end

local function isSpec(f: string): boolean
	return string.match(f, "%.spec%.luau$") ~= nil
end

local function of(g: graph.Graph, spec: string): string
	if string.match(spec, "^tests/meta/") then
		return "both"
	end
	if string.match(spec, "^tests/tooling/") then
		return "harness"
	end
	if matches(spec, GAME_FOLDERS) then
		return "game"
	end
	if string.match(spec, "^tests/acceptance/[fd]%d%d%d%d/") then
		return "game"
	end
	local reach = graph.closure(g, spec)
	if reach["src"] or reach[graph.PLACE_LIB] then
		return "game"
	end
	for dep in reach do
		if dep == "src" or string.sub(dep, 1, 4) == "src/" then
			return "game"
		end
	end
	return "harness"
end

local function list(g: graph.Graph, name: string): { string }
	local out: { string } = {}
	for _, f in g.files do
		if isSpec(f) then
			local side = of(g, f)
			if side == name or side == "both" then
				table.insert(out, f)
			end
		end
	end
	table.sort(out)
	return out
end

local function exists(path: string): boolean
	local ok, res = pcall(function()
		return fs.isFile(path) or fs.isDir(path)
	end)
	return ok and res == true
end

local function tokensOf(src: string): { string }
	local stripped = graph.stripComments(src)
	local raw: { string } = {}
	local i, n = 1, #stripped
	while i <= n do
		local c = string.sub(stripped, i, i)
		if c == '"' or c == "'" then
			local j = i + 1
			while j <= n do
				local d = string.sub(stripped, j, j)
				if d == "\\" then
					j += 2
				elseif d == c then
					break
				else
					j += 1
				end
			end
			table.insert(raw, string.sub(stripped, i + 1, j - 1))
			i = j + 1
		elseif c == "`" then
			local j = i + 1
			local piece: { string } = {}
			while j <= n do
				local d = string.sub(stripped, j, j)
				if d == "\\" then
					table.insert(piece, string.sub(stripped, j + 1, j + 1))
					j += 2
				elseif d == "`" then
					break
				elseif d == "{" then
					table.insert(raw, table.concat(piece))
					piece = {}
					local depth = 1
					j += 1
					while j <= n and depth > 0 do
						local e = string.sub(stripped, j, j)
						if e == "{" then
							depth += 1
						elseif e == "}" then
							depth -= 1
						end
						j += 1
					end
				else
					table.insert(piece, d)
					j += 1
				end
			end
			table.insert(raw, table.concat(piece))
			i = j + 1
		else
			i += 1
		end
	end
	local out: { string } = {}
	for _, s in raw do
		for part in string.gmatch(s, "%S+") do
			local t = part
			while string.sub(t, 1, 2) == "./" do
				t = string.sub(t, 3)
			end
			while string.sub(t, 1, 1) == "/" do
				t = string.sub(t, 2)
			end
			while string.sub(t, -1) == "/" do
				t = string.sub(t, 1, -2)
			end
			if t ~= "" and not string.find(t, "{", 1, true) then
				table.insert(out, t)
			end
		end
	end
	return out
end

type Ref = { token: string, live: boolean }
local cache: { [string]: { Ref } } = {}
local function refs(spec: string, text: string?): { Ref }
	local hit = cache[spec]
	if hit then
		return hit
	end
	local src = text or fs.readFile(spec)
	local out: { Ref } = {}
	for _, t in tokensOf(src) do
		table.insert(out, { token = t, live = exists(t) })
	end
	cache[spec] = out
	return out
end

local function textHit(specRefs: { Ref }, changed: { string }): boolean
	for _, c in changed do
		for _, r in specRefs do
			local t = r.token
			if t == c or string.sub(c, 1, #t + 1) == t .. "/" then
				return true
			end
			if r.live and (string.sub(t, 1, #c + 1) == c .. "/") then
				return true
			end
		end
	end
	return false
end

local function textAffected(g: graph.Graph, changed: { string }, extra: { [string]: string }?): { string }
	local out: { string } = {}
	for _, spec in g.files do
		if isSpec(spec) and textHit(refs(spec), changed) then
			table.insert(out, spec)
		end
	end
	if extra then
		for spec, text in extra do
			if textHit(refs(spec, text), changed) then
				table.insert(out, spec)
			end
		end
	end
	table.sort(out)
	return out
end

local function matchesList(changed: { string }, pats: { string }): boolean
	for _, f in changed do
		if matches(f, pats) then
			return true
		end
	end
	return false
end

local function select(g: graph.Graph, changed: { string }): { string } | "ALL"
	for _, f in changed do
		if matches(f, SHARED) then
			return "ALL"
		end
	end
	local set: { [string]: boolean } = {}
	for _, s in graph.affectedSpecs(g, changed, isSpec) do
		set[s] = true
	end
	for _, s in textAffected(g, changed) do
		set[s] = true
	end
	if matchesList(changed, HARNESS) then
		for _, s in list(g, "harness") do
			set[s] = true
		end
	end
	if matchesList(changed, GAME) then
		for _, s in list(g, "game") do
			set[s] = true
		end
	end
	local out: { string } = {}
	for s in set do
		table.insert(out, s)
	end
	table.sort(out)
	return out
end

local function sideOf(g: graph.Graph, path: string): { string }
	local function add(set: { [string]: boolean }, side: string)
		if side == "both" then
			set.harness = true
			set.game = true
		else
			set[side] = true
		end
	end
	local set: { [string]: boolean } = {}
	local promoted = string.match(path, "^tracker/issues/.*/(f%d%d%d%d)/acceptance/(.+)$")
		or string.match(path, "^tracker/issues/.*/(d%d%d%d%d)/acceptance/(.+)$")
		or string.match(path, "^tracker/issues/.*/(c%d%d%d%d)/acceptance/(.+)$")
	if isSpec(path) or promoted then
		local as = if promoted then `tests/acceptance/{promoted}/{string.match(path, "([^/]+)$")}` else path
		if fs.isFile(path) and string.match(as, "^tests/acceptance/c") then
			-- a chore spec: classify the real file's closure by reading it as if promoted
			local fake = table.clone(g)
			local files = table.clone(g.files)
			table.insert(files, path)
			local deps = table.clone(g.deps)
			deps[path] = {}
			local src = graph.stripComments(fs.readFile(path))
			for spec in string.gmatch(src, graph.REQUIRE_PATTERN) do
				local target = graph.resolve(path, spec)
				if target then
					table.insert(deps[path], target)
				end
			end
			fake = { files = files, deps = deps, unresolved = g.unresolved, dynamic = g.dynamic }
			add(set, of(fake :: any, path))
		else
			add(set, of(g, as))
		end
	elseif matches(path, SHARED) then
		add(set, "both")
	elseif
		matches(path, GAME)
		or string.sub(path, 1, 4) == "src/"
		or matches(path, GAME_FOLDERS)
		or string.match(path, "^tests/acceptance/[fd]%d%d%d%d/")
	then
		add(set, "game")
	elseif matches(path, HARNESS) then
		add(set, "harness")
	else
		local picked = select(g, { path })
		if picked == "ALL" then
			add(set, "both")
		else
			for _, spec in picked :: { string } do
				add(set, of(g, spec))
			end
		end
	end
	local out: { string } = {}
	if set.harness then
		table.insert(out, "harness")
	end
	if set.game then
		table.insert(out, "game")
	end
	return out
end

local g = graph.build({ "src", "tests" })
local harness = list(g, "harness")
local game = list(g, "game")
local both = 0
local uncovered: { string } = {}
local hset: { [string]: boolean } = {}
local gset: { [string]: boolean } = {}
for _, s in harness do
	hset[s] = true
end
for _, s in game do
	gset[s] = true
end
for _, f in g.files do
	if isSpec(f) then
		if hset[f] and gset[f] then
			both += 1
		end
		if not hset[f] and not gset[f] then
			table.insert(uncovered, f)
		end
	end
end
print(`E1 harness={#harness} game={#game} both={both} uncovered={#uncovered}`)
for _, u in uncovered do
	print("  uncovered " .. u)
end

local function show(label: string, changed: { string })
	local t0 = os.clock()
	local r = select(g, changed)
	local dt = os.clock() - t0
	if r == "ALL" then
		print(`E2 {label} -> ALL ({string.format("%.3f", dt)}s)`)
		return
	end
	local listR = r :: { string }
	local nh, ng, nb = 0, 0, 0
	for _, s in listR do
		local side = of(g, s)
		if side == "harness" then
			nh += 1
		elseif side == "game" then
			ng += 1
		else
			nb += 1
		end
	end
	print(`E2 {label} -> {#listR} (harness {nh}, game {ng}, both {nb}) ({string.format("%.3f", dt)}s)`)
end

show("tracker script", { "scripts/tracker/main.luau" })
show("game init", { "src/shared/Logic/Game/init.luau" })
show("smoke spec", { "tests/unit/smoke.spec.luau" })
show("run.luau", { "tests/run.luau" })
show("check.sh", { "scripts/check.sh" })
show("project", { "default.project.json" })
show("lobby project", { "lobby.project.json" })
show("skill", { ".claude/skills/ticket-prep/SKILL.md" })
show("template", { "tracker/templates/prompt.md" })
show("workflow", { ".github/workflows/check.yml" })
show("SETUP", { "SETUP.md" })
show("done check", { "tracker/issues/done/c0008/check.sh" })
show("game-design", { "tracker/game-design.md" })
show("fence", { "tests/lib/fence.luau" })
show("no such", { "no-such-top-level-file.md" })

local function which(path: string)
	print(`which {path} -> {table.concat(sideOf(g, path), ",")}`)
end
which("scripts/tracker/main.luau")
which("src/shared/Logic/Game/init.luau")
which("tests/lib/fence.luau")
which("tests/acceptance/c0041/place-game.spec.luau")
which("tracker/game-design.md")
which("tests/unit/smoke.spec.luau")
which("default.project.json")

-- deleted-path self-check (the spec's stand-in reader)
local text = 'local text = "gone/deleted-doc.md"\nlocal folder = `{root}/gone-folder/sub`\n'
local function syn(changed: string): number
	local n = 0
	if textHit(refs("reader.spec.luau", text), { changed }) then
		n = 1
	end
	return n
end
print(
	`deleted doc {syn("gone/deleted-doc.md")} folder {syn("gone-folder/sub/file.luau")} other {syn(
		"gone/other.md"
	)}`
)

-- harness specs selected by a src change, beyond the game suite
local srcSel = select(g, { "src/shared/Logic/Game/init.luau" })
if srcSel ~= "ALL" then
	local n = 0
	for _, s in srcSel :: { string } do
		if of(g, s) == "harness" then
			n += 1
			print("  src-names " .. s)
		end
	end
	print(`src change harness-only extras: {n}`)
end

local proj = select(g, { "default.project.json" })
if proj ~= "ALL" then
	local n = 0
	for _, s in proj :: { string } do
		if of(g, s) == "harness" then
			n += 1
			print("  project-names " .. s)
		end
	end
	print(`project change harness-only extras: {n}`)
end

local lobby = select(g, { "lobby.project.json" })
if lobby ~= "ALL" then
	local n = 0
	for _, s in lobby :: { string } do
		if of(g, s) == "harness" then
			n += 1
			print("  lobby-names " .. s)
		end
	end
	print(`lobby change harness-only extras: {n}`)
end

-- of() spot checks
local spots = {
	"tests/meta/architecture.spec.luau",
	"tests/tooling/affected.spec.luau",
	"tests/unit/smoke.spec.luau",
	"tests/unit/Pellets/pellets.spec.luau",
	"tests/acceptance/f0054/docs.spec.luau",
	"tests/acceptance/c0008/done-order.spec.luau",
	"tests/acceptance/c0002/affected-place.spec.luau",
	"tests/acceptance/c0041/place-game.spec.luau",
	"tests/tooling/board.spec.luau",
}
for _, s in spots do
	print(`of {s} = {of(g, s)} exists={fs.isFile(s)}`)
end

local named = {
	{ ".github/workflows/check.yml", "tests/acceptance/c0001/ci-workflow.spec.luau" },
	{ "SETUP.md", "tests/acceptance/c0015/docs.spec.luau" },
	{ "tracker/issues/done/c0008/check.sh", "tests/tooling/repo-fence.spec.luau" },
	{ "tests/unit/smoke.spec.luau", "tests/tooling/repo-fence.spec.luau" },
	{ "tests/unit/smoke.spec.luau", "tests/acceptance/c0049/spec-isolation.spec.luau" },
}
for _, c in named do
	local r = select(g, { c[1] })
	local hit = false
	if r ~= "ALL" then
		hit = table.find(r :: { string }, c[2]) ~= nil
	else
		hit = true
	end
	print(`text {c[1]} -> {c[2]}: {hit}`)
end

local function why(changed: string, limit: number)
	local n = 0
	for _, spec in g.files do
		if isSpec(spec) and of(g, spec) == "game" and textHit(refs(spec), { changed }) then
			local shortest = ""
			for _, r in refs(spec) do
				local t = r.token
				if t == changed or string.sub(changed, 1, #t + 1) == t .. "/" then
					if shortest == "" or #t < #shortest then
						shortest = t
					end
				end
			end
			print(`  game-reader {spec} via {shortest}`)
			n += 1
			if n >= limit then
				break
			end
		end
	end
end
why("scripts/tracker/main.luau", 10)
why("tracker/game-design.md", 5)

local shortestCounts: { [string]: number } = {}
for _, spec in g.files do
	if isSpec(spec) and textHit(refs(spec), { "tracker/issues/done/c0008/check.sh" }) then
		local shortest = ""
		for _, r in refs(spec) do
			local t = r.token
			local c = "tracker/issues/done/c0008/check.sh"
			if t == c or string.sub(c, 1, #t + 1) == t .. "/" then
				if shortest == "" or #t < #shortest then
					shortest = t
				end
			end
		end
		shortestCounts[shortest] = (shortestCounts[shortest] or 0) + 1
	end
end
for token, n in shortestCounts do
	print(`done-check token {token} -> {n}`)
end

fs.writeFile(".cache/c0083-harness-specs.txt", table.concat(harness, "\n") .. "\n")
print("done")
_ = process
