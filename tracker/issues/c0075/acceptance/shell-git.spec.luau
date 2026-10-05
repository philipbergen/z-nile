--!strict
-- c0810: a command run through the fixture helper (a shell string or a script) can't run git in, make, or retarget a
-- repository or work tree outside the checkout's .cache, however it names one: every command but git itself finds a
-- git shim first on its PATH. Every probe of the real checkout here is read-only (rev-parse, status); every write a
-- wrong shim would let through is aimed at a stand-in in the run's temp folder, never at the real checkout.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{root}/.cache/c0810-shell-git`
local fx = `{base}/fixture`
local other = `{base}/other`

local ID: { [string]: string } = {
	GIT_AUTHOR_NAME = "c0810",
	GIT_AUTHOR_EMAIL = "c0810@example.invalid",
	GIT_COMMITTER_NAME = "c0810",
	GIT_COMMITTER_EMAIL = "c0810@example.invalid",
}

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function shell(script: string): Result
	return fixture.exec(fx, "sh", { "-c", script, "_", root })
end

local function refused(r: Result)
	t.expect(r.ok).toBe(false)
	t.expect(has(r.stderr, "fixture git")).toBe(true)
	t.expect(has(r.stdout, root)).toBe(false) -- git never answered from the real checkout
end

-- refused, or git ignored the setting and stayed in the fixture: either way the real checkout was not reached
local function stayed(r: Result)
	if r.ok then
		t.expect(trim(r.stdout)).toBe(fixture.physical(fx))
	else
		t.expect(has(r.stderr, "fixture git")).toBe(true)
	end
end

local function repo(dir: string)
	fs.writeDir(dir)
	t.expect(process.exec("git", { "init", "-q", "-b", "main", dir }).ok).toBe(true)
	fs.writeFile(`{dir}/a.txt`, "a")
	fixture.git(dir, { "add", "a.txt" }, { env = ID })
	fixture.git(dir, { "commit", "-qm", "first" }, { env = ID })
end

