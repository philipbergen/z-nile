--!strict
-- c0191 AC3: which processes are leaks (the pure rules of `./zn reap`), over `ps` text and a table.
local reap = require("@znile/engine/reap")
local t = require("@tests/lib/t")

local NOW = 1793500000
local ME = 501
local SCRATCH = "/private/tmp/claude-501/-Users-me-code-pickman"
local TEMP = "/private/var/folders/ab/T"

local function p(over: { [string]: any }): reap.Proc
	local base: reap.Proc = {
		pid = 1000,
		ppid = 1,
		uid = ME,
		age = 3600,
		cpu = 3500,
		start = "Sat Oct 31 13:00:00 2026",
		command = "lune run p2.luau check x",
		cwd = `{SCRATCH}/sess/scratchpad/cr4`,
	}
	for k, v in over do
		(base :: any)[k] = if v == false then nil else v -- false: the field is unknown
	end
	return base
end

local function opts(over: { [string]: any }?): reap.Options
	local base: reap.Options = {
		uid = ME,
		now = NOW,
		minAge = 60,
		grace = 5,
		roots = { "/Users/me/code/pickman" },
		scratch = { SCRATCH, `{TEMP}/pickman-run.`, `{TEMP}/pickman-guard.` },
		self = { 7, 8 },
		under = nil,
		sessionAnywhere = true,
	}
	local extra: { [string]: any } = over or {}
	for k, v in extra do
		(base :: any)[k] = v
	end
	return base
end

local function pids(targets: { reap.Target }): { number }
	local out = {}
	for _, x in targets do
		table.insert(out, x.proc.pid)
	end
	table.sort(out)
	return out
end

local function leaks(procs: { reap.Proc }, o: reap.Options?): { number }
	return pids(reap.decide(procs, o or opts()))
end

