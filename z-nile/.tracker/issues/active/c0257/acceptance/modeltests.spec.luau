--!strict
-- c0257 AC2: the app's own tests for its pure model (Model.js) pass under node. Node is the toolchain's (SETUP.md: the full
-- gate needs it, c0042's page smoke test).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
-- ZN_C0257_TREE: a copy of the tree that holds z-nile-omarchy/ (prep proved these specs against the prototype that way)
local APP = `{process.env.ZN_C0257_TREE or TOP}/z-nile-omarchy/znile.board`

local function count(out: string, key: string): number
	local found: string? = string.match("\n" .. out, "\n# " .. key .. " (%d+)")
	return if found then tonumber(found) :: number else -1
end

return t.spec("c0257 AC2: the model's own tests under node", function(it)
	it("AC2: normalize, blocking, sorting, PR matching, sanitizer and agent argv tests pass", function()
		local file = `{APP}/tests/model.test.mjs`
		t.expect(fs.isFile(file)).toBe(true)
		local ok, r = pcall(process.exec, "node", { "--test", "--test-reporter=tap", file })
		if not ok then
			error("node is required for c0257's model specs (SETUP.md): " .. tostring(r))
		end
		t.expect(count(r.stdout, "fail")).toBe(0)
		t.expect(count(r.stdout, "pass") >= 12).toBe(true)
		t.expect(r.ok).toBe(true)
	end)
end)
