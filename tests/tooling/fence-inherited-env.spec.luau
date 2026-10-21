--!strict
-- c0120 code review 002: the guards derive what they protect from git, and an inherited variable must neither redirect
-- that read nor make it find nothing. From a project home (pickman/) git has to look one folder up to find the
-- checkout, so an inherited ceiling at the checkout's root would hide it (F1), and an inherited GIT_COMMON_DIR would
-- point it at another repository (F2). Finding nothing refuses; it never means "nothing to protect".
-- A throwaway repository under .cache plays the real one: it holds the runner, its guards and a pickman/ home.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = fixture.physical(".") :: string
local base = `{root}/.cache/c0120-inherited`
local repo = `{base}/real`
local foreign = `{base}/foreign`
local nowhere = `{base}/nowhere`

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

local function write(path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(parent)
	end
	fs.writeFile(path, text)
end

local function copyTree(rel: string)
	local src = `{root}/{rel}`
	if fs.isDir(src) then
		for _, name in fs.readDir(src) do
			copyTree(`{rel}/{name}`)
		end
	elseif fs.isFile(src) then
		write(`{repo}/{rel}`, fs.readFile(src))
	end
end

local ready = false
local function setUp()
	if ready then
		return
	end
	if fs.isDir(base) then
		fs.removeDir(base)
	end
	for _, rel in
		{
			"tests/run.luau",
			"tests/lib",
			"z-nile/lib",
			".luaurc",
			"rokit.toml",
			".gitignore",
			"pickman/.luaurc",
			"pickman/tests/run.luau",
			"pickman/tests/lib/t.luau",
			"pickman/tests/lib/renamed.luau",
		}
	do
		copyTree(rel)
	end
	-- the probe a nested run from pickman/ runs: it changes the repository's user config, which the tripwire must see
	write(
		`{repo}/pickman/tests/probe/config.spec.luau`,
		table.concat({
			'local process = require("@lune/process")',
			'local t = require("@tests/lib/t")',
			'return t.spec("probe", function(it)',
			'\tit("changes the repository\'s config", function()',
			`\t\tprocess.exec("git", \{ "-C", "{repo}", "config", "user.name", "c0120 probe" \})`,
			"\tend)",
			"end)",
			"",
		}, "\n")
	)
	process.exec("chmod", { "-R", "+x", `{repo}/z-nile/lib/git-hooks` })
	process.exec("git", { "init", "-q", "-b", "main", repo })
	fixture.git(repo, { "add", "-A" })
	fixture.git(
		repo,
		{ "-c", "user.name=c0120", "-c", "user.email=dev@example.invalid", "commit", "-qm", "runner" }
	)
	process.exec("git", { "init", "-q", foreign })
	fs.writeDir(nowhere)
	ready = true
end

-- A shell in the fixture: sources its fence.sh, inherits `inherit`, enters `from`, and reports what the fence protects.
local function probe(from: string, inherit: string, after: string?): fixture.Result
	local script = table.concat({
		". z-nile/lib/fence.sh",
		inherit,
		`cd {from} || exit 8`,
		'pickman_fence "$PWD" specs || { echo "REFUSED-FENCE"; exit 0; }',
		'echo "REAL=:$PICKMAN_FENCE_REAL_GIT:"',
		`if git -C {repo} update-ref refs/heads/c0120-escaped HEAD 2>/dev/null; then echo ESCAPED; else echo REFUSED; fi`,
		after or "",
		"",
	}, "\n")
	fs.writeFile(`{repo}/.cache-probe.sh`, script)
	local r = fixture.exec(repo, "bash", { ".cache-probe.sh" }, { env = { PICKMAN_TEST_JAIL = "none" } })
	fs.removeFile(`{repo}/.cache-probe.sh`)
	pcall(fixture.git, repo, { "update-ref", "-d", "refs/heads/c0120-escaped" })
	return r
end

local function guardsRepo(r: fixture.Result): boolean
	return has(r.stdout, `:{repo}/.git:`) and has(r.stdout, "REFUSED\n") and not has(r.stdout, "ESCAPED")
end

return t.spec(
	"c0120 the guards read what they protect in a clean environment, and refuse when it finds nothing",
	function(it)
		it(
			"a fence entered from pickman/ with a ceiling at the checkout's root records the checkout and refuses update-ref",
			function()
				setUp()
				local r = probe("pickman", `export GIT_CEILING_DIRECTORIES="{repo}"`)
				t.expect(has(r.stdout, "REFUSED-FENCE")).toBe(false)
				t.expect(guardsRepo(r)).toBe(true)
			end
		)

		it(
			"a fence entered from pickman/ with GIT_COMMON_DIR at another repository records the checkout, not that one",
			function()
				setUp()
				local r = probe("pickman", `export GIT_COMMON_DIR="{foreign}/.git"`)
				t.expect(guardsRepo(r)).toBe(true)
				t.expect(has(r.stdout, `{foreign}/.git`)).toBe(false)
			end
		)

		it(
			"pickman_guarded never answers unguarded for the checkout under a ceiling at its root, from the root or from pickman/",
			function()
				setUp()
				local r = probe(
					"pickman",
					`export GIT_CEILING_DIRECTORIES="{repo}"`,
					`echo "ROOT=$(pickman_guarded {repo})"; echo "HOME=$(pickman_guarded {repo}/pickman) rc=$?"`
				)
				t.expect(has(r.stdout, "ROOT=guarded\n")).toBe(true)
				-- from pickman/ the caller's own read can't see past the ceiling: no answer (exit 1), which callers treat as
				-- guarded (code review 003 F1); never unguarded
				t.expect(has(r.stdout, "HOME=guarded rc=0") or has(r.stdout, "HOME= rc=1")).toBe(true)
			end
		)

		it("a fence whose read finds no repository refuses, in every mode", function()
			setUp()
			for _, mode in { "specs", "checks" } do
				-- the markers set explicitly (code review 003 F2): inside this spec run PICKMAN_FENCE_SPECS is inherited, and
				-- it would turn checks mode into specs mode
				local markers = if mode == "specs"
					then "export PICKMAN_FENCE_SPECS=1"
					else "unset PICKMAN_FENCE_SPECS PICKMAN_TEST_FENCE"
				local script = table.concat({
					". z-nile/lib/fence.sh",
					markers,
					`cd {nowhere} || exit 8`,
					'echo "MODE-SPECS=${PICKMAN_FENCE_SPECS:-unset}"',
					`pickman_fence "$PWD" {mode}`,
					'echo "rc=$? COUNT=${GIT_CONFIG_COUNT:-unset}"',
					"",
				}, "\n")
				fs.writeFile(`{repo}/.cache-probe.sh`, script)
				local r = fixture.exec(
					repo,
					"bash",
					{ ".cache-probe.sh" },
					{ env = { PICKMAN_TEST_JAIL = "none" } }
				)
				fs.removeFile(`{repo}/.cache-probe.sh`)
				t.expect(has(r.stdout, "rc=1")).toBe(true)
				t.expect(has(r.stderr, "is in no git repository")).toBe(true)
				t.expect(has(r.stdout, if mode == "specs" then "MODE-SPECS=1" else "MODE-SPECS=unset"))
					.toBe(true)
			end
		end)

		-- code review 003 F2: a git that answers rev-parse with an empty success reaches the guards' empty-answer checks
		it(
			"with a git that answers rev-parse with nothing, the fence refuses and pickman_guarded never says unguarded",
			function()
				setUp()
				local real = (string.gsub(process.exec("sh", { "-c", "command -v git" }).stdout, "%s+$", ""))
				local stub = `{base}/fake-empty`
				fs.writeDir(stub)
				fs.writeFile(
					`{stub}/git`,
					`#!/bin/sh\nfor a in "$@"; do [ "$a" = rev-parse ] && exit 0; done\nexec "{real}" "$@"\n`
				)
				process.exec("chmod", { "+x", `{stub}/git` })
				local script = table.concat({
					". z-nile/lib/fence.sh",
					`PATH="{stub}:$PATH"; export PATH`,
					'echo "GUARDED=$(pickman_guarded "$PWD") rc=$?"',
					'pickman_fence "$PWD" specs; echo "FENCE-rc=$?"',
					"",
				}, "\n")
				fs.writeFile(`{repo}/.cache-probe.sh`, script)
				local r = fixture.exec(
					repo,
					"bash",
					{ ".cache-probe.sh" },
					{ env = { PICKMAN_TEST_JAIL = "none" } }
				)
				fs.removeFile(`{repo}/.cache-probe.sh`)
				t.expect(has(r.stdout, "unguarded")).toBe(false)
				t.expect(has(r.stdout, "GUARDED= rc=1")).toBe(true)
				t.expect(has(r.stdout, "FENCE-rc=1")).toBe(true)
				t.expect(has(r.stderr, "is in no git repository")).toBe(true)
			end
		)

		-- code review 003 F1: the caller's git acts where its own GIT_DIR points; pickman_guarded answers for that too
		it(
			"pickman_guarded answers guarded in a fixture whose caller set GIT_DIR to the protected repository",
			function()
				setUp()
				local r = probe(
					".",
					"",
					table.concat({
						`git init -q "{repo}/.cache/fx"`,
						`cd "{repo}/.cache/fx" || exit 7`,
						'echo "PLAIN=$(pickman_guarded "$PWD")"',
						`GIT_DIR="{repo}/.git"; export GIT_DIR`,
						'echo "SET=$(pickman_guarded "$PWD")"',
						-- and the other way: GIT_DIR at an unprotected repository hides nothing from the clean read
						`GIT_DIR="{foreign}/.git"; export GIT_DIR`,
						`echo "AWAY=$(pickman_guarded "{repo}")"`,
					}, "\n")
				)
				t.expect(has(r.stdout, "PLAIN=unguarded\n")).toBe(true)
				t.expect(has(r.stdout, "SET=guarded\n")).toBe(true)
				t.expect(has(r.stdout, "AWAY=guarded\n")).toBe(true)
			end
		)

		it(
			"a run from pickman/ with a ceiling at the checkout's root still sees the repository: its tripwire fires",
			function()
				setUp()
				local r = process.exec("lune", { "run", "tests/run", "--", "tests/probe/config.spec.luau" }, {
					cwd = `{repo}/pickman`,
					-- the outer run's ceiling stays (it proves this run a fixture of a guarded checkout), plus the root
					env = {
						PICKMAN_TEST_FENCE = "",
						GIT_CEILING_DIRECTORIES = `{process.env.GIT_CEILING_DIRECTORIES or ""}:{repo}`,
					},
				})
				pcall(fixture.git, repo, { "config", "--unset", "user.name" })
				t.expect(r.ok).toBe(false)
				t.expect(has(r.stdout .. r.stderr, "1 passed, 0 failed")).toBe(true)
				t.expect(has(r.stderr, "REPOSITORY CHANGED")).toBe(true)
			end
		)

		it("cleans up", function()
			if fs.isDir(base) then
				fs.removeDir(base)
			end
		end)
	end
)
