--!strict
-- c0530: the whole of scripts/setup.sh, run for real in a sandbox. Only `--tools` may skip the gate; a red gate
-- must fail setup; an unknown argument is refused before any tool runs. Nothing real is installed or run:
-- - the script is copied into a sandbox repo whose `scripts/check.sh` is a stub gate;
-- - PATH holds only one recording stub, linked as uname, xcode-select, git, gh, curl, unzip, rokit, rojo, selene,
--   stylua, luau-lsp and lune, plus links to a few system basics, and HOME is an empty sandbox directory;
-- - every variable setup.sh could read (CI, GH_TOKEN, GITHUB_PATH, the GitHub runner variables, the skip-looking
--   ones, the ones that change how bash starts) is set by the case or unset, so the run doesn't depend on where the
--   spec runs; everything else (the runner's own guards included) is inherited.
-- Every stub call and the stub gate append "<name> <args>" to one log, so a case can see what ran and in which order.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }
type Platform = { os: string, arch: string }

local ROOT = `{process.cwd}.cache/c0530-setup`
local LOG = `{ROOT}/calls.log`
local STUB = `{ROOT}/stub` -- the one stub script; every tool name is a symlink to it
local BIN = `{ROOT}/bin` -- tool names, first on PATH
local SYS = `{ROOT}/sys` -- links to real system basics, second and last on PATH
local HOME = `{ROOT}/home`
local REPO = `{ROOT}/repo`

local DARWIN: Platform = { os = "Darwin", arch = "arm64" }
local LINUX: Platform = { os = "Linux", arch = "x86_64" }
local BASICS = { "bash", "cat", "chmod", "cp", "dirname", "env", "head", "ln", "mkdir", "mktemp", "rm" }
local TOOLS =
	{ "uname", "xcode-select", "git", "gh", "curl", "unzip", "rojo", "selene", "stylua", "luau-lsp", "lune" }

-- One multi-call stub (by the name it was called as) logs "<name> <args>" and acts just enough for setup.sh. It is
-- written once per run and only symlinked after that: on macOS the first run of newly written executable files is
-- slow (c0530 E2), so there is one such file, not a dozen. The case picks the platform and the gate's exit code through STUB_* variables.
local STUB_TEXT = [[#!/bin/sh
name=${0##*/}
echo "$name $*" >> "@LOG@"
case "$name" in
  uname) if [ "$1" = -m ]; then echo "$STUB_ARCH"; else echo "$STUB_OS"; fi ;;
  xcode-select) echo /Library/Developer/CommandLineTools ;;
  git) if [ "$1" = --version ]; then echo "git version 2.0"; fi ;;
  gh) # release download ... -D <dir> leaves the release zip in <dir>
    if [ "$1" = release ]; then d=; while [ $# -gt 0 ]; do [ "$1" = -D ] && d=$2; shift; done; : > "$d/rokit.zip"; fi ;;
  unzip) # unzip -q <zip> -d <dir> drops the released rokit into <dir>
    d=; while [ $# -gt 0 ]; do [ "$1" = -d ] && d=$2; shift; done; ln -s "@STUB@" "$d/rokit" ;;
  rokit) # self-install puts rokit in ~/.rokit/bin, like the real one
    if [ "$1" = self-install ]; then mkdir -p "$HOME/.rokit/bin"; ln -s "@STUB@" "$HOME/.rokit/bin/rokit"; fi
    echo "rokit 1.2.0" ;;
  check.sh) exit "$STUB_GATE_EXIT" ;;
  *) echo "$name 1.0.0" ;;
esac
]]

-- the real path of a system tool, found on the spec's own PATH
local function real(name: string): string
	local r = process.exec("sh", { "-c", `command -v {name}` })
	local p = string.gsub(r.stdout, "%s+$", "")
	assert(r.ok and string.sub(p, 1, 1) == "/", `no {name} on PATH`)
	return p
end

local function link(target: string, path: string)
	local r = process.exec("ln", { "-s", target, path })
	assert(r.ok, r.stderr)
end

local built = false

