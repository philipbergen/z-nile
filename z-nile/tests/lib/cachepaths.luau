--!strict
-- The reviewed list of .cache paths in scripts/, z-nile/ and pickman/scripts/ (c0077, c0114, c0120). Unjailed writers under .cache must never
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
cachepaths.ROOTS = { "scripts", "z-nile", "pickman/scripts" }
-- every project root of the registry (design review 001 F5): a new root is skipped without an edit here
cachepaths.SKIP = { ["z-nile/tests"] = true } :: { [string]: boolean }
for _, r in projects.roots(projects.load(cachepaths.TOP)) do
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
		['fs.writeDir(".cache")'] = "the folder itself (fs.writeDir of an existing folder writes nothing)",
		['local out = given or ".cache/board.html"'] = `the board page, written with sh.writeReplacing: {RENAMED}`,
		["fs.writeDir(`{root}/.cache`)"] = "the main checkout's folder itself (c0070's board refresh; fs.writeDir of an existing folder writes nothing)",
		["sh.writeReplacing(`{root}/.cache/board.html`, page)"] = `the main checkout's board page (c0070's board refresh): {RENAMED}`,
	},
	["z-nile/engine/history.luau"] = {
		["local path = `{dir}/.cache/tracker-history.json`"] = `parsed git history for the current HEAD, read back on the next build and {RENAMED}`,
	},
}

cachepaths.ALLOWED = ALLOWED

return cachepaths
