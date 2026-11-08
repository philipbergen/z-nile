--!strict
-- c0262 AC5: "full force": the final review runs on the strongest model the CLI has. A checked proxy: the final mode is
-- the sharp tier, and the zz-review table of the repository's own .models.toml (the one table the final mode reads
-- until c0261's sharp tier names another) follows the review rule and ranks at least every other step on each CLI.
local dispatch = require("@znile/engine/dispatch")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

return t.spec("c0262 AC5 the final review runs on the strongest model", function(it)
	it("AC5: the final mode is the sharp tier, the review model of each CLI, and no other step outranks it", function()
		t.expect(((dispatch.REVIEW_MODES :: any).final or {}).tier).toBe("sharp")
		local cfg: any = serde.decode("toml", fs.readFile(`{TOP}/.models.toml`))
		local seen = 0
		for _, cli in { "claude", "grok", "agent" } do
			local review = cfg["zz-review"][cli]
			t.expect(review ~= nil).toBe(true)
			if cli == "grok" then
				t.expect(string.match(review.model, "^grok%-") ~= nil and review.effort == "xhigh").toBe(true)
			else
				t.expect(string.match(review.model, "^claude%-opus%-") ~= nil).toBe(true)
			end
			for step, tables in cfg do
				if type(tables) == "table" and step ~= "zz-review" and type(tables[cli]) == "table" then
					t.expect((tables[cli].rank :: number) <= (review.rank :: number)).toBe(true)
					seen += 1
				end
			end
		end
		t.expect(seen > 0).toBe(true)
	end)
end)
