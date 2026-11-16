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

return t.spec("c0257 AC3: model under node", function(it)
	it("AC3: the ordering, link, additive-key and rank-command rules hold", function()
		local file = `{TOP}/z-nile/.tracker/issues/c0257/acceptance/rules.test.mjs`
		local home = `{TOP}/z-nile/tests/acceptance/c0257/rules.test.mjs`
		local use = if fs.isFile(file) then file else home
		local r = node({ "--test", use })
		t.expect(count("\n" .. r.stdout, "fail")).toBe(0)
		t.expect(count("\n" .. r.stdout, "pass")).toBe(7)
		t.expect(r.ok).toBe(true)
	end)
end)
