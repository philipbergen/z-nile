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

-- The main checkout's root: `git worktree list --porcelain` names it first, even when asked from a linked worktree.
function watch.mainCheckout(porcelain: string): string?
	return string.match(porcelain, "^worktree ([^\n]+)")
end

-- Where the net runs: one standing worktree in the main checkout, whichever worktree started it.
function watch.netDir(main: string): string
	return `{main}/.worktree/watch-net`
end

-- The net's files: one folder in the main checkout, so a log outlives the worktree that kicked the net (d0383 F7).
function watch.filesDir(main: string): string
	return `{main}/.cache/watch-net`
end

-- One kick's files, named by its id so no kick reads or truncates another's (F6): the log of the net, the marker it
-- writes when it has its worktree, and the exit code its shell writes when it ends.
export type KickFiles = { id: string, log: string, ready: string, exit: string }
function watch.kickFiles(dir: string, epoch: number, pid: number): KickFiles
	local id = string.format("%010d-%d", epoch, pid)
	return { id = id, log = `{dir}/{id}.log`, ready = `{dir}/{id}.ready`, exit = `{dir}/{id}.exit` }
end

-- The files (names in the folder) of every kick but the newest `keep`: ids start with the zero-padded epoch, so a plain
-- sort is oldest first. Names that are not a kick's file are never listed.
function watch.pruneKicks(names: { string }, keep: number): { string }
	local ids: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, name in names do
		local id = string.match(name, "^(%d+%-%d+)%.%a+$")
		if id and not seen[id] then
			seen[id] = true
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	local drop: { [string]: boolean } = {}
	for i = 1, #ids - keep do
		drop[ids[i]] = true
	end
	local out: { string } = {}
	for _, name in names do
		local id = string.match(name, "^(%d+%-%d+)%.%a+$")
		if id and drop[id] then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

-- The newest pass commit in `log` (lines of "<committer epoch>\t<sha>\t<subject>", newest first) whose subject is
-- exactly the net's pass commit: its committer time and sha; nil when none is.
function watch.lastPass(log: string): (number?, string?)
	for line in string.gmatch(log, "[^\n]+") do
		local at, sha, subject = string.match(line, "^(%d+)\t(%x+)\t(.*)$")
		if at and subject == "watch-net: the suite passed" then
			return tonumber(at), sha
		end
	end
	return nil, nil
end

-- The committer time of the newest commit in `log` that changes something outside the tracker (d0383 F8, the user's
-- ruling). `log` is `git log --format=%x01%ct --name-only` (`-m --first-parent`, so a merge shows its changes), newest
-- first: a line starting with \1 opens a commit, the lines under it are its paths. `tracker` says whether a path is
-- tracker state (`trackerstate.under` over the registry's roots, the one reader). nil when no commit changes anything else.
function watch.newestSource(log: string, tracker: (path: string) -> boolean): number?
	local at: number? = nil
	for line in string.gmatch(log, "[^\n]+") do
		local stamp = string.match(line, "^\1(%d+)$")
		if stamp then
			at = tonumber(stamp)
		elseif at ~= nil and not tracker(line) then
			return at
		end
	end
	return nil
end

-- "watch-net: no pass since <UTC date of the pass commit>" when the newest source commit is more than `limit` seconds
-- newer than the last pass commit; nil when it is not, or when either time is unknown (no pass recorded yet, or no
-- source commit after it).
function watch.noPassLine(passed: number?, newest: number?, limit: number): string?
	if passed == nil or newest == nil or newest - passed <= limit then
		return nil
	end
	return `watch-net: no pass since {os.date("!%Y-%m-%d", passed)}`
end

-- The last non-empty line of a log: where the net says why it stopped.
function watch.errorLine(log: string): string?
	local last: string? = nil
	for line in string.gmatch(log, "[^\n]+") do
		if string.match(line, "%S") then
			last = line
		end
	end
	return last
end

-- A flag's value in seconds: `given` when it is a positive whole number, else nil, and the caller uses its default
-- (`--wait -5`, `--wait abc` and `--wait 0` are the default, never a loop of no steps).
function watch.waitSeconds(given: string?): number?
	local n = if given and string.match(given, "^%d+$") then tonumber(given) else nil
	return if n and n > 0 then n else nil
end

-- What the kick knows about the net it started, from what it can see: the net's marker (wins over everything: the net
-- had its worktree), the exit code its shell wrote, and whether its shell still runs. "gone" is a shell that ended
-- with neither file: killed.
function watch.startState(
	ready: boolean,
	code: number?,
	alive: boolean
): "ready" | "exited" | "gone" | "waiting"
	if ready then
		return "ready"
	elseif code ~= nil then
		return "exited"
	elseif not alive then
		return "gone"
	end
	return "waiting"
