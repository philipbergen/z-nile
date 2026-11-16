--!strict
-- c0123 AC3: the allow-listed environment, the rule both readers of z-nile/lib/cleanenv.list apply. The shell reader
-- (z-nile/lib/cleanenv.sh, for the entry scripts and ac.sh) and the Lune reader (z-nile/lib/cleanenv.luau, for the
-- runner) are fed one planted environment and must agree; each refuses an unknown entry or an empty value; the result
-- is idempotent; a restarted shell that is still dirty refuses instead of looping. What the run puts on PATH is
-- believed by where it is, never by a variable or by how its path reads: its canonical path must lie inside a folder
-- the runner registered for this run (tests-run.lock/folders), so a leftover, a folder made in .cache/.tmp and another
-- spelling of either are dropped and keep no fence name. A moved HOME may not make git read another file through a ~
-- path. Shells run in fixtures only, as bash -p, under `env -i`; the fixture is removed after every case, passed or not.
local cleanenv = require("@znile/lib/cleanenv")
local fence = require("@tests/lib/fence")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local home = fixture.physical(".") :: string
local root = string.match(home, "^(.*)/[^/]+$") :: string
local base = `{home}/.cache/c0123-cleanenv`
local dirs = `{base}/dirs`
local HOME = process.env.HOME or "/nonexistent"
local facts = cleanenv.facts() -- the account's home, git config and the trusted checkout, from the passwd database and this file's place
local list = fs.readFile(`{root}/z-nile/lib/cleanenv.list`)

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

local function spec(): cleanenv.Spec
	local parsed, problem = cleanenv.parse(list, facts.home)
	if not parsed then
		error(problem)
	end
	return parsed
end

local DUMP = table.concat({
	"#!/bin/bash -p",
	'. z-nile/lib/cleanenv.sh && pickman_clean_env "$0" "$@" || exit 9',
	'compgen -e | LC_ALL=C sort | while read -r n; do printf "%s=%s\\n" "$n" "${!n}"; done',
	"",
}, "\n")

-- The folders a case puts on PATH, all real (the cleaner resolves them). REG is the folder the runner registered for
-- this run: the run's bin and guard folders, stubs, a stub folder that is a link out of it, a folder with an ordinary
-- name, and one that matches two globs sit inside it. LOOSE holds what a spec or an agent leaves behind: the same names,
-- registered by nobody.
local REG = `{dirs}/reg`
local RUNBIN = `{REG}/pickman-run.AAAA/bin`
local GUARD = `{REG}/pickman-guard.BBBB`
local STUB = `{REG}/pickman-stub.r`
local LINK = `{REG}/pickman-stub.link`
local PLAIN = `{REG}/ordinary`
local BOTH = `{REG}/pickman-guard.q/pickman-stub.r`
local LOOSE = `{dirs}/loose`
local LRUN = `{LOOSE}/pickman-run.LLLL/bin`
local LGUARD = `{LOOSE}/pickman-guard.LLLL`
local LSTUB = `{LOOSE}/pickman-stub.LLLL`
local REGISTRY = `{base}/.cache/tests-run.lock/folders`

-- The run that holds a registered folder, as the runner records it in `<folder>/.pickman-owner`: a pid, a tab and the
-- process's start id. This spec's own process is the live owner of every folder it registers (no process is started,
-- nothing waits).
local function trim(text: string): string
	return (string.gsub(text, "%s+$", ""))
end
local ME = trim(process.exec("/bin/sh", { "-p", "-c", "echo $PPID" }).stdout)
local function startOf(pid: string): string
	return trim(process.exec("/usr/bin/perl", { "-e", cleanenv.STARTID, pid }).stdout)
end
local MYID = startOf(ME)
local function ownedBy(dir: string, pid: string?, id: string?)
	fs.writeDir(dir)
	fs.writeFile(`{dir}/.pickman-owner`, `{pid or ME}\t{id or MYID}\n`)
end

-- One fixture repository holding a copy of the shell reader, the folders above, the runner's registry naming REG and a
-- dump script. Built again for every case and removed after it (`guarded`).
local ready = false
local function setUp()
	if ready then
		return
	end
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	fs.writeDir(`{base}/z-nile/lib`)
	for _, name in { "cleanenv.sh", "cleanenv.list" } do
		fs.writeFile(`{base}/z-nile/lib/{name}`, fs.readFile(`{root}/z-nile/lib/{name}`))
	end
	for _, d in { RUNBIN, GUARD, STUB, PLAIN, BOTH, LRUN, LGUARD, LSTUB } do
		fs.writeDir(d)
	end
	process.exec("ln", { "-s", "/usr/bin", LINK })
	fs.writeFile(`{base}/dump.sh`, DUMP)
	process.exec("chmod", { "+x", `{base}/dump.sh` })
	process.exec("git", { "init", "-q", "-b", "main", base })
	fs.writeDir(`{base}/.cache/tests-run.lock`)
	fs.writeFile(REGISTRY, `{REG}\n`)
	for _, d in { REG, LOOSE, `{base}/.cache/.tmp` } do
		ownedBy(d)
	end
	ready = true
