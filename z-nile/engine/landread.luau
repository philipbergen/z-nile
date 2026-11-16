--!strict
-- c0252: the reads behind `./zn land-check` and `./zn done`'s pre-landing check: the top layer's pull request and the
-- paths main gained. Reads only (zz-arch: one edge); landcheck.luau judges what these return.
local landcheck = require("./landcheck")
local serde = require("@lune/serde")
local sh = require("../lib/sh")

local landread = {}

-- gh's `statusCheckRollup` and `pr view` JSON as a landcheck.Pr, or nil and why. Pure over the text: the edge below
-- runs gh. An entry with neither a conclusion nor a state is still running ("").
function landread.parsePr(text: string): (landcheck.Pr?, string?)
	local ok, j = pcall(function()
		return serde.decode("json", text)
	end)
	if not ok or type(j) ~= "table" then
		return nil, "gh's answer is not JSON"
	end
	local pr: any = j
	if type(pr.headRefOid) ~= "string" or pr.headRefOid == "" then
		return nil, "gh names no head commit"
	end
	local checks: { landcheck.Check } = {}
	if type(pr.statusCheckRollup) == "table" then
		for _, c in pr.statusCheckRollup :: { any } do
			local s = c.conclusion
			if type(s) ~= "string" or s == "" then
				s = c.state
			end
			table.insert(checks, {
				name = tostring(c.name or c.context or "check"),
				state = if type(s) == "string" then string.upper(s) else "",
			})
		end
	end
	return {
		state = tostring(pr.state or ""),
		draft = pr.isDraft == true,
		head = pr.headRefOid,
		mergeable = tostring(pr.mergeable or "UNKNOWN"),
		checks = checks,
	},
		nil
end

-- The pull request of a layer branch.
function landread.pr(branch: string): (landcheck.Pr?, string?)
	local r = sh.run("gh", {
		"pr",
		"view",
		branch,
		"--json",
		"state,isDraft,headRefOid,mergeable,statusCheckRollup",
	})
	if not r.ok then
		return nil, `gh pr view {branch} failed`
	end
	return landread.parsePr(r.stdout)
end

-- The paths named by `git diff --name-only a b`, or nil when git could not say.
function landread.diffNames(a: string, b: string): { string }?
	local r = sh.run("git", { "diff", "--name-only", "--no-renames", a, b })
	if not r.ok then
		return nil
	end
	local out: { string } = {}
	for line in string.gmatch(r.stdout .. "\n", "([^\n]*)\n") do
		if line ~= "" then
			table.insert(out, line)
		end
	end
	return out
end

return landread
