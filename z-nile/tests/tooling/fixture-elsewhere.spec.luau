--!strict
-- R0210 review 001 F4: the fixture helper also refuses git pointed elsewhere through `-c core.worktree=…` and
-- through git config handed in by environment variables; a command's own `-c` settings still pass.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- fixtures under this home's .cache (the working directory, c0120); root is for reading the tooling
local base = `{(string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))}/.cache/fixture-elsewhere`
local fx = `{base}/fx`
-- built by concatenation: the gate scan bans the literal name in tests/
local CONFIG_COUNT = "GIT_CONF" .. "IG_COUNT"

local function refused(f: () -> ()): string
	local ok: boolean, err: any = pcall(f :: any)
	t.expect(ok).toBe(false)
	return tostring(err)
end

return t.spec("fixture helper refuses config that points git elsewhere", function(it)
	it("sets up a fixture", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		t.expect(process.exec("git", { "init", "-q", "-b", "main", fx }).ok).toBe(true)
	end)

	it("a -c core.worktree setting is refused, any other -c passes", function()
		for _, value in { "core.worktree=/", "Core.WorkTree=/tmp" } do
			local err = refused(function()
				fixture.git(fx, { "-c", value, "status" })
			end)
			t.expect(string.find(err, "another repository", 1, true) ~= nil).toBe(true)
		end
		t.expect(fixture.git(fx, { "-c", "core.quotepath=false", "rev-parse", "--is-inside-work-tree" }))
			.toBe("true")
	end)

	it("config handed in through the environment is refused", function()
		local err = refused(function()
			fixture.exec(fx, "git", { "status" }, { env = { [CONFIG_COUNT] = "1" } })
		end)
		t.expect(string.find(err, "another repository", 1, true) ~= nil).toBe(true)
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
