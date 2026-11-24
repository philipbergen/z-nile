--!strict
-- Temporary trees live under <checkout or home>/.cache/.tmp (c0194): the one owner of making them for Lune code and for
-- agents, keeping them apart from every config of the checkout above them, jailing a command in one, and finding the
-- stale ones. Pure rules first, reads and writes at the edge (zz-arch). Its command line is z-nile/lib/tmpcli.luau
-- (`./zn tmp ...`); shell callers in the gate make their trees in shell (z-nile/lib/tmp.sh) and sweep through the command line.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local tmp = {}

tmp.REL = ".cache/.tmp"
tmp.MARKER = ".metadata_never_index"
tmp.OWNER = ".pickman-owner"
tmp.SENTINEL = "gitdir: /nonexistent/pickman-fence\n"
tmp.NONE = ".isolated-no-such-folder"
tmp.OWNED_DEAD_SECONDS = 3600
tmp.UNOWNED_SECONDS = 86400

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

-- A .luaurc key the neutralizer knows how to reset. Any other key in an ancestor refuses (fail closed): it could
-- change how a tree below is checked, and nothing here would undo it.
local RESETTABLE: { [string]: boolean } = { languageMode = true, aliases = true }

export type Ancestor = { path: string, text: string }

-- The .luaurc that keeps every ancestor's aliases out of the trees below .cache/.tmp: each alias an ancestor names
-- (case-insensitive, so lowercased) points at a folder that does not exist, and the language mode is Luau's default.
-- A tree's own .luaurc, nearer, sets its own again. Returns the text, or nil and why.
function tmp.neutralizer(ancestors: { Ancestor }): (string?, string?)
	local names: { [string]: boolean } = {}
	for _, a in ancestors do
		local ok, doc = pcall(function()
			return serde.decode("json", a.text)
		end)
		if not ok or type(doc) ~= "table" then
			return nil, `{a.path} is not strict JSON`
		end
		for key, value in doc :: { [string]: any } do
			if not RESETTABLE[key] then
				return nil, `{a.path} sets "{key}", which the isolation cannot reset`
			end
			if key == "aliases" then
				if type(value) ~= "table" then
					return nil, `{a.path} has aliases that are not an object`
				end
				for name in value :: { [string]: any } do
					names[string.lower(name)] = true
				end
			end
		end
	end
	local sorted: { string } = {}
	for name in names do
		table.insert(sorted, name)
	end
	table.sort(sorted)
	local lines: { string } = {}
	for _, name in sorted do
		table.insert(lines, `    {serde.encode("json", name)}: "./{tmp.NONE}"`)
	end
	local body = if #lines > 0 then "\n" .. table.concat(lines, ",\n") .. "\n  " else ""
	return `\{\n  "languageMode": "nonstrict",\n  "aliases": \{{body}\}\n\}\n`, nil
end

-- The tool names under [tools] in a rokit.toml, or nil and why. Every line there must be `name = "spec"`.
function tmp.rokitTools(text: string): ({ string }?, string?)
	local out: { string } = {}
	local inTools = false
	for line in string.gmatch(text, "[^\n]+") do
		local l = trim(line)
		if l == "" or string.sub(l, 1, 1) == "#" then
			continue
		end
		local section = string.match(l, "^%[([^%]]*)%]$")
		if section then
			inTools = section == "tools"
		elseif inTools then
			local name = string.match(l, '^([%w_%.%-]+)%s*=%s*"[^"]*"$')
			if not name then
				return nil, `cannot read the tools line: {l}`
			end
			table.insert(out, name)
		end
	end
	return out, nil
end

-- The tools the ancestors' manifests name that the tree's own manifests do not: Rokit merges every manifest up the
-- path, so a tool the tree dropped would still resolve from above. Returns the list, or nil and why.
function tmp.rokitLeaks(ancestors: { Ancestor }, own: { Ancestor }): ({ string }?, string?)
	local have: { [string]: boolean } = {}
	for _, o in own do
		local tools, why = tmp.rokitTools(o.text)
		if not tools then
			return nil, `{o.path}: {why}`
		end
		for _, name in tools do
			have[name] = true
		end
	end
	local leaks: { [string]: boolean } = {}
	for _, a in ancestors do
		local tools, why = tmp.rokitTools(a.text)
		if not tools then
			return nil, `{a.path}: {why}`
		end
		for _, name in tools do
			if not have[name] then
				leaks[name] = true
			end
		end
	end
	local out: { string } = {}
	for name in leaks do
		table.insert(out, name)
	end
	table.sort(out)
	return out, nil
