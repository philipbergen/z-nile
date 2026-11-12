--!strict
-- The watch map. A watch file is plain text: one repository-relative path per line, sorted, no duplicates,
-- no comments. A ticket's file is `<home>/tests/acceptance/<id>/watch.txt` and covers every spec directly in
-- that folder. Every other spec has `<name>.watch.txt` beside `<name>.spec.luau`. Pure: texts in, texts out.
-- The command line and this file format are the contract (the Python port reads the same bytes).

local watch = {}

export type Binding = { spec: string, watch: string, paths: { string } }
export type Commit = { message: string, files: { string } }
export type Reader = {
	isDir: (string) -> boolean,
	isFile: (string) -> boolean,
	readDir: (string) -> { string },
	readFile: (string) -> string,
}

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

function watch.isWatch(path: string): boolean
	return path == "watch.txt"
		or string.sub(path, -10) == ".watch.txt"
		or string.sub(path, -10) == "/watch.txt"
end

-- The watch file that covers `spec` (a repository-relative `*.spec.luau` path).
function watch.fileFor(spec: string): string
	local dir = string.match(spec, "^(.-/tests/acceptance/[^/]+)/%S+%.spec%.luau$")
		or string.match(spec, "^(tests/acceptance/[^/]+)/%S+%.spec%.luau$")
	if dir then
		return `{dir}/watch.txt`
	end
	if string.sub(spec, -10) == ".spec.luau" then
		return string.sub(spec, 1, #spec - 10) .. ".watch.txt"
	end
	return spec .. ".watch.txt"
end

-- A source file a watch list may name. Tracker documents, documentation, skills and lessons are not.
-- A spec and a watch file are not. Every other file under tests/ is: helpers, the runner, fixtures.
function watch.isSource(path: string): boolean
	if path == "" or string.sub(path, 1, 1) == "/" then
		return false
	end
	if string.find(path, "/.tracker/", 1, true) or string.sub(path, 1, 9) == ".tracker/" then
		return false
	end
	if string.sub(path, -3) == ".md" then
		return false
	end
	if string.find(path, "/skills/", 1, true) or string.sub(path, 1, 7) == "skills/" then
		return false
	end
	if string.find(path, "/lessons/", 1, true) or string.sub(path, 1, 8) == "lessons/" then
		return false
	end
	if string.sub(path, -10) == ".spec.luau" or watch.isWatch(path) then
		return false
	end
	if path == "z-nile/next" or path == "z-nile/compaction.txt" or path == "z-nile/watch-passed" then
		return false
	end
	return true
end

-- Files every run depends on and no spec requires. A spec whose text names one watches it.
-- A change to one of them runs those specs, never every spec.
function watch.sharedPins(): { string }
	return {
		"z-nile/tests/run.luau",
		"z-nile/check.sh",
		"zn",
		"rokit.toml",
		"stylua.toml",
		"selene.toml",
	}
end

local GAME_HOME: { [string]: boolean } = {
	arcade = true,
	pickman = true,
	portal = true,
	snake = true,
	invaders = true,
	asteroids = true,
}

-- A tooling spec keeps tooling paths. A game or library spec keeps game and library paths.
-- A squash that touched both suites does not bind one suite's specs to the other's files.
function watch.forSuite(spec: string, paths: { string }): { string }
	local tooling = string.sub(spec, 1, 7) == "z-nile/" or string.sub(spec, 1, 6) == "tests/"
	local out: { string } = {}
	for _, p in paths do
		local home = string.match(p, "^([^/]+)/") or ""
		local keep = if tooling
			then home == "" or home == "z-nile" or home == "scripts" or string.sub(p, 1, 8) == ".github/"
			else GAME_HOME[home] == true
		if keep then
			table.insert(out, p)
		end
	end
	return watch.unique(out)
end

function watch.sourceOf(paths: { string }): { string }
	local out: { string } = {}
	for _, p in paths do
		if watch.isSource(p) then
			table.insert(out, p)
		end
	end
	return watch.unique(out)
end

function watch.unique(paths: { string }): { string }
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	for _, p in paths do
		if not seen[p] then
			seen[p] = true
			table.insert(out, p)
		end
	end
	table.sort(out)
	return out
end

function watch.render(paths: { string }): string
	local list = watch.unique(paths)
	if #list == 0 then
		return ""
	end
	return table.concat(list, "\n") .. "\n"
end

-- nil and a reason when the text is not a watch file. An empty text is an empty list.
function watch.parse(text: string): ({ string }?, string?)
	local out: { string } = {}
	local prev = ""
	local n = 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		n += 1
		if line ~= "" then
			if line ~= trim(line) or string.find(line, "%s") then
				return nil, `line {n}: a path has whitespace`
			end
			if string.sub(line, 1, 1) == "#" or string.sub(line, 1, 1) == "/" then
				return nil, `line {n}: {line} is not a repository-relative path`
			end
			for comp in string.gmatch(line, "[^/]+") do
				if comp == ".." or comp == "." then
					return nil, `line {n}: {line} contains {comp}`
				end
			end
			if string.sub(line, -1) == "/" then
				return nil, `line {n}: {line} is a directory`
			end
			if prev ~= "" and line == prev then
				return nil, `line {n}: {line} is duplicated`
			end
			if prev ~= "" and line < prev then
				return nil, `line {n}: {line} is out of order`
			end
			prev = line
			table.insert(out, line)
		end
	end
	return out, nil
end

-- Specs whose watch file names a changed path, plus specs the change adds or edits, plus `current`.
function watch.select(bindings: { Binding }, changed: { string }, current: { string }?): { string }
	local set: { [string]: boolean } = {}
	for _, p in changed do
		set[p] = true
	end
	local have: { [string]: boolean } = {}
	local out: { string } = {}
	local function add(spec: string)
		if not have[spec] then
			have[spec] = true
			table.insert(out, spec)
		end
	end
	for _, b in bindings do
		local hit = set[b.spec] == true or set[b.watch] == true
		if not hit then
			for _, p in b.paths do
				if set[p] then
					hit = true
					break
				end
			end
		end
		if hit then
			add(b.spec)
		end
	end
	for _, p in changed do
		if string.sub(p, -10) == ".spec.luau" then
			add(p)
		end
	end
	local extra: { string } = current or {}
	for _, p in extra do
		add(p)
	end
	table.sort(out)
	return out
end

-- `renames[old] = new`. A path in `deletes` is dropped. The result is sorted and unique.
function watch.rewrite(
	paths: { string },
	renames: { [string]: string },
	deletes: { [string]: boolean }
): { string }
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	for _, p in paths do
		if not deletes[p] then
			local nextp = renames[p] or p
			if not seen[nextp] then
				seen[nextp] = true
				table.insert(out, nextp)
			end
		end
	end
	table.sort(out)
	return out
end

function watch.missing(paths: { string }, exists: (string) -> boolean): { string }
	local out: { string } = {}
	for _, p in paths do
		if not exists(p) then
			table.insert(out, p)
		end
	end
	return out
end

-- Issue ids on `Issue:` trailers, in order. A raft id counts too.
function watch.issueIds(message: string): { string }
	local out: { string } = {}
	for line in string.gmatch(message, "[^\n]+") do
		local id = string.match(line, "^Issue: ([fdcR]%d%d%d%d)$")
			or string.match(line, "^Issue: ([fdcR]%d%d%d%d)%s")
		if id then
			table.insert(out, id)
		end
	end
	return out
end

-- One list of source files per member. `shared` is true when a commit that changed a source file does not
-- name exactly one of `members`: every member then gets that whole source list.
function watch.assign(commits: { Commit }, members: { string }): ({ [string]: { string } }, boolean)
	local member: { [string]: boolean } = {}
	for _, id in members do
		member[id] = true
	end
	local per: { [string]: { string } } = {}
	for _, id in members do
		per[id] = {}
	end
	local all: { string } = {}
	local shared = false
	for _, c in commits do
		local sources = watch.sourceOf(c.files)
		if #sources > 0 then
			for _, f in sources do
				table.insert(all, f)
			end
			local ids = watch.issueIds(c.message)
			if #ids ~= 1 or not member[ids[1]] then
				shared = true
			elseif not shared then
				for _, f in sources do
					table.insert(per[ids[1]], f)
				end
			end
		end
	end
	local whole = watch.unique(all)
	if shared then
		for _, id in members do
			per[id] = whole
		end
	else
		for _, id in members do
			per[id] = watch.unique(per[id])
		end
	end
	return per, shared
end

-- `git log --name-only --pretty=format:---COMMIT---%n%B%n---FILES---`
function watch.parseLog(text: string): { Commit }
	local out: { Commit } = {}
	local parts = string.split(text, "---COMMIT---\n")
	for i = 2, #parts do
		local message, rest = string.match(parts[i], "^(.-)\n---FILES---\n(.*)$")
		if message then
			local files: { string } = {}
			for line in string.gmatch(rest or "", "[^\n]+") do
				if not string.find(line, "^---", 1) then
					table.insert(files, line)
				end
			end
			table.insert(out, { message = message, files = files })
		end
	end
	return out
end

function watch.requirePaths(text: string): { string }
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	local function add(s: string)
		if not seen[s] then
			seen[s] = true
			table.insert(out, s)
		end
	end
	for s in string.gmatch(text, 'require%s*%(%s*"([^"]+)"') do
		add(s)
	end
	for s in string.gmatch(text, "require%s*%(%s*'([^']+)'") do
		add(s)
	end
	for s in string.gmatch(text, "require%s*%(%s*`([^`]+)`") do
		add(s)
	end
	return out
end

-- Quoted strings that look like repository paths and are source files.
function watch.pathLiterals(text: string): { string }
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	for s in string.gmatch(text, '"([^"\n]+)"') do
		if string.find(s, "/", 1, true) and watch.isSource(s) and not seen[s] then
			seen[s] = true
			table.insert(out, s)
		end
	end
	return out
end

function watch.failingSpecs(text: string): { string }
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	for line in string.gmatch(text, "[^\n]+") do
		local path = string.match(line, "^FAIL%s+(%S+%.spec%.luau)")
		if path and not seen[path] then
			seen[path] = true
			table.insert(out, path)
		end
	end
	table.sort(out)
	return out
end

local function bind(
	watches: { [string]: { string } },
	problems: { string },
	file: string,
	specs: { string },
	reader: Reader
)
	local paths, err = watch.parse(reader.readFile(file))
	if not paths then
		table.insert(problems, `{file}: {err}`)
		return
	end
	if #paths == 0 then
		table.insert(problems, `{file} is empty`)
	end
	for _, p in paths do
		if not reader.isFile(p) then
			table.insert(problems, `{file}: {p} does not exist`)
		end
	end
	for _, spec in specs do
		watches[spec] = paths
	end
end

local function walk(
	reader: Reader,
	dir: string,
	watches: { [string]: { string } },
	problems: { string },
	seen: { string }
)
	if not reader.isDir(dir) then
		return
	end
	local names = reader.readDir(dir)
	table.sort(names)
	local folder = `{dir}/watch.txt`
	local acceptance = string.match(dir, "/tests/acceptance/[^/]+$")
		or string.match(dir, "^tests/acceptance/[^/]+$")
	if acceptance and reader.isFile(folder) then
		local specs: { string } = {}
		for _, name in names do
			if string.sub(name, -10) == ".spec.luau" then
				table.insert(specs, `{dir}/{name}`)
			end
		end
		bind(watches, problems, folder, specs, reader)
		return
	end
	for _, name in names do
		local child = `{dir}/{name}`
		if reader.isDir(child) then
			walk(reader, child, watches, problems, seen)
		elseif string.sub(name, -10) == ".spec.luau" then
			table.insert(seen, child)
		elseif string.sub(name, -10) == ".watch.txt" then
			local spec = string.sub(child, 1, #child - 10) .. ".spec.luau"
			if reader.isFile(spec) then
				bind(watches, problems, child, { spec }, reader)
			end
		end
	end
end

-- Watch bindings under one home (`prefix` is "" or "pickman/"), and every problem in those files.
-- A spec with no watch file, and a watch file with an empty list, are problems: the path is named.
function watch.collect(reader: Reader, prefix: string): ({ [string]: { string } }, { string })
	local watches: { [string]: { string } } = {}
	local problems: { string } = {}
	local seen: { string } = {}
	walk(reader, `{prefix}tests`, watches, problems, seen)
	for _, spec in seen do
		if watches[spec] == nil then
			table.insert(problems, `{spec} has no watch file`)
		end
	end
	return watches, problems
end

return watch
