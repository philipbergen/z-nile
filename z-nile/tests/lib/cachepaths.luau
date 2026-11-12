--!strict
-- The reviewed list of .cache paths in scripts/, z-nile/ and every project home's scripts/ (c0077, c0114, c0120, c0184).
-- Unjailed writers under .cache must never
-- write through a symlink a spec swapped in there (the jail can't refuse a swap, c0077 E1), so every line in those
-- folders that names a .cache path is listed here with how it stays safe: through z-nile/lib/replace-file.pl (a
-- rename, never a write through a link), a `mkdir -p` of a plain folder the fence checks, a read, or a message. A new
-- line needs a reviewer to add it here. The list covers scripts/ and z-nile/ (its .tracker/ documents aside) only: a
-- write through a listed variable, or a write from the runner (tests/lib), is review's to catch (zz-test skill).
local fs = require("@lune/fs")
local projects = require("@znile/engine/projects")

local cachepaths = {}

-- The checkout that holds this harness: three folders above z-nile/tests/lib/cachepaths.luau. Specs run from a
-- project's home (c0120), so the scan reads the checkout from here, with root-relative paths.
cachepaths.TOP = string.match(debug.info(1, "s"), "^(.*)/[^/]+/[^/]+/[^/]+/[^/]+$") or "."
-- The folders whose .luau and .sh files the list covers, and the ones inside them it skips: tracker documents, and
-- z-nile's own specs and harness (z-nile/tests, c0120), which are specs, not writers. Every .cache is skipped too.
-- The folders are the root's scripts/, z-nile/ and the scripts/ of every other project's home, from the registry
-- (c0184): a new project's writers join the scan without an edit here. Pure over a parsed registry.
function cachepaths.rootsOf(reg: projects.Registry): { string }
	local out = { "scripts", "z-nile" }
	for _, p in reg.projects do
		if p.home ~= "." and p.home ~= "z-nile" then
			table.insert(out, `{p.home}/scripts`)
		end
	end
	return out
end
local registry = projects.load(cachepaths.TOP)
cachepaths.ROOTS = cachepaths.rootsOf(registry)
-- every project root of the registry (design review 001 F5): a new root is skipped without an edit here
cachepaths.SKIP = { ["z-nile/tests"] = true } :: { [string]: boolean }
for _, r in projects.roots(registry) do
	cachepaths.SKIP[r] = true
end

-- The text of every .luau and .sh file the list covers, keyed by its root-relative path.
function cachepaths.files(): { [string]: string }
	local out: { [string]: string } = {}
	local function walk(dir: string)
		if not fs.isDir(`{cachepaths.TOP}/{dir}`) then
			return
		end
		for _, name in fs.readDir(`{cachepaths.TOP}/{dir}`) do
			local path = `{dir}/{name}`
			if cachepaths.SKIP[path] or name == ".cache" then
				continue
			elseif fs.isDir(`{cachepaths.TOP}/{path}`) then
				walk(path)
			elseif string.match(name, "%.luau$") or string.match(name, "%.sh$") then
				out[path] = fs.readFile(`{cachepaths.TOP}/{path}`)
			end
		end
	end
	for _, dir in cachepaths.ROOTS do
		walk(dir)
	end
	return out
end

-- A comment line in Luau (`--`) or shell (`#`): skipped by the scan.
local function comment(line: string): boolean
	return string.match(line, "^%s*%-%-") ~= nil or string.match(line, "^%s*#") ~= nil
end

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

-- Every line of `files` (path -> text) that names .cache and isn't in `allowed[path]` (trimmed line -> reason), as
-- "<path>: <trimmed line>"; and every allowed line not found in its file (the file missing included), as
-- "<path>: listed but missing: <line>". Comment lines are skipped both ways. Pure: it reads no files.
function cachepaths.scan(files: { [string]: string }, allowed: { [string]: { [string]: string } }): { string }
	local out: { string } = {}
	local seen: { [string]: { [string]: boolean } } = {}
	for path, text in files do
		local lines: { [string]: boolean } = {}
		seen[path] = lines
		local listed = allowed[path] or {}
		for line in string.gmatch(text, "[^\n]+") do
			if string.find(line, ".cache", 1, true) and not comment(line) then
				local trimmed = trim(line)
				lines[trimmed] = true
				if not listed[trimmed] then
					table.insert(out, `{path}: {trimmed}`)
				end
			end
		end
	end
	for path, lines in allowed do
		for line in lines do
			if not (seen[path] and seen[path][line]) then
				table.insert(out, `{path}: listed but missing: {line}`)
			end
		end
	end
	table.sort(out)
	return out
end

local RENAMED = "written through replace-file.pl (a rename onto the path, never through a link)"

local ALLOWED: { [string]: { [string]: string } } = {
	-- c0165: the orchestrator runs unjailed and names the files a run leaves in a home's .cache
	["z-nile/specs.luau"] = {
		["local resultsFile = `{ROOT}/{prefix}.cache/spec-results-{fence.myPid()}.json`"] = "the run's results file, named for the orchestrator's pid; the runner (inside the jail) writes it, this reads and removes it, and the runner writes only a path below its own .cache (c0165)",
		["pcall(fs.writeDir, `{ROOT}/{prefix}.cache`)"] = "the folder itself (fs.writeDir of an existing folder writes nothing)",
	},
	["z-nile/check.sh"] = {
		["luau-lsp analyze --base-luaurc=.luaurc --platform=standard --ignore='**/.tracker/**' --ignore='**/.cache/**' \"${LUNE_DIRS[@]}\""] = "an ignore pattern for the type check; writes nothing (c0120: a home's .cache holds fixtures' copies)",
		["mkdir -p .cache"] = "the folder itself: the runner and fence.sh refuse a .cache that isn't a plain folder",
		["find .cache -mindepth 1 -maxdepth 1 -type l -exec rm -f {} +"] = "unlinks top-level links, never follows one",
		["defs=.cache/globalTypes.d.luau"] = `downloaded to the user temp folder, then {RENAMED}`,
		['c="$(prefix "${homes[$i]}").cache"'] = "a project home's .cache folder (c0120): made with mkdir -p and its top-level links unlinked, as the root's",
		['out="$(prefix "$h").cache/check.rbxl"'] = `a project's game place, built in the user temp folder by build_place, then {RENAMED}`,
		['[[ $stem == default ]] || out="$(prefix "$h").cache/check-$stem.rbxl"'] = `a project's other places, built like the game place, then {RENAMED}`,
	},
	["z-nile/lib/fence.sh"] = {
		['*":$1/.cache:"*) ;;'] = "a match on an environment variable; writes nothing (c0120: the ceiling step)",
		['*) export GIT_CEILING_DIRECTORIES="${GIT_CEILING_DIRECTORIES:+$GIT_CEILING_DIRECTORIES:}$1/.cache" ;;'] = "a path in an environment variable; writes nothing",
		['echo "fence: cannot write $home/.cache\'s sentinel; refusing. Stop and report this." >&2'] = "a message (c0120)",
		['pickman_fence_sentinel "$d" || { echo "fence: cannot write $d/.cache\'s sentinel; refusing. Stop and report this." >&2; return 1; }'] = "a message; the sentinel is the fence's rename (pickman_fence_all, c0120 code review 005 F2)",
		['echo "fence: the jail refused $home/.cache\'s sentinel; its ceiling and every other guard hold" >&2'] = "a message (c0120)",
		['$home/.cache != "$PICKMAN_TEST_FENCE"/.cache && $home/.cache != "$PICKMAN_TEST_FENCE"/.cache/* ]]; then'] = "a comparison of paths; writes nothing (c0120 review 003 F2)",
		["if [[ ! -L $here/.cache/.git && -d $here/.cache/.git ]]; then"] = "a read: refuses a sentinel that is a folder (the refusals step)",
		['echo "fence: $here/.cache/.git is a folder; refusing (remove it yourself after checking it). Stop and report this." >&2'] = "a message",
		["if [[ -L $here/.cache || ( -e $here/.cache && ! -d $here/.cache ) ]]; then"] = "a read: refuses a .cache that isn't a plain folder",
		['echo "fence: $here/.cache is not a plain folder (a symlink or a file); refusing. Stop and report this." >&2'] = "a message",
		['mkdir -p "$here/.cache" || return 1'] = "the folder itself, checked to be a plain folder just above",
		['$here == "$PICKMAN_TEST_FENCE"/.cache/* ]]; then'] = "a read: compares two paths (the jail waiver, c0114)",
		['local sentinel="$here/.cache/.git"'] = "a link there is unlinked, a folder refused; the sentinel is renamed in (rename(2), inline)",
		['fresh=$(mktemp "$here/.cache/.sentinel.XXXXXX") || return 1 # created exclusively, before any spec runs'] = "mktemp creates a fresh file exclusively, never through a link",
		['mkdir -p "$here/.cache/gh-none" || return 1'] = "an empty folder for gh's configuration; mkdir -p over a link writes nothing through it",
		['export GH_CONFIG_DIR="$here/.cache/gh-none" GIT_TERMINAL_PROMPT=0'] = "a path in an environment variable; gh reads no configuration there in a spec run",
	},
	["z-nile/engine/main.luau"] = {
		["board [--out PATH] [-O]                       write the tracker as one HTML page (default .cache/board.html)"] = "usage text",
		['local FOCUS_FILE = ".cache/tracker-focus"'] = `sh.writeReplacing: {RENAMED}`,
		["return `.cache/tracker-claim-{raftId}`"] = `the claim file, written with sh.writeReplacing: {RENAMED}`,
		["return `.cache/tracker-stamp-{id}`"] = `c0274: the stamp this checkout remembers for a claim, written with sh.writeReplacing: {RENAMED}`,
		['hb.MARKS = ".cache/tracker-beats"'] = `c0275: the throttle marks, one file per claim, written with sh.writeReplacing: {RENAMED}; the folder is made with fs.writeDir (an existing folder writes nothing)`,
		["local cache = `{dir}/.cache`"] = "c0277: a read of another checkout's folder, to list the claims its memory holds; nothing is written",
		["fs.writeDir(`{path}/.cache`)"] = "c0277: a worktree's folder itself (fs.writeDir of an existing folder writes nothing), before the marker or the fresh file is renamed in",
		['hb.BEATER_DIR = ".cache/tracker-beater"'] = "c0275: the background beater's pid file and log, the pid file written with sh.writeReplacing (a rename), the log opened by the detached beater itself",
		['fs.writeDir(".cache")'] = "the folder itself (fs.writeDir of an existing folder writes nothing)",
		['local out = given or ".cache/board.html"'] = `the board page, written with sh.writeReplacing: {RENAMED}`,
		["fs.writeDir(`{root}/.cache`)"] = "the main checkout's folder itself (c0070's board refresh; fs.writeDir of an existing folder writes nothing)",
		["sh.writeReplacing(`{root}/.cache/board.html`, page)"] = `the main checkout's board page (c0070's board refresh): {RENAMED}`,
		["watch-kick                                    start watch-net after a landing and return at once (log: .cache/watch-net.log)"] = "usage text: the net's log path",
		['local at = string.find(cwd, "/.cache/", 1, true)'] = "a prefix compared with a CLI's real path (only a fake under .cache starts inside a check); nothing is written",
		['return if at then string.sub(cwd, 1, at + 7) else cwd .. ".cache/"'] = "the same prefix; nothing is written",
		["return `refusing to start {argv[1]}: inside a check run only a CLI under this checkout's .cache may start (found {bin})`"] = "a message",
		["stateDir = `.cache/idea-run/{id}/{phase}`,"] = "the idea stage's supervisor state for one attempt (pid, stdin, stop, measure); gitignored under this checkout's .cache, written by the runner the same way a dispatch step's state dir is",
	},
	["z-nile/engine/heartbeat.luau"] = {
		['heartbeat.DISCARDED = ".cache/discarded"'] = "c0277: the marker a takeover leaves in the old worktree, written with sh.writeReplacing (a rename); every other command only reads it",
		['heartbeat.FRESH = ".cache/fresh"'] = "c0277: the epoch a takeover made a copy, written with sh.writeReplacing (a rename), removed when the copy gets claim memory",
	},
	["z-nile/engine/watchcmd.luau"] = {
		["'cd \"$1\" && ./zn run --time 3600 -- ./zn watch-net > .cache/watch-net.log 2>&1 &',"] = "starts the net in the background; the log is this checkout's .cache, which the fence already guards",
		["fs.writeDir(`{root}/.cache`)"] = "the folder itself (fs.writeDir of an existing folder writes nothing)",
		['print("watch-net: started, log at .cache/watch-net.log")'] = "a message naming the log",
	},
	["z-nile/engine/board.luau"] = {
		["local home = `{dir}/.cache/dispatch`"] = "c0118: the board reads the dispatcher's run state (state.json, questions.md) to show it on a card; nothing is written",
	},
	["z-nile/engine/dispatcher.luau"] = {
		["checking: () -> boolean, -- inside a guarded run (a spec or a check.sh): only a CLI under .cache may start"] = "a comment in a type",
		['local HOME = ".cache/dispatch"'] = `the dispatcher's run state (c0117) in the main checkout: state.json and the markers through sh.writeReplacing ({RENAMED}); the runner's pid file is a nested file the launcher creates`,
		['local at = string.find(here, "/.cache/", 1, true)'] = "a prefix compared with a CLI's real path (c0117: only a fake under .cache starts inside a check); nothing is written",
		['return if at then string.sub(here, 1, at + 7) else here .. ".cache/"'] = "the same prefix; nothing is written",
		["`refusing to start {argv[1]}: inside a check run only a CLI under this checkout's .cache may start (found {bin})`"] = "a message",
	},
	["z-nile/engine/costrow.luau"] = {
		["local path = `{root}/.cache/measure.tsv`"] = "the checkout's measure buffer; gitignored, appended by a gate, a spec run or ./zn run, and folded into a ticket only by commit, spend, done or land",
	},
	["z-nile/engine/history.luau"] = {
		["local path = `{dir}/.cache/tracker-history.json`"] = `parsed git history for the current HEAD, read back on the next build and {RENAMED}`,
	},
}

cachepaths.ALLOWED = ALLOWED

return cachepaths
