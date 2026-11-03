--!strict
-- Which processes are leaks (c0191): the pure part of `./zn reap`. `parse` reads `ps -axww -E -o pid=,ppid=,uid=,etime=,time=,
-- lstart=,command=` (the command column carries the environment after the arguments, for the user's own processes);
-- `wantCwd` names the processes whose folder must be read next (`lsof`); `decide` says which to stop and why. Nothing
-- here reads or signals a process: main.luau does (zz-arch skill: pure over texts, reads at the edge).
-- A process is stopped only on an explicit yes, when all of these hold:
--   - it is the user's, neither the reaper nor one of its ancestors, and neither a detached `git maintenance` / file-system
--     monitor nor anything below one (they are meant to outlive their parent);
--   - it is in scope: its working folder is under one of `roots` (the repository's main checkout, which holds every
--     worktree), or under one of `scratch` (this repository's own Claude session folders and the spec runner's temp
--     folders, named by prefix: another project's folders are not in scope);
--   - and one of:
--     MARKED: a program of TARGETS or INTERPRETERS (never a macOS application) that carries ZN_BOUNDED_DEADLINE (set by
--       `./zn run`) whose time passed more than `grace` seconds ago;
--     ORPHANED: its name is one of ORPHANABLE (the tool programs and interpreters, what a loop or a follow runs: `sleep`,
--       `tail`, `gh`, `grep`, ...) or it is a tool shell, every ancestor up to launchd (pid 1) is one of CHAIN (so no
--       terminal, session or app owns it), and it is older than `minAge`;
--     SESSION END: it is a tool shell of the ending session (`under`: a direct child of the session's `claude` process
--       whose command sources one of Claude Code's shell snapshots), whatever it is running: the shell and everything
--       below it are stopped (a loop runs in the shell itself, and its children are `sleep` and `gh`).
-- Anything not known (a folder that could not be read, an ancestor missing from the table) keeps the process.

local reap = {}

export type Proc = {
	pid: number,
	ppid: number,
	uid: number,
	age: number, -- seconds since it started
	cpu: number, -- CPU seconds used
	start: string, -- `ps lstart`, with the pid it names a process
	command: string, -- the arguments (never the environment: it can hold secrets)
	cwd: string?,
	deadline: string?, -- ZN_BOUNDED_DEADLINE, from `markers`
}

export type Options = {
	uid: number,
	now: number, -- epoch seconds
	minAge: number, -- seconds an orphan must have lived
	grace: number, -- seconds past its deadline that a marked process is given
	roots: { string }, -- folders a process's working folder must be under
	scratch: { string }, -- prefixes of this repository's Claude session folders and the spec runner's temp folders
	self: { number }, -- the reaper's pid and its ancestors
	under: number?, -- an ending session's process: its tool shells, and what runs below them, are leaks too
	sessionAnywhere: boolean, -- the session rule needs no folder in scope: the shells are the session's by ancestry (the default scope; an explicit --root keeps the folder test)
}

export type Target = { proc: Proc, why: string, tree: { Proc } }

reap.TARGETS = { lune = true, git = true, sh = true, bash = true, perl = true } :: { [string]: boolean }
reap.INTERPRETERS = {
	node = true,
	python = true,
	python3 = true,
	ruby = true,
	deno = true,
	bun = true,
	luau = true,
	rojo = true,
} :: { [string]: boolean }
reap.ORPHANABLE = {
	lune = true,
	git = true,
	sh = true,
	bash = true,
	perl = true,
	node = true,
	python = true,
	python3 = true,
	ruby = true,
	deno = true,
	bun = true,
	luau = true,
	rojo = true,
	sleep = true,
	tail = true,
	gh = true,
	grep = true,
	ugrep = true, -- Claude Code's tool shells run `grep` as `ugrep` and `find` as `bfs`
	bfs = true,
	watch = true,
	yes = true,
	caffeinate = true,
} :: { [string]: boolean }
reap.CHAIN = {
	ugrep = true,
	bfs = true,
	sleep = true,
	tail = true,
	gh = true,
	grep = true,
	watch = true,
	yes = true,
	caffeinate = true,
	node = true,
	python = true,
	python3 = true,
	lune = true,
	git = true,
	sh = true,
	bash = true,
	zsh = true,
	perl = true,
	env = true,
	["sandbox-exec"] = true,
} :: { [string]: boolean }

-- `[[dd-]hh:]mm:ss[.cc]` to seconds; nil when it is not one
function reap.seconds(text: string): number?
	local days, rest = string.match(text, "^(%d+)%-(.+)$")
	local d = if days then tonumber(days) :: number else 0
	local parts = {}
	for p in string.gmatch(rest or text, "[^:]+") do
		local n = tonumber(p)
		if n == nil then
			return nil
		end
		table.insert(parts, n)
	end
	if #parts < 2 or #parts > 3 then
		return nil
	end
	local total = 0
	for _, n in parts do
		total = total * 60 + n
	end
	return math.floor(total + d * 86400)
end

-- The processes of a `ps` listing, and the lines that are not one (a problem is named, never skipped silently).
function reap.parse(text: string): ({ Proc }, { string })
	local procs: { Proc } = {}
	local problems: { string } = {}
	for line in string.gmatch(text, "[^\n]+") do
		local pid, ppid, uid, etime, cpu, start, command = string.match(
			line,
			"^%s*(%d+)%s+(%d+)%s+(%d+)%s+(%S+)%s+(%S+)%s+(%a%a%a %a%a%a +%d+ [%d:]+ %d+)%s+(.*)$"
		)
		local age = if etime then reap.seconds(etime) else nil
		local used = if cpu then reap.seconds(cpu) else nil
		if pid and age and used then
			table.insert(procs, {
				pid = tonumber(pid) :: number,
				ppid = tonumber(ppid) :: number,
				uid = tonumber(uid) :: number,
				age = age,
				cpu = used,
				start = start :: string,
				command = command :: string,
			})
		else
			table.insert(problems, `unreadable ps line: {string.sub(line, 1, 80)}`)
		end
	end
	return procs, problems
end

-- The program's name: the first word of the command, without its folder or a login dash (`-/bin/zsh`).
function reap.name(command: string): string
	local first = string.match(command, "^%s*(%S+)") or ""
	return string.match((string.gsub(first, "^%-", "")), "([^/]*)$") or first
end

-- The command to show, cut at 100 characters.
function reap.shown(command: string): string
	local c = string.gsub(command, "%s+", " ")
	return if #c > 100 then string.sub(c, 1, 100) .. "..." else c
end

local function under(path: string, root: string): boolean
	local r = (string.gsub(root, "/+$", ""))
	return path == r or string.sub(path, 1, #r + 1) == r .. "/"
end

-- A scratch prefix names a folder (the next character is `/` or, for a worktree session's folder, `--`), or, when it ends
-- in a dot, the start of a folder name that a random suffix follows (`pickman-run.Xy12`)
local function underScratch(path: string, prefix: string): boolean
	if string.sub(prefix, -1) == "." then
		return string.sub(path, 1, #prefix) == prefix
			and string.match(string.sub(path, #prefix + 1), "^[%w]+/?") ~= nil
	end
	local rest = string.sub(path, #prefix + 1)
	return string.sub(path, 1, #prefix) == prefix
		and (rest == "" or string.sub(rest, 1, 1) == "/" or string.sub(rest, 1, 2) == "--")
end

local function inScope(cwd: string?, roots: { string }, scratch: { string }): boolean
	if cwd == nil or cwd == "" then
		return false
	end
	for _, root in roots do
		if root ~= "" and under(cwd, root) then
			return true
		end
	end
	for _, prefix in scratch do
		if prefix ~= "" and underScratch(cwd, prefix) then
			return true
		end
	end
	return false
end

-- A detached `git maintenance` and the file-system monitor are meant to outlive their parent
local function legitGit(p: Proc): boolean
	return reap.name(p.command) == "git"
		and (
			string.find(p.command, "maintenance", 1, true) ~= nil
			or string.find(p.command, "fsmonitor", 1, true) ~= nil
		)
end

-- A legit git, or any ancestor of the process up to launchd is one: the `gc`, `repack` and `pack-objects` a detached
-- maintenance starts are as legitimate as it is
local function underLegitGit(p: Proc, byPid: { [number]: Proc }): boolean
	local at: Proc? = p
	for _ = 1, 64 do
		if at == nil then
			return false
		end
		if legitGit(at) then
			return true
		end
		if at.ppid <= 1 then
			return false
		end
		at = byPid[at.ppid]
	end
	return false
end

-- ZN_BOUNDED_DEADLINE per pid, from `ps -axww -E -o pid=,command=`: the environment follows the arguments,
-- space-separated, so only the text after the arguments `parse` already has for that pid is read (a process whose
-- arguments merely spell `ZN_BOUNDED_DEADLINE=...` has no such variable, and one that changed between the two `ps`
-- calls is not read at all). Only this value is kept, never the rest of the environment. macOS withholds the
-- environment of its own binaries (`sleep`, `perl`, `sh`), so a marked process is found only when it is not one.
function reap.markers(text: string, procs: { Proc }): { [number]: string }
	local byPid: { [number]: Proc } = {}
	for _, p in procs do
		byPid[p.pid] = p
	end
	local out: { [number]: string } = {}
	for line in string.gmatch(text, "[^\n]+") do
		local pid, rest = string.match(line, "^%s*(%d+)%s+(.*)$")
		local proc = if pid then byPid[tonumber(pid) :: number] else nil
		if proc and rest and string.sub(rest, 1, #proc.command) == proc.command then
			local deadline =
				string.match(string.sub(rest, #proc.command + 1), "[ \t]ZN_BOUNDED_DEADLINE=(%d+)")
			if deadline then
				out[proc.pid] = deadline
			end
		end
	end
	return out
end

-- The ending session's process: the nearest ancestor of the reaper (`self`, nearest first) that is `claude`; nil when
-- there is none, and then a session end stops nothing it owned (the orphan rule finds it later)
function reap.sessionRoot(procs: { Proc }, self: { number }): number?
	local byPid: { [number]: Proc } = {}
	for _, p in procs do
		byPid[p.pid] = p
	end
	for _, pid in self do
		local p = byPid[pid]
		if p ~= nil and reap.name(p.command) == "claude" then
			return pid
		end
	end
	return nil
end

-- Claude Code runs each Bash command in a shell that sources one of its shell snapshots (`<config>/shell-snapshots/`;
-- the config folder is `~/.claude` unless CLAUDE_CONFIG_DIR says otherwise, so only the last folder is matched)
function reap.isToolShell(command: string): boolean
	return string.find(command, "/shell-snapshots/", 1, true) ~= nil
end

-- Whether every ancestor up to launchd is one of CHAIN; false when one is not, or is missing from the table
local function ownerless(p: Proc, byPid: { [number]: Proc }): boolean
	local seen = 0
	local at = p.ppid
	while at ~= 1 do
		seen += 1
		local parent = byPid[at]
		if parent == nil or seen > 64 or not reap.CHAIN[reap.name(parent.command)] then
			return false
		end
		at = parent.ppid
	end
	return true
end

-- Pids whose working folder `decide` needs: the user's processes that could be a leak by name, as a tool shell, or by a deadline
function reap.wantCwd(procs: { Proc }, opts: Options): { number }
	local want: { number } = {}
	for _, p in procs do
		if p.uid == opts.uid and not table.find(opts.self, p.pid) then
			if p.deadline ~= nil or reap.ORPHANABLE[reap.name(p.command)] or reap.isToolShell(p.command) then
				table.insert(want, p.pid)
			end
		end
	end
	return want
end

local function treeOf(p: Proc, procs: { Proc }): { Proc }
	local out: { Proc } = {}
	local inTree: { [number]: boolean } = { [p.pid] = true }
	local grew = true
	while grew do
		grew = false
		for _, q in procs do
			if not inTree[q.pid] and inTree[q.ppid] and q.pid > 1 then
				inTree[q.pid] = true
				table.insert(out, q)
				grew = true
			end
		end
	end
	return out
end

-- The leaks among `procs` (each with `cwd` filled in where it could be read), each with why and its descendants.
function reap.decide(procs: { Proc }, opts: Options): { Target }
	local byPid: { [number]: Proc } = {}
	for _, p in procs do
		byPid[p.pid] = p
	end
	local targets: { Target } = {}
	local taken: { [number]: boolean } = {}
	for _, p in procs do
		if p.pid <= 1 or p.uid ~= opts.uid or table.find(opts.self, p.pid) or underLegitGit(p, byPid) then
			continue
		end
		local scoped = inScope(p.cwd, opts.roots, opts.scratch)
		-- the session's own tool shell is the session's wherever it has been (a `mktemp -d` clone, `/tmp`): ownership is
		-- known by ancestry, and the folder scope is only a proxy for ownership when the owner is gone
		local sessionShell = opts.under ~= nil
			and p.ppid == opts.under
			and reap.isToolShell(p.command)
			and (scoped or opts.sessionAnywhere)
		if not scoped and not sessionShell then
			continue
		end
		local name = reap.name(p.command)
		local why: string? = nil
		local deadline = p.deadline
		local stamp = if deadline and string.match(deadline, "^%d%d%d%d%d%d%d%d%d%d$")
			then tonumber(deadline)
			else nil
		if
			scoped
			and stamp ~= nil
			and stamp + opts.grace < opts.now
			and (reap.TARGETS[name] or reap.INTERPRETERS[name])
			and string.find(p.command, ".app/Contents/", 1, true) == nil
		then
			why = `past its ./zn run deadline by {opts.now - stamp}s`
		elseif sessionShell then
			why = "started by the session that is ending"
		elseif
			scoped
			and (reap.ORPHANABLE[name] or reap.isToolShell(p.command))
			and p.age >= opts.minAge
			and ownerless(p, byPid)
		then
			why = "orphaned (its parent is gone)"
		end
		if why ~= nil then
			table.insert(targets, { proc = p, why = why, tree = treeOf(p, procs) })
			taken[p.pid] = true
		end
	end
	-- a target inside another target's tree is stopped with that tree: it is listed once
	local kept: { Target } = {}
	for _, t in targets do
		local nested = false
		for _, other in targets do
			if other ~= t then
				for _, d in other.tree do
					if d.pid == t.proc.pid then
						nested = true
					end
				end
			end
		end
		if not nested then
			table.insert(kept, t)
		end
	end
	return kept
end

-- The default scope, or the one the caller named (pure, so the facts the edge reads are the only thing it adds): `main` is
-- the repository's main checkout (it holds every worktree), `uid` the user's id, `temp` the physical user temp folder
-- (`/private/var/folders/.../T`, or "" when unknown), `roots` the `--root` folders given. An explicit root replaces every
-- default scope, the session rule's reach included (`sessionAnywhere`), which keeps the end-to-end check safe; with none, the
-- folder is this repository's main checkout, this repository's own Claude session folders (named by the path slug Claude
-- derives from the main checkout: `/` and `.` become `-`) and the runner's temp folders.
export type Scope = { roots: { string }, scratch: { string }, sessionAnywhere: boolean }
function reap.scope(main: string, uid: string, temp: string, roots: { string }): Scope
	if #roots > 0 then
		return { roots = roots, scratch = {}, sessionAnywhere = false }
	end
	local slug = string.gsub(main, "[/%.]", "-")
	local scratch: { string } = { `/private/tmp/claude-{uid}/{slug}` }
	if temp ~= "" then
		table.insert(scratch, `{temp}/claude-{uid}/{slug}`)
		table.insert(scratch, `{temp}/pickman-run.`)
		table.insert(scratch, `{temp}/pickman-guard.`)
	end
	return { roots = { main }, scratch = scratch, sessionAnywhere = true }
end

-- The refusals of the command line (nil when the options are fine): the combinations that turn the reaper on a live
-- machine. `underIsClaude` says the `--under` pid is a `claude` process. Without a `--root` the reaper has its default
-- scope, so it takes no `--under` that is not a session's own process and no age below a minute.
export type Args = { roots: { string }, under: number?, underIsClaude: boolean, minAge: number, home: string }
function reap.checkOptions(a: Args): string?
	for _, root in a.roots do
		local trimmed = (string.gsub(root, "/+$", ""))
		if string.sub(root, 1, 1) ~= "/" or trimmed == "" or trimmed == (string.gsub(a.home, "/+$", "")) then
			return `--root {root} must be an absolute folder that is neither / nor the home folder`
		end
		if string.find("/" .. root .. "/", "/%.%./") then
			return `--root {root} must not contain ..`
		end
	end
	local explicit = #a.roots > 0
	if a.under ~= nil then
		if a.under <= 1 then
			return `--under {a.under} is no session's process`
		end
		if not a.underIsClaude and not explicit then
			return `--under {a.under} is not a claude process: name a --root to use it on other processes`
		end
	end
	if a.minAge < 60 and not explicit then
		return `--min-age {a.minAge} is under 60 seconds: name a --root to use it`
	end
	return nil
end

local function human(seconds: number): string
	if seconds >= 3600 then
		return string.format("%dh%02dm", seconds // 3600, (seconds % 3600) // 60)
	end
	return string.format("%dm%02ds", seconds // 60, seconds % 60)
end

-- One line per leak, for the person who ran the reaper or reads the log.
function reap.line(t: Target, verb: string): string
	local p = t.proc
	local more = if #t.tree > 0 then ` +{#t.tree} child(ren)` else ""
	return `reap: {verb} pid {p.pid}{more}, age {human(p.age)}, cpu {human(p.cpu)}, {t.why}, cwd {p.cwd or "?"}: {reap.shown(
		p.command
	)}`
end

return reap
