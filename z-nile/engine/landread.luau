--!strict
-- c0252: the reads behind `./zn land-check` and `./zn done`'s pre-landing check: the top layer's pull request and the
-- paths main gained. Reads only (zz-arch: one edge); landcheck.luau judges what these return.
local landcheck = require("./landcheck")
local serde = require("@lune/serde")
local sh = require("../lib/sh")
local trackerstate = require("./trackerstate")

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

-- The raw entries of `git diff-tree -r --raw --no-renames <a> <b>` (trackerstate's own input: a rename shows as a
-- delete and an add), or nil and why when git could not say.
function landread.rawEntries(a: string, b: string): ({ trackerstate.Entry }?, string?)
	local r = sh.run("git", { "diff-tree", "-r", "--raw", "--no-renames", a, b })
	if not r.ok then
		return nil, `git diff-tree {a} {b} failed`
	end
	return trackerstate.parseRaw(r.stdout)
end

-- Of the entries, the paths that are not tracker state: each entry is judged alone by trackerstate.judge against the
-- registry's roots, the one definition (an unregistered `foo/.tracker/x` and a file moved out of an item folder into
-- the engine are code; so is anything the rule refuses for another reason).
function landread.codePaths(entries: { trackerstate.Entry }, roots: { string }): { string }
	local out: { string } = {}
	for _, e in entries do
		if trackerstate.judge({ e }, roots, false) ~= nil then
			table.insert(out, e.path)
		end
	end
	return out
end

return landread