end

export type Entry = { name: string, link: boolean, newest: number, owner: string?, ownerAlive: boolean }

-- Whether a tree under .cache/.tmp is stale. Never a link, a name that is not plain (a dot-name is the folder's own file), a tree some process
-- has as its working directory, or a tree whose owner is alive. A tree with a dead owner is stale after an hour
-- unused; one with no owner (a plain mktemp) after a day.
function tmp.stale(e: Entry, now: number, occupied: boolean): boolean
	if e.link or occupied then
		return false
	end
	if string.match(e.name, "^[%w][%w._%-]*$") == nil then
		return false
	end
	local idle = now - e.newest
	if e.owner ~= nil then
		return not e.ownerAlive and idle >= tmp.OWNED_DEAD_SECONDS
	end
	return idle >= tmp.UNOWNED_SECONDS
end

-- ---------------------------------------------------------------------------------------------------- the edge

local function isLink(path: string): boolean
	return process.exec("test", { "-L", path }).ok
end

local function physical(path: string): string?
	if path == "" then
		return nil
	end
	local ok, r = pcall(process.exec, "pwd", { "-P" }, { cwd = path })
	return if ok and r.ok then trim(r.stdout) else nil
end

local function replace(dest: string, text: string): boolean
	local lib = string.match(debug.info(1, "s"), "^(.*)/[^/]+$") or "."
	local r = process.exec("perl", { `{lib}/replace-file.pl`, dest }, { stdio = { stdin = text } })
	return r.ok
end

local function readMaybe(path: string): string?
	local ok, text = pcall(fs.readFile, path)
	return if ok then text else nil
end

-- The files named `name` in every folder from `from` up to /, nearest first, as ancestors. `from` is physical.
local function above(from: string, name: string, skip: string?): { Ancestor }
	local out: { Ancestor } = {}
	local dir: string? = from
	-- each pass drops one folder from dir, so #from passes reach the top; the bound keeps the walk provable
	for _ = 0, #from do
		if not dir or dir == "" then
			break
		end
		local path = `{dir}/{name}`
		if path ~= skip then
			local text = readMaybe(path)
			if text then
				table.insert(out, { path = path, text = text })
			end
		end
		dir = string.match(dir, "^(.*)/[^/]+$")
	end
	local rootText = readMaybe(`/{name}`)
	if rootText then
		table.insert(out, { path = `/{name}`, text = rootText })
	end
	return out
end

-- <dir>/.cache/.tmp, made if missing: refuses a .cache or .tmp that is a link or a file (a link there would turn
-- every write below into a write elsewhere), writes the index marker, the git sentinel and the isolation .luaurc by
-- rename (never through a link). Returns the folder, or nil and why.
function tmp.root(dir: string): (string?, string?)
	local top = physical(dir)
	if not top then
		return nil, `{dir} is not a folder`
	end
	local cache = `{top}/.cache`
	local root = `{cache}/.tmp`
	for _, p in { cache, root } do
		if isLink(p) or (fs.isFile(p)) then
			return nil, `{p} is not a plain folder (a symlink or a file); refusing. Stop and report this.`
		end
	end
	fs.writeDir(root)
	local rootPhysical = physical(root)
	if rootPhysical ~= root then
		return nil, `{root} resolves to {rootPhysical or "nothing"}; refusing. Stop and report this.`
	end
	if not replace(`{root}/{tmp.MARKER}`, "") or not replace(`{root}/.git`, tmp.SENTINEL) then
		return nil, `cannot write {root}'s marker and sentinel`
	end
	-- the isolation file serves the trees that need it (Merging's clone). An ancestor it cannot reset leaves it out: a stale
	-- one is removed, `verify` says why, and the trees that don't need isolation (the gate's) still get their folder
	local text = tmp.neutralizer(above(root, ".luaurc", `{root}/.luaurc`))
	if not text then
		pcall(fs.removeFile, `{root}/.luaurc`)
	elseif readMaybe(`{root}/.luaurc`) ~= text and not replace(`{root}/.luaurc`, text) then
		return nil, `cannot write {root}/.luaurc`
	end
	return root, nil
end

-- Where a new tree goes. An explicit `dir` is that checkout's (or home's) .cache/.tmp. Without one, the environment
-- decides: a TMPDIR inside some .cache/.tmp is where this session or run keeps its trees (a spec run's own folder, an
-- agent's session folder), so they go there, which is also the only place a jailed run may write; otherwise the
-- checkout the command runs in.
function tmp.place(dir: string?): (string?, string?)
	if dir then
		return tmp.root(dir)
	end
	local env = process.env.TMPDIR or ""
	local prefix, belowMatch = string.match(env, "^(.*)/%.cache/%.tmp(/?.*)$") -- the nearest, a clone being inside another
	local below: string = belowMatch or ""
	if prefix and (below == "" or below == "/") then
		return tmp.root(prefix)
	elseif prefix and string.sub(below, 1, 1) == "/" then
		local folder = string.gsub(env, "/+$", "")
		if isLink(folder) or not fs.isDir(folder) then
			return nil, `{folder} (TMPDIR) is not a plain folder; refusing. Stop and report this.`
		end
		return folder, nil
	end
	return tmp.root(process.env.ZN_TOP or ".")
end

-- The kernel's start record of a pid: the same perl as the runner's lock (tests/lib/fence.luau), pinned equal by a spec, so a
-- run folder's owner record is read by the one format whoever wrote it, and the jail (which refuses the setuid ps) allows it.
tmp.STARTED = table.concat({
	"my $pid = shift; exit 2 unless defined $pid && $pid =~ /^\\d+$/;",
	"if ($^O eq 'darwin') { my $mib = pack('i4', 1, 14, 1, $pid); my $buf = \"\\0\" x 4096;",
	"my $len = pack('Q', length $buf); exit 2 unless syscall(202, $mib, 4, $buf, $len, 0, 0) == 0;",
	"exit 1 unless unpack('Q', $len) > 0; my ($sec, $usec) = unpack('q l', $buf); exit 1 unless $sec > 0;",
	'print "$sec.$usec\\n"; exit 0 }',
	"if ($^O eq 'linux') { open(my $b, '<', '/proc/sys/kernel/random/boot_id') or exit 2; my $boot = <$b>;",
	"close $b; chomp $boot; open(my $st, '<', \"/proc/$pid/stat\") or exit 1; my $line = <$st>; close $st;",
	"$line =~ s/^.*\\)\\s+//s or exit 2; my $ticks = (split /\\s+/, $line)[19];",
	"exit 2 unless $boot ne '' && defined $ticks && $ticks =~ /^\\d+$/; print \"$boot:$ticks\\n\"; exit 0 }",
	"exit 2;",
}, " ")

-- A pid's start id (see STARTED); "" for no such process (exit 1), nil when it cannot be told (exit 2, no perl, a platform it
-- does not know): then a caller takes the process as alive, as the runner's `fence.startOf` does.
function tmp.startOf(pid: string): string?
	if string.match(pid, "^%d+$") == nil then
		return ""
	end
	local ok, r = pcall(process.exec, "perl", { "-e", tmp.STARTED, pid })
	if not ok then
		return nil
	end
	if r.ok then
		return trim(r.stdout)
	end
	return if r.code == 1 then "" else nil
