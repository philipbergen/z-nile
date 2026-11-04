--!strict
-- c0165 AC10: the stop hook asks the selector which projects its changed paths force, then makes one affected gate call.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local dir = `{here}/.cache/c0165-stop-hook`

local function put(rel: string, text: string)
	fs.writeDir(string.match(`{dir}/{rel}`, "^(.*)/[^/]+$") :: string)
	fs.writeFile(`{dir}/{rel}`, text)
end

local function gateStub(fails: boolean)
	put(
		"scripts/check.sh",
		'#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$(dirname "$0")/../gate.log"\n'
			.. (if fails then "exit 7\n" else "exit 0\n")
	)
	process.exec("chmod", { "+x", `{dir}/scripts/check.sh` })
end

local function stop(): (boolean, number, string)
	local r = fixture.exec(
		dir,
		"bash",
		{ `{dir}/scripts/hooks/stop.sh` },
		{ stdin = '{"cwd": "' .. dir .. '"}' }
	)
	local log = `{dir}/gate.log`
	local calls = if fs.isFile(log) then fs.readFile(log) else ""
	if fs.isFile(log) then
		fs.removeFile(log)
	end
	return r.ok, r.code, calls
end

local function changes(paths: { string })
	for _, rel in paths do
		put(rel, "--!strict\nreturn 1\n")
	end
end

local function clean(paths: { string })
	for _, rel in paths do
		fs.removeFile(`{dir}/{rel}`)
	end
end

return t.spec("c0165 selector-scoped stop hook", function(it)
	it(
		"AC10: forced projects, old roots, combined changes and failures use one gate; old trees stay unscoped",
		function()
			if fs.isDir(dir) then
				fs.removeDir(dir)
			end
			fs.writeDir(dir)
			engine.copy(TOP, dir)
			gateStub(false)
			put("readme", "x\n")
			t.expect(process.exec("git", { "init", "-q", "-b", "main", dir }).ok).toBe(true)
			fixture.git(dir, { "config", "user.name", "c0165-stop" })
			fixture.git(dir, { "config", "user.email", "c0165-stop@example.invalid" })
			fixture.git(dir, { "add", "-A" })
			fixture.git(dir, { "commit", "-q", "-m", "base" })

			changes({ "z-nile/tests/lib/x.luau" })
			local ok, _, calls = stop()
			t.expect(ok).toBe(true)
			t.expect(calls).toBe("--project pickman --project z-nile --affected\n")
			clean({ "z-nile/tests/lib/x.luau" })

			changes({ "src/x.luau" })
			ok, _, calls = stop()
			t.expect(ok).toBe(true)
			t.expect(calls).toBe("--project z-nile --affected\n")
			clean({ "src/x.luau" })

			changes({ "pickman/src/shared/X.luau", "z-nile/engine/x.luau" })
			ok, _, calls = stop()
			t.expect(ok).toBe(true)
			t.expect(calls).toBe("--project pickman --project z-nile --affected\n")
			clean({ "pickman/src/shared/X.luau", "z-nile/engine/x.luau" })

			-- the helper's answer is used only when it can be: every other answer takes today's unscoped call
			local affectedPath, selectPath = `{dir}/z-nile/affected.luau`, `{dir}/z-nile/lib/select.luau`
			local origAffected, origSelect = fs.readFile(affectedPath), fs.readFile(selectPath)
			local exitOne = 'require("@lune/process").exit(1)\n'
			local function unscoped(why: string)
				changes({ "pickman/src/shared/X.luau", "z-nile/lib/x.luau" })
				local gateOk, _, gateCalls = stop()
				t.expect(gateOk).toBe(true)
				t.expect(`{why}: {gateCalls}`).toBe(`{why}: --affected\n`)
				clean({ "pickman/src/shared/X.luau", "z-nile/lib/x.luau" })
			end

			fs.removeFile(selectPath) -- a tree between c0114 and c0165: roots.luau, an old affected, no select.luau
			unscoped("middle-era tree")
			fs.writeFile(selectPath, origSelect)

			fs.writeFile(affectedPath, exitOne)
			unscoped("helper exits 1")
			fs.writeFile(affectedPath, 'print("ALL")\n')
			unscoped("helper prints ALL")
			fs.writeFile(affectedPath, 'print("pickman/tests/acceptance/c0002/place-rules.spec.luau")\n')
			unscoped("helper prints a spec path")
			fs.writeFile(affectedPath, "")
			unscoped("helper prints nothing")
			fs.writeFile(affectedPath, origAffected)

			fs.removeFile(`{dir}/z-nile/roots.luau`) -- before c0114
			unscoped("pre-c0114 tree")

			gateStub(true)
			changes({ "pickman/src/shared/X.luau" })
			local failOk, failCode, failCalls = stop()
			t.expect(failOk).toBe(false)
			t.expect(failCode).toBe(2)
			t.expect(failCalls).toBe("--affected\n")
			fs.removeDir(dir)
		end
	)
end)
