--!strict
-- c0120 AC12: CI follows the homes. A push touching only a project root (pickman/.tracker, z-nile/.tracker) or the
-- counter skips the deploy (c0172: deploy.yml carries the ignore list). deploy-beta builds a project's "$path"s
-- relative to the project file's own folder, and its step runs from pickman/. The stop hook gates pickman/ and
-- z-nile/ too. These specs run from z-nile/: the repository is read from its top. Fixtures under .cache/c0120-ci.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local wf = serde.decode("yaml", fs.readFile(`{TOP}/.github/workflows/deploy.yml`)) :: any

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function step(job: string, needle: string): any
	for _, s in wf.jobs[job].steps do
		if type(s.run) == "string" and has(s.run, needle) then
			return s
		end
	end
	error(`no {job} step runs {needle}`)
end

return t.spec("c0120 CI follows the homes", function(it)
	it("pushes touching only a project root or the counter skip the gate; tracker/ is not ignored", function()
		t.expect(wf["on"].push["paths-ignore"])
			.toEqual({ "pickman/.tracker/**", "z-nile/.tracker/**", "z-nile/next" })
	end)

	it("the deploy job publishes from pickman/, and sets up from the root", function()
		t.expect(step("deploy", "lune run scripts/deploy-beta")["working-directory"]).toBe("pickman")
		t.expect(step("deploy", "z-nile/setup.sh --tools")["working-directory"]).toBe(nil)
	end)

	it("deploy-beta builds a project's paths relative to the project file's folder", function()
		local text = fs.readFile(`{TOP}/pickman/scripts/deploy-beta.luau`)
		t.expect(has(text, 'local dir = string.match(source, "^(.*)/[^/]+$") or root')).toBe(true)
		t.expect(has(text, "pcall(Beta.project, fs.readFile(source), dir, target.attributes)")).toBe(true)
	end)

	it(
		"the stop hook gates a change in pickman/ or z-nile/, never one to a project root's documents alone",
		function()
			local root = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
			local dir = `{root}/.cache/c0120-ci-hook`
			if fs.isDir(dir) then
				fs.removeDir(dir)
			end
			fs.writeDir(dir)
			t.expect(process.exec("git", { "init", "-q", "-b", "main", dir }).ok).toBe(true)
			fixture.git(dir, { "config", "user.name", "c0120-ci" })
			fixture.git(dir, { "config", "user.email", "c0120-ci@example.invalid" })
			-- a stub gate at the path the hook calls, recording that it ran; the registry and its shell reader
			local function put(rel: string, text: string)
				fs.writeDir(string.match(`{dir}/{rel}`, "^(.*)/[^/]+$") :: string)
				fs.writeFile(`{dir}/{rel}`, text)
			end
			put("scripts/check.sh", '#!/usr/bin/env bash\necho "$@" >> "$(dirname "$0")/../gate.log"\n')
			process.exec("chmod", { "+x", `{dir}/scripts/check.sh` })
			for _, rel in { "z-nile/roots.luau", "z-nile/engine/projects.luau", "z-nile/projects.toml" } do
				put(rel, fs.readFile(`{TOP}/{rel}`))
			end
			put("readme", "x\n")
			fixture.git(dir, { "add", "-A" })
			fixture.git(dir, { "commit", "-q", "-m", "base" })
			local function gated(): boolean
				fixture.exec(
					dir,
					"bash",
					{ `{TOP}/scripts/hooks/stop.sh` },
					{ stdin = '{"cwd": "' .. dir .. '"}' }
				)
				local ran = fs.isFile(`{dir}/gate.log`)
				if ran then
					fs.removeFile(`{dir}/gate.log`)
				end
				return ran
			end
			put("pickman/.tracker/issues/f0001/f0001.md", "doc\n")
			t.expect(gated()).toBe(false) -- pickman's root alone: documents select no spec
			put("pickman/src/shared/X.luau", "--!strict\nreturn 1\n")
			t.expect(gated()).toBe(true) -- pickman's code: the gate runs
			fs.removeDir(`{dir}/pickman/src`)
			put("z-nile/lib/x.luau", "--!strict\nreturn 1\n")
			t.expect(gated()).toBe(true) -- the tooling's code: the gate runs
			fs.removeFile(`{dir}/z-nile/lib/x.luau`)
			put("z-nile/.tracker/issues/c0001/c0001.md", "doc\n")
			t.expect(gated()).toBe(false) -- z-nile's root alone
			put("src/x.luau", "--!strict\nreturn 1\n")
			t.expect(gated()).toBe(true) -- the old place: gated, and the old-roots check fails there
			fs.removeDir(`{dir}/src`)
			put("tests/x.luau", "--!strict\nreturn 1\n")
			t.expect(gated()).toBe(true) -- the root's old tests/: gated too
			fs.removeDir(dir)
		end
	)
end)