return t.spec("which processes are leaks", function(it)
	it(
		"AC3: ps lines parse, with every etime and cpu spelling, and a bad line is named, not skipped",
		function()
			local text = table.concat({
				"72711     1   501 14:02:11 840:12.40 Sat Oct 31 13:00:00 2026     lune run p2.luau check a b",
				"    9  7346   501    05:09     0:01.00 Sun Nov  1 03:35:12 2026 /bin/sh -c x",
				"   10     1     0 05-17:14:35  83:38.18 Mon Oct 26 11:28:38 2026 /sbin/launchd",
				"not a ps line",
			}, "\n")
			local procs, problems = reap.parse(text)
			t.expect(#procs).toBe(3)
			t.expect(procs[1].pid).toBe(72711)
			t.expect(procs[1].age).toBe(14 * 3600 + 2 * 60 + 11)
			t.expect(procs[1].cpu).toBe(840 * 60 + 12)
			t.expect(procs[1].start).toBe("Sat Oct 31 13:00:00 2026")
			t.expect(procs[1].command).toBe("lune run p2.luau check a b")
			t.expect(procs[2].age).toBe(5 * 60 + 9)
			t.expect(procs[3].age).toBe(5 * 86400 + 17 * 3600 + 14 * 60 + 35)
			t.expect(#problems).toBe(1)
			t.expect(string.find(problems[1], "not a ps line", 1, true) ~= nil).toBe(true)
		end
	)

	it(
		"AC3: markers reads the deadline from the environment, never from the arguments, and keeps nothing else",
		function()
			local procs = {
				p({ pid = 100, command = "lune run x" }),
				p({ pid = 101, command = "sh -c y" }),
				p({ pid = 102, command = "grep ZN_BOUNDED_DEADLINE=1793400000 file" }),
				p({ pid = 103, command = "sh -c ZN_BOUNDED_DEADLINE=1000000000 sleep 9" }),
				p({ pid = 104, command = "perl -e sleep" }),
			}
			local m = reap.markers(
				table.concat({
					"  100 lune run x SECRET_TOKEN=hunter2 ZN_BOUNDED_DEADLINE=1793400000 HOME=/Users/me",
					"  101 sh -c y HOME=/Users/me",
					"  102 grep ZN_BOUNDED_DEADLINE=1793400000 file HOME=/Users/me",
					"  103 sh -c ZN_BOUNDED_DEADLINE=1000000000 sleep 9 PATH=/bin",
					"  104 perl -e other ZN_BOUNDED_DEADLINE=1793400000",
					"  105 unknown-pid ZN_BOUNDED_DEADLINE=1793400000",
				}, "\n"),
				procs
			)
			t.expect(m[100]).toBe("1793400000")
			t.expect(m[101]).toBe(nil)
			t.expect(m[102]).toBe(nil) -- in the arguments
			t.expect(m[103]).toBe(nil) -- in the arguments of a shell: the decoys of the end-to-end check
			t.expect(m[104]).toBe(nil) -- the arguments differ from the first listing: the process changed
			t.expect(m[105]).toBe(nil) -- not in the first listing
		end
	)

	it(
		"AC3: the incident: an orphaned lune probe in a session scratch folder, 14 hours old, is a leak",
		function()
			local shim = p({ pid = 72700, ppid = 1 })
			local real =
				p({ pid = 72711, ppid = 72700, command = "/opt/homebrew/bin/lune run p2.luau check x" })
			local targets = reap.decide({ shim, real }, opts())
			t.expect(pids(targets)).toEqual({ 72700 })
			t.expect(#targets[1].tree).toBe(1)
			t.expect(targets[1].tree[1].pid).toBe(72711)
			t.expect(targets[1].why).toBe("orphaned (its parent is gone)")
		end
	)

	it("AC3: a process with a live owner is kept: a terminal, a session or an app above it", function()
		local procs = {
			p({ pid = 1000, ppid = 2000 }),
			p({ pid = 2000, ppid = 3000, command = "-/bin/zsh" }),
			p({ pid = 3000, ppid = 1, command = "claude", cwd = "/x" }),
			p({ pid = 1001, ppid = 4000 }),
			p({ pid = 4000, ppid = 1, command = "/usr/bin/login -pf me" }),
		}
		t.expect(leaks(procs)).toEqual({})
	end)

	it(
		"AC3: a chain of tool processes up to launchd is ownerless; a missing ancestor keeps the process",
		function()
			local chain = {
				p({ pid = 1000, ppid = 1001 }),
				p({ pid = 1001, ppid = 1002, command = "sh -c lune run x" }),
				p({ pid = 1002, ppid = 1, command = "perl -e wd" }),
			}
			t.expect(leaks(chain)).toEqual({ 1002 })
			t.expect(leaks({ p({ pid = 1000, ppid = 555 }) })).toEqual({})
		end
	)

	it("AC3: age, owner, name and folder each keep a process when they say no", function()
		t.expect(leaks({ p({ age = 59 }) })).toEqual({})
		t.expect(leaks({ p({ age = 60 }) })).toEqual({ 1000 })
		t.expect(leaks({ p({ uid = 0 }) })).toEqual({})
		t.expect(leaks({ p({ command = "tmux: server" }) })).toEqual({})
		t.expect(leaks({ p({ command = "vim notes.md" }) })).toEqual({})
		t.expect(leaks({ p({ cwd = "/Users/me/Documents" }) })).toEqual({})
		t.expect(leaks({ p({ cwd = false }) })).toEqual({}) -- unknown is not yes
		t.expect(leaks({ p({ cwd = "/Users/me/code/pickman-other/x" }) })).toEqual({})
		t.expect(leaks({ p({ cwd = "/Users/me/code/pickman/.worktree/R1/z-nile" }) })).toEqual({ 1000 })
	end)

	it(
		"AC3: the scratch scope is this repository's own session folders and the runner's temp folders, by prefix",
		function()
			local function at(cwd: string, o: reap.Options?): { number }
				return leaks({ p({ cwd = cwd }) }, o)
			end
			t.expect(at(`{SCRATCH}/sess/scratchpad`)).toEqual({ 1000 })
			-- a worktree session's folder: the main checkout's slug, then `--worktree-…`
			t.expect(at("/private/tmp/claude-501/-Users-me-code-pickman--worktree-prep-x/sess/scratchpad"))
				.toEqual({ 1000 })
			-- another project, a repository whose name only starts the same, another user's, a folder named like the pattern
			t.expect(at("/private/tmp/claude-501/-Users-me-code-other/sess/scratchpad")).toEqual({})
			t.expect(at("/private/tmp/claude-501/-Users-me-code-pickman-other/sess/scratchpad")).toEqual({})
			t.expect(at("/private/tmp/claude-502/-Users-me-code-pickman/sess/scratchpad")).toEqual({})
			t.expect(at("/Users/me/code/claude-2/x")).toEqual({})
			-- the runner's own temp folders, with their random suffix
			t.expect(at(`{TEMP}/pickman-run.Xy12/bin`)).toEqual({ 1000 })
			t.expect(at(`{TEMP}/pickman-run.`)).toEqual({})
			t.expect(at(`{TEMP}/pickman-runner/x`)).toEqual({})
			t.expect(at(`{TEMP}/other.Xy12`)).toEqual({})
			-- an explicit root replaces every default
			t.expect(at(`{SCRATCH}/sess`, opts({ scratch = {}, roots = { "/fixture" } }))).toEqual({})
			t.expect(at("/fixture/in", opts({ scratch = {}, roots = { "/fixture" } }))).toEqual({ 1000 })
		end
	)

	it("AC3: the reaper and its ancestors are never targets", function()
		local procs = { p({ pid = 7 }), p({ pid = 8 }), p({ pid = 9 }) }
		t.expect(leaks(procs)).toEqual({ 9 })
	end)

	it(
		"AC3: detached git maintenance, the file-system monitor and everything below them are not leaks",
		function()
			local procs = {
				p({ pid = 1, ppid = 0, command = "launchd", cwd = false }),
				p({
					pid = 2000,
					command = "/usr/libexec/git-core/git maintenance run --auto --quiet --detach",
				}),
				p({ pid = 2001, command = "git fsmonitor--daemon run --detach" }),
				p({ pid = 2002, command = "git log --all" }),
				p({ pid = 2003, ppid = 2000, command = "git gc --auto --quiet" }),
				p({
					pid = 2004,
					ppid = 2003,
					command = "git pack-objects --stdout",
					deadline = tostring(NOW - 99),
				}),
				p({ pid = 2005, command = "git maintenance run", deadline = tostring(NOW - 99), ppid = 9999 }),
			}
			t.expect(leaks(procs)).toEqual({ 2002 })
		end
	)

	it(
		"AC3: the deadline rule: past by more than 5 s, ten digits, a tool or an interpreter, in scope",
		function()
			local owner = p({ pid = 9000, ppid = 1, command = "claude", cwd = "/x" })
			local function marked(over: { [string]: any }): reap.Proc
				local base: { [string]: any } = { command = "lune run probe.luau", ppid = 9000 }
				for k, v in over do
					base[k] = v
				end
				return p(base)
			end
			local late = marked({ pid = 3000, deadline = tostring(NOW - 6) })
			local early = marked({ pid = 3001, deadline = tostring(NOW - 5) })
			local future = marked({ pid = 3002, deadline = tostring(NOW + 30) })
			local short = marked({ pid = 3003, deadline = "1" })
			local away = marked({ pid = 3004, deadline = tostring(NOW - 99), cwd = "/Users/me" })
			local app = marked({
				pid = 3005,
				deadline = tostring(NOW - 99),
				command = "/Applications/Studio.app/Contents/MacOS/node helper",
			})
			local node = marked({ pid = 3006, deadline = tostring(NOW - 99), command = "node server.js" })
			local editor = marked({ pid = 3007, deadline = tostring(NOW - 99), command = "vim notes.md" })
			local targets =
				reap.decide({ late, early, future, short, away, app, node, editor, owner }, opts())
			t.expect(pids(targets)).toEqual({ 3000, 3006 })
			t.expect(targets[1].why).toBe("past its ./zn run deadline by 6s")
		end
	)

	it(
		"AC3: a session that is ending takes its own tool shells, and what runs in and below them, and no one else's",
		function()
			local claude = p({ pid = 9000, ppid = 1, command = "claude", cwd = "/x" })
			local function shell(pid: number, ppid: number, cwd: string | boolean): reap.Proc
				return p({
					pid = pid,
					ppid = ppid,
					command = "/bin/zsh -c source /Users/me/.claude/shell-snapshots/snapshot-zsh-1.sh && eval 'x'",
					cwd = cwd,
				})
			end
			-- a loop runs in the tool shell itself; its children are sleep and gh, and a probe's tool is lune
			local loop = shell(9100, 9000, `{SCRATCH}/sess/scratchpad`)
			local sleeper = p({ pid = 4000, ppid = 9100, command = "sleep 30", age = 1 })
			local gh = p({ pid = 4001, ppid = 9100, command = "gh pr view 138", age = 1 })
			local probe = p({ pid = 4002, ppid = 9100, age = 1 })
			local deeper = p({ pid = 4003, ppid = 4002, command = "sh -c probe", age = 1 })
			local editor = p({ pid = 4004, ppid = 9100, command = "node editor.js", age = 1 })
			-- not the session's tool shells
			local mcp = p({ pid = 9200, ppid = 9000, command = "sh -c mcp-server", cwd = "/x" })
			local mcpChild = p({ pid = 4005, ppid = 9200, age = 1 })
			local odd =
				p({ pid = 9300, ppid = 9000, command = "/bin/zsh -c something else", cwd = `{SCRATCH}/sess` })
			local oddChild = p({ pid = 4006, ppid = 9300, age = 1 })
			local elsewhereShell = shell(9400, 9000, "/Users/me/Documents")
			local elsewhereChild = p({ pid = 4007, ppid = 9400, age = 1 })
			local other = p({ pid = 8000, ppid = 1, command = "claude", cwd = "/x" })
			local otherShell = shell(8100, 8000, `{SCRATCH}/sess`)
			local otherChild = p({ pid = 4008, ppid = 8100, age = 1 })
			local all = {
				claude,
				loop,
				sleeper,
				gh,
				probe,
				deeper,
				editor,
				mcp,
				mcpChild,
				odd,
				oddChild,
				elsewhereShell,
				elsewhereChild,
				other,
				otherShell,
				otherChild,
			}
			local ending = reap.decide(all, opts({ under = 9000 }))
			-- the session's own shells by ancestry, wherever they have been (one `cd`ed to Documents)
			t.expect(pids(ending)).toEqual({ 9100, 9400 })
			t.expect(ending[1].why).toBe("started by the session that is ending")
			t.expect(#ending[1].tree).toBe(5)
			-- an explicit root replaces the default scope, the session rule's reach included: the shell outside it is kept
			t.expect(pids(reap.decide(all, opts({ under = 9000, sessionAnywhere = false }))))
				.toEqual({ 9100 })
			-- without a session end the live shells are owned, and nothing is a leak
			t.expect(leaks(all)).toEqual({})
		end
	)

	it(
		"AC3: after the session is gone, its orphaned tool shell and what it left are leaks, one listing per tree",
		function()
			local function shell(pid: number, ppid: number): reap.Proc
				return p({
					pid = pid,
					ppid = ppid,
					command = "/bin/zsh -c source /Users/me/.claude/shell-snapshots/snapshot-zsh-1.sh && eval 'x'",
				})
			end
			local procs = {
				shell(9100, 1),
				p({ pid = 4000, ppid = 9100, command = "sleep 30" }),
				p({ pid = 4001, ppid = 9100, command = "gh pr view 138" }),
				-- a monitor's pipeline whose shell was killed: each end is its own orphan
				p({ pid = 5000, ppid = 1, command = "tail -f full.log" }),
				p({ pid = 5001, ppid = 1, command = "ugrep -G --ignore-files --line-buffered DONE" }),
				-- an orphaned shell whose folder is outside this repository's scope may be another project's: kept (the session
				-- end, which knows by ancestry whose it is, takes the same shell)
				p({
					pid = 9500,
					ppid = 1,
					command = "/bin/zsh -c source /Users/me/.claude/shell-snapshots/snapshot-zsh-2.sh && eval 'x'",
					cwd = `{TEMP}/tmp.VVx/repo/z-nile`,
				}),
				p({ pid = 5002, ppid = 1, command = "tmux: server" }),
				p({ pid = 5003, ppid = 1, command = "/bin/zsh -l" }),
			}
			local targets = reap.decide(procs, opts())
			t.expect(pids(targets)).toEqual({ 5000, 5001, 9100 })
			for _, x in targets do
				if x.proc.pid == 9100 then
					t.expect(#x.tree).toBe(2)
				end
			end
		end
	)

	it("AC3: the ending session's process is the nearest ancestor of the reaper that is claude", function()
		local procs = {
			p({ pid = 9000, ppid = 1, command = "/Users/me/.local/bin/claude --resume" }),
			p({ pid = 9100, ppid = 9000, command = "-/bin/zsh" }),
			p({ pid = 9200, ppid = 9100, command = "sh -c hook" }),
			p({ pid = 9300, ppid = 9200, command = "lune run main" }),
			p({ pid = 7000, ppid = 1, command = "claude" }),
		}
		t.expect(reap.sessionRoot(procs, { 9300, 9200, 9100, 9000 })).toBe(9000)
		t.expect(reap.sessionRoot(procs, { 9300, 9200 })).toBe(nil)
		t.expect(reap.sessionRoot({}, { 9300 })).toBe(nil)
	end)

	it(
		"AC3: wantCwd asks only for the user's candidates: by name, as a tool shell, or by deadline",
		function()
			local procs = {
				p({ pid = 10 }),
				p({ pid = 11, command = "tail -f full.log" }),
				p({ pid = 12, command = "lune run y", deadline = "1793400000" }),
				p({ pid = 13, command = "vim y", deadline = "1793400000" }),
				p({ pid = 14, uid = 0 }),
				p({ pid = 15, command = "vim notes.md" }),
				p({
					pid = 16,
					command = "/bin/zsh -c source /Users/me/.claude/shell-snapshots/snapshot-zsh-1.sh && eval 'x'",
				}),
				p({ pid = 7 }),
			}
			t.expect(reap.wantCwd(procs, opts())).toEqual({ 10, 11, 12, 13, 16 })
		end
	)

	it("AC3: a target inside another target's tree is listed once, under the tree's root", function()
		local procs = {
			p({ pid = 5000, ppid = 1 }),
			p({ pid = 5001, ppid = 5000 }),
			p({ pid = 5002, ppid = 5001, command = "sleep 5" }),
		}
		local targets = reap.decide(procs, opts())
		t.expect(pids(targets)).toEqual({ 5000 })
		t.expect(#targets[1].tree).toBe(2)
	end)

	it(
		"AC3: the default scope is built from facts, and reaches the incident; an explicit root replaces all of it",
		function()
			-- no --root: the main checkout, this repository's own Claude folders (the slug turns / and . into -), the runner's
			local scope = reap.scope("/Users/me/code/pick.man", "501", "/private/var/folders/ab/T", {})
			t.expect(scope.roots).toEqual({ "/Users/me/code/pick.man" })
			t.expect(scope.scratch).toEqual({
				"/private/tmp/claude-501/-Users-me-code-pick-man",
				"/private/var/folders/ab/T/claude-501/-Users-me-code-pick-man",
				"/private/var/folders/ab/T/pickman-run.",
				"/private/var/folders/ab/T/pickman-guard.",
			})
			t.expect(scope.sessionAnywhere).toBe(true)
			-- a --root: only that root, no scratch, and the session rule needs the folder too
			local explicit = reap.scope("", "501", "/private/var/folders/ab/T", { "/fixture/in" })
			t.expect(explicit.roots).toEqual({ "/fixture/in" })
			t.expect(explicit.scratch).toEqual({})
			t.expect(explicit.sessionAnywhere).toBe(false)
			-- no known temp folder: the system one only
			t.expect(#reap.scope("/m", "501", "", {}).scratch).toBe(1)
			-- the incident, through the scope's own output (not hand-made options): an orphaned probe in a worktree session's
			-- scratch folder, and a session's shell in a mktemp clone
			local main = "/Users/me/code/pickman"
			local def = reap.scope(main, "501", "/private/var/folders/ab/T", {})
			local o = opts({
				roots = def.roots,
				scratch = def.scratch,
				sessionAnywhere = def.sessionAnywhere,
				under = 9000,
			})
			local probe = p({
				pid = 72700,
				ppid = 1,
				cwd = "/private/tmp/claude-501/-Users-me-code-pickman--worktree-prep-x/sess/scratchpad/cr4",
			})
			local shell = p({
				pid = 9100,
				ppid = 9000,
				command = "/bin/zsh -c source /Users/me/.claude/shell-snapshots/snapshot-zsh-1.sh && eval 'x'",
				cwd = "/private/var/folders/ab/T/tmp.VVx/repo/z-nile",
			})
			local claude = p({ pid = 9000, ppid = 1, command = "claude", cwd = "/x" })
			t.expect(leaks({ probe, shell, claude }, o)).toEqual({ 9100, 72700 })
			local fixed = reap.scope("", "501", "/private/var/folders/ab/T", { "/fixture/in" })
			local o2 =
				opts({ roots = fixed.roots, scratch = fixed.scratch, sessionAnywhere = false, under = 9000 })
			t.expect(leaks({ probe, shell, claude }, o2)).toEqual({})
		end
	)

	it(
		"AC3: the options that would turn the reaper on a live machine are refused, and the safe forms are not",
		function()
			local function args(over: { [string]: any }): reap.Args
				local base: { [string]: any } =
					{ roots = {}, under = nil, underIsClaude = false, minAge = 60, home = "/Users/me" }
				for k, v in over do
					base[k] = v
				end
				return base :: any
			end
			-- refused, each naming the option
			local refused: { { over: { [string]: any }, says: string } } = {
				{ over = { under = 1 }, says = "--under 1" },
				{ over = { under = 0, roots = { "/fixture" } }, says = "--under 0" },
				{ over = { under = 4242 }, says = "--under 4242 is not a claude process" },
				{ over = { minAge = 0 }, says = "--min-age 0" },
				{ over = { minAge = 59 }, says = "--min-age 59" },
				{ over = { roots = { "/" } }, says = "--root /" },
				{ over = { roots = { "" } }, says = "--root " },
				{ over = { roots = { "relative/dir" } }, says = "--root relative/dir" },
				{ over = { roots = { "/Users/me" } }, says = "--root /Users/me" },
				{ over = { roots = { "/Users/me/" } }, says = "--root /Users/me/" },
				{ over = { roots = { "/fixture/../etc" } }, says = "must not contain .." },
			}
			for _, c in refused do
				local why = reap.checkOptions(args(c.over))
				if why == nil or string.find(why, c.says, 1, true) == nil then
					error(`expected a refusal naming "{c.says}", got {tostring(why)}`, 0)
				end
			end
			-- accepted: the defaults, a session's own process, and the check's explicit root with a short age and any pid
			t.expect(reap.checkOptions(args({}))).toBe(nil)
			t.expect(reap.checkOptions(args({ under = 4242, underIsClaude = true }))).toBe(nil)
			t.expect(reap.checkOptions(args({ roots = { "/fixture/in" }, minAge = 0, under = 4242 })))
				.toBe(nil)
			t.expect(reap.checkOptions(args({ minAge = 60 }))).toBe(nil)
		end
	)

	it(
		"AC3: the report line carries pid, age, cpu, reason, folder and command, cut at 100 characters",
		function()
			local target = reap.decide({ p({ pid = 72711 }) }, opts())[1]
			local line = reap.line(target, "stopped")
			for _, part in
				{
					"stopped pid 72711",
					"age 1h00m",
					"cpu 58m20s",
					"orphaned",
					"cwd /private/tmp/claude-501/",
					"lune run p2.luau check x",
				}
			do
				if not string.find(line, part, 1, true) then
					error(`missing {part} in: {line}`, 0)
				end
			end
			local long =
				reap.line({ proc = p({ command = string.rep("x", 300) }), why = "w", tree = {} }, "stopped")
			t.expect(#long < 400).toBe(true)
		end
	)
end)
