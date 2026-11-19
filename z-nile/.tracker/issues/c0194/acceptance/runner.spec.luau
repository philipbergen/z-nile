--!strict
-- c0194: the runner's per-run temp folder is a fresh pickman-run.* under this home's .cache/.tmp, the jail closes the rest
-- of .cache/.tmp to the specs, the fixture helper does not take a temporary tree for a fixture, and a run clears the
-- folders no live run owns. The outer-sandbox rule and the clearing rule are pure functions of what the runner reads.
local fence = require("@tests/lib/fence")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

local here = trim(process.exec("pwd", { "-P" }).stdout)
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local REQ = "req" .. "uire" -- keeps literal require text out of this file (graph scanner)
local env = process.env
local jailed = env.PICKMAN_TEST_JAIL == "sandbox-exec"
local tag = trim(process.exec("sh", { "-c", "echo $PPID" }).stdout)

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end

-- The case that tests the live spec jail runs only where the runner jailed itself (macOS, outside any other sandbox).
-- Anywhere else it returns after checking which kind of run this is: Linux, an outer sandbox, a jailed clone and c0075's
-- bubblewrap jail must not turn red on it once it is promoted. On macOS this check.sh proves it ran jailed (a marker),
-- the way c0076's does.
local function jailedHere(): boolean
	if jailed then
		return true
	end
	local label = env.PICKMAN_TEST_JAIL or ""
	t.expect(
		string.sub(label, 1, 4) == "none" or string.sub(label, 1, 14) == "outer sandbox " or label == "bwrap"
	)
		.toBe(true)
	return false
end

