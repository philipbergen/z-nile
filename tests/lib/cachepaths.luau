--!strict
-- The reviewed list of .cache paths in scripts/ (c0077). Unjailed writers under .cache must never write through a
-- symlink a spec swapped in there (the jail can't refuse a swap, c0077 E1), so every line in scripts/ that names a
-- .cache path is listed here with how it stays safe: through scripts/lib/replace-file.pl (a rename, never a write
-- through a link), a `mkdir -p` of a plain folder the fence checks, a read, or a message. A new line needs a
-- reviewer to add it here. The list covers scripts/ only: a write through a listed variable, or a write from the
-- runner (tests/lib), is review's to catch (testing skill).
local cachepaths = {}

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
	["scripts/check.sh"] = {
		["mkdir -p .cache"] = "the folder itself: the runner and fence.sh refuse a .cache that isn't a plain folder",
		["find .cache -mindepth 1 -maxdepth 1 -type l -exec rm -f {} +"] = "unlinks top-level links, never follows one",
		["defs=.cache/globalTypes.d.luau"] = `downloaded to the user temp folder, then {RENAMED}`,
		['"$@" -o "$d/$out" && perl scripts/lib/replace-file.pl ".cache/$out" "$d/$out"'] = `built in the user temp folder, then {RENAMED}`,
	},
	["scripts/lib/fence.sh"] = {
		['export GIT_CEILING_DIRECTORIES="${GIT_CEILING_DIRECTORIES:+$GIT_CEILING_DIRECTORIES:}$here/.cache"'] = "a path in an environment variable; writes nothing",
		["if [[ -L $here/.cache || ( -e $here/.cache && ! -d $here/.cache ) ]]; then"] = "a read: refuses a .cache that isn't a plain folder",
		['echo "fence: $here/.cache is not a plain folder (a symlink or a file); refusing. Stop and report this." >&2'] = "a message",
		['mkdir -p "$here/.cache"'] = "the folder itself, checked to be a plain folder just above",
		['local sentinel="$here/.cache/.git"'] = "a link there is unlinked, a folder refused; the sentinel is renamed in (rename(2), inline)",
		['fresh=$(mktemp "$here/.cache/.sentinel.XXXXXX") || return 1 # created exclusively, before any spec runs'] = "mktemp creates a fresh file exclusively, never through a link",
		['mkdir -p "$here/.cache/gh-none"'] = "an empty folder for gh's configuration; mkdir -p over a link writes nothing through it",
		['export GH_CONFIG_DIR="$here/.cache/gh-none" GIT_TERMINAL_PROMPT=0'] = "a path in an environment variable; gh reads no configuration there in a spec run",
	},
	["scripts/tracker/main.luau"] = {
		["board [--out PATH] [-O]                       write the tracker as one HTML page (default .cache/board.html)"] = "usage text",
		['local FOCUS_FILE = ".cache/tracker-focus"'] = `sh.writeReplacing: {RENAMED}`,
		["return `.cache/tracker-claim-{raftId}`"] = `the claim file, written with sh.writeReplacing: {RENAMED}`,
		['fs.writeDir(".cache")'] = "the folder itself (fs.writeDir of an existing folder writes nothing)",
		['local out = given or ".cache/board.html"'] = `the board page, written with sh.writeReplacing: {RENAMED}`,
		["fs.writeDir(`{root}/.cache`)"] = "the main checkout's folder itself (c0070's board refresh; fs.writeDir of an existing folder writes nothing)",
		["sh.writeReplacing(`{root}/.cache/board.html`, page)"] = `the main checkout's board page (c0070's board refresh): {RENAMED}`,
	},
}

cachepaths.ALLOWED = ALLOWED

return cachepaths
