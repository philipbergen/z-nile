--!strict
-- No check may change the real repository (testing skill, "Specs never touch the real repository").
-- tests/lib/fence.luau and scripts/lib/fence.sh enforce it for every run; this spec proves, on every gate
-- run, that the guards are on here, and that no spec, check.sh or script switches them off. It never tries
-- a write against this repository: the ref guard is proven by running its hook the way git would.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

local here = trim(process.exec("pwd", { "-P" }).stdout)
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
}
-- The guards themselves and their own specs, which must name them, wherever they are in their lifecycle.
-- Names a file may use for a stated reason, each reviewed (review skill, Repository safety). Nothing else in
-- the file may name them.
local ALLOWED: { [string]: { [string]: string } } = {
	-- c0510 (R0200, landed first): its fixture hooks unset what git exports to a hook, so that their own git calls
	-- reach the right repository; and until c0650 its specs set their own ceiling, from before these guards
	["tests/acceptance/c0510/commands.spec.luau"] = {
		GIT_DIR = "fixture hook",
		GIT_INDEX_FILE = "fixture hook",
		GIT_WORK_TREE = "fixture hook",
		GIT_CEILING_DIRECTORIES = "own fence, removed by c0650",
	},
	["tests/acceptance/c0510/publish.spec.luau"] = {
		GIT_DIR = "fixture hook",
		GIT_INDEX_FILE = "fixture hook",
		GIT_WORK_TREE = "fixture hook",
		GIT_CEILING_DIRECTORIES = "own fence, removed by c0650",
	},
}
local EXEMPT: { [string]: boolean } = {
	["tests/lib/fence.luau"] = true,
	["scripts/lib/fence.sh"] = true,
	["tests/tooling/repo-fence.spec.luau"] = true,
	["tracker/issues/done/c0640/check.sh"] = true,
}
for _, dir in
	{ "tracker/issues/c0640/acceptance", "tracker/issues/active/c0640/acceptance", "tests/acceptance/c0640" }
do
	EXEMPT[`{dir}/fence.spec.luau`] = true
	EXEMPT[`{dir}/lock.spec.luau`] = true
	EXEMPT[(string.gsub(dir, "/acceptance$", "")) .. "/check.sh"] = true -- the fence's own checks
end
-- The guard's own hooks (and their helper .repo.sh) name what they guard.
local EXEMPT_DIRS = { "scripts/lib/git-hooks/" }
local function exempt(path: string): boolean
	for _, dir in EXEMPT_DIRS do
		if string.sub(path, 1, #dir) == dir then
			return true
		end
	end
	return EXEMPT[path] == true
end

local function files(dir: string, out: { string })
	if not fs.isDir(dir) then
		return
	end
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			files(path, out)
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

-- What runs as a check today: specs and their libraries (tests/), scripts, and every check.sh. Acceptance
-- specs prepared under tracker/ are scanned once promoted into tests/, which is when they start to run.
local function sources(): { string }
	local all: { string } = {}
	for _, dir in { "tests", "scripts" } do
		files(dir, all)
	end
	local checks: { string } = {}
	files("tracker", checks)
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
		local hooks = `{here}/scripts/lib/git-hooks`
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
	end)

	it("specs have no GitHub credentials and push only into fixtures", function()
		t.expect(env.GH_TOKEN).toBe(nil)
		t.expect(env.GITHUB_TOKEN).toBe(nil)
		t.expect(env.SSH_AUTH_SOCK).toBe(nil)
		t.expect(env.GH_CONFIG_DIR).toBe(`{here}/.cache/gh-none`)
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
		local hooks = `{here}/scripts/lib/git-hooks`
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
				local text = string.lower(fs.readFile(path)) -- git config keys are case-insensitive: core.hookspath
				local allowed = ALLOWED[path] or {}
				for _, name in NAMES do
					if not allowed[name] and string.find(text, string.lower(name), 1, true) then
						table.insert(bad, `{path} names {name}`)
					end
				end
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
			for email in string.gmatch(fs.readFile(path), "user%.email[^@\n]-([%w%.%-_]+@[%w%.%-]+)") do
				if not string.match(email, "@example%.invalid$") then
					table.insert(bad, `{path}: {email}`)
				end
			end
		end
		if #bad > 0 then
			error(
				"fixture identities must be <name>@example.invalid (the tripwire relies on it):\n  "
					.. table.concat(bad, "\n  ")
			)
		end
	end)
end)
