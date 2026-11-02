--!strict
-- c0178 AC3: trackerfix.new builds its fixture from the packed seed image (engine.seed): a bare origin and two clones,
-- all holding one commit "seed" authored by the fixture's name, with the files the caller seeded and the skills' lessons
-- unless noLessons. The second clone (`other`) is made the first time a fixture helper is asked to work in it. The
-- fixture is copies (no hardlink into the image), a bounded number of files, and next to no processes beyond its
-- clones. Fixtures under .cache/c0178-seed*; the images are the real ones in images.dir().
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local images = require("@tests/lib/images")
local process = require("@lune/process")
local swept = require("@tests/lib/swept")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local HOME = fixture.physical(".") :: string
local BASE = `{HOME}/.cache/c0178-seed`
local REQ = "require" -- built by concatenation: a literal require in a string would join the graph

local function out(cmd: string, args: { string }, cwd: string?): string
	local r = process.exec(cmd, args, { cwd = cwd })
	if not r.ok then
		error(`{cmd} {table.concat(args, " ")} failed: {r.stderr}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function write(path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(parent)
	end
	fs.writeFile(path, text)
end

local function lines(text: string): { string }
	local list = {}
	for line in string.gmatch(text, "[^\n]+") do
		table.insert(list, line)
	end
	return list
end

local function files(dir: string): number
	return #lines(out("find", { ".", "-type", "f" }, dir))
end

local function count(list: { string }, prefix: string): number
	local n = 0
	for _, l in list do
		if string.sub(l, 1, #prefix) == prefix then
			n += 1
		end
	end
	return n
end

local f: trackerfix.Fixture
local plain: trackerfix.Fixture
local bare: trackerfix.Fixture

return t.spec("c0178 trackerfix.new from the seed image", function(it)
	it(
		"builds a bare origin and two clones that hold the same single seed commit, authored by the fixture's name",
		function()
			f = trackerfix.new(
				"c0178-seed-a",
				{ ["notes/extra.txt"] = "extra\n", [".gitignore"] = "mine/\n" }
			)
			t.expect(fixture.git(f.origin, { "rev-list", "--count", "main" })).toBe("1")
			t.expect(fixture.git(f.origin, { "rev-list", "--max-parents=0", "main" }))
				.toBe(fixture.git(f.origin, { "rev-parse", "main" }))
			t.expect(fixture.git(f.origin, { "log", "-1", "--format=%s|%an|%ae|%cn|%ce", "main" }))
				.toBe("seed|c0178-seed-a|c0178-seed-a@example.invalid|c0178-seed-a|c0178-seed-a@example.invalid")
			local tip = fixture.git(f.origin, { "rev-parse", "main" })
			for _, clone in { f.main, f.other } do
				t.expect(fixture.git(clone, { "rev-parse", "HEAD" })).toBe(tip)
				t.expect(fixture.git(clone, { "rev-parse", "origin/main" })).toBe(tip)
				t.expect(fixture.git(clone, { "status", "--porcelain" })).toBe("")
				t.expect(fixture.git(clone, { "config", "remote.origin.url" })).toBe(f.origin)
				t.expect(fixture.git(clone, { "config", "user.email" })).toBe("c0178-seed-a@example.invalid")
				t.expect(fixture.git(clone, { "rev-parse", "--abbrev-ref", "main@{upstream}" }))
					.toBe("origin/main")
			end
			-- the origin has no remote of its own: the image's path (or main's) is not the fixture's business
			t.expect(fixture.git(f.origin, { "remote" })).toBe("")
			t.expect(fixture.git(f.origin, { "rev-parse", "--is-bare-repository" })).toBe("true")
		end
	)

	it("the seeded files are in the commit and in both clones, over the tooling's own", function()
		t.expect(fixture.git(f.origin, { "show", "main:notes/extra.txt" })).toBe("extra")
		t.expect(fixture.git(f.origin, { "show", "main:.gitignore" })).toBe("mine/") -- the caller's file, not the image's
		for _, clone in { f.main, f.other } do
			t.expect(fs.readFile(`{clone}/notes/extra.txt`)).toBe("extra\n")
			t.expect(fs.isFile(`{clone}/zn`)).toBe(true)
			t.expect(fs.isFile(`{clone}/z-nile/engine/main.luau`)).toBe(true)
			t.expect(fs.readFile(`{clone}/z-nile/projects.toml`)).toBe(engine.REGISTRY)
			for _, root in engine.ROOTS do
				for _, d in { "issues/active", "issues/done", "rafts/active", "rafts/done" } do
					t.expect(fs.isFile(`{clone}/{root}/{d}/.gitkeep`)).toBe(true)
				end
			end
			t.expect(fs.isFile(`{clone}/z-nile/next`)).toBe(false) -- no counter, no items: the old numbering
			t.expect(fs.isDir(`{clone}/z-nile/tests`)).toBe(false)
		end
		t.expect(fs.isDir(`{f.base}/seed`)).toBe(false)
	end)

	it(
		"`other` is not on disk until a fixture helper is asked to work in it, and then it is the terminal the old setup made: at the seed",
		function()
			local fresh = trackerfix.new("c0178-seed-lazy")
			local seedTip = fixture.git(fresh.main, { "rev-parse", "HEAD" })
			t.expect(fs.isDir(fresh.other)).toBe(false)
			t.expect(fresh.other).toBe(`{fresh.base}/other`)
			t.expect(fs.isDir(fresh.main)).toBe(true)
			-- one more commit lands on the origin before `other` is first used
			write(`{fresh.main}/later.txt`, "later\n")
			fixture.git(fresh.main, { "add", "-A" })
			fixture.git(fresh.main, { "commit", "-q", "-m", "later" })
			fixture.git(fresh.main, { "push", "-q", "origin", "HEAD:main" })
			fixture.git(fresh.main, { "push", "-q", "origin", "HEAD:refs/heads/side" })
			-- made by this very call: still at the seed, the origin ahead of it, only the seed's branch known
			t.expect(fixture.git(fresh.other, { "rev-parse", "HEAD" })).toBe(seedTip)
			t.expect(fixture.git(fresh.other, { "rev-parse", "origin/main" })).toBe(seedTip)
			t.expect(fixture.git(fresh.other, { "branch", "-r" }))
				.toBe("origin/HEAD -> origin/main\n  origin/main")
			t.expect(fixture.git(fresh.other, { "rev-parse", "main@{upstream}" })).toBe(seedTip)
			t.expect(fs.isDir(fresh.other)).toBe(true)
			t.expect(fixture.git(fresh.other, { "config", "user.email" }))
				.toBe("c0178-seed-lazy@example.invalid")
			-- a terminal that is behind stays behind: its own commit is rejected until it pulls
			write(`{fresh.other}/mine.txt`, "mine\n")
			fixture.git(fresh.other, { "add", "-A" })
			fixture.git(fresh.other, { "commit", "-q", "-m", "mine" })
			t.expect(fixture.exec(fresh.other, "git", { "push", "-q", "origin", "HEAD:main" }).ok).toBe(false)
			-- used again, it is the same folder, not made again
			t.expect(fixture.git(fresh.other, { "log", "-1", "--format=%s" })).toBe("mine")
		end
	)

	it(
		"trackerfix.elsewhere makes `other` when it is the first to use it, and the commit reaches the origin",
		function()
			local fresh = trackerfix.new("c0178-seed-else")
			t.expect(fs.isDir(fresh.other)).toBe(false)
			trackerfix.elsewhere(fresh, { ["from/other.txt"] = "x\n" }, "from another terminal")
			t.expect(fs.isDir(fresh.other)).toBe(true)
			t.expect(fixture.git(fresh.origin, { "log", "-1", "--format=%s", "main" }))
				.toBe("from another terminal")
			t.expect(fixture.git(fresh.origin, { "show", "main:from/other.txt" })).toBe("x")
		end
	)

	it("a fixture with no seeded files is the image's commit under the fixture's name", function()
		plain = trackerfix.new("c0178-seed-plain")
		t.expect(fixture.git(plain.origin, { "rev-list", "--count", "main" })).toBe("1")
		t.expect(fixture.git(plain.origin, { "log", "-1", "--format=%an|%ae", "main" }))
			.toBe("c0178-seed-plain|c0178-seed-plain@example.invalid")
		t.expect(fixture.git(plain.other, { "rev-parse", "HEAD" }))
			.toBe(fixture.git(plain.origin, { "rev-parse", "main" }))
		t.expect(fixture.git(plain.main, { "show", "HEAD:.gitignore" })).toBe(".cache/\n.worktree/")
	end)

	it(
		"the skills' lessons are in the default fixture and out of the noLessons one, in every skill",
		function()
			local lessons = out("find", { "z-nile/skills", "-path", "*/lessons/*.md" }, f.main)
			t.expect(#lines(lessons) > 0).toBe(true)
			bare = trackerfix.new("c0178-seed-bare", nil, { noLessons = true })
			fixture.git(bare.other, { "status", "--porcelain" }) -- makes `other`
			for _, clone in { bare.main, bare.other } do
				t.expect(out("find", { "z-nile/skills", "-path", "*/lessons/*" }, clone)).toBe("")
				t.expect(fs.isFile(`{clone}/z-nile/skills/zz-test/SKILL.md`)).toBe(true) -- the skills themselves stay
			end
			t.expect(
				fixture.git(bare.origin, { "ls-tree", "-r", "--name-only", "main", "z-nile/skills" }) ~= ""
			)
				.toBe(true)
			local tracked = fixture.git(bare.origin, { "ls-tree", "-r", "--name-only", "main" })
			t.expect(string.find(tracked, "/lessons/", 1, true) == nil).toBe(true)
		end
	)

	it("a second fixture in the same process builds no image", function()
		local before = images.builds()
		local dirBefore = fs.readDir(images.dir())
		local again = trackerfix.new("c0178-seed-again", { ["x.txt"] = "x\n" })
		t.expect(images.builds()).toBe(before)
		t.expect(#fs.readDir(images.dir())).toBe(#dirBefore)
		t.expect(fixture.git(again.origin, { "rev-list", "--count", "main" })).toBe("1")
	end)

	it("rebuilding a fixture under the same name replaces the old one", function()
		write(`{f.main}/marker.txt`, "old fixture\n")
		local again = trackerfix.new("c0178-seed-a", { ["notes/extra.txt"] = "second\n" })
		t.expect(again.base).toBe(f.base)
		t.expect(fs.isFile(`{again.main}/marker.txt`)).toBe(false)
		t.expect(fs.readFile(`{again.main}/notes/extra.txt`)).toBe("second\n")
		f = again
	end)

	it("the fixture's folder is registered to be swept when the spec file passes", function()
		t.expect(table.find(swept.pending(), f.base) ~= nil).toBe(true)
	end)

	it("copies, never links: no file of a fixture or of an image has a second name", function()
		t.expect(out("find", { f.base, "-type", "f", "-links", "+1" })).toBe("")
		t.expect(out("find", { images.dir(), "-type", "f", "-links", "+1" })).toBe("")
	end)

	it("what a spec does to a fixture's objects cannot reach the next fixture", function()
		local victim = trackerfix.new("c0178-seed-victim")
		fs.removeDir(`{victim.main}/.git/objects/pack`) -- a spec breaking its own repository
		fs.removeDir(`{victim.origin}/objects/pack`)
		local next = trackerfix.new("c0178-seed-next")
		t.expect(fixture.git(next.main, { "fsck", "--no-dangling" })).toBe("")
		t.expect(fixture.git(next.origin, { "rev-list", "--count", "main" })).toBe("1")
		t.expect(fixture.git(next.other, { "status", "--porcelain" })).toBe("")
	end)

	it(
		"the fixture is small: about two working trees and little else, no seed repository, few loose objects",
		function()
			local fx = trackerfix.new("c0178-seed-small", { ["notes/extra.txt"] = "extra\n" })
			fixture.git(fx.other, { "status", "--porcelain" }) -- both clones exist
			local tree = files(fx.main) - files(`{fx.main}/.git`) -- files of the working tree
			t.expect(tree > 100).toBe(true)
			-- two working trees, their .git folders and the origin
			t.expect(files(fx.base) <= 2 * tree + 120).toBe(true)
			t.expect(files(fx.origin) <= 40).toBe(true)
			-- the tooling's objects are in the packs; only what the seed changed is loose
			t.expect(#lines(out("find", { fx.origin, "-path", "*/objects/??/*", "-type", "f" })) <= 25)
				.toBe(true)
			t.expect(#lines(out("find", { `{fx.main}/.git`, "-path", "*/objects/??/*", "-type", "f" })) <= 25)
				.toBe(true)
			-- and a fixture whose `other` nobody used is one working tree lighter
			local alone = trackerfix.new("c0178-seed-alone", { ["notes/extra.txt"] = "extra\n" })
			t.expect(files(alone.base) <= tree + 100).toBe(true)
		end
	)

	it("a warm fixture runs no cp, no git init, no git config, and two clones", function()
		local dir = `{BASE}/child`
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(`{dir}/bin`)
		for _, cmd in { "git", "cp" } do
			local real = out("which", { cmd })
			write(`{dir}/bin/{cmd}`, `#!/bin/sh\necho "{cmd} $1 $2 $3" >> "$SHIM_LOG"\nexec {real} "$@"\n`)
			out("chmod", { "+x", `{dir}/bin/{cmd}` })
		end
		write(
			`{dir}/child.luau`,
			table.concat({
				"--!strict",
				`local trackerfix = {REQ}("@tests/lib/trackerfix")`,
				'trackerfix.new("c0178-seed-child", { ["a/b.txt"] = "x\\n" })',
				"",
			}, "\n")
		)
		local r = process.exec("lune", { "run", `{dir}/child.luau` }, {
			cwd = HOME,
			env = { PATH = `{dir}/bin:{process.env.PATH or ""}`, SHIM_LOG = `{dir}/log` },
		})
		t.expect(r.ok).toBe(true)
		local log = lines(fs.readFile(`{dir}/log`))
		t.expect(count(log, "cp ")).toBe(0)
		t.expect(count(log, "git init")).toBe(0)
		t.expect(count(log, "git config")).toBe(0)
		t.expect(count(log, "git clone")).toBe(2) -- main from the image, origin from main; `other` waits to be used
		-- the clones, the commit, the remote changes and the fetch, and one guard check per fixture.git call
		t.expect(count(log, "git ") <= 16).toBe(true)
	end)

	it(
		"opts.copy brings checkout paths into the seed commit and opts.executable makes seeded files executable",
		function()
			local fx = trackerfix.new("c0178-seed-opts", {
				["tools/run.sh"] = "#!/bin/sh\necho run\n",
				["tools/plain.txt"] = "plain\n",
			}, { copy = { ".luaurc", "pickman/.tracker/architecture.md" }, executable = { "tools/run.sh" } })
			t.expect(fixture.git(fx.origin, { "show", "main:.luaurc" }))
				.toBe(out("cat", { `{engine.TOP}/.luaurc` }))
			t.expect(
				string.match(fixture.git(fx.origin, { "ls-tree", "main", "tools/run.sh" }), "^100755 blob")
					~= nil
			).toBe(true)
			t.expect(
				string.match(fixture.git(fx.origin, { "ls-tree", "main", "tools/plain.txt" }), "^100644 blob")
					~= nil
			).toBe(true)
			t.expect(
				fixture.git(
					fx.origin,
					{ "ls-tree", "--name-only", "main", "pickman/.tracker/architecture.md" }
				)
			)
				.toBe("pickman/.tracker/architecture.md")
			local ok, err = pcall(function(): any
				trackerfix.new("c0178-seed-opts-bad", nil, { copy = { "no/such/file" } })
				return nil
			end)
			t.expect(ok).toBe(false)
			t.expect(string.find(tostring(err), "no/such/file", 1, true) ~= nil).toBe(true)
		end
	)

	it(
		"the helpers count what they start and write: the tally is the shim log and the files on disk",
		function()
			local dir = `{BASE}/counted`
			if fs.isDir(dir) then
				fs.removeDir(dir)
			end
			fs.writeDir(`{dir}/bin`)
			for _, cmd in { "git", "cp", "pwd", "perl", "mkdir", "mktemp", "chmod", "sh" } do
				local real = out("which", { cmd })
				write(
					`{dir}/bin/{cmd}`,
					`#!/bin/sh\necho "{cmd} $1 $2 $3" >> "$SHIM_LOG"\nexec {real} "$@"\n`
				)
				out("chmod", { "+x", `{dir}/bin/{cmd}` })
			end
			write(
				`{dir}/child.luau`,
				table.concat({
					"--!strict",
					`local fixture = {REQ}("@tests/lib/fixture")`,
					`local tally = {REQ}("@tests/lib/tally")`,
					`local trackerfix = {REQ}("@tests/lib/trackerfix")`,
					'local f = trackerfix.new("c0178-seed-counted", { ["a/b.txt"] = "x\\n" })',
					'fixture.git(f.other, { "status", "--porcelain" })',
					"local files, procs = tally.read()",
					'print(files .. " " .. procs .. " " .. f.base)',
					"",
				}, "\n")
			)
			local r = process.exec("lune", { "run", `{dir}/child.luau` }, {
				cwd = HOME,
				env = { PATH = `{dir}/bin:{process.env.PATH or ""}`, SHIM_LOG = `{dir}/log` },
			})
			t.expect(r.ok).toBe(true)
			local written, procs, base = string.match(r.stdout, "^(%d+) (%d+) (%S+)")
			t.expect(tonumber(procs)).toBe(#lines(fs.readFile(`{dir}/log`)))
			t.expect(tonumber(written)).toBe(#lines(out("find", { base :: string, "-type", "f" })))
		end
	)
end)
