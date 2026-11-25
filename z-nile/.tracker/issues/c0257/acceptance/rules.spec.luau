--!strict
-- c0257 AC3: the rules of Model.js that the app's own tests leave unpinned or that this issue's Security section states,
-- run from rules.test.mjs beside this spec (found from this file's own path: the item moves to active/ and then to tests/).
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
-- ZN_C0257_TREE: a copy of the tree that holds z-nile-omarchy/ (prep proved these specs against the prototype that way)
local APP = `{process.env.ZN_C0257_TREE or TOP}/z-nile-omarchy/znile.board`
local HERE = string.match(debug.info(1, "s") :: string, "^(.*)/[^/]+$") or "."

local function count(out: string, key: string): number
	local found: string? = string.match("\n" .. out, "\n# " .. key .. " (%d+)")
	return if found then tonumber(found) :: number else -1
end

return t.spec("c0257 AC3: the model's rules", function(it)
	it(
		"AC3: reorder, paths, web base, stage, additive keys, clipping, session order, rank command, markdown, agents, PRs",
		function()
			local ok, r = pcall(
				process.exec,
				"node",
				{ "--test", "--test-reporter=tap", `{HERE}/rules.test.mjs` },
				{ env = { C0257_APP = APP } }
			)
			if not ok then
				error("node is required for c0257's model specs (SETUP.md): " .. tostring(r))
			end
			t.expect(count(r.stdout, "fail")).toBe(0)
			t.expect(count(r.stdout, "pass")).toBe(14)
			t.expect(r.ok).toBe(true)
		end
	)
end)