end

-- A fresh <root>/<kind>.XXXXXX, created exclusively. A caller that outlives its tree names itself as `owner` (a pid),
-- so the stale sweep can tell a live run's tree from a dead one's; a tree with no owner is judged by use alone.
function tmp.new(dir: string?, kind: string, owner: string?): (string?, string?)
	if string.match(kind, "^[%a][%w_%-]*$") == nil then
		return nil, `{kind} is not a kind of temporary tree (letters, digits, - and _)`
	end
	local root, why = tmp.place(dir)
	if not root then
		return nil, why
	end
	local made = process.exec("/usr/bin/env", { "mktemp", "-d", `{root}/{kind}.XXXXXX` })
	if not made.ok then
		return nil, `cannot make a folder in {root}: {trim(made.stderr)}`
	end
	local tree = trim(made.stdout)
	if owner and string.match(owner, "^%d+$") then
		fs.writeFile(`{tree}/{tmp.OWNER}`, `{owner}\t{tmp.startOf(owner) or "?"}\n`)
	end
	return tree, nil
end

-- The `.cache` folder, the `.tmp` folder and the name of a tree that is a direct child of one, from its physical path.
local function parts(at: string): (string?, string?, string?)
	local root, name = string.match(at, "^(.*/%.cache/%.tmp)/([%w][%w._%-]*)$")
	if not root then
		return nil, nil, nil
	end
	return string.sub(root, 1, -6), root, name
