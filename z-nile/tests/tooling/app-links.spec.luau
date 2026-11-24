--!strict
-- f0437 step 6, slice 2: the page's id links, the detail view, the routing and the fetching, against a stub page in node
-- (tests/tooling/app-links.node.js). Node is the test's own tool, as for app-live and app-md.
local fixture = require("@tests/lib/fixture")
local process = require("@lune/process")
local t = require("@tests/lib/t")

return t.spec("f0437 step 6, slice 2: id links, the detail view, routing and fetching", function(it)
	it("links ids, shows the detail view, keeps the reader's place and fetches only what changed (node)", function()
		local which = process.exec("sh", { "-c", "command -v node" })
		if not which.ok then
			print("SKIPPED: node is not installed, so the page's tests did not run")
			return
		end
		local home = fixture.physical(".") :: string
		local r = process.exec("node", { `{home}/tests/tooling/app-links.node.js`, `{home}/app` })
		if not r.ok then
			error(`app-links.node.js failed:\n{r.stdout}{r.stderr}`, 0)
		end
	end)
end)
