--!strict
-- c0249 AC7: the Omarchy board app orders tickets and rafts by the engine's rank (a set rank first, the lower first, the
-- ticket number as the tiebreak), ships rankCommand as `./zn rank {id} --before {beforeId}` so a drag persists on
-- origin/main, and drops its session order once a move is saved. Runs app.test.mjs beside this spec under node (found
-- from this file's own path: the item moves to active/ and then to tests/), over the checkout's z-nile-omarchy/ folder.
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local APP = `{TOP}/z-nile-omarchy/znile.board`
local HERE = string.match(debug.info(1, "s") :: string, "^(.*)/[^/]+$") or "."

local function count(out: string, key: string): number
	local found: string? = string.match("\n" .. out, "\n# " .. key .. " (%d+)")
	return if found then tonumber(found) :: number else -1
end

return t.spec("c0249 the Omarchy app follows the rank", function(it)
	it(
		"AC7: the shipped command, the rank order, a raft's effective rank, junk ranks and the session order",
		function()
			local ok, r = pcall(
				process.exec,
				"node",
				{ "--test", `{HERE}/app.test.mjs` },
				{ env = { C0249_APP = APP } }
			)
			if not ok then
				error("node is required for c0249's app specs (SETUP.md): " .. tostring(r))
			end
			if count(r.stdout, "fail") ~= 0 then
				error(r.stdout, 0)
			end
			t.expect(count(r.stdout, "fail")).toBe(0)
			t.expect(count(r.stdout, "pass")).toBe(6)
			t.expect(r.ok).toBe(true)
		end
	)
end)