-- the parts every run shares, built once per spec run
local function build()
	if fs.isDir(ROOT) then
		fs.removeDir(ROOT)
	end
	for _, dir in { BIN, SYS, `{REPO}/z-nile` } do
		fs.writeDir(dir)
	end
	local text = string.gsub(string.gsub(STUB_TEXT, "@LOG@", LOG), "@STUB@", STUB)
	fs.writeFile(STUB, text)
	process.exec("chmod", { "+x", STUB })
	for _, name in BASICS do
		link(real(name), `{SYS}/{name}`)
	end
	for _, name in TOOLS do
		link(STUB, `{BIN}/{name}`)
	end
	-- c0114 override: the bootstrap and the gate moved to z-nile/
	link(STUB, `{REPO}/z-nile/check.sh`)
	-- c0120 override: specs run in z-nile's home, so the script is read from the checkout's top
	local top = string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", "")
	fs.writeFile(`{REPO}/z-nile/setup.sh`, fs.readFile(`{top}/z-nile/setup.sh`))
	built = true
end

type Run = { platform: Platform, gateExit: number, rokitInstalled: boolean }
local run: Run = { platform = DARWIN, gateExit = 0, rokitInstalled = true }

-- a fresh state for one run: empty log and HOME; `rokitInstalled` false leaves rokit off PATH, so setup.sh installs it
local function sandbox(platform: Platform, gateExit: number, rokitInstalled: boolean)
	if not built then
		build()
	end
	fs.writeFile(LOG, "")
	if fs.isDir(HOME) then
		fs.removeDir(HOME)
	end
	fs.writeDir(HOME)
	if fs.isFile(`{ROOT}/github_path`) then
		fs.removeFile(`{ROOT}/github_path`)
	end
	local has = fs.isFile(`{BIN}/rokit`)
	if rokitInstalled and not has then
		link(STUB, `{BIN}/rokit`)
	elseif not rokitInstalled and has then
		fs.removeFile(`{BIN}/rokit`)
	end
	run = { platform = platform, gateExit = gateExit, rokitInstalled = rokitInstalled }
end

-- every variable a case may set; any the case leaves out is unset (env -u), as on a runner that doesn't set it
local CONTROLLED: { string } = {}

-- runs the sandbox's setup.sh with `args`, the variables in `env`, and every other CONTROLLED variable unset
local function setup(args: { string }, env: { [string]: string }?): Result
	local vars: { [string]: string } = {
		PATH = `{BIN}:{SYS}`,
		HOME = HOME,
		STUB_OS = run.platform.os,
		STUB_ARCH = run.platform.arch,
		STUB_GATE_EXIT = tostring(run.gateExit),
	}
	local given: { [string]: string } = env or {}
	for k, v in given do
		vars[k] = v
	end
	local argv: { string } = {}
	for _, k in CONTROLLED do
		if given[k] == nil then
			table.insert(argv, "-u")
			table.insert(argv, k)
		end
	end
	table.insert(argv, real("bash"))
	table.insert(argv, `{REPO}/z-nile/setup.sh`)
	for _, a in args do
		table.insert(argv, a)
	end
	return process.exec(real("env"), argv, { env = vars })
end

-- the logged calls, one "<name> <args>" string each
local function calls(): { string }
	local out = {}
	for line in string.gmatch(fs.readFile(LOG), "[^\n]+") do
		table.insert(out, line)
	end
	return out
end

local function count(list: { string }, entry: string): number
	local n = 0
	for _, l in list do
		if l == entry then
			n += 1
		end
	end
	return n
end

