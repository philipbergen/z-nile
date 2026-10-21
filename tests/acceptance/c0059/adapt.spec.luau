--!strict
-- c0650: R0200 (c0510) landed before the guards; this adapts it to them. Its promoted specs drop their own fence,
-- the gate scan lets them name only what their fixture hooks unset, and the publisher pushes nothing from a
-- repository the guards protect (a check run at the real root must not publish tracker state to origin/main).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{root}/.cache/c0650-adapt`
local repo = `{base}/scan` -- the runner, the guards, the gate spec and c0510's specs
local work = `{base}/work` -- a tracker clone with an origin
local wt = `{base}/wt` -- a linked worktree of it: tracker.sh new refuses to run in a main checkout with an origin
local origin = `{base}/origin.git`
-- c0062 split the commands spec into parts: every `commands-*.spec.luau`, then the publish spec
local function c0510Specs(): { string }
	local out: { string } = {}
	for _, name in fs.readDir(`{root}/tests/acceptance/c0053`) do
		if string.match(name, "^commands%-.+%.spec%.luau$") then
			table.insert(out, `tests/acceptance/c0053/{name}`)
		end
	end
	table.sort(out)
	table.insert(out, "tests/acceptance/c0053/publish.spec.luau")
	return out
end
local C0510 = c0510Specs()
local ID = { "-c", "user.name=e2e", "-c", "user.email=e2e@example.invalid" }

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

-- Runs git in a fixture this spec created, after checking that the directory is that fixture's own top.
local function git(dir: string, args: { string }): string
	local top = must(process.exec("git", { "rev-parse", "--show-toplevel" }, { cwd = dir }), "rev-parse")
	if top ~= must(process.exec("pwd", { "-P" }, { cwd = dir }), "pwd") then
		error(`{dir} is not a fixture repository; not running git there`)
	end
	return must(process.exec("git", args, { cwd = dir }), `git {table.concat(args, " ")}`)
end

local function originTip(): string
	return must(process.exec("git", { "rev-parse", "main" }, { cwd = origin }), "origin tip")
end

local function copyTree(from: string, to: string)
	if fs.isDir(from) then
		fs.writeDir(to)
		for _, name in fs.readDir(from) do
			copyTree(`{from}/{name}`, `{to}/{name}`)
		end
	elseif fs.isFile(from) then
		fs.writeFile(to, fs.readFile(from))
	end
end

local function copyInto(dest: string, rels: { string })
	for _, rel in rels do
		local parent = string.match(`{dest}/{rel}`, "^(.*)/[^/]+$")
		if parent then
			fs.writeDir(parent)
		end
		copyTree(`{root}/{rel}`, `{dest}/{rel}`)
	end
	if fs.isDir(`{dest}/scripts`) then
		must(process.exec("chmod", { "-R", "+x", `{dest}/scripts` }), "chmod")
	end
	-- c0114 override: the entry, the guards and the engine moved to ./zn and z-nile/
	for _, rel in { "zn", "z-nile/lib" } do
		if fs.isFile(`{dest}/{rel}`) or fs.isDir(`{dest}/{rel}`) then
			must(process.exec("chmod", { "-R", "+x", `{dest}/{rel}` }), "chmod")
		end
	end
end

local function gate(): string
	local r = process.exec(
		"lune",
		{ "run", "tests/run", "--", "tests/tooling/repo-fence.spec.luau" },
		{ cwd = repo, env = { PICKMAN_TEST_FENCE = "" } }
	)
	return r.stdout .. r.stderr
end

local ready = false
local function setUp()
	if not ready then
		error("setup did not finish: not running this case", 2)
	end
end

return t.spec("c0650 R0200 lives by the guards", function(it)
	it("sets up a scan copy and a tracker checkout with an origin", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		copyInto(repo, {
			"tests/run.luau",
			"tests/lib",
			"zn",
			"scripts",
			"z-nile/engine",
			"z-nile/lib",
			"z-nile/templates",
			"z-nile/vendor",
			"z-nile/projects.toml",
			"tests/tooling/repo-fence.spec.luau",
			".luaurc",
		})
		copyInto(repo, C0510)
		must(process.exec("git", { "init", "-q", "-b", "main", repo }), "git init scan")
		copyInto(work, {
			"zn",
			"scripts",
			"z-nile/engine",
			"z-nile/lib",
			"z-nile/templates",
			"z-nile/vendor",
			"z-nile/projects.toml",
			"rokit.toml",
			".luaurc",
		})
		must(process.exec("git", { "init", "-q", "--bare", "-b", "main", origin }), "git init origin")
		must(process.exec("git", { "init", "-q", "-b", "main", work }), "git init work")
		git(work, { "config", "user.name", "e2e" })
		git(work, { "config", "user.email", "e2e@example.invalid" })
		git(work, { "add", "-A" })
		git(work, { ID[1], ID[2], ID[3], ID[4], "commit", "-q", "-m", "tracker" })
		git(work, { "remote", "add", "origin", origin })
		git(work, { "push", "-q", "origin", "main" })
		git(work, { "fetch", "-q", "origin" })
		git(work, { "branch", "-q", "--set-upstream-to=origin/main" })
		git(work, { "worktree", "add", "-q", "-b", "work-wt", wt, "origin/main" })
		ready = true
	end)

	it("c0510's specs set no fence of their own, and pass the gate's scan", function()
		setUp()
		for _, path in C0510 do
			t.expect(string.find(fs.readFile(`{root}/{path}`), "GIT_CEILING_DIRECTORIES", 1, true) == nil)
				.toBe(true)
		end
		local out = gate()
		t.expect(string.find(out, "could not load spec", 1, true) == nil).toBe(true)
		t.expect(string.find(out, " spec files", 1, true) ~= nil).toBe(true)
		local scans = {
			"no spec, check.sh or script switches a guard off or points git elsewhere",
			"every fixture commits as <name>@example.invalid",
		}
		for _, case in scans do
			if string.find(out, `:: {case}`, 1, true) then
				error(out)
			end
		end
	end)

	it("c0510's specs may name only what their fixture hooks unset", function()
		setUp()
		local path = `{repo}/{C0510[1]}`
		local before = fs.readFile(path)
		-- planted name, and the scan's list entry it reports
		local planted = {
			{ "GIT_CEILING_" .. "DIRECTORIES", "GIT_CEILING_" .. "DIRECTORIES" },
			{ "GIT_COMMON_" .. "DIR", "GIT_COMMON_" .. "DIR" },
			{ "GIT_CONFIG_" .. "COUNT", "GIT_CONFIG_" },
		}
		for _, pair in planted do
			local name, reported = pair[1], pair[2]
			fs.writeFile(path, before .. `\n-- {name}\n`)
			local out = gate()
			fs.writeFile(path, before)
			if not string.find(out, `{C0510[1]} names {reported}\n`, 1, true) then
				error(`the scan let c0510's spec name {name}:\n{out}`)
			end
		end
	end)

	it("a check run publishes nothing, says so, and still works", function()
		setUp()
		local tip, head = originTip(), git(wt, { "rev-parse", "HEAD" })
		local guarded = process.exec("bash", {
			"-c",
			'source z-nile/lib/fence.sh || exit 1; pickman_fence "$PWD" && bash scripts/tracker.sh new issue c probe-one',
		}, { cwd = wt })
		local said = guarded.stdout .. guarded.stderr
		if not guarded.ok then
			error(said)
		end
		t.expect(string.find(said, "not publishing", 1, true) ~= nil).toBe(true)
		t.expect(originTip()).toBe(tip)
		t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(head)
		-- the stub is made locally, as with PICKMAN_PUBLISH=0
		local status =
			process.exec("git", { "status", "--porcelain", "--untracked-files=all" }, { cwd = wt }).stdout
		t.expect(
			string.find(status, "probe-one", 1, true) ~= nil
				or string.find(status, "pickman/.tracker/issues/c", 1, true) ~= nil
		).toBe(true)
	end)

	it("outside the guards' protection the same command publishes", function()
		setUp()
		local tip = originTip()
		local r = process.exec(
			"bash",
			{ "scripts/tracker.sh", "new", "issue", "c", "probe-two" },
			{ cwd = wt }
		)
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		t.expect(string.find(r.stdout .. r.stderr, "not publishing", 1, true) == nil).toBe(true)
		t.expect(originTip() ~= tip).toBe(true)
	end)

	it("a check run's status move publishes nothing either, and says so", function()
		setUp()
		-- the issue the previous case published
		local id: string? = nil
		-- c0120 override: the copied registry puts pickman's items in pickman/.tracker
		for _, dir in fs.readDir(`{wt}/pickman/.tracker/issues`) do
			local doc = `{wt}/pickman/.tracker/issues/{dir}/{dir}.md`
			if fs.isFile(doc) and string.find(fs.readFile(doc), "probe-two", 1, true) then
				id = dir
			end
		end
		if not id then
			error("the published probe-two issue is not in the worktree")
		end
		local tip, head = originTip(), git(wt, { "rev-parse", "HEAD" })
		local guarded = process.exec("bash", {
			"-c",
			'source z-nile/lib/fence.sh || exit 1; pickman_fence "$PWD" && bash scripts/tracker.sh status "$1" preparing',
			"_",
			id,
		}, { cwd = wt })
		t.expect(string.find(guarded.stdout .. guarded.stderr, "not publishing", 1, true) ~= nil).toBe(true)
		t.expect(originTip()).toBe(tip)
		t.expect(git(wt, { "rev-parse", "HEAD" })).toBe(head)
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