return t.spec("c0194 the runner's temp folder", function(it)
	it("TMPDIR is a fresh folder under this home's .cache/.tmp, and a plain mktemp lands in it", function()
		local tmpdir = env.TMPDIR or ""
		t.expect(
			string.match(
				tmpdir,
				"^" .. string.gsub(here, "%p", "%%%0") .. "/%.cache/%.tmp/pickman%-run%.[%w]+$"
			) ~= nil
		).toBe(true)
		local made = trim(process.exec("mktemp", { "-d" }).stdout)
		t.expect(string.sub(made, 1, #tmpdir + 1)).toBe(tmpdir .. "/")
		pcall(fs.removeDir, made)
		-- the Spotlight marker of the folder every suite works in
		t.expect(fs.isFile(`{here}/.cache/.tmp/.metadata_never_index`)).toBe(true)
	end)

	it("the specs can write their own folder and nothing else under .cache/.tmp", function()
		if not jailedHere() then
			return
		end
		local tmpdir = env.TMPDIR or ""
		t.expect((pcall(fs.writeFile, `{tmpdir}/c0194-probe-{tag}`, ""))).toBe(true)
		pcall(fs.removeFile, `{tmpdir}/c0194-probe-{tag}`)
		local top = `{here}/.cache/.tmp`
		-- a sibling folder (where an agent's clone or an earlier run's folder would be), the folder's own files, the
		-- folder itself (no replacing it), and a link made beside the run's folder
		t.expect((pcall(fs.writeFile, `{top}/c0194-sibling-{tag}`, ""))).toBe(false)
		t.expect((pcall(fs.writeFile, `{top}/.luaurc`, "{}"))).toBe(false)
		t.expect(process.exec("touch", { "-c", "-r", top, top }).ok).toBe(false)
		t.expect(process.exec("ln", { "-s", "/nonexistent", `{top}/c0194-link-{tag}` }).ok).toBe(false)
		t.expect(process.exec("mv", { top, `{top}-moved` }).ok).toBe(false)
		t.expect(fs.isDir(top)).toBe(true)
		-- proof for check.sh (AC3) that the jailed branch ran
		pcall(fs.writeDir, `{here}/.cache/c0194-runner`)
		t.expect((pcall(fs.writeFile, `{here}/.cache/c0194-runner/jailed-cases-ran`, ""))).toBe(true)
	end)

	it("a temporary tree is not a fixture: the helper refuses anything under .cache/.tmp", function()
		t.expect(fixture.zone(`{here}/.cache/fx`, here)).toBe(true)
		t.expect(fixture.zone(`{here}/.cache/.tmp/pickman-run.A/x`, here)).toBe(false)
		t.expect(fixture.zone(`{here}/.cache/.tmp`, here)).toBe(false)
		t.expect(fixture.zone(`{here}/.cache/.tmpx/fx`, here)).toBe(true) -- a different folder name
		t.expect(fixture.zone(`{here}/.cache-other/fx`, here)).toBe(false)
		t.expect(fixture.zone(`/elsewhere/.cache/fx`, here)).toBe(false)
		-- and the check itself, on a real repository inside the run's folder
		local tmpdir = env.TMPDIR or ""
		must(process.exec("git", { "init", "-q", `{tmpdir}/not-a-fixture` }), "git init")
		t.expect(function()
			fixture.git(`{tmpdir}/not-a-fixture`, { "status" })
		end).toThrow("not a fixture repository")
	end)

	-- fixture.check, run in a child Lune from a stand-in checkout: a repository in this stand-in's own .cache is a
	-- fixture; one in some other .cache (not under .tmp) is not. Inside the jail the only place such a repository can be made
	-- is under this home's .cache, so the checker's point of view moves instead of the repository.
	it("the helper refuses a repository under another .cache folder than the checkout it runs in", function()
		local stand = `{here}/.cache/c0194-zone`
		local foreign = `{here}/.cache/c0194-foreign`
		for _, d in { stand, foreign } do
			must(process.exec("rm", { "-rf", d }), "rm")
		end
		fs.writeDir(stand)
		must(process.exec("git", { "init", "-q", `{stand}/.cache/fx` }), "git init")
		must(process.exec("git", { "init", "-q", `{foreign}/.cache/fx` }), "git init")
		fs.writeFile(`{stand}/.luaurc`, `\{"aliases":\{"tests":"{root}/z-nile/tests"\}\}`)
		fs.writeFile(
			`{stand}/probe.luau`,
			`local fixture = {REQ}("@tests/lib/fixture")\n`
				.. 'print(pcall(fixture.check, ".cache/fx"))\n'
				.. `print(pcall(fixture.check, "{foreign}/.cache/fx"))\n`
		)
		local r = process.exec("lune", { "run", "probe" }, { cwd = stand })
		local lines = string.split(trim(r.stdout), "\n")
		t.expect(lines[1]).toBe("true")
		t.expect(string.sub(lines[2] or "", 1, 5)).toBe("false")
		t.expect(string.find(lines[2] or "", "not a fixture repository", 1, true) ~= nil).toBe(true)
	end)

	it(
		"an outer sandbox is asked about the home's, the checkout's, the main checkout's and TMPDIR's folders, each once",
		function()
			local function paths(list: { fence.TmpSource }): string
				local out: { string } = {}
				for _, f in list do
					table.insert(
						out,
						`{f.path}{if f.ownHome then " own" else ""}{if f.fixture then " fixture" else ""}`
					)
				end
				return table.concat(out, "\n")
			end
			-- a worktree run, the session's TMPDIR in the main checkout
			t.expect(
				paths(fence.tmpFolders("/m/.worktree/w/z-nile", "/m/.worktree/w", "/m", "/m/.cache/.tmp", ""))
			)
				.toBe("/m/.worktree/w/z-nile/.cache/.tmp own\n/m/.worktree/w/.cache/.tmp\n/m/.cache/.tmp")
			-- no session TMPDIR: the main checkout's folder (where agents' clones are) is still asked about
			t.expect(paths(fence.tmpFolders("/m/.worktree/w/z-nile", "/m/.worktree/w", "/m", nil, "")))
				.toBe("/m/.worktree/w/z-nile/.cache/.tmp own\n/m/.worktree/w/.cache/.tmp\n/m/.cache/.tmp")
			-- a run folder as TMPDIR names the .tmp that holds it: the nearest .cache/.tmp of the path (a clone is inside another)
			t.expect(
				paths(
					fence.tmpFolders(
						"/c/z-nile",
						"/c",
						"/c",
						"/x/.cache/.tmp/gate.A/repo/.cache/.tmp/pickman-run.B",
						""
					)
				)
			).toBe("/c/z-nile/.cache/.tmp own\n/c/.cache/.tmp\n/x/.cache/.tmp/gate.A/repo/.cache/.tmp")
			-- run at the root: the home and the root are one folder, and it is the run's own
			t.expect(paths(fence.tmpFolders("/c", "/c", "/c", nil, ""))).toBe("/c/.cache/.tmp own")
			-- folders under a ceiling .cache are a guarded checkout's fixtures
			t.expect(
				paths(
					fence.tmpFolders(
						"/o/.cache/fx/z-nile",
						"/o/.cache/fx",
						"/o/.cache/fx",
						nil,
						"/o/.cache:/o/z-nile/.cache"
					)
				)
			).toBe("/o/.cache/fx/z-nile/.cache/.tmp own fixture\n/o/.cache/fx/.cache/.tmp fixture")
		end
	)

	it("an outer sandbox is accepted only while no .cache/.tmp folder is open to the specs", function()
		local function folder(over: { [string]: any }): fence.TmpFolder
			local f =
				{ path = "/co/.cache/.tmp", writable = true, entries = {}, ownHome = false, fixture = false }
			for k, v in over do
				(f :: any)[k] = v
			end
			return f :: fence.TmpFolder
		end
		-- the main checkout's or the root's folder: writable at all is a leak, empty or not
		t.expect(#fence.tmpLeaks({ folder({}) })).toBe(1)
		t.expect(#fence.tmpLeaks({ folder({ entries = { "agent-clone.X" } }) })).toBe(1)
		t.expect(#fence.tmpLeaks({ folder({ writable = false, entries = { "agent-clone.X" } }) })).toBe(0)
		-- a fixture's folder holds no agent's tree
		t.expect(#fence.tmpLeaks({ folder({ fixture = true }) })).toBe(0)
		-- this run's home: only run folders and the folder's dot-files are fine
		t.expect(#fence.tmpLeaks({ folder({ ownHome = true, entries = { "pickman-run.A", ".luaurc" } }) }))
			.toBe(0)
		t.expect(
			#fence.tmpLeaks({ folder({ ownHome = true, entries = { "pickman-run.A", "agent-clone.X" } }) })
		)
			.toBe(1)
	end)

	-- the spec jail's rules as a pure function of the paths (a live sandbox cannot start inside another, so the rules are
	-- pinned here, and the live case runs in the raft's own gate)
	it(
		"the spec jail lets a spec write the cache, minus .tmp, plus the run's own folder, in that order",
		function()
			local profile = fence.profileFor(
				"/w/.cache",
				"/p/w/.cache",
				"/w/.cache/.tmp/pickman-run.A",
				"/p/w/.cache/.tmp/pickman-run.A"
			)
			local function at(part: string, from: number?): number
				return (string.find(profile, part, from or 1, true)) or -1
			end
			local allowCache = at('(allow file-write* (subpath "/w/.cache"))')
			local denyTmp = at('(deny file-write* (subpath "/w/.cache/.tmp"))')
			local allowRun = at('(allow file-write* (subpath "/w/.cache/.tmp/pickman-run.A"))')
			local denyEntry = at('(deny file-write* (literal "/w/.cache"))')
			t.expect(allowCache > 0 and denyTmp > allowCache and allowRun > denyTmp and denyEntry > allowRun)
				.toBe(true)
			for _, part in
				{
					'(deny file-write* (subpath "/"))',
					'(allow file-write* (subpath "/dev"))',
					'(allow file-write* (subpath "/p/w/.cache"))',
					'(deny file-write* (subpath "/p/w/.cache/.tmp"))',
					'(allow file-write* (subpath "/p/w/.cache/.tmp/pickman-run.A"))',
					'(deny file-write* (literal "/p/w/.cache"))',
					'(deny file-write-create (require-all (vnode-type SYMLINK) (regex #"^/w/\\.cache/[^/]+$")))',
					"(deny network-outbound (remote ip))",
					"(deny signal (with no-log))",
					"(allow signal (target same-sandbox))",
				}
			do
				t.expect(at(part) > 0).toBe(true)
			end
			local allows = 0
			for _ in string.gmatch(profile, "%(allow file%-write%*") do
				allows += 1
			end
			t.expect(allows).toBe(5) -- /dev, and the cache and the run folder, each written and resolved
		end
	)

	it("only a run folder whose owner no longer holds is cleared", function()
		t.expect(fence.clearable("pickman-run.A", false, false)).toBe(true)
		t.expect(fence.clearable("pickman-run.A", false, true)).toBe(false) -- a live run waiting for the lock
		t.expect(fence.clearable("pickman-run.A", true, false)).toBe(false) -- a link
		t.expect(fence.clearable("agent-clone.A", false, false)).toBe(false) -- not a run folder
		t.expect(fence.clearable("tmp.A", false, false)).toBe(false)
	end)

	-- a copy of the runner in a fixture repository, run as a top-level run (inside this jail it is an outer-sandbox run),
	-- with `planted` made under its z-nile/.cache/.tmp first (a record, when given, is the folder's owner file); returns
	-- the result and the fixture's path
	type Planted = { name: string, record: string? }
	local function copiedRun(name: string, planted: { Planted }): (Result, string)
		local repo = `{here}/.cache/{name}`
		if fs.isDir(repo) then
			fs.removeDir(repo)
		end
		fs.writeDir(`{repo}/z-nile/tests/probe`)
		fs.writeDir(`{repo}/z-nile/lib`)
		local function copyTree(rel: string)
			local src = `{root}/{rel}`
			if fs.isDir(src) then
				fs.writeDir(`{repo}/{rel}`)
				for _, entry in fs.readDir(src) do
					copyTree(`{rel}/{entry}`)
				end
			elseif fs.isFile(src) then
				fs.writeFile(`{repo}/{rel}`, fs.readFile(src))
			end
		end
		for _, rel in
			{
				"z-nile/tests/run.luau",
				"z-nile/tests/lib",
				"z-nile/.luaurc",
				"z-nile/lib/ac.sh",
				"z-nile/lib/fence.sh",
				"z-nile/lib/git-hooks",
				".luaurc",
				"rokit.toml",
				".gitignore",
			}
		do
			copyTree(rel)
		end
		must(process.exec("chmod", { "-R", "+x", `{repo}/z-nile/lib/git-hooks` }), "chmod")
		fs.writeFile(
			`{repo}/z-nile/tests/probe/seen.spec.luau`,
			`--!strict\nlocal fs = {REQ}("@lune/fs")\nlocal process = {REQ}("@lune/process")\nlocal t = {REQ}("@tests/lib/t")\n`
				.. 'return t.spec("seen", function(it)\n\tit("records its TMPDIR", function()\n'
				.. '\t\tfs.writeFile(".cache/seen-tmpdir", process.env.TMPDIR or "")\n'
				.. "\t\tt.expect(1).toBe(1)\n\tend)\nend)\n"
		)
		for _, p in planted do
			fs.writeDir(`{repo}/z-nile/.cache/.tmp/{p.name}`)
			fs.writeFile(`{repo}/z-nile/.cache/.tmp/{p.name}/left`, "x")
			if p.record then
				fs.writeFile(`{repo}/z-nile/.cache/.tmp/{p.name}/.pickman-owner`, p.record)
			end
		end
		must(process.exec("git", { "init", "-q", "-b", "main", repo }), "git init")
		must(process.exec("git", { "add", "-A" }, { cwd = repo }), "git add")
		must(
			process.exec(
				"git",
				{ "-c", "user.name=dev", "-c", "user.email=dev@example.invalid", "commit", "-qm", "runner" },
				{ cwd = repo }
			),
			"git commit"
		)
		local r = process.exec(
			"lune",
			{ "run", "tests/run", "--", "tests/probe/seen.spec.luau" },
			{ cwd = `{repo}/z-nile`, env = { PICKMAN_TEST_FENCE = "" } }
		)
		return r, repo
	end

	it(
		"a run clears the run folders nothing owns and keeps a live run's, and removes its own at the end",
		function()
			local mine = `{tag}\t{fence.startOf(tag) or ""}\n`
			local r, repo = copiedRun("c0194-stray", {
				{ name = "pickman-run.STRAY" }, -- no record: an older runner's
				{ name = "pickman-run.DEAD", record = "99997\tNo Such Start\n" },
				{ name = "pickman-run.LIVE", record = mine }, -- a run waiting for the lock, owned by this spec's process
			})
			if not r.ok then
				error(r.stdout .. r.stderr)
			end
			local seen = trim(fs.readFile(`{repo}/z-nile/.cache/seen-tmpdir`))
			t.expect((string.find(seen, `{repo}/z-nile/.cache/.tmp/pickman-run.`, 1, true))).toBe(1)
			t.expect(fs.isDir(`{repo}/z-nile/.cache/.tmp/pickman-run.LIVE`)).toBe(true)
			t.expect(fs.isDir(`{repo}/z-nile/.cache/.tmp/pickman-run.STRAY`)).toBe(false)
			t.expect(fs.isDir(`{repo}/z-nile/.cache/.tmp/pickman-run.DEAD`)).toBe(false)
			local mineOnly = 0
			for _, name in fs.readDir(`{repo}/z-nile/.cache/.tmp`) do
				if string.sub(name, 1, 12) == "pickman-run." and name ~= "pickman-run.LIVE" then
					mineOnly += 1
				end
			end
			t.expect(mineOnly).toBe(0) -- its own folder is gone
			t.expect(fs.isFile(`{repo}/z-nile/.cache/.tmp/.metadata_never_index`)).toBe(true)
			fs.removeDir(repo)
		end
	)
end)