end

local function tearDown()
	ready = false
	if fs.isDir(base) then
		fs.removeDir(base)
	end
end

-- A case that leaves nothing behind, whether it passes or not: the fixture holds proof-named folders that must never
-- outlive the case (a standing one on a later PATH would be a run that never was).
local function guarded(body: () -> ()): () -> ()
	return function()
		local ok, err = pcall(body)
		tearDown()
		if not ok then
			error(err, 0)
		end
	end
end

-- The Lune reader's facts for the fixture checkout: the real account facts, the registry the fixture holds.
local function fixtureFacts(): cleanenv.Facts
	local out = table.clone(facts)
	out.registered = cleanenv.registered({ base, facts.trust })
	return out
end

-- Runs `script` (a file of the fixture) with exactly `env` (nothing inherited: the shell is started through /usr/bin/env -i).
local function inShell(script: string, env: { [string]: string }, dir: string?): fixture.Result
	setUp()
	local args = { "-i" }
	for name, value in env do
		table.insert(args, `{name}={value}`)
	end
	table.insert(args, script)
	return fixture.exec(dir or base, "/usr/bin/env", args)
end

-- The environment a case plants: every kind the list distinguishes.
local function planted(extra: { [string]: string }?): { [string]: string }
	local env: { [string]: string } = {
		HOME = HOME,
		LANG = "C",
		LC_ALL = "C",
		TERM = "dumb",
		TMPDIR = "/tmp",
		PATH = `/tmp/evil:{RUNBIN}:{STUB}:{GUARD}:{LINK}:{PLAIN}:{LRUN}:{LSTUB}:{BOTH}:{LGUARD}:/opt/other:/usr/bin`,
		CDPATH = ".:/tmp",
		BASH_ENV = "/tmp/nope",
		SHELLOPTS = "verbose",
		GIT_EXEC_PATH = "/tmp/evil",
		GIT_CONFIG_COUNT = "1",
		GIT_CEILING_DIRECTORIES = "/c",
		GIT_SSH_COMMAND = "evil",
		FOO_UNLISTED = "1",
		XDG_CONFIG_HOME = "/x/xdg",
		GIT_CONFIG_GLOBAL = "/x/gc",
		PICKMAN_TEST_JAIL = "none",
		ZN_TOP = "/z",
		CLAUDE_PROJECT_DIR = "/proj",
		CLAUDE_ENV_FILE = "/envfile",
		CLAUDE_CODE_OTHER = "x",
		["BASH_FUNC_git%%"] = "() { echo hijack; }",
		["BASH_FUNC_command%%"] = "() { echo hijack; }",
	}
	if extra then
		for k, v in extra do
			env[k] = v
		end
	end
	return env
end

local function parseLines(text: string): { [string]: string }
	local out: { [string]: string } = {}
	for line in string.gmatch(text, "[^\n]+") do
		local k, v = string.match(line, "^([^=]+)=(.*)$")
		if k and v then
			out[k] = v
		end
	end
	return out
end

local function luau(env: { [string]: string }): ({ [string]: string }, boolean)
	setUp()
	return cleanenv.clean(env, spec(), fixtureFacts(), cleanenv.resolve)
end

-- Whether this volume treats `.CACHE` and `.cache` as one name (APFS and NTFS do by default, ext4 does not).
local function foldsCase(): boolean
	setUp()
	return fs.isDir(string.upper(REG)) and string.upper(REG) ~= REG
end