end

-- "isolated", or why not: the tree is a direct child of a .cache/.tmp (its root comes from the tree itself, never from
-- where the command runs), that folder's .luaurc is what the folders above need today, and no ancestor Rokit manifest
-- names a tool the manifests between the tree and the folder lack (a manifest in the folder itself is no tree's own).
function tmp.verify(tree: string): string
	local at = physical(tree)
	if not at then
		return "not isolated: the tree is missing"
	end
	local cache, root = parts(at)
	if not cache or not root or isLink(tree) or isLink(root) or isLink(cache) then
		return `not isolated: {at} is not a direct child of a {tmp.REL} folder`
	end
	local want, why = tmp.neutralizer(above(root, ".luaurc", `{root}/.luaurc`))
	if not want then
		return `not isolated: {why}`
	end
	if readMaybe(`{root}/.luaurc`) ~= want then
		return `not isolated: {root}/.luaurc is not what the folders above need (run ./zn tmp root)`
	end
	local own: { Ancestor } = {}
	for _, a in above(at, "rokit.toml", nil) do
		if string.sub(a.path, 1, #root + 1) == root .. "/" and a.path ~= `{root}/rokit.toml` then
			table.insert(own, a)
		end
	end
	local leaks, lwhy = tmp.rokitLeaks(above(root, "rokit.toml", nil), own)
	if not leaks then
		return `not isolated: {lwhy}`
	end
	if #leaks > 0 then
		return `not isolated: rokit.toml above names {table.concat(leaks, ", ")}, which the tree's own rokit.toml does not`
	end
	return "isolated"
end

-- Process working directories, from lsof; nil when lsof cannot answer (then nothing is swept).
function tmp.workingDirs(): { string }?
	local started, r = pcall(process.exec, "lsof", { "-a", "-d", "cwd", "-Fn" })
	if not started or (not r.ok and r.stdout == "") then
		return nil -- lsof is missing or failed: cannot tell (R0070 final review F1)
	end
	local out: { string } = {}
	for line in string.gmatch(r.stdout, "[^\n]+") do
		if string.sub(line, 1, 1) == "n" then
			table.insert(out, string.sub(line, 2))
		end
	end
	return out
end

-- When anything in the tree was last changed, in seconds: the folder and its entries first, then a look through the
-- whole tree for a change within `windowMinutes` (the window of the rule that judges this tree; find stops at the first).
local function newest(path: string, windowMinutes: number): number
	local best = 0
	local function see(p: string)
		local ok, meta = pcall(fs.metadata, p)
		if ok and meta.modifiedAt then
			best = math.max(best, (meta.modifiedAt :: any).unixTimestamp)
		end
	end
	see(path)
	-- only folders and regular files go to fs.metadata, which panics Lune on a FIFO or socket (R0070 final review F2)
	local listed = process.exec(
		"find",
		{ path, "-mindepth", "1", "-maxdepth", "1", "(", "-type", "d", "-o", "-type", "f", ")" }
	)
	if listed.ok then
		for entry in string.gmatch(listed.stdout, "[^\n]+") do
			see(entry)
		end
	end
	local recent = process.exec("find", { path, "-mmin", `-{windowMinutes}`, "-print", "-quit" })
	if recent.ok and trim(recent.stdout) ~= "" then
		best = math.max(best, os.time())
	end
	return best
end

-- Removes <root>/<name> from inside <root>, entered by its physical path: a link swapped in for `.cache` or `.tmp` since
-- the caller checked them makes this refuse instead of deleting somewhere else. Only a plain name; a direct child.
function tmp.remove(root: string, name: string): boolean
	if string.match(name, "^[%w][%w._%-]*$") == nil then
		return false
	end
	local script = 'cd -P -- "$1" && [ "$(pwd -P)" = "$1" ] && exec rm -rf -- "$2"'
	return process.exec("sh", { "-c", script, "_", root, name }).ok
end

-- Removes the stale trees under <dir>/.cache/.tmp. `dryRun` removes nothing.
-- Returns the trees removed (or that would be, with `dryRun`), each with its idle time, or nil and why when it could not
-- tell what is in use. The caller reports them.
export type Probes = { workingDirs: () -> { string }?, startOf: (string) -> string? }
tmp.REAL = { workingDirs = tmp.workingDirs, startOf = tmp.startOf } :: Probes

function tmp.sweep(dir: string, dryRun: boolean, probes: Probes): ({ string }?, string?)
	local top = physical(dir)
	local root = if top then `{top}/{tmp.REL}` else nil
	if not root or not fs.isDir(root) or isLink(root) or isLink(`{top}/.cache`) then
		return {}, nil
	end
	local cwds = probes.workingDirs()
	if not cwds then
		return nil, "cannot list the processes' working directories (lsof); nothing swept"
	end
	local now = os.time()
	local found: { string } = {}
	for _, name in fs.readDir(root) do
		local path = `{root}/{name}`
		local link = isLink(path)
		-- a directory or a regular file only: never a socket, FIFO or device (review 001 F4)
		-- (fs.metadata panics Lune on those kinds, so only `test` looks at an entry until it is known to be one of the two)
		local isDirectory = not link and process.exec("test", { "-d", path }).ok
		local swept = isDirectory or (not link and process.exec("test", { "-f", path }).ok)
		local owner: string? = nil
		local alive = false
		if isDirectory then
			local rec = readMaybe(`{path}/{tmp.OWNER}`)
			if rec then
				local pid, start = string.match(rec, "^(%d+)\t([^\n]*)")
				-- a record that does not parse is no record: the day rule judges the tree
				if pid then
					owner = rec
					local running = probes.startOf(pid)
					alive = running == nil
						or (running ~= "" and (start == "?" or start == "" or running == start))
				end
			end
		end
		local occupied = false
		for _, c in cwds do
			if c == path or string.sub(c, 1, #path + 1) == path .. "/" then
				occupied = true
			end
		end
		local entry: Entry = {
			name = name,
			link = link,
			newest = if not swept
				then now
				else newest(
					path,
					if owner then tmp.OWNED_DEAD_SECONDS // 60 else tmp.UNOWNED_SECONDS // 60
				),
			owner = owner,
			ownerAlive = alive,
		}
		if swept and tmp.stale(entry, now, occupied) then
			table.insert(found, `{path} (idle {math.floor((now - entry.newest) / 3600)} h)`)
			if not dryRun then
				tmp.remove(root, name)
			end
		end
	end
	return found, nil
end

-- A path as a sandbox regex: every character that means something in one is escaped.
local function regexOf(path: string): string
	return (string.gsub(path, "[%.%[%]%*%^%$%(%)%+%?{}|\\]", "\\%0"))
end

-- The profile for a command run in a scratch tree that has no guards of its own (an unguarded-code run, zz-test). It is
-- the spec jail's rule set applied to the clone inside the tree, so that a spec runner started there takes the clone for a
-- fixture of a guarded checkout and its nested runs pass (the user's decision, 2026-11-01, "Make them work jailed"): the
-- command may write `/dev`, its own TMPDIR (`<tree>/.jail-tmp`) and the contents of the `.cache` folders it is given
-- (`caches`, the ones `prepareCaches` made: a checkout's and each project home's, as the runner guards them), never the
-- entry of one and never a symlink at the top of one; the rest of the tree, the clone's sources and its git directory,
-- is read-only to it, as the checkout is to a spec. No allow rule is a pattern over names: a path the command can create
-- itself (a `.cache` folder deeper in the sources or the git directory) is never matched. No network but loopback, no
-- signal out of the sandbox. `tree` is the tree's physical path (sandbox rules match the resolved path, so no other spelling is
-- written); every cache is below it.
function tmp.jailProfile(tree: string, caches: { string }): string
	local rules = {
		"(version 1)",
		"(allow default)",
		"(deny network-outbound (remote ip))",
		'(allow network-outbound (remote ip "localhost:*"))',
		'(deny file-write* (subpath "/"))',
		'(allow file-write* (subpath "/dev"))',
		`(allow file-write* (subpath "{tree}/.jail-tmp"))`,
	}
	for _, cache in caches do
		table.insert(rules, `(allow file-write* (subpath "{cache}"))`)
	end
	for _, cache in caches do
		table.insert(rules, `(deny file-write* (literal "{cache}"))`) -- later rules win
		table.insert(
			rules,
			`(deny file-write-create (require-all (vnode-type SYMLINK) (regex #"^{regexOf(cache)}/[^/]+$")))`
		)
	end
	table.insert(rules, "(deny signal (with no-log))")
	table.insert(rules, "(allow signal (target same-sandbox))")
	return table.concat(rules, "")
end

export type Inherited = { ceilings: string, realGit: string, common: string }
export type JailPlan = { argv: { string }, cwd: string }

-- What running `argv` in `tree` under that profile takes: the command line (sandbox-exec, then `env` with TMPDIR inside the
-- tree and the two lists the spec runner reads to take this for a fixture of a guarded checkout: the `.cache` that holds the
-- tree's `.tmp` joins GIT_CEILING_DIRECTORIES, and this checkout's git directory joins PICKMAN_FENCE_REAL_GIT, so a runner started in
-- the clone does not refuse to start inside this sandbox), and the folder it runs in (the tree). Nil and why unless
-- the tree is a direct child of a .cache/.tmp, made by `new`. It makes the `.cache` folders the profile opens first
-- (`prepareCaches`), so a tree that is not one is never written.
function tmp.jailPlan(tree: string, argv: { string }, inherited: Inherited): (JailPlan?, string?)
	local at = physical(tree)
	local cache = if at then parts(at) else nil
	if not at or not cache or isLink(tree) then
		return nil, `{tree} is not a tree made by ./zn tmp new (a direct child of a {tmp.REL} folder)`
	end
	if #argv == 0 then
		return nil, "no command given"
	end
	local caches, cachesWhy = tmp.prepareCaches(at) -- made first: the jail denies the sources around them
	if not caches then
		return nil, cachesWhy
	end
	local function joined(a: string, b: string): string
		return if a == "" then b else `{a}:{b}`
	end
	local out = {
		"sandbox-exec",
		"-p",
		tmp.jailProfile(at, caches),
		"env",
		`TMPDIR={at}/.jail-tmp`,
		`GIT_CEILING_DIRECTORIES={joined(inherited.ceilings, cache)}`,
		`PICKMAN_FENCE_REAL_GIT={joined(inherited.realGit, inherited.common)}`,
	}
	for _, a in argv do
		table.insert(out, a)
	end
	return { argv = out, cwd = at }, nil
end

-- The project homes of a checkout: its direct children that hold a `.tracker` (the set fence.sh fences), as paths.
function tmp.homesOf(checkout: string): { string }
	local out: { string } = {}
	local ok, names = pcall(fs.readDir, checkout)
	if ok then
		for _, home in names do
			local path = `{checkout}/{home}`
			if fs.isDir(path) and not isLink(path) and fs.isDir(`{path}/.tracker`) then
				table.insert(out, path)
			end
		end
	end
	return out
end

-- The `.cache` folders the jail will let a command write, made before it starts (the jail cannot make them: it denies
-- the sources around them): one in every checkout inside the tree (a direct child with a `.git`) and one in each of its
-- project homes (a direct child of the checkout that holds a `.tracker`), the set `fence.sh` fences. A `.cache` that is a
-- link or a file refuses. Returns the folders made or found, or nil and why.
function tmp.prepareCaches(tree: string): ({ string }?, string?)
	local at = physical(tree)
	if not at then
		return nil, `{tree} is not a folder`
	end
	local out: { string } = {}
	local function make(dir: string): string?
		local cache = `{dir}/.cache`
		if isLink(cache) or fs.isFile(cache) then
			return `{cache} is not a plain folder (a symlink or a file); refusing. Stop and report this.`
		end
		fs.writeDir(cache)
		table.insert(out, cache)
		return nil
	end
	for _, name in fs.readDir(at) do
		local checkout = `{at}/{name}`
		if
			fs.isDir(checkout)
			and not isLink(checkout)
			and process.exec("test", { "-e", `{checkout}/.git` }).ok
		then
			local why = make(checkout)
			if why then
				return nil, why
			end
			for _, home in tmp.homesOf(checkout) do
				local homeWhy = make(home)
				if homeWhy then
					return nil, homeWhy
				end
			end
		end
	end
	return out, nil
end

-- Removes one tree made by `new` (a direct child of a .cache/.tmp that is not a link), through `remove`.
function tmp.removeTree(tree: string): (boolean, string?)
	local at = physical(tree)
	local _, root, name = parts(at or "")
	if not at or not root or isLink(tree) then
		return false, `{tree} is not a tree made by ./zn tmp new (a direct child of a {tmp.REL} folder)`
	end
	return tmp.remove(root, name :: string), nil
end

-- The trees the tooling used to leave in the system temp folder (or `base`), one report line each, for the person to
-- look at before anything is removed. Only the names in `remove` are removed, and never one a process works in.
-- The folder is resolved to its physical path first (the user temp folder is `/var/folders/...`, a link to
-- `/private/var/...`, and `lsof` and `tmp.remove` speak the physical one), so both comparisons use one spelling. When
-- `probes.workingDirs` cannot tell what is in use, nothing is removed and every tree reads `IN USE?`. Returns the lines,
-- or an empty list and why the folder could not be resolved.
function tmp.leftovers(remove: { string }, base: string?, probes: Probes?): ({ string }, string?)
	local chosen: string = base or ""
	if not base then
		local ut = process.exec("getconf", { "DARWIN_USER_TEMP_DIR" })
		chosen = if ut.ok and trim(ut.stdout) ~= "" then trim(ut.stdout) else (process.env.TMPDIR or "/tmp")
	end
	local where = physical((string.gsub(chosen, "/+$", "")))
	if not where then
		return {}, `{chosen} is not a folder; nothing listed`
	end
	local cwds = (probes or tmp.REAL).workingDirs()
	local patterns = {
		"^tmp%.",
		"^pickman%-run%.",
		"^par%.",
		"^tracker%-remap%-base%.",
		"^check%-build%.",
		"^globalTypes%.",
		"^pickman%-guard%.",
	}
	local want: { [string]: boolean } = {}
	for _, n in remove do
		want[n] = true
	end
	local lines: { string } = {}
	for _, name in fs.readDir(where) do
		local match = false
		for _, p in patterns do
			if string.match(name, p) then
				match = true
			end
		end
		local path = `{where}/{name}`
		if match and fs.isDir(path) and not isLink(path) then
			local occupied = false
			local busy: { string } = if cwds then cwds else {}
			for _, c in busy do
				if c == path or string.sub(c, 1, #path + 1) == path .. "/" then
					occupied = true
				end
			end
			local size = string.match(process.exec("du", { "-sk", path }).stdout, "^%s*(%d+)") or "?"
			local repo = fs.isDir(`{path}/repo/.git`) or fs.isDir(`{path}/.git`)
			local idle = math.floor((os.time() - newest(path, tmp.UNOWNED_SECONDS // 60)) / 3600)
			local removed = false
			if want[name] and cwds and not occupied then
				removed = tmp.remove(where, name)
			end
			table.insert(
				lines,
				`{name}\t{size} kB\t{idle} h idle\t{if repo then "repo" else "-"}\t{if not cwds
					then "IN USE?"
					else if occupied then "IN USE" else if removed then "REMOVED" else "kept"}`
			)
		end
	end
	return lines, nil
end

return tmp
