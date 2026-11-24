--!strict
-- f0437 step 6, slice 1: the markdown renderer of the app page (z-nile/app/live.js) against hostile and real-shaped text, in node:
-- a strict parser over the produced HTML (allowed elements, attributes and content model), the constructs, the hostile corpus
-- counted in steps, and the colour pairs checked for contrast in both themes. Node is the test's own tool, as for app-live.
local fixture = require("@tests/lib/fixture")
local nodecheck = require("@tests/lib/nodecheck")
local process = require("@lune/process")
local t = require("@tests/lib/t")

return t.spec("f0437 step 6: the markdown renderer", function(it)
	it("renders every construct, refuses every hostile one and meets contrast (node)", function()
		if not nodecheck.ok() then
			return
		end
		local home = fixture.physical(".") :: string
		local r = process.exec("node", { `{home}/tests/tooling/app-md.node.js`, `{home}/app` })
		if not r.ok then
			error(`app-md.node.js failed:\n{r.stdout}{r.stderr}`, 0)
		end
	end)

	-- review F9: three real tickets, frozen, come out of the renderer with their text word for word and their code blocks exact
	it("renders the frozen copy of three real tickets word for word, code blocks exact (node)", function()
		if not nodecheck.ok() then
			return
		end
		local home = fixture.physical(".") :: string
		local r = process.exec("node", {
			`{home}/tests/tooling/app-md-real.node.js`,
			`{home}/app`,
			`{home}/tests/fixtures/walk-real.served.json`,
		})
		if not r.ok then
			error(`app-md-real.node.js failed:\n{r.stdout}{r.stderr}`, 0)
		end
	end)

	-- f0437 slice 2: the same three real tickets with the real index: every id is a link or a marked unknown, counted, and no word changes
	it(
		"links the ids of the frozen real tickets against the frozen real index: the counts equal the oracle's and the frozen ones (node)",
		function()
			if not nodecheck.ok() then
				return
			end
			local home = fixture.physical(".") :: string
			local fx = `{home}/tests/fixtures`
			local r = process.exec("node", {
				`{home}/tests/tooling/app-md-real.node.js`,
				`{home}/app`,
				`{fx}/walk-real.served.json`,
				`--units={fx}/units-real.served.json`,
				`--themes={fx}/themes-real.served.json`,
				`--expect={fx}/units-real.expected.json`,
			})
			if not r.ok then
				error(`app-md-real.node.js with the index failed:\n{r.stdout}{r.stderr}`, 0)
			end
		end
	)
end)