return t.spec("c0123 the allow-listed environment", function(rawIt)
	local function it(name: string, body: () -> ())
		rawIt(name, guarded(body))
	end

	it("the shell reader and the Lune reader agree on the planted environments", function()
		for name, env in
			{
				live = planted(),
				noproof = planted({ PATH = `/tmp/evil:{STUB}:/usr/bin` }),
				forged = planted({
					PICKMAN_FENCE_REAL_GIT = "/nonexistent",
					PATH = `{LINK}:/tmp/evil:/usr/bin`,
				}),
				overlap = planted({ PATH = `{BOTH}:{BOTH}:{STUB}:/usr/bin` }),
				-- leftovers: proof- and stub-named folders nobody registered, with the fence names a forger sets
				leftover = planted({
					PICKMAN_FENCE_REAL_GIT = "/nonexistent",
					PATH = `{LGUARD}:{LRUN}:{LSTUB}:/usr/bin`,
				}),
				-- the same folders spelled other ways: dot segments, doubled slashes, a relative name found only through CDPATH
				spelled = planted({
					CDPATH = REG,
					PATH = `{REG}/./pickman-stub.r:{REG}//pickman-guard.BBBB:{REG}/ordinary/../pickman-stub.r:pickman-stub.r:{LOOSE}/../loose/pickman-stub.LLLL:/usr/bin`,
				}),
				homeMoved = planted({ HOME = "/nonexistent/evil", XDG_CONFIG_HOME = "/nonexistent/evil" }),
				none = { HOME = HOME },
			} :: { [string]: { [string]: string } }
		do
			local r = inShell("./dump.sh", env)
			if not r.ok then
				error(`{name}: {r.stderr}{r.stdout}`)
			end
			local shellSide = parseLines(r.stdout)
			local luauSide = luau(env)
			if name == "spelled" then
				-- the Lune reader resolves a relative name from where it runs, never through the caller's CDPATH (here
				-- the fixture also holds a .cache, which a followed CDPATH would find first)
				local viaCdpath = cleanenv.resolve(".cache", { CDPATH = base })
				t.expect(viaCdpath).toBe(`{home}/.cache`)
			end
			-- bash adds its own bookkeeping
			for _, own in { "PWD", "SHLVL", "_", "OLDPWD" } do
				shellSide[own] = nil
				luauSide[own] = nil
			end
			for k, v in luauSide do
				if shellSide[k] ~= v then
					error(`{name}: {k}: shell {shellSide[k]}, Lune {v}`)
				end
			end
			for k, v in shellSide do
				if luauSide[k] ~= v then
					error(`{name}: {k}: shell {v}, Lune {luauSide[k]}`)
				end
			end
		end
	end)

	it(
		"what the list drops is dropped, and PATH is the run's registered folders then the fixed directories",
		function()
			local out, dirty = luau(planted())
			t.expect(dirty).toBe(true)
			for _, gone in
				{
					"CDPATH",
					"BASH_ENV",
					"SHELLOPTS",
					"GIT_EXEC_PATH",
					"FOO_UNLISTED",
					"XDG_CONFIG_HOME",
					"CLAUDE_CODE_OTHER", -- only the two names the SessionStart hook reads are admitted, not the family
					"BASH_FUNC_git%%",
					"BASH_FUNC_command%%",
				}
			do
				if out[gone] ~= nil then
					error(`{gone} survived`)
				end
			end
			-- the fence's own state passes while a folder of the run proves a run is live
			t.expect(out.GIT_CONFIG_COUNT).toBe("1")
			t.expect(out.GIT_CEILING_DIRECTORIES).toBe("/c")
			t.expect(out.PICKMAN_TEST_JAIL).toBe("none")
			t.expect(out.ZN_TOP).toBe("/z")
			t.expect(out.CLAUDE_PROJECT_DIR).toBe("/proj")
			t.expect(out.CLAUDE_ENV_FILE).toBe("/envfile")
			local fixed = table.concat(spec().path, ":")
			-- registered folders in the order given, once each; a link out of the run folder, an ordinary name and the
			-- unregistered leftovers are dropped
			t.expect(out.PATH).toBe(`{RUNBIN}:{STUB}:{GUARD}:{BOTH}:{fixed}`)
			-- the caller's HOME and XDG_CONFIG_HOME choose neither PATH nor git's global config
			t.expect(out.GIT_CONFIG_GLOBAL).toBe(facts.gitConfigGlobal)
			local moved = luau(
				planted({ HOME = "/nonexistent/evil", GIT_CONFIG_GLOBAL = "/nonexistent/evil/.gitconfig" })
			)
			t.expect((string.find(moved.PATH :: string, "/nonexistent/evil", 1, true))).toBe(nil)
			t.expect(moved.HOME).toBe("/nonexistent/evil") -- the value passes (specs set it); nothing is derived from it
			t.expect(moved.GIT_CONFIG_GLOBAL).toBe(facts.gitConfigGlobal)
		end
	)

	it("a forged fence marker gains nothing: no unregistered folder believed, no fence name kept", function()
		setUp()
		-- Lune reader: proof- and stub-named folders that nobody registered, the forged marker, ssh and config
		local env = planted({
			PICKMAN_FENCE_REAL_GIT = "/nonexistent",
			PATH = `{LGUARD}:{LRUN}:{LSTUB}:/elsewhere/pickman-stub.x:/elsewhere/pickman-run.z/bin:/usr/bin`,
			GIT_SSH_COMMAND = "evil",
			GIT_CONFIG_COUNT = "1",
			GIT_CONFIG_KEY_0 = "core.fsmonitor",
		})
		local out = luau(env)
		t.expect(out.PATH).toBe(table.concat(spec().path, ":"))
		for _, gone in
			{ "GIT_SSH_COMMAND", "GIT_CONFIG_COUNT", "GIT_CONFIG_KEY_0", "GIT_CEILING_DIRECTORIES" }
		do
			if out[gone] ~= nil then
				error(`{gone} survived a forged marker`)
			end
		end
		-- shell reader, end to end: a git and a perl in a loose stub folder, the forged marker, ssh and config
		local evil = `{LOOSE}/pickman-stub.evil`
		fs.writeDir(evil)
		for _, tool in { "git", "perl" } do
			fs.writeFile(`{evil}/{tool}`, "#!/bin/sh\necho EVIL\n")
			process.exec("chmod", { "+x", `{evil}/{tool}` })
		end
		fs.writeFile(
			`{base}/probe.sh`,
			table.concat({
				"#!/bin/bash -p",
				'. z-nile/lib/cleanenv.sh && pickman_clean_env "$0" "$@" || exit 9',
				'echo "GIT=$(type -P git) PERL=$(type -P perl)"',
				'echo "SSH=${GIT_SSH_COMMAND-unset} COUNT=${GIT_CONFIG_COUNT-unset} KEY=${GIT_CONFIG_KEY_0-unset}"',
				'echo "PATH=$PATH"',
				"",
			}, "\n")
		)
		process.exec("chmod", { "+x", `{base}/probe.sh` })
		local forged = {
			HOME = HOME,
			PICKMAN_FENCE_REAL_GIT = "/nonexistent",
			PATH = `{evil}:{LGUARD}:{LRUN}:/usr/bin:/bin`,
			GIT_SSH_COMMAND = "evil",
			GIT_CONFIG_COUNT = "1",
			GIT_CONFIG_KEY_0 = "core.fsmonitor",
		}
		local r = inShell("./probe.sh", forged)
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		t.expect(has(r.stdout, "EVIL")).toBe(false)
		t.expect(has(r.stdout, "SSH=unset COUNT=unset KEY=unset")).toBe(true)
		t.expect(has(r.stdout, evil)).toBe(false)
		t.expect(has(r.stdout, LGUARD)).toBe(false)
		-- the control: the same loose folder IS believed once the runner's registry names it (whoever can write the
		-- registry in the checkout's .cache is the accepted class), and its proof then passes the fence names
		fs.writeFile(REGISTRY, `{REG}\n{LOOSE}\n`)
		local control = inShell("./probe.sh", forged)
		t.expect(has(control.stdout, evil)).toBe(true)
		t.expect(has(control.stdout, "SSH=evil COUNT=1 KEY=core.fsmonitor")).toBe(true)
		fs.writeFile(REGISTRY, `{REG}\n`)
		-- not through a link either: a stub-named link to a folder outside the registered one is dropped from PATH
		local viaLink = inShell("./probe.sh", { HOME = HOME, PATH = `{LINK}:/usr/bin:/bin` })
		t.expect(viaLink.ok).toBe(true)
		t.expect(has(viaLink.stdout, LINK)).toBe(false)
	end)

	it(
		"a folder is kept only inside a folder the runner registered, whatever it is called and however its path is spelled",
		function()
			setUp()
			local fixed = table.concat(spec().path, ":")
			-- .cache/.tmp: anyone's mktemp can make a folder with any name there, and so can a spec in a .cache of its own
			local tmpStub = `{base}/.cache/.tmp/pickman-stub.t`
			local oddCache = `{base}/.CACHE/.tmp/T/.cache/pickman-stub.y`
			fs.writeDir(tmpStub)
			fs.writeDir(oddCache)
			local env = planted({ PATH = `{tmpStub}:{oddCache}:/usr/bin`, PICKMAN_FENCE_REAL_GIT = "/x" })
			t.expect(parseLines(inShell("./dump.sh", env).stdout).PATH).toBe(fixed)
			t.expect(luau(env).PATH).toBe(fixed)
			-- the runner registers the run's folder, resolved, in tests-run.lock/folders; the folder inside it is kept
			fs.writeFile(REGISTRY, `{REG}\n{base}/.cache/.tmp\n`)
			local inTmp = planted({ PATH = `{tmpStub}:/usr/bin` })
			t.expect(parseLines(inShell("./dump.sh", inTmp).stdout).PATH).toBe(`{tmpStub}:{fixed}`)
			t.expect(luau(inTmp).PATH).toBe(`{tmpStub}:{fixed}`)
			fs.writeFile(REGISTRY, `{REG}\n`)
			-- standing proof folders under the home's .cache, as a spec that never cleaned up would leave them: with the
			-- forged config and ssh names no launcher passes them on; registered, the same folders are the run's own
			local leftover = planted({
				PATH = `{LGUARD}:{LRUN}:/usr/bin`,
				GIT_CONFIG_COUNT = "1",
				GIT_CONFIG_KEY_0 = "core.fsmonitor",
				GIT_SSH_COMMAND = "evil",
			})
			local shellLeft = parseLines(inShell("./dump.sh", leftover).stdout)
			t.expect(shellLeft.PATH).toBe(fixed)
			t.expect(shellLeft.GIT_SSH_COMMAND).toBe(nil)
			t.expect(shellLeft.GIT_CONFIG_COUNT).toBe(nil)
			local luauLeft = luau(leftover)
			t.expect(luauLeft.PATH).toBe(fixed)
			t.expect(luauLeft.GIT_SSH_COMMAND).toBe(nil)
			fs.writeFile(REGISTRY, `{LOOSE}\n`)
			local shellOwn = parseLines(inShell("./dump.sh", leftover).stdout)
			t.expect(shellOwn.PATH).toBe(`{LGUARD}:{LRUN}:{fixed}`)
			t.expect(shellOwn.GIT_SSH_COMMAND).toBe("evil")
			t.expect(luau(leftover).GIT_SSH_COMMAND).toBe("evil")
			-- a registry line that is no folder or is relative (the one below is a real folder of the fixture, from where the
			-- script runs) names nothing; a registry in a dot-folder is not read
			fs.writeFile(REGISTRY, `dirs/reg\n/nonexistent/reg\n`)
			local stubOnly = planted({ PATH = `{STUB}:/usr/bin` })
			t.expect(parseLines(inShell("./dump.sh", stubOnly).stdout).PATH).toBe(fixed)
			t.expect(luau(stubOnly).PATH).toBe(fixed)
			fs.writeFile(REGISTRY, `{REG}\n/nonexistent/reg\n`)
			t.expect(parseLines(inShell("./dump.sh", stubOnly).stdout).PATH).toBe(`{STUB}:{fixed}`)
			fs.writeFile(REGISTRY, "")
			fs.writeDir(`{base}/.cache/.cache/tests-run.lock`)
			fs.writeFile(`{base}/.cache/.cache/tests-run.lock/folders`, `{REG}\n`)
			t.expect(parseLines(inShell("./dump.sh", stubOnly).stdout).PATH).toBe(fixed)
			t.expect(luau(stubOnly).PATH).toBe(fixed)
			fs.writeFile(REGISTRY, `{REG}\n`)
			-- on a volume that folds letter case (APFS, NTFS) the same folder has many spellings: the filesystem's own
			-- spelling decides, in the registry and in PATH (the shell's pwd -P keeps the caller's)
			if foldsCase() then
				local upLoose = `{string.upper(LOOSE)}/pickman-stub.LLLL`
				local upTmp = `{string.upper(base)}/.CACHE/.TMP/pickman-stub.t`
				local cased = planted({ PATH = `{upLoose}:{upTmp}:/usr/bin`, PICKMAN_FENCE_REAL_GIT = "/x" })
				t.expect(parseLines(inShell("./dump.sh", cased).stdout).PATH).toBe(fixed)
				t.expect(luau(cased).PATH).toBe(fixed)
				-- a registered folder spelled in other letters, and an entry of it spelled in other letters: kept, once, as stored
				fs.writeFile(REGISTRY, `{string.upper(REG)}\n`)
				local registeredCased = planted({ PATH = `{string.upper(STUB)}:{STUB}:/usr/bin` })
				t.expect(parseLines(inShell("./dump.sh", registeredCased).stdout).PATH).toBe(`{STUB}:{fixed}`)
				t.expect(luau(registeredCased).PATH).toBe(`{STUB}:{fixed}`)
			end
		end
	)

	it("a registered folder is believed only while the run that registered it still holds it", function()
		setUp()
		local fixed = table.concat(spec().path, ":")
		local env = planted({
			PATH = `{GUARD}:{STUB}:/usr/bin`,
			PICKMAN_FENCE_REAL_GIT = "/x",
			GIT_CONFIG_COUNT = "1",
			GIT_SSH_COMMAND = "evil",
		})
		-- what each reader makes of the registry as it stands: the PATH it builds and whether the fence names survived
		local function seen(): (string, string, string?, string?)
			local shellSide = parseLines(inShell("./dump.sh", env).stdout)
			local luauSide = luau(env)
			return shellSide.PATH :: string,
				luauSide.PATH :: string,
				shellSide.GIT_SSH_COMMAND,
				luauSide.GIT_SSH_COMMAND
		end
		local function expectKept()
			local sp, lp, ss, ls = seen()
			t.expect(sp).toBe(`{GUARD}:{STUB}:{fixed}`)
			t.expect(lp).toBe(`{GUARD}:{STUB}:{fixed}`)
			t.expect(ss).toBe("evil")
			t.expect(ls).toBe("evil")
		end
		local function expectDropped(what: string)
			local sp, lp, ss, ls = seen()
			if sp ~= fixed or lp ~= fixed or ss ~= nil or ls ~= nil then
				error(`{what}: still believed (shell {sp} / {tostring(ss)}, Lune {lp} / {tostring(ls)})`)
			end
		end
		expectKept() -- the live owner
		-- a killed run: its registry, lock and folders stay and its pid is gone (a planted dead pid, no process is killed)
		local dead = trim(process.exec("/bin/sh", { "-p", "-c", "echo $$" }).stdout)
		ownedBy(REG, dead, MYID)
		expectDropped("a dead owner")
		-- a reused pid: the pid is alive, but it started at another time than the run that recorded it
		ownedBy(REG, ME, "1.1")
		expectDropped("a reused pid")
		-- perl's own variables cannot say the pid still holds: PERL5OPT that makes perl die reads as "cannot tell", which
		-- would leave a reused pid holding if perl ran in the caller's environment (inline use has no restart to save it)
		t.expect(cleanenv.holds(REG, { PERL5OPT = "-MNoSuchModuleC0123", PERL5LIB = "/nonexistent" }))
			.toBe(false)
		local inline = fixture.exec(base, "/usr/bin/env", {
			"-i",
			`HOME={HOME}`,
			"PERL5OPT=-MNoSuchModuleC0123",
			`PATH={GUARD}:/usr/bin:/bin`,
			"/bin/bash",
			"-p",
			"-c",
			'. z-nile/lib/cleanenv.sh; pickman_clean_env; printf "PATH=%s\\n" "$PATH"',
		})
		t.expect(inline.ok).toBe(true)
		t.expect(has(inline.stdout, GUARD)).toBe(false)
		-- a record that names pid 0 (the caller's own process group) holds nothing
		ownedBy(REG, "0", MYID)
		expectDropped("an owner record naming pid 0")
		ownedBy(REG, ME, "1.1")
		-- no owner record, or one that names no pid
		fs.removeFile(`{REG}/.pickman-owner`)
		expectDropped("no owner record")
		fs.writeFile(`{REG}/.pickman-owner`, "not-a-pid\t\n")
		expectDropped("a malformed owner record")
		-- a process this one may not signal (the first process of the system): Operation not permitted reads as alive, as
		-- the runner's fence.alive does inside the jail, and its start id decides
		local one = startOf("1")
		if one ~= "" then
			ownedBy(REG, "1", one)
			expectKept()
			ownedBy(REG, "1", "1.1")
			expectDropped("another start id on a pid this process may not signal")
		end
		-- an owner with no start id recorded (an older runner) leaves a live pid holding, as fence.holds does
		ownedBy(REG, ME, "")
		expectKept()
	end)

	it(
		"the three copies of the start-id program are one text, and the shell reader holds the same decision",
		function()
			local function flat(text: string): string
				return (string.gsub(string.gsub(text, "%s+", " "), "^ ", ""))
			end
			local shellText = fs.readFile(`{root}/z-nile/lib/cleanenv.sh`)
			local embedded = string.match(shellText, "\n_pickman_startid='(.-)'\n_pickman_perl=")
			t.expect(embedded ~= nil).toBe(true)
			t.expect(flat((string.gsub(embedded :: string, "'\\''", "'")))).toBe(flat(cleanenv.STARTID))
			t.expect(flat(cleanenv.STARTID)).toBe(flat(fence.STARTED))
		end
	)

	it(
		"the runner registers exactly its own run folder, once: the live registry has one line, TMPDIR",
		function()
			-- every spec runs under a live run; read what the real writer wrote (a file under .cache, readable in the jail)
			local live = fs.readFile(`{home}/.cache/tests-run.lock/folders`)
			local lines: { string } = {}
			for line in string.gmatch(live, "[^\n]+") do
				table.insert(lines, line)
			end
			t.expect(#lines).toBe(1)
			local tmp = trim(process.env.TMPDIR or "")
			t.expect(tmp ~= "").toBe(true)
			t.expect(cleanenv.resolve(lines[1] :: string)).toBe(cleanenv.resolve(tmp))
			-- and that folder is the run's own, not a place agents share
			t.expect(string.find(lines[1] :: string, "/pickman%-run%.[^/]+$") ~= nil).toBe(true)
			t.expect(cleanenv.holds(lines[1] :: string)).toBe(true)
		end
	)

	it(
		"a PATH entry is believed by where it is: the link out of the run folder and the ordinary name are dropped, an entry that matches two globs is kept once",
		function()
			local env = planted({ PATH = `{LINK}:{PLAIN}:{BOTH}:{BOTH}:{STUB}:/usr/bin` })
			local out, dirty = luau(env)
			t.expect(dirty).toBe(true)
			t.expect(out.PATH).toBe(`{BOTH}:{STUB}:{table.concat(spec().path, ":")}`)
			local again, stillDirty = luau(out)
			t.expect(stillDirty).toBe(false)
			t.expect(again.PATH).toBe(out.PATH)
			-- a run's bin or guard folder is the proof that a run is live; a stub alone is not
			local stubOnly = luau(planted({ PATH = `{STUB}:/usr/bin` }))
			t.expect(stubOnly.GIT_CONFIG_COUNT).toBe(nil)
			t.expect(stubOnly.PATH).toBe(`{STUB}:{table.concat(spec().path, ":")}`)
		end
	)

	it("the result is clean, and cleaning it again changes nothing", function()
		local once = luau(planted())
		local again, dirty = luau(once)
		t.expect(dirty).toBe(false)
		for k, v in once do
			t.expect(again[k]).toBe(v)
		end
	end)

	it(
		"an unknown entry, or an entry with an empty value, is refused by both readers, never skipped",
		function()
			setUp()
			for _, extra in { "keep FOO\n", "allow\n", "allow \n", "path \n", "internal \n", "proof \n" } do
				local parsed, problem = cleanenv.parse(list .. extra, facts.home)
				if parsed ~= nil or not has(problem or "", "unknown entry") then
					error(`the Lune reader accepted {string.format("%q", extra)}`)
				end
				fs.writeFile(`{base}/z-nile/lib/cleanenv.list`, list .. extra)
				local r = inShell("./dump.sh", { HOME = HOME })
				fs.writeFile(`{base}/z-nile/lib/cleanenv.list`, list)
				if r.ok or not has(r.stderr, "unknown entry") then
					error(`the shell reader accepted {string.format("%q", extra)}: {r.stdout}{r.stderr}`)
				end
			end
		end
	)

	it(
		"a moved HOME may not make git read another file through a ~ path in the account's own config",
		function()
			-- pure: the Lune reader refuses when the pinned config holds a ~ path and HOME is not the account's
			local withTilde: cleanenv.Facts = {
				home = facts.home,
				gitConfigGlobal = "/x/.gitconfig",
				trust = facts.trust,
				tildeLine = "path = ~/.gitconfig.local",
				registered = {},
			}
			t.expect(cleanenv.refusal({ HOME = "/nonexistent/evil" }, withTilde) ~= nil).toBe(true)
			t.expect(cleanenv.refusal({ HOME = facts.home }, withTilde)).toBe(nil)
			t.expect(cleanenv.refusal({ HOME = "/nonexistent/evil" }, facts)).toBe(nil)
			-- shell: a copy of the reader whose account home is a fixture with such a config
			setUp()
			local acct = `{base}/acct`
			fs.writeDir(`{acct}/z-nile/lib`)
			process.exec("git", { "init", "-q", "-b", "main", acct })
			fs.writeDir(`{acct}/home`)
			fs.writeFile(`{acct}/home/.gitconfig`, "[include]\n\tpath = ~/.gitconfig.local\n")
			for _, name in { "cleanenv.sh", "cleanenv.list" } do
				fs.writeFile(`{acct}/z-nile/lib/{name}`, fs.readFile(`{base}/z-nile/lib/{name}`))
			end
			local text = fs.readFile(`{acct}/z-nile/lib/cleanenv.sh`)
			local patched = string.gsub(
				text,
				'acct_home=%$%(eval "echo ~%$acct"%) || acct_home=',
				`acct_home={acct}/home`
			)
			t.expect(patched ~= text).toBe(true)
			fs.writeFile(`{acct}/z-nile/lib/cleanenv.sh`, patched)
			fs.writeFile(`{acct}/dump.sh`, DUMP)
			process.exec("chmod", { "+x", `{acct}/dump.sh` })
			-- a ~ path that is only a data file (ignore patterns) does not refuse
			fs.writeFile(`{acct}/home/.gitconfig`, "[core]\n\texcludesfile = ~/.gitignore_global\n")
			local data = inShell("./dump.sh", { HOME = "/nonexistent/evil" }, acct)
			t.expect(data.ok).toBe(true)
			fs.writeFile(`{acct}/home/.gitconfig`, "[include]\n\tpath = ~/.gitconfig.local\n")
			local moved = inShell("./dump.sh", { HOME = "/nonexistent/evil" }, acct)
			t.expect(moved.ok).toBe(false)
			t.expect(has(moved.stderr, "~ path")).toBe(true)
			local same = inShell("./dump.sh", { HOME = `{acct}/home` }, acct)
			t.expect(same.ok).toBe(true)
		end
	)

	it(
		"a script started in a dirty environment restarts in the clean one, and a restart that is still dirty refuses",
		function()
			setUp()
			fs.writeFile(
				`{base}/probe2.sh`,
				table.concat({
					"#!/bin/bash -p",
					'. z-nile/lib/cleanenv.sh && pickman_clean_env "$0" "$@" || exit 9',
					'echo "ARGS=$*"',
					'echo "FOO=${FOO_UNLISTED-unset} CDPATH=${CDPATH-unset} CLEANED=${PICKMAN_CLEANED-unset}"',
					'echo "GIT=$(type -P git)"',
					"",
				}, "\n")
			)
			fixture.exec(base, "chmod", { "+x", "probe2.sh" })
			local env = planted()
			env.PATH = `/tmp/evil:/usr/bin:/bin`
			local args = { "-i" }
			for k, v in env do
				table.insert(args, `{k}={v}`)
			end
			for _, a in { "./probe2.sh", "one", "two words" } do
				table.insert(args, a)
			end
			local r = fixture.exec(base, "/usr/bin/env", args)
			if not r.ok then
				error(r.stderr .. r.stdout)
			end
			t.expect(has(r.stdout, "ARGS=one two words")).toBe(true)
			t.expect(has(r.stdout, "FOO=unset CDPATH=unset")).toBe(true)
			t.expect(has(r.stdout, "CLEANED=unset")).toBe(true)
			-- a restart marker equal to the shell's own pid on a still-dirty shell refuses instead of looping
			fs.writeFile(
				`{base}/loop.sh`,
				table.concat({
					"#!/bin/bash -p",
					". z-nile/lib/cleanenv.sh",
					"export PICKMAN_CLEANED=$$ FOO_UNLISTED=1",
					'pickman_clean_env "$0" "$@"; echo "rc=$?"',
					"",
				}, "\n")
			)
			fixture.exec(base, "chmod", { "+x", "loop.sh" })
			local loop = fixture.exec(base, "/usr/bin/env", { "-i", `HOME={HOME}`, "./loop.sh" })
			t.expect(has(loop.stdout, "rc=1")).toBe(true)
			t.expect(has(loop.stderr, "still not the allow-list")).toBe(true)
		end
	)

	it(
		"with no script to restart only a privileged shell is trusted; a shell that ran BASH_ENV refuses",
		function()
			setUp()
			fs.writeFile(`{base}/benv.sh`, "true\n")
			-- not -p, BASH_ENV set: the file already ran
			local r = fixture.exec(base, "/usr/bin/env", {
				"-i",
				`BASH_ENV={base}/benv.sh`,
				"/bin/bash",
				"-c",
				'. z-nile/lib/cleanenv.sh; pickman_clean_env; echo "rc=$?"',
			})
			t.expect(has(r.stdout, "rc=1")).toBe(true)
			-- inline use from a shell that is not privileged: an imported echo would decide the account's home
			local inlinePlain = fixture.exec(base, "/usr/bin/env", {
				"-i",
				"BASH_FUNC_echo%%=() { builtin echo /tmp/evilhome; }",
				"/bin/bash",
				"-c",
				'. z-nile/lib/cleanenv.sh; pickman_clean_env; printf "rc=%s PATH=%s\\n" $? "$PATH"',
			})
			t.expect(has(inlinePlain.stdout, "rc=1")).toBe(true)
			t.expect(has(inlinePlain.stdout, "evilhome")).toBe(false)
			-- privileged and inline: a function carrier cannot be dropped, so it refuses; plain names are unset in place
			local carrier = fixture.exec(base, "/usr/bin/env", {
				"-i",
				"BASH_FUNC_git%%=() { echo hijack; }",
				"/bin/bash",
				"-p",
				"-c",
				'. z-nile/lib/cleanenv.sh; pickman_clean_env; echo "rc=$?"',
			})
			t.expect(has(carrier.stdout, "rc=1")).toBe(true)
			local plain = fixture.exec(base, "/usr/bin/env", {
				"-i",
				"GIT_NAMESPACE=x",
				"CDPATH=/tmp",
				"/bin/bash",
				"-p",
				"-c",
				'. z-nile/lib/cleanenv.sh; pickman_clean_env; echo "rc=$? ${CDPATH-unset}"',
			})
			t.expect(has(plain.stdout, "rc=0 unset")).toBe(true)
		end
	)

	-- last: whatever the cases above left in the fixture (guard and bin folders nobody registered, planted stubs) must
	-- be gone, passed or failed, so a later PATH never meets a proof folder of a run that never was
	it("the fixture of every case above is gone", function()
		t.expect(fs.isDir(base)).toBe(false)
		t.expect(fs.isDir(dirs)).toBe(false)
	end)
end)
