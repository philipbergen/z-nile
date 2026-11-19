--!strict
-- c0178 AC1 and AC2: the fixture image store (@tests/lib/images). An image is a folder built once from what it is
-- keyed by (file bytes, executable bits, the harness code), named `<kind>-<24 hex>`, and published by one rename; a
-- lock keeps callers from repeating a build; nothing here removes an image, and pruning (once per run, before any
-- spec starts) removes only older images of their own kind. Everything
-- here runs in folders of its own under .cache/c0178-images (the home's .cache), never in images.dir().
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local images = require("@tests/lib/images")
local process = require("@lune/process")
local pruning = require("@tests/lib/pruning")
local t = require("@tests/lib/t")
local tally = require("@tests/lib/tally")
local task = require("@lune/task")

local HOME = fixture.physical(".") :: string
local BASE = `{HOME}/.cache/c0178-images`
local REQ = "require" -- built by concatenation: a literal require in a string would join the graph

local function write(path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(parent)
	end
	fs.writeFile(path, text)
end

local function out(cmd: string, args: { string }): string
	local r = process.exec(cmd, args)
	if not r.ok then
		error(`{cmd} {table.concat(args, " ")} failed: {r.stderr}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function must(r: { ok: boolean, stderr: string }, what: string)
	if not r.ok then
		error(`{what} failed: {r.stderr}`, 2)
	end
end

-- A folder to use as a case's checkout and its images folder, both fresh.
local function fresh(name: string): (string, string)
	local dir = `{BASE}/{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(`{dir}/root`)
	return `{dir}/root`, `{dir}/images`
end

local function names(dir: string): { string }
	local found = {}
	if fs.isDir(dir) then
		for _, n in fs.readDir(dir) do
			table.insert(found, n)
		end
	end
	table.sort(found)
	return found
end

-- A spec over `root` whose build writes built.txt and counts its calls in `calls[1]`.
local function specOf(kind: string, root: string, calls: { number }?, over: { [string]: any }?): images.Spec
	local spec: images.Spec = {
		name = kind,
		root = root,
		inputs = { "in" },
		skip = { "in/skipped" },
		code = {},
		build = function(dest: string)
			if calls then
				calls[1] += 1
			end
			write(`{dest}/built.txt`, "built")
		end,
	}
	if over then
		for k, v in over do
			(spec :: any)[k] = v
		end
	end
	return spec
end

local function idOf(spec: images.Spec, dir: string): string
	return (string.match(images.ensure(spec, { dir = dir }), "([^/]+)$")) :: string
end

local function touch(path: string, stamp: string)
	must(process.exec("touch", { "-t", stamp, path }), `touch {path}`)
end

local function childScript(): string
	return table.concat({
		"--!strict",
		`local images = {REQ}("@tests/lib/images")`,
		`local fs = {REQ}("@lune/fs")`,
		`local process = {REQ}("@lune/process")`,
		`local task = {REQ}("@lune/task")`,
		"local args = {}",
		"for _, a in process.args do",
		'	if a ~= "--" then',
		"		table.insert(args, a)",
		"	end",
		"end",
		"local home, root, log = args[1], args[2], args[3]",
		"local path = images.ensure({",
		'	name = "conc", root = root, inputs = { "in" }, skip = {}, code = {},',
		"	build = function(dest: string)",
		'		fs.writeFile(`{log}/build-{math.random(1, 1e9)}-{os.clock()}`, "")',
		"		task.wait(1)",
		'		fs.writeFile(`{dest}/built.txt`, "built")',
		"	end,",
		"}, { dir = home })",
		"print(path)",
		"",
	}, "\n")
end

return t.spec("c0178 fixture image store", function(it)
	it("images.dir is the current home's .cache/images", function()
		t.expect(images.dir()).toBe(`{HOME}/.cache/images`)
	end)

	it(
		"builds an image once: a second call for the same content returns the same folder and builds nothing",
		function()
			local root, dir = fresh("once")
			write(`{root}/in/a.txt`, "alpha")
			local calls = { 0 }
			local before = images.builds()
			local first = images.ensure(specOf("kind", root, calls), { dir = dir })
			local second = images.ensure(specOf("kind", root, calls), { dir = dir })
			t.expect(second).toBe(first)
			t.expect(calls[1]).toBe(1)
			t.expect(images.builds() - before).toBe(1)
			t.expect(fs.readFile(`{first}/built.txt`)).toBe("built")
			t.expect(string.match(first, "/kind%-%x+$") ~= nil).toBe(true)
			t.expect(#(string.match(first, "%-(%x+)$") :: string)).toBe(24)
			-- nothing but the image is left in the images folder: no build folder, no lock
			t.expect(names(dir)).toEqual({ string.match(first, "([^/]+)$") :: string })
		end
	)

	it("a file's bytes decide the image: same name and size, one byte different, another image", function()
		local rootA, dir = fresh("bytes")
		write(`{rootA}/in/a.txt`, "alpha")
		local rootB = `{BASE}/bytes/rootB`
		write(`{rootB}/in/a.txt`, "alphb")
		local rootC = `{BASE}/bytes/rootC`
		write(`{rootC}/in/a.txt`, "alpha")
		local a = idOf(specOf("kind", rootA, nil), dir)
		t.expect(idOf(specOf("kind", rootB, nil), dir) ~= a).toBe(true)
		t.expect(idOf(specOf("kind", rootC, nil), dir)).toBe(a) -- the same bytes under another checkout: the same image
	end)

	it("a file's name and place decide the image", function()
		local rootA, dir = fresh("place")
		write(`{rootA}/in/a.txt`, "same")
		local rootB = `{BASE}/place/rootB`
		write(`{rootB}/in/b.txt`, "same")
		local rootC = `{BASE}/place/rootC`
		write(`{rootC}/in/sub/a.txt`, "same")
		local a = idOf(specOf("kind", rootA, nil), dir)
		t.expect(idOf(specOf("kind", rootB, nil), dir) ~= a).toBe(true)
		t.expect(idOf(specOf("kind", rootC, nil), dir) ~= a).toBe(true)
	end)

	it("the executable bit decides the image", function()
		local rootA, dir = fresh("exec")
		write(`{rootA}/in/run.sh`, "echo")
		local rootB = `{BASE}/exec/rootB`
		write(`{rootB}/in/run.sh`, "echo")
		must(process.exec("chmod", { "+x", `{rootB}/in/run.sh` }), "chmod")
		t.expect(idOf(specOf("kind", rootB, nil), dir) ~= idOf(specOf("kind", rootA, nil), dir)).toBe(true)
	end)

	it("a skipped path decides nothing, its sibling decides as any other", function()
		local rootA, dir = fresh("skip")
		write(`{rootA}/in/a.txt`, "alpha")
		write(`{rootA}/in/skipped/state.txt`, "one")
		local rootB = `{BASE}/skip/rootB`
		write(`{rootB}/in/a.txt`, "alpha")
		write(`{rootB}/in/skipped/state.txt`, "two, and longer")
		write(`{rootB}/in/skipped/more.txt`, "a new file")
		local rootC = `{BASE}/skip/rootC`
		write(`{rootC}/in/a.txt`, "alpha")
		write(`{rootC}/in/skipped.txt`, "a sibling whose name starts like the skipped path")
		local a = idOf(specOf("kind", rootA, nil), dir)
		t.expect(idOf(specOf("kind", rootB, nil), dir)).toBe(a)
		t.expect(idOf(specOf("kind", rootC, nil), dir) ~= a).toBe(true)
	end)

	it("the bytes of the harness code decide the image", function()
		local root, dir = fresh("code")
		write(`{root}/in/a.txt`, "alpha")
		write(`{BASE}/code/one.luau`, "return 1")
		write(`{BASE}/code/two.luau`, "return 2")
		local one = idOf(specOf("kind", root, nil, { code = { `{BASE}/code/one.luau` } }), dir)
		local two = idOf(specOf("kind", root, nil, { code = { `{BASE}/code/two.luau` } }), dir)
		local none = idOf(specOf("kind", root, nil), dir)
		t.expect(one ~= two).toBe(true)
		t.expect(one ~= none).toBe(true)
	end)

	it("an input that is missing is refused, naming it, and nothing is built", function()
		local root, dir = fresh("missing")
		write(`{root}/other/a.txt`, "alpha") -- the root exists, the input `in` does not
		local calls = { 0 }
		local ok, err = pcall(images.ensure, specOf("kind", root, calls), { dir = dir })
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), `{root}/in`, 1, true) ~= nil).toBe(true)
		t.expect(calls[1]).toBe(0)
		t.expect(names(dir)).toEqual({})
	end)

	it("a symlink is keyed by its target text and never followed", function()
		local rootA, dir = fresh("link")
		write(`{BASE}/link/outside.txt`, "first")
		fs.writeDir(`{rootA}/in`)
		must(process.exec("ln", { "-s", `{BASE}/link/outside.txt`, `{rootA}/in/ln` }), "ln")
		local a = idOf(specOf("kind", rootA, nil), dir)
		-- the same link over other bytes of its target: the same image (the key never reads through the link)
		write(`{BASE}/link/outside.txt`, "second, and longer")
		local rootB = `{BASE}/link/rootB`
		fs.writeDir(`{rootB}/in`)
		must(process.exec("ln", { "-s", `{BASE}/link/outside.txt`, `{rootB}/in/ln` }), "ln")
		t.expect(idOf(specOf("kind", rootB, nil), dir)).toBe(a)
		-- a link to another target: another image
		local rootC = `{BASE}/link/rootC`
		fs.writeDir(`{rootC}/in`)
		must(process.exec("ln", { "-s", `{BASE}/link/other.txt`, `{rootC}/in/ln` }), "ln")
		t.expect(idOf(specOf("kind", rootC, nil), dir) ~= a).toBe(true)
	end)

	it("a name that is not lowercase letters, digits and - is refused, naming it", function()
		local root, dir = fresh("name")
		write(`{root}/in/a.txt`, "alpha")
		for _, bad in { "Kind", "kind_x", "1kind", "ki/nd", "" } do
			local ok, err = pcall(images.ensure, specOf(bad, root, nil), { dir = dir })
			t.expect(ok).toBe(false)
			t.expect(string.find(tostring(err), bad, 1, true) ~= nil).toBe(true)
		end
		t.expect(names(dir)).toEqual({})
	end)

	it(
		"a failed build leaves no image, no build folder and no lock, and the error names the image and the cause",
		function()
			local root, dir = fresh("fail")
			write(`{root}/in/a.txt`, "alpha")
			local ok, err = pcall(
				images.ensure,
				specOf("kind", root, nil, {
					build = function(_dest: string)
						error("the build broke here")
					end,
				}),
				{ dir = dir }
			)
			t.expect(ok).toBe(false)
			t.expect(string.find(tostring(err), "building kind-", 1, true) ~= nil).toBe(true)
			t.expect(string.find(tostring(err), "the build broke here", 1, true) ~= nil).toBe(true)
			t.expect(names(dir)).toEqual({})
			-- and the next caller builds it
			t.expect(fs.isDir(images.ensure(specOf("kind", root, nil), { dir = dir }))).toBe(true)
		end
	)

	it("another caller's publish during our build wins: ours is discarded and leaves nothing", function()
		local root, dir = fresh("race")
		write(`{root}/in/a.txt`, "alpha")
		local path = images.ensure(
			specOf("kind", root, nil, {
				build = function(dest: string)
					-- the lock is named after the image: publish an image of that name, as a concurrent caller would
					local final = ""
					for _, n in fs.readDir(dir) do
						if string.match(n, "%.lock$") then
							final = `{dir}/{string.sub(n, 1, -6)}`
						end
					end
					write(`{final}/theirs.txt`, "theirs")
					write(`{dest}/ours.txt`, "ours")
				end,
			}),
			{ dir = dir }
		)
		t.expect(fs.isFile(`{path}/theirs.txt`)).toBe(true)
		t.expect(fs.isFile(`{path}/ours.txt`)).toBe(false)
		t.expect(names(dir)).toEqual({ string.match(path, "([^/]+)$") :: string })
	end)

	it("a held lock makes the caller wait for the image and not build it", function()
		local root, dir = fresh("held")
		write(`{root}/in/a.txt`, "alpha")
		local probe = images.ensure(specOf("kind", root, nil), { dir = dir }) -- learns the image's name
		local stash = `{BASE}/held/stash`
		fs.move(probe, stash)
		fs.writeDir(`{probe}.lock`) -- someone else is building it
		task.spawn(function()
			task.wait(1)
			fs.move(stash, probe) -- ... and publishes
		end)
		local calls = { 0 }
		local got = images.ensure(specOf("kind", root, calls), { dir = dir, stale = 600 })
		t.expect(got).toBe(probe)
		t.expect(calls[1]).toBe(0)
	end)

	it("a lock older than stale holds nobody off: the caller builds while it is still there", function()
		local root, dir = fresh("stale")
		write(`{root}/in/a.txt`, "alpha")
		local probe = images.ensure(specOf("kind", root, nil), { dir = dir })
		fs.removeDir(probe)
		fs.writeDir(`{probe}.lock`) -- its owner died
		local released = false
		local watchdog = task.delay(5, function()
			released = true
			fs.removeDir(`{probe}.lock`)
		end)
		local builtBeforeRelease = false
		local got = images.ensure(
			specOf("kind", root, nil, {
				build = function(dest: string)
					builtBeforeRelease = not released
					write(`{dest}/built.txt`, "built")
				end,
			}),
			{ dir = dir, stale = 0 }
		)
		task.cancel(watchdog)
		t.expect(got).toBe(probe)
		t.expect(builtBeforeRelease).toBe(true)
		t.expect(fs.isFile(`{got}/built.txt`)).toBe(true)
	end)

	it("a caller that has waited `wait` seconds builds although the lock is fresh", function()
		local root, dir = fresh("waited")
		write(`{root}/in/a.txt`, "alpha")
		local probe = images.ensure(specOf("kind", root, nil), { dir = dir })
		fs.removeDir(probe)
		fs.writeDir(`{probe}.lock`) -- fresh, and its owner never publishes
		local released = false
		local watchdog = task.delay(5, function()
			released = true
			fs.removeDir(`{probe}.lock`)
		end)
		local builtBeforeRelease = false
		local got = images.ensure(
			specOf("kind", root, nil, {
				build = function(dest: string)
					builtBeforeRelease = not released
					write(`{dest}/built.txt`, "built")
				end,
			}),
			{ dir = dir, stale = 600, wait = 0.4 }
		)
		task.cancel(watchdog)
		t.expect(got).toBe(probe)
		t.expect(builtBeforeRelease).toBe(true)
	end)

	it("the salt decides the image: the same inputs with another salt are another image", function()
		local root, dir = fresh("salt")
		write(`{root}/in/a.txt`, "alpha")
		local a = idOf(specOf("kind", root, nil, { salt = "commit-a" }), dir)
		local b = idOf(specOf("kind", root, nil, { salt = "commit-b" }), dir)
		local again = idOf(specOf("kind", root, nil, { salt = "commit-a" }), dir)
		local none = idOf(specOf("kind", root, nil), dir)
		t.expect(a ~= b).toBe(true)
		t.expect(again).toBe(a)
		t.expect(none ~= a).toBe(true)
	end)

	it(
		"a lock whose recorded owner is dead holds nobody off: the caller builds at once, without waiting for it to go stale",
		function()
			local root, dir = fresh("dead")
			write(`{root}/in/a.txt`, "alpha")
			local probe = images.ensure(specOf("kind", root, nil), { dir = dir })
			fs.removeDir(probe)
			fs.writeDir(`{probe}.lock`)
			fs.writeFile(`{probe}.lock/owner`, "4194303 a-start-id-no-process-has") -- a pid no process holds
			local released = false
			local watchdog = task.delay(5, function()
				released = true
				pcall(fs.removeDir, `{probe}.lock`)
			end)
			local builtBeforeRelease = false
			local got = images.ensure(
				specOf("kind", root, nil, {
					build = function(dest: string)
						builtBeforeRelease = not released
						write(`{dest}/built.txt`, "built")
					end,
				}),
				{ dir = dir, stale = 600, wait = 600 }
			)
			task.cancel(watchdog)
			t.expect(got).toBe(probe)
			t.expect(builtBeforeRelease).toBe(true)
			t.expect(fs.isFile(`{got}/built.txt`)).toBe(true)
			t.expect(#names(dir)).toBe(2) -- the image, and the dead owner's lock (pruning clears it)
		end
	)

	it("a lock whose owner is alive is waited for, and waiting starts next to no process", function()
		local root, dir = fresh("alive")
		write(`{root}/in/a.txt`, "alpha")
		local probe = images.ensure(specOf("kind", root, nil), { dir = dir })
		local stash = `{BASE}/alive/stash`
		fs.move(probe, stash)
		fs.writeDir(`{probe}.lock`)
		local me = out("sh", { "-c", "echo $PPID" }) -- this very process
		fs.writeFile(`{probe}.lock/owner`, `{me} `)
		task.spawn(function()
			task.wait(1.5)
			fs.move(stash, probe)
		end)
		local _, before = tally.read()
		local calls = { 0 }
		local got = images.ensure(specOf("kind", root, calls), { dir = dir, stale = 600 })
		local _, after = tally.read()
		t.expect(got).toBe(probe)
		t.expect(calls[1]).toBe(0)
		-- about eight polls in 1.5 s: the in-process look at the folder and the lock starts no process
		t.expect(after - before <= 2).toBe(true)
	end)

	it("an image published between the look and the lock is used and not built again", function()
		local root, dir = fresh("between")
		write(`{root}/in/a.txt`, "alpha")
		local calls = { 0 }
		local got = images.ensure(specOf("kind", root, calls), {
			dir = dir,
			beforeLock = function(final: string)
				write(`{final}/theirs.txt`, "theirs") -- the owner of the lock just finished
			end,
		})
		t.expect(calls[1]).toBe(0)
		t.expect(fs.isFile(`{got}/theirs.txt`)).toBe(true)
		t.expect(names(dir)).toEqual({ string.match(got, "([^/]+)$") :: string }) -- and the lock we took is gone
	end)

	it("four processes asking at once build one image and all get it", function()
		local root, dir = fresh("conc")
		write(`{root}/in/a.txt`, "alpha")
		fs.writeDir(`{BASE}/conc/log`)
		local script = `{BASE}/conc/child.luau`
		write(script, childScript())
		local outputs: { string } = {}
		local done = 0
		for i = 1, 4 do
			task.spawn(function()
				local r = process.exec(
					"lune",
					{ "run", script, "--", dir, root, `{BASE}/conc/log` },
					{ cwd = HOME }
				)
				outputs[i] = if r.ok then (string.gsub(r.stdout, "%s+$", "")) else `FAILED: {r.stderr}`
				done += 1
			end)
		end
		while done < 4 do
			task.wait(0.1)
		end
		for i = 2, 4 do
			t.expect(outputs[i]).toBe(outputs[1])
		end
		t.expect(string.find(outputs[1], "FAILED", 1, true) == nil).toBe(true)
		t.expect(fs.isFile(`{outputs[1]}/built.txt`)).toBe(true)
		t.expect(#names(`{BASE}/conc/log`)).toBe(1)
		t.expect(#names(dir)).toBe(1)
	end)

	-- pruning (once per run, before any spec starts) removes older images of their own kind beyond `keep`, none younger than
	-- `minAge`, and the build folders and locks nobody can still be using; the kind is the whole id minus its key
	local function pruneCase(name: string, keep: number, expectGone: { string }, expectKept: { string })
		local root, dir = fresh(name)
		write(`{root}/in/a.txt`, "alpha")
		local K = function(c: string): string
			return string.rep(c, 24)
		end
		local old = { "202001010000", "202001020000", "202001030000" } -- oldest first
		for i, stamp in old do
			local d = `{dir}/p-{K(tostring(i))}`
			fs.writeDir(d)
			touch(d, stamp)
		end
		fs.writeDir(`{dir}/p-q-{K("b")}`) -- another kind whose name starts with "p-"
		touch(`{dir}/p-q-{K("b")}`, "202001010000")
		fs.writeDir(`{dir}/p-{K("c")}`) -- young: just made
		fs.writeDir(`{dir}/.build.OLD`)
		touch(`{dir}/.build.OLD`, "202001010000")
		fs.writeDir(`{dir}/.build.NEW`)
		fs.writeDir(`{dir}/p-{K("d")}.lock`)
		touch(`{dir}/p-{K("d")}.lock`, "202001010000")
		pruning.run(dir, keep, 3600)
		local left = names(dir)
		for _, n in expectGone do
			t.expect(table.find(left, n)).toBe(nil)
		end
		for _, n in expectKept do
			t.expect(table.find(left, n) ~= nil).toBe(true)
		end
	end
	it(
		"prune keeps the newest `keep` older images of the kind, removes the rest, and leaves other kinds alone",
		function()
			local K = function(c: string): string
				return string.rep(c, 24)
			end
			pruneCase(
				"prune1",
				1,
				{ `p-{K("1")}`, `p-{K("2")}`, `p-{K("3")}`, ".build.OLD", `p-{K("d")}.lock` },
				{ `p-q-{K("b")}`, `p-{K("c")}`, ".build.NEW" }
			)
			pruneCase(
				"prune2",
				2,
				{ `p-{K("1")}`, `p-{K("2")}` },
				{ `p-{K("3")}`, `p-{K("c")}`, `p-q-{K("b")}` }
			)
		end
	)

	it(
		"ensure never removes an image: after many publishes of one kind every earlier image is still there",
		function()
			local root, dir = fresh("keeps")
			local ids = {}
			for i = 1, 5 do
				write(`{root}/in/a{i}.txt`, `content {i}`)
				local rooti = `{BASE}/keeps/root{i}`
				write(`{rooti}/in/a.txt`, `content {i}`)
				table.insert(ids, idOf(specOf("kind", rooti, nil), dir))
			end
			touch(`{dir}/{ids[1]}`, "202001010000") -- the oldest is long past any age limit
			write(`{BASE}/keeps/rootX/in/a.txt`, "one more")
			table.insert(ids, idOf(specOf("kind", `{BASE}/keeps/rootX`, nil), dir))
			t.expect(names(dir)).toEqual((function()
				local want = table.clone(ids)
				table.sort(want)
				return want
			end)())
		end
	)

	it("prune never removes an image younger than minAge, however many there are", function()
		local root, dir = fresh("young")
		write(`{root}/in/a.txt`, "alpha")
		for i = 1, 4 do
			fs.writeDir(`{dir}/p-{string.rep(tostring(i), 24)}`)
		end
		pruning.run(dir, 1, 3600)
		t.expect(#names(dir)).toBe(4)
	end)
end)
