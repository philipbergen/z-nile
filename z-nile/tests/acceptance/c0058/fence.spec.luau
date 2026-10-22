--!strict
-- c0640: no check can change the repository it runs in. A throwaway repository plays "the real one": it
-- holds a copy of the runner and its guards, and probe specs try to escape, damage it, or bypass the
-- guards. Inner runs keep the outer run's guards (a probe that escaped this repository would still be
-- stopped before the real one) and clear only the marker, as a top-level run started by a person would.
-- The lock has its own spec (lock.spec.luau).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local task = require("@lune/task")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
-- c0120 override: specs run from their project's home (z-nile/): the fixtures live under its .cache (the jail refuses
-- the top's), and the copied runner runs from the copy's z-nile/ home, whose .cache (`cache`) holds the probes' files
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0640-fence`
local repo = `{base}/real`
-- c0120 override: the spec runs from its project's home after the move
local cache = `{repo}/z-nile/.cache`
local REQ = "req" .. "uire" -- keeps literal require text out of this file (graph scanner)

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end

local function physical(path: string): string
	return must(process.exec("pwd", { "-P" }, { cwd = path }), "pwd -P")
end

-- Every git this spec runs targets a repository it created. It refuses to act anywhere else: if a fixture's
-- repository were missing, git would find the enclosing real one (c0640's Problem, and how this spec once
-- damaged the shared repository while its guards did not exist yet).
local function fixture(dir: string)
	local top = if fs.isDir(dir)
		then process.exec("git", { "rev-parse", "--show-toplevel" }, { cwd = dir })
		else nil
	if not top or not top.ok or trim(top.stdout) ~= physical(dir) then
		error(`refusing to run git in {dir}: it is not a fixture repository this spec created`, 3)
	end
end

local function git(dir: string, args: { string }): string
	fixture(dir)
	return must(process.exec("git", args, { cwd = dir }), "git " .. table.concat(args, " "))
end

-- git whose failure is fine (cleanup), still only in a fixture
local function gitTry(dir: string, args: { string })
	fixture(dir)
	process.exec("git", args, { cwd = dir })
end

local FIXTURE = { "-c", "user.name=e2e", "-c", "user.email=e2e@example.invalid" }
local DEV = { "-c", "user.name=dev", "-c", "user.email=dev@example.com" }

local function as(identity: { string }, args: { string }): { string }
	local out = table.clone(identity)
	for _, a in args do
		table.insert(out, a)
	end
	return out
end

local ready = false
local function setUp()
	if not ready then
		error("setup did not finish: not running this case", 2)
	end
end

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

local function copyTree(dir: string, rel: string)
	local src = `{root}/{rel}`
	if not fs.isFile(src) and not fs.isDir(src) then
		return -- not built yet: each case then fails on its own assertion
	elseif fs.isDir(src) then
		for _, name in fs.readDir(src) do
			copyTree(dir, `{rel}/{name}`)
		end
	else
		write(dir, rel, fs.readFile(src))
	end
end

-- A repository holding the runner and its guards (plus `extra` files), committed by a non-fixture identity.
local function runnerRepo(dir: string, extra: { string })
	fs.writeDir(dir)
	-- c0120 override: the runner, its harness and its aliases are z-nile's (z-nile/tests/, z-nile/.luaurc)
	local parts = { "z-nile/tests/run.luau", "z-nile/tests/lib", "z-nile/lib/ac.sh", "z-nile/lib/fence.sh" }
	for _, rel in { "z-nile/lib/git-hooks", "z-nile/.luaurc", ".luaurc", "rokit.toml", ".gitignore" } do
		table.insert(parts, rel)
	end
	for _, rel in extra do
		table.insert(parts, rel)
	end
	for _, rel in parts do
		copyTree(dir, rel)
	end
	if fs.isDir(`{dir}/z-nile/lib/git-hooks`) then
		must(process.exec("chmod", { "-R", "+x", `{dir}/z-nile/lib/git-hooks` }), "chmod hooks")
	end
	must(process.exec("git", { "init", "-q", "-b", "main", dir }), "git init")
	-- no local identity: the runner refuses a repository whose identity is a fixture's
	git(dir, { "add", "-A" })
	git(dir, as(DEV, { "commit", "-qm", "runner" }))
end

-- A probe spec whose single case runs `body`; `fs`, `process`, `task`, `t`, `here` (the physical path of the repo's
-- z-nile/ home, where it runs), `repo` (the repo's physical path) and `sh` (a shell command in `here`) are in scope.
-- c0120 override: probes are z-nile's specs, run from the copy's z-nile/ home, one folder below the repository's top
local function probe(name: string, body: string)
	write(
		repo,
		-- c0120 override: the tooling's files live in z-nile/ (its home)
		`z-nile/tests/probe/{name}.spec.luau`,
		-- c0120 override: the spec runs from its project's home after the move
		`--!strict\nlocal fs = {REQ}("@lune/fs")\nlocal process = {REQ}("@lune/process")\n`
			.. `local task = {REQ}("@lune/task")\nlocal t = {REQ}("@tests/lib/t")\n`
			.. 'local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))\n'
			.. 'local repo = string.match(here, "^(.*)/z%-nile$") or ""\n'
			.. 'local function sh(c: string) return process.exec("sh", { "-c", c }, { cwd = here }) end\n'
			.. 'local top = sh("git rev-parse --show-toplevel")\n'
			.. 'if not top.ok or (string.gsub(top.stdout, "%s+$", "")) ~= repo then error("refusing: not the fixture repository") end\n'
			.. `return t.spec("{name}", function(it)\n\tit("probe", function()\n{body}\n\tend)\nend)\n`
	)
end

-- A top-level run of the copied runner in `dir`: only the marker is cleared, so the outer guards stay.
local function runIn(dir: string, args: { string }, extra: { [string]: string }?): Result
	local env: { [string]: string } = { PICKMAN_TEST_FENCE = "" }
	local more: { [string]: string } = extra or {}
	for k, v in more do
		env[k] = v
	end
	local argv = { "run", "tests/run", "--" }
	for _, a in args do
		table.insert(argv, a)
	end
	return process.exec("lune", argv, { cwd = `{dir}/z-nile`, env = env }) -- c0120 override: from the copy's z-nile/ home
end

local function run(probes: { string }, extra: { [string]: string }?): Result
	local args: { string } = {}
	for _, p in probes do
		table.insert(args, `tests/probe/{p}.spec.luau`)
	end
	return runIn(repo, args, extra)
end

-- Runs the `hold` probe; while it waits, `meanwhile` acts on the repository from outside the run.
local function during(meanwhile: () -> ()): Result
	for _, f in { "f-held", "f-go" } do
		if fs.isFile(`{cache}/{f}`) then -- c0120 override: the home's .cache
			fs.removeFile(`{cache}/{f}`)
		end
	end
	local result: Result? = nil
	task.spawn(function()
		result = run({ "hold" })
	end)
	local waited = 0
	-- c0120 override: the spec runs from its project's home after the move
	while not fs.isFile(`{cache}/f-held`) and waited < 20 do
		task.wait(0.05)
		waited += 0.05
	end
	meanwhile()
	-- c0120 override: the spec runs from its project's home after the move
	fs.writeFile(`{cache}/f-go`, "")
	while result == nil and waited < 40 do
		task.wait(0.05)
		waited += 0.05
	end
	if result == nil then
		error("the held run did not finish")
	end
	return result :: Result
end

local function branches(): string
	return git(repo, { "branch", "--list", "--format=%(refname)" })
end

return t.spec("c0640 checks never touch the real repository", function(it)
	it("sets up a repository holding a copy of the runner and its guards", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		runnerRepo(repo, {})
		fs.writeDir(cache) -- c0120 override: the home's .cache
		probe("ok", "\t\tt.expect(1).toBe(1)")
		probe("fails", "\t\tt.expect(1).toBe(2)")
		probe(
			"escape",
			"\t\tfs.writeDir(`{here}/.cache/f-probe/sub`)\n"
				.. '\t\tt.expect(sh("cd .cache/f-probe/sub && git rev-parse --git-dir").ok).toBe(false)\n'
				.. '\t\tt.expect(sh("cd .cache && git rev-parse --git-dir").ok).toBe(false)'
		)
		probe(
			"own",
			'\t\tt.expect(process.env["GIT_DIR"]).toBe(nil)\n'
				.. '\t\tt.expect(process.env["GIT_INDEX_FILE"]).toBe(nil)\n'
				.. '\t\tlocal r = sh("rm -rf .cache/f-own && git init -q .cache/f-own && cd .cache/f-own && echo x > f '
				.. '&& git add f && git rev-parse --absolute-git-dir")\n'
				.. '\t\tt.expect((string.gsub(r.stdout, "%s+$", ""))).toBe(`{here}/.cache/f-own/.git`)'
		)
		probe(
			"env",
			'\t\tlocal r = sh("printf %s \\"$GIT_CEILING_DIRECTORIES\\"; echo; git config core.hooksPath")\n'
				.. "\t\tfs.writeFile(`{here}/.cache/f-env.txt`, r.stdout)"
		)
		probe(
			"refs",
			'\t\tt.expect(sh("git branch escaped").ok).toBe(false)\n'
				.. '\t\tt.expect(sh("git commit -q --allow-empty -m escaped").ok).toBe(false)\n'
				.. '\t\tt.expect(sh("git switch -q -c escaped2").ok).toBe(false)\n'
				.. '\t\tt.expect(sh("git worktree add -q --detach .cache/f-wt-escaped").ok).toBe(false)\n'
				.. '\t\tt.expect(sh("git update-ref refs/heads/escaped3 HEAD").ok).toBe(false)'
		)
		probe(
			"push",
			-- c0120 override: the repository is `..` (and `../../..` from a fixture in .cache) of the home the probe runs in
			'\t\tlocal r = sh("rm -rf .cache/f-pushfx .cache/f-bare.git && git clone -q --no-hardlinks .. .cache/f-pushfx '
				.. "&& git init -q --bare .cache/f-bare.git && cd .cache/f-pushfx && git -c user.name=e2e "
				.. '-c user.email=e2e@example.invalid commit -q --allow-empty -m fx")\n'
				.. "\t\tt.expect(r.ok).toBe(true)\n"
				-- c0120 override: the spec runs from its home: the checkout's files are read from the top
				-- into the repository: by its configured origin, by a relative path and by a file:// URL
				.. '\t\tt.expect(sh("cd .cache/f-pushfx && git push -q origin HEAD:refs/heads/pushed").ok).toBe(false)\n'
				.. '\t\tt.expect(sh("cd .cache/f-pushfx && git push -q ../../.. HEAD:refs/heads/pushed-rel").ok).toBe(false)\n'
				.. "\t\tt.expect(sh(`cd .cache/f-pushfx && git push -q file://{repo} HEAD:refs/heads/pushed-url`).ok).toBe(false)\n"
				-- into a fixture: by a relative and by an absolute path
				.. '\t\tt.expect(sh("cd .cache/f-pushfx && git push -q ../f-bare.git HEAD:refs/heads/ok").ok).toBe(true)\n'
				.. "\t\tt.expect(sh(`cd .cache/f-pushfx && git push -q {here}/.cache/f-bare.git HEAD:refs/heads/ok2`).ok).toBe(true)"
		)
		probe("remote", '\t\tsh("git remote add escaped /nowhere")')
		probe("user", '\t\tsh("git config user.email escaped@example.com")')
		probe(
			"hold",
			'\t\tfs.writeFile(`{here}/.cache/f-held`, "")\n'
				.. "\t\tlocal waited = 0\n"
				.. "\t\twhile not fs.isFile(`{here}/.cache/f-go`) and waited < 30 do\n"
				.. "\t\t\ttask.wait(0.05)\n\t\t\twaited += 0.05\n\t\tend"
		)
		probe(
			"fetch",
			-- a spec fetches into no protected repository (only check.sh flows may: ci-verify)
			'\t\tt.expect(sh("git fetch -q . HEAD:refs/remotes/self/main").ok).toBe(false)\n'
				.. '\t\tt.expect(sh("git update-ref -d refs/remotes/self/main").ok).toBe(false)'
		)
		probe(
			"github",
			'\t\tt.expect(process.env["GH_TOKEN"]).toBe(nil)\n'
				.. '\t\tt.expect(process.env["GITHUB_TOKEN"]).toBe(nil)\n'
				.. '\t\tt.expect(process.env["GH_CONFIG_DIR"]).toBe(`{here}/.cache/gh-none`)\n'
				.. '\t\tt.expect(process.env["SSH_AUTH_SOCK"]).toBe(nil)\n'
				.. '\t\tlocal helpers = string.split((string.gsub(sh("git config --get-all credential.helper").stdout, "\\n$", "")), "\\n")\n'
				.. '\t\tt.expect(helpers[#helpers]).toBe("")\n'
				.. "\t\t-- no network transport, by any spelling, alias or pushurl, hooks or not\n"
				.. "\t\tlocal urls = { 'https://github.com/x/y.git', 'HTTPS://github.com/x/y.git', 'http://example.invalid/x',\n"
				.. "\t\t\t'git://example.invalid/x', 'github.com:x/y.git', 'gh:x/y', 'ssh://git@github.com/x/y' }\n"
				.. "\t\tfor _, url in urls do\n"
				.. "\t\t\tlocal r = sh(`git ls-remote {url}`)\n"
				.. "\t\t\tif r.ok or not string.find(r.stderr, 'not allowed', 1, true) then error(`{url}: {r.stderr}`) end\n"
				.. "\t\tend\n"
				.. "\t\tlocal alias = sh('git -c url.https://github.com/.insteadOf=zz: ls-remote zz:x/y.git')\n"
				.. "\t\tt.expect(string.find(alias.stderr, 'not allowed', 1, true) ~= nil).toBe(true)\n"
				.. '\t\tsh("rm -rf .cache/f-net && git init -q .cache/f-net")\n'
				.. "\t\tlocal push = sh('cd .cache/f-net && git -c user.name=e2e -c user.email=e2e@example.invalid commit -q --allow-empty -m x && git -c remote.o.url=/nonexistent -c remote.o.pushurl=HTTPS://github.com/x/y.git push o HEAD:main')\n"
				.. "\t\tt.expect(string.find(push.stderr, 'not allowed', 1, true) ~= nil).toBe(true)"
		)
		probe(
			"jail",
			'\t\tfs.writeFile(`{here}/.cache/f-jail.txt`, process.env["PICKMAN_TEST_JAIL"] or "unset")'
		)
		probe(
			"ownhooks",
			"\t\tlocal fx = `{here}/.cache/f-hooks`\n"
				.. '\t\tsh("rm -rf .cache/f-hooks && git init -q .cache/f-hooks")\n'
				.. '\t\tfs.writeFile(`{fx}/.git/hooks/pre-commit`, "#!/bin/sh\\necho ran > " .. fx .. "/pre-commit.log\\n")\n'
				.. '\t\tfs.writeFile(`{fx}/.git/hooks/reference-transaction`, "#!/bin/sh\\ncat >> " .. fx .. "/rt.log\\n")\n'
				.. "\t\tsh(`chmod +x {fx}/.git/hooks/pre-commit {fx}/.git/hooks/reference-transaction`)\n"
				.. "\t\tt.expect(sh(`cd {fx} && git -c user.name=e2e -c user.email=e2e@example.invalid commit -q --allow-empty -m x`).ok).toBe(true)\n"
				.. "\t\tt.expect(fs.isFile(`{fx}/pre-commit.log`)).toBe(true)\n"
				.. '\t\tt.expect(string.find(fs.readFile(`{fx}/rt.log`), "refs/heads/", 1, true) ~= nil).toBe(true)'
		)
		probe(
			"chain",
			-- the guard hooks named explicitly, as on an unjailed run: they hand the fixture's own hooks the same
			-- arguments and input, and pass on their exit status
			-- c0120 override: the guard hooks are the repository's, one folder above the home
			"\t\tlocal G = `-c core.hooksPath={repo}/z-nile/lib/git-hooks -c user.name=e2e -c user.email=e2e@example.invalid`\n"
				.. "\t\tlocal fx, tgt = `{here}/.cache/f-chain`, `{here}/.cache/f-chain-tgt.git`\n"
				.. "\t\tsh(`rm -rf {fx} {tgt} && git init -q -b main {fx} && git init -q --bare {tgt}`)\n"
				.. '\t\tfs.writeFile(`{fx}/.git/hooks/pre-push`, `#!/bin/sh\\necho "$2" > {fx}/pp.args\\ncat > {fx}/pp.in\\n[ ! -f {fx}/fail ] || exit 3\\n`)\n'
				.. '\t\tfs.writeFile(`{fx}/.git/hooks/reference-transaction`, `#!/bin/sh\\n[ "$1" = prepared ] || exit 0\\ncat >> {fx}/rt.in\\n[ ! -f {fx}/rtfail ] || exit 4\\n`)\n'
				.. "\t\tsh(`chmod +x {fx}/.git/hooks/pre-push {fx}/.git/hooks/reference-transaction`)\n"
				.. "\t\tt.expect(sh(`cd {fx} && git {G} commit -q --allow-empty -m one && git {G} push -q {tgt} main`).ok).toBe(true)\n"
				.. "\t\tt.expect(string.find(fs.readFile(`{fx}/pp.args`), tgt, 1, true) ~= nil).toBe(true)\n"
				.. "\t\tt.expect(string.find(fs.readFile(`{fx}/pp.in`), 'refs/heads/main', 1, true) ~= nil).toBe(true)\n"
				.. "\t\tlocal pushed = sh(`git -C {tgt} rev-parse main`).stdout\n"
				.. "\t\tfs.writeFile(`{fx}/fail`, '')\n"
				.. "\t\tt.expect(sh(`cd {fx} && git {G} commit -q --allow-empty -m two && git {G} push -q {tgt} main`).ok).toBe(false)\n"
				.. "\t\tt.expect(sh(`git -C {tgt} rev-parse main`).stdout).toBe(pushed)\n"
				.. "\t\tt.expect(string.find(fs.readFile(`{fx}/rt.in`), 'refs/heads/main', 1, true) ~= nil).toBe(true)\n"
				.. "\t\tfs.writeFile(`{fx}/rtfail`, '')\n"
				.. "\t\tt.expect(sh(`cd {fx} && git {G} update-ref refs/heads/z HEAD`).ok).toBe(false)\n"
				.. "\t\tt.expect(sh(`git -C {fx} rev-parse --verify -q refs/heads/z`).ok).toBe(false)\n"
				.. "\t\tt.expect(string.find(fs.readFile(`{fx}/rt.in`), 'refs/heads/z', 1, true) ~= nil).toBe(true)"
		)
		local r = run({ "ok" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		ready = true
	end)

	it("a failing case still fails the run, and a passing one passes", function()
		setUp()
		local failing = run({ "fails" })
		t.expect(failing.ok).toBe(false)
		t.expect(has(failing.stdout .. failing.stderr, "0 passed, 1 failed")).toBe(true)
		t.expect(run({ "ok" }).ok).toBe(true)
	end)

	it("a bad --jobs value still exits 2 through the guard", function()
		setUp()
		local r = runIn(repo, { "--jobs", "x", "tests/probe/ok.spec.luau" })
		t.expect(r.code).toBe(2)
		t.expect(has(r.stderr, "--jobs")).toBe(true)
	end)

	it("git in a fixture folder without a repository, or in .cache itself, finds none", function()
		setUp()
		local r = run({ "escape" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
	end)

	it("inherited repository overrides are stripped before any spec runs", function()
		setUp()
		local before = git(repo, { "ls-files", "--stage" })
		local r = run({ "own" }, { GIT_DIR = `{repo}/.git`, GIT_INDEX_FILE = `{repo}/.git/index` })
		t.expect(git(repo, { "ls-files", "--stage" })).toBe(before)
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
	end)

	it("the guards reach everything the run starts and keep the outer ceiling", function()
		setUp()
		must(run({ "env" }), "env run")
		-- c0120 override: each run fences its home's .cache: the copy's z-nile/, and this run's (here)
		local lines = string.split(fs.readFile(`{cache}/f-env.txt`), "\n")
		local ceiling = ":" .. lines[1] .. ":"
		t.expect(has(ceiling, `:{physical(repo)}/z-nile/.cache:`)).toBe(true)
		t.expect(has(ceiling, `:{physical(here)}/.cache:`)).toBe(true)
		t.expect(fs.isFile(`{trim(lines[2] or "")}/reference-transaction`)).toBe(true)
	end)

	it("ac.sh gives check.sh files the same guards", function()
		setUp()
		local script = table.concat({
			'source "$1" || exit 1',
			'[ "$(git rev-parse --show-toplevel 2>/dev/null)" = "$2" ] || { echo "refusing: not the fixture repository"; exit 1; }',
			'[ -z "${GIT_DIR+x}" ] || { echo "GIT_DIR still set"; exit 1; }',
			'case ":$GIT_CEILING_DIRECTORIES:" in *":$(pwd -P)/.cache:"*) ;; *) echo "no fence"; exit 1;; esac',
			'(cd .cache && git rev-parse --git-dir) && { echo "found a repository from .cache"; exit 1; }',
			'git branch ac-escaped && { echo "a ref update was allowed"; exit 1; }',
			"exit 0",
		}, "\n")
		local r = process.exec(
			"bash",
			{ "-c", script, "_", `{repo}/z-nile/lib/ac.sh`, physical(repo) },
			{ cwd = repo, env = { GIT_DIR = `{repo}/.git` } }
		)
		t.expect(has(branches(), "ac-escaped")).toBe(false)
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
	end)

	it("a ref update in the repository from inside a run is refused", function()
		setUp()
		local before = branches()
		local r = run({ "refs" })
		t.expect(branches()).toBe(before)
		t.expect(fs.isDir(`{cache}/f-wt-escaped`)).toBe(false) -- c0120 override: the home's .cache
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
	end)

	it("a push from a fixture into the repository is refused; into a fixture it works", function()
		setUp()
		local r = run({ "push" })
		t.expect(has(branches(), "pushed")).toBe(false) -- none of pushed, pushed-rel, pushed-url
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
	end)

	it("a run that changed remote or user config fails, even though every case passed", function()
		setUp()
		for _, p in { "remote", "user" } do
			local r = run({ p })
			gitTry(repo, { "remote", "remove", "escaped" })
			gitTry(repo, { "config", "--unset", "user.email" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stdout .. r.stderr, "1 passed, 0 failed")).toBe(true)
			t.expect(has(r.stderr, "REPOSITORY CHANGED")).toBe(true)
			t.expect(has(r.stderr, "config")).toBe(true)
		end
	end)

	it("someone else's commit during a run, or gh's own config, does not trip it", function()
		setUp()
		local r = during(function()
			git(repo, as(DEV, { "commit", "-q", "--allow-empty", "-m", "dev" }))
			git(repo, { "config", "remote.origin.gh-resolved", "base" })
		end)
		gitTry(repo, { "config", "--unset", "remote.origin.gh-resolved" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
	end)

	it("a run during which HEAD gained a fixture commit, or lost history, fails", function()
		setUp()
		local start = git(repo, { "rev-parse", "HEAD" })
		local gained = during(function()
			git(repo, as(FIXTURE, { "commit", "-q", "--allow-empty", "-m", "a fixture commit" }))
		end)
		git(repo, { "reset", "-q", "--hard", start })
		t.expect(gained.ok).toBe(false)
		t.expect(has(gained.stderr, "HEAD gained commits written by a fixture")).toBe(true)
		local lost = during(function()
			git(repo, { "reset", "-q", "--hard", "HEAD~1" })
		end)
		git(repo, { "reset", "-q", "--hard", start })
		t.expect(lost.ok).toBe(false)
		t.expect(has(lost.stderr, "does not descend")).toBe(true)
	end)

	it("a run during which a fixture-written ref or a worktree under .cache appeared fails", function()
		setUp()
		local leaked = during(function()
			local tree = git(repo, { "rev-parse", "HEAD^{tree}" })
			local commit = git(repo, as(FIXTURE, { "commit-tree", tree, "-m", "leaked" }))
			git(repo, { "update-ref", "refs/heads/leaked", commit })
		end)
		git(repo, { "update-ref", "-d", "refs/heads/leaked" })
		t.expect(leaked.ok).toBe(false)
		t.expect(has(leaked.stderr, "refs written by a fixture")).toBe(true)
		local wt = during(function()
			git(repo, { "worktree", "add", "-q", "--detach", `{repo}/.cache/f-wt` })
		end)
		git(repo, { "worktree", "remove", "--force", `{repo}/.cache/f-wt` })
		t.expect(wt.ok).toBe(false)
		t.expect(has(wt.stderr, "worktrees registered under .cache")).toBe(true)
	end)

	it("a fake marker does not switch the guards off", function()
		setUp()
		local r = run({ "escape", "env" }, { PICKMAN_TEST_FENCE = "/bogus" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		t.expect(has(r.stderr, "ignoring")).toBe(true)
		-- c0120 override: the home's .cache
		local ceiling = ":" .. string.split(fs.readFile(`{cache}/f-env.txt`), "\n")[1] .. ":"
		t.expect(has(ceiling, `:{physical(repo)}/z-nile/.cache:`)).toBe(true)
	end)

	it("list mode is still refused before anything else", function()
		setUp()
		local r = run({ "ok" }, { AC_LIST = "1" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout .. r.stderr, "AC_LIST")).toBe(true)
	end)

	it("the gate spec fails on a spec, script or identity that would bypass a guard", function()
		setUp()
		local scan = `{base}/scan`
		-- c0120 override: the gate spec is z-nile's, run from the copy's z-nile/ home
		runnerRepo(scan, { "z-nile/tests/tooling/repo-fence.spec.luau" })
		local spec = { "tests/tooling/repo-fence.spec.luau" }
		-- this repository sits inside this run's own jail, which can't be nested: the gate's jail case
		-- rightly fails here, and every other case must pass
		local jailCase = ":: on macOS this run can write nothing in the checkout outside .cache"
		local function failures(r: Result): { string }
			local out: { string } = {}
			for line in string.gmatch(r.stdout .. r.stderr, "[^\n]+") do
				if string.match(line, "^FAIL ") and not (process.os == "macos" and has(line, jailCase)) then
					table.insert(out, line)
				end
			end
			return out
		end
		local clean = runIn(scan, spec)
		if #failures(clean) > 0 or not has(clean.stdout, " spec files") then
			error(clean.stdout .. clean.stderr)
		end
		-- c0120 override: specs and their libraries are scanned in the homes (no tests/ at the root any more)
		write(scan, "z-nile/tests/planted/bad.luau", "-- points git elsewhere: GIT_" .. "DIR\n")
		write(scan, "scripts/planted-env.sh", "env -" .. 'i PATH="$PATH" git status\n') -- clears every guard
		write(scan, "scripts/planted-push.sh", "git push --no-" .. "verify origin HEAD\n") -- skips the push guard
		write(scan, "scripts/planted-osa.sh", "osa" .. "script -e 'do shell script \"git push\"'\n") -- runs outside the jail
		-- c0120 override: the tooling's files live in z-nile/ (its home)
		write(scan, "z-nile/tests/planted/id.luau", "-- git config user.email dev@example.com\n")
		write(scan, "scripts/planted-tool", "#!/bin/sh\ngit -c core.hooks" .. "Path=/dev/null push\n") -- an extensionless script
		local dirty = runIn(scan, spec)
		t.expect(#failures(dirty) > 0).toBe(true)
		local out = dirty.stdout .. dirty.stderr
		t.expect(has(out, "tests/planted/bad.luau")).toBe(true)
		t.expect(has(out, "scripts/planted-env.sh")).toBe(true)
		t.expect(has(out, "scripts/planted-push.sh")).toBe(true)
		t.expect(has(out, "scripts/planted-osa.sh")).toBe(true)
		t.expect(has(out, "tests/planted/id.luau: dev@example.com")).toBe(true)
		t.expect(has(out, "scripts/planted-tool")).toBe(true)
	end)

	it("a repository whose git identity is a fixture's is refused before any spec runs", function()
		setUp()
		git(repo, { "config", "user.email", "e2e@example.invalid" })
		local r = run({ "ok" })
		gitTry(repo, { "config", "--unset", "user.email" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "fixture identity")).toBe(true)
		t.expect(has(r.stdout .. r.stderr, "1 passed")).toBe(false)
	end)

	it("a check.sh may fetch into refs/remotes, a spec may not, and neither may delete one", function()
		setUp()
		local r = run({ "fetch" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		local script = table.concat({
			'source "$1" || exit 1',
			'[ "$(git rev-parse --show-toplevel 2>/dev/null)" = "$2" ] || { echo "refusing: not the fixture repository"; exit 1; }',
			"git fetch -q . HEAD:refs/remotes/self/main || { echo 'a check.sh could not fetch'; exit 1; }",
			"git update-ref -d refs/remotes/self/main && { echo 'a remote ref was deleted'; exit 1; }",
			"exit 0",
		}, "\n")
		-- as a check.sh that tracker.sh starts outside any spec run (one started by a spec keeps the spec's limits)
		local check = process.exec(
			"bash",
			{ "-c", script, "_", `{repo}/z-nile/lib/ac.sh`, physical(repo) },
			{ cwd = repo, env = { PICKMAN_FENCE_SPECS = "" } }
		)
		gitTry(repo, { "update-ref", "-d", "refs/remotes/self/main" })
		if not check.ok then
			error(check.stdout .. check.stderr)
		end
	end)

	it("specs get no GitHub credentials and can't push to any network remote", function()
		setUp()
		local r = run({ "github" }, { GH_TOKEN = "not-a-real-token", GITHUB_TOKEN = "not-a-real-token" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
	end)

	it("a marker leaked into another checkout below it is ignored", function()
		setUp()
		local other = `{repo}/.worktree/X`
		git(repo, as(DEV, { "worktree", "add", "-q", "-b", "x", other }))
		-- c0120 override: the probe, the run and its .cache are the other checkout's z-nile/ home's
		write(
			other,
			"z-nile/tests/probe/env.spec.luau",
			fs.readFile(`{repo}/z-nile/tests/probe/env.spec.luau`)
		)
		local ceiling = (process.env.GIT_CEILING_DIRECTORIES or "") .. `:{physical(repo)}/z-nile/.cache`
		local r = runIn(other, { "tests/probe/env.spec.luau" }, {
			PICKMAN_TEST_FENCE = physical(repo),
			GIT_CEILING_DIRECTORIES = ceiling,
		})
		-- c0120 override: the spec runs from its project's home after the move
		local fence = `:{physical(other)}/z-nile/.cache:` -- before the worktree goes
		local env = if fs.isFile(`{other}/z-nile/.cache/f-env.txt`)
			then fs.readFile(`{other}/z-nile/.cache/f-env.txt`)
			else ""
		gitTry(repo, { "worktree", "remove", "--force", other })
		gitTry(repo, { "branch", "-q", "-D", "x" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		t.expect(has(r.stderr, "ignoring")).toBe(true)
		t.expect(has(":" .. string.split(env, "\n")[1] .. ":", fence)).toBe(true)
	end)

	it("a run inside a sandbox says it is not jailed again, and still runs guarded", function()
		setUp()
		local r = run({ "jail" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		local jail = trim(fs.readFile(`{cache}/f-jail.txt`)) -- c0120 override: the home's .cache
		if process.os == "macos" then
			-- this spec runs jailed, and macOS can't nest sandboxes
			t.expect(has(r.stderr, "already inside a sandbox")).toBe(true)
			t.expect(string.sub(jail, 1, 14)).toBe("outer sandbox ")
		else
			t.expect(string.sub(jail, 1, 4)).toBe("none")
		end
	end)

	it("a run that can't be jailed and could write its repository refuses to start", function()
		setUp()
		-- Inside this run's own jail (macOS can't nest it), which lets it write this repository (it lives under the
		-- real checkout's .cache). It may go on only as a proven fixture of a jailed outer run. Both runs below keep
		-- the inherited guards, except for one thing that breaks the proof:
		local cases: { { [string]: string } } = {
			-- no outer guard
			{ PICKMAN_FENCE_REAL_GIT = "" },
			-- a ceiling that holds an ancestor that is no checkout's .cache (as a prompt speed-up might)
			{ GIT_CEILING_DIRECTORIES = (string.gsub(physical(repo), "/[^/]+$", "")) },
		}
		for _, broken in cases do
			local r = run({ "ok" }, broken)
			if process.os ~= "macos" then
				t.expect(r.ok).toBe(true) -- no jail off macOS: environment guards only
				continue
			end
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "cannot jail this run")).toBe(true)
			t.expect(has(r.stdout .. r.stderr, "1 passed")).toBe(false)
		end
		-- c0120 override: the run starts in the copy's z-nile/ home: neither it nor the top keeps a probe file
		for _, dir in { repo, `{repo}/z-nile` } do
			for _, name in fs.readDir(dir) do
				t.expect(string.match(name, "^%.pickman%-jail%-probe")).toBe(nil) -- its probe files are gone
			end
		end
	end)

	it("a check.sh started inside a spec run keeps the spec's limits", function()
		setUp()
		local script = table.concat({
			'source "$1" || exit 1',
			'[ "$(git rev-parse --show-toplevel 2>/dev/null)" = "$2" ] || { echo "refusing: not the fixture repository"; exit 1; }',
			'[ -z "$(git config --get-all credential.helper | tail -n 1)" ] || { echo "a credential helper is back"; exit 1; }',
			"git fetch -q . HEAD:refs/remotes/self/kept && { echo 'a spec-run check.sh fetched'; exit 1; }",
			"exit 0",
		}, "\n")
		local check = process.exec(
			"bash",
			{ "-c", script, "_", `{repo}/z-nile/lib/ac.sh`, physical(repo) },
			{ cwd = repo }
		)
		gitTry(repo, { "update-ref", "-d", "refs/remotes/self/kept" })
		if not check.ok then
			error(check.stdout .. check.stderr)
		end
	end)

	it(
		"the guard hooks hand a fixture's own hooks their arguments and input, and keep their failures",
		function()
			setUp()
			local r = run({ "chain" })
			if not r.ok then
				error(r.stdout .. r.stderr)
			end
		end
	)

	it("a fixture's own git hooks still run under the guards", function()
		setUp()
		-- this inner run is not jailed (it can't be nested), so the guard hooks are configured, and chain on
		local r = run({ "ownhooks" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
