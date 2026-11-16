--!strict
-- c0257 AC2, AC3: the app's pure model (Model.js) runs under node: its own tests pass, and so do prep's rule cases for
-- what those leave unpinned. Node is the toolchain's (SETUP.md: the full gate needs it, c0042's page smoke test).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
-- ZN_C0257_TREE: a copy of the tree that holds z-nile-omarchy/ (prep proved these specs against the prototype that way)
local APP = `{process.env.ZN_C0257_TREE or TOP}/z-nile-omarchy/znile.board`

local function node(args: { string }): process.ExecResult
	local ok, r = pcall(process.exec, "node", args, { env = { C0257_APP = APP } })
	if not ok then
		error("node is required for c0257's model specs (SETUP.md): " .. tostring(r))
	end
	return r :: any
end

local function count(out: string, key: string): number
	return tonumber(string.match(out, "\n# " .. key .. " (%d+)")) or -1
end

return t.spec("c0257 AC2: model under node", function(it)
	it("AC2: the model's own tests (normalize, blocking, sorting, PR matching, sanitizer, agent argv) pass", function()
		local file = `{APP}/tests/model.test.mjs`
		t.expect(fs.isFile(file)).toBe(true)
		local r = node({ "--test", file })
		t.expect(count("\n" .. r.stdout, "fail")).toBe(0)
		t.expect(count("\n" .. r.stdout, "pass") >= 12).toBe(true)
		t.expect(r.ok).toBe(true)
	end)
end)