return t.spec("c0810 the fixture helper fences git in the commands it runs", function(it)
	it("sets up two fixture repositories", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		repo(fx)
		repo(other)
	end)

	it("a shell command that changes to the real checkout cannot run git there", function()
		refused(shell('cd "$1" && git rev-parse --show-toplevel'))
	end)

	it("git -C, --git-dir, --work-tree and core.worktree can't reach the real checkout", function()
		refused(shell('git -C "$1" rev-parse --show-toplevel'))
		refused(shell('git --git-dir="$1/.git" rev-parse --show-toplevel'))
		refused(shell('git --git-dir "$1/.git" rev-parse --show-toplevel'))
		refused(shell('git --work-tree="$1" rev-parse --show-toplevel'))
		stayed(shell('git -c core.worktree="$1" rev-parse --show-toplevel'))
		stayed(shell('git -c Core.WorkTree="$1" rev-parse --show-toplevel'))
	end)

	it("a repository variable set inside the command is refused", function()
		refused(shell('GIT_DIR="$1/.git" git rev-parse --show-toplevel'))
		refused(shell('export GIT_WORK_TREE="$1"; git rev-parse --show-toplevel'))
	end)

	it("a script run through the helper gets the same fence", function()
		fs.writeFile(`{fx}/probe.sh`, 'cd "$1" && git rev-parse --show-toplevel\n')
		local r = fixture.exec(fx, "bash", { "probe.sh", root })
		refused(r)
		fs.removeFile(`{fx}/probe.sh`)
	end)

	it("git options and variables pointing at another fixture under .cache work", function()
		local viaOption =
			fixture.exec(fx, "sh", { "-c", 'git --git-dir="$1/.git" log -1 --format=%s', "_", other })
		t.expect(viaOption.ok).toBe(true)
		t.expect(trim(viaOption.stdout)).toBe("first")
		local viaVariable =
			fixture.exec(fx, "sh", { "-c", 'GIT_DIR="$1/.git" git log -1 --format=%s', "_", other })
		t.expect(viaVariable.ok).toBe(true)
		t.expect(trim(viaVariable.stdout)).toBe("first")
	end)

	it("a fixture whose own config points core.worktree at the real checkout is refused", function()
		local moved = `{base}/moved`
		repo(moved)
		fixture.git(moved, { "config", "core.worktree", root })
		-- the helper itself refuses to start in it (its top is now the real checkout), so start in a good fixture
		t.expect((pcall(fixture.exec, moved, "sh", { "-c", "true" }))).toBe(false)
		for _, probe in { "git rev-parse --show-toplevel", "git status --porcelain" } do
			local r = fixture.exec(fx, "sh", { "-c", 'cd "$1" && ' .. probe, "_", moved })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "fixture git")).toBe(true)
		end
	end)

	it("core.worktree set through the environment doesn't reach the real checkout", function()
		stayed(
			shell(
				'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.worktree GIT_CONFIG_VALUE_0="$1" git rev-parse --show-toplevel'
			)
		)
	end)

	it("init, clone and worktree add can't make or retarget a repository outside .cache", function()
		-- a stand-in repository outside .cache (the run's own temp folder): every write here is aimed at it, never at
		-- the real checkout, so a wrong shim changes only the stand-in
		local tmp = process.env.TMPDIR or "/tmp"
		local tag = tostring(os.time()) .. "-" .. tostring(math.random(100000))
		local stand = `{tmp}/c0810-stand-{tag}`
		t.expect(process.exec("git", { "clone", "-q", "--no-hardlinks", other, stand }).ok).toBe(true)
		local function snapshot(): string
			local names = fs.readDir(`{stand}/.git`)
			table.sort(names)
			return table.concat(names, ",") .. "\n" .. fs.readFile(`{stand}/.git/config`)
		end
		local before = snapshot()
		-- a start under .cache that resolves into the temp folder: a ".." from it would land outside
		fs.writeDir(`{tmp}/c0810-out-{tag}`)
		t.expect(process.exec("ln", { "-s", `{tmp}/c0810-out-{tag}`, `{base}/out` }).ok).toBe(true)
		local function denied(script: string, made: string?)
			local r = fixture.exec(fx, "sh", { "-c", script, "_", stand, other, base, tmp, tag })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "fixture git")).toBe(true)
			if made then
				t.expect(fs.isDir(made) or fs.isFile(made)).toBe(false)
			end
		end
		denied('cd "$1" && git init -q') -- would reinitialize the stand-in
		denied('git -C "$1" init -q')
		denied('git init -q "$4/c0810-init-$5"', `{tmp}/c0810-init-{tag}`)
		denied('git clone -q "$2" "$4/c0810-clone-$5"', `{tmp}/c0810-clone-{tag}`)
		denied('cd "$4" && git clone -q "$2" "c0810-clone2-$5"', `{tmp}/c0810-clone2-{tag}`)
		denied('git init -q --separate-git-dir="$4/c0810-sep-$5" "$3/sep-target"', `{tmp}/c0810-sep-{tag}`)
		denied('git init -q --separate-git-dir "$4/c0810-sep2-$5" "$3/sep-target2"', `{tmp}/c0810-sep2-{tag}`)
		-- its nearest existing folder ($3) is under .cache, but git makes new/ and the kernel follows out/ to the temp
		-- folder, so the repository would land there
		denied('git init -q "$3/new/../out/../c0810-escape-$5"', `{tmp}/c0810-escape-{tag}`)
		-- the routes round 2 found: the repository or work tree named by an option or a variable
		denied('GIT_DIR="$4/c0810-gd-$5" git init -q', `{tmp}/c0810-gd-{tag}`)
		denied('git --git-dir="$4/c0810-gd2-$5" init -q', `{tmp}/c0810-gd2-{tag}`)
		denied('GIT_DIR="$1/.git" GIT_WORK_TREE="$PWD" git init -q') -- would write core.worktree into the stand-in
		denied('GIT_WORK_TREE="$4/c0810-wt-$5" git clone -q "$2" "$3/cloned-wt"', `{tmp}/c0810-wt-{tag}`)
		denied('git worktree add -q "$4/c0810-add-$5"', `{tmp}/c0810-add-{tag}`)
		t.expect(snapshot()).toBe(before)
		-- still fine under .cache: a branch option's value, and a repository named by GIT_DIR there
		t.expect(
			fixture.exec(fx, "sh", { "-c", 'git clone -q -b main "$1" "$2/cloned-b"', "_", other, base }).ok
		)
			.toBe(true)
		t.expect(fixture.exec(fx, "sh", { "-c", 'GIT_DIR="$1/made-gd" git init -q', "_", base }).ok)
			.toBe(true)
		t.expect(fs.isDir(`{base}/made-gd`)).toBe(true)
		t.expect(fixture.exec(fx, "sh", { "-c", 'git worktree add -q "$1/wt-ok"', "_", base }).ok).toBe(true)
		fs.removeDir(stand)
		fs.removeDir(`{tmp}/c0810-out-{tag}`)
	end)

	it("a .git symlink into a repository outside .cache is refused", function()
		local tmp = process.env.TMPDIR or "/tmp"
		local stand = `{tmp}/c0810-linked-{tostring(os.time())}`
		t.expect(process.exec("git", { "clone", "-q", "--no-hardlinks", other, stand }).ok).toBe(true)
		fs.writeDir(`{base}/linked`)
		t.expect(process.exec("ln", { "-s", `{stand}/.git`, `{base}/linked/.git` }).ok).toBe(true)
		local index = fs.readFile(`{stand}/.git/index`)
		fs.writeFile(`{base}/linked/new.txt`, "x")
		local r = fixture.exec(fx, "sh", { "-c", 'cd "$1" && git add new.txt', "_", `{base}/linked` })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "fixture git")).toBe(true)
		t.expect(fs.readFile(`{stand}/.git/index`) == index).toBe(true)
		fs.removeDir(stand)
	end)

	it("a command outside any repository is refused", function()
		local r = shell("cd / && git status")
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "fixture git")).toBe(true)
	end)

	it(
		"git in the fixture and in another fixture under .cache still works, and so do init and clone",
		function()
			local here = trim(shell("git rev-parse --show-toplevel").stdout)
			t.expect(here).toBe(fixture.physical(fx))
			local log = fixture.exec(fx, "sh", { "-c", 'cd "$1" && git log -1 --format=%s', "_", other })
			t.expect(log.ok).toBe(true)
			t.expect(trim(log.stdout)).toBe("first")
			t.expect(shell('git -C "$PWD" status --porcelain').ok).toBe(true)
			local made = fixture.exec(
				fx,
				"sh",
				{ "-c", 'git init -q "$1/made" && git clone -q "$2" "$1/cloned"', "_", base, other }
			)
			t.expect(made.ok).toBe(true)
			t.expect(fs.isDir(`{base}/made/.git`)).toBe(true)
			t.expect(fs.isFile(`{base}/cloned/a.txt`)).toBe(true)
			t.expect(shell("git --version").ok).toBe(true)
		end
	)

	it("the helper's own git calls are unchanged", function()
		t.expect(fixture.git(fx, { "rev-parse", "--show-toplevel" })).toBe(fixture.physical(fx))
		t.expect(fixture.git(fx, { "log", "-1", "--format=%s" })).toBe("first")
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
