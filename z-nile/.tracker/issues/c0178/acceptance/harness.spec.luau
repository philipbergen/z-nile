--!strict
-- c0178 AC4: what the harness does around a spec file. swept: helpers register folders and the runner removes them when
-- every case of the file passed, and keeps them when one failed. tally: the fixture helpers count files written and
-- processes started, and the runner prints the sums beside `slowest:`. git's template: a spec's `git init` and `git
-- clone` get empty hooks/ and info/ folders and none of the 16 sample files. Folders under .cache/c0178-harness.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local images = require("@tests/lib/images")
local pruning = require("@tests/lib/pruning")
local process = require("@lune/process")
local swept = require("@tests/lib/swept")
local t = require("@tests/lib/t")
local tally = require("@tests/lib/tally")

local HOME = fixture.physical(".") :: string
local CACHE = `{HOME}/.cache`
local BASE = `{CACHE}/c0178-harness`
local REQ = "require" -- built by concatenation: a literal require in a string would join the graph

local function write(path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(parent)
	end
	fs.writeFile(path, text)
end

local function names(dir: string): { string }
	local list = {}
	for _, n in fs.readDir(dir) do
		table.insert(list, n)
	end
	table.sort(list)
	return list
end

local function must(r: { ok: boolean, stderr: string }, what: string)
	if not r.ok then
		error(`{what} failed: {r.stderr}`, 2)
	end
end

-- Runs the runner on the one spec file `body` in a folder of its own (a nested run, as run-lane-error does); returns
-- the exit code and what it printed.
local function nested(name: string, body: string, env: { [string]: string }?): (number, string)
	local dir = `{BASE}/{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	write(`{dir}/x.spec.luau`, body)
	-- a nested run is its own run: it is no worker of the run it sits in, whatever that run has in its environment
	local merged: { [string]: string } = { PICKMAN_JOBS = "", PICKMAN_WORKER = "", PICKMAN_TALLY = "" }
	if env then
		for k, v in env do
			merged[k] = v
		end
	end
	local r = process.exec("perl", {
		"-e",
		"alarm 60; exec @ARGV",
		"lune",
		"run",
		"tests/run",
		"--",
		"--jobs",
		"1",
		`.cache/c0178-harness/{name}/x.spec.luau`,
	}, { cwd = HOME, env = merged })
	return r.code, r.stdout .. r.stderr
end

local function specBody(folder: string, failing: boolean): string
	return table.concat({
		"--!strict",
		`local fs = {REQ}("@lune/fs")`,
		`local swept = {REQ}("@tests/lib/swept")`,
		`local t = {REQ}("@tests/lib/t")`,
		`local tally = {REQ}("@tests/lib/tally")`,
		`return t.spec("x", function(it)`,
		`	it("makes a fixture", function()`,
		`		fs.writeDir("{folder}/deep/er")`,
		`		fs.writeFile("{folder}/deep/er/f.txt", "x")`,
		`		swept.register("{folder}")`,
		`		tally.files(7)`,
		`		tally.started(3)`,
		`	end)`,
		`	it("then ends", function()`,
		if failing then `		error("this case fails")` else "		t.expect(1).toBe(1)",
		`	end)`,
		`end)`,
		"",
	}, "\n")
end

return t.spec("c0178 swept, tally and git's template", function(it)
	it(
		"swept refuses a folder that is not strictly inside the home's .cache, or is inside an image, naming it",
		function()
			for _, bad in
				{
					HOME,
					`{HOME}/tests`,
					CACHE,
					`{CACHE}/`,
					`{CACHE}/../tests`,
					`{CACHE}/c0178-harness/..`,
					images.dir(),
					`{CACHE}/.`,
					`{CACHE}//images`,
					`{CACHE}/./c0178-harness`,
					`{CACHE}/c0178-harness/./x`,
					`{CACHE}/.git`,
					`{CACHE}/.tmp/x`,
					`{CACHE}/Images`,
					`{CACHE}/TESTS-RUN.LOCK`,
					`{CACHE}/tests-run.lock`,
					`{CACHE}/spec-durations.tsv`,
					`{images.dir()}/tooling-abc`,
					"/tmp/c0178-elsewhere",
					"relative/path",
				}
			do
				local ok, err = pcall(function(): any
					swept.register(bad)
					return nil
				end)
				if ok then
					error(`swept accepted {bad}`)
				end
				t.expect(string.find(tostring(err), bad, 1, true) ~= nil).toBe(true)
			end
			t.expect(#swept.pending()).toBe(0)
		end
	)

	it("swept removes what was registered, nested files included, and forgets it", function()
		local a, b = `{BASE}/sweep/a`, `{BASE}/sweep/b`
		write(`{a}/x/y/z.txt`, "z")
		write(`{b}/w.txt`, "w")
		swept.register(a)
		swept.register(b)
		fs.removeDir(b) -- already gone by the time of the sweep: not an error
		t.expect(swept.pending()).toEqual({ a, b })
		t.expect((swept.sweep())).toBe(2)
		t.expect(fs.isDir(a)).toBe(false)
		t.expect(swept.pending()).toEqual({})
		t.expect((swept.sweep())).toBe(0)
	end)

	it("tally counts the processes the fixture helpers start and the files they write", function()
		local files0, procs0 = tally.read()
		tally.started(1)
		tally.started(1)
		tally.files(5)
		local files1, procs1 = tally.read()
		t.expect(procs1 - procs0).toBe(2)
		t.expect(files1 - files0).toBe(5)
		-- files are counted by walking, regular files only, folders not
		write(`{BASE}/walk/a.txt`, "a")
		write(`{BASE}/walk/sub/b.txt`, "b")
		write(`{BASE}/walk/sub/deeper/c.txt`, "c")
		fs.writeDir(`{BASE}/walk/empty`)
		t.expect(tally.count(`{BASE}/walk`)).toBe(3)
	end)

	it("the runner sweeps a passing file's folders and prints what the helpers cost beside slowest:", function()
		local folder = `{BASE}/run-pass/fx`
		local code, output = nested("run-pass", specBody(folder, false))
		t.expect(code).toBe(0)
		t.expect(fs.isDir(folder)).toBe(false)
		t.expect(string.match(output, "fixtures: (%d+) files written, (%d+) processes started") ~= nil).toBe(true)
		t.expect(string.find(output, "2 passed, 0 failed, 1 spec files", 1, true) ~= nil).toBe(true)
	end)

	it("the runner keeps a failing file's folders", function()
		local folder = `{BASE}/run-fail/fx`
		local code, output = nested("run-fail", specBody(folder, true))
		t.expect(code).toBe(1)
		t.expect(fs.isDir(folder)).toBe(true)
		t.expect(fs.isFile(`{folder}/deep/er/f.txt`)).toBe(true)
		t.expect(string.find(output, "1 passed, 1 failed, 1 spec files", 1, true) ~= nil).toBe(true)
	end)

	it(
		"the coordinator of a concurrent run sums its workers' counts and prints them once, between slowest: and the summary",
		function()
			local dir = `{BASE}/run-two`
			if fs.isDir(dir) then
				fs.removeDir(dir)
			end
			write(`{dir}/a.spec.luau`, specBody(`{dir}/fx-a`, false))
			write(`{dir}/b.spec.luau`, specBody(`{dir}/fx-b`, false))
			local r = process.exec("perl", {
				"-e",
				"alarm 60; exec @ARGV",
				"lune",
				"run",
				"tests/run",
				"--",
				"--jobs",
				"2",
				".cache/c0178-harness/run-two/a.spec.luau",
				".cache/c0178-harness/run-two/b.spec.luau",
			}, { cwd = HOME, env = { PICKMAN_JOBS = "", PICKMAN_WORKER = "", PICKMAN_TALLY = "" } })
			t.expect(r.code).toBe(0)
			local all = {}
			for line in string.gmatch(r.stdout, "[^\n]+") do
				table.insert(all, line)
			end
			t.expect(#all).toBe(3)
			t.expect(string.sub(all[1], 1, 9)).toBe("slowest: ")
			local files, procs = string.match(all[2], "^fixtures: (%d+) files written, (%d+) processes started")
			t.expect(tonumber(files)).toBe(14) -- 7 from each of the two files
			t.expect(tonumber(procs)).toBe(6) -- 3 from each
			t.expect(all[3]).toBe("4 passed, 0 failed, 2 spec files")
			t.expect(fs.isDir(`{dir}/fx-a`) or fs.isDir(`{dir}/fx-b`)).toBe(false)
		end
	)

	it("a folder that cannot be removed is shown by name and fails the run, though every case passed", function()
		local folder = `{BASE}/run-stuck/fx`
		local body = table.concat({
			"--!strict",
			`local fs = {REQ}("@lune/fs")`,
			`local process = {REQ}("@lune/process")`,
			`local swept = {REQ}("@tests/lib/swept")`,
			`local t = {REQ}("@tests/lib/t")`,
			`return t.spec("x", function(it)`,
			`	it("leaves a folder nobody can empty", function()`,
			`		fs.writeDir("{folder}/locked")`,
			`		fs.writeFile("{folder}/locked/f.txt", "x")`,
			'		process.exec("chmod", { "555", "' .. folder .. '/locked" })',
			`		swept.register("{folder}")`,
			`	end)`,
			`end)`,
			"",
		}, "\n")
		local code, output = nested("run-stuck", body)
		pcall(process.exec, "chmod", { "-R", "u+w", folder })
		t.expect(code).toBe(1)
		t.expect(string.find(output, `swept: could not remove {folder}`, 1, true) ~= nil).toBe(true)
		t.expect(string.find(output, "1 passed, 0 failed, 1 spec files", 1, true) ~= nil).toBe(true)
	end)

	it(
		"a hand-built fixture copied into with engine.copy is swept too, and a folder nobody registered stays",
		function()
			local fx = `{CACHE}/c0178-harness-hand`
			local keep = `{CACHE}/c0178-harness-unregistered`
			local body = table.concat({
				"--!strict",
				`local engine = {REQ}("@tests/lib/engine")`,
				`local fs = {REQ}("@lune/fs")`,
				`local t = {REQ}("@tests/lib/t")`,
				`return t.spec("x", function(it)`,
				`	it("builds by hand", function()`,
				`		fs.writeDir("{fx}/repo")`,
				`		engine.copy(".", "{fx}/repo")`,
				`		fs.writeDir("{keep}")`,
				`		fs.writeFile("{keep}/f.txt", "x")`,
				`	end)`,
				`end)`,
				"",
			}, "\n")
			if fs.isDir(keep) then
				fs.removeDir(keep)
			end
			local code = nested("run-hand", body)
			t.expect(code).toBe(0)
			t.expect(fs.isDir(fx)).toBe(false)
			t.expect(fs.isFile(`{keep}/f.txt`)).toBe(true)
			fs.removeDir(keep)
		end
	)

	it("a spec that writes into git's template is named, the template is restored, and the run fails", function()
		local template = process.env.GIT_TEMPLATE_DIR or ""
		local body = table.concat({
			"--!strict",
			`local fs = {REQ}("@lune/fs")`,
			`local process = {REQ}("@lune/process")`,
			`local t = {REQ}("@tests/lib/t")`,
			`return t.spec("x", function(it)`,
			`	it("writes a hook into the template", function()`,
			'		fs.writeFile(process.env.GIT_TEMPLATE_DIR .. "/hooks/post-checkout", "x")',
			'		fs.writeFile(process.env.GIT_TEMPLATE_DIR .. "/description", "x")',
			`	end)`,
			`end)`,
			"",
		}, "\n")
		local code, output = nested("run-template", body)
		t.expect(code).toBe(1)
		t.expect(string.find(output, `git template changed: {template}/hooks/post-checkout`, 1, true) ~= nil).toBe(true)
		t.expect(string.find(output, `git template changed: {template}/description`, 1, true) ~= nil).toBe(true)
		t.expect(names(template)).toEqual({ "hooks", "info" })
		t.expect(names(`{template}/hooks`)).toEqual({})
	end)

	it(
		"each spec file of a concurrent run has a git template of its own: a write is blamed on its writer alone",
		function()
			local dir = `{BASE}/run-owns`
			if fs.isDir(dir) then
				fs.removeDir(dir)
			end
			local meet = `{dir}/meet`
			fs.writeDir(meet)
			-- a writes into its template, tells b, and stays until b has finished its own case; b waits for a's write and ends
			-- while a is still running: with one template for all workers, b's check would find a's hook and blame b
			local function body(writes: boolean): string
				local wait =
					"local function waitFor(path) for _ = 1, 100 do if fs.isFile(path) then return end task.wait(0.2) end end"
				return table.concat({
					"--!strict",
					`local fs = {REQ}("@lune/fs")`,
					`local process = {REQ}("@lune/process")`,
					`local task = {REQ}("@lune/task")`,
					`local t = {REQ}("@tests/lib/t")`,
					wait,
					`return t.spec("x", function(it)`,
					`	it("works", function()`,
					if writes
						then '		fs.writeFile(process.env.GIT_TEMPLATE_DIR .. "/hooks/post-checkout", "x")\n		fs.writeFile("'
							.. meet
							.. '/a-wrote", "")\n		waitFor("'
							.. meet
							.. '/b-done")'
						else '		waitFor("' .. meet .. '/a-wrote")\n		fs.writeFile("' .. meet .. '/b-done", "")',
					`	end)`,
					`end)`,
					"",
				}, "\n")
			end
			write(`{dir}/a.spec.luau`, body(true))
			write(`{dir}/b.spec.luau`, body(false))
			local r = process.exec("perl", {
				"-e",
				"alarm 60; exec @ARGV",
				"lune",
				"run",
				"tests/run",
				"--",
				"--jobs",
				"2",
				".cache/c0178-harness/run-owns/a.spec.luau",
				".cache/c0178-harness/run-owns/b.spec.luau",
			}, { cwd = HOME, env = { PICKMAN_JOBS = "", PICKMAN_WORKER = "", PICKMAN_TALLY = "" } })
			t.expect(r.code).toBe(1)
			t.expect(string.find(r.stdout, "run-owns/a.spec.luau: git template changed", 1, true) ~= nil).toBe(true)
			t.expect(string.find(r.stdout, "run-owns/b.spec.luau: git template changed", 1, true) == nil).toBe(true)
		end
	)

	it("the launcher prunes the images once, under the run's lock and before any spec starts", function()
		local text = fs.readFile(`{HOME}/tests/lib/fence.luau`)
		local calls = 0
		for _ in string.gmatch(text, "pruning%.run%(") do
			calls += 1
		end
		t.expect(calls).toBe(1)
		t.expect(string.find(text, "pruning.run(pruning.dir())", 1, true) ~= nil).toBe(true)
		t.expect(pruning.dir()).toBe(images.dir())
		local lock, prune, argv =
			string.find(text, "takeLock(lock)", 1, true),
			string.find(text, "pruning.run(", 1, true),
			string.find(text, "local argv = {", 1, true)
		t.expect(lock ~= nil and prune ~= nil and argv ~= nil and lock < prune and prune < argv).toBe(true)
	end)

	it("a worker of a concurrent run leaves the printing to its coordinator", function()
		local _, output = nested("run-worker", specBody(`{BASE}/run-worker/fx`, false), { PICKMAN_WORKER = "1" })
		t.expect(string.find(output, "fixtures:", 1, true) == nil).toBe(true)
	end)

	it("git's template is an empty hooks/ and an empty info/, and a spec's git init and git clone use it", function()
		local template = process.env.GIT_TEMPLATE_DIR or ""
		t.expect(template ~= "").toBe(true)
		t.expect(names(template)).toEqual({ "hooks", "info" })
		t.expect(names(`{template}/hooks`)).toEqual({})
		t.expect(names(`{template}/info`)).toEqual({})
		local dir = `{BASE}/template`
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(dir)
		must(process.exec("git", { "init", "-q", "-b", "main", `{dir}/made` }), "git init")
		t.expect(fs.isDir(`{dir}/made/.git/hooks`)).toBe(true)
		t.expect(names(`{dir}/made/.git/hooks`)).toEqual({})
		t.expect(fs.isDir(`{dir}/made/.git/info`)).toBe(true)
		t.expect(fs.isFile(`{dir}/made/.git/description`)).toBe(false)
		fixture.git(`{dir}/made`, {
			"-c",
			"user.name=c0178",
			"-c",
			"user.email=c0178@example.invalid",
			"commit",
			"-q",
			"--allow-empty",
			"-m",
			"x",
		})
		must(process.exec("git", { "clone", "-q", `{dir}/made`, `{dir}/cloned` }), "git clone")
		t.expect(names(`{dir}/cloned/.git/hooks`)).toEqual({})
		-- a spec that installs a hook writes into the folder, as the older specs do, with no mkdir
		fs.writeFile(`{dir}/made/.git/hooks/pre-push`, "#!/bin/sh\nexit 0\n")
		t.expect(fs.isFile(`{dir}/made/.git/hooks/pre-push`)).toBe(true)
	end)
end)