end

-- The line a net prints, and the kick passes on as its own, when another net holds the lock.
watch.ALREADY = "watch-net: already running"

-- The lock's text: the holder's pid and its start id (the kernel's start record, lib/procstart), which tells the holder
-- from a later process that reused the pid.
function watch.lockText(pid: number, start: string): string
	return `{pid} {start}\n`
end

function watch.parseLock(text: string): { pid: number, start: string }?
	local pid, start = string.match(text, "^(%d+) ([^\n]+)\n?$")
	if pid == nil or start == nil then
		return nil
	end
	return { pid = tonumber(pid) :: number, start = start }
end

-- Whether the lock still holds: its holder runs (`liveStart` is the start id of that pid now, nil when no process has
-- it) with the same start id. A lock that does not parse holds nothing, so it is taken over rather than left to block
-- every net: the net writes the lock with a plain write under the guard, and a net killed in the middle of it can leave
-- a torn file (G7).
function watch.lockHeld(text: string, liveStart: string?): boolean
	local lock = watch.parseLock(text)
	return lock ~= nil and liveStart ~= nil and liveStart == lock.start
end

-- The refusal line of a kick made inside a dispatched step (`ZN_DISPATCH` or `ZN_PUBLISH_BROKER` set and not empty, the
-- two variables the dispatcher gives a step: dispatcher.luau), nil for any other kick. A step's credential and wrapped git
-- can push tracker state only, and the net pushes its records (the pass commit, a repair) to main: a net started from a step
-- would run the whole suite holding the one lock and then fail at its push. A step's landing brings no source for a net to
-- test (source lands through the dispatcher's own merge, which kicks in the dispatcher's environment).
function watch.stepKick(env: { [string]: string? }): string?
	for _, name in { "ZN_DISPATCH", "ZN_PUBLISH_BROKER" } do
		local v = env[name]
		if v ~= nil and v ~= "" then
			return "watch-net: not started: a dispatched step cannot push the net's records to main; the dispatcher starts the net after its own merge"
		end
	end
	return nil
end

-- The time a further round must have to spare beyond the last round's own duration: the net's bound (`./zn run --time`)
-- would otherwise stop it in the middle of a git write in the standing worktree.
watch.ROUND_MARGIN_SECONDS = 300

-- Whether the net runs again in-process after a round: a rerun was requested, fewer than `max` rounds have run, and (when
-- the caller knows them) the `left` seconds under the net's own time limit are at least the LONGEST round so far
-- (`rounds`, the durations in seconds: a short tracker-only round says little about the next one) plus the margin.
-- A nil `rounds` or `left` means no time bound. When a request is pending and this says no, the net hands it to a fresh
-- net with its own time (watchcmd.net).
function watch.again(
	requested: boolean,
	round: number,
	max: number,
	rounds: { number }?,
	left: number?
): boolean
	if not requested or round >= max then
		return false
	end
	if rounds ~= nil and left ~= nil then
		local longest = 0
		for _, d in rounds do
			longest = math.max(longest, d)
		end
		return left >= longest + watch.ROUND_MARGIN_SECONDS
	end
	return true
end

-- The time the net's rounds may use: `given` (the `--limit` flag) when it is lower than `bound`, else `bound` (the
-- `./zn run --time` the net runs under: a longer limit would count time the bound never gives).
function watch.netLimit(given: number?, bound: number): number
	return if given ~= nil and given < bound then given else bound
end

return watch
