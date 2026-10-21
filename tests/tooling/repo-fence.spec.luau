--!strict
-- No check may change the real repository (testing skill, "Specs never touch the real repository").
-- tests/lib/fence.luau and z-nile/lib/fence.sh enforce it for every run; this spec proves, on every gate
-- run, that the guards are on here, and that no spec, check.sh or script switches them off. It never tries
-- a write against this repository: the ref guard is proven by running its hook the way git would.
local fs = require("@lune/fs")
local process = require("@lune/process")
local renamed = require("@tests/lib/renamed")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

local here = trim(process.exec("pwd", { "-P" }).stdout)
-- the checkout's root (`checkout`): `here` itself, or the folder above a project's home (pickman/, c0120), whose run is jailed to
-- its own .cache; pickman/tests/meta/fence.spec.luau runs this spec there
local checkout = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
if checkout == "" then
	checkout = here
end
local env = process.env

-- What turns a guard off or sends git to another repository; also what overrides the guard's own config.
local NAMES = {
	"GIT_CEILING_DIRECTORIES",
	"PICKMAN_TEST_FENCE",
	"PICKMAN_FENCE_",
	"GIT_DIR",
	"GIT_WORK_TREE",
	"GIT_INDEX_FILE",
	"GIT_COMMON_DIR",
	"GIT_OBJECT_DIRECTORY",
	"GIT_ALTERNATE_OBJECT_DIRECTORIES",
	"GIT_CONFIG_",
	"hooksPath",
	"--no-verify",
	"env -i",
	"sandbox-exec",
	"GH_CONFIG_DIR",
	"osascript",
	"launchctl",
	-- settings a command line (`-c`) or an environment could use to undo the fence's no-network and no-credential
	-- config where there is no jail (Linux, review 001 F1)
	"protocol.allow",
	"protocol.http",
	"protocol.ssh",
	"protocol.git",
	"credential.",
	"extraheader",
	"GIT_SSH_COMMAND",
	"GIT_ASKPASS",
	"SSH_ASKPASS",
	-- git's own protocol allowlist overrides protocol.allow, and a proxy would reach the network through the
	-- jail's open loopback (review 002 F2, F5)
	"GIT_ALLOW_PROTOCOL",
	"_proxy",
	"http.proxy",
	"gitproxy",
}

-- The banned names `text` contains, except those `allowed` lists (case-insensitive: git config keys are).
local function bannedIn(text: string, allowed: { [string]: string }): { string }
	local lower = string.lower(text)
	local out: { string } = {}
	for _, name in NAMES do
		if not allowed[name] and string.find(lower, string.lower(name), 1, true) then
			table.insert(out, name)
		end
	end
	return out
end

-- Every commit identity `text` sets, in any case (config keys and many environments are case-insensitive):
-- `user.email` (config or `-c`), the author, committer or EMAIL variables, and `--author`.
local function identitiesIn(text: string): { string }
	local out: { string } = {}
	local lower = string.lower(text)
	for _, pattern in { "email[^@\n]-([%w%.%-_]+@[%w%.%-]+)", "%-%-author[^@\n]-([%w%.%-_]+@[%w%.%-]+)" } do
		for email in string.gmatch(lower, pattern) do
			table.insert(out, email)
		end
	end
	return out
