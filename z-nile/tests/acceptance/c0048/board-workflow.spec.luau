--!strict
-- c0460, overridden by c0172: GitHub Actions no longer builds the board. The deploy workflow uploads nothing.
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

return t.spec("c0460 board workflow", function(it)
	it("deploy.yml uploads no artifact", function()
		local wf = serde.decode("yaml", fs.readFile(`{TOP}/.github/workflows/deploy.yml`))
		local upload = false
		for _, job in wf.jobs do
			for _, step in job.steps do
				if
					type(step.uses) == "string"
					and string.sub(step.uses, 1, #"actions/upload-artifact") == "actions/upload-artifact"
				then
					upload = true
				end
			end
		end
		t.expect(upload).toBe(false)
	end)
end)
