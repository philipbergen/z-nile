--!strict
-- c0120 code review 005 F2: a check.sh fences the root's .cache and every project home's, from the one owner of that
-- set (fence.sh's pickman_fence_all), whichever project it belongs to and wherever it is started. The reviewer's probe:
-- with no sentinel in z-nile/.cache yet (a fresh checkout), a pickman check.sh's `git add -f -N` in z-nile/.cache
-- reached the real index. Run with the jail's marker set explicitly both ways (lesson
-- testing/specs-set-host-markers-explicitly). Fixture under this home's .cache/c0120-every-home.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0120-every-home`
local repo = `{base}/repo`

local CHECK = table.concat({
	"#!/usr/bin/env bash",
	'HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"',
	'source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh"',
	"probe() {",
	"  local h",
	"  for h in pickman z-nile; do",
	'    mkdir -p "$ZN_ROOT/$h/.cache/fx-probe" && touch "$ZN_ROOT/$h/.cache/fx-probe/f" || return 1',
	'    if (cd "$ZN_ROOT/$h/.cache" && git rev-parse --absolute-git-dir) >/dev/null 2>&1; then',
	'      echo "git finds a repository in $h/.cache"; return 1',
	"    fi",
	'    if (cd "$ZN_ROOT/$h/.cache/fx-probe" && git add -f -N f) >/dev/null 2>&1; then',
	'      echo "git add -f -N in $h/.cache reached a repository"; return 1',
	"    fi",
	"  done",
	"}",
	'check "AC1: git finds no repository in any home\'s .cache" probe',
	"finish",
	"",
}, "\n")

local function sh(dir: string, args: { string }, jail: string): (boolean, string)
	local r = process.exec("bash", args, {
		cwd = dir,
		env = {
			PICKMAN_TEST_JAIL = jail,
			PICKMAN_FENCE_SPECS = "1",
			PICKMAN_TEST_FENCE = here,
		},
	})
	return r.ok, r.stdout .. r.stderr
end

local function index(): string
	return fixture.git(repo, { "ls-files", "--", "pickman/.cache", "z-nile/.cache" })
end

return t.spec("c0120 a check.sh fences every home's .cache", function(it)
	it("sets up a fixture checkout with a check.sh in each project", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(repo)
		engine.copy(root, repo)
		engine.roots(repo)
		for _, item in { "pickman/.tracker/issues/f0001", "z-nile/.tracker/issues/c0001" } do
			fs.writeDir(`{repo}/{item}`)
			fs.writeFile(`{repo}/{item}/check.sh`, CHECK)
		end
		fs.writeFile(`{repo}/.gitignore`, ".cache/\n")
		t.expect(process.exec("git", { "init", "-q", "-b", "main", repo }).ok).toBe(true)
		fixture.git(repo, { "add", "-A" })
		fixture.git(
			repo,
			{ "-c", "user.name=c0120", "-c", "user.email=c0120@example.invalid", "commit", "-qm", "fixture" }
		)
	end)

	for _, jail in { "sandbox-exec", "none (not macOS: environment guards only)" } do
		it(
			`each check.sh, from the root and from each home, finds no repository in any home's .cache ({jail})`,
			function()
				for _, item in { "pickman/.tracker/issues/f0001", "z-nile/.tracker/issues/c0001" } do
					for _, from in { "", "pickman", "z-nile" } do
						-- a fresh checkout: no sentinel in any home yet
						for _, h in { "pickman", "z-nile" } do
							if fs.isFile(`{repo}/{h}/.cache/.git`) then
								fs.removeFile(`{repo}/{h}/.cache/.git`)
							end
						end
						local dir = if from == "" then repo else `{repo}/{from}`
						local ok, out = sh(dir, { `{repo}/{item}/check.sh` }, jail)
						if not ok then
							print(`{item} from {if from == "" then "the root" else from}:\n{out}`)
						end
						t.expect(ok).toBe(true)
						t.expect(index()).toBe("")
					end
				end
			end
		)
	end

	it("a symlinked .cache in another home refuses a pickman check.sh before any check", function()
		local away = `{base}/away`
		fs.writeDir(away)
		if fs.isDir(`{repo}/z-nile/.cache`) then
			fs.removeDir(`{repo}/z-nile/.cache`)
		end
		t.expect(process.exec("ln", { "-s", away, `{repo}/z-nile/.cache` }).ok).toBe(true)
		local ok, out = sh(repo, { `{repo}/pickman/.tracker/issues/f0001/check.sh` }, "sandbox-exec")
		fs.removeFile(`{repo}/z-nile/.cache`)
		t.expect(ok).toBe(false)
		t.expect(string.find(out, "z-nile/.cache is not a plain folder", 1, true) ~= nil).toBe(true)
		t.expect((string.find(out, "PASS", 1, true))).toBe(nil)
		fs.removeDir(base)
	end)
end)
