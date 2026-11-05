--!strict
-- c0123 AC4: every launcher starts what it runs in the allow-listed environment. A caller's environment is poisoned
-- (exported functions named git and command, a BASH_ENV file that leaves a marker, CDPATH, GIT_EXEC_PATH and a PATH
-- entry holding a planted git and cat, SHELLOPTS, an unlisted name) and each launcher is started directly, as a
-- person starts it: ./zn, the forwarders, the gate, `zn check` (the engine's `bash -p` check.sh with ac.sh), and the
-- spec runner. What it starts must see none of it: the marker file never appears, no function, only allowed names,
-- the fixed PATH, and the system git. Fixtures only, under this home's .cache.
local cleanenv = require("@znile/lib/cleanenv")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local home = fixture.physical(".") :: string
local root = string.match(home, "^(.*)/[^/]+$") :: string
local base = `{home}/.cache/c0123-launch`
local facts = cleanenv.facts()

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local function sh(cmd: string, dir: string?)
	local r = process.exec("bash", { "-c", cmd }, { cwd = dir })
	if not r.ok then
		error(`{cmd} failed: {r.stderr}{r.stdout}`)
	end
end

local fixed: string = (function()
	local parsed = cleanenv.parse(fs.readFile(`{root}/z-nile/lib/cleanenv.list`), facts.home)
	return table.concat((parsed :: cleanenv.Spec).path, ":")
end)()

local ready = false
local marker = `{base}/bash-env-ran`
local evil = `{base}/evil`
local function poison(): { [string]: string }
	if not ready then
		return {}
	end
	return {
		["BASH_FUNC_git%%"] = "() { echo hijack; }",
		["BASH_FUNC_command%%"] = "() { echo hijack; }",
		BASH_ENV = `{base}/bash-env.sh`,
		CDPATH = `.:{base}`,
		GIT_EXEC_PATH = evil,
		SHELLOPTS = "verbose",
		FOO_UNLISTED = "1",
		PATH = `{evil}:{process.env.PATH or ""}`,
	}
end

local probeCheck = table.concat({
	"#!/usr/bin/env bash",
	'HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"',
	'source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh"',
	"probe() {",
	'  { echo "FLAGS=$-"; echo "FUNCS=$(compgen -A function | grep -vE "^(_ac_|check$|finish$|probe$|pickman_|_pickman)" | tr "\\n" " ")";',
	'    echo "NAMES=$(compgen -e | LC_ALL=C sort | tr "\\n" " ")"; echo "PATH=$PATH"; echo "GIT=$(type -P git)"; } >"$ZN_ROOT/.cache/launch-probe.txt"',
	"}",
	'check "AC1: writes the probe" probe',
	"finish",
	"",
}, "\n")

local fx: trackerfix.Fixture
local function setUp()
	if ready then
		return
	end
	fx = trackerfix.new("c0123-launch-tf", {
		["z-nile/.tracker/issues/c0900/c0900.md"] = trackerfix.stub("c0900", "probe", "new-a-b-c"),
		["z-nile/.tracker/issues/c0900/check.sh"] = probeCheck,
	})
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	fs.writeDir(evil)
	fs.writeFile(`{evil}/git`, "#!/bin/sh\necho EVIL-GIT\n")
	fs.writeFile(`{evil}/cat`, "#!/bin/sh\nexit 0\n")
	sh(`chmod +x "{evil}/git" "{evil}/cat"`)
	fs.writeFile(`{base}/bash-env.sh`, `echo ran > "{marker}"\n`)
	ready = true
end

-- Starts `rel` (a file of the fixture, run directly) under the poisoned environment.
local function launch(rel: string, args: { string }): fixture.Result
	setUp()
	return fixture.exec(fx.main, rel, args, { env = poison() })
end

-- the git the process found is in one of the fixed PATH directories, never the planted one
local function systemGit(seen: string)
	local git = string.match(seen, "GIT=(%S+)")
	t.expect(git ~= nil).toBe(true)
	local dir = string.match(git :: string, "^(.*)/git$")
	local ok = false
	for entry in string.gmatch(fixed, "[^:]+") do
		if entry == dir then
			ok = true
		end
	end
	if not ok or has(seen, evil) then
		error(`git came from {git}, not from the fixed PATH:\n{seen}`)
	end
end

local function noMarker()
	t.expect(fs.isFile(marker)).toBe(false)
end

local function forbidden(text: string)
	for _, gone in
		{
			"BASH_FUNC_",
			"CDPATH",
			"BASH_ENV",
			"SHELLOPTS",
			"GIT_EXEC_PATH",
			"FOO_UNLISTED",
			"hijack",
			"EVIL-GIT",
		}
	do
		if has(text, gone) then
			error(`the launched process saw {gone}:\n{text}`)
		end
	end
end

return t.spec("c0123 every launcher starts its children in the allow-listed environment", function(it)
	it("./zn runs a command through bash -p and leaves the caller's BASH_ENV and functions unused", function()
		local r = launch("./zn", { "list" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		noMarker()
		forbidden(r.stdout .. r.stderr)
	end)

	it("the forwarders (scripts/tracker.sh, scripts/check.sh) start the same clean command", function()
		local r = launch("scripts/tracker.sh", { "list" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		noMarker()
		forbidden(r.stdout .. r.stderr)
		local plan = launch("scripts/check.sh", { "--plan" })
		if not plan.ok then
			error(plan.stderr .. plan.stdout)
		end
		noMarker()
		forbidden(plan.stdout .. plan.stderr)
	end)

	it("the gate starts in the allow-listed environment before any other line of it", function()
		setUp()
		local gate = fs.readFile(`{root}/z-nile/check.sh`)
		local lines = string.split(gate, "\n")
		local at = 0
		for i, line in lines do
			if has(line, 'pickman_clean_env "$0" "$@"') then
				at = i
				break
			end
		end
		t.expect(at > 0).toBe(true)
		-- nothing but the shebang, comments and the line that finds cleanenv.sh runs before it
		t.expect(lines[1]).toBe("#!/bin/bash -p")
		for i = 2, at - 1 do
			local line = lines[i] :: string
			if string.sub(line, 1, 1) ~= "#" and not has(line, "BASH_SOURCE") then
				error(`line {i} of z-nile/check.sh runs before the clean-environment step: {line}`)
			end
		end
		-- the gate itself, cut after that line with a probe in place of the rest, run directly
		local cut = table.concat(table.move(lines, 1, at, 1, {}), "\n")
			.. '\necho "FLAGS=$-" >"$PWD/gate-probe.txt"; echo "NAMES=$(compgen -e | tr "\\n" " ")" >>"$PWD/gate-probe.txt"; echo "GIT=$(type -P git)" >>"$PWD/gate-probe.txt"\n'
		fs.writeFile(`{fx.main}/z-nile/check-probe.sh`, cut)
		sh(`chmod +x "{fx.main}/z-nile/check-probe.sh"`)
		local r = launch("z-nile/check-probe.sh", {})
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		noMarker()
		local seen = fs.readFile(`{fx.main}/gate-probe.txt`)
		fs.removeFile(`{fx.main}/gate-probe.txt`)
		fs.removeFile(`{fx.main}/z-nile/check-probe.sh`)
		forbidden(seen)
		systemGit(seen)
	end)

	it("zn check starts check.sh as bash -p in the allow-listed environment", function()
		local r = launch("./zn", { "check", "c0900" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		noMarker()
		local seen = fs.readFile(`{fx.main}/.cache/launch-probe.txt`)
		forbidden(seen)
		-- bash -p: privileged mode is on, and no function reached the script
		t.expect(string.find(seen, "FLAGS=[%a]*p", 1) ~= nil).toBe(true)
		t.expect(has(seen, "FUNCS=\n")).toBe(true)
		t.expect(has(seen, `{fixed}\n`)).toBe(true) -- the fixed directories end the PATH; the run's own entries may precede them
		systemGit(seen)
	end)

	it(
		"a check.sh started by hand with bash -p is restarted by ac.sh in the allow-listed environment",
		function()
			setUp()
			local env = poison()
			-- the first lines of a hand-started check.sh run in the caller's own environment (its PATH, its CDPATH) before
			-- ac.sh can act; the launchers above are what start it clean
			env.PATH = process.env.PATH or "/usr/bin:/bin"
			local clean: { [string]: string } = {}
			for k, v in env do
				if k ~= "CDPATH" then
					clean[k] = v
				end
			end
			env = clean
			local r = fixture.exec(
				fx.main,
				"/bin/bash",
				{ "-p", "z-nile/.tracker/issues/c0900/check.sh" },
				{ env = env }
			)
			if not r.ok then
				error(r.stderr .. r.stdout)
			end
			noMarker()
			forbidden(fs.readFile(`{fx.main}/.cache/launch-probe.txt`))
		end
	)

	it(
		"a person's shell cannot move the PATH, the lune, perl, git or git's config through HOME, a stub name or XDG_CONFIG_HOME",
		function()
			setUp()
			-- an entry script as the Design writes one, then the fence and a ref write
			local entry = table.concat({
				"#!/bin/bash -p",
				'_c=${BASH_SOURCE[0]%/*}; [[ $_c != "${BASH_SOURCE[0]}" ]] || _c=.',
				'. "$_c/lib/cleanenv.sh" && pickman_clean_env "$0" "$@" || exit 1',
				'cd "$_c/.." || exit 1',
				'. z-nile/lib/fence.sh && pickman_fence "$PWD" || { echo FENCE-REFUSED; exit 0; }',
				'echo "GIT=$(type -P git) PERL=$(type -P perl) GLOBAL=$(git config --global --get core.fsmonitor) SSH=${GIT_SSH_COMMAND-unset}"',
				"if git update-ref refs/heads/c0123-human HEAD 2>/dev/null; then echo ESCAPED; else echo GUARDED; fi",
				"",
			}, "\n")
			fs.writeFile(`{fx.main}/z-nile/probe-entry.sh`, entry)
			sh(`chmod +x "{fx.main}/z-nile/probe-entry.sh"`)
			-- the permissive hook folder and a home that holds a perl printing the pin, a git, and a config naming a program
			local pin = string.match(
				fs.readFile(`{root}/z-nile/lib/fence.sh`),
				"_PICKMAN_FENCE_HOOKS_SHA256=(%x+)"
			) :: string
			local permissive = `{base}/permissive-hooks`
			sh(`rm -rf "{permissive}" && cp -R "{fx.main}/z-nile/lib/git-hooks" "{permissive}"`)
			for _, hook in { "reference-transaction", "pre-push" } do
				fs.writeFile(`{permissive}/{hook}`, "#!/bin/sh\nexit 0\n")
			end
			local evilHome = `{base}/evil-home`
			fs.writeDir(`{evilHome}/.rokit/bin`)
			fs.writeFile(`{evilHome}/.rokit/bin/perl`, `#!/bin/sh\necho {pin}\n`)
			fs.writeFile(`{evilHome}/.rokit/bin/git`, "#!/bin/sh\necho EVIL-GIT\n")
			fs.writeFile(`{evilHome}/.gitconfig`, "[core]\n\tfsmonitor = /nonexistent/evil-fsmonitor\n")
			fs.writeDir(`{evilHome}/xdg/git`)
			fs.writeFile(`{evilHome}/xdg/git/config`, "[core]\n\tfsmonitor = /nonexistent/evil-fsmonitor\n")
			fs.writeDir(`{base}/pickman-stub.planted`)
			fs.writeFile(`{base}/pickman-stub.planted/git`, "#!/bin/sh\necho EVIL-GIT\n")
			fs.writeFile(`{base}/pickman-stub.planted/perl`, `#!/bin/sh\necho {pin}\n`)
			sh(
				`chmod +x "{evilHome}/.rokit/bin/"* "{base}/pickman-stub.planted/git" "{base}/pickman-stub.planted/perl"`
			)
			-- an agent's own scratch tree: `mktemp -t pickman-stub` puts a folder in .cache/.tmp, and the caller spells its
			-- path with other letters (the same folder on a volume that folds letter case); it holds a git and a perl too
			local agentStub = `{fx.main}/.cache/.tmp/pickman-stub.agent`
			fs.writeDir(agentStub)
			fs.writeFile(`{agentStub}/git`, "#!/bin/sh\necho EVIL-GIT\n")
			fs.writeFile(`{agentStub}/perl`, `#!/bin/sh\necho {pin}\n`)
			sh(`chmod +x "{agentStub}/git" "{agentStub}/perl"`)
			local agentSpelled = string.gsub(agentStub, "/%.cache/%.tmp/", "/.CACHE/.TMP/")
			-- a person's shell: the fence marker is forged, not empty (it is a name anyone can set), and the planted folders are not believed
			local env = poison()
			env.HOME = evilHome
			env.XDG_CONFIG_HOME = `{evilHome}/xdg`
			env.PICKMAN_FENCE_REAL_GIT = "/nonexistent" -- forged: a person can set it
			env.GIT_SSH_COMMAND = "evil"
			env.PICKMAN_FENCE_HOOKS = permissive
			env.PICKMAN_TEST_JAIL = "none"
			env.PICKMAN_FENCE_SPECS = ""
			env.PICKMAN_TEST_FENCE = ""
			env.PATH =
				`{base}/pickman-stub.planted:{agentStub}:{agentSpelled}:{evilHome}/.rokit/bin:{process.env.PATH or ""}`
			local r = fixture.exec(fx.main, "z-nile/probe-entry.sh", {}, { env = env })
			fs.removeFile(`{fx.main}/z-nile/probe-entry.sh`)
			if not r.ok then
				error(r.stderr .. r.stdout)
			end
			t.expect(has(r.stdout, "GUARDED")).toBe(true)
			t.expect(has(r.stdout, "ESCAPED")).toBe(false)
			t.expect(has(r.stdout, "EVIL")).toBe(false)
			t.expect(has(r.stdout, evilHome)).toBe(false)
			t.expect(has(r.stdout, "GLOBAL= SSH=unset")).toBe(true) -- the account's own config names no fsmonitor; a forged marker kept no ssh command
		end
	)

	it(
		"the SessionStart hook keeps CLAUDE_PROJECT_DIR and CLAUDE_ENV_FILE under a poisoned caller and still writes the session's TMPDIR",
		function()
			setUp()
			-- c0194's hook is an entry script (a caller starts it): privileged, cleaned, and CLAUDE_* is on the list
			local envFile = `{base}/claude-env`
			fs.writeFile(envFile, "")
			local env = poison()
			env.CLAUDE_PROJECT_DIR = fx.main
			env.CLAUDE_ENV_FILE = envFile
			-- a planted `lune` first on the caller's PATH: only a hook that cleaned its environment first skips it
			local evilLune = `{base}/evil-lune`
			local lunePlanted = `{base}/evil-lune-ran`
			fs.writeDir(evilLune)
			fs.writeFile(`{evilLune}/lune`, `#!/bin/sh\necho ran > "{lunePlanted}"\nexit 1\n`)
			sh(`chmod +x "{evilLune}/lune"`)
			env.PATH = `{evilLune}:{env.PATH}`
			local r = fixture.exec(fx.main, "scripts/hooks/session-tmp.sh", {}, { env = env })
			if not r.ok then
				error(r.stderr .. r.stdout)
			end
			noMarker()
			t.expect(fs.isFile(lunePlanted)).toBe(false)
			local written = fs.readFile(envFile)
			t.expect(has(written, `export TMPDIR={fx.main}/.cache/.tmp`)).toBe(true)
			t.expect(has(written, `{fx.main}/z-nile/bin`)).toBe(true)
			forbidden(written .. r.stderr)
		end
	)

	it(
		"the spec runner, started at the top with the poisoned environment, restarts itself in the clean one",
		function()
			setUp()
			local repo = `{base}/runner`
			if fs.isDir(repo) then
				fs.removeDir(repo)
			end
			fs.writeDir(`{repo}/z-nile/tests/probe`)
			for _, rel in
				{
					"z-nile/tests/run.luau",
					"z-nile/tests/lib",
					"z-nile/lib",
					"z-nile/.luaurc",
					".luaurc",
					"rokit.toml",
					".gitignore",
				}
			do
				local parent = string.match(rel, "^(.*)/[^/]+$")
				if parent then
					fs.writeDir(`{repo}/{parent}`)
				end
				sh(`cp -R "{root}/{rel}" "{repo}/{rel}"`)
			end
			sh(`chmod -R +x "{repo}/z-nile/lib/git-hooks"`)
			fs.writeFile(
				`{repo}/z-nile/tests/probe/env.spec.luau`,
				table.concat({
					"--!strict",
					'local fs = require("@lune/fs")',
					'local process = require("@lune/process")',
					'local t = require("@tests/lib/t")',
					'return t.spec("probe", function(it)',
					'\tit("writes what it sees", function()',
					"\t\tlocal names = {}",
					"\t\tfor k in process.env do",
					"\t\t\ttable.insert(names, k)",
					"\t\tend",
					"\t\ttable.sort(names)",
					'\t\tlocal git = process.exec("bash", { "-p", "-c", "type -P git" }).stdout',
					-- an entry script's cleaner, started inside this run with an agent's scratch folder (a sibling of the run
					-- folder in .cache/.tmp, registered by nobody) first on PATH
					'\t\tlocal agent = process.cwd .. ".cache/.tmp/pickman-stub.agent"',
					'\t\tlocal entry = process.exec("/bin/bash", { "-p", "-c", ". lib/cleanenv.sh && pickman_clean_env && echo \\"ENTRYGIT=$(type -P git)\\" && echo \\"ENTRYPATH=$PATH\\"" }, { env = { PATH = agent .. ":" .. (process.env.PATH or "") } })',
					'\t\tfs.writeFile(".cache/runner-probe.txt", "NAMES=" .. table.concat(names, " ") .. "\\nPATH=" .. (process.env.PATH or "") .. "\\nGIT=" .. git .. "\\n" .. entry.stdout .. entry.stderr)',
					"\tend)",
					"end)",
					"",
				}, "\n")
			)
			-- an agent's scratch folder in the copy's .cache/.tmp, beside the run folder the copy's runner will make
			fs.writeDir(`{repo}/z-nile/.cache/.tmp/pickman-stub.agent`)
			fs.writeFile(`{repo}/z-nile/.cache/.tmp/pickman-stub.agent/git`, "#!/bin/sh\necho EVIL-GIT\n")
			sh(`chmod +x "{repo}/z-nile/.cache/.tmp/pickman-stub.agent/git"`)
			process.exec("git", { "init", "-q", "-b", "main", repo })
			fixture.git(repo, { "add", "-A" })
			fixture.git(
				repo,
				{ "-c", "user.name=c0123", "-c", "user.email=dev@example.invalid", "commit", "-qm", "runner" }
			)
			local env = poison()
			env.PICKMAN_TEST_FENCE = "" -- a top-level run of the copy
			local r = fixture.exec(
				`{repo}`,
				"/usr/bin/env",
				{ "-C", `{repo}/z-nile`, "lune", "run", "tests/run", "--", "tests/probe/env.spec.luau" },
				{ env = env }
			)
			if not r.ok then
				error(r.stderr .. r.stdout)
			end
			noMarker()
			local seen = fs.readFile(`{repo}/z-nile/.cache/runner-probe.txt`)
			forbidden(seen)
			t.expect(has(seen, fixed)).toBe(true)
			systemGit(seen)
			-- the registry the copy's runner wrote names its own run folder and not the shared one: the sibling the
			-- caller put first on PATH is dropped by an entry script's cleaner, the run's own bin (macOS) is kept
			t.expect(has(seen, "ENTRYGIT=")).toBe(true)
			t.expect(has(seen, "EVIL-GIT")).toBe(false)
			t.expect(has(seen, "pickman-stub.agent")).toBe(false)
			if process.os == "macos" then
				t.expect(has(string.match(seen, "ENTRYPATH=[^\n]*") or "", "/pickman-run.")).toBe(true)
			end
			-- a runner told it was restarted, in a dirty environment, refuses instead of restarting again
			local again = fixture.exec(`{repo}`, "/usr/bin/env", {
				"-C",
				`{repo}/z-nile`,
				"lune",
				"run",
				"tests/run",
				"--",
				"--cleaned",
				"tests/probe/env.spec.luau",
			}, { env = env })
			t.expect(again.ok).toBe(false)
			t.expect(has(again.stderr .. again.stdout, "still not the allow-list")).toBe(true)
			trim("")
		end
	)
end)