local function index(list: { string }, prefix: string): number
	for i, l in list do
		if string.sub(l, 1, #prefix) == prefix then
			return i
		end
	end
	return 0
end

local function has(text: string, token: string): boolean
	return string.find(text, token, 1, true) ~= nil
end

-- GitHub's default runner variables (docs.github.com/actions/reference/variables-reference, "Default environment
-- variables", read 2026-10-01: every variable listed as always set), as a gate job
-- on ubuntu sees them, plus the job's GH_TOKEN; a setup.sh that skips the gate on any of them must fail the spec
local CI_ENV: { [string]: string } = {
	CI = "true",
	GH_TOKEN = "ghs_fake",
	GITHUB_ACTIONS = "true",
	GITHUB_ACTION = "__run_2",
	GITHUB_ACTOR = "octocat",
	GITHUB_ACTOR_ID = "1",
	GITHUB_BASE_REF = "main",
	GITHUB_EVENT_NAME = "pull_request",
	GITHUB_HEAD_REF = "R0010-demo",
	GITHUB_JOB = "gate",
	GITHUB_REF = "refs/pull/1/merge",
	GITHUB_REF_NAME = "1/merge",
	GITHUB_REF_TYPE = "branch",
	GITHUB_REPOSITORY = "philipbergen/pickman",
	GITHUB_REPOSITORY_OWNER = "philipbergen",
	GITHUB_REPOSITORY_ID = "123456789",
	GITHUB_REPOSITORY_OWNER_ID = "1234567",
	GITHUB_WORKFLOW_SHA = "0000000000000000000000000000000000000000",
	GITHUB_REF_PROTECTED = "false",
	GITHUB_RETENTION_DAYS = "90",
	GITHUB_RUN_ATTEMPT = "1",
	GITHUB_RUN_ID = "1000",
	GITHUB_RUN_NUMBER = "7",
	GITHUB_SERVER_URL = "https://github.com",
	GITHUB_API_URL = "https://api.github.com",
	GITHUB_GRAPHQL_URL = "https://api.github.com/graphql",
	GITHUB_SHA = "0000000000000000000000000000000000000000",
	GITHUB_TRIGGERING_ACTOR = "octocat",
	GITHUB_WORKFLOW = "check",
	GITHUB_WORKFLOW_REF = "philipbergen/pickman/.github/workflows/check.yml@refs/pull/1/merge",
	GITHUB_WORKSPACE = "/home/runner/work/pickman/pickman",
	ImageOS = "ubuntu24",
	ImageVersion = "20260928.1",
	RUNNER_ARCH = "X64",
	RUNNER_ENVIRONMENT = "github-hosted",
	RUNNER_NAME = "GitHub Actions 1",
	RUNNER_OS = "Linux",
	RUNNER_TEMP = "/home/runner/work/_temp",
	RUNNER_TOOL_CACHE = "/opt/hostedtoolcache",
}

-- ...and the ones GitHub sets on every `run:` step, pointing at files in the sandbox
CI_ENV.GITHUB_ENV = `{ROOT}/gh-env`
CI_ENV.GITHUB_OUTPUT = `{ROOT}/gh-output`
CI_ENV.GITHUB_STEP_SUMMARY = `{ROOT}/gh-summary`
CI_ENV.GITHUB_STATE = `{ROOT}/gh-state`
CI_ENV.GITHUB_EVENT_PATH = `{ROOT}/gh-event.json`
CI_ENV.RUNNER_WORKSPACE = "/home/runner/work/pickman"

for k in CI_ENV do
	table.insert(CONTROLLED, k)
end
for _, k in
	{
		"GITHUB_PATH",
		"GITHUB_TOKEN",
		"PICKMAN_SKIP_GATE",
		"SKIP_GATE",
		"BASH_ENV",
		"ENV",
		"CDPATH",
		"GLOBIGNORE",
	}
do
	table.insert(CONTROLLED, k)
end
table.sort(CONTROLLED)

return t.spec("c0530 setup.sh, run whole", function(it)
	it(
		"with no argument, installs the tools, then runs the gate once with --full and ends SETUP OK",
		function()
			for _, platform in { DARWIN, LINUX } do
				sandbox(platform, 0, true)
				local r = setup({})
				if not r.ok then
					error(`{platform.os}: setup failed ({r.code}): {r.stderr}`)
				end
				local log = calls()
				t.expect(count(log, "check.sh --full")).toBe(1)
				t.expect(index(log, "check.sh")).toBe(#log) -- the gate is the last thing that runs
				t.expect(index(log, "rokit install") > 0).toBe(true)
				t.expect(index(log, "lune setup") > index(log, "rokit install")).toBe(true)
				t.expect(index(log, "check.sh") > index(log, "lune setup")).toBe(true)
				t.expect(has(r.stdout, "SETUP OK")).toBe(true)
			end
		end
	)

	it("--tools installs the same tools, runs no gate, and says so", function()
		for _, platform in { DARWIN, LINUX } do
			sandbox(platform, 0, true)
			local r = setup({ "--tools" })
			t.expect(r.ok).toBe(true)
			local log = calls()
			t.expect(index(log, "check.sh")).toBe(0)
			t.expect(index(log, "lune setup") > index(log, "rokit install")).toBe(true)
			t.expect(has(r.stdout, "tools only: gate skipped")).toBe(true)
			t.expect(has(r.stdout, "SETUP OK")).toBe(false)
		end
	end)

	it("on CI, with no argument, the gate still runs once with --full", function()
		for _, platform in { DARWIN, LINUX } do
			sandbox(platform, 0, true)
			local env = table.clone(CI_ENV)
			env.GITHUB_PATH = `{ROOT}/github_path`
			local r = setup({}, env)
			if not r.ok then
				error(`{platform.os}: setup failed on CI ({r.code}): {r.stderr}`)
			end
			local log = calls()
			t.expect(count(log, "check.sh --full")).toBe(1)
			t.expect(has(r.stdout, "SETUP OK")).toBe(true)
			-- it really took the CI branches: token check by API, rokit authenticated, PATH handed to later steps
			t.expect(index(log, "gh api rate_limit") > 0).toBe(true)
			t.expect(index(log, "gh auth status")).toBe(0)
			t.expect(index(log, "rokit authenticate github --token ghs_fake") > 0).toBe(true)
			t.expect(has(fs.readFile(`{ROOT}/github_path`), `{HOME}/.rokit/bin`)).toBe(true)
		end
	end)

	it("no variable skips the gate: only --tools does", function()
		local envs: { { [string]: string } } = {
			{ CI = "1" },
			{ CI = "true" },
			{ GITHUB_ACTIONS = "true" },
			{ PICKMAN_SKIP_GATE = "1" },
			{ SKIP_GATE = "1" },
			{ CI = "true", PICKMAN_SKIP_GATE = "1", GH_TOKEN = "ghs_fake" },
		}
		for _, env in envs do
			sandbox(LINUX, 0, true)
			local r = setup({}, env)
			t.expect(r.ok).toBe(true)
			t.expect(count(calls(), "check.sh --full")).toBe(1)
		end
	end)

	it("a red gate fails setup with the gate's exit code and no SETUP OK, locally and on CI", function()
		local envs: { { [string]: string } } = { {}, CI_ENV }
		for _, env in envs do
			for _, platform in { DARWIN, LINUX } do
				sandbox(platform, 3, true)
				local r = setup({}, env)
				t.expect(r.ok).toBe(false)
				t.expect(r.code).toBe(3)
				t.expect(count(calls(), "check.sh --full")).toBe(1)
				t.expect(has(r.stdout, "SETUP OK")).toBe(false)
			end
		end
	end)

	it("an unknown argument exits 2 before any tool runs", function()
		for _, bad in { "--bogus", "-t", "tools", "--full" } do
			sandbox(LINUX, 0, true)
			local r = setup({ bad }, CI_ENV)
			t.expect(r.ok).toBe(false)
			t.expect(r.code).toBe(2)
			t.expect(has(r.stderr, "unknown argument")).toBe(true)
			t.expect(calls()).toEqual({})
		end
	end)

	it("on a host without rokit, installs it from the release, then runs the gate", function()
		sandbox(DARWIN, 0, false)
		local r = setup({})
		if not r.ok then
			error(`setup failed ({r.code}): {r.stderr}`)
		end
		local log = calls()
		local download =
			index(log, "gh release download v1.2.0 -R rojo-rbx/rokit -p rokit-1.2.0-macos-aarch64.zip")
		t.expect(download > 0).toBe(true)
		t.expect(index(log, "rokit self-install") > download).toBe(true)
		t.expect(fs.isFile(`{HOME}/.rokit/bin/rokit`)).toBe(true)
		t.expect(count(log, "check.sh --full")).toBe(1)
	end)

	it("leaves nothing behind", function()
		fs.removeDir(ROOT)
		built = false
		t.expect(fs.isDir(ROOT)).toBe(false)
	end)
end)