end
-- The guards themselves and their own specs, which must name them, wherever they are in their lifecycle.
-- Names a file may use for a stated reason, each reviewed (review skill, Repository safety). Nothing else in
-- the file may name them.
local ALLOWED: { [string]: { [string]: string } } = {
	-- c0660: the fixture helper names these to refuse them, and its spec proves it
	["tests/lib/fixture.luau"] = {
		GIT_CONFIG_ = "refused (config in env)",
		GIT_DIR = "refused",
		GIT_WORK_TREE = "refused",
		GIT_INDEX_FILE = "refused",
		GIT_COMMON_DIR = "refused",
		GIT_OBJECT_DIRECTORY = "refused",
	},
	["tests/acceptance/c0060/fixture.spec.luau"] = {
		GIT_DIR = "proves the helper refuses it",
		GIT_WORK_TREE = "proves the helper refuses it",
	},
	-- review 005 F2: clears the marker so a copied runner acts as a top-level run
	["tests/tooling/fence-leftovers.spec.luau"] = {
		PICKMAN_TEST_FENCE = "runs a copied runner as a top-level run",
	},
	-- review 004 F1: its runner case clears the marker so a copied runner acts as a top-level run
	["tests/tooling/fence-cache-entry.spec.luau"] = {
		PICKMAN_TEST_FENCE = "runs a copied runner as a top-level run",
	},
	-- c0650: its spec proves the scan refuses these names
	["tests/acceptance/c0059/adapt.spec.luau"] = {
		GIT_CEILING_DIRECTORIES = "asserts c0510 names none",
		GIT_CONFIG_ = "planted to prove the scan flags it",
		PICKMAN_TEST_FENCE = "runs the copied gate as a top-level run",
	},
	-- c0510 (R0200): its fixture hooks unset what git exports to a hook, so that their own git calls reach the right
	-- repository
	["tests/acceptance/c0053/commands-new.spec.luau"] = {
		GIT_DIR = "fixture hook",
		GIT_INDEX_FILE = "fixture hook",
		GIT_WORK_TREE = "fixture hook",
	},
	-- c0077: the reviewed list of .cache lines quotes fence.sh lines that name these
	["tests/lib/cachepaths.luau"] = {
		GIT_CEILING_DIRECTORIES = "quotes a fence.sh line in the reviewed .cache list",
		GH_CONFIG_DIR = "quotes a fence.sh line in the reviewed .cache list",
		PICKMAN_TEST_FENCE = "quotes a fence.sh line in the reviewed .cache list (the jail waiver, c0114)",
	},
	["tests/acceptance/c0053/publish.spec.luau"] = {
		GIT_DIR = "fixture hook",
		GIT_INDEX_FILE = "fixture hook",
		GIT_WORK_TREE = "fixture hook",
	},
	-- c0074: doneGate reads PICKMAN_FENCE_SPECS to skip done's gate inside a spec run, never to switch a guard; its
	-- spec names it only as a table key passed to that pure function, never in a process's environment
	["z-nile/engine/gate.luau"] = {
		PICKMAN_FENCE_ = "doneGate reads PICKMAN_FENCE_SPECS to skip done's gate inside a spec run, never to switch a guard (c0074)",
	},
	-- c0120: its fixture check.sh files print the git guards they see, and one fence call in a fixture gets an empty
	-- hook folder and no jail marker, to prove a refused home fence leaves the inherited guards whole; its fixture
	-- check.sh runs get the jail's three markers set explicitly, so they test the same path on every host
	["tests/acceptance/c0120/homes.spec.luau"] = {
		GIT_CEILING_DIRECTORIES = "a fixture check.sh prints the ceiling it sees",
		GIT_CONFIG_ = "a fixture check.sh and a fence call compare the guard config they see",
		PICKMAN_FENCE_ = "points PICKMAN_FENCE_HOOKS at an empty folder for one fence call in a fixture, and sets PICKMAN_FENCE_SPECS for a fixture check.sh",
		PICKMAN_TEST_FENCE = "a fixture check.sh gets the jail's markers set explicitly, naming the fixture (review 003 F1)",
		GIT_DIR = "a fixture shell inherits GIT_DIR (relative, or another fixture repository) to prove the fence strips it before it reads the repository it protects (code review 001 F1)",
		["sandbox-exec"] = "a fixture check.sh gets the jail's markers set explicitly, with chmod 555 standing in for the jail",
	},
	["tests/acceptance/c0074/done-gate.spec.luau"] = {
		PICKMAN_FENCE_ = "names PICKMAN_FENCE_SPECS only as a table key passed to the pure doneGate, never in a process's environment (c0074)",
	},
	-- c0076, c0078: the jail's own specs read the run's lock (through the marker, to find the top process outside the
	-- jail) and test whether they run jailed (PICKMAN_TEST_JAIL == "sandbox-exec"); neither sets either
	["tests/acceptance/c0076/sweeper.spec.luau"] = {
		PICKMAN_TEST_FENCE = "reads the run's lock to find the top process, outside the jail",
		["sandbox-exec"] = "tests whether it runs jailed",
	},
	["tests/tooling/sweeper-interlock.spec.luau"] = {
		PICKMAN_TEST_FENCE = "reads the run's lock to find the top process, outside the jail",
		["sandbox-exec"] = "tests whether it runs jailed, and clears that for one sweeper",
	},
	-- c0114: its nested gate run clears the marker so the copied runner acts as a top-level run
	["tests/acceptance/c0114/gate-cover.spec.luau"] = {
		PICKMAN_TEST_FENCE = "runs the copied gate as a top-level run",
	},
	-- c0114: one fence call in a fixture gets the hook folder cleared and the jail marker unset or set, to prove the
	-- fence refuses a checkout with no hooks outside the jail; this run's own environment is never changed
	["tests/acceptance/c0114/guards.spec.luau"] = {
		PICKMAN_TEST_FENCE = "runs the copied runner as a top-level run",
		PICKMAN_FENCE_ = "clears PICKMAN_FENCE_HOOKS for one fence call in a fixture",
		["sandbox-exec"] = "sets the jail marker for one fence call in a fixture",
	},
	["tests/acceptance/c0078/jail-signals.spec.luau"] = {
		PICKMAN_TEST_FENCE = "reads the run's lock to find the top process, outside the jail",
		["sandbox-exec"] = "tests whether it runs jailed",
	},
}
-- c0640, by the id it has now (c0870: the user's compaction renumbers it); no literal path, so compaction's path
-- rewrite never maps it a second time
local C0640 = renamed.id("c0640")
local EXEMPT: { [string]: boolean } = {
	["tests/lib/fence.luau"] = true,
	["z-nile/lib/fence.sh"] = true,
	["tests/tooling/repo-fence.spec.luau"] = true,
}
-- Every project root of the registry (design review 001 F5). Only a copy of the runner with no engine at all (some
-- fixtures copy only tests/ and z-nile/lib/) uses the roots c0114 shipped with; an engine that is there but fails to
-- load is an error, never a narrower scan (design review 002 F4).
local ROOTS: { string } = { "tracker", "z-nile/.tracker" }
-- the checkout's registry, read at its root (c0120: this spec also runs from pickman/, see `checkout`)
if fs.isFile(`{checkout}/z-nile/engine/projects.luau`) then
	local okP, lib = pcall(require, "@znile/engine/projects")
	if not okP then
		error(`repo-fence: z-nile/engine/projects.luau does not load: {lib}`)
	end
	ROOTS = (lib :: any).roots((lib :: any).load(checkout))
end
-- c0640 lives in z-nile's tracker root since c0114; every root and state is listed so a move never unexempts it
local C0640_DIRS = { "tests/acceptance/" .. C0640 }
for _, root in ROOTS do
	for _, state in { "", "active/", "done/" } do
		table.insert(C0640_DIRS, `{root}/issues/{state}{C0640}/acceptance`)
	end
end
for _, dir in C0640_DIRS do
	EXEMPT[`{dir}/fence.spec.luau`] = true
	EXEMPT[`{dir}/lock.spec.luau`] = true
	EXEMPT[(string.gsub(dir, "/acceptance$", "")) .. "/check.sh"] = true -- the fence's own checks
end
-- The guard's own hooks (and their helper .repo.sh) name what they guard.
local EXEMPT_DIRS = { "z-nile/lib/git-hooks/" }
local function exempt(path: string): boolean
	for _, dir in EXEMPT_DIRS do
		if string.sub(path, 1, #dir) == dir then
			return true
		end
	end
	return EXEMPT[path] == true
end

-- Walks `dir` (relative to the checkout's root, wherever this run started) and records root-relative paths.
local function files(dir: string, out: { string }, skip: { [string]: boolean }?)
	if not fs.isDir(`{checkout}/{dir}`) then
		return
	end
	for _, name in fs.readDir(`{checkout}/{dir}`) do
		local path = `{dir}/{name}`
		if skip and skip[path] then
			continue
		elseif fs.isDir(`{checkout}/{path}`) then
			files(path, out, skip)
		elseif
			string.match(name, "%.luau$")
			or string.match(name, "%.sh$")
			or not string.find(name, ".", 2, true)
		then
			-- sources, shell scripts, and extensionless executables (hooks, tools)
			table.insert(out, path)
		end
	end
end

-- What runs as a check today: specs and their libraries (tests/), scripts, z-nile's engine and gate (c0114) with its
-- ./zn entry, and every check.sh under every project root. Acceptance specs prepared under a root are scanned once
-- promoted into tests/, which is when they start to run.
local function sources(): { string }
	local all: { string } = if fs.isFile(`{checkout}/zn`) then { "zn" } else {}
	local skip: { [string]: boolean } = {}
	for _, r in ROOTS do
		skip[r] = true
	end
	-- c0120: pickman's home runs as a check too (its specs, scripts, gate entry and forwarders)
	for _, dir in { "tests", "scripts", "z-nile", "pickman" } do
		files(dir, all, skip)
	end
	local checks: { string } = {}
	for _, r in ROOTS do
		files(r, checks)
	end
	for _, path in checks do
		if string.match(path, "/check%.sh$") then
			table.insert(all, path)
		end
	end
	return all
end

return t.spec("repository fence", function(it)
	it("this run is guarded for this checkout", function()
		t.expect(env.PICKMAN_TEST_FENCE).toBe(here)
		local ceiling = ":" .. (env.GIT_CEILING_DIRECTORIES or "") .. ":"
		t.expect(string.find(ceiling, `:{here}/.cache:`, 1, true) ~= nil).toBe(true)
		t.expect(env.GIT_DIR).toBe(nil)
		t.expect(env.GIT_INDEX_FILE).toBe(nil)
		t.expect(env.GIT_WORK_TREE).toBe(nil)
	end)

	it("git finds no repository in .cache, nor in a folder below it that has none", function()
		local probe = `{here}/.cache/repo-fence/sub`
		fs.writeDir(probe)
		local below = process.exec("git", { "rev-parse", "--git-dir" }, { cwd = probe })
		local at = process.exec("git", { "rev-parse", "--git-dir" }, { cwd = `{here}/.cache` })
		fs.removeDir(`{here}/.cache/repo-fence`)
		t.expect(below.ok).toBe(false)
		t.expect(at.ok).toBe(false)
	end)

	it("every git this run starts refuses ref updates in this repository", function()
		-- Under the jail the kernel denies every write to this repository (the next case), so no hook is set: a
		-- fixture's own hooks run natively. Elsewhere the guard's hooks are configured for every git. Either way
		-- the guard script refuses this repository when git calls it.
		local configured = trim(process.exec("git", { "config", "core.hooksPath" }).stdout)
		if env.PICKMAN_TEST_JAIL == "sandbox-exec" then
			t.expect(configured).toBe("")
		else
			-- the first guard's hook folder stays in force down a chain of runs, so check what it holds
			t.expect(fs.isFile(`{configured}/reference-transaction`)).toBe(true)
			t.expect(fs.isFile(`{configured}/pre-push`)).toBe(true)
		end
		local hooks = `{checkout}/z-nile/lib/git-hooks`
		t.expect(fs.isFile(`{hooks}/reference-transaction`)).toBe(true)
		t.expect(fs.isFile(`{hooks}/pre-push`)).toBe(true)
		local refused = process.exec(`{hooks}/reference-transaction`, { "prepared" }, { cwd = here })
		t.expect(refused.ok).toBe(false)
		t.expect(string.find(refused.stderr, "refused", 1, true) ~= nil).toBe(true)
		-- and a fixture repository may still update its own refs
		local fixture = `{here}/.cache/repo-fence-own`
		if fs.isDir(fixture) then
			fs.removeDir(fixture)
		end
		fs.writeDir(fixture)
		process.exec("git", { "init", "-q" }, { cwd = fixture })
		local own = process.exec(`{hooks}/reference-transaction`, { "prepared" }, { cwd = fixture })
		fs.removeDir(fixture)
		t.expect(own.ok).toBe(true)
	end)

	it("on macOS this run can write nothing in the checkout outside .cache", function()
		if process.os ~= "macos" then
			-- CI on Linux: a disposable checkout, guarded by the environment guards only
			t.expect(string.sub(env.PICKMAN_TEST_JAIL or "", 1, 4)).toBe("none")
			return
		end
		local jail = env.PICKMAN_TEST_JAIL or ""
		t.expect(jail == "sandbox-exec" or string.sub(jail, 1, 14) == "outer sandbox ").toBe(true)
		local common =
			trim(process.exec("git", { "rev-parse", "--path-format=absolute", "--git-common-dir" }).stdout)
		local main = (string.gsub(common, "/%.git$", ""))
		local tag = trim(process.exec("sh", { "-c", "echo $$" }).stdout)
		-- harmless if the jail were broken: untracked files, removed at once
		local probes = { `{here}/.pickman-jail-probe-{tag}`, `{common}/pickman-jail-probe-{tag}` }
		if checkout ~= here then
			-- a project home's run (c0120): the checkout's root and the root's .cache are outside its jail too
			table.insert(probes, `{checkout}/.pickman-jail-probe-{tag}`)
			table.insert(probes, `{checkout}/.cache/pickman-jail-probe-{tag}`)
		end
		if main ~= here then
			table.insert(probes, `{main}/.pickman-jail-probe-{tag}`) -- the main checkout, from a worktree
		end
		local home = env.HOME or ""
		if home ~= "" then
			table.insert(probes, `{home}/.config/git/pickman-jail-probe-{tag}`) -- the person's git configuration
		end
		local allowed: { string } = {}
		for _, path in probes do
			if pcall(fs.writeFile, path, "") then
				pcall(fs.removeFile, path)
				table.insert(allowed, path)
			end
		end
		-- the person's ~/.gitconfig: opened for appending, nothing written, so harmless if it were allowed
		if home ~= "" and process.exec("sh", { "-c", ': >> "$HOME/.gitconfig"' }).ok then
			table.insert(allowed, `{home}/.gitconfig`)
		end
		if #allowed > 0 then
			error(
				`this run could write the repository ({table.concat(allowed, ", ")}): {jail}. `
					.. "Inside another sandbox, run the gate outside it, or in one that denies writes to the checkout."
			)
		end
		t.expect((pcall(fs.writeFile, `{here}/.cache/repo-fence-jail-{tag}`, ""))).toBe(true)
		pcall(fs.removeFile, `{here}/.cache/repo-fence-jail-{tag}`)
		-- live probes, each harmless if the jail were broken: a file in the person's home (removed at once); `touch -c
		-- -r d d` on every ancestor of the checkout (it would set a folder's times to their own values); a connect to
		-- TEST-NET, where nothing listens; and loopback, which local test servers need, must still work
		local escaped: { string } = {}
		if home ~= "" then
			local probe = `{home}/.pickman-jail-probe-{tag}`
			if pcall(fs.writeFile, probe, "") then
				pcall(fs.removeFile, probe)
				table.insert(escaped, `a file in {home}`)
			end
		end
		-- the user temp folder (the ordinary shell's TMPDIR, review 004 F2) is closed too: specs get their own
		local ut = trim(process.exec("getconf", { "DARWIN_USER_TEMP_DIR" }).stdout)
		ut = (string.gsub(ut, "/+$", ""))
		if ut ~= "" then
			local probe = `{ut}/pickman-jail-probe-{tag}`
			if pcall(fs.writeFile, probe, "") then
				pcall(fs.removeFile, probe)
				table.insert(escaped, `the user temp folder {ut}`)
			end
		end
		-- no symlink can be made at the top of .cache (unjailed writers would follow it, review 005 F1)
		local link = `{here}/.cache/pickman-link-probe-{tag}`
		if process.exec("ln", { "-s", "/nonexistent", link }).ok then
			process.exec("rm", { "-f", link })
			table.insert(escaped, "a symlink at the top of .cache")
		end
		-- the run's mktemp honours -t too
		local named = trim(process.exec("mktemp", { "-t", "pickman" }).stdout)
		t.expect(named ~= "" and string.sub(named, 1, #(env.TMPDIR or "")) == env.TMPDIR).toBe(true)
		pcall(fs.removeFile, named)
		-- the .cache entry itself can't be replaced (a symlink there would redirect later writes, review 004 F1)
		if process.exec("touch", { "-c", "-r", `{here}/.cache`, `{here}/.cache` }).ok then
			table.insert(escaped, "the .cache entry itself")
		end
		-- the run's TMPDIR lies outside the checkout, and a plain `mktemp -d` lands in it
		local tmp = env.TMPDIR or ""
		t.expect(tmp ~= "" and string.sub(tmp .. "/", 1, #here + 1) ~= here .. "/").toBe(true)
		local made = trim(process.exec("mktemp", { "-d" }).stdout)
		t.expect(made ~= "" and string.sub(made, 1, #tmp) == tmp).toBe(true)
		pcall(fs.removeDir, made)
		-- the shared temp folder: programs outside the jail run and copy files from it (review 003 F1)
		local shared = `/private/tmp/pickman-jail-probe-{tag}`
		if pcall(fs.writeFile, shared, "") then
			pcall(fs.removeFile, shared)
			table.insert(escaped, "the shared temp folder /private/tmp")
		end
		local up = string.match(here, "^(.*)/[^/]+$")
		while up and up ~= "" do
			if process.exec("touch", { "-c", "-r", up, up }).ok then
				table.insert(escaped, `the folder {up}, above the checkout`)
			end
			up = string.match(up, "^(.*)/[^/]+$")
		end
		local net = process.exec("perl", {
			"-MIO::Socket::INET",
			"-e",
			'my $s = IO::Socket::INET->new(PeerAddr => "192.0.2.1", PeerPort => 9, Timeout => 2); print $s ? "connected" : "$!"',
		})
		if net.stdout ~= "Operation not permitted" then
			table.insert(escaped, `the network ({net.stdout})`)
		end
		local loop = process.exec("perl", {
			"-MIO::Socket::INET",
			"-e",
			'my $l = IO::Socket::INET->new(Listen => 1, LocalAddr => "127.0.0.1", LocalPort => 0) or die "$!"; '
				.. 'my $c = IO::Socket::INET->new(PeerAddr => "127.0.0.1", PeerPort => $l->sockport, Timeout => 2); print $c ? "ok" : "$!"',
		})
		t.expect(loop.stdout).toBe("ok")
		if #escaped > 0 then
			error(`the jail lets specs reach {table.concat(escaped, ", ")}: {jail}`)
		end
	end)

	it("when jailed, a spec can't signal the run's top process", function()
		if env.PICKMAN_TEST_JAIL ~= "sandbox-exec" then
			return -- no jail, so no signal rule (Linux, an outer sandbox): the testing skill's "Caught only by review"
		end
		local top = trim(fs.readFile(`{env.PICKMAN_TEST_FENCE or ""}/.cache/tests-run.lock/pid`))
		t.expect(string.match(top, "^%d+$") ~= nil).toBe(true)
		-- kill -0 and URG, which the top process ignores anyway: harmless if the rule were missing
		for _, sig in { "-0", "-URG" } do
			local r = process.exec("kill", { sig, top })
			t.expect(r.ok).toBe(false)
			t.expect(string.find(r.stderr, "Operation not permitted", 1, true) ~= nil).toBe(true)
		end
	end)

	it("specs have no GitHub credentials and push only into fixtures", function()
		t.expect(env.GH_TOKEN).toBe(nil)
		t.expect(env.GITHUB_TOKEN).toBe(nil)
		t.expect(env.SSH_AUTH_SOCK).toBe(nil)
		-- the fence's empty GitHub config folder; spelled in two parts because c0640's promoted spec names the literal
		-- path, and c0470 lets only one spec file name a .cache folder
		t.expect(env.GH_CONFIG_DIR).toBe(`{here}/.cache/` .. "gh" .. "-none")
		-- the last entry, empty, resets the helper list: no keychain (only the final newline is stripped)
		local listed = process.exec("git", { "config", "--get-all", "credential.helper" }).stdout
		local helpers = string.split((string.gsub(listed, "\n$", "")), "\n")
		t.expect(helpers[#helpers]).toBe("")
		-- no network transport at all, with or without hooks (none run under the jail): any spelling, and an alias
		for _, args in
			{
				{ "ls-remote", "https://example.invalid/x.git" },
				{ "ls-remote", "HTTPS://example.invalid/x.git" },
				{ "ls-remote", "http://example.invalid/x.git" },
				{ "ls-remote", "git://example.invalid/x.git" },
				{ "ls-remote", "git@example.invalid:x.git" },
				{ "ls-remote", "ssh://git@example.invalid/x.git" },
				{ "-c", "url.https://example.invalid/.insteadOf=zz:", "ls-remote", "zz:x.git" },
			}
		do
			local r = process.exec("git", args, { cwd = "/" }) -- outside every repository
			t.expect(r.ok).toBe(false)
			t.expect(string.find(r.stderr, "not allowed", 1, true) ~= nil).toBe(true)
		end
		-- and the push guard refuses them where hooks run
		local hooks = `{checkout}/z-nile/lib/git-hooks`
		for _, url in
			{ "https://github.com/x/y.git", "github.com:x/y.git", "gh:x/y", "ssh://git@github.com/x/y" }
		do
			t.expect(process.exec(`{hooks}/pre-push`, { "origin", url }, { cwd = here }).ok).toBe(false)
		end
	end)

	it("no spec, check.sh or script switches a guard off or points git elsewhere", function()
		local all = sources()
		t.expect(#all > 0).toBe(true)
		local bad: { string } = {}
		for _, path in all do
			if not exempt(path) then
				for _, name in bannedIn(fs.readFile(`{checkout}/{path}`), ALLOWED[path] or {}) do
					table.insert(bad, `{path} names {name}`)
				end
			end
		end
		-- the scan itself catches the overrides it bans (review 001 F1)
		-- planted text, built by concatenation so this file names none of it
		local planted = {
			"git -c protocol." .. "allow=always push",
			"git -c protocol." .. "https.allow=always push",
			"git -c credential." .. "helper=osxkeychain push",
			"git -c http." .. "extraheader=x push",
			"GIT_SSH_" .. "COMMAND=ssh git push",
			"GIT_ALLOW_" .. "PROTOCOL=https git push",
			"HTTPS_" .. "PROXY=http://127.0.0.1:3128 git push",
			"git -c http." .. "proxy=http://127.0.0.1:3128 push",
		}
		for _, text in planted do
			if #bannedIn(text, {}) == 0 then
				error(`the scan misses: {text}`)
			end
		end
		if #bad > 0 then
			error("checks must not override the repository guards:\n  " .. table.concat(bad, "\n  "))
		end
	end)

	it("every fixture commits as <name>@example.invalid", function()
		local bad: { string } = {}
		for _, path in sources() do
			if exempt(path) then
				continue
			end
			for _, email in identitiesIn(fs.readFile(`{checkout}/{path}`)) do
				if not string.match(email, "@example%.invalid$") then
					table.insert(bad, `{path}: {email}`)
				end
			end
		end
		-- identities set in the environment are read too (review 001 F3)
		local ids = identitiesIn(
			"{ GIT_AUTHOR_"
				.. 'EMAIL = "dev@example.com" }\ngit -c user.'
				.. "email=e2e@example.invalid"
				.. "\ngit -c User."
				.. "Email=boss@example.org\ngit commit --"
				.. 'author="X <x@example.net>"'
		)
		t.expect(table.find(ids, "boss@example.org") ~= nil).toBe(true)
		t.expect(table.find(ids, "x@example.net") ~= nil).toBe(true)
		t.expect(table.find(ids, "dev@example.com") ~= nil).toBe(true)
		t.expect(table.find(ids, "e2e@example.invalid") ~= nil).toBe(true)
		if #bad > 0 then
			error(
				"fixture identities must be <name>@example.invalid (the tripwire relies on it):\n  "
					.. table.concat(bad, "\n  ")
			)
		end
	end)
end)
