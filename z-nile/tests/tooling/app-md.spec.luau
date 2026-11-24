--!strict
-- f0437 step 6, slice 1: the markdown renderer of the app page (z-nile/app/live.js) against hostile and real-shaped text, in node:
-- a strict parser over the produced HTML (allowed elements, attributes and content model), the constructs, the hostile corpus
-- counted in steps, and the colour pairs checked for contrast in both themes. Node is the test's own tool, as for app-live.
local fixture = require("@tests/lib/fixture")
local process = require("@lune/process")
local t = require("@tests/lib/t")

return t.spec("f0437 step 6: the markdown renderer", function(it)
	it("renders every construct, refuses every hostile one and meets contrast (node)", function()
		local which = process.exec("sh", { "-c", "command -v node" })
		if not which.ok then
			print("SKIPPED: node is not installed, so the renderer's tests did not run")
			return
		end
		local home = fixture.physical(".") :: string
		local r = process.exec("node", { `{home}/tests/tooling/app-md.node.js`, `{home}/app` })
		if not r.ok then
			error(`app-md.node.js failed:\n{r.stdout}{r.stderr}`, 0)
		end
	end)
end)
